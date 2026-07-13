import Foundation
import FoundationModels
import os

/// On-device intelligence via Apple's FoundationModels framework (#4.8):
/// conversation titles + previews after the first completed exchange, and
/// one-line condensation of the agent's reasoning channel (#4.15). Everything
/// runs locally — no Hermes dependency, works offline, nothing leaves the
/// device.
///
/// When the system model is unavailable (device not eligible, Apple
/// Intelligence off, model still downloading) every entry point degrades to a
/// deterministic truncation fallback, so callers always get a usable result.
@MainActor
final class LocalIntelligenceService {
    private static let logger = Logger(subsystem: "org.aethyrion.talaria", category: "LocalIntelligence")

    struct ConversationCard: Equatable, Sendable {
        let title: String
        let preview: String
    }

    /// Guided-generation shape for the title + preview call (#4.8).
    // fileprivate, not private: the @Generable macro expansion emits code
    // that cannot see a private nested type.
    @Generable
    fileprivate struct GeneratedCard {
        @Guide(description: "Title for the conversation: 2 to 6 plain-text words, no quotes, no trailing punctuation.")
        var title: String
        @Guide(description: "One sentence, at most 90 characters, saying what the conversation is about.")
        var preview: String
    }

    private var model: SystemLanguageModel { SystemLanguageModel.default }

    /// Bounded generation for every call site in this service (#102's
    /// thermal guardrail applied to the three sites the #61/#102 source read
    /// flagged): with `maximumResponseTokens` unset, a degenerate generation
    /// may run until the context window fills (verified against the iOS 27
    /// docs 2026-07-12). The caps are ~5× a healthy output; hitting one
    /// terminates early with NO error, and each caller already degrades
    /// honestly — the card guard / `condensedLine` for the single-line
    /// generators, and a decode failure → nil → verbatim-tail fallback for
    /// the context brief. Sampling and temperature are intentionally
    /// unchanged — the #61 guard logs will say whether a retune is
    /// warranted.
    nonisolated static let cardGenerationOptions = GenerationOptions(temperature: 0.3, maximumResponseTokens: 256)
    nonisolated static let reasoningGenerationOptions = GenerationOptions(temperature: 0.3, maximumResponseTokens: 128)
    nonisolated static let contextBriefGenerationOptions = GenerationOptions(temperature: 0.2, maximumResponseTokens: 1024)

    var isModelAvailable: Bool {
        if case .available = model.availability { return true }
        return false
    }

    // MARK: - Title + preview (#4.8)

    /// Generates `{title, preview}` from the conversation's first completed
    /// exchange. Never throws: any failure (model unavailable, guardrail
    /// veto, context overflow) falls back to deterministic truncation of the
    /// inputs, so the caller always gets a real card.
    func conversationCard(userText: String, assistantText: String) async -> ConversationCard {
        guard isModelAvailable else {
            return fallbackCardLoggingDegeneracy(userText: userText, assistantText: assistantText)
        }

        // Budget the inputs against the shared context headroom, split
        // user ⅓ / assistant ⅔ (the reply usually carries more of what the
        // conversation is about).
        let inputBudget = promptInputBudget
        let user = await trimmed(userText, toTokenBudget: inputBudget / 3)
        let assistant = await trimmed(assistantText, toTokenBudget: inputBudget - inputBudget / 3)

        let session = LanguageModelSession(instructions: """
            You label conversations between a user and an AI assistant named Hermes. \
            Given the first exchange, produce a short title and a one-line preview. \
            Describe the topic itself; never mention "conversation", "user", or "assistant".
            """)
        do {
            let response = try await session.respond(
                to: """
                USER:
                \(user)

                HERMES:
                \(assistant)
                """,
                generating: GeneratedCard.self,
                options: Self.cardGenerationOptions
            )
            let title = Self.condensedLine(response.content.title, limit: 48)
            let preview = Self.condensedLine(response.content.preview, limit: 90)
            // #61: a degenerate generated card (repetition, or title ≈
            // preview) is discarded for the known-good truncation shape. The
            // log names the PATH (guided) and the guard that tripped — the
            // device symptom never said which path misbehaved.
            if let reason = Self.degenerateCardReason(title: title, preview: preview) {
                Self.logger.notice("conversationCard: guided card degenerate — \(reason, privacy: .public); using truncation fallback (#61)")
                return fallbackCardLoggingDegeneracy(userText: userText, assistantText: assistantText)
            }
            // Fallback is computed only on the branches that need it — the
            // happy path shouldn't pay for line scans it throws away.
            if !title.isEmpty, !preview.isEmpty {
                return ConversationCard(title: title, preview: preview)
            }
            let fallback = fallbackCardLoggingDegeneracy(userText: userText, assistantText: assistantText)
            guard !title.isEmpty else { return fallback }
            // The mixed card pairs a generated title with the fallback
            // preview — a generated title that merely echoes the reply's
            // first line would slip an identical pair past the guard above
            // (the generated preview was empty, so there was nothing to
            // compare yet).
            if let reason = Self.degenerateCardReason(title: title, preview: fallback.preview) {
                Self.logger.notice("conversationCard: mixed card degenerate — \(reason, privacy: .public); using truncation fallback (#61)")
                return fallback
            }
            return ConversationCard(title: title, preview: fallback.preview)
        } catch {
            Self.logger.notice("conversationCard: generation failed — \(error.localizedDescription, privacy: .public); using truncation fallback")
            return fallbackCardLoggingDegeneracy(userText: userText, assistantText: assistantText)
        }
    }

    /// #61: the fallback card is always returned — it is the last resort and
    /// its SHAPE is known-good — but when even its content shows repetition,
    /// the exchange text itself is degenerate (e.g. a #102 phrase-looped
    /// reply became the preview). Logging that closes the guided-vs-fallback
    /// question the device symptom left open. Containment is deliberately
    /// not checked here: fallback title and preview legitimately derive from
    /// the same line on attachment-only turns.
    private func fallbackCardLoggingDegeneracy(userText: String, assistantText: String) -> ConversationCard {
        let card = Self.fallbackCard(userText: userText, assistantText: assistantText)
        if let unit = Self.repeatedRunUnit(in: card.title) ?? Self.repeatedRunUnit(in: card.preview) {
            Self.logger.notice("conversationCard: FALLBACK card carries repetition (\"\(unit, privacy: .public)\") — the exchange text itself is degenerate (#61/#102)")
        }
        return card
    }

    // MARK: - Reasoning condensation (#4.15)

    /// Condenses a reasoning transcript into one short line — what the model
    /// was working out. Nil when the on-device model is unavailable or
    /// generation fails; callers fall back to the last raw reasoning line.
    func condensedReasoning(_ reasoning: String) async -> String? {
        let trimmedInput = reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty, isModelAvailable else { return nil }

        let input = await trimmed(trimmedInput, toTokenBudget: promptInputBudget)

        let session = LanguageModelSession(instructions: """
            You condense an AI assistant's private reasoning transcript into one \
            short line of at most nine words describing what it worked out. Plain \
            text only — no quotes, no trailing punctuation.
            """)
        do {
            let response = try await session.respond(
                to: """
                REASONING TRANSCRIPT:
                \(input)
                """,
                options: Self.reasoningGenerationOptions
            )
            let line = Self.condensedLine(response.content, limit: 72)
            return line.isEmpty ? nil : line
        } catch {
            Self.logger.notice("condensedReasoning: generation failed — \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Context transplant condensation (P1 / OPEN_ITEMS #90)

    /// Guided-generation shape for the context brief. An array of short
    /// declarative facts keeps the output structured enough to format and
    /// budget deterministically.
    // fileprivate, not private: the @Generable macro expansion emits code
    // that cannot see a private nested type.
    @Generable
    fileprivate struct GeneratedContextBrief {
        @Guide(description: "The conversation's essential facts, goals, decisions, and outcomes, each as one short declarative sentence. State every fact at its FINAL value after any corrections — never include a superseded value. Exclude small talk, tangents, and one-off trivia the conversation never built on.")
        var facts: [String]
    }

    /// Condenses a rendered conversation transcript into the declarative
    /// context brief a fresh Hermes session is primed with at a brain hop
    /// (P1). This is the condenser whose fidelity the #89 probe flagged as
    /// the residual risk — CondenserFidelityTests is its guardrail:
    /// corrections must survive at their LATEST value, distractors must be
    /// pruned, and the result must fit the priming budget.
    ///
    /// Nil when the on-device model is unavailable or generation fails;
    /// `ContextTransplanter` then falls back to a verbatim recent tail —
    /// honest degradation, never fabricated condensation.
    func condensedContextBrief(transcript: String) async -> String? {
        let trimmedInput = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty, isModelAvailable else { return nil }

        // Safety net only — the transplanter pre-fits the transcript keeping
        // the NEWEST turns (this prefix-side trim would cut the wrong end).
        let input = await trimmed(trimmedInput, toTokenBudget: promptInputBudget)

        let session = LanguageModelSession(instructions: """
            You condense a conversation between a user and an AI assistant named \
            Hermes into a compact context brief, so a fresh assistant instance \
            can continue the conversation seamlessly. Extract only what matters \
            to continuing: facts, goals, decisions, preferences, and outcomes. \
            Two hard rules. One: when a value was corrected or changed during \
            the conversation, keep ONLY the final corrected value — repeating a \
            superseded value is worse than omitting the fact. Two: omit small \
            talk, tangents, and one-off trivia the conversation never built on \
            — every carried fact costs the user tokens.
            """)
        do {
            let response = try await session.respond(
                to: """
                CONVERSATION TRANSCRIPT:
                \(input)
                """,
                generating: GeneratedContextBrief.self,
                options: Self.contextBriefGenerationOptions
            )
            let facts = response.content.facts
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !facts.isEmpty else { return nil }
            return facts.map { "- \($0)" }.joined(separator: "\n")
        } catch {
            Self.logger.notice("condensedContextBrief: generation failed — \(error.localizedDescription, privacy: .public); caller falls back to verbatim tail")
            return nil
        }
    }

    // MARK: - Context budgeting (#4.8)

    /// Prompt-input token budget: the on-device context window (8192 tokens
    /// on iOS 27 hardware — read live, never hardcoded) minus headroom for
    /// instructions + output.
    ///
    /// Internal (not private) since P1: `ContextTransplanter` pre-fits the
    /// condenser's transcript input against this budget, keeping the newest
    /// turns — `trimmed(_:toTokenBudget:)` cuts from the tail, which is the
    /// wrong end for a conversation.
    var promptInputBudget: Int { max(512, model.contextSize - 1024) }

    /// Trims `text` to roughly `budget` tokens, measured with the model's own
    /// tokenizer where available (`tokenCount(for:)`, iOS 26.4+) and a
    /// conservative chars/3 estimate otherwise. Proportional cuts re-measured
    /// over up to three passes, so a pathological tokenization can't overshoot
    /// the context window.
    ///
    /// Internal (not private) since #26: `LocalChatBackend` reuses this and
    /// `measuredTokenCount(of:)` for its context-window condensation, so the
    /// tokenizer-facing surface stays in exactly one place.
    func trimmed(_ text: String, toTokenBudget budget: Int) async -> String {
        // Every token is at least one UTF-8 byte, so a byte count inside the
        // budget can never overflow it — skip the tokenizer round trip for
        // the common short-exchange case.
        guard text.utf8.count > budget else { return text }
        var candidate = text
        for _ in 0 ..< 3 {
            let tokens = await measuredTokenCount(of: candidate)
            if tokens <= budget { return candidate }
            let ratio = Double(budget) / Double(tokens) * 0.9
            let cut = max(64, Int(Double(candidate.count) * ratio))
            candidate = String(candidate.prefix(cut))
        }
        return candidate
    }

    func measuredTokenCount(of text: String) async -> Int {
        if #available(iOS 26.4, *) {
            // `tokenCount(for:)` takes Instructions, not Prompt (verified
            // against the SDK docs 2026-07-07) — either wraps the same text,
            // and the count is what matters here.
            if let count = try? await model.tokenCount(for: Instructions("\(text)")) {
                return count
            }
        }
        // ~3 chars per token deliberately underestimates the budget room —
        // it can waste input, never overflow the context.
        return max(1, text.count / 3)
    }

    // MARK: - Degenerate-card guard (#61)

    /// The shortest run treated as card repetition. Below it, doubled words
    /// and hyphenated refrains ("cha-cha-cha") are ordinary language.
    private nonisolated static let cardRepetitionMinimumUnitLength = 4
    /// Full copies of the unit a SHORT run must contain. A run at least
    /// `cardTwoCopyRunLength` long is degenerate with just two full copies
    /// plus a matching partial — no healthy 40-character line says the same
    /// thing twice verbatim, and the 90-character preview can only hold two
    /// copies of the longer looped phrases #61 produces.
    private nonisolated static let cardRepetitionMinimumRepeats = 3
    private nonisolated static let cardTwoCopyRunLength = 40
    /// Texts shorter than this are never judged repetitive.
    private nonisolated static let cardRepetitionMinimumLength = 12
    /// Containment only counts as near-identical when the shorter side is at
    /// least this long — a 2-word title echoed inside a longer preview is
    /// normal phrasing, not degeneracy.
    private nonisolated static let cardContainmentMinimumLength = 12
    /// A verbatim ≥24-character title echoed as the preview's PREFIX is
    /// either lazy generation or two truncations of the same degenerate run
    /// (the shape units longer than ~45 characters take, which the
    /// repetition scan structurally cannot see in a 90-character field).
    private nonisolated static let cardPrefixEchoMinimumLength = 24

    /// Why a generated card must be discarded — nil when the card is healthy.
    /// The returned reason is a short log-stable tag: repetition in either
    /// field, or title ≈ preview (fold-identical, one contained in the other
    /// while covering at least half of it, or a long verbatim prefix echo —
    /// the shapes two truncations of the same degenerate run take).
    nonisolated static func degenerateCardReason(title: String, preview: String) -> String? {
        if let unit = repeatedRunUnit(in: title) {
            return "title repeats \"\(unit)\""
        }
        if let unit = repeatedRunUnit(in: preview) {
            return "preview repeats \"\(unit)\""
        }
        let foldedTitle = cardComparisonFold(title)
        let foldedPreview = cardComparisonFold(preview)
        guard !foldedTitle.isEmpty, !foldedPreview.isEmpty else { return nil }
        if foldedTitle == foldedPreview { return "title and preview identical" }
        let (shorter, longer) = foldedTitle.count <= foldedPreview.count
            ? (foldedTitle, foldedPreview)
            : (foldedPreview, foldedTitle)
        if shorter.count >= cardContainmentMinimumLength,
           shorter.count * 2 >= longer.count,
           longer.contains(shorter) {
            return "title and preview near-identical (containment)"
        }
        if shorter.count >= cardPrefixEchoMinimumLength, longer.hasPrefix(shorter) {
            return "title and preview near-identical (prefix echo)"
        }
        return nil
    }

    /// The repeating unit when the (folded) text ends in one short run
    /// repeated to the cut — the shape a degenerate generation takes after
    /// `condensedLine` truncation ("phrase phrase phrase phr…", with or
    /// without a healthy preamble). End-reaching and truncation-tolerant (a
    /// partial final copy still matches); the run must dominate at least
    /// half the field so a trailing flourish never condemns a healthy line.
    /// Nil for healthy text.
    nonisolated static func repeatedRunUnit(in text: String) -> String? {
        let chars = Array(cardComparisonFold(text))
        let count = chars.count
        guard count >= cardRepetitionMinimumLength else { return nil }
        var start = 0
        while (count - start) * 2 >= count {
            if let unit = repeatedRun(startingAt: start, in: chars) {
                return unit
            }
            start += 1
        }
        return nil
    }

    /// The repeating unit covering `chars[start...]` entirely (with a
    /// partial final copy allowed), nil when that suffix is not one run.
    private nonisolated static func repeatedRun(startingAt start: Int, in chars: [Character]) -> String? {
        let length = chars.count - start
        guard length >= cardRepetitionMinimumLength else { return nil }
        var unitLength = cardRepetitionMinimumUnitLength
        while unitLength * 2 <= length {
            var covered = true
            var index = start + unitLength
            while index < chars.count {
                if chars[index] != chars[start + (index - start) % unitLength] {
                    covered = false
                    break
                }
                index += 1
            }
            if covered {
                let fullCopies = length / unitLength
                if fullCopies >= 2,
                   fullCopies >= cardRepetitionMinimumRepeats || length >= cardTwoCopyRunLength,
                   cardUnitQualifies(chars, unitStart: start, unitLength: unitLength) {
                    return String(chars[start ..< start + unitLength])
                }
            }
            unitLength += 1
        }
        return nil
    }

    /// Same qualification rules as the chat breaker's: the unit must carry
    /// words, and must not itself be a shorter loop (so "ha ha ha ha" is
    /// judged at its below-minimum 3-character fundamental period, never at
    /// a 6-character multiple).
    private nonisolated static func cardUnitQualifies(_ chars: [Character], unitStart: Int, unitLength: Int) -> Bool {
        var hasWordCharacter = false
        for index in unitStart ..< (unitStart + unitLength) where chars[index].isLetter || chars[index].isNumber {
            hasWordCharacter = true
            break
        }
        guard hasWordCharacter else { return false }
        for period in 1 ..< unitLength where unitLength % period == 0 {
            var matchesPeriod = true
            for index in (unitStart + period) ..< (unitStart + unitLength) {
                if chars[index] != chars[index - period] {
                    matchesPeriod = false
                    break
                }
            }
            if matchesPeriod { return false }
        }
        return true
    }

    /// Comparison fold shared by the guard's checks: case- and
    /// whitespace-insensitive, with the truncation ellipsis and trailing
    /// separators stripped so two truncations of the same text compare equal.
    private nonisolated static func cardComparisonFold(_ text: String) -> String {
        var line = text.lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = line.last, last == "…" || ".,:;!?".contains(last) {
            line.removeLast()
        }
        return line.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Deterministic fallbacks (model unavailable / generation failed)

    /// Truncation-based card: title from the first meaningful user line (or
    /// the reply's, when the turn was attachment-only), preview from the
    /// reply. When the title had to borrow the reply's first line, the
    /// preview steps to the reply's NEXT line so the two never echo (#61).
    nonisolated static func fallbackCard(userText: String, assistantText: String) -> ConversationCard {
        let userLine = firstMeaningfulLine(of: userText)
        let assistantLines = meaningfulLines(of: assistantText)
        let titleSource = userLine ?? assistantLines.first ?? ""
        // #61: when the user turn carried no meaningful line (attachment-only,
        // slash command, empty), the title has to borrow the reply's first
        // line — the very line the preview would otherwise use. Showing it in
        // both fields reads as a duplicate card (device pass 2026-07-11 FAIL:
        // "repeats the first line on both lines"). Give the preview a DISTINCT
        // source: the reply's next meaningful line, or nothing — a title-only
        // card is honest; two copies of one line is not.
        let previewSource = userLine == nil
            ? (assistantLines.dropFirst().first ?? "")
            : (assistantLines.first ?? "")
        return ConversationCard(
            title: condensedLine(titleSource, limit: 48),
            preview: condensedLine(previewSource, limit: 90)
        )
    }

    /// Every line that carries words, in order — skips blanks and fenced code
    /// blocks (markers AND their contents, so a code line never becomes a
    /// title), and strips markdown heading markers.
    nonisolated static func meaningfulLines(of text: String) -> [String] {
        var lines: [String] = []
        var inFence = false
        for line in text.split(separator: "\n") {
            var trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inFence.toggle()
                continue
            }
            guard !inFence, !trimmed.isEmpty else { continue }
            while trimmed.hasPrefix("#") { trimmed.removeFirst() }
            trimmed = trimmed.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { lines.append(trimmed) }
        }
        return lines
    }

    /// First line that carries words. See `meaningfulLines`.
    nonisolated static func firstMeaningfulLine(of text: String) -> String? {
        meaningfulLines(of: text).first
    }

    /// Collapses whitespace to single spaces, strips wrapping quotes/backticks
    /// and trailing separator punctuation (`.,:;` — question/exclamation marks
    /// are meaning, they stay), then word-boundary-truncates to `limit`.
    nonisolated static func condensedLine(_ text: String, limit: Int) -> String {
        var line = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = line.first, "\"'`“”‘’".contains(first) { line.removeFirst() }
        while let last = line.last, "\"'`“”‘’".contains(last) { line.removeLast() }
        line = line.trimmingCharacters(in: .whitespaces)
        while let last = line.last, ".,:;".contains(last) { line.removeLast() }
        guard line.count > limit else { return line }
        let head = String(line.prefix(limit))
        let cut = head.range(of: " ", options: .backwards).map { String(head[..<$0.lowerBound]) } ?? head
        return (cut.isEmpty ? head : cut) + "…"
    }
}
