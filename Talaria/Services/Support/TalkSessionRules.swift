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
