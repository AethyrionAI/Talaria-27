import SwiftUI

// MARK: - Theme art direction (app target only)
// The presentation layer that sits ON TOP of `ThemePaletteDefinition`
// (Shared/ThemePaletteCore.swift). The palette stays a flat, widget-safe
// color table; everything here is richer art direction — background glow
// pools, texture tints, panel treatments — consumed only inside the app, so
// the widget target never pays for it (design/THEME_ART_DIRECTION_PLAN.md).
//
// Every field is optional-with-inert-default: a theme with no catalog entry
// resolves to `.standard`, which renders byte-identically to the pre-art-
// direction app. Deep Field (and every other shipped theme) has no entry, so
// the `DesignThemeTests` pixel guarantee is untouched by construction.

/// One radial "glow pool" layered between the screen gradient and the
/// texture — the nebula/atmosphere wash a flat 3-stop gradient can't express.
struct ThemeGlowPool: Equatable, Sendable {
    /// Pool color including its opacity (pools stack additively).
    let color: Color
    /// Center in unit space. May sit outside 0…1 (e.g. y = -0.1 pins the
    /// bloom above the screen, matching the handoffs' off-canvas gradients).
    let centerX: Double
    let centerY: Double
    /// End radius as a fraction of the screen's larger dimension.
    let radiusFraction: Double
    /// Slow whole-pool opacity breathing (Karaoke Supernova's `roomPulse`,
    /// 5s ease-in-out between `pulseMinOpacity` and 1). `nil` = static pool —
    /// the default, so every existing pool renders byte-identically. Under
    /// Reduce Motion a pulsing pool freezes at `pulseMinOpacity` (the CSS
    /// animation's 0% keyframe).
    var pulsePeriod: TimeInterval? = nil
    var pulseMinOpacity: Double = 0.6

    var center: UnitPoint { UnitPoint(x: centerX, y: centerY) }
}

/// Speck field for the `.starfield` background texture. The texture has no
/// theme-neutral look — a starfield theme must curate its own hues.
struct ThemeStarfield: Equatable, Sendable {
    /// Speck hues, cycled across the field (opacity applied per speck).
    let colors: [Color]
    /// Total speck count across all drift layers.
    var count: Int = 56
    /// Multiplier on the per-layer drift speed (1.0 ≈ the handoff's 24s pan).
    var driftScale: Double = 1.0
}

/// Data-driven atmosphere motion — the Swift port of a handoff's multi-layer
/// tiled `background-image` pan (Event Horizon's `.page-bg` + `starfieldDrift`).
/// Each layer is one repeating speck tile; the whole layer translates by
/// `driftPerLoop` over one `period` and wraps, so the loop is seamless when
/// each drift component is a whole multiple of the tile size (the handoffs
/// always pan by exactly one tile). Rendered by `AtmosphereMotionField`
/// (Talaria/Core/HUD/ThemeTextures.swift) — app target only, never widgets.
struct AtmosphereMotionSpec: Equatable, Sendable {
    struct Layer: Equatable, Sendable {
        /// Square tile edge (pt) — one speck per tile.
        let tileSize: CGFloat
        /// Displacement (pt) over one full period. Scalars, not CGVector,
        /// for the same Equatable/Sendable conservatism as `ThemeGlowPool`.
        let driftX: CGFloat
        let driftY: CGFloat
        /// Speck color (opacity carried separately in `speckAlpha`).
        let hue: Color
        /// Per-speck fill opacity.
        let speckAlpha: Double
        /// Speck center inside its tile, unit coords — the CSS
        /// `radial-gradient(circle at 20% 30%, …)` anchor. Staggered anchors
        /// keep the layers from aligning into a visible lattice.
        var anchorX: Double = 0.5
        var anchorY: Double = 0.5
        /// Speck radius (pt). The design's speck is
        /// `radial-gradient(circle, hue 0, transparent 2px)` — a point that
        /// FADES OUT by 2px, not a 2pt solid disc. A hard 2pt fill translated
        /// to ~12 physical px of flat color ("confetti", the first device
        /// verdict); the design look is a smaller center softened by the
        /// renderer's blur (AtmosphereMotionField).
        var speckRadius: CGFloat = 1.25
        /// Tile height (pt) when the lattice is non-square — Karaoke
        /// Supernova's 120×180 laser tiles. `nil` = square (`tileSize`).
        var tileHeight: CGFloat? = nil
        /// When set, the speck renders as a vertical capsule `speckRadius × 2`
        /// wide and this tall — the design's `radial-gradient(2px 80px …)`
        /// laser bars — instead of a round point. `nil` = round speck.
        var barHeight: CGFloat? = nil
        /// Multiplier on the renderer's per-layer softening blur. 1.0 = the
        /// starlight falloff (Event Horizon, unchanged); halftone dot fields
        /// (Retro Sci-Fi's comic print — `red 1.5px, transparent 2px`, a
        /// crisp dot with a hair of anti-aliasing) sit near 0.25.
        var blurScale: Double = 1.0
    }

    let layers: [Layer]
    /// Seconds per loop — linear, infinite.
    let period: TimeInterval
    /// Opacity of the whole field (the handoffs' `.page-bg { opacity }`).
    let fieldOpacity: Double
}

/// Data-driven angled line/streak lattice — the Swift port of the handoffs'
/// repeating-linear-gradient page textures. One spec type covers three
/// gallery families (Phase 2 inventory):
///  • continuous lattices — Holo Sushi's dual-tone 0°/90° grid, Cyber
///    Cactus's ±45° crosshatch, Graffiti Galaxy's chat-surface bands;
///  • dark scanline rows (0° lines in black — Glitch Garden / Bubblegum
///    Mecha / Disco Inferno `repeating-linear-gradient(0deg, … rgba(0,0,0,.35))`);
///  • per-tile spray streaks (Graffiti Galaxy's four-angle paint grain) via
///    `segmentLength`.
/// Rendered by `LineFieldTexture` (ThemeTextures.swift) — static, one Canvas,
/// batched stroke per layer. App target only, never widgets.
struct ThemeLineFieldSpec: Equatable, Sendable {
    struct Layer: Equatable, Sendable {
        /// Line direction in degrees: 0 = horizontal rows, 90 = vertical
        /// columns, ±45 = diagonals (measured like the CSS gradients' stripe
        /// direction, not their gradient axis).
        let angleDegrees: Double
        /// Line color (opacity carried separately in `alpha`, matching the
        /// other spec types' hue/alpha split).
        let hue: Color
        let alpha: Double
        /// Perpendicular pitch between lines — or the square tile edge in
        /// streak mode.
        let spacing: CGFloat
        var lineWidth: CGFloat = 1
        /// `nil` = continuous lines. Set = streak mode: one soft dash of this
        /// length per `spacing × spacing` tile (the handoffs'
        /// `linear-gradient(135deg, hue 0, transparent 12px)` spray marks).
        var segmentLength: CGFloat? = nil
    }

    let layers: [Layer]
    /// Opacity of the whole field (the handoffs' `.page-bg { opacity }`).
    let fieldOpacity: Double
}

/// Layered offset title shadows — the comic/graffiti h1 treatments that
/// `ThemeTitleGlow`'s soft radial chain can't express: Retro Sci-Fi's hard
/// `4px 4px 0` print offsets, Graffiti Galaxy's stacked tag shadows, Glitch
/// Garden's ±2px chromatic aberration. Layers with `blur == 0` are ink and
/// ignore the glow pref; layers with `blur > 0` are light and ride it like
/// every other glow. Applied by `View.hudTitleGlow()` alongside (not
/// replacing) `titleGlow` — both default inert.
struct ThemeTitleShadowSpec: Equatable, Sendable {
    struct Layer: Equatable, Sendable {
        let hue: Color
        let alpha: Double
        let offsetX: CGFloat
        let offsetY: CGFloat
        var blur: CGFloat = 0
    }

    let layers: [Layer]
    /// Chromatic-jitter cycle (Glitch Garden's `glitch-text`, 3s — quiet for
    /// ~90% of the cycle, two brief offset scrambles at the end). `nil` =
    /// static shadows. Frozen at the base layout under Reduce Motion (the
    /// CSS animation's 0% keyframe).
    var glitchPeriod: TimeInterval? = nil
}

/// Layered neon glow for screen titles — the handoffs' stacked h1
/// `text-shadow` chains. Applied by `View.hudTitleGlow()` (HUDComponents):
/// tight + mid + wide shadows in `primary`, one outer halo in `secondary`,
/// all riding the glow pref × the theme's `glowScale`.
struct ThemeTitleGlow: Equatable, Sendable {
    /// The tight/mid/wide shadow hue (Event Horizon: triple violet).
    let primary: Color
    /// The widest outer halo hue (Event Horizon: cyan at 90px).
    let secondary: Color
}

/// Halo treatment around HUD panels — an offset rim ring plus an outer glow
/// (the handoffs' `box-shadow: 0 0 0 8px …, 0 0 50px …` framing).
struct ThemePanelHalo: Equatable, Sendable {
    /// Rim ring drawn just outside the panel border (carries its own opacity).
    let ringColor: Color
    /// Outer glow color; opacity is computed from glow intensity × the
    /// theme's `glowScale`, so the Appearance glow pref and light themes
    /// behave exactly like every other `hudGlow`.
    let glowColor: Color
    var glowRadius: CGFloat = 22
}

/// The design's `.spin-ring`: a full-surface starburst of thin spokes —
/// `repeating-conic-gradient(from 0deg, transparent 0deg 2deg, hue 2deg 4deg)`
/// — rotating one full turn per `period` (`horizonSpin`, 30s linear infinite
/// for Event Horizon). Rendered by `RadialSpokeField`.
struct RadialSpokeSpec: Equatable, Sendable {
    /// Spoke color (opacity carried separately in `spokeAlpha`).
    let hue: Color
    /// Per-spoke fill opacity — the design uses 0.03; keep it whisper-quiet.
    let spokeAlpha: Double
    /// Angular width of one lit spoke AND of the gap between spokes, in
    /// degrees (the design's 2°/2° cadence → 90 spokes per turn).
    var segmentDegrees: Double = 2
    /// Seconds per full rotation — linear, infinite. Frozen under Reduce
    /// Motion (rendered at t = 0).
    let period: TimeInterval
}

/// The art-direction payload for one theme. All fields default to "off";
/// `.standard` is the identity treatment every un-listed theme resolves to.
struct ThemeArtDirection: Equatable, Sendable {
    /// Radial glow pools painted over the screen gradient (empty = none).
    var glowPools: [ThemeGlowPool] = []
    /// Tint for the `.embers` texture. `nil` = legacy behavior (the theme's
    /// forge warning color — correct for Solar Forge, overridable per theme).
    var emberTint: Color? = nil
    /// Speck field for the `.starfield` texture (required when the palette
    /// selects `.starfield`; see ThemeArtDirectionTests).
    var starfield: ThemeStarfield? = nil
    /// Panel rim + outer glow treatment (`nil` = flat panels, the default).
    var panelHalo: ThemePanelHalo? = nil
    /// Tiled parallax drift field. When set it supersedes the palette's
    /// static texture in `ThemeTextureView`; `nil` (every theme without a
    /// spec) keeps the pre-motion rendering byte-identical.
    var atmosphereMotion: AtmosphereMotionSpec? = nil
    /// Slow-rotating radial spoke field (`.spin-ring`): the design's
    /// `repeating-conic-gradient(transparent 0-2deg, hue 2-4deg)` starburst
    /// turning over `period`. `nil` = no spokes (the default, byte-identical).
    var radialSpokes: RadialSpokeSpec? = nil
    /// Angled line/streak lattice drawn in the texture slot (below the grid).
    /// When set it supersedes the palette's static texture in
    /// `ThemeTextureView`, after `atmosphereMotion` in the chain. `nil` =
    /// byte-identical to the pre-line-field rendering.
    var lineTexture: ThemeLineFieldSpec? = nil
    /// Dark scanline rows drawn ABOVE the grid — the handoffs stack their
    /// `rgba(0,0,0,.35)` CRT rows on top of the whole screen (`multiply`),
    /// so this field gets its own slot instead of the texture slot. `nil` =
    /// no overlay (the default, byte-identical).
    var scanlineOverlay: ThemeLineFieldSpec? = nil
    /// Neon screen-title glow (`nil` = plain titles, the default).
    var titleGlow: ThemeTitleGlow? = nil
    /// Offset/chromatic title shadows (`nil` = none, the default). Composes
    /// with `titleGlow`; comic themes typically set only this.
    var titleShadow: ThemeTitleShadowSpec? = nil

    /// The identity treatment: no pools, no tints, no halo, no motion.
    static let standard = ThemeArtDirection()
}

// MARK: - Catalog

/// Per-theme art direction, keyed by render identity. Only themes whose
/// handoff specifies non-color art direction appear here — everything else
/// resolves to `.standard` and renders exactly as before this layer existed.
enum ThemeArtDirectionCatalog {

    static let overrides: [ThemeID: ThemeArtDirection] = [
        .eventHorizon: eventHorizon,
    ]

    static func artDirection(for theme: ThemeID) -> ThemeArtDirection {
        overrides[theme] ?? .standard
    }

    // MARK: Event Horizon — design/themes/theme-event-horizon.html
    // Void-black interface lit by infalling matter: accretion-violet bloom
    // pinned above the screen, centered lensed washes, Hawking-cyan and
    // singularity-magenta pools, four-hue drifting starlight, violet-rimmed
    // haloed panels, neon violet+cyan title glow. Values sit AT the handoff's
    // levels — the original quiet translation read flat on device (Lane E
    // Task 3); don't re-tame them without a device pass.

    static let eventHorizon = ThemeArtDirection(
        glowPools: [
            // radial(1200px 800px at 50% -10%, rgba(138,92,255,.12) → 60%)
            ThemeGlowPool(color: Color(hex: 0x8A5CFF, opacity: 0.12),
                          centerX: 0.5, centerY: -0.10, radiusFraction: 0.95),
            // Centered lensed washes — chat-screen::before, design-exact:
            // violet .10 → 30% over cyan .06 → 50%.
            ThemeGlowPool(color: Color(hex: 0x8A5CFF, opacity: 0.10),
                          centerX: 0.5, centerY: 0.5, radiusFraction: 0.30),
            ThemeGlowPool(color: Color(hex: 0x00F0FF, opacity: 0.06),
                          centerX: 0.5, centerY: 0.5, radiusFraction: 0.50),
            // Device-verdict correction: the previous cyan (card::before) and
            // magenta (user-bubble) pools promoted PANEL-local washes to
            // 50-60%-of-screen blooms — on device they swamped the void-black
            // base into a bright blue-teal wash the design never had. Those
            // treatments belong to panels/bubbles, not the screen.
        ],
        // Fail-soft speck field only — the atmosphere motion spec supersedes
        // it in ThemeTextureView. Count matches the handoff's tile density on
        // a phone canvas (~105 specks across the four layers).
        starfield: ThemeStarfield(colors: [
            Color(hex: 0x8A5CFF),   // Accretion Violet
            Color(hex: 0x00F0FF),   // Hawking Cyan
            Color(hex: 0xFFDC50),   // Supernova Gold
            Color(hex: 0xFF2AA8),   // Singularity Magenta
        ], count: 104),
        panelHalo: ThemePanelHalo(
            // Handoff framing: an 8px ring at .06 stacked on a .32 border —
            // a single 1pt rim needs more alpha to carry the same weight.
            ringColor: Color(hex: 0x8A5CFF, opacity: 0.24),
            glowColor: Color(hex: 0x8A5CFF),
            // box-shadow: 0 0 50px rgba(138,92,255,.15) — was 22.
            glowRadius: 40
        ),
        atmosphereMotion: eventHorizonAtmosphere(preset: eventHorizonAtmospherePreset),
        // .spin-ring — the gravitational-lensing starburst, the design's
        // biggest chat-surface drama: gold 2°/2° spokes at .03, one turn
        // per 30s (horizonSpin).
        radialSpokes: RadialSpokeSpec(
            hue: Color(hex: 0xFFDC50),
            spokeAlpha: 0.03,
            period: 30
        ),
        // h1 text-shadow: 10/30px violet, 60px violet .45, 90px cyan .25.
        titleGlow: ThemeTitleGlow(
            primary: Color(hex: 0x8A5CFF),
            secondary: Color(hex: 0x00F0FF)
        )
    )

    // MARK: Event Horizon atmosphere presets (Lane E Task 1)

    /// On-device A/B knob: flip, rebuild, judge — no server round trip.
    /// `.faithful` is the handoff verbatim; `.punchy` pushes opacity/speed;
    /// `.subtle` backs both off. Ships on `.faithful`.
    enum AtmospherePreset {
        case faithful, punchy, subtle
    }

    static let eventHorizonAtmospherePreset: AtmospherePreset = .faithful

    /// The handoff's four `.page-bg` layers (`starfieldDrift`, 24s linear
    /// infinite): tile sizes 90/120/150/110, each layer panning exactly one
    /// tile per loop, speck anchors at the CSS gradient centers.
    static func eventHorizonAtmosphere(preset: AtmospherePreset) -> AtmosphereMotionSpec {
        let alphaScale: Double = (preset == .punchy) ? 1.5 : 1.0
        let layers = [
            AtmosphereMotionSpec.Layer(
                tileSize: 90, driftX: 90, driftY: 90,
                hue: Color(hex: 0x8A5CFF), speckAlpha: 0.12 * alphaScale,   // Accretion Violet
                anchorX: 0.20, anchorY: 0.30),
            AtmosphereMotionSpec.Layer(
                tileSize: 120, driftX: -120, driftY: 120,
                hue: Color(hex: 0x00F0FF), speckAlpha: 0.10 * alphaScale,   // Hawking Cyan
                anchorX: 0.70, anchorY: 0.70),
            AtmosphereMotionSpec.Layer(
                tileSize: 150, driftX: 150, driftY: -150,
                hue: Color(hex: 0xFFDC50), speckAlpha: 0.08 * alphaScale,   // Supernova Gold
                anchorX: 0.50, anchorY: 0.50),
            AtmosphereMotionSpec.Layer(
                tileSize: 110, driftX: -110, driftY: 110,
                hue: Color(hex: 0xFF2AA8), speckAlpha: 0.10 * alphaScale,   // Singularity Magenta
                anchorX: 0.85, anchorY: 0.20),
        ]
        switch preset {
        case .faithful:
            return AtmosphereMotionSpec(layers: layers, period: 24, fieldOpacity: 0.45)
        case .punchy:
            return AtmosphereMotionSpec(layers: layers, period: 18, fieldOpacity: 0.65)
        case .subtle:
            return AtmosphereMotionSpec(layers: layers, period: 30, fieldOpacity: 0.35)
        }
    }
}

// MARK: - Runtime access

extension ThemeRuntime {
    /// Art direction for the active theme. Observation tracks `theme`, so any
    /// view reading this re-renders on a theme switch like palette readers do.
    var artDirection: ThemeArtDirection {
        ThemeArtDirectionCatalog.artDirection(for: theme.themeID)
    }
}
