import Foundation
import Testing
@testable import Talaria

/// #84 — talk-mode preflight + mic-health primitives: the pure flatline
/// verdict rule, the route formatter, and the overlay's permission-action
/// predicate (which must stay in lockstep with the engines' standardized
/// preflight wording). Live audio behavior is a device concern covered by
/// the OPEN_ITEMS #84 device checklist.
struct TalkPreflightTests {

    // MARK: - MicFlatlineRule

    @Test func flatlineFlagsConnectedUnmutedSilence() {
        #expect(MicFlatlineRule.verdict(
            speechEvidence: false,
            isMuted: false,
            connectionState: .connected
        ) == .flag)
    }

    @Test func flatlineRearmsWhileMuted() {
        // Muted silence is expected — the window re-arms instead of flagging
        // or standing down, so unmuted silence later still gets caught.
        #expect(MicFlatlineRule.verdict(
            speechEvidence: false,
            isMuted: true,
            connectionState: .connected
        ) == .rearm)
    }

    @Test func flatlineDisarmsOnSpeechEvidence() {
        #expect(MicFlatlineRule.verdict(
            speechEvidence: true,
            isMuted: false,
            connectionState: .connected
        ) == .disarm)
    }

    @Test func flatlineDisarmsWhenSessionIsGone() {
        for state: TalkConnectionState in [.idle, .checking, .ready, .connecting, .blocked, .failed] {
            #expect(MicFlatlineRule.verdict(
                speechEvidence: false,
                isMuted: false,
                connectionState: state
            ) == .disarm, "expected disarm for \(state)")
        }
    }

    @Test func flatlineEvidenceWinsOverMute() {
        #expect(MicFlatlineRule.verdict(
            speechEvidence: true,
            isMuted: true,
            connectionState: .connected
        ) == .disarm)
    }

    // MARK: - TalkAudioRoute.describe

    @Test func routeDescribesInputAndOutput() {
        let summary = TalkAudioRoute.describe(
            inputs: [(name: "iPhone Microphone", portType: "MicrophoneBuiltIn")],
            outputs: [(name: "Speaker", portType: "Speaker")]
        )
        #expect(summary == "iPhone Microphone → Speaker")
    }

    @Test func routeJoinsMultiplePortsPerSide() {
        let summary = TalkAudioRoute.describe(
            inputs: [
                (name: "WH-1000XM4", portType: "BluetoothHFP"),
                (name: "iPhone Microphone", portType: "MicrophoneBuiltIn"),
            ],
            outputs: [(name: "WH-1000XM4", portType: "BluetoothHFP")]
        )
        #expect(summary == "WH-1000XM4 + iPhone Microphone → WH-1000XM4")
    }

    @Test func routeIsHonestAboutMissingInput() {
        // The #82 suspect state: output routed somewhere, no capture side.
        let summary = TalkAudioRoute.describe(
            inputs: [],
            outputs: [(name: "Speaker", portType: "Speaker")]
        )
        #expect(summary == "no input → Speaker")
    }

    @Test func routeIsNilWhenRouteIsEmpty() {
        #expect(TalkAudioRoute.describe(inputs: [], outputs: []) == nil)
    }

    // MARK: - TalkMicPreflight.isPermissionActionable

    @Test func standardPreflightMessagesAreActionable() {
        // The overlay's OPEN SETTINGS gate must fire for the exact wording
        // the engines emit — a rename that breaks this loses the deep link.
        #expect(TalkMicPreflight.isPermissionActionable(TalkMicPreflight.microphoneDeniedMessage))
        #expect(TalkMicPreflight.isPermissionActionable(TalkMicPreflight.speechDeniedMessage))
    }

    @Test func historicalPermissionPhrasingsStayActionable() {
        #expect(TalkMicPreflight.isPermissionActionable("Microphone access is required for talk mode."))
        #expect(TalkMicPreflight.isPermissionActionable("Speech recognition permission is required for local voice."))
    }

    @Test func nonPermissionFailuresAreNotActionable() {
        #expect(!TalkMicPreflight.isPermissionActionable("Your Hermes host is offline."))
        #expect(!TalkMicPreflight.isPermissionActionable("OpenAI Realtime session creation failed."))
    }

    // MARK: - Snapshot plumbing

    @Test func snapshotDefaultsLeaveMicHealthUnset() {
        // Existing construction sites (mocks, CarPlay, widgets) compile
        // against defaults — and defaults must read as "healthy/unknown",
        // never as a warning.
        let snapshot = TalkSessionSnapshot(
            voiceState: .idle,
            connectionState: .idle,
            transcriptItems: [],
            sessionDuration: 0,
            isMuted: false,
            blockedReason: nil,
            statusMessage: nil,
            canStartSession: true,
            latencyMetrics: TalkLatencyMetrics(),
            voiceSessionID: nil
        )
        #expect(snapshot.micHealthHint == nil)
        #expect(snapshot.audioRouteSummary == nil)
    }
}
