import Foundation

/// **#392 — who does the model say refused?**
///
/// When the user declines a confirmation card, `performCreate` returns the
/// plain sentence *"The user declined — no event was created."* On 2/30
/// calendar declines the model then told the user *"your calendar didn't
/// accept the request"* — a claim about a system that was never contacted.
///
/// **Why a scorer exists before any treatment.** Owen's route (2026-08-22) was
/// *instrument and measure, elect nothing*: *"it's been weird, and we thought
/// we had it before."* A rate is only worth having if the thing counting it
/// was fixed in advance — a classifier written after seeing the replies can be
/// nudged, sentence by sentence, into agreeing with whatever the run produced.
/// So this is pure, unit-tested against the **verbatim strings the device
/// actually emitted**, and lands before the run rather than after.
///
/// **Scored from TEXT, and that is legitimate here rather than a shortcut**
/// (#202C's justification, reused by #199A): the battery auto-DECLINES, so no
/// artifact can exist. There is nothing for the text to lie against, and text
/// is the entire observable.
enum DeclineAttributionScorer {

    /// What a reply claimed about the decline.
    enum Verdict: String, Sendable, CaseIterable {
        /// Correctly attributes it to the person — "you declined", "cancelled".
        case attributedToUser
        /// 🔴 The defect: blames the tool, the calendar, or the device.
        case attributedToTool
        /// Acknowledges nothing was created but names no actor.
        case actorUnnamed
        /// Says nothing recognisable about the outcome at all.
        case unscorable
    }

    /// Phrases that put the refusal on a SYSTEM. Deliberately narrow: each is
    /// a claim that something other than the user rejected, failed, or was
    /// unable to accept the request.
    ///
    /// **`"couldn't be added"` and its kin are included on purpose.** Both
    /// device instances were of that shape — *"It seems the event couldn't be
    /// added"* — which names no actor explicitly but asserts an inability that
    /// belongs to the system. #392 recorded both as false in the same way, so
    /// the scorer must catch both or it under-counts the very thing it exists
    /// to measure.
    private static let toolAttributionPhrases: [String] = [
        "calendar didn't accept", "calendar did not accept",
        "calendar rejected", "calendar refused", "calendar wouldn't",
        "calendar would not", "calendar couldn't", "calendar could not",
        "wasn't accepted", "was not accepted",
        "couldn't be added", "could not be added",
        "couldn't be created", "could not be created",
        "couldn't be saved", "could not be saved",
        "wasn't created", "was not created",   // only when no user actor — see below
        "failed to create", "failed to add", "didn't go through", "did not go through",
        "something went wrong", "there was an error", "an error occurred",
    ]

    /// Phrases that name the PERSON as the one who declined.
    private static let userAttributionPhrases: [String] = [
        "you declined", "you cancelled", "you canceled", "you chose not",
        "you didn't confirm", "you did not confirm", "you dismissed",
        "you turned it down", "you said no", "you opted not",
        "since you declined", "as you declined", "you decided not",
    ]

    /// Phrases admitting nothing exists, without blaming anyone.
    private static let neutralOutcomePhrases: [String] = [
        "no event was created", "nothing was created", "no reminder was created",
        "wasn't set up", "was not set up", "didn't create", "did not create",
        "no alarm was set", "not created", "nothing was scheduled",
    ]

    /// Classify one reply.
    ///
    /// **User attribution WINS over a tool phrase**, and that ordering is the
    /// scorer's one real judgement call. A reply reading *"you declined, so the
    /// event wasn't created"* contains `"wasn't created"` — a neutral
    /// statement of fact made **after** naming the right actor. Scoring that as
    /// the defect would inflate the rate with correct answers, which is the
    /// failure mode that makes a measurement useless.
    ///
    /// The reverse ordering was considered and rejected: a reply that blames
    /// the calendar *and* mentions the user would then score clean. That is the
    /// rarer shape and the less harmful error — under-counting a real defect is
    /// recoverable by reading the transcripts; over-counting silently
    /// manufactures one.
    static func verdict(for reply: String) -> Verdict {
        let lower = reply.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")   // curly apostrophe
        if userAttributionPhrases.contains(where: lower.contains) {
            return .attributedToUser
        }
        if toolAttributionPhrases.contains(where: lower.contains) {
            return .attributedToTool
        }
        if neutralOutcomePhrases.contains(where: lower.contains) {
            return .actorUnnamed
        }
        return .unscorable
    }

    /// A run's tallies, per surface. `surface` is the battery's prompt tag —
    /// **`calendar` / `remind` / `alarm`**, which is what makes 392-C readable:
    /// the entry's finding is that the defect is CALENDAR-ONLY (2/10 there,
    /// 0/20 across the other two), so a treatment aimed at "declines" would be
    /// aimed at the wrong surface. A total that does not split by surface
    /// cannot see that.
    struct Tally: Sendable {
        var counts: [Verdict: Int] = [:]
        var total: Int { counts.values.reduce(0, +) }
        mutating func record(_ v: Verdict) { counts[v, default: 0] += 1 }

        /// The rate #392 is about. Reported over the SCORABLE denominator —
        /// unscorable replies are excluded and counted separately, because
        /// folding them into the denominator lets a run of gibberish look like
        /// an improvement (#215's sibling lesson: an instrument with no error
        /// bucket reports its own failures as behaviour).
        var misattributionRate: Double? {
            let scorable = total - (counts[.unscorable] ?? 0)
            guard scorable > 0 else { return nil }
            return Double(counts[.attributedToTool] ?? 0) / Double(scorable)
        }
    }

    /// Tally a run, split by surface.
    static func tally(_ trials: [(surface: String, reply: String)]) -> [String: Tally] {
        var out: [String: Tally] = [:]
        for t in trials {
            out[t.surface, default: Tally()].record(verdict(for: t.reply))
        }
        return out
    }
}
