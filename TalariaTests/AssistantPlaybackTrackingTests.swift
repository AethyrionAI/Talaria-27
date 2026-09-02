import Foundation
import Testing
@testable import Talaria

/// **#419-B — the assistant-playback counter follows the AUDIO BUFFER, not the
/// transcript.**
///
/// Realtime emits `response.output_audio_transcript.done` when text generation
/// completes, seconds ahead of audio playout. Until #419-B, `finalizeAssistantText`
/// treated that event as the end of the utterance: it nil'd the playback stamp,
/// nil'd the live item id, and flipped the state to `.listening` while the
/// buffer was still draining. Every `audio.stopped after Nms` reading in the
/// project's archives was 0 because of it, a barge-in in the tail of any
/// utterance sent no `conversation.item.truncate` at all, and the interruption
/// guard was blind for the whole tail. These pins drive the service through the
/// real event order and read the same counter the log line prints.
@Suite("Assistant playback tracking survives transcript completion (#419-B)")
struct AssistantPlaybackTrackingTests {

    private final class SentEvents: @unchecked Sendable {
        var payloads: [[String: Any]] = []
    }

    @MainActor
    private func makeService() -> (LiveVoiceSessionService, SentEvents) {
        let sent = SentEvents()
        let service = LiveVoiceSessionService(
            realtimeEventTransportOverride: { data in
                guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return false
                }
                sent.payloads.append(payload)
                return true
            }
        )
        service.connectionState = .connected
        return (service, sent)
    }

    /// The server's order for one spoken response, up to and including the
    /// event under test. Audio is playing when this returns.
    @MainActor
    private func beginSpokenResponse(_ service: LiveVoiceSessionService, itemID: String = "item_419") {
        service.handleDataChannelEvent(["type": "response.created", "response": ["id": "resp_419"]])
        service.handleDataChannelEvent([
            "type": "conversation.item.added",
            "item": ["id": itemID, "role": "assistant", "type": "message"],
        ])
        service.handleDataChannelEvent(["type": "response.output_audio_transcript.delta", "delta": "Hello there."])
        service.handleDataChannelEvent(["type": "output_audio_buffer.started"])
    }

    // MARK: - 419-B2

    @Test("transcript-done mid-playback does not zero the running counter")
    @MainActor
    func transcriptDoneMidPlaybackKeepsTheCounterRunning() async throws {
        let (service, _) = makeService()
        beginSpokenResponse(service)
        try await Task.sleep(for: .milliseconds(40))

        service.handleDataChannelEvent(["type": "response.output_audio_transcript.done", "transcript": "Hello there."])
        try await Task.sleep(for: .milliseconds(40))

        // The same value the `#138 audio.stopped after Nms` line prints.
        #expect(service.currentAssistantAudioPlaybackMilliseconds() >= 80)
    }

    @Test("audio.stopped after transcript-done banks the real elapsed, not 0")
    @MainActor
    func audioStoppedAfterTranscriptDoneBanksTheRealElapsed() async throws {
        let (service, _) = makeService()
        beginSpokenResponse(service)
        try await Task.sleep(for: .milliseconds(40))
        service.handleDataChannelEvent(["type": "response.output_audio_transcript.done", "transcript": "Hello there."])
        try await Task.sleep(for: .milliseconds(40))

        service.handleDataChannelEvent(["type": "output_audio_buffer.stopped"])

        #expect(service.currentAssistantAudioPlaybackMilliseconds() >= 80)
        #expect(service.voiceState == .listening)
    }

    // MARK: - 419-B3

    @Test("a barge-in after transcript-done still truncates the live item with the heard milliseconds")
    @MainActor
    func bargeInAfterTranscriptDoneStillTruncates() async throws {
        let (service, sent) = makeService()
        beginSpokenResponse(service, itemID: "item_tail")
        try await Task.sleep(for: .milliseconds(40))
        service.handleDataChannelEvent(["type": "response.output_audio_transcript.done", "transcript": "Hello there."])
        try await Task.sleep(for: .milliseconds(40))

        service.handleDataChannelEvent(["type": "input_audio_buffer.speech_started"])

        let truncate = try #require(sent.payloads.first { $0["type"] as? String == "conversation.item.truncate" })
        #expect(truncate["item_id"] as? String == "item_tail")
        let audioEndMs = try #require(truncate["audio_end_ms"] as? Int)
        #expect(audioEndMs >= 80)
    }

    // MARK: - 419-B4

    @Test("transcript-done mid-playback leaves the state speaking until the buffer stops")
    @MainActor
    func transcriptDoneMidPlaybackKeepsSpeakingUntilTheBufferStops() async throws {
        let (service, _) = makeService()
        beginSpokenResponse(service)

        service.handleDataChannelEvent(["type": "response.output_audio_transcript.done", "transcript": "Hello there."])
        #expect(service.voiceState == .speaking)

        service.handleDataChannelEvent(["type": "output_audio_buffer.stopped"])
        #expect(service.voiceState == .listening)
    }

    // MARK: - 419-B5 (control)

    @Test("an audio-less response still finalizes to listening and arms nothing")
    @MainActor
    func audioLessResponseStillFinalizesToListening() async throws {
        let (service, sent) = makeService()
        service.handleDataChannelEvent(["type": "response.created", "response": ["id": "resp_text"]])
        service.handleDataChannelEvent([
            "type": "conversation.item.added",
            "item": ["id": "item_text", "role": "assistant", "type": "message"],
        ])
        service.handleDataChannelEvent(["type": "response.output_text.delta", "delta": "Text only."])

        service.handleDataChannelEvent(["type": "response.output_text.done", "text": "Text only."])
        #expect(service.voiceState == .listening)

        service.handleDataChannelEvent(["type": "input_audio_buffer.speech_started"])
        #expect(sent.payloads.isEmpty)
    }
}
