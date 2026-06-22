import SwiftUI

/// The Talaria arc-reactor orb: concentric rings (one slow spin, one reverse-spin
/// arc) around a glowing radial core. Sizes per the design — nav 30pt, panel 42pt,
/// onboarding 74pt, voice 232pt. See design/Talaria.dc.html.
///
/// All motion is reduce-motion-aware (each animated piece checks
/// `accessibilityReduceMotion`). The orb is decorative — marked accessibilityHidden.
struct ReactorOrb: View {

    enum Style {
        /// Just an outer ring + glowing core (header logo / small avatars).
        case minimal
        /// Outer ring + a reverse-spinning arc + core (chat avatar, panels).
        case standard
        /// Full onboarding hero — slow outer ring, reverse arc, bright core.
        case onboarding
        /// Voice link hero — ping halo, dashed ring, dual counter-rotating arcs,
        /// breathing core with a wide glow.
        case voice
    }

    let size: CGFloat
    var style: Style = .standard
    var glowIntensity: Double = Design.Glow.k

    var body: some View {
        ZStack {
            switch style {
            case .minimal:
                outerRing(opacity: 0.4, lineWidth: lw(0.033))
                    .continuousRotation(9)
                BreathingCore(diameter: size * 0.54, glowRadius: size * 0.35, glow: glowIntensity)

            case .standard:
                outerRing(opacity: 0.35, lineWidth: lw(0.033))
                    .continuousRotation(10)
                spinArc(inset: size * 0.13, lineWidth: lw(0.05))
                    .continuousRotation(4, reverse: true)
                BreathingCore(diameter: size * 0.40, glowRadius: size * 0.32, glow: glowIntensity)

            case .onboarding:
                outerRing(opacity: 0.3, lineWidth: lw(0.014))
                    .continuousRotation(14)
                spinArc(inset: size * 0.12, lineWidth: lw(0.027))
                    .continuousRotation(5, reverse: true)
                BreathingCore(diameter: size * 0.36, glowRadius: size * 0.36, glow: glowIntensity)

            case .voice:
                PingHalo(diameter: size)
                dashedRing(inset: size * 0.06)
                    .continuousRotation(26)
                spinArc(inset: size * 0.145, lineWidth: 2, trim: 0.28)
                    .continuousRotation(7, reverse: true)
                spinArc(inset: size * 0.22, lineWidth: 2, trim: 0.22)
                    .continuousRotation(5)
                VoiceCore(diameter: size * 0.36, glowRadius: size * 0.26, glow: glowIntensity)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    // MARK: - Static pieces

    private func lw(_ fraction: CGFloat) -> CGFloat { max(1, size * fraction) }

    private func outerRing(opacity: Double, lineWidth: CGFloat) -> some View {
        Circle()
            .strokeBorder(Design.Colors.accentTint(opacity), lineWidth: lineWidth)
            .frame(width: size, height: size)
    }

    /// A bright cyan arc (≈ top quadrant) — the visibly spinning element.
    private func spinArc(inset: CGFloat, lineWidth: CGFloat, trim: CGFloat = 0.25) -> some View {
        Circle()
            .trim(from: 0, to: trim)
            .stroke(Design.Brand.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .frame(width: size - inset * 2, height: size - inset * 2)
    }

    private func dashedRing(inset: CGFloat) -> some View {
        Circle()
            .strokeBorder(
                Design.Colors.accentTint(0.3),
                style: StrokeStyle(lineWidth: 1, dash: [4, 5])
            )
            .frame(width: size - inset * 2, height: size - inset * 2)
    }
}

// MARK: - Animated subviews (isolated state per element)

private struct BreathingCore: View {
    let diameter: CGFloat
    let glowRadius: CGFloat
    let glow: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(Design.Brand.reactorCore)
            .frame(width: diameter, height: diameter)
            .scaleEffect(pulse ? 1.05 : 1.0)
            .hudGlow(Design.Brand.accent, radius: glowRadius, strength: 0.85, intensity: glow)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(Design.Motion.reactorBreathe) { pulse = true }
            }
    }
}

private struct VoiceCore: View {
    let diameter: CGFloat
    let glowRadius: CGFloat
    let glow: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Color(hex: 0xE2FBFD), Design.Brand.accent, Color(hex: 0x0F5867)],
                    center: UnitPoint(x: 0.5, y: 0.38),
                    startRadius: 0,
                    endRadius: diameter * 0.6
                )
            )
            .frame(width: diameter, height: diameter)
            .overlay(
                Circle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: diameter, height: diameter)
                    .blur(radius: diameter * 0.18)
            )
            .scaleEffect(pulse ? 1.05 : 1.0)
            .hudGlow(Design.Brand.accent, radius: glowRadius, strength: 0.7, intensity: glow)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(Design.Motion.reactorBreathe) { pulse = true }
            }
    }
}

private struct PingHalo: View {
    let diameter: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expand = false

    var body: some View {
        Circle()
            .strokeBorder(Design.Colors.accentTint(0.18), lineWidth: 1)
            .frame(width: diameter, height: diameter)
            .scaleEffect(reduceMotion ? 1 : (expand ? 1.0 : 0.7))
            .opacity(reduceMotion ? 0.3 : (expand ? 0 : 0.7))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 3).repeatForever(autoreverses: false)) {
                    expand = true
                }
            }
    }
}
