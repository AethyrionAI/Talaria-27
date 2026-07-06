import Foundation
import Testing
@testable import Talaria

/// #6 — Ask Hermes intent: the pure helpers that shape what Siri speaks and
/// how a finished send is classified. The App Intents runtime itself isn't
/// exercised here — perform() needs the system Siri/Shortcuts machinery.
struct AskHermesIntentTests {

    // MARK: - spokenSummary

    @Test func shortAnswerIsSpokenVerbatim() {
        #expect(AskHermesIntent.spokenSummary(of: "Sunny and 22 degrees.") == "Sunny and 22 degrees.")
    }

    @Test func summaryKeepsOnlyTheFirstTwoSentences() {
        let answer = "First point. Second point. Third point. Fourth point."
        #expect(AskHermesIntent.spokenSummary(of: answer) == "First point. Second point.")
    }

    @Test func summaryCollapsesNewlinesAndWhitespaceRuns() {
        let answer = "Line one\ncontinues after a break.\n\n  Second   sentence here."
        #expect(
            AskHermesIntent.spokenSummary(of: answer)
                == "Line one continues after a break. Second sentence here."
        )
    }

    @Test func longSingleSentenceIsCutAtWordBoundaryWithEllipsis() {
        // 100 words, no sentence terminator — one giant "sentence" that must
        // hit the character cap instead of the sentence cap.
        let answer = Array(repeating: "word", count: 100).joined(separator: " ")
        let spoken = AskHermesIntent.spokenSummary(of: answer)
        #expect(spoken.hasSuffix("…"))
        #expect(spoken.count <= 281) // 280 + ellipsis
        // Word-boundary cut: no clipped fragment like "wor…".
        #expect(spoken.dropLast().split(separator: " ").allSatisfy { $0 == "word" })
    }

    @Test func emptyAnswerYieldsEmptySummary() {
        #expect(AskHermesIntent.spokenSummary(of: "   \n  ").isEmpty)
    }

    // MARK: - resolveOutcome

    private let cutoff = Date(timeIntervalSince1970: 1_000_000)

    private func message(
        _ sender: MessageSender,
        _ content: String,
        at offset: TimeInterval,
        status: MessageStatus = .delivered,
        isStreaming: Bool = false
    ) -> Message {
        Message(
            sender: sender,
            content: content,
            timestamp: cutoff.addingTimeInterval(offset),
            status: status,
            isStreaming: isStreaming
        )
    }

    @Test func hermesReplyAfterCutoffIsTheAnswer() {
        let messages = [
            message(.hermes, "Old cached reply.", at: -100),
            message(.user, "What's the weather?", at: 1, status: .sending),
            message(.hermes, "Sunny and 22 degrees.", at: 2),
        ]
        #expect(
            AskHermesIntent.resolveOutcome(messages: messages, sentAfter: cutoff)
                == .answered("Sunny and 22 degrees.")
        )
    }

    @Test func cachedRepliesBeforeCutoffAreIgnored() {
        // Only history predates the send — nothing new means still pending,
        // never a stale answer presented as fresh ("real data only").
        let messages = [
            message(.hermes, "Old cached reply.", at: -5),
            message(.user, "New question", at: 1, status: .sending),
        ]
        #expect(AskHermesIntent.resolveOutcome(messages: messages, sentAfter: cutoff) == .pending)
    }

    @Test func streamingOrEmptyReplyIsNotAnAnswer() {
        let messages = [
            message(.user, "Question", at: 1, status: .sending),
            message(.hermes, "partial…", at: 2, isStreaming: true),
            message(.hermes, "   ", at: 3),
        ]
        #expect(AskHermesIntent.resolveOutcome(messages: messages, sentAfter: cutoff) == .pending)
    }

    @Test func systemFailureSurfacesItsRealErrorText() {
        // ChatStore's .failed path plants the transport error verbatim in a
        // .system/.failed message — that exact text must reach Siri's UI.
        let errorText = "Could not connect to the server."
        let messages = [
            message(.user, "Question", at: 1, status: .failed),
            message(.system, errorText, at: 2, status: .failed),
        ]
        #expect(
            AskHermesIntent.resolveOutcome(messages: messages, sentAfter: cutoff)
                == .failed(errorText)
        )
    }

    @Test func interruptedCommittedRunIsPending() {
        // ChatStore's .interrupted path: placeholder removed, user turn marked
        // .working — the run continues server-side and reconcile picks it up.
        let messages = [
            message(.user, "Question", at: 1, status: .working),
        ]
        #expect(AskHermesIntent.resolveOutcome(messages: messages, sentAfter: cutoff) == .pending)
    }

    @Test func replyWinsOverEarlierFailureInSameExchange() {
        // A late-arriving reply after a transient failure message means the
        // exchange ultimately succeeded — prefer the answer.
        let messages = [
            message(.user, "Question", at: 1),
            message(.system, "stream dropped", at: 2, status: .failed),
            message(.hermes, "Recovered answer.", at: 3),
        ]
        #expect(
            AskHermesIntent.resolveOutcome(messages: messages, sentAfter: cutoff)
                == .answered("Recovered answer.")
        )
    }
}
