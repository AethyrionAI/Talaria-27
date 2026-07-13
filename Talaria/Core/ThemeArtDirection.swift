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
    /// When set, the drift phase is quantized into this many discrete jumps
    /// per loop — a `steps(N)` TV-noise scramble (authored for the cut Haunted VHS; reusable)
    /// (a smooth 0.9s pan reads as vibration, not static). `nil` = smooth
    /// linear pan, byte-identical for every existing spec.
    var stepCount: Int? = nil
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
        /// Displacement (pt) over one `driftPeriod` loop — Midnight
        /// Aquarium's `causticDrift` background-position pan. Inert (0)
        /// unless the spec sets a `driftPeriod`.
        var driftX: CGFloat = 0
        var driftY: CGFloat = 0
    }

    let layers: [Layer]
    /// Opacity of the whole field (the handoffs' `.page-bg { opacity }`).
    let fieldOpacity: Double
    /// Seconds per drift loop — linear, infinite (`causticDrift 16s`). `nil`
    /// = static field: the pre-drift rendering path, byte-identical, with no
    /// TimelineView cost. Frozen at t = 0 under Reduce Motion (the CSS
    /// animation's 0% keyframe).
    var driftPeriod: TimeInterval? = nil
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

/// A rotated banner pinned to the screen's top-trailing corner — the design's
/// `chat-screen::after` 'TAG' ribbon (Graffiti Galaxy). Rendered by
/// `CornerRibbonView`, clipped by the screen edge like the CSS overflow.
struct ThemeCornerRibbonSpec: Equatable, Sendable {
    /// Banner text, verbatim from the handoff (`content: 'TAG'`).
    let text: String
    /// Text color (`--graf-accent-citron`).
    let textColor: Color
    /// Banner fill (`--graf-accent-pink`).
    let background: Color
    /// Hard on/off blink cycle — a `steps(2)` hard blink (authored for the cut Haunted VHS; reusable):
    /// full opacity for the first half, `blinkMinOpacity` for the second.
    /// `nil` = static ribbon (Graffiti Galaxy's 'TAG'), byte-identical, no
    /// TimelineView. Held at full opacity under Reduce Motion (the CSS
    /// animation's 0% keyframe).
    var blinkPeriod: TimeInterval? = nil
    /// The dimmed half's opacity (`recBlink`'s `opacity: 0.15`).
    var blinkMinOpacity: Double = 0.15
}

/// A full-width horizontal glow band sweeping vertically down the screen —
/// a CRT tracking band (46px, symmetric two-hue profile — authored for the cut Haunted VHS; reusable:
/// transparent → shoulder 35% → center 50% → shoulder 65% → transparent,
/// traveling top −18% → 118% over 6s, linear infinite). The atmosphere
/// engine's laser bars are vertical capsules and can't express a horizontal
/// band's gradient profile, so this is its own minimal spec (the dispatch's
/// pre-authorized third primitive). Rendered by `SweepBarField`
/// (ThemeTextures.swift); under Reduce Motion the band parks at the CSS 0%
/// keyframe (`top: -18%` — off-screen, i.e. absent), exactly the handoff's
/// `prefers-reduced-motion` behavior.
struct ThemeSweepBarSpec: Equatable, Sendable {
    /// Band thickness (pt) — `height: 46px`.
    let height: CGFloat
    /// The 35%/65% stops (`rgba(232,255,232,0.07)`).
    let shoulderColor: Color
    let shoulderAlpha: Double
    /// The 50% stop (`rgba(53,224,255,0.12)`).
    let centerColor: Color
    let centerAlpha: Double
    /// Seconds per sweep — linear, infinite.
    let period: TimeInterval
    /// Travel endpoints for the band's top edge, as fractions of the screen
    /// height (`top: -18%` → `top: 118%`).
    var travelStart: Double = -0.18
    var travelEnd: Double = 1.18
}

/// Thin gradient bar hugging a panel's top edge — the design's
/// `card::before` (4px, 90° multi-hue, opacity .7). Follows the panel's
/// rounded top corners; rendered by the `panelHalo` modifier.
struct ThemePanelTopStripSpec: Equatable, Sendable {
    /// Left-to-right gradient stops (the CSS `linear-gradient(90deg, …)`).
    let colors: [Color]
    /// Bar height in points (`height: 4px`).
    var height: CGFloat = 4
    /// Bar opacity (`opacity: 0.7`).
    var opacity: Double = 0.7
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
    /// Vertically sweeping glow band (`trackingBar`-class; no shipped adopter), drawn
    /// between the grid and the scanline overlay (the handoff's z-order:
    /// the tracking bar rides UNDER the CRT rows). `nil` = no band (the
    /// default, byte-identical).
    var sweepBar: ThemeSweepBarSpec? = nil
    /// Neon screen-title glow (`nil` = plain titles, the default).
    var titleGlow: ThemeTitleGlow? = nil
    /// Offset/chromatic title shadows (`nil` = none, the default). Composes
    /// with `titleGlow`; comic themes typically set only this.
    var titleShadow: ThemeTitleShadowSpec? = nil
    /// Rotated corner banner (`chat-screen::after`) — Graffiti Galaxy's
    /// 'TAG'. `nil` = no ribbon (the default, byte-identical).
    var cornerRibbon: ThemeCornerRibbonSpec? = nil
    /// Thin gradient bar hugging every panel's top edge (`card::before`).
    /// `nil` = no strip (the default, byte-identical).
    var panelTopStrip: ThemePanelTopStripSpec? = nil

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
        .glitchGarden: glitchGarden,
        .witchsBrew: witchsBrew,
        .holoSushi: holoSushi,
        .cerealBox: cerealBox,
        .bubblegumMecha: bubblegumMecha,
        .retroSciFi: retroSciFi,
        .lunarDiner: lunarDiner,
        .cyberCactus: cyberCactus,
        .discoInferno: discoInferno,
        .graffitiGalaxy: graffitiGalaxy,
        .karaokeSupernova: karaokeSupernova,
        .midnightAquarium: midnightAquarium,
        .moltenForge: moltenForge,
        .luchaLibre: luchaLibre,
        .kaijuAttack: kaijuAttack,
        .pulpNoir: pulpNoir,
        .casinoLucky7s: casinoLucky7s,
        .cosmicBowling: cosmicBowling,
        .stickerBombToybox: stickerBombToybox,
        .comicVillain: comicVillain,
        .comicFunnies: comicFunnies,
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

    // MARK: Glitch Garden — design/themes/theme-glitch-garden.html
    // Dead-black CRT greenhouse: green bloom pinned above the screen, a faint
    // cyan under-light, dark scanline rows over the design's own 40px green
    // grid (grid = palette data), and the chromatic-aberration title with the
    // 3s glitch jitter. Recipe rule 2: the cyan wash is `chat-screen::before`
    // (screen-scope by design); the card glass stays panel-scope.

    static let glitchGarden = ThemeArtDirection(
        glowPools: [
            // radial(1200px 800px at 50% -10%, rgba(57,255,20,.10) → 60%)
            ThemeGlowPool(color: Color(hex: 0x39FF14, opacity: 0.10),
                          centerX: 0.5, centerY: -0.10, radiusFraction: 0.95),
            // chat-screen::before: cyan .05 at 50% 100% → 50%, ×.6 layer.
            ThemeGlowPool(color: Color(hex: 0x00F0FF, opacity: 0.03),
                          centerX: 0.5, centerY: 1.0, radiusFraction: 0.50),
        ],
        // page-bg::after: repeating 0deg, black .35 rows 2px on 4px pitch,
        // on the .25-opacity page layer.
        scanlineOverlay: ThemeLineFieldSpec(layers: [
            .init(angleDegrees: 0, hue: Color(hex: 0x000000), alpha: 0.35,
                  spacing: 4, lineWidth: 2),
        ], fieldOpacity: 0.25),
        // h1: 2px 0 magenta, -2px 0 cyan (chromatic ink), 0 0 24px green
        // (glow), scrambling every 3s (glitch-text 92/94/96% keyframes).
        titleShadow: ThemeTitleShadowSpec(layers: [
            .init(hue: Color(hex: 0xFF00AA), alpha: 1.0, offsetX: 2, offsetY: 0),
            .init(hue: Color(hex: 0x00F0FF), alpha: 1.0, offsetX: -2, offsetY: 0),
            .init(hue: Color(hex: 0x39FF14), alpha: 1.0, offsetX: 0, offsetY: 0, blur: 24),
        ], glitchPeriod: 3)
    )

    // MARK: Witch's Brew — design/themes/theme-witchs-brew.html
    // Midnight cauldron: poison bloom above, poison under-light, and the
    // design's static three-hue speck field (mystic/poison/bubble tiles at
    // 120/180/220 — zero drift, the CSS never pans it).

    static let witchsBrew = ThemeArtDirection(
        glowPools: [
            ThemeGlowPool(color: Color(hex: 0x4ADE80, opacity: 0.10),
                          centerX: 0.5, centerY: -0.10, radiusFraction: 0.95),
            // chat-screen::before: poison .06 at 50% 100% → 50%, ×.6 layer.
            ThemeGlowPool(color: Color(hex: 0x4ADE80, opacity: 0.036),
                          centerX: 0.5, centerY: 1.0, radiusFraction: 0.50),
        ],
        // Static field: drift 0 keeps the seamless invariant trivially; the
        // period is inert at zero drift.
        atmosphereMotion: AtmosphereMotionSpec(layers: [
            AtmosphereMotionSpec.Layer(
                tileSize: 120, driftX: 0, driftY: 0,
                hue: Color(hex: 0xA855F7), speckAlpha: 0.15,
                anchorX: 0.30, anchorY: 0.40),
            AtmosphereMotionSpec.Layer(
                tileSize: 180, driftX: 0, driftY: 0,
                hue: Color(hex: 0x4ADE80), speckAlpha: 0.12,
                anchorX: 0.70, anchorY: 0.60),
            AtmosphereMotionSpec.Layer(
                tileSize: 220, driftX: 0, driftY: 0,
                hue: Color(hex: 0xFACC15), speckAlpha: 0.10,
                anchorX: 0.50, anchorY: 0.80),
        ], period: 1, fieldOpacity: 0.25),
        // h1: 0 0 18px poison, 0 0 44px poison .5 — single-hue soft glow.
        titleGlow: ThemeTitleGlow(
            primary: Color(hex: 0x4ADE80),
            secondary: Color(hex: 0x4ADE80)
        )
    )

    // MARK: Holo Sushi — design/themes/theme-holo-sushi.html
    // Glossy neon counter: roe bloom + under-light, and the signature
    // dual-tone holo grid (wasabi verticals × roe horizontals, 24px, ×.35).

    static let holoSushi = ThemeArtDirection(
        glowPools: [
            ThemeGlowPool(color: Color(hex: 0xFF69B4, opacity: 0.10),
                          centerX: 0.5, centerY: -0.10, radiusFraction: 0.95),
            ThemeGlowPool(color: Color(hex: 0xFF69B4, opacity: 0.036),
                          centerX: 0.5, centerY: 1.0, radiusFraction: 0.50),
        ],
        lineTexture: ThemeLineFieldSpec(layers: [
            .init(angleDegrees: 90, hue: Color(hex: 0x00F0FF), alpha: 0.04, spacing: 24),
            .init(angleDegrees: 0, hue: Color(hex: 0xFF69B4), alpha: 0.04, spacing: 24),
        ], fieldOpacity: 0.35),
        titleGlow: ThemeTitleGlow(
            primary: Color(hex: 0xFF69B4),
            secondary: Color(hex: 0xFF69B4)
        )
    )

    // MARK: Cereal Box — design/themes/theme-cereal-box.html (drama retrofit)
    // The shipped recolor never got its handoff atmosphere: berry bloom,
    // milk under-light, and the big soft berry/milk/honey sparkles (8px
    // fade-outs → 5pt centers under the layer blur, recipe rule 1).

    static let cerealBox = ThemeArtDirection(
        glowPools: [
            ThemeGlowPool(color: Color(hex: 0xFF5078, opacity: 0.10),
                          centerX: 0.5, centerY: -0.10, radiusFraction: 0.95),
            ThemeGlowPool(color: Color(hex: 0x00C8FF, opacity: 0.036),
                          centerX: 0.5, centerY: 1.0, radiusFraction: 0.50),
        ],
        atmosphereMotion: AtmosphereMotionSpec(layers: [
            AtmosphereMotionSpec.Layer(
                tileSize: 60, driftX: 0, driftY: 0,
                hue: Color(hex: 0xFF5078), speckAlpha: 0.12,
                anchorX: 0.20, anchorY: 0.30, speckRadius: 5),
            AtmosphereMotionSpec.Layer(
                tileSize: 80, driftX: 0, driftY: 0,
                hue: Color(hex: 0x00C8FF), speckAlpha: 0.12,
                anchorX: 0.70, anchorY: 0.70, speckRadius: 5),
            AtmosphereMotionSpec.Layer(
                tileSize: 100, driftX: 0, driftY: 0,
                hue: Color(hex: 0xFFDC00), speckAlpha: 0.10,
                anchorX: 0.50, anchorY: 0.50, speckRadius: 5),
        ], period: 1, fieldOpacity: 0.3),
        titleGlow: ThemeTitleGlow(
            primary: Color(hex: 0xFF5078),
            secondary: Color(hex: 0xFF5078)
        )
    )

    // MARK: Bubblegum Mecha — design/themes/theme-bubblegum-mecha.html
    // (drama retrofit) Candy bloom + under-light, candy/cyan/yellow sparkle
    // field, and the cockpit's dark scanline rows (`chat-screen::after`,
    // ×.18 multiply).

    static let bubblegumMecha = ThemeArtDirection(
        glowPools: [
            ThemeGlowPool(color: Color(hex: 0xFF6EC7, opacity: 0.10),
                          centerX: 0.5, centerY: -0.10, radiusFraction: 0.95),
            ThemeGlowPool(color: Color(hex: 0xFF6EC7, opacity: 0.036),
                          centerX: 0.5, centerY: 1.0, radiusFraction: 0.50),
        ],
        atmosphereMotion: AtmosphereMotionSpec(layers: [
            AtmosphereMotionSpec.Layer(
                tileSize: 60, driftX: 0, driftY: 0,
                hue: Color(hex: 0xFF6EC7), speckAlpha: 0.12,
                anchorX: 0.20, anchorY: 0.30, speckRadius: 5),
            AtmosphereMotionSpec.Layer(
                tileSize: 80, driftX: 0, driftY: 0,
                hue: Color(hex: 0x00F0FF), speckAlpha: 0.12,
                anchorX: 0.70, anchorY: 0.70, speckRadius: 5),
            AtmosphereMotionSpec.Layer(
                tileSize: 100, driftX: 0, driftY: 0,
                hue: Color(hex: 0xFFE600), speckAlpha: 0.10,
                anchorX: 0.50, anchorY: 0.50, speckRadius: 5),
        ], period: 1, fieldOpacity: 0.3),
        scanlineOverlay: ThemeLineFieldSpec(layers: [
            .init(angleDegrees: 0, hue: Color(hex: 0x000000), alpha: 0.35,
                  spacing: 4, lineWidth: 2),
        ], fieldOpacity: 0.18),
        titleGlow: ThemeTitleGlow(
            primary: Color(hex: 0xFF6EC7),
            secondary: Color(hex: 0xFF6EC7)
        )
    )

    // MARK: Retro Sci-Fi — design/themes/theme-retro-sci-fi.html
    // (drama retrofit) Warm newsprint under comic halftone: yellow sunbeams
    // (top bloom + the 80%/10% corner spot), the two offset red/blue dot
    // lattices (crisp print dots — blurScale 0.25), and faint dark rows on
    // the reading surface. Title = hard 4,4 yellow / 8,8 blue print offsets.

    static let retroSciFi = ThemeArtDirection(
        glowPools: [
            // radial(1200px 800px at 50% -10%, rgba(255,214,0,.18) → 60%)
            ThemeGlowPool(color: Color(hex: 0xFFD600, opacity: 0.18),
                          centerX: 0.5, centerY: -0.10, radiusFraction: 0.95),
            // chat-screen::before: yellow .15 at 80% 10% → 35%, ×.6 layer.
            ThemeGlowPool(color: Color(hex: 0xFFD600, opacity: 0.09),
                          centerX: 0.8, centerY: 0.10, radiusFraction: 0.35),
        ],
        // Halftone: two full-strength dot lattices on a .18 layer, offset by
        // half a tile (anchors .5/.5 vs 0/0), dots ~1.5px fading at 2px —
        // crisp comic print, so the softening blur is nearly off.
        atmosphereMotion: AtmosphereMotionSpec(layers: [
            AtmosphereMotionSpec.Layer(
                tileSize: 12, driftX: 0, driftY: 0,
                hue: Color(hex: 0xFF2D2D), speckAlpha: 1.0,
                anchorX: 0.5, anchorY: 0.5, speckRadius: 1.9, blurScale: 0.25),
            AtmosphereMotionSpec.Layer(
                tileSize: 12, driftX: 0, driftY: 0,
                hue: Color(hex: 0x007BFF), speckAlpha: 1.0,
                anchorX: 0.0, anchorY: 0.0, speckRadius: 1.9, blurScale: 0.25),
        ], period: 1, fieldOpacity: 0.18),
        // chat-messages: black .03 rows, 3px on 6px pitch (direct alpha).
        scanlineOverlay: ThemeLineFieldSpec(layers: [
            .init(angleDegrees: 0, hue: Color(hex: 0x000000), alpha: 0.03,
                  spacing: 6, lineWidth: 3),
        ], fieldOpacity: 1.0),
        // h1: 4px 4px 0 yellow, 8px 8px 0 blue .25 — pure ink, no glow.
        titleShadow: ThemeTitleShadowSpec(layers: [
            .init(hue: Color(hex: 0xFFD600), alpha: 1.0, offsetX: 4, offsetY: 4),
            .init(hue: Color(hex: 0x007BFF), alpha: 0.25, offsetX: 8, offsetY: 8),
        ])
    )

    // MARK: Lunar Diner — design/themes/theme-lunar-diner.html
    // Drive-in on the dark side of the moon: soda bloom + under-light and
    // the static two-layer white starlight lattice (60/120 tiles).

    static let lunarDiner = ThemeArtDirection(
        glowPools: [
            ThemeGlowPool(color: Color(hex: 0xFF9AB4, opacity: 0.10),
                          centerX: 0.5, centerY: -0.10, radiusFraction: 0.95),
            ThemeGlowPool(color: Color(hex: 0xFF9AB4, opacity: 0.036),
                          centerX: 0.5, centerY: 1.0, radiusFraction: 0.50),
        ],
        atmosphereMotion: AtmosphereMotionSpec(layers: [
            AtmosphereMotionSpec.Layer(
                tileSize: 60, driftX: 0, driftY: 0,
                hue: Color(hex: 0xFFFFFF), speckAlpha: 0.15),
            AtmosphereMotionSpec.Layer(
                tileSize: 120, driftX: 0, driftY: 0,
                hue: Color(hex: 0xFFFFFF), speckAlpha: 0.08),
        ], period: 1, fieldOpacity: 0.3),
        titleGlow: ThemeTitleGlow(
            primary: Color(hex: 0xFF9AB4),
            secondary: Color(hex: 0xFF9AB4)
        )
    )

    // MARK: Cyber Cactus — design/themes/theme-cyber-cactus.html
    // Synthwave desert: sunset bloom, succulent under-light, and the
    // signature ±45° two-tone crosshatch (1px lines, 11px pitch, ×.25).

    static let cyberCactus = ThemeArtDirection(
        glowPools: [
            ThemeGlowPool(color: Color(hex: 0xFF5078, opacity: 0.10),
                          centerX: 0.5, centerY: -0.10, radiusFraction: 0.95),
            ThemeGlowPool(color: Color(hex: 0x00DCC8, opacity: 0.036),
                          centerX: 0.5, centerY: 1.0, radiusFraction: 0.50),
        ],
        lineTexture: ThemeLineFieldSpec(layers: [
            .init(angleDegrees: 45, hue: Color(hex: 0x00DCC8), alpha: 0.03, spacing: 11),
            .init(angleDegrees: -45, hue: Color(hex: 0xFF5078), alpha: 0.03, spacing: 11),
        ], fieldOpacity: 0.25),
        titleGlow: ThemeTitleGlow(
            primary: Color(hex: 0xFF5078),
            secondary: Color(hex: 0xFF5078)
        )
    )
    // MARK: Disco Inferno — design/themes/theme-disco-inferno.html
    // Mirror-ball hell: gold bloom, the BRIGHT gold/silver sparkle lattice
    // (.45/.35 — the loudest speck field in the gallery, on a .35 layer),
    // dark scanline rows; the gold dot grid is palette data.

    static let discoInferno = ThemeArtDirection(
        glowPools: [
            // radial(1200px 800px at 50% -10%, rgba(255,215,0,.12) → 60%)
            ThemeGlowPool(color: Color(hex: 0xFFD700, opacity: 0.12),
                          centerX: 0.5, centerY: -0.10, radiusFraction: 0.95),
        ],
        atmosphereMotion: AtmosphereMotionSpec(layers: [
            AtmosphereMotionSpec.Layer(
                tileSize: 24, driftX: 0, driftY: 0,
                hue: Color(hex: 0xFFD700), speckAlpha: 0.45),
            AtmosphereMotionSpec.Layer(
                tileSize: 12, driftX: 0, driftY: 0,
                hue: Color(hex: 0xE8E8E8), speckAlpha: 0.35,
                anchorX: 0.0, anchorY: 0.0),
        ], period: 1, fieldOpacity: 0.35),
        scanlineOverlay: ThemeLineFieldSpec(layers: [
            .init(angleDegrees: 0, hue: Color(hex: 0x000000), alpha: 0.35,
                  spacing: 4, lineWidth: 2),
        ], fieldOpacity: 0.18),
        titleGlow: ThemeTitleGlow(
            primary: Color(hex: 0xFFD700),
            secondary: Color(hex: 0xFFD700)
        )
    )

    // MARK: Graffiti Galaxy — design/themes/theme-graffiti-galaxy.html (SE)
    // Street art in orbit: violet nebula bloom, the four-angle spray-streak
    // grain (40px tiles, 12px fades) merged with the chat surface's citron/
    // spray diagonal bands into one line field (page + screen paint the same
    // z-plane behind content), pink-ringed violet-glow panels (the design's
    // `0 0 0 6px pink` + `0 0 50px violet` chat frame → panel halo, EH
    // precedent), and the stacked tag-shadow title. Deferred, per the
    // inventory table: the "TAG" corner ribbon (text overlay on live UI),
    // the citron outline echo (no text-stroke primitive), clipped bubble
    // corners + citron pip (bubble-scope), card gradient top-strip (no
    // panel-strip primitive — Owen call).

    static let graffitiGalaxy = ThemeArtDirection(
        glowPools: [
            // radial(1200px 800px at 50% -10%, rgba(131,56,236,.12) → 60%)
            ThemeGlowPool(color: Color(hex: 0x8338EC, opacity: 0.12),
                          centerX: 0.5, centerY: -0.10, radiusFraction: 0.95),
        ],
        panelHalo: ThemePanelHalo(
            // 6px ring at .08 → single-pt rim at the EH compression (.24).
            ringColor: Color(hex: 0xFF006E, opacity: 0.24),
            glowColor: Color(hex: 0x8338EC),
            glowRadius: 40
        ),
        // Layer alphas carry their CSS layer opacities pre-multiplied
        // (page streaks ×.45, screen bands ×.6) so one field renders both.
        lineTexture: ThemeLineFieldSpec(layers: [
            .init(angleDegrees: 135, hue: Color(hex: 0xFF006E), alpha: 0.045,
                  spacing: 40, lineWidth: 2.5, segmentLength: 12),
            .init(angleDegrees: 225, hue: Color(hex: 0x8338EC), alpha: 0.045,
                  spacing: 40, lineWidth: 2.5, segmentLength: 12),
            .init(angleDegrees: 45, hue: Color(hex: 0x00F5D4), alpha: 0.036,
                  spacing: 40, lineWidth: 2.5, segmentLength: 12),
            .init(angleDegrees: 315, hue: Color(hex: 0xFBFF26), alpha: 0.036,
                  spacing: 40, lineWidth: 2.5, segmentLength: 12),
            .init(angleDegrees: 135, hue: Color(hex: 0xFBFF26), alpha: 0.036,
                  spacing: 30, lineWidth: 2.1),
            .init(angleDegrees: 45, hue: Color(hex: 0x00F5D4), alpha: 0.03,
                  spacing: 30, lineWidth: 2.1),
        ], fieldOpacity: 1.0),
        // h1: 3px 3px 0 violet, 6px 6px 0 pink .45 (ink), 0 0 40px pink .35.
        titleShadow: ThemeTitleShadowSpec(layers: [
            .init(hue: Color(hex: 0x8338EC), alpha: 1.0, offsetX: 3, offsetY: 3),
            .init(hue: Color(hex: 0xFF006E), alpha: 0.45, offsetX: 6, offsetY: 6),
            .init(hue: Color(hex: 0xFF006E), alpha: 0.35, offsetX: 0, offsetY: 0, blur: 40),
        ]),
        // chat-screen::after — the 'TAG' throwie: citron on pink, rotated
        // into the top-trailing corner (Owen-approved correction round).
        cornerRibbon: ThemeCornerRibbonSpec(
            text: "TAG",
            textColor: Color(hex: 0xFBFF26),
            background: Color(hex: 0xFF006E)
        ),
        // card::before — 4px 90° pink→violet→spray→citron strip at .7.
        panelTopStrip: ThemePanelTopStripSpec(colors: [
            Color(hex: 0xFF006E),
            Color(hex: 0x8338EC),
            Color(hex: 0x00F5D4),
            Color(hex: 0xFBFF26),
        ])
    )

    // MARK: Karaoke Supernova — design/themes/theme-karaoke-supernova.html (SE)
    // Private booth at 1 AM: magenta stage bloom, the roomPulse corner
    // spotlights (magenta/cyan .12/.10 breathing .6↔1 over 5s — the gold top
    // band ported as a whisper radial at the screen top, linear→radial
    // approximation noted in the PR), four drifting laser bars (2×80pt on
    // non-square tiles, one tile per 18s — the handoff's laserSweep),
    // magenta-framed panels, and the exact EH-shape title glow
    // (magenta 10/30/60 + cyan 90). Deferred: bobbing ♪ bubble pip
    // (bubble-scope), card::after top wash (EH precedent drops card washes),
    // subtitle pulse chip (gallery chrome).

    static let karaokeSupernova = ThemeArtDirection(
        glowPools: [
            ThemeGlowPool(color: Color(hex: 0xFF00AA, opacity: 0.12),
                          centerX: 0.5, centerY: -0.10, radiusFraction: 0.95),
            // chat-screen::before, breathing together (roomPulse 5s, .6↔1).
            ThemeGlowPool(color: Color(hex: 0xFF00AA, opacity: 0.12),
                          centerX: 0.2, centerY: 0.2, radiusFraction: 0.25,
                          pulsePeriod: 5),
            ThemeGlowPool(color: Color(hex: 0x00F0FF, opacity: 0.10),
                          centerX: 0.8, centerY: 0.8, radiusFraction: 0.25,
                          pulsePeriod: 5),
            ThemeGlowPool(color: Color(hex: 0xFFE600, opacity: 0.03),
                          centerX: 0.5, centerY: 0.0, radiusFraction: 0.40,
                          pulsePeriod: 5),
        ],
        panelHalo: ThemePanelHalo(
            // 8px ring at .06 → .24 rim (the EH compression, same values).
            ringColor: Color(hex: 0xFF00AA, opacity: 0.24),
            glowColor: Color(hex: 0xFF00AA),
            glowRadius: 40
        ),
        // laserSweep: each bar layer pans exactly one (non-square) tile per
        // 18s loop — magenta/cyan/gold/laser 2×80 bars, anchors from the
        // CSS gradient positions.
        atmosphereMotion: AtmosphereMotionSpec(layers: [
            AtmosphereMotionSpec.Layer(
                tileSize: 120, driftX: 120, driftY: 180,
                hue: Color(hex: 0xFF00AA), speckAlpha: 0.35,
                anchorX: 0.20, anchorY: 0.10, speckRadius: 1,
                tileHeight: 180, barHeight: 80),
            AtmosphereMotionSpec.Layer(
                tileSize: 160, driftX: -160, driftY: 220,
                hue: Color(hex: 0x00F0FF), speckAlpha: 0.30,
                anchorX: 0.50, anchorY: 0.30, speckRadius: 1,
                tileHeight: 220, barHeight: 80),
            AtmosphereMotionSpec.Layer(
                tileSize: 200, driftX: 200, driftY: -260,
                hue: Color(hex: 0xFFE600), speckAlpha: 0.25,
                anchorX: 0.80, anchorY: 0.60, speckRadius: 1,
                tileHeight: 260, barHeight: 80),
            AtmosphereMotionSpec.Layer(
                tileSize: 140, driftX: -140, driftY: 200,
                hue: Color(hex: 0xFF2A6D), speckAlpha: 0.30,
                anchorX: 0.35, anchorY: 0.80, speckRadius: 1,
                tileHeight: 200, barHeight: 80),
        ], period: 18, fieldOpacity: 0.35),
        // h1: 10/30px magenta, 60px magenta .45, 90px cyan .25 — the exact
        // Event Horizon text-shadow shape.
        titleGlow: ThemeTitleGlow(
            primary: Color(hex: 0xFF00AA),
            secondary: Color(hex: 0x00F0FF)
        )
    )

    // MARK: Midnight Aquarium — design/themes/theme-midnight-aquarium.html (SE, batch 4)
    // After-hours aquarium: pink bloom pinned above the tank, three-hue
    // bubble columns climbing the glass (bubbleRise 14s — driftY is exactly
    // one tile per loop; the small lateral driftX values are verbatim and
    // reset mid-tile at the loop point exactly as the CSS's own
    // background-position snap does), and the ±105° caustic lattices gliding
    // on the new line-field drift (causticDrift 16s — both fields stack,
    // bubbles below caustics, the handoff's DOM order). Pink-framed panels
    // (EH halo compression), EH-shape pink/teal title glow. Deferred, per
    // the inventory table: the chat-screen 11s bubble pair + 12s caustic
    // (panel-scope layers on a second period — the screen field already
    // paints behind chat, and the EH device verdict keeps panel-scope
    // treatments panel-scope), the inset teal tank wash (panel inner wash),
    // bubble pips / input / send chrome (bubble- and accent-system scope).
    // Abyss Gold #FFD166 is gallery badge chrome — N/A.

    static let midnightAquarium = ThemeArtDirection(
        glowPools: [
            // radial(1200px 800px at 50% -10%, rgba(255,122,217,.10) → 60%)
            ThemeGlowPool(color: Color(hex: 0xFF7AD9, opacity: 0.10),
                          centerX: 0.5, centerY: -0.10, radiusFraction: 0.95),
        ],
        panelHalo: ThemePanelHalo(
            // 8px ring at .06 on the .32 border → 1pt rim at the EH compression.
            ringColor: Color(hex: 0xFF7AD9, opacity: 0.24),
            glowColor: Color(hex: 0xFF7AD9),
            glowRadius: 40
        ),
        // bubbleRise: three non-square bubble columns, each rising exactly
        // one tile height per 14s loop. Speck centers at the CSS fade radii
        // (3/2.2/2.6px) × the rule-1 soft-port ratio 0.625.
        atmosphereMotion: AtmosphereMotionSpec(layers: [
            AtmosphereMotionSpec.Layer(
                tileSize: 130, driftX: 20, driftY: -520,
                hue: Color(hex: 0x3EF2E0), speckAlpha: 0.4,
                anchorX: 0.25, anchorY: 0.85, speckRadius: 1.875,
                tileHeight: 520),
            AtmosphereMotionSpec.Layer(
                tileSize: 170, driftX: -30, driftY: -640,
                hue: Color(hex: 0xFF7AD9), speckAlpha: 0.35,
                anchorX: 0.60, anchorY: 0.95, speckRadius: 1.375,
                tileHeight: 640),
            AtmosphereMotionSpec.Layer(
                tileSize: 210, driftX: 10, driftY: -760,
                hue: Color(hex: 0x8A7CFF), speckAlpha: 0.3,
                anchorX: 0.85, anchorY: 0.75, speckRadius: 1.625,
                tileHeight: 760),
        ], period: 14, fieldOpacity: 0.4),
        // causticDrift: the two ±105° lattices — 4px lines on 38/50px pitch,
        // panning (240,120) / (−240,−80) per 16s loop.
        lineTexture: ThemeLineFieldSpec(layers: [
            .init(angleDegrees: 105, hue: Color(hex: 0x3EF2E0), alpha: 0.05,
                  spacing: 38, lineWidth: 4, driftX: 240, driftY: 120),
            .init(angleDegrees: -105, hue: Color(hex: 0xFF7AD9), alpha: 0.04,
                  spacing: 50, lineWidth: 4, driftX: -240, driftY: -80),
        ], fieldOpacity: 0.6, driftPeriod: 16),
        // h1: 10/30px pink, 60px pink .45, 90px teal .25 — the EH shape.
        titleGlow: ThemeTitleGlow(
            primary: Color(hex: 0xFF7AD9),
            secondary: Color(hex: 0x3EF2E0)
        )
    )

    // MARK: Molten Forge — design/themes/theme-molten-forge.html (SE, batch 4)
    // Volcanic smithy: lava bloom above, three-hue emberRise columns
    // (orange / spark gold / ember red — the fourth hue lives here and on
    // the orb halo, the Karaoke laser-red precedent), and the heatShimmer
    // bottom glow ported as a PULSING POOL anchored at the bottom edge —
    // approximation-first per the Karaoke gold-band precedent, because the
    // CSS layer is a page-scope linear band breathing opacity .5↔.85 with a
    // scaleY 1→1.05 that is sub-perceptual on a soft gradient (choice noted
    // in the PR; pool color .17 = the band's .20 × its .85 peak, min .59 =
    // .50/.85, so the rendered opacity range is exactly the CSS's .10–.17).
    // emberTint is inert here: the atmosphere spec supersedes the `.embers`
    // texture, so no Solar Forge values are reused anywhere (Owen mandate —
    // the variant-set diff lives in the palette entry + PR). Deferred, per
    // the inventory table: the chat-screen 8s ember pair and 3.5s/45%
    // shimmer variant (panel-scope layers on second periods).

    static let moltenForge = ThemeArtDirection(
        glowPools: [
            // radial(1200px 800px at 50% -10%, rgba(255,106,26,.10) → 60%)
            ThemeGlowPool(color: Color(hex: 0xFF6A1A, opacity: 0.10),
                          centerX: 0.5, centerY: -0.10, radiusFraction: 0.95),
            // heatShimmer: fixed bottom 40% band, rgba(255,106,26,.20) → up,
            // 4s ease-in-out breathe (see the approximation note above).
            ThemeGlowPool(color: Color(hex: 0xFF6A1A, opacity: 0.17),
                          centerX: 0.5, centerY: 1.0, radiusFraction: 0.40,
                          pulsePeriod: 4, pulseMinOpacity: 0.59),
        ],
        panelHalo: ThemePanelHalo(
            // 8px ring at .06 on the .32 border → 1pt rim at the EH compression.
            ringColor: Color(hex: 0xFF6A1A, opacity: 0.24),
            glowColor: Color(hex: 0xFF6A1A),
            glowRadius: 40
        ),
        // emberRise: three non-square ember columns, one tile height up per
        // 10s loop; lateral driftX verbatim (the CSS's own mid-tile loop
        // snap, same as Midnight Aquarium). Speck centers at the CSS fade
        // radii (2.5/2/2px) × the rule-1 soft-port ratio 0.625.
        atmosphereMotion: AtmosphereMotionSpec(layers: [
            AtmosphereMotionSpec.Layer(
                tileSize: 120, driftX: -30, driftY: -420,
                hue: Color(hex: 0xFF6A1A), speckAlpha: 0.5,
                anchorX: 0.30, anchorY: 0.80, speckRadius: 1.5625,
                tileHeight: 420),
            AtmosphereMotionSpec.Layer(
                tileSize: 160, driftX: 40, driftY: -560,
                hue: Color(hex: 0xFFD23C), speckAlpha: 0.45,
                anchorX: 0.60, anchorY: 0.90, speckRadius: 1.25,
                tileHeight: 560),
            AtmosphereMotionSpec.Layer(
                tileSize: 200, driftX: -20, driftY: -680,
                hue: Color(hex: 0xFF3B2D), speckAlpha: 0.4,
                anchorX: 0.80, anchorY: 0.70, speckRadius: 1.25,
                tileHeight: 680),
        ], period: 10, fieldOpacity: 0.45),
        // h1: 10/30px lava, 60px lava .45, 90px spark gold .25 — the EH shape.
        titleGlow: ThemeTitleGlow(
            primary: Color(hex: 0xFF6A1A),
            secondary: Color(hex: 0xFFD23C)
        )
    )
    // MARK: Lucha Libre — midnight-marquee-final-lineup.html §1b (Lane L)
    // The arena after the families go home: royal-blue bloom above the ring,
    // two skewed pyro/chrome spotlight shafts (glowPulse 4s — ported as
    // pulsing corner pools; the skewed linear shaft geometry has no
    // primitive, approximation noted in the PR), the static two-hue crowd
    // dot field, blue-framed panels, and the layered pyro/chrome print
    // offsets under a royal-blue title glow.

    static let luchaLibre = ThemeArtDirection(
        glowPools: [
            // radial(1100px 700px at 50% -10%, rgba(61,107,255,.14) → 60%)
            ThemeGlowPool(color: Color(hex: 0x3D6BFF, opacity: 0.14),
                          centerX: 0.5, centerY: -0.10, radiusFraction: 0.95),
            // Spotlight shafts: chrome left (12%), pyro right (86%), each
            // breathing on the design's 4s glowPulse.
            ThemeGlowPool(color: Color(hex: 0xCCD6E8, opacity: 0.10),
                          centerX: 0.16, centerY: 0.10, radiusFraction: 0.50,
                          pulsePeriod: 4, pulseMinOpacity: 0.6),
            ThemeGlowPool(color: Color(hex: 0xFF7A29, opacity: 0.10),
                          centerX: 0.86, centerY: 0.10, radiusFraction: 0.50,
                          pulsePeriod: 4, pulseMinOpacity: 0.6),
        ],
        panelHalo: ThemePanelHalo(
            // 0 0 0 8px rgba(61,107,255,.07), 0 0 50px .16 → EH compression.
            ringColor: Color(hex: 0x3D6BFF, opacity: 0.24),
            glowColor: Color(hex: 0x3D6BFF),
            glowRadius: 40
        ),
        // Crowd dots: royal 26px / pyro 34px lattices on the .30 page layer
        // (specks fade at 2.5px → rule-1 soft-port centers 1.5625).
        atmosphereMotion: AtmosphereMotionSpec(layers: [
            AtmosphereMotionSpec.Layer(
                tileSize: 26, driftX: 0, driftY: 0,
                hue: Color(hex: 0x3D6BFF), speckAlpha: 0.35,
                anchorX: 0.30, anchorY: 0.30, speckRadius: 1.5625),
            AtmosphereMotionSpec.Layer(
                tileSize: 34, driftX: 0, driftY: 0,
                hue: Color(hex: 0xFF7A29), speckAlpha: 0.28,
                anchorX: 0.70, anchorY: 0.60, speckRadius: 1.5625),
        ], period: 1, fieldOpacity: 0.30),
        // h1: 0 0 14px royal .6 (glow layer), 4px 4px 0 pyro, 8px 8px 0
        // chrome .35 (ink offsets) — one composed shadow stack.
        titleShadow: ThemeTitleShadowSpec(layers: [
            .init(hue: Color(hex: 0xFF7A29), alpha: 1.0, offsetX: 4, offsetY: 4),
            .init(hue: Color(hex: 0xCCD6E8), alpha: 0.35, offsetX: 8, offsetY: 8),
            .init(hue: Color(hex: 0x3D6BFF), alpha: 0.6, offsetX: 0, offsetY: 0, blur: 14),
        ])
    )

    // MARK: Kaiju Attack — midnight-marquee-final-lineup.html §1c (Lane L)
    // Night siege: siren bloom, the rotating searchlight fan (the design's
    // two 8° amber beams orbSpin 24s — RadialSpokeSpec draws an 8°/8°
    // cadence, the closest the spoke primitive expresses; noted in the PR),
    // static green/red city dots, siren-framed panels, and the red/green
    // chromatic print title. The top hazard-stripe banner is deferred
    // (top-masked screen layer — no mask primitive).

    static let kaijuAttack = ThemeArtDirection(
        glowPools: [
            // radial(1100px 700px at 50% -10%, rgba(255,68,56,.12) → 60%)
            ThemeGlowPool(color: Color(hex: 0xFF4438, opacity: 0.12),
                          centerX: 0.5, centerY: -0.10, radiusFraction: 0.95),
        ],
        panelHalo: ThemePanelHalo(
            ringColor: Color(hex: 0xFF4438, opacity: 0.24),
            glowColor: Color(hex: 0xFF4438),
            glowRadius: 40
        ),
        // City dots: green 30px / red 38px lattices on the .25 page layer.
        atmosphereMotion: AtmosphereMotionSpec(layers: [
            AtmosphereMotionSpec.Layer(
                tileSize: 30, driftX: 0, driftY: 0,
                hue: Color(hex: 0x6AFF57), speckAlpha: 0.3,
                anchorX: 0.30, anchorY: 0.30, speckRadius: 1.5625),
            AtmosphereMotionSpec.Layer(
                tileSize: 38, driftX: 0, driftY: 0,
                hue: Color(hex: 0xFF4438), speckAlpha: 0.3,
                anchorX: 0.70, anchorY: 0.60, speckRadius: 1.5625),
        ], period: 1, fieldOpacity: 0.25),
        // Searchlight sweep: amber wedges rgba(255,210,89,.10) on the .5
        // conic layer, one turn per 24s.
        radialSpokes: RadialSpokeSpec(
            hue: Color(hex: 0xFFD259),
            spokeAlpha: 0.05,
            segmentDegrees: 8,
            period: 24
        ),
        // h1: 0 0 16px siren .6, 4px 4px 0 siren, -3px -3px 0 green .5.
        titleShadow: ThemeTitleShadowSpec(layers: [
            .init(hue: Color(hex: 0xFF4438), alpha: 1.0, offsetX: 4, offsetY: 4),
            .init(hue: Color(hex: 0x6AFF57), alpha: 0.5, offsetX: -3, offsetY: -3),
            .init(hue: Color(hex: 0xFF4438), alpha: 0.6, offsetX: 0, offsetY: 0, blur: 16),
        ])
    )

    // MARK: Pulp Noir — midnight-marquee-final-lineup.html §1f (Lane L, light)
    // The dime-store paperback: crimson masthead bloom, sun-fade corner
    // washes (mustard top-left, crimson bottom-right — the page's two
    // aging ellipses ported as pools on their .25 layer), and the crimson
    // print offset under the typewriter title. Paper tooth is palette data
    // (9px ink dot grid + .paperGrain); panels print hard offset ink
    // shadows in the design, so there is deliberately no panelHalo (glow
    // is not this theme's language).

    static let pulpNoir = ThemeArtDirection(
        glowPools: [
            // radial(1100px 700px at 50% -10%, rgba(179,56,46,.08) → 60%)
            ThemeGlowPool(color: Color(hex: 0xB3382E, opacity: 0.08),
                          centerX: 0.5, centerY: -0.10, radiusFraction: 0.95),
            // Sun-fade washes: mustard .25 at 15% 8%, crimson .12 at 90% 95%,
            // both on the .25 page layer.
            ThemeGlowPool(color: Color(hex: 0xC8912B, opacity: 0.0625),
                          centerX: 0.15, centerY: 0.08, radiusFraction: 0.35),
            ThemeGlowPool(color: Color(hex: 0xB3382E, opacity: 0.03),
                          centerX: 0.90, centerY: 0.95, radiusFraction: 0.30),
        ],
        // h1: 2px 2px 0 crimson .35 — pure ink, no glow.
        titleShadow: ThemeTitleShadowSpec(layers: [
            .init(hue: Color(hex: 0xB3382E), alpha: 0.35, offsetX: 2, offsetY: 2),
        ])
    )

    // MARK: Casino Lucky 7s — midnight-marquee-final-lineup.html §1g (Lane L)
    // The high-limit table: jackpot-gold bloom over deep felt, gold-framed
    // panels, and the cherry print offset under the gold title glow. The
    // felt dot lattice is palette grid data (Disco precedent); the blinking
    // marquee-bulb edge rows are deferred (no screen-edge strip primitive —
    // noted in the PR).

    static let casinoLucky7s = ThemeArtDirection(
        glowPools: [
            // radial(1100px 700px at 50% -10%, rgba(255,210,74,.12) → 60%)
            ThemeGlowPool(color: Color(hex: 0xFFD24A, opacity: 0.12),
                          centerX: 0.5, centerY: -0.10, radiusFraction: 0.95),
        ],
        panelHalo: ThemePanelHalo(
            // 0 0 0 8px rgba(255,210,74,.05), 0 0 50px .12 → EH compression.
            ringColor: Color(hex: 0xFFD24A, opacity: 0.24),
            glowColor: Color(hex: 0xFFD24A),
            glowRadius: 40
        ),
        // h1: 0 0 16px gold .55, 3px 3px 0 cherry.
        titleShadow: ThemeTitleShadowSpec(layers: [
            .init(hue: Color(hex: 0xFF4757), alpha: 1.0, offsetX: 3, offsetY: 3),
            .init(hue: Color(hex: 0xFFD24A), alpha: 0.55, offsetX: 0, offsetY: 0, blur: 16),
        ])
    )

    // MARK: Cosmic Bowling — midnight-marquee-final-lineup.html §1j (Lane L)
    // Carpet Classic: teal bloom, the immortal alley-carpet speck field
    // (teal/coral/grape confetti on non-square tiles) with the grape
    // squiggle diagonal as a sparse line lattice (the design's one streak
    // per 220×180 tile ≈ a 200pt continuous pitch — approximation noted),
    // teal-framed panels, and the coral/grape print offsets under a teal
    // glow. The lane sheen is deferred (a horizontally-traveling vertical
    // band — sweepBar only travels vertically).

    static let cosmicBowling = ThemeArtDirection(
        glowPools: [
            // radial(1100px 700px at 50% -10%, rgba(0,179,164,.12) → 60%)
            ThemeGlowPool(color: Color(hex: 0x00B3A4, opacity: 0.12),
                          centerX: 0.5, centerY: -0.10, radiusFraction: 0.95),
        ],
        panelHalo: ThemePanelHalo(
            ringColor: Color(hex: 0x00B3A4, opacity: 0.24),
            glowColor: Color(hex: 0x00B3A4),
            glowRadius: 40
        ),
        // Carpet confetti: teal 130×110 / coral 110×95 / grape 160×130
        // tiles on the .28 page layer (fades 4 / 3.5 / 4.5px → rule-1
        // centers 2.5 / 2.1875 / 2.8125).
        atmosphereMotion: AtmosphereMotionSpec(layers: [
            AtmosphereMotionSpec.Layer(
                tileSize: 130, driftX: 0, driftY: 0,
                hue: Color(hex: 0x00B3A4), speckAlpha: 0.5,
                anchorX: 0.20, anchorY: 0.30, speckRadius: 2.5,
                tileHeight: 110),
            AtmosphereMotionSpec.Layer(
                tileSize: 110, driftX: 0, driftY: 0,
                hue: Color(hex: 0xFF6257), speckAlpha: 0.45,
                anchorX: 0.60, anchorY: 0.65, speckRadius: 2.1875,
                tileHeight: 95),
            AtmosphereMotionSpec.Layer(
                tileSize: 160, driftX: 0, driftY: 0,
                hue: Color(hex: 0x8455E0), speckAlpha: 0.5,
                anchorX: 0.85, anchorY: 0.25, speckRadius: 2.8125,
                tileHeight: 130),
        ], period: 1, fieldOpacity: 0.28),
        // The grape squiggle: 35° lines (CSS-angle verbatim, the aquarium
        // 105° precedent) at the carpet tile pitch.
        lineTexture: ThemeLineFieldSpec(layers: [
            .init(angleDegrees: 35, hue: Color(hex: 0x8455E0), alpha: 0.25,
                  spacing: 200, lineWidth: 2),
        ], fieldOpacity: 0.28),
        // h1: 0 0 12px teal .6, 3px 3px 0 coral .55, 6px 6px 0 grape .4.
        titleShadow: ThemeTitleShadowSpec(layers: [
            .init(hue: Color(hex: 0xFF6257), alpha: 0.55, offsetX: 3, offsetY: 3),
            .init(hue: Color(hex: 0x8455E0), alpha: 0.4, offsetX: 6, offsetY: 6),
            .init(hue: Color(hex: 0x00B3A4), alpha: 0.6, offsetX: 0, offsetY: 0, blur: 12),
        ])
    )

    // MARK: Sticker-Bomb Toybox — midnight-marquee-final-lineup.html §1k (Lane L, light)
    // Kidcore Shelf in daylight: a whisper of grape bloom and the big soft
    // sticker dots (grape/tangerine/slime on 140/170/190 tiles, the page's
    // .5 layer — fades at 4px → rule-1 centers 2.5). Grape/tangerine print
    // offsets under the marker title; hard toy-plastic panel shadows are
    // the design's panel language, so no panelHalo (print, not glow).

    static let stickerBombToybox = ThemeArtDirection(
        glowPools: [
            // radial(1100px 700px at 50% -10%, rgba(140,82,255,.08) → 60%)
            ThemeGlowPool(color: Color(hex: 0x8C52FF, opacity: 0.08),
                          centerX: 0.5, centerY: -0.10, radiusFraction: 0.95),
        ],
        atmosphereMotion: AtmosphereMotionSpec(layers: [
            AtmosphereMotionSpec.Layer(
                tileSize: 140, driftX: 0, driftY: 0,
                hue: Color(hex: 0x8C52FF), speckAlpha: 0.18,
                anchorX: 0.25, anchorY: 0.25, speckRadius: 2.5,
                tileHeight: 120),
            AtmosphereMotionSpec.Layer(
                tileSize: 170, driftX: 0, driftY: 0,
                hue: Color(hex: 0xFF8A2B), speckAlpha: 0.18,
                anchorX: 0.70, anchorY: 0.60, speckRadius: 2.5,
                tileHeight: 150),
            AtmosphereMotionSpec.Layer(
                tileSize: 190, driftX: 0, driftY: 0,
                hue: Color(hex: 0x4BBF22), speckAlpha: 0.18,
                anchorX: 0.45, anchorY: 0.80, speckRadius: 2.5,
                tileHeight: 160),
        ], period: 1, fieldOpacity: 0.5),
        // h1: 3px 3px 0 grape .4, -2px -2px 0 tangerine .35 — pure ink.
        titleShadow: ThemeTitleShadowSpec(layers: [
            .init(hue: Color(hex: 0x8C52FF), alpha: 0.4, offsetX: 3, offsetY: 3),
            .init(hue: Color(hex: 0xFF8A2B), alpha: 0.35, offsetX: -2, offsetY: -2),
        ])
    )

    // MARK: Comic Book (dark) — Villain Variant, midnight-marquee-final-lineup.html §2a
    // (Lane L Phase 2 — the collection's most animated theme.) Kapow bloom,
    // the DRIFTING half of the halftone (yellow 34px lattice — the static
    // white lattice is palette grid data; the CSS pans both +36px/8s, ported
    // as one whole tile (34,34) per loop for the seamless invariant,
    // sub-perceptual delta noted in the PR), raking 105° speed lines panning
    // on the design's speedShift (−260px x / 3s), yellow-framed red-glow
    // panels, and the off-register title: red/yellow print offsets + yellow
    // glow scrambling on the inkShake 6s beat (titleShadow's glitch
    // mechanic). Deferred: the localized Kirby-krackle twinkle cluster
    // (a corner-pinned opacity-pulsing dot cluster — no primitive) and the
    // POW-burst badge (title-side gallery chrome; the orb carries the burst).

    static let comicVillain = ThemeArtDirection(
        glowPools: [
            // radial(1100px 700px at 50% -10%, rgba(255,216,40,.10) → 60%)
            ThemeGlowPool(color: Color(hex: 0xFFD828, opacity: 0.10),
                          centerX: 0.5, centerY: -0.10, radiusFraction: 0.95),
        ],
        panelHalo: ThemePanelHalo(
            // 0 0 0 8px rgba(255,216,40,.06), 0 0 50px rgba(255,43,43,.12).
            ringColor: Color(hex: 0xFFD828, opacity: 0.24),
            glowColor: Color(hex: 0xFF2B2B),
            glowRadius: 40
        ),
        // The drifting yellow half of the halftone (dotDrift 8s).
        atmosphereMotion: AtmosphereMotionSpec(layers: [
            AtmosphereMotionSpec.Layer(
                tileSize: 34, driftX: 34, driftY: 34,
                hue: Color(hex: 0xFFD828), speckAlpha: 0.25,
                anchorX: 0.70, anchorY: 0.60, speckRadius: 1.5625),
        ], period: 8, fieldOpacity: 0.25),
        // Speed lines: 105° ink-white raking pair (2px at .5 + 1px at .3 on
        // a 160px cycle), panning the design's speedShift −260px per 3s.
        lineTexture: ThemeLineFieldSpec(layers: [
            .init(angleDegrees: 105, hue: Color(hex: 0xF5F2FF), alpha: 0.5,
                  spacing: 160, lineWidth: 2, driftX: -260, driftY: 0),
            .init(angleDegrees: 105, hue: Color(hex: 0xF5F2FF), alpha: 0.3,
                  spacing: 160, lineWidth: 1, driftX: -260, driftY: 0),
        ], fieldOpacity: 0.14, driftPeriod: 3),
        // h1: 4px 4px 0 red, 8px 8px 0 yellow .35 (ink), 0 0 16px yellow .45
        // (glow), shaking off-register every 6s (inkShake).
        titleShadow: ThemeTitleShadowSpec(layers: [
            .init(hue: Color(hex: 0xFF2B2B), alpha: 1.0, offsetX: 4, offsetY: 4),
            .init(hue: Color(hex: 0xFFD828), alpha: 0.35, offsetX: 8, offsetY: 8),
            .init(hue: Color(hex: 0xFFD828), alpha: 0.45, offsetX: 0, offsetY: 0, blur: 16),
        ], glitchPeriod: 6)
    )

    // MARK: Comic Book (light) — Sunday Funnies, midnight-marquee-final-lineup.html §2b
    // (Lane L Phase 2.) Warm newsprint under drifting Ben-Day process dots
    // (cyan 22px + magenta 30px, dotDrift 10s — whole-tile drift per loop),
    // 75° panel-ink speed lines on the 4s speedShift, and the press-shake
    // title (cyan/magenta print offsets, inkShake 7s). Print language:
    // deliberately no panelHalo — the design's panels carry hard cyan offset
    // shadows (bubble-scope, deferred like every panel-scope treatment).

    static let comicFunnies = ThemeArtDirection(
        glowPools: [
            // radial(1100px 700px at 50% -10%, rgba(0,168,232,.08) → 60%)
            ThemeGlowPool(color: Color(hex: 0x00A8E8, opacity: 0.08),
                          centerX: 0.5, centerY: -0.10, radiusFraction: 0.95),
        ],
        // Ben-Day drift: cyan 22px .22 / magenta 30px .16 on the .5 page
        // layer (fades 3.5 / 3px → rule-1 centers 2.1875 / 1.875).
        atmosphereMotion: AtmosphereMotionSpec(layers: [
            AtmosphereMotionSpec.Layer(
                tileSize: 22, driftX: 22, driftY: 22,
                hue: Color(hex: 0x00A8E8), speckAlpha: 0.22,
                anchorX: 0.25, anchorY: 0.25, speckRadius: 2.1875),
            AtmosphereMotionSpec.Layer(
                tileSize: 30, driftX: 30, driftY: 30,
                hue: Color(hex: 0xFF3D7F), speckAlpha: 0.16,
                anchorX: 0.60, anchorY: 0.60, speckRadius: 1.875),
        ], period: 10, fieldOpacity: 0.5),
        // Speed lines: 75° panel ink, 2px on a 110px cycle at .6, panning
        // the 4s speedShift.
        lineTexture: ThemeLineFieldSpec(layers: [
            .init(angleDegrees: 75, hue: Color(hex: 0x1F1A24), alpha: 0.6,
                  spacing: 110, lineWidth: 2, driftX: -260, driftY: 0),
        ], fieldOpacity: 0.10, driftPeriod: 4),
        // h1: 4px 4px 0 cyan .5, 8px 8px 0 magenta .35 — pure ink,
        // press-shaking every 7s.
        titleShadow: ThemeTitleShadowSpec(layers: [
            .init(hue: Color(hex: 0x00A8E8), alpha: 0.5, offsetX: 4, offsetY: 4),
            .init(hue: Color(hex: 0xFF3D7F), alpha: 0.35, offsetX: 8, offsetY: 8),
        ], glitchPeriod: 7)
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
    /// Art direction for the active theme. Observation tracks `theme` (and
    /// `systemColorScheme` for the adaptive Comic Book), so any view reading
    /// this re-renders on a theme or appearance switch like palette readers.
    var artDirection: ThemeArtDirection {
        ThemeArtDirectionCatalog.artDirection(for: theme.themeID(for: systemColorScheme))
    }
}
