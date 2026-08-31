import Testing
@testable import Talaria

/// **#418/#419 — the two voice log-line formatters are pure and pinned.**
///
/// Both instruments exist because the 2026-08-30 AirPods archive (#413's
/// probe) exposed questions no existing log line could answer: which route
/// and sample rate the capture actually rode (#418), and what zeroes the
/// assistant-playback counter mid-utterance (#419 — every recorded reading
/// of `audio.stopped after Nms` is 0). An instrument that under-specifies
/// its own discriminator is #419's defect all over again, so the load-bearing
/// parts of each line are pinned here rather than trusted.
@Suite("Voice instrument log lines (#418/#419)")
struct VoiceInstrumentLogLineTests {

    // MARK: - #419 assistant item arrival

    @Test("mid-playback arrival names the elapsed being destroyed")
    func midPlaybackArrivalNamesTheDestroyedElapsed() {
        let line = LiveVoiceSessionService.assistantItemArrivalLogDetail(
            eventType: "conversation.item.added",
            itemID: "item_B",
            currentItemID: "item_A",
            playbackElapsedMs: 2160
        )
        #expect(line.contains("MID-PLAYBACK"))
        #expect(line.contains("2160ms"))
    }

    @Test("idle arrival says idle and carries no mid-playback marker")
    func idleArrivalSaysIdle() {
        let line = LiveVoiceSessionService.assistantItemArrivalLogDetail(
            eventType: "conversation.item.added",
            itemID: "item_B",
            currentItemID: "item_A",
            playbackElapsedMs: nil
        )
        #expect(line.contains("assistant idle"))
        #expect(!line.contains("MID-PLAYBACK"))
    }

    @Test("same item re-announced is distinguished from a new item")
    func sameItemReannouncementIsDistinguished() {
        let same = LiveVoiceSessionService.assistantItemArrivalLogDetail(
            eventType: "conversation.item.added",
            itemID: "item_A",
            currentItemID: "item_A",
            playbackElapsedMs: nil
        )
        let new = LiveVoiceSessionService.assistantItemArrivalLogDetail(
            eventType: "conversation.item.added",
            itemID: "item_B",
            currentItemID: "item_A",
            playbackElapsedMs: nil
        )
        #expect(same.contains("same item re-announced"))
        #expect(!same.contains("new item"))
        #expect(new.contains("new item"))
        #expect(new.contains("item_A"))  // the replaced id is named
        #expect(!new.contains("same item re-announced"))
    }

    @Test("the session's first assistant item says so")
    func firstItemOfTheSessionSaysSo() {
        let line = LiveVoiceSessionService.assistantItemArrivalLogDetail(
            eventType: "conversation.item.created",
            itemID: "item_A",
            currentItemID: nil,
            playbackElapsedMs: nil
        )
        #expect(line.contains("first assistant item"))
    }

    @Test("the event type rides the line — beta/GA double-fire is readable")
    func eventTypeRidesTheLine() {
        let line = LiveVoiceSessionService.assistantItemArrivalLogDetail(
            eventType: "conversation.item.created",
            itemID: "item_A",
            currentItemID: nil,
            playbackElapsedMs: nil
        )
        #expect(line.contains("conversation.item.created"))
    }

    // MARK: - #418 audio route

    @Test("route line carries every port type, port name, and the sample rate")
    func routeLineCarriesPortsAndSampleRate() {
        let line = LiveVoiceSessionService.audioRouteLogDetail(
            inputs: [(portType: "BluetoothHFP", portName: "AirPods Pro")],
            outputs: [(portType: "BluetoothA2DPOutput", portName: "AirPods Pro")],
            sampleRateHz: 16000.0
        )
        #expect(line.contains("BluetoothHFP"))
        #expect(line.contains("BluetoothA2DPOutput"))
        #expect(line.contains("AirPods Pro"))
        #expect(line.contains("16000Hz"))
    }

    @Test("multiple ports are all listed, none silently dropped")
    func multiplePortsAllListed() {
        let line = LiveVoiceSessionService.audioRouteLogDetail(
            inputs: [
                (portType: "MicrophoneBuiltIn", portName: "iPhone Microphone"),
                (portType: "BluetoothHFP", portName: "AirPods Pro"),
            ],
            outputs: [(portType: "Speaker", portName: "Speaker")],
            sampleRateHz: 48000.0
        )
        #expect(line.contains("MicrophoneBuiltIn"))
        #expect(line.contains("BluetoothHFP"))
        #expect(line.contains("48000Hz"))
    }

    @Test("an empty input list is stated, not rendered as blank")
    func emptyInputListIsStated() {
        let line = LiveVoiceSessionService.audioRouteLogDetail(
            inputs: [],
            outputs: [(portType: "Speaker", portName: "Speaker")],
            sampleRateHz: 48000.0
        )
        #expect(line.contains("in=[none]"))
    }
}
