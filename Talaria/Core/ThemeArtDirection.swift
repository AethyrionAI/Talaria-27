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

    /// The identity treatment: no pools, no tints, no halo.
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

    // MARK: Event Horizon — design/theme-event-horizon.html
    // Void-black interface lit by infalling matter: accretion-violet bloom
    // pinned above the screen, Hawking-cyan and singularity-magenta pools,
    // four-hue drifting lensed starlight, violet-rimmed panels.

    static let eventHorizon = ThemeArtDirection(
        glowPools: [
            // radial(1200px 800px at 50% -10%, rgba(138,92,255,.12) → 60%)
            ThemeGlowPool(color: Color(hex: 0x8A5CFF, opacity: 0.12),
                          centerX: 0.5, centerY: -0.10, radiusFraction: 0.95),
            // Hawking-cyan pool, lower trailing (card/chat nebulas).
            ThemeGlowPool(color: Color(hex: 0x00F0FF, opacity: 0.06),
                          centerX: 0.72, centerY: 0.85, radiusFraction: 0.60),
            // Faint singularity-magenta bloom, upper trailing.
            ThemeGlowPool(color: Color(hex: 0xFF2AA8, opacity: 0.05),
                          centerX: 0.88, centerY: 0.16, radiusFraction: 0.50),
        ],
        starfield: ThemeStarfield(colors: [
            Color(hex: 0x8A5CFF),   // Accretion Violet
            Color(hex: 0x00F0FF),   // Hawking Cyan
            Color(hex: 0xFFDC50),   // Supernova Gold
            Color(hex: 0xFF2AA8),   // Singularity Magenta
        ]),
        panelHalo: ThemePanelHalo(
            ringColor: Color(hex: 0x8A5CFF, opacity: 0.18),
            glowColor: Color(hex: 0x8A5CFF)
        )
    )
}

// MARK: - Runtime access

extension ThemeRuntime {
    /// Art direction for the active theme. Observation tracks `theme`, so any
    /// view reading this re-renders on a theme switch like palette readers do.
    var artDirection: ThemeArtDirection {
        ThemeArtDirectionCatalog.artDirection(for: theme.themeID)
    }
}
