import SwiftUI

struct VoiceOrb: View {
    let voiceState: VoiceState
    let connectionState: TalkConnectionState

    @State private var pulseScale: CGFloat = 1.0

    /// Always blue when connected, muted grey otherwise.
    private var orbColor: Color {
        switch connectionState {
        case .connected: .blue
        default: .secondary
        }
    }

    private var isActive: Bool {
        connectionState == .connected
    }

    var body: some View {
        ZStack {
            // Outer pulse ring — only visible when Hermes is responding
            Circle()
                .fill(orbColor.opacity(0.15))
                .frame(width: Design.Size.voiceOrbSize * 1.3, height: Design.Size.voiceOrbSize * 1.3)
                .scaleEffect(pulseScale)

            // Middle ring
            Circle()
                .fill(orbColor.opacity(0.1))
                .frame(width: Design.Size.voiceOrbSize * 1.15, height: Design.Size.voiceOrbSize * 1.15)
                .scaleEffect(pulseScale * 0.95)

            // Main orb
            Circle()
                .fill(orbColor.gradient)
                .frame(width: Design.Size.voiceOrbSize, height: Design.Size.voiceOrbSize)
                .glassEffect(.regular, in: Circle())
                .overlay {
                    Image(systemName: "mic.fill")
                        .font(.system(size: Design.Size.iconHero, weight: .light))
                        .foregroundStyle(.white)
                }
        }
        .onChange(of: voiceState) { updateAnimation() }
        .onChange(of: connectionState) { updateAnimation() }
        .onAppear { updateAnimation() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Voice status: \(voiceState.displayLabel)")
    }

    private func updateAnimation() {
        switch voiceState {
        case .speaking:
            // Pulsing when Hermes is talking
            withAnimation(Design.Motion.breathe) { pulseScale = 1.12 }
        case .thinking:
            // Gentle pulse when processing
            withAnimation(Design.Motion.pulse) { pulseScale = 1.04 }
        default:
            // Static when idle, listening, or disconnected
            withAnimation(Design.Motion.gentle) { pulseScale = 1.0 }
        }
    }
}
