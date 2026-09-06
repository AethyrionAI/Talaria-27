import Foundation
import Testing
@testable import Talaria

/// #1 — locally composed voice-session hand-off: the transcript messages are
/// built on-device from the TalkStore snapshot (no relay), and the optional
/// Sessions-API context turn is plain text.
struct VoiceTranscriptTests {

    private func makeSession(
        transcript: [TranscriptItem],
        duration: TimeInterval = 83
    ) -> CompletedVoiceSession {
        CompletedVoiceSession(
            voiceSessionId: UUID(),
            duration: duration,
            turnCount: transcript.count,
            transcript: transcript,
            engine: .realtime
        )
    }

    // MARK: Message composition

    @Test func composesBannerAndSpokenTurns() {
        let session = makeSession(transcript: [
            TranscriptItem(speaker: .user, text: "What's the weather?"),
            TranscriptItem(speaker: .hermes, text: "Sunny and 22 degrees."),
        ])

        let messages = ChatStore.voiceTranscriptMessages(from: session)

        #expect(messages.count == 3)
        #expect(messages[0].sender == .system)
        #expect(messages[0].content == "[Voice session ended]")
        #expect(messages[0].voiceSessionDuration == 83)
        #expect(messages[1].sender == .voiceUser)
        #expect(messages[1].content == "What's the weather?")
        #expect(messages[2].sender == .voiceHermes)
        #expect(messages[2].content == "Sunny and 22 degrees.")
    }

    @Test func dropsPartialEmptyAndSystemItems() {
        let session = makeSession(transcript: [
            TranscriptItem(speaker: .system, text: "Session connected"),
            TranscriptItem(speaker: .user, text: "Hello", isPartial: true),
            TranscriptItem(speaker: .user, text: "   "),
            TranscriptItem(speaker: .user, text: "Hello there"),
            TranscriptItem(speaker: .hermes, text: "Hi!"),
        ])

        let messages = ChatStore.voiceTranscriptMessages(from: session)

        #expect(messages.count == 3)
        #expect(messages.filter(\.isVoiceTranscript).count == 2)
    }

    @Test func emptySessionComposesNothing() {
        // Image-only / system-only sessions must not leave a dangling banner.
        let session = makeSession(transcript: [
            TranscriptItem(speaker: .system, text: "Session connected"),
            TranscriptItem(speaker: .user, text: "", imageData: Data([0xFF])),
        ])

        #expect(ChatStore.voiceTranscriptMessages(from: session).isEmpty)
        #expect(ChatStore.voiceTranscriptTurnText(from: session).isEmpty)
    }

    // MARK: Sessions-API context turn

    @Test func contextTurnLabelsSpeakersAndSkipsNoise() {
        let session = makeSession(transcript: [
            TranscriptItem(speaker: .system, text: "Session connected"),
            TranscriptItem(speaker: .user, text: "Remind me to call Sam."),
            TranscriptItem(speaker: .hermes, text: "Done — reminder set.", isPartial: true),
            TranscriptItem(speaker: .hermes, text: "Done — reminder set."),
        ])

        let turn = ChatStore.voiceTranscriptTurnText(from: session)

        #expect(turn.hasPrefix("[Voice session transcript"))
        #expect(turn.contains("User: Remind me to call Sam."))
        #expect(turn.contains("Talaria: Done — reminder set."))
        #expect(!turn.contains("Session connected"))
        // The partial duplicate is filtered — exactly one assistant line.
        #expect(turn.components(separatedBy: "Talaria:").count == 2)
    }

    // MARK: - #340 bar 340-F3 — the belt mines only the `User:` lines

    /// **The founding wrong-value shape, through the voice door.** The user
    /// asks for a reminder and names NO time; Talaria's own earlier line names
    /// one. The whole transcript is what `appendVoiceTranscript` POSTs, so
    /// without this filter the card comes back carrying the ASSISTANT's date —
    /// a time the user never asked for, on a reminder they did.
    ///
    /// Scored where it matters — through `resolvedDue`, the function that
    /// actually reads the belt's text — rather than only on the string helper,
    /// so the row fails if the two are ever wired up differently.
    @Test func theBeltNeverMinesAnAssistantLinesDate() {
        let session = makeSession(transcript: [
            TranscriptItem(speaker: .hermes, text: "Your dentist appointment is tomorrow at 4pm."),
            TranscriptItem(speaker: .user, text: "Remind me to call Sam."),
        ])
        let turn = ChatStore.voiceTranscriptTurnText(from: session)

        let belt = LocalChatBackend.beltUserText(from: turn)

        #expect(!belt.contains("Talaria:"), "an assistant line reached the belt")
        #expect(!belt.contains("4pm"), "the assistant's DATE reached the belt")
        #expect(belt.contains("Remind me to call Sam."), "the user's own line must survive")
        let resolution = ReminderCreateTool.resolvedDue(
            rawDue: "", userText: belt, now: Date())
        #expect(resolution.date == nil,
                "the user named no time — the card must stay dateless, got \(String(describing: resolution.date))")
        #expect(resolution.source == "none")
    }

    /// **The other half, and the reason the filter is not simply "return
    /// nothing".** A date the USER spoke still resolves — the voice path keeps
    /// the fallback, it just loses the assistant's half.
    @Test func theBeltStillMinesTheUsersOwnDate() {
        let session = makeSession(transcript: [
            TranscriptItem(speaker: .user, text: "Remind me to call Sam tomorrow at 4pm."),
            TranscriptItem(speaker: .hermes, text: "Done — reminder set."),
        ])
        let turn = ChatStore.voiceTranscriptTurnText(from: session)

        let belt = LocalChatBackend.beltUserText(from: turn)
        let resolution = ReminderCreateTool.resolvedDue(
            rawDue: "", userText: belt, now: Date())

        #expect(resolution.source == "userText",
                "the user's own spoken date must still resolve")
    }

    /// Several spoken user turns are JOINED, in order, with the labels
    /// stripped — the belt reads sentences, not a labelled log.
    @Test func everyUserLineIsJoinedAndTheLabelIsStripped() {
        let session = makeSession(transcript: [
            TranscriptItem(speaker: .user, text: "Hello."),
            TranscriptItem(speaker: .hermes, text: "Hi."),
            TranscriptItem(speaker: .user, text: "Remind me to call Sam."),
        ])
        let turn = ChatStore.voiceTranscriptTurnText(from: session)

        #expect(LocalChatBackend.beltUserText(from: turn) == "Hello.\nRemind me to call Sam.")
    }

    /// **A typed message is passed through BYTE-FOR-BYTE.** The filter keys on
    /// the transcript header, so an ordinary turn — including one that happens
    /// to contain the string `Talaria:` — is untouched. Without this the
    /// narrowing would reach every turn in the app and the #340 fallback would
    /// stop working on typed messages.
    @Test func anOrdinaryTypedMessageIsUnchanged() {
        let typed = "Remind me at 4 to ask Talaria: does it work?"

        #expect(LocalChatBackend.beltUserText(from: typed) == typed)
        #expect(LocalChatBackend.beltUserText(from: "") == "")
    }

    /// **A transcript with no user line yields "" and not the assistant's
    /// speech.** `nil` (not a transcript) and `""` (a transcript the user said
    /// nothing in) are different answers, and collapsing them would hand the
    /// belt exactly the text this bar exists to withhold.
    @Test func aTranscriptWithNoUserLineYieldsNothingRatherThanTheAssistants() {
        let session = makeSession(transcript: [
            TranscriptItem(speaker: .hermes, text: "Your dentist appointment is tomorrow at 4pm."),
        ])
        let turn = ChatStore.voiceTranscriptTurnText(from: session)

        #expect(LocalChatBackend.beltUserText(from: turn) == "")
        #expect(VoiceTranscriptFormat.userLines(in: turn) == "",
                "the shape was recognised — an empty string, never nil")
        #expect(VoiceTranscriptFormat.userLines(in: "Remind me at 4") == nil,
                "an ordinary message is not a transcript")
    }

    /// **The writer and the reader share one definition of the shape.** If
    /// `voiceTranscriptTurnText` ever stopped emitting
    /// `VoiceTranscriptFormat.header`, the reader would stop recognising a
    /// transcript and fail OPEN — every assistant line back in the belt, with
    /// nothing else red. This is the row that would catch it.
    @Test func theWriterEmitsTheHeaderTheReaderKeysOn() {
        let session = makeSession(transcript: [
            TranscriptItem(speaker: .user, text: "Remind me to call Sam."),
        ])

        let turn = ChatStore.voiceTranscriptTurnText(from: session)

        #expect(turn.hasPrefix(VoiceTranscriptFormat.header))
        #expect(turn.contains(VoiceTranscriptFormat.userPrefix + "Remind me to call Sam."))
    }

    /// The seam itself: `beginToolTurn` — the ONE call both production turn
    /// paths make — is what applies the filter. A source witness, because the
    /// paths need a live `LanguageModelSession` and cannot be driven here.
    ///
    /// It deliberately does NOT re-pin `beginToolTurn(userText: message)` in
    /// `send`/`streamTurn`; `ToolTurnUserTextTests` owns that, and 340-F3 was
    /// designed to leave those two lines byte-identical.
    @Test(.enabled(if: RepoSourceWitness.repoSourcesAreReadable))
    func theTurnSeamAppliesTheFilter() throws {
        let line = try RepoSourceWitness.soleLine(
            containing: "toolRelay?.beginTurn(userText:", in: RepoSourceWitness.backendPath)

        #expect(line.contains("Self.beltUserText(from:)"),
                "the turn seam must narrow the belt's text — 340-F3 — got: \(line)")
    }

    // MARK: Banner duration persistence

    @Test func voiceSessionDurationSurvivesCacheRoundTrip() throws {
        let banner = Message(
            sender: .system,
            content: "[Voice session ended]",
            status: .delivered,
            voiceSessionDuration: 42
        )

        let decoded = try JSONDecoder().decode(
            Message.self,
            from: JSONEncoder().encode(banner)
        )

        #expect(decoded.voiceSessionDuration == 42)
        #expect(decoded.content == "[Voice session ended]")
    }
}
