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
            transcript: transcript
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
        #expect(turn.contains("Hermes: Done — reminder set."))
        #expect(!turn.contains("Session connected"))
        // The partial duplicate is filtered — exactly one Hermes line.
        #expect(turn.components(separatedBy: "Hermes:").count == 2)
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
