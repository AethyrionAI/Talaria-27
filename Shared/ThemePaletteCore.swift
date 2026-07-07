import SwiftUI

// MARK: - Theme palette core
// The single source of truth for every theme/accent color in Talaria. This file
// is compiled into BOTH the app target and TalariaWidgets (see project.yml
// `Shared` sources) so the widgets can render theme palettes without importing
// the app's ThemeRuntime. Keep it dependency-free: SwiftUI value types only.
//
// Model: a THEME owns the whole visual environment (background, foreground
// ramp, surfaces, borders, texture, grid); the ACCENT is one of three abstract
// slots the theme re-interprets as its own hue family. Slot `.cyan` is always
// the theme's hero accent (Cyan Arc / Forge Amber / Phosphor Green / Tracker
// Red), so untouched defaults land on each theme's canonical hue.
//
// Deep Field × cyan is byte-identical to the pre-theming Design constants —
// verified by TalariaTests/DesignThemeTests. Do not retune those values.

/// Theme identity, decoupled from the app's `AppearanceTheme` (same raw values).
enum ThemeID: String, CaseIterable, Codable, Hashable, Sendable {
    case deepField
    case solarForge
    case terminal
    case paperTape
    case winterFrost
    case summerSolar
    case springSprout
    case autumnHarvest
    case cerealBox
    case bubblegumMecha
    case retroSciFi
    case eventHorizon
}

/// Accent slot identity, decoupled from the app's `AppearanceAccent`
/// (same raw values — these are persisted, never rename).
enum AccentSlot: String, CaseIterable, Codable, Hashable, Sendable {
    case cyan
    case amber
    case violet
}

extension ThemeID {
    /// A theme whose identity IS a single hue exposes no accent choice: palette
    /// resolution pins the effective slot to this hero regardless of the
    /// persisted accent, so a slot picked under another theme can't bleed
    /// through (#12). The stored pref stays untouched — switching away restores
    /// the user's prior accent. `nil` = the theme re-interprets all three slots.
    /// Carried as catalog data (#49), not a hard-coded special case.
    var lockedAccentSlot: AccentSlot? {
        ThemePaletteCatalog.definition(for: self).lockedAccentSlot
    }
}

/// How `GridOverlay` draws the background grid for a theme.
enum ThemeGridStyle: Hashable, Sendable {
    /// Vertical + horizontal hairlines (Deep Field, Solar Forge).
    case lines
    /// Dot lattice at the intersections (Terminal phosphor pitch).
    case dots
    /// Horizontal rules only (Paper Tape ledger).
    case rules
}

/// Which background texture `ThemeTextureView` draws behind the grid.
enum ThemeBackgroundTexture: Hashable, Sendable {
    case none
    /// Slow-drifting warm ember specks (Solar Forge). Static under Reduce Motion.
    case embers
    /// Static phosphor scanline rows (Terminal).
    case scanlines
    /// Static ink speckle + fiber grain (Paper Tape).
    case paperGrain
    /// Drifting multi-hue star specks (Event Horizon lensed starlight).
    /// Speck hues come from the app-side `ThemeArtDirectionCatalog` — widgets
    /// never draw textures, so the shared palette only *selects* this.
    case starfield
}

/// Which of `ReactorOrb`'s view compositions a theme renders. Like
/// `ThemeBackgroundTexture`, the drawing code stays in the view; the theme
/// data only *selects* a composition, so a new catalog theme can reuse an
/// existing orb without touching `ReactorOrb.swift` (#49).
enum ThemeOrbStyle: Hashable, Sendable {
    /// The original arc-reactor rings + glowing core (Deep Field).
    case arcReactor
    /// Heavier concentric rings around an ember core (Solar Forge).
    case forgeSun
    /// Thin ring + crosshair ticks, CRT-bloomed core (Terminal).
    case crtCrosshair
    /// Mechanical reel: sprocket holes + tick ring + inked hub (Paper Tape).
    case paperReel
}

/// One stop of the screen's radial background gradient.
struct ThemeGradientStop: Equatable, Sendable {
    let color: Color
    let location: Double
}

// MARK: - Palette data model (#49)
// Everything below describes a theme as pure data. `ThemePalette` resolves a
// (theme, accent) pair by looking the theme up in `ThemePaletteCatalog` —
// there are no per-theme switch arms left in resolution, so a new theme is
// one catalog entry.

/// The six-step foreground ramp of a theme (or of an accent variant, for
/// themes whose whole foreground follows the accent — Terminal's phosphor).
struct ThemeForegroundRamp: Equatable, Sendable {
    let foreground: Color
    let foregroundBright: Color
    let secondaryForeground: Color
    let mutedForeground: Color
    let dimForeground: Color
    let coolForeground: Color
}

/// How a theme's neutral chip/divider chrome resolves.
enum ThemeChipStyle: Equatable, Sendable {
    /// Fixed neutral colors, independent of accent slot.
    case fixed(surface: Color, divider: Color, border: Color)
    /// Derived from the resolved ramp's `secondaryForeground` at these
    /// opacities (Terminal — even the neutral chrome follows the phosphor).
    case foregroundTinted(surface: Double, divider: Double, border: Double)
}

/// How a theme's hairline / strong borders resolve.
enum ThemeBorderStyle: Equatable, Sendable {
    /// Borders are the resolved accent base at these opacities (dark themes).
    case accentTinted(hairline: Double, strong: Double)
    /// Fixed border colors — Paper Tape ink; borders shouldn't read as
    /// colored marks on paper.
    case fixed(hairline: Color, strong: Color)
}

/// How the background grid lines are colored.
enum ThemeGridLineStyle: Equatable, Sendable {
    /// The resolved accent base at this opacity.
    case accentTinted(Double)
    /// A fixed color independent of the accent.
    case fixed(Color)
}

/// One accent slot as a theme re-interprets it: the accent family, the slot's
/// contextual display name, the warning accent kept separable from it, and —
/// for themes whose environment follows the accent — optional overrides of
/// the theme-level environment.
struct ThemeAccentVariant: Equatable, Sendable {
    /// Contextual UI label for the slot inside this theme (e.g. the `.amber`
    /// slot reads "Cyan · Plasma" on Solar Forge).
    let displayName: String

    // Accent family
    let base: Color
    let bright: Color
    let deep: Color
    let coreHighlight: Color
    let coreShadow: Color

    /// Warning ("forge") accent as resolved for this slot — curated per slot
    /// so it always stays separable from `base` (e.g. distinct orange when
    /// the accent itself is an amber).
    let forge: Color

    // Environment pieces that follow the accent instead of the theme
    // (Terminal: the whole CRT re-tints to the selected phosphor).
    // `nil` = use the theme-level value.
    var ramp: ThemeForegroundRamp? = nil
    var screenGradientStops: [ThemeGradientStop]? = nil
    var drawerColors: [Color]? = nil
    var surface: Color? = nil
}

/// All three accent slots of a theme. A struct (not a dictionary) so a
/// definition cannot ship with a missing slot — totality is compile-checked.
struct ThemeAccentVariants: Equatable, Sendable {
    let cyan: ThemeAccentVariant
    let amber: ThemeAccentVariant
    let violet: ThemeAccentVariant

    /// Keyed access over the fixed slot set (not per-theme data logic).
    subscript(slot: AccentSlot) -> ThemeAccentVariant {
        switch slot {
        case .cyan: cyan
        case .amber: amber
        case .violet: violet
        }
    }
}

/// The complete curated data for one theme: environment, foreground ramp,
/// surface/border rules, semantic colors, per-slot accent variants, and
/// behavior knobs. This is the payload `ThemePalette(theme:accent:)` resolves
/// from — adding a theme means adding one of these to `ThemePaletteCatalog`.
struct ThemePaletteDefinition: Equatable, Sendable {
    /// A theme whose identity IS a single hue pins resolution to this slot
    /// regardless of the persisted accent (#12) — data, not a special case.
    let lockedAccentSlot: AccentSlot?

    // Environment
    let background: Color
    let screenGradientStops: [ThemeGradientStop]
    let drawerColors: [Color]
    let texture: ThemeBackgroundTexture

    /// Theme-level foreground ramp (a variant may override it wholesale).
    let ramp: ThemeForegroundRamp

    // Surfaces / borders
    let surface: Color
    let chips: ThemeChipStyle
    let borders: ThemeBorderStyle
    let scrim: Color

    // Semantic colors (accent-independent; per-slot warning lives on the variant)
    let danger: Color
    let dangerBright: Color

    /// The three accent slots as this theme re-interprets them.
    let accents: ThemeAccentVariants

    // Behavior knobs
    let glowScale: Double
    let gridStyle: ThemeGridStyle
    let gridLine: ThemeGridLineStyle
    let gridCell: CGFloat
    let isLight: Bool
    let orbStyle: ThemeOrbStyle
}

/// The fully resolved color environment for one (theme, accent) pair.
/// Everything `Design.Brand` / `Design.Colors` exposes resolves through this.
struct ThemePalette: Equatable, Sendable {

    // Environment
    let background: Color
    let screenGradientStops: [ThemeGradientStop]
    let drawerColors: [Color]
    let texture: ThemeBackgroundTexture

    // Foreground ramp
    let foreground: Color
    let foregroundBright: Color
    let secondaryForeground: Color
    let mutedForeground: Color
    let dimForeground: Color
    let coolForeground: Color

    // Surfaces / borders
    let surface: Color
    let chipSurface: Color
    let divider: Color
    let chipBorder: Color
    let hairline: Color
    let strongBorder: Color
    let scrim: Color

    // Accent family (resolved slot)
    let base: Color
    let bright: Color
    let deep: Color
    let coreHighlight: Color
    let coreShadow: Color

    // Semantic colors
    let forge: Color
    let danger: Color
    let dangerBright: Color

    // Behavior knobs
    /// Multiplier applied inside `hudGlow` — 1.0 on the dark themes, ≈0 on
    /// Paper Tape where glows become faint ink shadows.
    let glowScale: Double
    let gridStyle: ThemeGridStyle
    let gridLineColor: Color
    let gridCell: CGFloat
    let isLight: Bool
    /// Which `ReactorOrb` composition this theme renders.
    let orbStyle: ThemeOrbStyle

    init(theme: ThemeID, accent: AccentSlot) {
        self.init(definition: ThemePaletteCatalog.definition(for: theme), accent: accent)
    }

    /// Resolve one (definition, accent) pair into the flat palette every view
    /// consumes. All *values* live in the definition; the only logic here is
    /// the locked-slot pin (#12), variant fallbacks, and the tint rules.
    init(definition: ThemePaletteDefinition, accent: AccentSlot) {
        // Locked themes (Terminal) resolve their hero slot no matter what
        // accent was persisted — the single pin point for the app, the
        // Appearance previews, and both widget resolution paths (#12).
        let slot = definition.lockedAccentSlot ?? accent
        let variant = definition.accents[slot]
        let ramp = variant.ramp ?? definition.ramp

        background = definition.background
        screenGradientStops = variant.screenGradientStops ?? definition.screenGradientStops
        drawerColors = variant.drawerColors ?? definition.drawerColors
        texture = definition.texture

        foreground = ramp.foreground
        foregroundBright = ramp.foregroundBright
        secondaryForeground = ramp.secondaryForeground
        mutedForeground = ramp.mutedForeground
        dimForeground = ramp.dimForeground
        coolForeground = ramp.coolForeground

        surface = variant.surface ?? definition.surface
        switch definition.chips {
        case let .fixed(surfaceColor, dividerColor, borderColor):
            chipSurface = surfaceColor
            divider = dividerColor
            chipBorder = borderColor
        case let .foregroundTinted(surfaceOpacity, dividerOpacity, borderOpacity):
            chipSurface = ramp.secondaryForeground.opacity(surfaceOpacity)
            divider = ramp.secondaryForeground.opacity(dividerOpacity)
            chipBorder = ramp.secondaryForeground.opacity(borderOpacity)
        }
        switch definition.borders {
        case let .accentTinted(hairlineOpacity, strongOpacity):
            hairline = variant.base.opacity(hairlineOpacity)
            strongBorder = variant.base.opacity(strongOpacity)
        case let .fixed(hairlineColor, strongColor):
            hairline = hairlineColor
            strongBorder = strongColor
        }
        scrim = definition.scrim

        base = variant.base
        bright = variant.bright
        deep = variant.deep
        coreHighlight = variant.coreHighlight
        coreShadow = variant.coreShadow

        forge = variant.forge
        danger = definition.danger
        dangerBright = definition.dangerBright

        glowScale = definition.glowScale
        gridStyle = definition.gridStyle
        switch definition.gridLine {
        case let .accentTinted(opacity):
            gridLineColor = variant.base.opacity(opacity)
        case let .fixed(color):
            gridLineColor = color
        }
        gridCell = definition.gridCell
        isLight = definition.isLight
        orbStyle = definition.orbStyle
    }
}

// MARK: - Palette catalog (#49)
// The render-layer data catalog: every theme's curated palette definition,
// keyed by render identity. The app-level `ThemeCatalog` (identity /
// availability / gating, app target only) references these payloads; this
// catalog lives in Shared so the widget target resolves the same data.

enum ThemePaletteCatalog {

    /// Every shipped theme's definition, keyed by render identity. Adding a
    /// theme = one entry here (+ its `ThemeID` case and app-catalog
    /// `ThemeDefinition`) — no switch-arm edits anywhere in resolution.
    static let definitions: [ThemeID: ThemePaletteDefinition] = [
        .deepField: deepField,
        .solarForge: solarForge,
        .terminal: terminal,
        .paperTape: paperTape,
        .winterFrost: winterFrost,
        .summerSolar: summerSolar,
        .springSprout: springSprout,
        .autumnHarvest: autumnHarvest,
        .cerealBox: cerealBox,
        .bubblegumMecha: bubblegumMecha,
        .retroSciFi: retroSciFi,
        .eventHorizon: eventHorizon,
    ]

    /// Total lookup over the shipped themes (coverage guarded by
    /// `DesignThemeTests`). The Deep Field fallback exists so a future gap
    /// fails visibly in Debug instead of crashing resolution in Release.
    static func definition(for theme: ThemeID) -> ThemePaletteDefinition {
        guard let definition = definitions[theme] else {
            assertionFailure("ThemePaletteCatalog has no definition for \(theme.rawValue)")
            return deepField
        }
        return definition
    }

    // MARK: Deep Field — the original arc-reactor HUD (values byte-identical
    // to the pre-theming constants; cyan/amber/violet keep their meanings —
    // verified by TalariaTests/DesignThemeTests. Do not retune).

    static let deepField = ThemePaletteDefinition(
        lockedAccentSlot: nil,
        background: Color(hex: 0x06080C),
        screenGradientStops: [
            ThemeGradientStop(color: Color(hex: 0x0C2730), location: 0.0),
            ThemeGradientStop(color: Color(hex: 0x070D15), location: 0.52),
            ThemeGradientStop(color: Color(hex: 0x04070C), location: 1.0),
        ],
        drawerColors: [Color(hex: 0x0A1822), Color(hex: 0x060C13), Color(hex: 0x05090F)],
        texture: .none,
        ramp: ThemeForegroundRamp(
            foreground: Color(hex: 0xE8EEF5),
            foregroundBright: Color(hex: 0xEAF6F8),
            secondaryForeground: Color(hex: 0x7C93A6),
            mutedForeground: Color(hex: 0x5D7488),
            dimForeground: Color(hex: 0x4D6273),
            coolForeground: Color(hex: 0xCFE1EA)
        ),
        surface: Color(hex: 0x08121A, opacity: 0.6),
        chips: .fixed(
            surface: Color(hex: 0x7896AF, opacity: 0.08),
            divider: Color(hex: 0x7896AF, opacity: 0.16),
            border: Color(hex: 0x7896AF, opacity: 0.22)
        ),
        borders: .accentTinted(hairline: 0.14, strong: 0.30),
        scrim: Color(hex: 0x02060A, opacity: 0.85),
        danger: Color(hex: 0xE0625F),
        dangerBright: Color(hex: 0xFF8A86),
        accents: ThemeAccentVariants(
            cyan: ThemeAccentVariant(   // hero — Cyan Arc
                displayName: "Cyan · Arc",
                base: Color(hex: 0x54E6F0),
                bright: Color(hex: 0xCDF8FB),
                deep: Color(hex: 0x14636E),
                coreHighlight: Color(hex: 0xE2FBFD),
                coreShadow: Color(hex: 0x0F5867),
                forge: Color(hex: 0xFFC14D)
            ),
            amber: ThemeAccentVariant(
                displayName: "Amber · Forge",
                base: Color(hex: 0xFFC14D),
                bright: Color(hex: 0xFFE2A6),
                deep: Color(hex: 0x6E4D14),
                coreHighlight: Color(hex: 0xFFF1D2),
                coreShadow: Color(hex: 0x3E2C08),
                // Warning stays separable from the accent: distinct orange
                // under the amber slot (pre-theming behavior).
                forge: Color(hex: 0xFF7A18)
            ),
            violet: ThemeAccentVariant(
                displayName: "Violet · Flux",
                base: Color(hex: 0xB18CFF),
                bright: Color(hex: 0xE2D4FF),
                deep: Color(hex: 0x3A2D6E),
                coreHighlight: Color(hex: 0xF1E8FF),
                coreShadow: Color(hex: 0x241A47),
                forge: Color(hex: 0xFFC14D)
            )
        ),
        glowScale: 1.0,
        gridStyle: .lines,
        gridLine: .accentTinted(0.05),
        gridCell: 26,
        isLight: false,
        orbStyle: .arcReactor
    )

    // MARK: Solar Forge — industrial forge: brass, ember, warm metal.
    // Hero slot is the forge amber; cyan/violet become exotic plasma hues.

    static let solarForge = ThemePaletteDefinition(
        lockedAccentSlot: nil,
        background: Color(hex: 0x080602),
        screenGradientStops: [
            ThemeGradientStop(color: Color(hex: 0x2A1A0C), location: 0.0),
            ThemeGradientStop(color: Color(hex: 0x120C07), location: 0.52),
            ThemeGradientStop(color: Color(hex: 0x080602), location: 1.0),
        ],
        drawerColors: [Color(hex: 0x22150A), Color(hex: 0x130B06), Color(hex: 0x0D0804)],
        texture: .embers,
        ramp: ThemeForegroundRamp(
            foreground: Color(hex: 0xF5E8D8),
            foregroundBright: Color(hex: 0xFAF3E7),
            secondaryForeground: Color(hex: 0xB8A58F),
            mutedForeground: Color(hex: 0x8F7B66),
            dimForeground: Color(hex: 0x7D6B5A),
            coolForeground: Color(hex: 0xE3D2BC)
        ),
        surface: Color(hex: 0x1A140E, opacity: 0.6),
        chips: .fixed(
            surface: Color(hex: 0xAF8A5F, opacity: 0.08),
            divider: Color(hex: 0xAF8A5F, opacity: 0.16),
            border: Color(hex: 0xAF8A5F, opacity: 0.22)
        ),
        borders: .accentTinted(hairline: 0.14, strong: 0.30),
        scrim: Color(hex: 0x0A0502, opacity: 0.85),
        danger: Color(hex: 0xE0625F),
        dangerBright: Color(hex: 0xFF8A86),
        accents: ThemeAccentVariants(
            cyan: ThemeAccentVariant(   // hero — Forge Amber
                displayName: "Amber · Forge",
                base: Color(hex: 0xFFC14D),
                bright: Color(hex: 0xFFE2A6),
                deep: Color(hex: 0x6E4D14),
                coreHighlight: Color(hex: 0xFFF1D2),
                coreShadow: Color(hex: 0x3E2C08),
                // Warning must stay separable from an amber-family accent.
                forge: Color(hex: 0xFF7A18)
            ),
            amber: ThemeAccentVariant(  // Plasma Cyan
                displayName: "Cyan · Plasma",
                base: Color(hex: 0x54E6F0),
                bright: Color(hex: 0xCDF8FB),
                deep: Color(hex: 0x14636E),
                coreHighlight: Color(hex: 0xE2FBFD),
                coreShadow: Color(hex: 0x0F5867),
                forge: Color(hex: 0xFFC14D)
            ),
            violet: ThemeAccentVariant( // Violet Flux
                displayName: "Violet · Flux",
                base: Color(hex: 0xB18CFF),
                bright: Color(hex: 0xE2D4FF),
                deep: Color(hex: 0x3A2D6E),
                coreHighlight: Color(hex: 0xF1E8FF),
                coreShadow: Color(hex: 0x241A47),
                forge: Color(hex: 0xFFC14D)
            )
        ),
        glowScale: 1.0,
        gridStyle: .lines,
        gridLine: .fixed(Color(hex: 0xC89B5A, opacity: 0.06)),
        gridCell: 26,
        isLight: false,
        orbStyle: .forgeSun
    )

    // MARK: Terminal — CRT phosphor on true black. The whole environment
    // (foreground ramp, gradients, drawers, surface) follows the selected
    // phosphor, so the non-hero variants override it wholesale. The theme's
    // identity IS the phosphor green: `lockedAccentSlot` pins resolution to
    // the hero (#12), so the amber / IBM-cyan variants are curated but
    // unreachable until the lock is ever lifted.

    static let terminal = ThemePaletteDefinition(
        lockedAccentSlot: .cyan,
        background: Color(hex: 0x000000),
        screenGradientStops: [
            ThemeGradientStop(color: Color(hex: 0x0A140A), location: 0.0),
            ThemeGradientStop(color: Color(hex: 0x040A04), location: 0.52),
            ThemeGradientStop(color: Color(hex: 0x000000), location: 1.0),
        ],
        drawerColors: [Color(hex: 0x0A120A), Color(hex: 0x050905), Color(hex: 0x020402)],
        texture: .scanlines,
        ramp: ThemeForegroundRamp(
            foreground: Color(hex: 0xD8FFD0),
            foregroundBright: Color(hex: 0xEDFFE8),
            secondaryForeground: Color(hex: 0x7BC96A),
            mutedForeground: Color(hex: 0x55A046),
            dimForeground: Color(hex: 0x3D7A32),
            coolForeground: Color(hex: 0xC0EFB4)
        ),
        surface: Color(hex: 0x0A0F0A, opacity: 0.7),
        // Even the neutral chrome follows the phosphor.
        chips: .foregroundTinted(surface: 0.08, divider: 0.16, border: 0.22),
        // Stronger hairlines for the CRT feel.
        borders: .accentTinted(hairline: 0.25, strong: 0.45),
        scrim: Color(hex: 0x000000, opacity: 0.88),
        danger: Color(hex: 0xFF4D42),
        dangerBright: Color(hex: 0xFF8A80),
        accents: ThemeAccentVariants(
            cyan: ThemeAccentVariant(   // hero — Phosphor Green (theme-level env IS this variant's)
                displayName: "Green · Phosphor",
                base: Color(hex: 0x33FF00),
                bright: Color(hex: 0xB6FF9E),
                deep: Color(hex: 0x0E6B00),
                coreHighlight: Color(hex: 0xE4FFDB),
                coreShadow: Color(hex: 0x0A4A00),
                forge: Color(hex: 0xFFB000)
            ),
            amber: ThemeAccentVariant(  // Amber Phosphor
                displayName: "Amber · Phosphor",
                base: Color(hex: 0xFFB000),
                bright: Color(hex: 0xFFDD8A),
                deep: Color(hex: 0x7A5400),
                coreHighlight: Color(hex: 0xFFF0C8),
                coreShadow: Color(hex: 0x4A3300),
                // Warning must stay separable from an amber phosphor accent.
                forge: Color(hex: 0xFF6A00),
                ramp: ThemeForegroundRamp(
                    foreground: Color(hex: 0xFFE8C2),
                    foregroundBright: Color(hex: 0xFFF4DE),
                    secondaryForeground: Color(hex: 0xCC9A55),
                    mutedForeground: Color(hex: 0xA0793F),
                    dimForeground: Color(hex: 0x7A5C2E),
                    coolForeground: Color(hex: 0xF2D9A8)
                ),
                screenGradientStops: [
                    ThemeGradientStop(color: Color(hex: 0x140F04), location: 0.0),
                    ThemeGradientStop(color: Color(hex: 0x0A0703), location: 0.52),
                    ThemeGradientStop(color: Color(hex: 0x000000), location: 1.0),
                ],
                drawerColors: [Color(hex: 0x120D05), Color(hex: 0x090603), Color(hex: 0x030201)],
                surface: Color(hex: 0x100C05, opacity: 0.7)
            ),
            violet: ThemeAccentVariant( // IBM Cyan
                displayName: "Cyan · IBM",
                base: Color(hex: 0x3BD6E0),
                bright: Color(hex: 0xBEF2F7),
                deep: Color(hex: 0x0F5B63),
                coreHighlight: Color(hex: 0xE0FBFD),
                coreShadow: Color(hex: 0x0A434A),
                forge: Color(hex: 0xFFB000),
                ramp: ThemeForegroundRamp(
                    foreground: Color(hex: 0xD2F4F7),
                    foregroundBright: Color(hex: 0xE8FBFC),
                    secondaryForeground: Color(hex: 0x6FB8BF),
                    mutedForeground: Color(hex: 0x4E8F96),
                    dimForeground: Color(hex: 0x386B71),
                    coolForeground: Color(hex: 0xBEEAEE)
                ),
                screenGradientStops: [
                    ThemeGradientStop(color: Color(hex: 0x041214), location: 0.0),
                    ThemeGradientStop(color: Color(hex: 0x030A0C), location: 0.52),
                    ThemeGradientStop(color: Color(hex: 0x000000), location: 1.0),
                ],
                drawerColors: [Color(hex: 0x061013), Color(hex: 0x040A0C), Color(hex: 0x020405)],
                surface: Color(hex: 0x061012, opacity: 0.7)
            )
        ),
        glowScale: 1.2,
        gridStyle: .dots,
        gridLine: .accentTinted(0.10),
        gridCell: 14,
        isLight: false,
        orbStyle: .crtCrosshair
    )

    // MARK: Paper Tape — vintage teleprinter: ink on warm paper. The one light
    // environment; "bright" accent/danger variants run DARKER than base because
    // emphasis on paper means more ink, not more light.

    static let paperTape = ThemePaletteDefinition(
        lockedAccentSlot: nil,
        background: Color(hex: 0xF2EFE9),
        screenGradientStops: [
            ThemeGradientStop(color: Color(hex: 0xF9F6F0), location: 0.0),
            ThemeGradientStop(color: Color(hex: 0xF2EFE9), location: 0.52),
            ThemeGradientStop(color: Color(hex: 0xE7E1D6), location: 1.0),
        ],
        drawerColors: [Color(hex: 0xEFEBE3), Color(hex: 0xE9E4DA), Color(hex: 0xE2DCD0)],
        texture: .paperGrain,
        ramp: ThemeForegroundRamp(
            foreground: Color(hex: 0x2B2B2B),
            foregroundBright: Color(hex: 0x151515),
            secondaryForeground: Color(hex: 0x5C5C5C),
            mutedForeground: Color(hex: 0x6E6A63),
            dimForeground: Color(hex: 0x8A8A8A),
            coolForeground: Color(hex: 0x3E3A34)
        ),
        surface: Color(hex: 0xE8E4DC, opacity: 0.8),
        chips: .fixed(
            surface: Color(hex: 0x4A4438, opacity: 0.06),
            divider: Color(hex: 0x2B2B2B, opacity: 0.12),
            border: Color(hex: 0x2B2B2B, opacity: 0.18)
        ),
        // Ink hairlines, not accent-tinted — borders shouldn't read as colored
        // marks on paper.
        borders: .fixed(
            hairline: Color(hex: 0x2B2B2B, opacity: 0.14),
            strong: Color(hex: 0x2B2B2B, opacity: 0.32)
        ),
        scrim: Color(hex: 0x2B2B2B, opacity: 0.35),
        danger: Color(hex: 0xB3261E),
        dangerBright: Color(hex: 0x8C1D17),
        accents: ThemeAccentVariants(
            cyan: ThemeAccentVariant(   // hero — Tracker Red
                displayName: "Red · Tracker",
                base: Color(hex: 0xB5382E),
                bright: Color(hex: 0x7E1F17),
                deep: Color(hex: 0xE5978F),
                coreHighlight: Color(hex: 0xFAEDEA),
                coreShadow: Color(hex: 0x6E1B14),
                forge: Color(hex: 0xA96A12)
            ),
            amber: ThemeAccentVariant(  // Cyan Ink
                displayName: "Cyan · Ink",
                base: Color(hex: 0x1E7F8C),
                bright: Color(hex: 0x115560),
                deep: Color(hex: 0x9CCFD6),
                coreHighlight: Color(hex: 0xEAF6F7),
                coreShadow: Color(hex: 0x0D3F47),
                forge: Color(hex: 0xA96A12)
            ),
            violet: ThemeAccentVariant( // Amber Ink
                displayName: "Amber · Ink",
                base: Color(hex: 0xA96A12),
                bright: Color(hex: 0x74490C),
                deep: Color(hex: 0xD9B173),
                coreHighlight: Color(hex: 0xF8EEDC),
                coreShadow: Color(hex: 0x543508),
                // Warning must stay separable from an amber-family accent.
                forge: Color(hex: 0xB4530F)
            )
        ),
        glowScale: 0.15,
        gridStyle: .rules,
        gridLine: .fixed(Color(hex: 0x2B2B2B, opacity: 0.10)),
        gridCell: 24,
        isLight: true,
        orbStyle: .paperReel
    )

    // MARK: Winter — Winter Frost

    static let winterFrost = ThemePaletteDefinition(
        lockedAccentSlot: nil,
        background: Color(hex: 0xF4F9FC),
        screenGradientStops: [
            ThemeGradientStop(color: Color(hex: 0xE8F3F8), location: 0.0),
            ThemeGradientStop(color: Color(hex: 0xF4F9FC), location: 0.52),
            ThemeGradientStop(color: Color(hex: 0xDCEBF3), location: 1.0),
        ],
        drawerColors: [Color(hex: 0xE8F3F8), Color(hex: 0xF4F9FC), Color(hex: 0xDCEBF3)],
        texture: .none,
        ramp: ThemeForegroundRamp(
            foreground: Color(hex: 0x0F2330),
            foregroundBright: Color(hex: 0x0D1E29),
            secondaryForeground: Color(hex: 0x4A6578),
            mutedForeground: Color(hex: 0x4A6578),
            dimForeground: Color(hex: 0x7D96A6),
            coolForeground: Color(hex: 0x4A6578)
        ),
        surface: Color(hex: 0x78D2FF, opacity: 0.18),
        chips: .fixed(
            surface: Color(hex: 0x78D2FF, opacity: 0.18),
            divider: Color(hex: 0xA0DCF0, opacity: 0.18),
            border: Color(hex: 0xDCF0FF, opacity: 0.14)
        ),
        borders: .fixed(
            hairline: Color(hex: 0x0F2330, opacity: 0.1),
            strong: Color(hex: 0x0F2330, opacity: 0.22)
        ),
        scrim: Color(hex: 0x0F2330, opacity: 0.35),
        danger: Color(hex: 0xC94545),
        dangerBright: Color(hex: 0xA13939),
        accents: ThemeAccentVariants(
            cyan: ThemeAccentVariant(
                displayName: "Ice · Winter",
                base: Color(hex: 0x3AB3F0),
                bright: Color(hex: 0x6BC6F4),
                deep: Color(hex: 0x297DA8),
                coreHighlight: Color(hex: 0x93D5F7),
                coreShadow: Color(hex: 0x206284),
                forge: Color(hex: 0xD49020)
            ),
            amber: ThemeAccentVariant(
                displayName: "Snow · Winter",
                base: Color(hex: 0x8FD4F4),
                bright: Color(hex: 0xABDFF7),
                deep: Color(hex: 0x6494AB),
                coreHighlight: Color(hex: 0xC1E7F9),
                coreShadow: Color(hex: 0x4F7586),
                forge: Color(hex: 0xD49020)
            ),
            violet: ThemeAccentVariant(
                displayName: "Berry · Winter",
                base: Color(hex: 0xC94F6D),
                bright: Color(hex: 0xD67B92),
                deep: Color(hex: 0x8D374C),
                coreHighlight: Color(hex: 0xE19EAF),
                coreShadow: Color(hex: 0x6F2B3C),
                forge: Color(hex: 0xD49020)
            )
        ),
        glowScale: 0.15,
        gridStyle: .lines,
        gridLine: .fixed(Color(hex: 0x0F2330, opacity: 0.1)),
        gridCell: 26,
        isLight: true,
        orbStyle: .arcReactor
    )

    // MARK: Summer — Summer Solar

    static let summerSolar = ThemePaletteDefinition(
        lockedAccentSlot: nil,
        background: Color(hex: 0x1A1005),
        screenGradientStops: [
            ThemeGradientStop(color: Color(hex: 0x281A08), location: 0.0),
            ThemeGradientStop(color: Color(hex: 0x1A1005), location: 0.52),
            ThemeGradientStop(color: Color(hex: 0x0F0802), location: 1.0),
        ],
        drawerColors: [Color(hex: 0x281A08), Color(hex: 0x1A1005), Color(hex: 0x0F0802)],
        texture: .embers,
        ramp: ThemeForegroundRamp(
            foreground: Color(hex: 0xFFF8E8),
            foregroundBright: Color(hex: 0xFFF9EA),
            secondaryForeground: Color(hex: 0xF0D8A8),
            mutedForeground: Color(hex: 0xF0D8A8),
            dimForeground: Color(hex: 0xC0A070),
            coolForeground: Color(hex: 0xF0D8A8)
        ),
        surface: Color(hex: 0xFFA028, opacity: 0.08),
        chips: .fixed(
            surface: Color(hex: 0xFFA028, opacity: 0.08),
            divider: Color(hex: 0xFF503C, opacity: 0.08),
            border: Color(hex: 0x78DCFF, opacity: 0.06)
        ),
        borders: .accentTinted(hairline: 0.14, strong: 0.30),
        scrim: Color(hex: 0x000000, opacity: 0.85),
        danger: Color(hex: 0xFF3C2A),
        dangerBright: Color(hex: 0xFF6355),
        accents: ThemeAccentVariants(
            cyan: ThemeAccentVariant(
                displayName: "Mango · Summer",
                base: Color(hex: 0xFFA028),
                bright: Color(hex: 0xFFB85E),
                deep: Color(hex: 0xB2701C),
                coreHighlight: Color(hex: 0xFFCB89),
                coreShadow: Color(hex: 0x8C5816),
                forge: Color(hex: 0xFFCC00)
            ),
            amber: ThemeAccentVariant(
                displayName: "Heatwave · Summer",
                base: Color(hex: 0xFF503C),
                bright: Color(hex: 0xFF7C6D),
                deep: Color(hex: 0xB2382A),
                coreHighlight: Color(hex: 0xFF9F94),
                coreShadow: Color(hex: 0x8C2C21),
                forge: Color(hex: 0xFFCC00)
            ),
            violet: ThemeAccentVariant(
                displayName: "Pool · Summer",
                base: Color(hex: 0x78DCFF),
                bright: Color(hex: 0x9AE5FF),
                deep: Color(hex: 0x549AB2),
                coreHighlight: Color(hex: 0xB5ECFF),
                coreShadow: Color(hex: 0x42798C),
                forge: Color(hex: 0xFFCC00)
            )
        ),
        glowScale: 1.2,
        gridStyle: .lines,
        gridLine: .accentTinted(0.08),
        gridCell: 26,
        isLight: false,
        orbStyle: .arcReactor
    )

    // MARK: Spring — Spring Sprout

    static let springSprout = ThemePaletteDefinition(
        lockedAccentSlot: nil,
        background: Color(hex: 0xFFF9F4),
        screenGradientStops: [
            ThemeGradientStop(color: Color(hex: 0xFFF0E4), location: 0.0),
            ThemeGradientStop(color: Color(hex: 0xFFF9F4), location: 0.52),
            ThemeGradientStop(color: Color(hex: 0xFFE8D8), location: 1.0),
        ],
        drawerColors: [Color(hex: 0xFFF0E4), Color(hex: 0xFFF9F4), Color(hex: 0xFFE8D8)],
        texture: .none,
        ramp: ThemeForegroundRamp(
            foreground: Color(hex: 0x2A1F1A),
            foregroundBright: Color(hex: 0x241A16),
            secondaryForeground: Color(hex: 0x7A6258),
            mutedForeground: Color(hex: 0x7A6258),
            dimForeground: Color(hex: 0xA99088),
            coolForeground: Color(hex: 0x7A6258)
        ),
        surface: Color(hex: 0xFF96AA, opacity: 0.18),
        chips: .fixed(
            surface: Color(hex: 0xFF96AA, opacity: 0.18),
            divider: Color(hex: 0x8CE6A0, opacity: 0.18),
            border: Color(hex: 0xFFDC78, opacity: 0.14)
        ),
        borders: .fixed(
            hairline: Color(hex: 0x2A1F1A, opacity: 0.1),
            strong: Color(hex: 0x2A1F1A, opacity: 0.22)
        ),
        scrim: Color(hex: 0x2A1F1A, opacity: 0.35),
        danger: Color(hex: 0xD94A4A),
        dangerBright: Color(hex: 0xAE3C3C),
        accents: ThemeAccentVariants(
            cyan: ThemeAccentVariant(
                displayName: "Blossom · Spring",
                base: Color(hex: 0xFF6B8A),
                bright: Color(hex: 0xFF90A7),
                deep: Color(hex: 0xB24B61),
                coreHighlight: Color(hex: 0xFFAEBF),
                coreShadow: Color(hex: 0x8C3B4C),
                forge: Color(hex: 0xE89C30)
            ),
            amber: ThemeAccentVariant(
                displayName: "Mint · Spring",
                base: Color(hex: 0x5ED47A),
                bright: Color(hex: 0x86DF9B),
                deep: Color(hex: 0x429455),
                coreHighlight: Color(hex: 0xA6E7B6),
                coreShadow: Color(hex: 0x347543),
                forge: Color(hex: 0xE89C30)
            ),
            violet: ThemeAccentVariant(
                displayName: "Butter · Spring",
                base: Color(hex: 0xFFD04A),
                bright: Color(hex: 0xFFDC77),
                deep: Color(hex: 0xB29234),
                coreHighlight: Color(hex: 0xFFE59B),
                coreShadow: Color(hex: 0x8C7229),
                forge: Color(hex: 0xE89C30)
            )
        ),
        glowScale: 0.15,
        gridStyle: .lines,
        gridLine: .fixed(Color(hex: 0x2A1F1A, opacity: 0.1)),
        gridCell: 26,
        isLight: true,
        orbStyle: .arcReactor
    )

    // MARK: Autumn — Autumn Harvest

    static let autumnHarvest = ThemePaletteDefinition(
        lockedAccentSlot: nil,
        background: Color(hex: 0x1A110A),
        screenGradientStops: [
            ThemeGradientStop(color: Color(hex: 0x261C12), location: 0.0),
            ThemeGradientStop(color: Color(hex: 0x1A110A), location: 0.52),
            ThemeGradientStop(color: Color(hex: 0x0F0906), location: 1.0),
        ],
        drawerColors: [Color(hex: 0x261C12), Color(hex: 0x1A110A), Color(hex: 0x0F0906)],
        texture: .embers,
        ramp: ThemeForegroundRamp(
            foreground: Color(hex: 0xFFF5E8),
            foregroundBright: Color(hex: 0xFFF6EA),
            secondaryForeground: Color(hex: 0xE0C4A0),
            mutedForeground: Color(hex: 0xE0C4A0),
            dimForeground: Color(hex: 0xA08060),
            coolForeground: Color(hex: 0xE0C4A0)
        ),
        surface: Color(hex: 0xFF8C28, opacity: 0.08),
        chips: .fixed(
            surface: Color(hex: 0xFF8C28, opacity: 0.08),
            divider: Color(hex: 0xC85032, opacity: 0.08),
            border: Color(hex: 0xB4A050, opacity: 0.06)
        ),
        borders: .accentTinted(hairline: 0.14, strong: 0.30),
        scrim: Color(hex: 0x000000, opacity: 0.85),
        danger: Color(hex: 0xA03020),
        dangerBright: Color(hex: 0xB3594D),
        accents: ThemeAccentVariants(
            cyan: ThemeAccentVariant(
                displayName: "Pumpkin · Autumn",
                base: Color(hex: 0xFF8C28),
                bright: Color(hex: 0xFFA95E),
                deep: Color(hex: 0xB2621C),
                coreHighlight: Color(hex: 0xFFC089),
                coreShadow: Color(hex: 0x8C4D16),
                forge: Color(hex: 0xD49020)
            ),
            amber: ThemeAccentVariant(
                displayName: "Cranberry · Autumn",
                base: Color(hex: 0xC85032),
                bright: Color(hex: 0xD67C65),
                deep: Color(hex: 0x8C3823),
                coreHighlight: Color(hex: 0xE19F8E),
                coreShadow: Color(hex: 0x6E2C1C),
                forge: Color(hex: 0xD49020)
            ),
            violet: ThemeAccentVariant(
                displayName: "Gourd · Autumn",
                base: Color(hex: 0xB4A050),
                bright: Color(hex: 0xC7B87C),
                deep: Color(hex: 0x7E7038),
                coreHighlight: Color(hex: 0xD6CB9F),
                coreShadow: Color(hex: 0x63582C),
                forge: Color(hex: 0xD49020)
            )
        ),
        glowScale: 1.1,
        gridStyle: .lines,
        gridLine: .accentTinted(0.08),
        gridCell: 26,
        isLight: false,
        orbStyle: .arcReactor
    )

    // MARK: Cereal — Cereal Box

    static let cerealBox = ThemePaletteDefinition(
        lockedAccentSlot: nil,
        background: Color(hex: 0x0A0610),
        screenGradientStops: [
            ThemeGradientStop(color: Color(hex: 0x140A20), location: 0.0),
            ThemeGradientStop(color: Color(hex: 0x0A0610), location: 0.52),
            ThemeGradientStop(color: Color(hex: 0x050308), location: 1.0),
        ],
        drawerColors: [Color(hex: 0x140A20), Color(hex: 0x0A0610), Color(hex: 0x050308)],
        texture: .embers,
        ramp: ThemeForegroundRamp(
            foreground: Color(hex: 0xFFF8FF),
            foregroundBright: Color(hex: 0xFFF8FF),
            secondaryForeground: Color(hex: 0xC8B8D8),
            mutedForeground: Color(hex: 0xC8B8D8),
            dimForeground: Color(hex: 0x887098),
            coolForeground: Color(hex: 0xC8B8D8)
        ),
        surface: Color(hex: 0xFF5078, opacity: 0.08),
        chips: .fixed(
            surface: Color(hex: 0xFF5078, opacity: 0.08),
            divider: Color(hex: 0x00C8FF, opacity: 0.08),
            border: Color(hex: 0xFFDC00, opacity: 0.06)
        ),
        borders: .accentTinted(hairline: 0.14, strong: 0.30),
        scrim: Color(hex: 0x000000, opacity: 0.85),
        danger: Color(hex: 0xFF4A2B),
        dangerBright: Color(hex: 0xFF654A),
        accents: ThemeAccentVariants(
            cyan: ThemeAccentVariant(
                displayName: "Berry · Cereal",
                base: Color(hex: 0xFF5078),
                bright: Color(hex: 0xFF7B99),
                deep: Color(hex: 0xB23854),
                coreHighlight: Color(hex: 0xFF9EB4),
                coreShadow: Color(hex: 0x8C2C42),
                forge: Color(hex: 0xFF9D00)
            ),
            amber: ThemeAccentVariant(
                displayName: "Milk · Cereal",
                base: Color(hex: 0x00C8FF),
                bright: Color(hex: 0x3FD5FF),
                deep: Color(hex: 0x008CB2),
                coreHighlight: Color(hex: 0x72E0FF),
                coreShadow: Color(hex: 0x006E8C),
                forge: Color(hex: 0xFF9D00)
            ),
            violet: ThemeAccentVariant(
                displayName: "Honey · Cereal",
                base: Color(hex: 0xFFDC00),
                bright: Color(hex: 0xFFE43F),
                deep: Color(hex: 0xB29A00),
                coreHighlight: Color(hex: 0xFFEB72),
                coreShadow: Color(hex: 0x8C7900),
                forge: Color(hex: 0xFF9D00)
            )
        ),
        glowScale: 1.1,
        gridStyle: .lines,
        gridLine: .accentTinted(0.08),
        gridCell: 26,
        isLight: false,
        orbStyle: .arcReactor
    )

    // MARK: Bubblegum — Bubblegum Mecha

    static let bubblegumMecha = ThemePaletteDefinition(
        lockedAccentSlot: nil,
        background: Color(hex: 0x0A050A),
        screenGradientStops: [
            ThemeGradientStop(color: Color(hex: 0x1A0F1A), location: 0.0),
            ThemeGradientStop(color: Color(hex: 0x0A050A), location: 0.52),
            ThemeGradientStop(color: Color(hex: 0x050205), location: 1.0),
        ],
        drawerColors: [Color(hex: 0x1A0F1A), Color(hex: 0x0A050A), Color(hex: 0x050205)],
        texture: .embers,
        ramp: ThemeForegroundRamp(
            foreground: Color(hex: 0xFFF5F8),
            foregroundBright: Color(hex: 0xFFF5F8),
            secondaryForeground: Color(hex: 0xD8B8C8),
            mutedForeground: Color(hex: 0xD8B8C8),
            dimForeground: Color(hex: 0x906080),
            coolForeground: Color(hex: 0xD8B8C8)
        ),
        surface: Color(hex: 0xFF6EC7, opacity: 0.08),
        chips: .fixed(
            surface: Color(hex: 0xFF6EC7, opacity: 0.08),
            divider: Color(hex: 0x00F0FF, opacity: 0.08),
            border: Color(hex: 0xFFE600, opacity: 0.06)
        ),
        borders: .accentTinted(hairline: 0.14, strong: 0.30),
        scrim: Color(hex: 0x000000, opacity: 0.85),
        danger: Color(hex: 0xFF3366),
        dangerBright: Color(hex: 0xFF517C),
        accents: ThemeAccentVariants(
            cyan: ThemeAccentVariant(
                displayName: "Candy · Mecha",
                base: Color(hex: 0xFF6EC7),
                bright: Color(hex: 0xFF92D5),
                deep: Color(hex: 0xB24D8B),
                coreHighlight: Color(hex: 0xFFAFE0),
                coreShadow: Color(hex: 0x8C3C6D),
                forge: Color(hex: 0xFF9A00)
            ),
            amber: ThemeAccentVariant(
                displayName: "Cyan · Mecha",
                base: Color(hex: 0x00F0FF),
                bright: Color(hex: 0x3FF3FF),
                deep: Color(hex: 0x00A8B2),
                coreHighlight: Color(hex: 0x72F6FF),
                coreShadow: Color(hex: 0x00848C),
                forge: Color(hex: 0xFF9A00)
            ),
            violet: ThemeAccentVariant(
                displayName: "Voltage · Mecha",
                base: Color(hex: 0xFFE600),
                bright: Color(hex: 0xFFEC3F),
                deep: Color(hex: 0xB2A100),
                coreHighlight: Color(hex: 0xFFF172),
                coreShadow: Color(hex: 0x8C7E00),
                forge: Color(hex: 0xFF9A00)
            )
        ),
        glowScale: 1.1,
        gridStyle: .lines,
        gridLine: .accentTinted(0.08),
        gridCell: 26,
        isLight: false,
        orbStyle: .arcReactor
    )

    // MARK: Retro — Retro Sci-Fi

    static let retroSciFi = ThemePaletteDefinition(
        lockedAccentSlot: nil,
        background: Color(hex: 0xF5F0E8),
        screenGradientStops: [
            ThemeGradientStop(color: Color(hex: 0xE8E2D8), location: 0.0),
            ThemeGradientStop(color: Color(hex: 0xF5F0E8), location: 0.52),
            ThemeGradientStop(color: Color(hex: 0xFFFDF8), location: 1.0),
        ],
        drawerColors: [Color(hex: 0xE8E2D8), Color(hex: 0xF5F0E8), Color(hex: 0xFFFDF8)],
        texture: .none,
        ramp: ThemeForegroundRamp(
            foreground: Color(hex: 0x1A1210),
            foregroundBright: Color(hex: 0x160F0D),
            secondaryForeground: Color(hex: 0x5C5048),
            mutedForeground: Color(hex: 0x5C5048),
            dimForeground: Color(hex: 0x8A7E74),
            coolForeground: Color(hex: 0x5C5048)
        ),
        surface: Color(hex: 0xFF2D2D, opacity: 0.08),
        chips: .fixed(
            surface: Color(hex: 0xFF2D2D, opacity: 0.08),
            divider: Color(hex: 0x007BFF, opacity: 0.08),
            border: Color(hex: 0xFFD600, opacity: 0.08)
        ),
        borders: .fixed(
            hairline: Color(hex: 0x1A1210, opacity: 0.1),
            strong: Color(hex: 0x1A1210, opacity: 0.22)
        ),
        scrim: Color(hex: 0x1A1210, opacity: 0.35),
        danger: Color(hex: 0xD00000),
        dangerBright: Color(hex: 0xB00000),
        accents: ThemeAccentVariants(
            cyan: ThemeAccentVariant(
                displayName: "Red · Retro",
                base: Color(hex: 0xFF2D2D),
                bright: Color(hex: 0xFF6161),
                deep: Color(hex: 0xB21F1F),
                coreHighlight: Color(hex: 0xFF8B8B),
                coreShadow: Color(hex: 0x8C1818),
                forge: Color(hex: 0xE67E00)
            ),
            amber: ThemeAccentVariant(
                displayName: "Blue · Retro",
                base: Color(hex: 0x007BFF),
                bright: Color(hex: 0x3F9CFF),
                deep: Color(hex: 0x0056B2),
                coreHighlight: Color(hex: 0x72B6FF),
                coreShadow: Color(hex: 0x00438C),
                forge: Color(hex: 0xE67E00)
            ),
            violet: ThemeAccentVariant(
                displayName: "Yellow · Retro",
                base: Color(hex: 0xFFD600),
                bright: Color(hex: 0xFFE03F),
                deep: Color(hex: 0xB29500),
                coreHighlight: Color(hex: 0xFFE872),
                coreShadow: Color(hex: 0x8C7500),
                forge: Color(hex: 0xE67E00)
            )
        ),
        glowScale: 0.15,
        gridStyle: .rules,
        gridLine: .fixed(Color(hex: 0x1A1210, opacity: 0.1)),
        gridCell: 26,
        isLight: true,
        orbStyle: .arcReactor
    )

    // MARK: Event — Event Horizon

    static let eventHorizon = ThemePaletteDefinition(
        lockedAccentSlot: nil,
        background: Color(hex: 0x08050F),
        screenGradientStops: [
            ThemeGradientStop(color: Color(hex: 0x100A1A), location: 0.0),
            ThemeGradientStop(color: Color(hex: 0x08050F), location: 0.52),
            ThemeGradientStop(color: Color(hex: 0x040208), location: 1.0),
        ],
        drawerColors: [Color(hex: 0x100A1A), Color(hex: 0x08050F), Color(hex: 0x040208)],
        texture: .starfield,
        ramp: ThemeForegroundRamp(
            foreground: Color(hex: 0xF7F4FF),
            foregroundBright: Color(hex: 0xF7F4FF),
            secondaryForeground: Color(hex: 0xC4B8D8),
            mutedForeground: Color(hex: 0xC4B8D8),
            dimForeground: Color(hex: 0x7A7090),
            coolForeground: Color(hex: 0xC4B8D8)
        ),
        surface: Color(hex: 0x8A5CFF, opacity: 0.08),
        chips: .fixed(
            surface: Color(hex: 0x8A5CFF, opacity: 0.08),
            divider: Color(hex: 0x00F0FF, opacity: 0.08),
            border: Color(hex: 0xFFDC50, opacity: 0.06)
        ),
        borders: .accentTinted(hairline: 0.14, strong: 0.30),
        scrim: Color(hex: 0x000000, opacity: 0.85),
        danger: Color(hex: 0xFF3B3B),
        dangerBright: Color(hex: 0xFF5858),
        accents: ThemeAccentVariants(
            cyan: ThemeAccentVariant(
                // Handoff-native slot names (theme-event-horizon.html).
                displayName: "Accretion Violet",
                base: Color(hex: 0x8A5CFF),
                bright: Color(hex: 0xA784FF),
                deep: Color(hex: 0x6040B2),
                coreHighlight: Color(hex: 0xBEA5FF),
                coreShadow: Color(hex: 0x4B328C),
                forge: Color(hex: 0xFF9E00)
            ),
            amber: ThemeAccentVariant(
                displayName: "Hawking Cyan",
                base: Color(hex: 0x00F0FF),
                bright: Color(hex: 0x3FF3FF),
                deep: Color(hex: 0x00A8B2),
                coreHighlight: Color(hex: 0x72F6FF),
                coreShadow: Color(hex: 0x00848C),
                forge: Color(hex: 0xFF9E00)
            ),
            violet: ThemeAccentVariant(
                displayName: "Supernova Gold",
                base: Color(hex: 0xFFDC50),
                bright: Color(hex: 0xFFE47B),
                deep: Color(hex: 0xB29A38),
                coreHighlight: Color(hex: 0xFFEB9E),
                coreShadow: Color(hex: 0x8C792C),
                forge: Color(hex: 0xFF9E00)
            )
        ),
        glowScale: 1.1,
        gridStyle: .lines,
        gridLine: .accentTinted(0.08),
        gridCell: 26,
        isLight: false,
        orbStyle: .arcReactor
    )
}

// MARK: - Color hex helper
// Lives here (not Design.swift) so the widget target gets it too.

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }
}
