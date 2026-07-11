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
///  • singularity  — collapsed star: gold→magenta core, Hawking-cyan
///                   counter-pulse rim, multi-hue accretion sweep
///                   (Event Horizon — design/themes/theme-event-horizon.html).
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
            case .singularity: singularityLayers
            // Gallery-port compositions (Lane E Phase 2, gh#64). Most share
            // the handoffs' tri-ring anatomy — data below, drawing in
            // `triRingLayers` — with bespoke extras per theme.
            case .glitchSeed: triRingLayers(Self.glitchSeed)
            case .cauldronBrew: cauldronBrewLayers
            case .holoNigiri: triRingLayers(Self.holoNigiri)
            case .prizeWheel: triRingLayers(Self.prizeWheel)
            case .candyMecha: triRingLayers(Self.candyMecha)
            case .jukeboxGlow: triRingLayers(Self.jukeboxGlow)
            case .cactusBloom: triRingLayers(Self.cactusBloom)
            case .anglerLure: triRingLayers(Self.anglerLure)
            case .discoBall: discoBallLayers
            case .sprayCap: sprayCapLayers
            case .mirrorBall: triRingLayers(Self.mirrorBall)
            case .rocketBadge: rocketBadgeLayers
            // Batch-4 Claude-Design compositions — the three handoffs share
            // one anatomy (solid / spinning-dashed / solid pulse rings +
            // brightening two-hue core with a third-hue outer halo), so all
            // three are tri-ring data; the moon jelly adds the whole-orb bob.
            case .moonJelly: moonJellyLayers
            case .crucible: triRingLayers(Self.crucible)
            case .phosphor: triRingLayers(Self.phosphor)
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

    // MARK: - Singularity (Event Horizon — collapsed star)

    @ViewBuilder private var singularityLayers: some View {
        switch style {
        case .minimal:
            HorizonRing(diameter: size, color: SingularityHue.violet,
                        baseOpacity: 0.35, lineWidth: lw(0.033))
            SingularityCore(diameter: size * 0.44, glow: glowIntensity)

        case .standard:
            HorizonRing(diameter: size, color: SingularityHue.violet,
                        baseOpacity: 0.35, lineWidth: lw(0.033))
            AccretionRing(diameter: size * 0.62, lineWidth: lw(0.05))
            SingularityCore(diameter: size * 0.34, glow: glowIntensity)

        case .onboarding:
            // The handoff's three horizon rings at 100/74/48%, staggered
            // pulses, with the accretion sweep orbiting between them.
            HorizonRing(diameter: size, color: SingularityHue.violet,
                        baseOpacity: 0.35, lineWidth: lw(0.027))
            HorizonRing(diameter: size * 0.74, color: SingularityHue.cyan,
                        baseOpacity: 0.55, lineWidth: lw(0.027), dash: [4, 5], pulseDelay: 0.3)
            AccretionRing(diameter: size * 0.60, lineWidth: lw(0.027))
            HorizonRing(diameter: size * 0.48, color: SingularityHue.gold,
                        baseOpacity: 0.75, lineWidth: lw(0.027), pulseDelay: 0.6)
            SingularityCore(diameter: size * 0.30, glow: glowIntensity)

        case .voice:
            PingHalo(diameter: size)
            HorizonRing(diameter: size, color: SingularityHue.violet,
                        baseOpacity: 0.35, lineWidth: 2)
            HorizonRing(diameter: size * 0.74, color: SingularityHue.cyan,
                        baseOpacity: 0.55, lineWidth: 2, dash: [4, 5], pulseDelay: 0.3)
            AccretionRing(diameter: size * 0.58, lineWidth: 3)
            HorizonRing(diameter: size * 0.48, color: SingularityHue.gold,
                        baseOpacity: 0.75, lineWidth: 2, pulseDelay: 0.6)
            SingularityCore(diameter: size * 0.30, glow: glowIntensity)
        }
    }

    // MARK: - Tri-ring gallery family (Lane E Phase 2)
    // The collection handoffs share one orb anatomy: three staggered pulse
    // rings at 100/74/48% with per-theme hues, around a two-hue radial core
    // with a per-theme motion (design/themes/*.html `.orb`). The drawing is
    // shared; each theme is a `TriRingOrbSpec` of verbatim handoff values.

    @ViewBuilder private func triRingLayers(_ spec: TriRingOrbSpec) -> some View {
        switch style {
        case .minimal:
            triRing(spec, index: 0, diameter: size)
            triCore(spec, diameter: size * 0.50)

        case .standard:
            triRing(spec, index: 0, diameter: size)
            triRing(spec, index: 2, diameter: size * spec.rings[2].diameterFraction)
            triCore(spec, diameter: size * 0.36)

        case .onboarding:
            // The handoff's exact three-ring stack + core.
            ForEach(spec.rings.indices, id: \.self) { index in
                triRing(spec, index: index,
                        diameter: size * spec.rings[index].diameterFraction)
            }
            triCore(spec, diameter: size * spec.coreFraction)

        case .voice:
            PingHalo(diameter: size)
            ForEach(spec.rings.indices, id: \.self) { index in
                triRing(spec, index: index,
                        diameter: size * spec.rings[index].diameterFraction)
            }
            triCore(spec, diameter: size * max(spec.coreFraction, 0.34))
        }
    }

    @ViewBuilder private func triRing(_ spec: TriRingOrbSpec, index: Int, diameter: CGFloat) -> some View {
        let ring = spec.rings[index]
        let pulse = TriPulseRing(
            diameter: diameter,
            color: ring.color,
            baseOpacity: ring.baseOpacity,
            lineWidth: lw(ring.lineWidthFraction),
            dash: ring.dash,
            period: spec.pulsePeriod,
            delay: ring.delay
        )
        if let spin = ring.spinPeriod {
            pulse.continuousRotation(spin)
        } else {
            pulse
        }
    }

    private func triCore(_ spec: TriRingOrbSpec, diameter: CGFloat) -> some View {
        TwoHueOrbCore(
            diameter: diameter,
            highlight: spec.coreHighlight,
            base: spec.coreBase,
            glowColor: spec.coreGlow,
            glow: glowIntensity,
            motion: spec.coreMotion,
            glyph: spec.coreGlyph,
            glyphColor: spec.coreGlyphColor,
            outerGlowColor: spec.coreOuterGlow
        )
    }

    /// Witch's Brew: the tri-ring stack plus rising mystic bubbles — skipped
    /// at `.minimal` where a 30pt orb has no room for them.
    @ViewBuilder private var cauldronBrewLayers: some View {
        triRingLayers(Self.cauldronBrew)
        if style != .minimal {
            CauldronBubbles(diameter: size, glow: glowIntensity)
        }
    }

    /// Midnight Aquarium: the tri-ring moon jelly with the whole orb bobbing
    /// (`jellyFloat`, 5s ease-in-out, −8px on the 120px reference orb →
    /// size-relative so every orb size breathes at the same proportion).
    private var moonJellyLayers: some View {
        triRingLayers(Self.moonJelly)
            .modifier(JellyFloatModifier(travel: size * (8.0 / 120.0), period: 5))
    }

    // MARK: Disco Inferno — mirror ball (dashed/dotted counter-spin, pixel core)

    @ViewBuilder private var discoBallLayers: some View {
        switch style {
        case .minimal:
            discoOuterRing(diameter: size)
            DiscoPixelCore(edge: size * 0.42, glow: glowIntensity)
        case .standard:
            discoOuterRing(diameter: size)
            discoInnerDouble(diameter: size * 0.52)
            DiscoPixelCore(edge: size * 0.29, glow: glowIntensity)
        case .onboarding, .voice:
            if style == .voice { PingHalo(diameter: size) }
            discoOuterRing(diameter: size)
            discoMidRing(diameter: size * 0.76)
            discoInnerDouble(diameter: size * 0.52)
            DiamondCoinRing(diameter: size * 1.12, color: DiscoHue.silver)
            DiscoPixelCore(edge: size * 0.29, glow: glowIntensity)
        }
    }

    /// Dashed gold ring, one turn per 18s (`orbSpin`).
    private func discoOuterRing(diameter: CGFloat) -> some View {
        Circle()
            .strokeBorder(DiscoHue.gold.opacity(0.85),
                          style: StrokeStyle(lineWidth: lw(0.048), dash: [lw(0.09), lw(0.09)]))
            .frame(width: diameter, height: diameter)
            .hudGlow(DiscoHue.gold, radius: diameter * 0.14, strength: 0.6, intensity: glowIntensity)
            .continuousRotation(18)
    }

    /// Dotted silver ring counter-spinning at 12s.
    private func discoMidRing(diameter: CGFloat) -> some View {
        Circle()
            .strokeBorder(DiscoHue.silver.opacity(0.75),
                          style: StrokeStyle(lineWidth: lw(0.024), lineCap: .round,
                                             dash: [0.1, lw(0.055)]))
            .frame(width: diameter, height: diameter)
            .continuousRotation(12, reverse: true)
    }

    /// The `border-style: double` crimson ring — two thin concentric strokes
    /// pulsing together at 3s.
    private func discoInnerDouble(diameter: CGFloat) -> some View {
        TriPulseRing(diameter: diameter, color: DiscoHue.crimson, baseOpacity: 0.9,
                     lineWidth: lw(0.024), period: 3, scaleAmp: 1.08)
            .overlay {
                TriPulseRing(diameter: diameter - lw(0.024) * 3, color: DiscoHue.crimson,
                             baseOpacity: 0.9, lineWidth: lw(0.024), period: 3, scaleAmp: 1.08)
            }
    }

    // MARK: Graffiti Galaxy — spray cap (square citron core, counter-spun outline)

    @ViewBuilder private var sprayCapLayers: some View {
        switch style {
        case .minimal:
            triRing(Self.sprayCapRings, index: 0, diameter: size)
            SprayCapCore(edge: size * 0.44, glow: glowIntensity)
        case .standard:
            triRing(Self.sprayCapRings, index: 0, diameter: size)
            triRing(Self.sprayCapRings, index: 2,
                    diameter: size * Self.sprayCapRings.rings[2].diameterFraction)
            SprayCapCore(edge: size * 0.30, glow: glowIntensity)
        case .onboarding, .voice:
            if style == .voice { PingHalo(diameter: size) }
            ForEach(Self.sprayCapRings.rings.indices, id: \.self) { index in
                triRing(Self.sprayCapRings, index: index,
                        diameter: size * Self.sprayCapRings.rings[index].diameterFraction)
            }
            SprayCapCore(edge: size * 0.30, glow: glowIntensity)
        }
    }

    // MARK: Retro Sci-Fi — rocket badge (pinwheel disc, inked primaries)

    @ViewBuilder private var rocketBadgeLayers: some View {
        switch style {
        case .minimal:
            PinwheelDisc(diameter: size, lineWidth: lw(0.027))
            badgeDisc(diameter: size * 0.52, fill: RetroHue.red, delay: 0.6)
        case .standard:
            PinwheelDisc(diameter: size, lineWidth: lw(0.027))
            badgeDisc(diameter: size * 0.58, fill: RetroHue.yellow, delay: 0.3)
            badgeDisc(diameter: size * 0.30, fill: RetroHue.red, delay: 0.6)
        case .onboarding, .voice:
            if style == .voice { PingHalo(diameter: size) }
            PinwheelDisc(diameter: size, lineWidth: lw(0.027))
            badgeDisc(diameter: size * 0.70, fill: RetroHue.blue, delay: 0.3)
            badgeDisc(diameter: size * 0.40, fill: RetroHue.yellow, delay: 0.6)
            badgeDisc(diameter: size * 0.28, fill: RetroHue.red, delay: 0.6)
        }
    }

    /// A flat inked disc — solid fill, dark comic border, hard offset shadow
    /// (`box-shadow: 4px 4px 0`), scale-only pulse.
    private func badgeDisc(diameter: CGFloat, fill: Color, delay: Double) -> some View {
        BadgePulseDisc(diameter: diameter, fill: fill,
                       border: RetroHue.ink, borderWidth: max(1, lw(0.018)),
                       delay: delay)
    }

    // MARK: Tri-ring specs (verbatim handoff hues; design/themes/*.html)

    private static let glitchSeed = TriRingOrbSpec(
        rings: [
            .init(color: GlitchHue.green, baseOpacity: 0.4, diameterFraction: 1.0),
            .init(color: GlitchHue.cyan, baseOpacity: 0.6, diameterFraction: 0.74, delay: 0.3),
            .init(color: GlitchHue.magenta, baseOpacity: 0.8, diameterFraction: 0.48, delay: 0.6),
        ],
        coreHighlight: GlitchHue.cyan, coreBase: GlitchHue.green, coreGlow: GlitchHue.green,
        coreMotion: .spinGradient(period: 6)
    )

    private static let cauldronBrew = TriRingOrbSpec(
        rings: [
            .init(color: BrewHue.poison, baseOpacity: 0.4, diameterFraction: 1.0),
            .init(color: BrewHue.poison, baseOpacity: 0.6, diameterFraction: 0.74, delay: 0.3),
            .init(color: BrewHue.poison, baseOpacity: 0.8, diameterFraction: 0.48, delay: 0.6),
        ],
        coreHighlight: BrewHue.bubble, coreBase: BrewHue.poison, coreGlow: BrewHue.poison,
        coreMotion: .breathe(period: 3, scale: 1.08)
    )

    private static let holoNigiri = TriRingOrbSpec(
        rings: [
            .init(color: SushiHue.roe, baseOpacity: 0.4, diameterFraction: 1.0, dash: [5, 4]),
            .init(color: SushiHue.wasabi, baseOpacity: 0.6, diameterFraction: 0.74, delay: 0.3),
            .init(color: SushiHue.nori, baseOpacity: 0.8, diameterFraction: 0.48, delay: 0.6),
        ],
        coreHighlight: SushiHue.wasabi, coreBase: SushiHue.roe, coreGlow: SushiHue.roe,
        coreMotion: .shimmer(period: 3, degrees: 15)
    )

    private static let prizeWheel = TriRingOrbSpec(
        rings: [
            .init(color: CerealHue.berry, baseOpacity: 0.4, diameterFraction: 1.0),
            .init(color: CerealHue.milk, baseOpacity: 0.6, diameterFraction: 0.74, delay: 0.3),
            .init(color: CerealHue.honey, baseOpacity: 0.8, diameterFraction: 0.48, delay: 0.6),
        ],
        coreHighlight: CerealHue.honey, coreBase: CerealHue.berry, coreGlow: CerealHue.berry,
        coreMotion: .spinGradient(period: 6)
    )

    private static let candyMecha = TriRingOrbSpec(
        rings: [
            .init(color: MechaHue.candy, baseOpacity: 0.4, diameterFraction: 1.0),
            .init(color: MechaHue.cyan, baseOpacity: 0.6, diameterFraction: 0.74, delay: 0.5),
            .init(color: MechaHue.yellow, baseOpacity: 0.8, diameterFraction: 0.48, delay: 1.0),
        ],
        pulsePeriod: 5,
        coreHighlight: MechaHue.yellow, coreBase: MechaHue.candy, coreGlow: MechaHue.candy,
        coreMotion: .brighten(period: 4, scale: 1.08, amount: 0.2)
    )

    private static let jukeboxGlow = TriRingOrbSpec(
        rings: [
            .init(color: LunarHue.soda, baseOpacity: 0.4, diameterFraction: 1.0),
            .init(color: LunarHue.chrome, baseOpacity: 0.6, diameterFraction: 0.74, delay: 0.3),
            .init(color: LunarHue.mustard, baseOpacity: 0.8, diameterFraction: 0.48, delay: 0.6),
        ],
        coreHighlight: LunarHue.mustard, coreBase: LunarHue.soda, coreGlow: LunarHue.soda,
        coreMotion: .brighten(period: 3, scale: 1.05, amount: 0.15)
    )

    private static let cactusBloom = TriRingOrbSpec(
        rings: [
            .init(color: CactusHue.sunset, baseOpacity: 0.4, diameterFraction: 1.0),
            .init(color: CactusHue.succulent, baseOpacity: 0.6, diameterFraction: 0.74, delay: 0.3),
            .init(color: CactusHue.sand, baseOpacity: 0.8, diameterFraction: 0.48, delay: 0.6),
        ],
        coreHighlight: CactusHue.sand, coreBase: CactusHue.sunset, coreGlow: CactusHue.sunset,
        coreMotion: .breathe(period: 3, scale: 1.04)
    )

    private static let anglerLure = TriRingOrbSpec(
        rings: [
            .init(color: AbyssHue.lure, baseOpacity: 0.4, diameterFraction: 1.0),
            .init(color: AbyssHue.coral, baseOpacity: 0.6, diameterFraction: 0.74, delay: 0.3),
            .init(color: AbyssHue.gold, baseOpacity: 0.8, diameterFraction: 0.48, delay: 0.6),
        ],
        coreHighlight: AbyssHue.gold, coreBase: AbyssHue.lure, coreGlow: AbyssHue.lure,
        coreMotion: .brighten(period: 3, scale: 1.05, amount: 0.15)
    )

    private static let mirrorBall = TriRingOrbSpec(
        rings: [
            .init(color: KaraokeHue.magenta, baseOpacity: 0.3, diameterFraction: 1.0),
            .init(color: KaraokeHue.cyan, baseOpacity: 0.5, diameterFraction: 0.74, delay: 0.3),
            .init(color: KaraokeHue.gold, baseOpacity: 0.7, diameterFraction: 0.48, delay: 0.6),
        ],
        pulsePeriod: 3,
        coreHighlight: KaraokeHue.gold, coreBase: KaraokeHue.magenta, coreGlow: KaraokeHue.magenta,
        coreMotion: .spinGradient(period: 4),
        coreFraction: 0.34,
        coreGlyph: "♪", coreGlyphColor: KaraokeHue.ink
    )

    private static let sprayCapRings = TriRingOrbSpec(
        rings: [
            .init(color: GraffitiHue.pink, baseOpacity: 0.35, diameterFraction: 1.0,
                  lineWidthFraction: 0.025),
            .init(color: GraffitiHue.violet, baseOpacity: 0.55, diameterFraction: 0.72,
                  dash: [5, 4], delay: 0.3, lineWidthFraction: 0.025),
            .init(color: GraffitiHue.spray, baseOpacity: 0.75, diameterFraction: 0.44,
                  delay: 0.6, lineWidthFraction: 0.017),
        ],
        pulsePeriod: 3.5,
        coreHighlight: GraffitiHue.citron, coreBase: GraffitiHue.citron,
        coreGlow: GraffitiHue.citron
    )

    // MARK: Batch-4 Claude-Design specs (shared anatomy: rings 1.0/0.74/0.48
    // at .35/.55/.75, pulse 3.5s staggered 0/0.3/0.6, dashed middle ring
    // spinning (orbSpin), 30% two-hue core — corePulse 4s, scale 1.12,
    // brightness 1.3 — glowing 30px in the hero and 60px in the third hue).

    private static let moonJelly = TriRingOrbSpec(
        rings: [
            .init(color: AquariumHue.jelly, baseOpacity: 0.35, diameterFraction: 1.0),
            .init(color: AquariumHue.biolume, baseOpacity: 0.55, diameterFraction: 0.74,
                  dash: [5, 4], delay: 0.3, spinPeriod: 20),
            .init(color: AquariumHue.anemone, baseOpacity: 0.75, diameterFraction: 0.48,
                  delay: 0.6),
        ],
        pulsePeriod: 3.5,
        coreHighlight: AquariumHue.biolume, coreBase: AquariumHue.jelly,
        coreGlow: AquariumHue.jelly,
        coreMotion: .brighten(period: 4, scale: 1.12, amount: 0.3),
        coreFraction: 0.30,
        coreOuterGlow: AquariumHue.anemone
    )

    private static let crucible = TriRingOrbSpec(
        rings: [
            .init(color: MoltenHue.lava, baseOpacity: 0.35, diameterFraction: 1.0),
            .init(color: MoltenHue.spark, baseOpacity: 0.55, diameterFraction: 0.74,
                  dash: [5, 4], delay: 0.3, spinPeriod: 14),
            .init(color: MoltenHue.steel, baseOpacity: 0.75, diameterFraction: 0.48,
                  delay: 0.6),
        ],
        pulsePeriod: 3.5,
        coreHighlight: MoltenHue.spark, coreBase: MoltenHue.lava,
        coreGlow: MoltenHue.lava,
        coreMotion: .brighten(period: 4, scale: 1.12, amount: 0.3),
        coreFraction: 0.30,
        coreOuterGlow: MoltenHue.ember
    )

    private static let phosphor = TriRingOrbSpec(
        rings: [
            .init(color: VHSHue.phosphor, baseOpacity: 0.35, diameterFraction: 1.0),
            .init(color: VHSHue.chroma, baseOpacity: 0.55, diameterFraction: 0.74,
                  dash: [5, 4], delay: 0.3, spinPeriod: 14),
            .init(color: VHSHue.staticCyan, baseOpacity: 0.75, diameterFraction: 0.48,
                  delay: 0.6),
        ],
        pulsePeriod: 3.5,
        coreHighlight: VHSHue.staticCyan, coreBase: VHSHue.phosphor,
        coreGlow: VHSHue.phosphor,
        coreMotion: .brighten(period: 4, scale: 1.12, amount: 0.3),
        coreFraction: 0.30,
        coreOuterGlow: VHSHue.chroma
    )

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

// MARK: - Singularity pieces (Event Horizon)

/// Handoff hues (design/themes/theme-event-horizon.html). The singularity is
/// inherently multi-hue — the four accents together ARE its identity — so the
/// composition curates its own colors instead of the resolved accent slot.
private enum SingularityHue {
    static let violet = Color(hex: 0x8A5CFF)   // Accretion Violet
    static let cyan = Color(hex: 0x00F0FF)     // Hawking Cyan
    static let gold = Color(hex: 0xFFDC50)     // Supernova Gold
    static let magenta = Color(hex: 0xFF2AA8)  // Singularity Magenta
}

/// One pulsing horizon ring (the handoff's `.orb-ring`): 3.5s ease-in-out
/// scale 1→1.05 with a slight opacity lift, staggered per ring via
/// `pulseDelay` like the CSS animation-delay chain. Static under Reduce Motion.
private struct HorizonRing: View {
    let diameter: CGFloat
    let color: Color
    let baseOpacity: Double
    var lineWidth: CGFloat = 2
    var dash: [CGFloat] = []
    var pulseDelay: Double = 0

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || ThemeRuntime.shared.appReduceMotion }
    @State private var pulse = false

    var body: some View {
        Circle()
            .strokeBorder(color, style: StrokeStyle(lineWidth: lineWidth, dash: dash))
            .frame(width: diameter, height: diameter)
            .opacity(pulse ? min(1, baseOpacity + 0.15) : baseOpacity)
            .scaleEffect(pulse ? 1.05 : 1.0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)
                    .delay(pulseDelay)) {
                    pulse = true
                }
            }
    }
}

/// The slow accretion sweep (`horizonSpin`, 30s linear): a violet → cyan →
/// gold → magenta angular gradient ring orbiting the core. Rotation is
/// reduce-motion-aware via `continuousRotation`.
private struct AccretionRing: View {
    let diameter: CGFloat
    var lineWidth: CGFloat = 2
    var opacity: Double = 0.7

    var body: some View {
        Circle()
            .strokeBorder(
                AngularGradient(
                    colors: [SingularityHue.violet, SingularityHue.cyan, SingularityHue.gold,
                             SingularityHue.magenta, SingularityHue.violet],
                    center: .center
                ),
                lineWidth: lineWidth
            )
            .opacity(opacity)
            .frame(width: diameter, height: diameter)
            .continuousRotation(30)
    }
}

/// The collapsed star (`.orb-core` + its `::after` rim): a gold→magenta
/// radial core — `singularityPulse`, 4s ease-in-out, scale 1→1.1, brightness
/// 1→1.25 — inside a Hawking-cyan rim counter-pulsing at 3.5s (scale 1→1.05,
/// opacity 0.5→0.7; the differing periods keep the two out of phase, the
/// handoff's `reverse`). Glow is the layered magenta 30px + violet 60px
/// box-shadow, scaled to the core diameter and riding the glow pref.
private struct SingularityCore: View {
    let diameter: CGFloat
    let glow: Double

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || ThemeRuntime.shared.appReduceMotion }
    @State private var corePulse = false
    @State private var rimPulse = false

    /// The handoff's `inset: -8px` rim on the 36px reference core.
    private var rimDiameter: CGFloat { diameter * 1.44 }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(SingularityHue.cyan, lineWidth: max(1, diameter * 0.055))
                .frame(width: rimDiameter, height: rimDiameter)
                .opacity(rimPulse ? 0.7 : 0.5)
                .scaleEffect(rimPulse ? 1.05 : 1.0)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [SingularityHue.gold, SingularityHue.magenta],
                        center: UnitPoint(x: 0.3, y: 0.3),
                        startRadius: 0,
                        endRadius: diameter * 0.62
                    )
                )
                .frame(width: diameter, height: diameter)
                .scaleEffect(corePulse ? 1.1 : 1.0)
                .brightness(corePulse ? 0.25 : 0)
                .hudGlow(SingularityHue.magenta, radius: diameter * 0.85, strength: 0.85, intensity: glow)
                .hudGlow(SingularityHue.violet, radius: diameter * 1.7, strength: 0.4, intensity: glow)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                corePulse = true
            }
            withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) {
                rimPulse = true
            }
        }
    }
}

// MARK: - Gallery orb machinery (Lane E Phase 2)

/// One tri-ring gallery orb as pure data: three staggered pulse rings plus a
/// two-hue core. Values come verbatim from the theme handoffs; the drawing
/// lives in `ReactorOrb.triRingLayers`.
private struct TriRingOrbSpec {
    struct Ring {
        let color: Color
        let baseOpacity: Double
        /// Ring diameter as a fraction of the orb (handoffs: 1.0/0.74/0.48).
        let diameterFraction: CGFloat
        var dash: [CGFloat] = []
        var delay: Double = 0
        var lineWidthFraction: CGFloat = 0.02
        /// Seconds per full rotation (`orbSpin` on a dashed ring — the batch-4
        /// Claude-Design orbs spin their middle ring). `nil` = static ring,
        /// byte-identical for every existing spec.
        var spinPeriod: Double? = nil
    }

    let rings: [Ring]
    var pulsePeriod: Double = 4
    let coreHighlight: Color
    let coreBase: Color
    let coreGlow: Color
    var coreMotion: OrbCoreMotion = .steady
    var coreFraction: CGFloat = 0.32
    var coreGlyph: String? = nil
    var coreGlyphColor: Color = .black
    /// Hue of the core's WIDE outer halo when it differs from `coreGlow` —
    /// the batch-4 handoffs' `box-shadow: 0 0 30px hero, 0 0 60px rgba(third
    /// hue, .4)` stack. `nil` = both halos in `coreGlow` (byte-identical).
    var coreOuterGlow: Color? = nil
}

/// Per-theme core motions — each theme's `.orb-core` keyframe family.
private enum OrbCoreMotion {
    case steady
    /// Scale breathe (`bubble`: 1 → scale → 1).
    case breathe(period: Double, scale: CGFloat)
    /// Scale + brightness flash (`mecha-pulse` / `chrome` / `biolum`).
    case brighten(period: Double, scale: CGFloat, amount: Double)
    /// Rotate the off-center radial gradient — the CSS `spin` on a
    /// `circle at 30% 30%` core makes the highlight orbit.
    case spinGradient(period: Double)
    /// Iridescent hue drift (`shimmer`: hue-rotate 0 → degrees → 0).
    case shimmer(period: Double, degrees: Double)
}

/// One staggered pulse ring (the gallery `.orb-ring`): ease-in-out scale
/// 1 → `scaleAmp` with a +0.2 opacity lift, half-period each way so a CSS
/// `pulse Ns` keyframe matches exactly. Static under Reduce Motion.
private struct TriPulseRing: View {
    let diameter: CGFloat
    let color: Color
    let baseOpacity: Double
    var lineWidth: CGFloat = 2
    var dash: [CGFloat] = []
    var period: Double = 4
    var delay: Double = 0
    var scaleAmp: CGFloat = 1.04

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || ThemeRuntime.shared.appReduceMotion }
    @State private var pulse = false

    var body: some View {
        Circle()
            .strokeBorder(color, style: StrokeStyle(lineWidth: lineWidth, dash: dash))
            .frame(width: diameter, height: diameter)
            .opacity(pulse ? min(1, baseOpacity + 0.2) : baseOpacity)
            .scaleEffect(pulse ? scaleAmp : 1.0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: period / 2).repeatForever(autoreverses: true)
                    .delay(delay)) {
                    pulse = true
                }
            }
    }
}

/// The gallery two-hue core: `radial-gradient(circle at 30% 30%, highlight,
/// base)` with the handoffs' 30px + 60px glow stack and a per-theme motion.
/// `outerGlowColor` re-hues just the wide 60px halo (the batch-4 orbs halo
/// in their third accent); nil keeps both halos in `glowColor`, byte-identical.
private struct TwoHueOrbCore: View {
    let diameter: CGFloat
    let highlight: Color
    let base: Color
    let glowColor: Color
    let glow: Double
    var motion: OrbCoreMotion = .steady
    var glyph: String? = nil
    var glyphColor: Color = .black
    var outerGlowColor: Color? = nil

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || ThemeRuntime.shared.appReduceMotion }
    @State private var pulse = false

    var body: some View {
        ZStack {
            switch motion {
            case let .spinGradient(period):
                gradientDisc.continuousRotation(period)
            default:
                gradientDisc
            }
            if let glyph {
                // The Karaoke core prints ♪ in the room's ink — the glyph
                // stays upright while the gradient spins beneath it.
                Text(glyph)
                    .font(.system(size: diameter * 0.55, weight: .black))
                    .foregroundStyle(glyphColor)
            }
        }
        .frame(width: diameter, height: diameter)
        .scaleEffect(pulse ? motionScale : 1.0)
        .brightness(pulse ? motionBrightness : 0)
        .hueRotation(.degrees(pulse ? motionHueDegrees : 0))
        .hudGlow(glowColor, radius: diameter * 0.85, strength: 0.85, intensity: glow)
        .hudGlow(outerGlowColor ?? glowColor, radius: diameter * 1.7, strength: 0.4, intensity: glow)
        .onAppear {
            guard !reduceMotion, let period = motionPeriod else { return }
            withAnimation(.easeInOut(duration: period / 2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private var gradientDisc: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [highlight, base],
                    center: UnitPoint(x: 0.3, y: 0.3),
                    startRadius: 0,
                    endRadius: diameter * 0.62
                )
            )
            .frame(width: diameter, height: diameter)
    }

    private var motionPeriod: Double? {
        switch motion {
        case .steady, .spinGradient: nil
        case let .breathe(period, _): period
        case let .brighten(period, _, _): period
        case let .shimmer(period, _): period
        }
    }

    private var motionScale: CGFloat {
        switch motion {
        case let .breathe(_, scale): scale
        case let .brighten(_, scale, _): scale
        default: 1.0
        }
    }

    private var motionBrightness: Double {
        if case let .brighten(_, _, amount) = motion { amount } else { 0 }
    }

    private var motionHueDegrees: Double {
        if case let .shimmer(_, degrees) = motion { degrees } else { 0 }
    }
}

/// Witch's Brew `.orb-bubbles`: two mystic-violet bubbles rising through the
/// orb every 2.5s (staggered 1.2s), shrinking and fading as they go — drawn
/// in a circle-clipped Canvas at the handoff's 0.5 layer opacity. Static at
/// t = 0 under Reduce Motion.
private struct CauldronBubbles: View {
    let diameter: CGFloat
    let glow: Double

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || ThemeRuntime.shared.appReduceMotion }

    /// (x fraction, radius fraction of orb, start height fraction, delay)
    private static let bubbles: [(x: Double, radius: Double, startY: Double, delay: Double)] = [
        (0.30, 0.036, 0.90, 0.0),
        (0.60, 0.027, 0.95, 1.2),
    ]
    private static let risePeriod = 2.5
    /// The handoff's translateY(-80px) on a 110px orb.
    private static let riseFraction = 0.73

    var body: some View {
        Group {
            if reduceMotion {
                Canvas { context, size in
                    Self.draw(context: context, size: size, time: 0)
                }
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                    Canvas { context, size in
                        Self.draw(
                            context: context,
                            size: size,
                            time: timeline.date.timeIntervalSinceReferenceDate
                        )
                    }
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .opacity(0.5)
        .allowsHitTesting(false)
    }

    private static func draw(context: GraphicsContext, size: CGSize, time: Double) {
        var soft = context
        soft.addFilter(.blur(radius: 1))
        for bubble in bubbles {
            let cycle = ((time - bubble.delay).truncatingRemainder(dividingBy: risePeriod)
                + risePeriod).truncatingRemainder(dividingBy: risePeriod) / risePeriod
            let scale = 1 - 0.6 * cycle
            let opacity = 0.6 * (1 - cycle)
            let radius = size.width * bubble.radius * scale
            guard radius > 0.1, opacity > 0.01 else { continue }
            let x = size.width * bubble.x
            let y = size.height * bubble.startY - cycle * size.height * riseFraction
            soft.fill(
                Path(ellipseIn: CGRect(x: x - radius, y: y - radius,
                                       width: radius * 2, height: radius * 2)),
                with: .color(BrewHue.mystic.opacity(opacity))
            )
        }
    }
}

/// Disco Inferno's pixel core: a flat gold square with the handoff's inner
/// white sheen and two faint square halos (the `::after` pixel frame — its
/// cross clip reads as square outlines at core size; noted in the port).
private struct DiscoPixelCore: View {
    let edge: CGFloat
    let glow: Double

    var body: some View {
        ZStack {
            Rectangle()
                .strokeBorder(Color.white.opacity(0.06), lineWidth: max(1, edge * 0.167))
                .frame(width: edge * 1.67, height: edge * 1.67)
            Rectangle()
                .strokeBorder(Color.white.opacity(0.12), lineWidth: max(1, edge * 0.167))
                .frame(width: edge * 1.33, height: edge * 1.33)
            Rectangle()
                .fill(DiscoHue.gold)
                .overlay {
                    Rectangle()
                        .stroke(Color.white.opacity(0.5), lineWidth: max(1, edge * 0.08))
                        .blur(radius: edge * 0.1)
                }
                .frame(width: edge, height: edge)
                .hudGlow(DiscoHue.gold, radius: edge * 0.75, strength: 0.85, intensity: glow)
        }
    }
}

/// Disco Inferno's `.orb-coin`: a silver ring clipped to a diamond, orbiting
/// the core counter-clockwise every 7s — four arc glints sweeping the rim.
private struct DiamondCoinRing: View {
    let diameter: CGFloat
    let color: Color

    var body: some View {
        Circle()
            .strokeBorder(color, lineWidth: 2)
            .frame(width: diameter, height: diameter)
            .clipShape(DiamondShape())
            .opacity(0.55)
            .continuousRotation(7, reverse: true)
    }
}

/// The CSS `clip-path: polygon(50% 0, 100% 50%, 50% 100%, 0 50%)` diamond.
private struct DiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

/// Graffiti Galaxy's spray cap: a rounded-square citron core spinning at 5s
/// with a pink square outline counter-spinning around it.
private struct SprayCapCore: View {
    let edge: CGFloat
    let glow: Double

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: edge * 0.13)
                .strokeBorder(GraffitiHue.pink, lineWidth: max(1, edge * 0.055))
                .frame(width: edge * 1.33, height: edge * 1.33)
                .continuousRotation(5, reverse: true)
            RoundedRectangle(cornerRadius: edge * 0.13)
                .fill(GraffitiHue.citron)
                .frame(width: edge, height: edge)
                .hudGlow(GraffitiHue.citron, radius: edge * 0.85, strength: 0.85, intensity: glow)
                .hudGlow(GraffitiHue.citron, radius: edge * 1.7, strength: 0.4, intensity: glow)
                .continuousRotation(5)
        }
    }
}

/// Retro Sci-Fi's pinwheel: the handoff's `repeating-conic-gradient` of 20°
/// red/yellow/blue/cream wedges as a static inked disc (the CSS spins only
/// the flat core, which reads as no motion). Comic offset shadow, dark rim.
private struct PinwheelDisc: View {
    let diameter: CGFloat
    let lineWidth: CGFloat

    private static let wedgeColors = [RetroHue.red, RetroHue.yellow, RetroHue.blue, RetroHue.cream]

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            let wedge = Angle(degrees: 20).radians
            for index in 0..<18 {
                var path = Path()
                let start = Double(index) * wedge - .pi / 2
                path.move(to: center)
                path.addArc(center: center, radius: radius,
                            startAngle: .radians(start), endAngle: .radians(start + wedge),
                            clockwise: false)
                path.closeSubpath()
                context.fill(path, with: .color(Self.wedgeColors[index % 4]))
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(RetroHue.ink, lineWidth: lineWidth)
        }
        .opacity(0.9)
        .shadow(color: .black.opacity(0.15), radius: 0,
                x: diameter * 0.036, y: diameter * 0.036)
    }
}

/// One flat comic disc of the rocket badge — solid fill, inked border, hard
/// offset shadow, scale-only pulse (the handoff's opacity-free `pulse`).
private struct BadgePulseDisc: View {
    let diameter: CGFloat
    let fill: Color
    let border: Color
    let borderWidth: CGFloat
    var delay: Double = 0

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || ThemeRuntime.shared.appReduceMotion }
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(fill)
            .overlay {
                Circle().strokeBorder(border, lineWidth: borderWidth)
            }
            .frame(width: diameter, height: diameter)
            .shadow(color: .black.opacity(0.15), radius: 0,
                    x: diameter * 0.05, y: diameter * 0.05)
            .scaleEffect(pulse ? 1.05 : 1.0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)
                    .delay(delay)) {
                    pulse = true
                }
            }
    }
}

// MARK: - Gallery hue tables (verbatim from design/themes/*.html)
// Like `SingularityHue`, each complex orb curates its own hues — the
// multi-hue identity must not follow the user's resolved accent slot.

private enum GlitchHue {
    static let green = Color(hex: 0x39FF14)
    static let cyan = Color(hex: 0x00F0FF)
    static let magenta = Color(hex: 0xFF00AA)
}

private enum BrewHue {
    static let poison = Color(hex: 0x4ADE80)
    static let mystic = Color(hex: 0xA855F7)
    static let bubble = Color(hex: 0xFACC15)
}

private enum SushiHue {
    static let roe = Color(hex: 0xFF69B4)
    static let wasabi = Color(hex: 0x00F0FF)
    static let nori = Color(hex: 0xADFF2F)
}

private enum CerealHue {
    static let berry = Color(hex: 0xFF5078)
    static let milk = Color(hex: 0x00C8FF)
    static let honey = Color(hex: 0xFFDC00)
}

private enum MechaHue {
    static let candy = Color(hex: 0xFF6EC7)
    static let cyan = Color(hex: 0x00F0FF)
    static let yellow = Color(hex: 0xFFE600)
}

private enum LunarHue {
    static let soda = Color(hex: 0xFF9AB4)
    static let chrome = Color(hex: 0x40E0D0)
    static let mustard = Color(hex: 0xFFD700)
}

private enum CactusHue {
    static let sunset = Color(hex: 0xFF5078)
    static let succulent = Color(hex: 0x00DCC8)
    static let sand = Color(hex: 0xFFC850)
}

private enum AbyssHue {
    static let lure = Color(hex: 0x00F5FF)
    static let coral = Color(hex: 0xFF6B6B)
    static let gold = Color(hex: 0xFFD166)
}

private enum DiscoHue {
    static let gold = Color(hex: 0xFFD700)
    static let silver = Color(hex: 0xE8E8E8)
    static let crimson = Color(hex: 0xFF3333)
}

private enum GraffitiHue {
    static let pink = Color(hex: 0xFF006E)
    static let violet = Color(hex: 0x8338EC)
    static let citron = Color(hex: 0xFBFF26)
    static let spray = Color(hex: 0x00F5D4)
}

private enum KaraokeHue {
    static let magenta = Color(hex: 0xFF00AA)
    static let cyan = Color(hex: 0x00F0FF)
    static let gold = Color(hex: 0xFFE600)
    static let ink = Color(hex: 0x050417)   // kara-bg-3, the ♪ glyph ink
}

private enum RetroHue {
    static let red = Color(hex: 0xFF2D2D)
    static let blue = Color(hex: 0x007BFF)
    static let yellow = Color(hex: 0xFFD600)
    static let cream = Color(hex: 0xFFFDF8)
    static let ink = Color(hex: 0x1A1210)
}

private enum AquariumHue {
    static let jelly = Color(hex: 0xFF7AD9)     // Jelly Pink
    static let biolume = Color(hex: 0x3EF2E0)   // Biolume Cyan
    static let anemone = Color(hex: 0x8A7CFF)   // Anemone Violet
}

private enum MoltenHue {
    static let lava = Color(hex: 0xFF6A1A)      // Lava Orange
    static let spark = Color(hex: 0xFFD23C)     // Spark Gold
    static let steel = Color(hex: 0xA9C2D1)     // Hammered Steel
    static let ember = Color(hex: 0xFF3B2D)     // Ember Red — core outer halo
}

private enum VHSHue {
    static let phosphor = Color(hex: 0x3BFF6F)  // Phosphor Green
    static let chroma = Color(hex: 0xFF3BD4)    // Chroma Magenta
    static let staticCyan = Color(hex: 0x35E0FF) // Static Cyan
}

/// Midnight Aquarium's `jellyFloat`: the whole orb rising `travel` points and
/// settling back over `period` seconds, ease-in-out — the CSS 0%/50%/100%
/// translateY keyframes. Static (translateY 0) under Reduce Motion.
private struct JellyFloatModifier: ViewModifier {
    let travel: CGFloat
    let period: Double

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || ThemeRuntime.shared.appReduceMotion }
    @State private var bob = false

    func body(content: Content) -> some View {
        content
            .offset(y: bob ? -travel : 0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: period / 2).repeatForever(autoreverses: true)) {
                    bob = true
                }
            }
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
