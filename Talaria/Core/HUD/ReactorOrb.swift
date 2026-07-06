import SwiftUI

/// The Talaria reactor orb. Sizes per the design — nav 30pt, panel 42pt,
/// onboarding 74pt, voice 232pt. See design/Talaria.dc.html.
///
/// The four `Style` presets are the public API; the *drawing* re-skins per
/// theme via `palette.orbStyle` (#49) — the theme data selects one of the
/// compositions below (same pattern as `ThemeTextureView`), so a new catalog
/// theme reuses an existing orb without touching this file:
///  • arcReactor   — the original rings + glowing core (Deep Field; unchanged).
///  • forgeSun     — heavier concentric rings around an ember core.
///  • crtCrosshair — thin ring + crosshair ticks, CRT-bloomed core.
///  • paperReel    — mechanical reel: sprocket holes + tick ring + inked hub.
///
/// All motion is reduce-motion-aware (each animated piece checks
/// `accessibilityReduceMotion`). The orb is decorative — marked accessibilityHidden.
struct ReactorOrb: View {

    enum Style {
        /// Just an outer ring + core (header logo / small avatars).
        case minimal
        /// Outer ring + a spinning arc + core (chat avatar, panels).
        case standard
        /// Full onboarding hero — slow outer ring, arc, bright core.
        case onboarding
        /// Voice link hero — ping halo, dashed ring, dual counter-rotating
        /// arcs, breathing core with a wide glow.
        case voice
    }

    let size: CGFloat
    var style: Style = .standard
    var glowIntensity: Double = Design.Glow.k

    var body: some View {
        ZStack {
            switch ThemeRuntime.shared.palette.orbStyle {
            case .arcReactor: arcReactorLayers
            case .forgeSun: forgeSunLayers
            case .crtCrosshair: crtCrosshairLayers
            case .paperReel: paperReelLayers
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    // MARK: - Arc reactor (Deep Field's original — do not retune)

    @ViewBuilder private var arcReactorLayers: some View {
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

    // MARK: - Forge sun (heavier rings, ember core)

    @ViewBuilder private var forgeSunLayers: some View {
        switch style {
        case .minimal:
            outerRing(opacity: 0.45, lineWidth: lw(0.05))
                .continuousRotation(9)
            BreathingCore(diameter: size * 0.54, glowRadius: size * 0.35, glow: glowIntensity)

        case .standard:
            outerRing(opacity: 0.4, lineWidth: lw(0.05))
                .continuousRotation(10)
            ring(inset: size * 0.24, opacity: 0.18, lineWidth: lw(0.033))
            spinArc(inset: size * 0.13, lineWidth: lw(0.07))
                .continuousRotation(4, reverse: true)
            BreathingCore(diameter: size * 0.40, glowRadius: size * 0.32, glow: glowIntensity)

        case .onboarding:
            outerRing(opacity: 0.35, lineWidth: lw(0.022))
                .continuousRotation(14)
            ring(inset: size * 0.20, opacity: 0.15, lineWidth: lw(0.014))
            spinArc(inset: size * 0.12, lineWidth: lw(0.04))
                .continuousRotation(5, reverse: true)
            BreathingCore(diameter: size * 0.38, glowRadius: size * 0.38, glow: glowIntensity)

        case .voice:
            PingHalo(diameter: size)
            dashedRing(inset: size * 0.06, dash: [7, 4])
                .continuousRotation(30)
            ring(inset: size * 0.13, opacity: 0.2, lineWidth: 2)
            spinArc(inset: size * 0.145, lineWidth: 3, trim: 0.30)
                .continuousRotation(8, reverse: true)
            spinArc(inset: size * 0.23, lineWidth: 3, trim: 0.20)
                .continuousRotation(5)
            VoiceCore(diameter: size * 0.38, glowRadius: size * 0.28, glow: glowIntensity)
        }
    }

    // MARK: - CRT crosshair (static ticks, bloomed core)

    @ViewBuilder private var crtCrosshairLayers: some View {
        switch style {
        case .minimal:
            outerRing(opacity: 0.5, lineWidth: 1)
            radialTicks(count: 4, length: size * 0.14, thickness: 1.5, opacity: 0.8, edgeInset: 0)
            BreathingCore(diameter: size * 0.46, glowRadius: size * 0.4, glow: glowIntensity)

        case .standard:
            outerRing(opacity: 0.45, lineWidth: 1)
            radialTicks(count: 4, length: size * 0.14, thickness: 1.5, opacity: 0.8, edgeInset: 0)
            spinArc(inset: size * 0.16, lineWidth: 1.5)
                .continuousRotation(6, reverse: true)
            BreathingCore(diameter: size * 0.36, glowRadius: size * 0.36, glow: glowIntensity)

        case .onboarding:
            outerRing(opacity: 0.4, lineWidth: 1)
            radialTicks(count: 4, length: size * 0.12, thickness: 2, opacity: 0.8, edgeInset: 0)
            spinArc(inset: size * 0.15, lineWidth: 1.5)
                .continuousRotation(7, reverse: true)
            BreathingCore(diameter: size * 0.34, glowRadius: size * 0.4, glow: glowIntensity)

        case .voice:
            PingHalo(diameter: size)
            dashedRing(inset: size * 0.06, dash: [1, 5])
                .continuousRotation(30)
            radialTicks(count: 4, length: size * 0.10, thickness: 2, opacity: 0.85, edgeInset: size * 0.02)
            spinArc(inset: size * 0.17, lineWidth: 2, trim: 0.24)
                .continuousRotation(7, reverse: true)
            VoiceCore(diameter: size * 0.34, glowRadius: size * 0.3, glow: glowIntensity)
        }
    }

    // MARK: - Paper reel (sprockets, ticks, inked hub)

    @ViewBuilder private var paperReelLayers: some View {
        switch style {
        case .minimal:
            outerRing(opacity: 0.55, lineWidth: 1.5)
            PaperHub(diameter: size * 0.5)

        case .standard:
            outerRing(opacity: 0.55, lineWidth: 1.5)
            radialTicks(count: 12, length: size * 0.09, thickness: 1, opacity: 0.45, edgeInset: size * 0.08)
                .continuousRotation(30)
            PaperHub(diameter: size * 0.42)

        case .onboarding:
            outerRing(opacity: 0.55, lineWidth: 1.5)
            sprocketHoles(count: 8, holeRadius: size * 0.035, edgeInset: size * 0.12)
                .continuousRotation(36)
            radialTicks(count: 12, length: size * 0.07, thickness: 1, opacity: 0.4, edgeInset: size * 0.26)
                .continuousRotation(36)
            PaperHub(diameter: size * 0.34)

        case .voice:
            PingHalo(diameter: size)
            outerRing(opacity: 0.55, lineWidth: 1.5)
            sprocketHoles(count: 10, holeRadius: size * 0.03, edgeInset: size * 0.10)
                .continuousRotation(40)
            radialTicks(count: 16, length: size * 0.06, thickness: 1, opacity: 0.4, edgeInset: size * 0.22)
                .continuousRotation(28, reverse: true)
            PaperHub(diameter: size * 0.34)
        }
    }

    // MARK: - Shared pieces

    private func lw(_ fraction: CGFloat) -> CGFloat { max(1, size * fraction) }

    private func outerRing(opacity: Double, lineWidth: CGFloat) -> some View {
        Circle()
            .strokeBorder(Design.Colors.accentTint(opacity), lineWidth: lineWidth)
            .frame(width: size, height: size)
    }

    /// A static accent ring inset from the rim.
    private func ring(inset: CGFloat, opacity: Double, lineWidth: CGFloat) -> some View {
        Circle()
            .strokeBorder(Design.Colors.accentTint(opacity), lineWidth: lineWidth)
            .frame(width: size - inset * 2, height: size - inset * 2)
    }

    /// A bright accent arc (≈ top quadrant) — the visibly spinning element.
    private func spinArc(inset: CGFloat, lineWidth: CGFloat, trim: CGFloat = 0.25) -> some View {
        Circle()
            .trim(from: 0, to: trim)
            .stroke(Design.Brand.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .frame(width: size - inset * 2, height: size - inset * 2)
    }

    private func dashedRing(inset: CGFloat, dash: [CGFloat] = [4, 5]) -> some View {
        Circle()
            .strokeBorder(
                Design.Colors.accentTint(0.3),
                style: StrokeStyle(lineWidth: 1, dash: dash)
            )
            .frame(width: size - inset * 2, height: size - inset * 2)
    }

    /// Evenly spaced radial tick marks just inside the rim (crosshair when
    /// count == 4, reel graduations at higher counts).
    private func radialTicks(
        count: Int,
        length: CGFloat,
        thickness: CGFloat,
        opacity: Double,
        edgeInset: CGFloat
    ) -> some View {
        ZStack {
            ForEach(0..<count, id: \.self) { index in
                Rectangle()
                    .fill(Design.Brand.accent.opacity(opacity))
                    .frame(width: thickness, height: length)
                    .offset(y: -(size / 2 - edgeInset - length / 2))
                    .rotationEffect(.degrees(Double(index) / Double(count) * 360))
            }
        }
    }

    /// Stroked sprocket holes ringed inside the rim (Paper Tape reel).
    private func sprocketHoles(count: Int, holeRadius: CGFloat, edgeInset: CGFloat) -> some View {
        ZStack {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .strokeBorder(Design.Colors.accentTint(0.5), lineWidth: 1)
                    .frame(width: holeRadius * 2, height: holeRadius * 2)
                    .offset(y: -(size / 2 - edgeInset))
                    .rotationEffect(.degrees(Double(index) / Double(count) * 360))
            }
        }
    }
}

// MARK: - Animated subviews (isolated state per element)

private struct BreathingCore: View {
    let diameter: CGFloat
    let glowRadius: CGFloat
    let glow: Double

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || ThemeRuntime.shared.appReduceMotion }
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

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || ThemeRuntime.shared.appReduceMotion }
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [ThemeRuntime.shared.palette.coreHighlight,
                             Design.Brand.accent,
                             ThemeRuntime.shared.palette.coreShadow],
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

/// Paper Tape hub — inked reel center, deliberately unlit (no breathing, no
/// glow fill; `glowScale` already zeroes the shadow).
private struct PaperHub: View {
    let diameter: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Design.Brand.accent.opacity(0.7), lineWidth: 1.5)
            Circle()
                .fill(Design.Brand.accent)
                .frame(width: diameter * 0.3, height: diameter * 0.3)
        }
        .frame(width: diameter, height: diameter)
    }
}

private struct PingHalo: View {
    let diameter: CGFloat

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || ThemeRuntime.shared.appReduceMotion }
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
