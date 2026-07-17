import AVFoundation
import Foundation

// MARK: - Voice-residuals lane decision cores (#118 / #119)
//
// Residuals from the #82 confirm run, pure so they're testable without a
// device:
//   • `TalkBackgroundRule` — #118 (privacy): leaving the app must not leave
//     the capture chain (and the system mic indicator) live. There is no
//     background-audio voice mode in this app; backgrounding ends the
//     session. CarPlay is the one exemption — CarPlay voice runs with the
//     phone UI backgrounded by design (#19), and the CarPlay scene contract
//     explicitly keeps the session alive across connect/disconnect.
//   • `RealtimeErrorRule` — #119a: which realtime `error` events are normal
//     races to swallow, and which are real failures that must surface. A
//     cancel racing an already-completed response is a no-op, not a session
//     failure — the old handler bubbled the backend string into the session
//     UI AND flagged the connection `.failed`, which is also what wedged the
//     header on CONNECTING (#119b) mid-conversation.

enum TalkBackgroundRule {
    /// True when a `didEnterBackground` event should end the voice session
    /// through the user-end path. Both engines answer to this rule: the
    /// realtime engine survives backgrounding (UIBackgroundModes `audio`
    /// keeps WebRTC streaming), and the native pipeline's capture chain
    /// outlives the scene — the mic indicator stays lit either way.
    static func shouldEndSession(isSessionActive: Bool, routeHasCarAudio: Bool) -> Bool {
        isSessionActive && !routeHasCarAudio
    }
}

enum RealtimeErrorRule {
    enum Disposition: Equatable {
        /// #119a: a barge-in/manual cancel raced a response that had already
        /// completed server-side. The connection is healthy and the
        /// conversation continues — log `.notice`, never touch session state.
        case swallowNoOpCancel
        /// Our own `response.create` after MCP tool completion raced an
        /// already-active response (pre-existing suppression, now classified).
        case swallowResponseCreateRace
        /// A real failure — surface it honestly.
        case surface
    }

    /// Classifies a realtime `error` event by its `code` and `message`.
    /// Matching is deliberately narrow — anything unrecognized fails open to
    /// `.surface` (an unnecessary banner beats a silently eaten failure).
    static func disposition(code: String?, message: String) -> Disposition {
        let lowered = message.lowercased()
        if code == "response_cancel_not_active"
            || (lowered.contains("cancel") && lowered.contains("no active response")) {
            return .swallowNoOpCancel
        }
        if lowered.contains("active response in progress") {
            return .swallowResponseCreateRace
        }
        return .surface
    }
}
