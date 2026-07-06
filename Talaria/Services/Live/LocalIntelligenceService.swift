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
    @Generable
    private struct GeneratedCard {
        @Guide(description: "Title for the conversation: 2 to 6 plain-text words, no quotes, no trailing punctuation.")
        var title: String
        @Guide(description: "One sentence, at most 90 characters, saying what the conversation is about.")
        var preview: String
    }

    private var model: SystemLanguageModel { SystemLanguageModel.default }

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
            return Self.fallbackCard(userText: userText, assistantText: assistantText)
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
                options: GenerationOptions(temperature: 0.3)
            )
            let title = Self.condensedLine(response.content.title, limit: 48)
            let preview = Self.condensedLine(response.content.preview, limit: 90)
            // Fallback is computed only on the branches that need it — the
            // happy path shouldn't pay for line scans it throws away.
            if !title.isEmpty, !preview.isEmpty {
                return ConversationCard(title: title, preview: preview)
            }
            let fallback = Self.fallbackCard(userText: userText, assistantText: assistantText)
            guard !title.isEmpty else { return fallback }
            return ConversationCard(title: title, preview: fallback.preview)
        } catch {
            Self.logger.notice("conversationCard: generation failed — \(error.localizedDescription, privacy: .public); using truncation fallback")
            return Self.fallbackCard(userText: userText, assistantText: assistantText)
        }
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
                options: GenerationOptions(temperature: 0.3)
            )
            let line = Self.condensedLine(response.content, limit: 72)
            return line.isEmpty ? nil : line
        } catch {
            Self.logger.notice("condensedReasoning: generation failed — \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Context budgeting (#4.8)

    /// Prompt-input token budget: the on-device context window (8192 tokens
    /// on iOS 27 hardware — read live, never hardcoded) minus headroom for
    /// instructions + output.
    private var promptInputBudget: Int { max(512, model.contextSize - 1024) }

    /// Trims `text` to roughly `budget` tokens, measured with the model's own
    /// tokenizer where available (`tokenCount(for:)`, iOS 26.4+) and a
    /// conservative chars/3 estimate otherwise. Proportional cuts re-measured
    /// over up to three passes, so a pathological tokenization can't overshoot
    /// the context window.
    private func trimmed(_ text: String, toTokenBudget budget: Int) async -> String {
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

    private func measuredTokenCount(of text: String) async -> Int {
        if #available(iOS 26.4, *) {
            if let count = try? await model.tokenCount(for: Prompt("\(text)")) {
                return count
            }
        }
        // ~3 chars per token deliberately underestimates the budget room —
        // it can waste input, never overflow the context.
        return max(1, text.count / 3)
    }

    // MARK: - Deterministic fallbacks (model unavailable / generation failed)

    /// Truncation-based card: title from the first meaningful user line (or
    /// the reply's, when the turn was attachment-only), preview from the
    /// reply's first meaningful line.
    nonisolated static func fallbackCard(userText: String, assistantText: String) -> ConversationCard {
        let titleSource = firstMeaningfulLine(of: userText) ?? firstMeaningfulLine(of: assistantText) ?? ""
        let previewSource = firstMeaningfulLine(of: assistantText) ?? ""
        return ConversationCard(
            title: condensedLine(titleSource, limit: 48),
            preview: condensedLine(previewSource, limit: 90)
        )
    }

    /// First line that carries words — skips blanks and fenced code blocks
    /// (markers AND their contents, so a code line never becomes a title),
    /// and strips markdown heading markers.
    nonisolated static func firstMeaningfulLine(of text: String) -> String? {
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
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
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
