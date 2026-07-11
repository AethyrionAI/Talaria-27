import Foundation
import os

/// Composes the priming turn that transplants a conversation's context into a
/// fresh Hermes session at a brain hop (P1 continuity fabric, OPEN_ITEMS #90).
///
/// The #89 probe validated the MECHANISM: a condensed ~10:1 priming turn read
/// as continuous context (recall, cross-turn inference, mid-stream correction)
/// indistinguishably from the original session. The residual risk is condenser
/// fidelity — preserving corrected values at their LATEST value and pruning
/// distractors — which is why the on-device condensation path is covered by
/// the CondenserFidelityTests acceptance suite.
///
/// Two paths, both budget-enforced:
/// - **Condensed (preferred):** `LocalIntelligenceService.condensedContextBrief`
///   distills the journal into declarative facts on-device.
/// - **Verbatim tail (fallback):** when the on-device model is unavailable or
///   declines, the newest turns ship verbatim within budget behind an honest
///   omission marker — degraded recall depth, but never fabricated
///   condensation (real-data-only).
@MainActor
final class ContextTransplanter {
    private static let logger = Logger(subsystem: "org.aethyrion.talaria", category: "ContextTransplanter")

    /// What `composePriming` produced: the wire-ready priming text plus how it
    /// was made, so callers can log/surface the path honestly.
    struct PrimingComposition: Sendable {
        let text: String
        /// True when the on-device model condensed the journal; false for the
        /// verbatim-tail fallback.
        let condensedByModel: Bool
        /// Journal entries the composition drew from.
        let entryCount: Int
    }

    /// Token budget for the whole priming turn. The priming rides the SERVER
    /// model (large windows), so this bounds cost and pruning discipline, not
    /// fit: ~10:1 against a typical mobile session, per the #89 probe's
    /// validated ratio.
    static let primingTokenBudget = 1500

    /// Per-entry cap in the verbatim-tail fallback — the same order of
    /// magnitude as LocalChatBackend.condensedPerTurnTokens, so one giant
    /// reply can't crowd every other turn out of the tail.
    static let fallbackPerEntryTokens = 160

    private let intelligence: LocalIntelligenceService

    init(intelligence: LocalIntelligenceService) {
        self.intelligence = intelligence
    }

    /// Composes the priming turn for a fresh hop from the journal's entries.
    /// Never throws and never returns empty text for a non-empty journal —
    /// the fallback always produces something honest.
    func composePriming(
        from entries: [ConversationJournal.Entry],
        tokenBudget: Int = ContextTransplanter.primingTokenBudget
    ) async -> PrimingComposition {
        if let brief = await intelligence.condensedContextBrief(
            transcript: await modelInputTranscript(from: entries)
        ) {
            var text = Self.primingText(body: brief)
            // Budget enforcement is an invariant, not a hope. The trim cuts
            // from the fact list's tail — a safety net that should rarely
            // fire (the condenser is instructed to be brief, and the budget
            // is generous against a facts list).
            if await intelligence.measuredTokenCount(of: text) > tokenBudget {
                text = await intelligence.trimmed(text, toTokenBudget: tokenBudget)
            }
            return PrimingComposition(text: text, condensedByModel: true, entryCount: entries.count)
        }

        Self.logger.notice("composePriming: on-device condenser unavailable/declined — using verbatim-tail fallback")
        return await fallbackPriming(from: entries, tokenBudget: tokenBudget)
    }

    /// The verbatim-tail fallback: the newest turns, per-entry capped, behind
    /// an honest omission marker, with the WHOLE priming text (preamble
    /// included) measured against the budget. No pruning happens here — the
    /// fallback carries whatever fits, newest first, because deterministic
    /// code cannot judge relevance (real-data-only; the condensation rules
    /// live in the model path).
    ///
    /// Internal (not private) so CondenserFidelityTests can exercise this
    /// path directly even on machines where the on-device model is available.
    func fallbackPriming(
        from entries: [ConversationJournal.Entry],
        tokenBudget: Int
    ) async -> PrimingComposition {
        var lines: [String] = []
        for entry in entries {
            let capped = await intelligence.trimmed(entry.text, toTokenBudget: Self.fallbackPerEntryTokens)
            lines.append(Self.renderedLine(role: entry.role, text: capped))
        }

        func measuredPriming(droppingOldest dropCount: Int) async -> (text: String, tokens: Int) {
            let text = Self.primingText(body: Self.renderedBody(lines: Array(lines[dropCount...]), omittedCount: dropCount))
            return (text, await intelligence.measuredTokenCount(of: text))
        }

        // Token counts aren't additive across joined lines (separators, the
        // omission marker, the preamble), so the fit check measures the FULL
        // priming text. Fit is monotone in how many oldest lines are dropped
        // — binary-search the smallest drop that fits instead of re-measuring
        // per line.
        var low = 0
        var high = max(lines.count - 1, 0)
        if await measuredPriming(droppingOldest: low).tokens > tokenBudget {
            while low < high {
                let mid = (low + high) / 2
                if await measuredPriming(droppingOldest: mid).tokens <= tokenBudget {
                    high = mid
                } else {
                    low = mid + 1
                }
            }
        }

        var (text, tokens) = await measuredPriming(droppingOldest: low)
        // The fit is monotone-in-practice, but the omission marker's own
        // tokens can wobble the boundary by a line — walk forward to certainty.
        while tokens > tokenBudget, low + 1 < lines.count {
            low += 1
            (text, tokens) = await measuredPriming(droppingOldest: low)
        }
        if tokens > tokenBudget, !lines.isEmpty {
            // Even the newest line alone busts the budget — it still ships,
            // cut to fit AROUND the preamble's own cost, because priming with
            // nothing is worse. This is the one case where the trim direction
            // (tail) is acceptable: there is only one turn left to cut. The
            // ratchet re-measures the whole text — token counts aren't
            // additive, so a single computed trim can land a hair over.
            let overhead = await intelligence.measuredTokenCount(
                of: Self.primingText(body: Self.renderedBody(lines: [], omittedCount: lines.count - 1))
            )
            var room = max(32, tokenBudget - overhead)
            for _ in 0 ..< 3 {
                let newest = await intelligence.trimmed(lines[lines.count - 1], toTokenBudget: room)
                text = Self.primingText(body: Self.renderedBody(lines: [newest], omittedCount: lines.count - 1))
                if await intelligence.measuredTokenCount(of: text) <= tokenBudget { break }
                room = max(32, room * 3 / 4)
            }
        }
        return PrimingComposition(text: text, condensedByModel: false, entryCount: entries.count)
    }

    /// Renders the journal for the on-device condenser, keeping the NEWEST
    /// turns when the transcript outgrows the model's input budget: recency
    /// carries the corrections, and a prefix-side trim would cut exactly the
    /// wrong end. Dropped older turns are marked honestly.
    private func modelInputTranscript(from entries: [ConversationJournal.Entry]) async -> String {
        let inputBudget = intelligence.promptInputBudget
        var lines = entries.map { Self.renderedLine(role: $0.role, text: $0.text) }

        func measured(droppingOldest dropCount: Int) async -> Int {
            await intelligence.measuredTokenCount(
                of: Self.renderedBody(lines: Array(lines[dropCount...]), omittedCount: dropCount)
            )
        }

        var low = 0
        var high = max(lines.count - 1, 0)
        if await measured(droppingOldest: low) > inputBudget {
            while low < high {
                let mid = (low + high) / 2
                if await measured(droppingOldest: mid) <= inputBudget {
                    high = mid
                } else {
                    low = mid + 1
                }
            }
        }
        if low == lines.count - 1, await measured(droppingOldest: low) > inputBudget {
            // A single monster turn: cap it rather than fail the condenser.
            lines[lines.count - 1] = await intelligence.trimmed(lines[lines.count - 1], toTokenBudget: inputBudget / 2)
        }
        return Self.renderedBody(lines: Array(lines[low...]), omittedCount: low)
    }

    // MARK: - Pure formatting (unit-tested)

    nonisolated static func renderedLine(role: ConversationJournal.Entry.Role, text: String) -> String {
        "\(role == .user ? "User" : "Hermes"): \(text)"
    }

    /// Chronological body with the honest omission marker when older turns
    /// fell off the budget.
    nonisolated static func renderedBody(lines: [String], omittedCount: Int) -> String {
        let body = lines.joined(separator: "\n")
        guard omittedCount > 0 else { return body }
        return "(\(omittedCount) earlier turn\(omittedCount == 1 ? "" : "s") omitted — context begins mid-conversation)\n" + body
    }

    /// The wire shape of the priming turn. The preamble tells the fresh
    /// session what the payload is (established conversation memory, facts at
    /// their latest corrected values) and pins the acknowledgment short, so
    /// the priming exchange costs little output and never reads as a question
    /// to answer.
    nonisolated static func primingText(body: String) -> String {
        """
        [CONTEXT TRANSPLANT — this is turn zero of a continued conversation.]
        The notes below carry the context of this conversation so far, from the user's device journal. Treat them as established conversation memory: every fact is already stated at its most recent corrected value. Do not re-answer or re-open anything below. Acknowledge in one short sentence and wait for the user's next message.

        \(body)
        """
    }
}
