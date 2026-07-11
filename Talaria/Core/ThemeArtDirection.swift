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
    }

    let layers: [Layer]
    /// Seconds per loop — linear, infinite.
    let period: TimeInterval
    /// Opacity of the whole field (the handoffs' `.page-bg { opacity }`).
    let fieldOpacity: Double
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
    /// Neon screen-title glow (`nil` = plain titles, the default).
    var titleGlow: ThemeTitleGlow? = nil

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
            // Centered lensed washes — chat-screen::before, violet .10 → 30%
            // over cyan .06 → 50%. The main surface glow the quiet
            // translation dropped.
            ThemeGlowPool(color: Color(hex: 0x8A5CFF, opacity: 0.10),
                          centerX: 0.5, centerY: 0.5, radiusFraction: 0.35),
            ThemeGlowPool(color: Color(hex: 0x00F0FF, opacity: 0.06),
                          centerX: 0.5, centerY: 0.5, radiusFraction: 0.55),
            // Hawking-cyan pool, lower trailing (card::before, .08 → 35%).
            ThemeGlowPool(color: Color(hex: 0x00F0FF, opacity: 0.08),
                          centerX: 0.72, centerY: 0.85, radiusFraction: 0.60),
            // Singularity-magenta bloom, upper trailing — magenta reads at
            // .10 everywhere in the handoff (starfield layer, user bubble).
            ThemeGlowPool(color: Color(hex: 0xFF2AA8, opacity: 0.10),
                          centerX: 0.88, centerY: 0.16, radiusFraction: 0.50),
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
