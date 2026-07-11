import AVFoundation
import Foundation

// MARK: - Talk-mode preflight + mic-health primitives (#84)
//
// The #82 evening: the overlay rendered a live "LISTENING" state on top of a
// dead microphone — transport connectivity was treated as proof of audio.
// These helpers keep the two claims separate:
//   • `TalkMicPreflight` — standardized, actionable permission messaging
//     shared by both voice engines, plus the predicate the overlay uses to
//     decide when a blocked reason deserves an "OPEN SETTINGS" deep link.
//     `classify(permissionGranted:inputAvailable:)` is the three-state
//     decision core: permission denied, permissions OK but no reachable mic
//     input (the #82 wedge shape — reboot guidance, NOT a Settings link),
//     or clear to start.
//   • `MicFlatlineRule` — the pure decision core of the runtime tripwire:
//     N seconds into a connected, unmuted session with zero speech evidence
//     is a mic-health problem worth a hint, not silent listening.
//   • `TalkAudioRoute` — human-readable current-route summary (a stale
//     Bluetooth route with a dead mic was the other live #82 suspect).

enum TalkMicPreflight {
    /// Actionable wording — names the switch and where to flip it.
    static let microphoneDeniedMessage =
        "Microphone access is off — enable it for Talaria in Settings."
    static let speechDeniedMessage =
        "Speech Recognition permission is off — enable it for Talaria in Settings."
    /// The third preflight state: permission granted, but the capture side is
    /// dead (no reachable mic input). Settings can't fix this — the known
    /// recovery for a wedged capture stack (#82) is a reboot, so that's the
    /// guidance. Wording deliberately avoids claiming WHY the mic is gone.
    static let noMicInputMessage =
        "Microphone permission is on, but no mic input is reachable — try rebooting this iPhone."

    /// The preflight's three-way verdict on the microphone.
    enum MicCheck: Equatable {
        /// Permission granted and an input is reachable — clear to start.
        case ok
        /// The user (or a profile) turned the permission off — the overlay
        /// pairs the message with an OPEN SETTINGS deep link.
        case permissionDenied
        /// Permissions are fine but no mic input exists right now. Distinct
        /// from `permissionDenied` so the overlay never sends the user to
        /// Settings for a switch that is already on.
        case noInputAvailable
    }

    /// Pure decision core shared by both voice engines. `permissionGranted`
    /// wins: with the permission off, input availability is unknowable and
    /// the Settings link is the right action.
    static func classify(permissionGranted: Bool, inputAvailable: Bool) -> MicCheck {
        guard permissionGranted else { return .permissionDenied }
        return inputAvailable ? .ok : .noInputAvailable
    }

    /// Live capture-side availability, for the `inputAvailable` argument.
    /// `isInputAvailable` is the best app-visible signal for "a mic exists
    /// and the system will let us at it"; whether the #82 seed wedge trips it
    /// is exactly what the post-seed device checklist verifies.
    @MainActor
    static func isMicInputAvailable() -> Bool {
        AVAudioSession.sharedInstance().isInputAvailable
    }

    /// Engine-level backstop for the #82 wedge: a wedged capture stack can
    /// pass `isInputAvailable` (a route exists) while the engine's input node
    /// reports a degenerate hardware format (0 Hz / 0 channels). Installing a
    /// tap with that format raises an Objective-C NSException that Swift
    /// cannot catch — a hard crash. Both voice engines gate their tap install
    /// on this check and surface `noMicInputMessage` (reboot guidance)
    /// instead. Pure so it's unit-testable.
    static func isViableCaptureFormat(sampleRate: Double, channelCount: UInt32) -> Bool {
        sampleRate > 0 && channelCount > 0
    }

    /// Should the talk overlay offer the system-Settings deep link for this
    /// blocked reason? Matches the standardized messages above plus the
    /// historical phrasings that shipped before #84.
    static func isPermissionActionable(_ reason: String) -> Bool {
        // The no-input state names the permission (as already ON) and the
        // microphone, so the keyword net below would catch it — but Settings
        // is a dead end there; reboot guidance stands alone.
        if reason == noMicInputMessage { return false }
        let lowered = reason.lowercased()
        return lowered.contains("microphone")
            || lowered.contains("permission")
            || lowered.contains("speech recognition")
            || lowered.contains("enable it for talaria")
    }
}

/// Pure decision core for the flatline tripwire. Engines arm a repeating
/// window after reaching `.connected`; each expiry asks this rule what to do.
enum MicFlatlineRule {
    /// How long a connected, unmuted session may run with zero speech
    /// evidence before the hint fires. Long enough that a user gathering
    /// their thoughts doesn't trip it; short enough to beat the "why is it
    /// ignoring me" abandonment window.
    static let window: Duration = .seconds(12)

    static let hintMessage =
        "No microphone signal detected — check the mic permission, mute, and audio route."

    enum Verdict: Equatable {
        /// Surface the mic-health hint.
        case flag
        /// Silence is expected (muted) — arm another window instead.
        case rearm
        /// Evidence arrived or the session is gone — stand down.
        case disarm
    }

    static func verdict(
        speechEvidence: Bool,
        isMuted: Bool,
        connectionState: TalkConnectionState
    ) -> Verdict {
        if speechEvidence || connectionState != .connected { return .disarm }
        if isMuted { return .rearm }
        return .flag
    }
}

enum TalkAudioRoute {
    /// "iPhone Microphone → Speaker" from raw route descriptions. Pure so
    /// it's unit-testable without an `AVAudioSession`.
    static func describe(
        inputs: [(name: String, portType: String)],
        outputs: [(name: String, portType: String)]
    ) -> String? {
        guard !inputs.isEmpty || !outputs.isEmpty else { return nil }
        let inputSide = inputs.isEmpty ? "no input" : inputs.map(\.name).joined(separator: " + ")
        let outputSide = outputs.isEmpty ? "no output" : outputs.map(\.name).joined(separator: " + ")
        return "\(inputSide) → \(outputSide)"
    }

    /// Live summary of the shared audio session's current route.
    @MainActor
    static func currentSummary() -> String? {
        let route = AVAudioSession.sharedInstance().currentRoute
        return describe(
            inputs: route.inputs.map { ($0.portName, $0.portType.rawValue) },
            outputs: route.outputs.map { ($0.portName, $0.portType.rawValue) }
        )
    }
}
