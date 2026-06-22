import SwiftUI

// MARK: - HUD effect modifiers
// Shared building blocks for the arc-reactor HUD: a glow/shadow knob (the
// design's `--glowK`) and a reduce-motion-aware continuous rotation used by the
// reactor orbs.

extension View {
    /// Outer cyan (or amber) glow. `intensity` maps to the design's `--glowK`.
    func hudGlow(
        _ color: Color = Design.Brand.accent,
        radius: CGFloat = 16,
        strength: Double = 0.4,
        intensity: Double = Design.Glow.k
    ) -> some View {
        shadow(color: color.opacity(strength * intensity), radius: radius)
    }
}

// MARK: - Continuous rotation

private struct ContinuousRotation: ViewModifier {
    let duration: Double
    let reverse: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var angle: Double = 0

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(angle))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                    angle = reverse ? -360 : 360
                }
            }
    }
}

extension View {
    /// Spin forever at a fixed period. Disabled under Reduce Motion.
    func continuousRotation(_ duration: Double, reverse: Bool = false) -> some View {
        modifier(ContinuousRotation(duration: duration, reverse: reverse))
    }
}

// MARK: - Pulsing opacity (telemetry blink / breathe)

private struct PulseEffect: ViewModifier {
    let animation: Animation
    let from: Double
    let to: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var active = false

    func body(content: Content) -> some View {
        content
            .opacity(active ? to : from)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(animation) { active = true }
            }
    }
}

extension View {
    /// Blink opacity between `from` and `to` forever. Disabled under Reduce Motion.
    func hudPulse(
        _ animation: Animation = Design.Motion.blink,
        from: Double = 1.0,
        to: Double = 0.25
    ) -> some View {
        modifier(PulseEffect(animation: animation, from: from, to: to))
    }
}

// MARK: - Letter spacing helper

extension View {
    /// Apply HUD tracking (kerning) to text-bearing views.
    func hudTracking(_ tracking: CGFloat) -> some View {
        self.tracking(tracking)
    }
}
