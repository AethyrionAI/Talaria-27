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

    // MARK: - #415-S naming — the Shortcuts surface says Talaria

    /// **415-S-1.** Owen's straggler ruling, verbatim: *"shortcuts only."*
    /// This is the COMPILED value the App Intents extractor bakes into the
    /// bundle's `Metadata.appintents`, so it fails on a real regression
    /// rather than on stale comment prose — `LocalizedStringResource` is
    /// `Equatable`, and a literal that got commented out instead of changed
    /// would not satisfy it. Same instrument as 415-N-1 used for the two
    /// Control Center intents.
    @Test func askIntentTitleNamesTalaria() {
        #expect(AskHermesIntent.title == "Ask Talaria")
    }

    /// **415-S-2, the `AppShortcut` half.** `AppShortcut` publishes
    /// initializers and **no readable `shortTitle` property** (checked in the
    /// iOS SDK's `AppIntents.swiftinterface`), so the compiled value is
    /// unreachable from a test and the source is the only honest instrument
    /// — the #399 / 415-N-2 source-reading pattern.
    ///
    /// Both directions are asserted, and the presence half is matched WITH
    /// its surrounding call so no amount of comment prose can satisfy it.
    /// Fails loudly if the file cannot be read: a check that cannot run must
    /// say so rather than pass.
    ///
    /// The absence half matches the QUOTED spelling only — that file may
    /// legitimately discuss the old name in prose, but not as a literal.
    @Test func theAppShortcutSpellsTalaria() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TalariaTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Talaria/Intents/StartVoiceSessionIntent.swift")
        let source = try #require(
            try? String(contentsOf: file, encoding: .utf8),
            "cannot read Talaria/Intents/StartVoiceSessionIntent.swift — this check did not run"
        )

        #expect(source.contains("shortTitle: \"Ask Talaria\""),
                "the Ask shortcut's shortTitle is missing or renamed")
        #expect(!source.contains("\"Ask Hermes\""),
                "the App Shortcut still spells a literal \"Ask Hermes\"")

        // 415-S-5: the registration identity does NOT move with the title.
        // Measured out of a real build product — `Metadata.appintents`
        // records `identifier: "AskHermesIntent"` and
        // `mangledTypeName: "7Talaria15AskHermesIntentV"`, so the system keys
        // placed shortcuts off the TYPE, never the display string. Renaming
        // the type is the Shortcuts-surface twin of 415-N-3's control-`kind`
        // hazard: it would satisfy every other bar here and still orphan
        // every shortcut Owen has already built.
        #expect(source.contains("intent: AskHermesIntent()"),
                "the shortcut's intent type moved — that orphans placed shortcuts")
    }

    /// **415-S-3.** CarPlay was DECLINED-FOR-NOW with a trigger, not
    /// forgotten (Owen: *"I don't see any reason to make changes that we
    /// can't even see right now"* — #74 has left the CarPlay simulator
    /// broken across three runtimes, so the rename would be unverifiable).
    ///
    /// A bar of the form "we did not edit that file" is unfalsifiable in a
    /// diff nobody re-reads, so the deferral gets a live guard instead: if a
    /// future sweep takes this line before CarPlay becomes verifiable, this
    /// goes red and the deferral is re-decided deliberately. The two sibling
    /// strings ride along because they are host-meaning and must survive any
    /// eventual rename of the idle title.
    @Test func carPlayIdleTitleIsUntouched() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TalariaTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Talaria/CarPlay/CarPlayVoiceManager.swift")
        let source = try #require(
            try? String(contentsOf: file, encoding: .utf8),
            "cannot read Talaria/CarPlay/CarPlayVoiceManager.swift — this check did not run"
        )

        #expect(source.contains("titleVariants: [\"Talk to Hermes\"]"),
                "CarPlay's idle title moved — #415 declined that rename until #74 makes CarPlay verifiable")
        // Host-meaning siblings: Talaria is a client for a Hermes host.
        #expect(source.contains("\"Connecting to Hermes...\""))
        #expect(source.contains("\"Hermes is speaking\""))
    }
}
