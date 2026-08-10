import Foundation
import Testing
@testable import Talaria

/// #280 — the inputs the on-device conversation-card generator runs on.
///
/// **These started life as CHARACTERIZATION tests written against the DEFECT.**
/// `voiceOnlyThreadYieldsNoCardInputs` PASSED before any fix — a voice-only
/// thread returned nil here, which is what blocker B2
/// (`generateConversationCardIfNeeded`'s eligibility guard matching `.hermes`
/// only, while a spoken reply is `.voiceHermes`) looked like from the outside.
/// It is now inverted into `voiceOnlyThreadYieldsTheSpokenExchange`. Recording
/// the defect in executable form first is what makes that inversion's RED
/// honest evidence rather than a test pinned to text the fix never touched.
///
/// Three independent blockers stood between a spoken thread and a title, any
/// one of them sufficient to produce the symptom:
///
/// - **B1** — `appendVoiceTranscript` never called
///   `finalizeOnDeviceIntelligence()`, so the generator was not invoked on the
///   voice path at all. The outermost cause, and absent from #280's entry.
/// - **B2** — the `.hermes` eligibility guard, above.
/// - **B3** — the title source matched `.user`, missing `.voiceUser`. #280's
///   STATED cause, and the least consequential of the three: it degrades the
///   title's *quality*, it does not suppress the title.
///
/// Note what the tracker got wrong and these tests must not repeat: an EMPTY
/// user side is not the bug. `LocalIntelligenceService.fallbackCard` is built
/// for it — it borrows the reply's first line for the title and steps the
/// preview to the reply's second line so the two never echo.
struct ConversationCardInputTests {

    // MARK: - Builders

    private func message(
        _ sender: MessageSender,
        _ content: String,
        status: MessageStatus = .delivered,
        attachments: [MessageAttachment] = []
    ) -> Message {
        Message(sender: sender, content: content, status: status, attachments: attachments)
    }

    private func conversation(_ messages: [Message]) -> Conversation {
        Conversation(title: Conversation.defaultTitle, messages: messages)
    }

    /// The exact shape `ChatStore.voiceTranscriptMessages` produces: a
    /// `.system` banner, then one row per finalized spoken turn.
    private func voiceOnlyConversation() -> Conversation {
        conversation([
            message(.system, "[Voice session ended]"),
            message(.voiceUser, "Remind me what we decided about the trip to Lisbon."),
            message(.voiceHermes, "You settled on the first week of October, flying out of Gatwick."),
        ])
    }

    // MARK: - 280-B · the card runs on what was SPOKEN

    /// **280-B.** The inversion of this file's original characterization test
    /// (`voiceOnlyThreadYieldsNoCardInputs`, which passed against the defect).
    ///
    /// RED evidence: with the two predicates reverted to `== .hermes` /
    /// `== .user`, this fails **because the function returns nil** — the
    /// `.hermes` guard rejects `.voiceHermes` and there is no exchange to
    /// report. Not a string mismatch, not a compile error.
    @Test func voiceOnlyThreadYieldsTheSpokenExchange() {
        let inputs = ChatStore.conversationCardInputs(for: voiceOnlyConversation())

        #expect(inputs != nil)
        #expect(inputs?.userText == "Remind me what we decided about the trip to Lisbon.")
        #expect(inputs?.assistantText == "You settled on the first week of October, flying out of Gatwick.")
    }

    /// The `.system` banner sorts FIRST in every voice transcript, so a
    /// predicate that leaked it would take it every single time.
    @Test func theVoiceSessionBannerIsNeitherSideOfTheExchange() {
        let inputs = ChatStore.conversationCardInputs(for: voiceOnlyConversation())

        #expect(inputs?.userText != "[Voice session ended]")
        #expect(inputs?.assistantText != "[Voice session ended]")
    }

    // MARK: - 280-C · a mixed thread titles from its FIRST exchange

    /// **280-C — a pre-registered BEHAVIOR CHANGE, not a side effect.** Before
    /// this lane the card generated from the TYPED exchange while
    /// `generateConversationCardIfNeeded`'s own doc comment promised "the
    /// conversation's first completed exchange". The first exchange was
    /// spoken. Applying both predicates makes the doc comment true again.
    @Test func mixedThreadYieldsTheSpokenFirstExchange() {
        let conv = conversation([
            message(.system, "[Voice session ended]"),
            message(.voiceUser, "What's on for Thursday?"),
            message(.voiceHermes, "Two calls and the dentist at four."),
            message(.user, "Move the dentist to Friday."),
            message(.hermes, "Moved — Friday at four."),
        ])

        let inputs = ChatStore.conversationCardInputs(for: conv)

        #expect(inputs?.userText == "What's on for Thursday?")
        #expect(inputs?.assistantText == "Two calls and the dentist at four.")
    }

    /// The mirror, and the control on 280-C: typed first, spoken second, still
    /// the FIRST exchange. Guards against a fix that merely PREFERS spoken
    /// rows rather than treating a spoken exchange as an ordinary one.
    @Test func mixedThreadTypedFirstYieldsTheTypedExchange() {
        let conv = conversation([
            message(.user, "Draft the standup note."),
            message(.hermes, "Here's a draft you can trim."),
            message(.system, "[Voice session ended]"),
            message(.voiceUser, "Read it back to me."),
            message(.voiceHermes, "Sure — here it is."),
        ])

        let inputs = ChatStore.conversationCardInputs(for: conv)

        #expect(inputs?.userText == "Draft the standup note.")
        #expect(inputs?.assistantText == "Here's a draft you can trim.")
    }

    /// A spoken reply with no spoken question before it — the empty user side
    /// is a DESIGNED-FOR input, not a failure. `fallbackCard` borrows the
    /// reply's first line for the title and steps the preview to its second.
    /// This is the case #280's entry mistook for the bug.
    @Test func replyWithoutAUserTurnStillYieldsAnExchange() {
        let conv = conversation([
            message(.system, "[Voice session ended]"),
            message(.voiceHermes, "Your first meeting moved to nine."),
        ])

        let inputs = ChatStore.conversationCardInputs(for: conv)

        #expect(inputs?.userText == "")
        #expect(inputs?.assistantText == "Your first meeting moved to nine.")
    }

    // MARK: - The working cases these must not disturb (280-D)

    @Test func typedThreadYieldsUserAndReply() {
        let conv = conversation([
            message(.user, "  How do I renew the certificate?  "),
            message(.hermes, "Run the renew command from the deploy host."),
        ])

        let inputs = ChatStore.conversationCardInputs(for: conv)

        #expect(inputs?.userText == "How do I renew the certificate?")
        #expect(inputs?.assistantText == "Run the renew command from the deploy host.")
    }

    /// 280-D's deliberate case. `"[2 attachment(s)]"` is a DISPLAY
    /// placeholder, not user words — it must never become the title, and the
    /// card derives everything from the reply instead. **This row is the one
    /// that must NOT be "fixed".**
    @Test func attachmentPlaceholderNormalizesToEmptyUserText() {
        let attachment = MessageAttachment(kind: "image", fileName: "screenshot.png", mimeType: "image/png")
        let conv = conversation([
            message(.user, "[2 attachment(s)]", attachments: [attachment]),
            message(.hermes, "That's the login screen after the redirect."),
        ])

        let inputs = ChatStore.conversationCardInputs(for: conv)

        #expect(inputs?.userText == "")
        #expect(inputs?.assistantText == "That's the login screen after the redirect.")
    }

    /// A reply that has not been delivered is not a completed exchange.
    @Test func undeliveredReplyIsNotAnExchange() {
        let conv = conversation([
            message(.user, "Still there?"),
            message(.hermes, "", status: .sending),
        ])

        #expect(ChatStore.conversationCardInputs(for: conv) == nil)
    }

    /// A whitespace-only reply is not one either — a tool-shell row carries
    /// no content to label the thread with.
    @Test func whitespaceOnlyReplyIsNotAnExchange() {
        let conv = conversation([
            message(.user, "Run the check."),
            message(.hermes, "   \n  "),
        ])

        #expect(ChatStore.conversationCardInputs(for: conv) == nil)
    }

    /// No reply at all — the thread has nothing to label yet.
    @Test func userOnlyThreadYieldsNoInputs() {
        #expect(ChatStore.conversationCardInputs(for: conversation([message(.user, "Hello?")])) == nil)
    }
}

// MARK: - The voice path reaches the generator at all (280-A, 280-E)

/// #280 blocker **B1**, which is the one the tracker never named: the pure
/// function above can be perfect and a voice-only thread still gets no title,
/// because `appendVoiceTranscript` never invoked the generator.
///
/// **These ride the REAL `LocalIntelligenceService`.** `ChatStore.localIntelligence`
/// is a concrete type with no protocol seam, so there is no fake to inject.
/// The service behaves differently by environment — on the test host
/// `isAvailable` is true but generation throws `Code=5000` (no assets) and the
/// deterministic truncation fallback runs instantly; on a device with assets,
/// real guided generation runs and takes seconds. **So these assert
/// NON-DEFAULT title only, never exact text**, and the poll budget tolerates a
/// real generation.
@Suite(.serialized)
struct VoiceThreadTitleTests {

    @MainActor
    private final class StubHermesClient: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .connected
        var currentConversation: Conversation?
        var sendCallCount = 0

        func connect() async {}
        func disconnect() async {}

        func send(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) async -> Message {
            sendCallCount += 1
            return Message(sender: .hermes, content: "unused", status: .delivered)
        }

        func sendStreaming(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) -> AsyncStream<StreamingUpdate> {
            AsyncStream { $0.finish() }
        }

        func loadConversation() async -> Conversation {
            currentConversation ?? Conversation(title: Conversation.defaultTitle)
        }

        func clearConversation() async throws -> Conversation {
            Conversation(title: Conversation.defaultTitle)
        }
    }

    @MainActor
    private func makeStore() -> ChatStore {
        let suiteName = "voice-title-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = ChatStore(
            hermesClient: StubHermesClient(),
            persistence: UserDefaultsAppPersistenceStore(defaults: defaults)
        )
        store.localIntelligence = LocalIntelligenceService()
        return store
    }

    private func voiceSession() -> CompletedVoiceSession {
        let transcript = [
            TranscriptItem(speaker: .user, text: "Remind me what we decided about the trip to Lisbon."),
            TranscriptItem(speaker: .hermes, text: "You settled on the first week of October, flying out of Gatwick."),
        ]
        return CompletedVoiceSession(
            voiceSessionId: UUID(),
            duration: 83,
            turnCount: transcript.count,
            transcript: transcript,
            engine: .realtime
        )
    }

    /// Generous on purpose: the truncation fallback returns in milliseconds,
    /// a real on-device guided generation takes seconds.
    @MainActor
    private func pollUntil(
        timeout: Duration = .seconds(20),
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return condition()
    }

    /// **280-A — the bar that catches the no-op.** RED evidence: with the
    /// `finalizeOnDeviceIntelligence()` call deleted from
    /// `appendVoiceTranscript`, this fails on the poll TIMING OUT with the
    /// title still `"Hermes"`. That is B1, and no predicate change can
    /// satisfy this bar.
    @Test @MainActor func voiceOnlyThreadGetsAGeneratedTitle() async {
        let store = makeStore()

        store.appendVoiceTranscript(voiceSession(), postToHermes: false)

        let titled = await pollUntil { store.conversation?.title != Conversation.defaultTitle }
        #expect(titled, "the voice-only thread never left Conversation.defaultTitle")
        #expect(store.conversation?.title.isEmpty == false)
    }

    /// **280-E.** A conversation retitled by hand keeps its title — the
    /// generator only ever runs while the title is still the placeholder, and
    /// the new call site must not route around that.
    @Test @MainActor func manualTitleSurvivesAVoiceAppend() async {
        let store = makeStore()
        store.conversation = Conversation(title: "Trip notes")

        store.appendVoiceTranscript(voiceSession(), postToHermes: false)

        // Give a generation every chance to (wrongly) land before asserting.
        _ = await pollUntil(timeout: .seconds(2)) { store.conversation?.title != "Trip notes" }
        #expect(store.conversation?.title == "Trip notes")
    }

    /// **280-E, second half.** Two appends, one generation: once the first
    /// settles the title off the placeholder, the second append's generator
    /// call returns at its own guard rather than relabelling the thread.
    @Test @MainActor func secondVoiceAppendDoesNotRegenerate() async {
        let store = makeStore()

        store.appendVoiceTranscript(voiceSession(), postToHermes: false)
        let titled = await pollUntil { store.conversation?.title != Conversation.defaultTitle }
        #expect(titled)
        let firstTitle = store.conversation?.title

        store.appendVoiceTranscript(voiceSession(), postToHermes: false)
        _ = await pollUntil(timeout: .seconds(2)) { store.conversation?.title != firstTitle }

        #expect(store.conversation?.title == firstTitle)
    }
}
