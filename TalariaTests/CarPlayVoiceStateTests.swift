import Foundation
import Testing
@testable import Talaria

/// #19 — the pure TalkStore → CPVoiceControlTemplate state mapping, including
/// the new blocked surface for a failed auto-start. Template plumbing and the
/// observation loop are CarPlay Simulator concerns (OPEN_ITEMS checklist).
struct CarPlayVoiceStateTests {

    @Test func inactiveWithNoBlockIsIdle() {
        #expect(CarPlayVoiceManager.stateIdentifier(
            isSessionActive: false,
            canStartSession: true,
            blockedReason: nil,
            connectionState: .idle,
            voiceState: .idle
        ) == CarPlayVoiceManager.StateID.idle)
    }

    @Test func failedReadinessSurfacesBlockedState() {
        #expect(CarPlayVoiceManager.stateIdentifier(
            isSessionActive: false,
            canStartSession: false,
            blockedReason: "Could not reach the relay.",
            connectionState: .failed,
            voiceState: .disconnected
        ) == CarPlayVoiceManager.StateID.blocked)
    }

    @Test func blockedNeedsBothSignals() {
        // A reason with canStartSession still true (e.g. stale message after
        // recovery) must not trap the car UI in blocked.
        #expect(CarPlayVoiceManager.stateIdentifier(
            isSessionActive: false,
            canStartSession: true,
            blockedReason: "Old failure",
            connectionState: .ready,
            voiceState: .idle
        ) == CarPlayVoiceManager.StateID.idle)
    }

    @Test func connectingStatesWinWhileSessionEstablishes() {
        for state in [TalkConnectionState.connecting, .checking] {
            #expect(CarPlayVoiceManager.stateIdentifier(
                isSessionActive: true,
                canStartSession: true,
                blockedReason: nil,
                connectionState: state,
                voiceState: .thinking
            ) == CarPlayVoiceManager.StateID.connecting)
        }
    }

    @Test func voiceStatesMapOnceConnected() {
        let cases: [(VoiceState, String)] = [
            (.listening, CarPlayVoiceManager.StateID.listening),
            (.thinking, CarPlayVoiceManager.StateID.thinking),
            (.speaking, CarPlayVoiceManager.StateID.speaking),
            (.interrupted, CarPlayVoiceManager.StateID.listening),
            (.idle, CarPlayVoiceManager.StateID.idle),
            (.disconnected, CarPlayVoiceManager.StateID.idle),
        ]
        for (voiceState, expected) in cases {
            #expect(CarPlayVoiceManager.stateIdentifier(
                isSessionActive: true,
                canStartSession: true,
                blockedReason: nil,
                connectionState: .connected,
                voiceState: voiceState
            ) == expected)
        }
    }

    @Test func blockedTitleTrimsAndCaps() {
        #expect(CarPlayVoiceManager.blockedTitle(reason: nil) == nil)
        #expect(CarPlayVoiceManager.blockedTitle(reason: "   ") == nil)
        #expect(CarPlayVoiceManager.blockedTitle(reason: " Relay down ") == "Relay down")
        let long = String(repeating: "x", count: 200)
        #expect(CarPlayVoiceManager.blockedTitle(reason: long)?.count == 80)
    }
}
