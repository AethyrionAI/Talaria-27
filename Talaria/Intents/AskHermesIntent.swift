import AppIntents
import SwiftUI

/// "Ask Talaria …" from Siri / Shortcuts → one Hermes exchange, answered in
/// place (#6). A background query intent: `perform()` routes through the same
/// `ChatStore.sendMessage` seam the Chat screen uses — the agent stays the
/// brain, and reusing the store gives conversation-cache consistency (the
/// exchange appears in the app on next open) plus widget updates for free.
///
/// Two-tier long-run strategy (#6):
///  - Tier A (this file, stable API): `perform()` awaits the send under a
///    ~25 s budget — iOS kills background intent performs around 30 s. If the
///    reply lands in budget it's spoken + shown in a snippet; if not, Siri
///    says the run continues and the answer lands in the app. The in-flight
///    run is deliberately NOT cancelled on budget expiry.
///  - Tier B (AskHermesLongRunSupport.swift, flag-gated behind
///    TALARIA_IOS27_INTENTS): iOS 27 `LongRunningIntent` adoption so the run
///    can survive past the cap with real progress + a Stop control. Disabled
///    until a Mac session verifies the beta SDK shape.
struct AskHermesIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Hermes"
    static let description = IntentDescription(
        "Asks Hermes a question and speaks the answer without opening the app.",
        categoryName: "Chat"
    )
    /// Background query — Siri shows the answer in place. The full transcript
    /// is one `hermes://chat` deep link away (handled in AppEntry).
    static let openAppWhenRun = false

    /// Free-form text. Note: String parameters cannot ride App Shortcut
    /// phrases (AppEnum/AppEntity only), so "Ask Talaria" prompts for the
    /// question via this dialog instead of capturing it inline.
    @Parameter(
        title: "Question",
        description: "What to ask Hermes.",
        requestValueDialog: IntentDialog("What should I ask Hermes?")
    )
    var question: String

    static var parameterSummary: some ParameterSummary {
        Summary("Ask Hermes \(\.$question)")
    }

    /// Tier A time budget. The system terminates background intent performs
    /// around ~30 s; returning at 25 s leaves headroom for result delivery.
    static let replyBudget: Duration = .seconds(25)

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetView {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty else {
            throw $question.needsValueError()
        }

        let container = AppContainer.sharedDefault()
        let chatStore = container.chatStore

        // One run at a time — stacking a second stream onto an in-flight one
        // would tangle ChatStore's placeholder bookkeeping.
        guard !chatStore.isStreaming else {
            throw AskHermesIntentError.busy
        }

        await Self.waitForAPIKeyRestore(container)

        // Seed from the cached conversation FIRST so this exchange appends to
        // the canonical thread rather than a fresh one — that is what makes it
        // show up in the app's transcript on next open (#6 acceptance).
        await chatStore.loadConversationIfNeeded()

        // Everything this exchange appends is timestamped at/after this
        // instant; `resolveOutcome` classifies by that cutoff (same convention
        // as ChatStore.attemptReconcile).
        let sentAt = Date()

        // Unstructured and never cancelled on budget expiry (deliberate — #6
        // Tier A): when the budget lapses we answer Siri with "still working"
        // and let the stream keep running for as long as iOS keeps this
        // background launch alive. sendMessage persists the conversation cache
        // when it completes, and the pendingRun/reconcile machinery covers a
        // dropped stream, so the reply is waiting in the app either way.
        let completion = CompletionFlag()
        Task { @MainActor in
            await chatStore.sendMessage(trimmedQuestion)
            completion.isDone = true
        }

        // Budget poll. Task.sleep throws immediately once Siri cancels the
        // perform, so the loop is cancellation-responsive without busy-waiting.
        let clock = ContinuousClock()
        let deadline = clock.now + Self.replyBudget
        while !completion.isDone, clock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(200))
        }

        if Task.isCancelled {
            // Siri's Stop/Cancel → the existing run-interruption path (#6
            // acceptance). cancelStreaming finalizes any partial reply into
            // the conversation and persists it, so even an aborted exchange
            // shows in the app.
            chatStore.cancelStreaming()
            throw CancellationError()
        }

        guard completion.isDone else {
            // Budget expired mid-run. The run keeps streaming (see above) —
            // report the truth: it's still working, the answer lands in-app.
            return .result(
                value: "",
                dialog: IntentDialog("Hermes is still working on it. Open Talaria to watch it finish."),
                view: AskHermesSnippetView(question: trimmedQuestion, state: .working)
            )
        }

        switch Self.resolveOutcome(messages: chatStore.conversation?.messages ?? [], sentAfter: sentAt) {
        case .answered(let answer):
            // Speak a trimmed summary; the snippet + `value` carry the full
            // text (value lets Shortcuts chain the answer onward).
            return .result(
                value: answer,
                dialog: IntentDialog("\(Self.spokenSummary(of: answer))"),
                view: AskHermesSnippetView(question: trimmedQuestion, state: .answered(answer))
            )
        case .failed(let errorText):
            // Real failure text from the chat path (tailnet unreachable, auth,
            // HTTP status) — surfaced verbatim in Siri's error UI, never a
            // fabricated answer ("real data only").
            throw AskHermesIntentError.hermesFailed(errorText)
        case .queued:
            // Sessions API unreachable — the turn is parked in the compose
            // outbox (#90) and auto-sends when the host is reachable. Honest
            // dialog: nothing was accepted yet, nothing is running.
            return .result(
                value: "",
                dialog: IntentDialog("Hermes is unreachable right now. Your question is queued and will send automatically."),
                view: AskHermesSnippetView(question: trimmedQuestion, state: .working)
            )
        case .pending:
            // Stream dropped but the run is committed server-side (ChatStore's
            // .interrupted path) — reconcile delivers the reply on next open.
            return .result(
                value: "",
                dialog: IntentDialog("Hermes accepted the question and is still working. Open Talaria to see the answer."),
                view: AskHermesSnippetView(question: trimmedQuestion, state: .working)
            )
        }
    }

    // MARK: - Outcome classification

    /// How one intent-originated exchange ended, read back from the
    /// conversation after `sendMessage` returns.
    enum Outcome: Equatable, Sendable {
        /// A Hermes reply landed — content is the answer.
        case answered(String)
        /// The send failed outright — content is the REAL error text.
        case failed(String)
        /// The Sessions API was unreachable — the turn parked in the offline
        /// compose outbox (#90) and auto-sends when the host is reachable.
        case queued
        /// No reply and no failure yet (run interrupted but committed
        /// server-side, or the post-accept refresh hasn't delivered).
        case pending
    }

    /// Classifies the messages this exchange appended (timestamped at/after
    /// `cutoff`, captured just before the send). A real Hermes reply wins;
    /// then a system failure message (whose content is the real error text —
    /// ChatStore's `.failed` path); otherwise the run is still pending.
    /// Timestamps here are client-composed (optimistic append / stream
    /// finalize), so the comparison is skew-free.
    nonisolated static func resolveOutcome(messages: [Message], sentAfter cutoff: Date) -> Outcome {
        let exchange = messages.filter { $0.timestamp >= cutoff }
        if let reply = exchange.last(where: {
            $0.sender == .hermes
                && !$0.isStreaming
                && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) {
            return .answered(reply.content)
        }
        if let failure = exchange.last(where: { $0.sender == .system && $0.status == .failed }) {
            return .failed(failure.content)
        }
        if exchange.contains(where: { $0.sender == .user && $0.status == .queued }) {
            return .queued
        }
        return .pending
    }

    // MARK: - Spoken summary

    /// Trims an answer for Siri's spoken dialog: whitespace collapsed, first
    /// `maxSentences` sentences, hard-capped at `maxCharacters` (cut at a word
    /// boundary + ellipsis). The snippet and `value` still carry the full text.
    nonisolated static func spokenSummary(
        of answer: String,
        maxSentences: Int = 2,
        maxCharacters: Int = 280
    ) -> String {
        // Collapse all whitespace runs (newlines included) — spoken text has
        // no layout, and markdown line breaks read as pauses otherwise.
        let collapsed = answer.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !collapsed.isEmpty else { return collapsed }

        var sentences: [String] = []
        collapsed.enumerateSubstrings(
            in: collapsed.startIndex..<collapsed.endIndex,
            options: .bySentences
        ) { substring, _, _, stop in
            if let sentence = substring?.trimmingCharacters(in: .whitespaces), !sentence.isEmpty {
                sentences.append(sentence)
            }
            if sentences.count >= maxSentences {
                stop = true
            }
        }

        let summary = sentences.isEmpty ? collapsed : sentences.joined(separator: " ")
        guard summary.count > maxCharacters else { return summary }

        let cutIndex = summary.index(summary.startIndex, offsetBy: maxCharacters)
        let clipped = summary[..<cutIndex]
        let wordBounded = clipped.lastIndex(of: " ").map { clipped[..<$0] } ?? clipped
        return wordBounded.trimmingCharacters(in: .whitespaces) + "…"
    }

    // MARK: - Cold-launch key restore

    /// AppContainer.makeDefault() restores the Sessions-API key from the
    /// Keychain on a detached task. Siri can cold-launch the process just for
    /// this intent, and the send would outrun that restore and 401 with an
    /// empty key. Wait briefly for it to land; a genuinely unconfigured key
    /// just exhausts the window and the send surfaces its real error.
    @MainActor
    private static func waitForAPIKeyRestore(_ container: AppContainer) async {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(2)
        while container.hermesAPIKey.isEmpty, clock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}

/// Reference box so the unstructured send task can signal completion to the
/// budget poll without capturing a mutable local (Swift 6 strict concurrency).
@MainActor
private final class CompletionFlag {
    var isDone = false
}

// MARK: - Errors

/// Errors surfaced in Siri's result UI. `hermesFailed` carries the REAL
/// failure text from the chat path (e.g. the URLError for an unreachable
/// tailnet host) — never a fabricated reply ("real data only").
enum AskHermesIntentError: Error, CustomLocalizedStringResourceConvertible {
    case hermesFailed(String)
    case busy

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .hermesFailed(let message):
            return "\(message)"
        case .busy:
            return "Hermes is already working on another request. Open Talaria to see it."
        }
    }
}

// MARK: - Snippet view

/// The result card Siri / Shortcuts renders under the spoken dialog.
///
/// Deliberately self-contained: the snippet is archived and drawn in a system
/// process, where `ThemeRuntime`'s live state and the bundled custom fonts
/// (Chakra Petch / JetBrains Mono) can't be assumed. Deep Field default hex
/// values via `Color(hex:)` (Shared/ThemePaletteCore.swift) and the system
/// monospaced font stand in for the Design tokens / MonoLabel, mirroring the
/// HUD panel look: dark surface, accent hairline, uppercase mono header.
struct AskHermesSnippetView: View {
    enum DisplayState: Equatable {
        case answered(String)
        case working
    }

    let question: String
    let state: DisplayState

    // Deep Field defaults (ThemePaletteCore init(deepField:), cyan slot).
    private var accent: Color { Color(hex: 0x54E6F0) }      // Brand.accent
    private var forge: Color { Color(hex: 0xFFC14D) }       // Brand.forge
    private var foreground: Color { Color(hex: 0xE8EEF5) }  // Colors.foreground
    private var secondary: Color { Color(hex: 0x7C93A6) }   // Colors.secondaryForeground
    private var muted: Color { Color(hex: 0x5D7488) }       // Colors.mutedForeground
    private var panel: Color { Color(hex: 0x08121A) }       // Colors.surface base

    private var isWorking: Bool { state == .working }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isWorking ? forge : accent)
                    .frame(width: 6, height: 6)
                monoHeader("HERMES", color: accent)
                Spacer(minLength: 0)
                monoHeader(isWorking ? "WORKING" : "REPLY", color: muted)
            }

            Text(question)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(secondary)
                .lineLimit(2)

            Rectangle()
                .fill(accent.opacity(0.14)) // Colors.hairline
                .frame(height: 1)

            switch state {
            case .answered(let answer):
                Text(answer)
                    .font(.system(size: 15))
                    .foregroundStyle(foreground)
                    .lineLimit(12)
                    .fixedSize(horizontal: false, vertical: true)
            case .working:
                Text("The run is still going — open Talaria for the full transcript when it lands.")
                    .font(.system(size: 14))
                    .foregroundStyle(secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(accent.opacity(0.30), lineWidth: 1) // Colors.strongBorder
                )
        )
    }

    private func monoHeader(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .tracking(2.2)
            .foregroundStyle(color)
    }
}
