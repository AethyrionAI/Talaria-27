import SwiftUI

/// The arc-reactor voice hero. Wraps `ReactorOrb(style: .voice)` and maps the
/// existing voice/connection state onto the reactor's glow intensity.
///
/// The init signature is preserved (referenced from TalkModeScreen and
/// VoiceOverlayScreen). The orb itself is decorative — ReactorOrb is already
/// `accessibilityHidden`, so this wrapper carries the status accessibilityLabel.
struct VoiceOrb: View {
    let voiceState: VoiceState
    let connectionState: TalkConnectionState

    private var isConnected: Bool {
        connectionState == .connected
    }

    /// Brighter glow when Hermes is speaking, dim when disconnected.
    private var glowIntensity: Double {
        guard isConnected else { return 0.35 }
        switch voiceState {
        case .speaking: return 1.4
        case .thinking: return 1.1
        case .listening: return 1.0
        default: return 0.7
        }
    }

    var body: some View {
        ReactorOrb(
            size: Design.Size.voiceOrbSize,
            style: .voice,
            // Per-state glow scaled by the user's Glow Intensity pref (default 1.0).
            glowIntensity: glowIntensity * Design.Glow.k
        )
        .opacity(isConnected ? 1.0 : 0.55)
        .animation(Design.Motion.gentle, value: glowIntensity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Voice status: \(voiceState.displayLabel)")
    }
}
