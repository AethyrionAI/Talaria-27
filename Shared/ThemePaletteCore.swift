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
}

/// Accent slot identity, decoupled from the app's `AppearanceAccent`
/// (same raw values — these are persisted, never rename).
enum AccentSlot: String, CaseIterable, Codable, Hashable, Sendable {
    case cyan
    case amber
    case violet
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
}

/// One stop of the screen's radial background gradient.
struct ThemeGradientStop: Equatable, Sendable {
    let color: Color
    let location: Double
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

    init(theme: ThemeID, accent: AccentSlot) {
        switch theme {
        case .deepField: self.init(deepField: accent)
        case .solarForge: self.init(solarForge: accent)
        case .terminal: self.init(terminal: accent)
        case .paperTape: self.init(paperTape: accent)
        }
    }

    // MARK: Deep Field — the original arc-reactor HUD (values byte-identical
    // to the pre-theming constants; cyan/amber/violet keep their meanings).

    private init(deepField accent: AccentSlot) {
        let base: Color, bright: Color, deep: Color
        let coreHighlight: Color, coreShadow: Color
        switch accent {
        case .cyan:
            base = Color(hex: 0x54E6F0); bright = Color(hex: 0xCDF8FB); deep = Color(hex: 0x14636E)
            coreHighlight = Color(hex: 0xE2FBFD); coreShadow = Color(hex: 0x0F5867)
        case .amber:
            base = Color(hex: 0xFFC14D); bright = Color(hex: 0xFFE2A6); deep = Color(hex: 0x6E4D14)
            coreHighlight = Color(hex: 0xFFF1D2); coreShadow = Color(hex: 0x3E2C08)
        case .violet:
            base = Color(hex: 0xB18CFF); bright = Color(hex: 0xE2D4FF); deep = Color(hex: 0x3A2D6E)
            coreHighlight = Color(hex: 0xF1E8FF); coreShadow = Color(hex: 0x241A47)
        }

        background = Color(hex: 0x06080C)
        screenGradientStops = [
            ThemeGradientStop(color: Color(hex: 0x0C2730), location: 0.0),
            ThemeGradientStop(color: Color(hex: 0x070D15), location: 0.52),
            ThemeGradientStop(color: Color(hex: 0x04070C), location: 1.0),
        ]
        drawerColors = [Color(hex: 0x0A1822), Color(hex: 0x060C13), Color(hex: 0x05090F)]
        texture = .none

        foreground = Color(hex: 0xE8EEF5)
        foregroundBright = Color(hex: 0xEAF6F8)
        secondaryForeground = Color(hex: 0x7C93A6)
        mutedForeground = Color(hex: 0x5D7488)
        dimForeground = Color(hex: 0x4D6273)
        coolForeground = Color(hex: 0xCFE1EA)

        surface = Color(hex: 0x08121A, opacity: 0.6)
        chipSurface = Color(hex: 0x7896AF, opacity: 0.08)
        divider = Color(hex: 0x7896AF, opacity: 0.16)
        chipBorder = Color(hex: 0x7896AF, opacity: 0.22)
        hairline = base.opacity(0.14)
        strongBorder = base.opacity(0.30)
        scrim = Color(hex: 0x02060A, opacity: 0.85)

        self.base = base; self.bright = bright; self.deep = deep
        self.coreHighlight = coreHighlight; self.coreShadow = coreShadow

        // Warning stays separable from the accent: distinct orange under the
        // amber slot, forge amber otherwise (pre-theming behavior).
        forge = accent == .amber ? Color(hex: 0xFF7A18) : Color(hex: 0xFFC14D)
        danger = Color(hex: 0xE0625F)
        dangerBright = Color(hex: 0xFF8A86)

        glowScale = 1.0
        gridStyle = .lines
        gridLineColor = base.opacity(0.05)
        gridCell = 26
        isLight = false
    }

    // MARK: Solar Forge — industrial forge: brass, ember, warm metal.
    // Hero slot is the forge amber; cyan/violet become exotic plasma hues.

    private init(solarForge accent: AccentSlot) {
        let base: Color, bright: Color, deep: Color
        let coreHighlight: Color, coreShadow: Color
        let isAmberFamily: Bool
        switch accent {
        case .cyan:   // hero — Forge Amber
            base = Color(hex: 0xFFC14D); bright = Color(hex: 0xFFE2A6); deep = Color(hex: 0x6E4D14)
            coreHighlight = Color(hex: 0xFFF1D2); coreShadow = Color(hex: 0x3E2C08)
            isAmberFamily = true
        case .amber:  // Plasma Cyan
            base = Color(hex: 0x54E6F0); bright = Color(hex: 0xCDF8FB); deep = Color(hex: 0x14636E)
            coreHighlight = Color(hex: 0xE2FBFD); coreShadow = Color(hex: 0x0F5867)
            isAmberFamily = false
        case .violet: // Violet Flux
            base = Color(hex: 0xB18CFF); bright = Color(hex: 0xE2D4FF); deep = Color(hex: 0x3A2D6E)
            coreHighlight = Color(hex: 0xF1E8FF); coreShadow = Color(hex: 0x241A47)
            isAmberFamily = false
        }

        background = Color(hex: 0x080602)
        screenGradientStops = [
            ThemeGradientStop(color: Color(hex: 0x2A1A0C), location: 0.0),
            ThemeGradientStop(color: Color(hex: 0x120C07), location: 0.52),
            ThemeGradientStop(color: Color(hex: 0x080602), location: 1.0),
        ]
        drawerColors = [Color(hex: 0x22150A), Color(hex: 0x130B06), Color(hex: 0x0D0804)]
        texture = .embers

        foreground = Color(hex: 0xF5E8D8)
        foregroundBright = Color(hex: 0xFAF3E7)
        secondaryForeground = Color(hex: 0xB8A58F)
        mutedForeground = Color(hex: 0x8F7B66)
        dimForeground = Color(hex: 0x7D6B5A)
        coolForeground = Color(hex: 0xE3D2BC)

        surface = Color(hex: 0x1A140E, opacity: 0.6)
        chipSurface = Color(hex: 0xAF8A5F, opacity: 0.08)
        divider = Color(hex: 0xAF8A5F, opacity: 0.16)
        chipBorder = Color(hex: 0xAF8A5F, opacity: 0.22)
        hairline = base.opacity(0.14)
        strongBorder = base.opacity(0.30)
        scrim = Color(hex: 0x0A0502, opacity: 0.85)

        self.base = base; self.bright = bright; self.deep = deep
        self.coreHighlight = coreHighlight; self.coreShadow = coreShadow

        forge = isAmberFamily ? Color(hex: 0xFF7A18) : Color(hex: 0xFFC14D)
        danger = Color(hex: 0xE0625F)
        dangerBright = Color(hex: 0xFF8A86)

        glowScale = 1.0
        gridStyle = .lines
        gridLineColor = Color(hex: 0xC89B5A, opacity: 0.06)
        gridCell = 26
        isLight = false
    }

    // MARK: Terminal — CRT phosphor on true black. The whole foreground ramp
    // follows the selected phosphor (green hero / amber / IBM cyan).

    private init(terminal accent: AccentSlot) {
        let base: Color, bright: Color, deep: Color
        let coreHighlight: Color, coreShadow: Color
        switch accent {
        case .cyan:   // hero — Phosphor Green
            base = Color(hex: 0x33FF00); bright = Color(hex: 0xB6FF9E); deep = Color(hex: 0x0E6B00)
            coreHighlight = Color(hex: 0xE4FFDB); coreShadow = Color(hex: 0x0A4A00)

            foreground = Color(hex: 0xD8FFD0)
            foregroundBright = Color(hex: 0xEDFFE8)
            secondaryForeground = Color(hex: 0x7BC96A)
            mutedForeground = Color(hex: 0x55A046)
            dimForeground = Color(hex: 0x3D7A32)
            coolForeground = Color(hex: 0xC0EFB4)

            screenGradientStops = [
                ThemeGradientStop(color: Color(hex: 0x0A140A), location: 0.0),
                ThemeGradientStop(color: Color(hex: 0x040A04), location: 0.52),
                ThemeGradientStop(color: Color(hex: 0x000000), location: 1.0),
            ]
            drawerColors = [Color(hex: 0x0A120A), Color(hex: 0x050905), Color(hex: 0x020402)]
            surface = Color(hex: 0x0A0F0A, opacity: 0.7)
            forge = Color(hex: 0xFFB000)
        case .amber:  // Amber Phosphor
            base = Color(hex: 0xFFB000); bright = Color(hex: 0xFFDD8A); deep = Color(hex: 0x7A5400)
            coreHighlight = Color(hex: 0xFFF0C8); coreShadow = Color(hex: 0x4A3300)

            foreground = Color(hex: 0xFFE8C2)
            foregroundBright = Color(hex: 0xFFF4DE)
            secondaryForeground = Color(hex: 0xCC9A55)
            mutedForeground = Color(hex: 0xA0793F)
            dimForeground = Color(hex: 0x7A5C2E)
            coolForeground = Color(hex: 0xF2D9A8)

            screenGradientStops = [
                ThemeGradientStop(color: Color(hex: 0x140F04), location: 0.0),
                ThemeGradientStop(color: Color(hex: 0x0A0703), location: 0.52),
                ThemeGradientStop(color: Color(hex: 0x000000), location: 1.0),
            ]
            drawerColors = [Color(hex: 0x120D05), Color(hex: 0x090603), Color(hex: 0x030201)]
            surface = Color(hex: 0x100C05, opacity: 0.7)
            // Warning must stay separable from an amber phosphor accent.
            forge = Color(hex: 0xFF6A00)
        case .violet: // IBM Cyan
            base = Color(hex: 0x3BD6E0); bright = Color(hex: 0xBEF2F7); deep = Color(hex: 0x0F5B63)
            coreHighlight = Color(hex: 0xE0FBFD); coreShadow = Color(hex: 0x0A434A)

            foreground = Color(hex: 0xD2F4F7)
            foregroundBright = Color(hex: 0xE8FBFC)
            secondaryForeground = Color(hex: 0x6FB8BF)
            mutedForeground = Color(hex: 0x4E8F96)
            dimForeground = Color(hex: 0x386B71)
            coolForeground = Color(hex: 0xBEEAEE)

            screenGradientStops = [
                ThemeGradientStop(color: Color(hex: 0x041214), location: 0.0),
                ThemeGradientStop(color: Color(hex: 0x030A0C), location: 0.52),
                ThemeGradientStop(color: Color(hex: 0x000000), location: 1.0),
            ]
            drawerColors = [Color(hex: 0x061013), Color(hex: 0x040A0C), Color(hex: 0x020405)]
            surface = Color(hex: 0x061012, opacity: 0.7)
            forge = Color(hex: 0xFFB000)
        }

        background = Color(hex: 0x000000)
        texture = .scanlines

        chipSurface = secondaryForeground.opacity(0.08)
        divider = secondaryForeground.opacity(0.16)
        chipBorder = secondaryForeground.opacity(0.22)
        // Stronger hairlines for the CRT feel.
        hairline = base.opacity(0.25)
        strongBorder = base.opacity(0.45)
        scrim = Color(hex: 0x000000, opacity: 0.88)

        self.base = base; self.bright = bright; self.deep = deep
        self.coreHighlight = coreHighlight; self.coreShadow = coreShadow

        danger = Color(hex: 0xFF4D42)
        dangerBright = Color(hex: 0xFF8A80)

        glowScale = 1.2
        gridStyle = .dots
        gridLineColor = base.opacity(0.10)
        gridCell = 14
        isLight = false
    }

    // MARK: Paper Tape — vintage teleprinter: ink on warm paper. The one light
    // environment; "bright" accent/danger variants run DARKER than base because
    // emphasis on paper means more ink, not more light.

    private init(paperTape accent: AccentSlot) {
        let base: Color, bright: Color, deep: Color
        let coreHighlight: Color, coreShadow: Color
        let isAmberFamily: Bool
        switch accent {
        case .cyan:   // hero — Tracker Red
            base = Color(hex: 0xB5382E); bright = Color(hex: 0x7E1F17); deep = Color(hex: 0xE5978F)
            coreHighlight = Color(hex: 0xFAEDEA); coreShadow = Color(hex: 0x6E1B14)
            isAmberFamily = false
        case .amber:  // Cyan Ink
            base = Color(hex: 0x1E7F8C); bright = Color(hex: 0x115560); deep = Color(hex: 0x9CCFD6)
            coreHighlight = Color(hex: 0xEAF6F7); coreShadow = Color(hex: 0x0D3F47)
            isAmberFamily = false
        case .violet: // Amber Ink
            base = Color(hex: 0xA96A12); bright = Color(hex: 0x74490C); deep = Color(hex: 0xD9B173)
            coreHighlight = Color(hex: 0xF8EEDC); coreShadow = Color(hex: 0x543508)
            isAmberFamily = true
        }

        background = Color(hex: 0xF2EFE9)
        screenGradientStops = [
            ThemeGradientStop(color: Color(hex: 0xF9F6F0), location: 0.0),
            ThemeGradientStop(color: Color(hex: 0xF2EFE9), location: 0.52),
            ThemeGradientStop(color: Color(hex: 0xE7E1D6), location: 1.0),
        ]
        drawerColors = [Color(hex: 0xEFEBE3), Color(hex: 0xE9E4DA), Color(hex: 0xE2DCD0)]
        texture = .paperGrain

        foreground = Color(hex: 0x2B2B2B)
        foregroundBright = Color(hex: 0x151515)
        secondaryForeground = Color(hex: 0x5C5C5C)
        mutedForeground = Color(hex: 0x6E6A63)
        dimForeground = Color(hex: 0x8A8A8A)
        coolForeground = Color(hex: 0x3E3A34)

        surface = Color(hex: 0xE8E4DC, opacity: 0.8)
        chipSurface = Color(hex: 0x4A4438, opacity: 0.06)
        divider = Color(hex: 0x2B2B2B, opacity: 0.12)
        chipBorder = Color(hex: 0x2B2B2B, opacity: 0.18)
        // Ink hairlines, not accent-tinted — borders shouldn't read as colored
        // marks on paper.
        hairline = Color(hex: 0x2B2B2B, opacity: 0.14)
        strongBorder = Color(hex: 0x2B2B2B, opacity: 0.32)
        scrim = Color(hex: 0x2B2B2B, opacity: 0.35)

        self.base = base; self.bright = bright; self.deep = deep
        self.coreHighlight = coreHighlight; self.coreShadow = coreShadow

        forge = isAmberFamily ? Color(hex: 0xB4530F) : Color(hex: 0xA96A12)
        danger = Color(hex: 0xB3261E)
        dangerBright = Color(hex: 0x8C1D17)

        glowScale = 0.15
        gridStyle = .rules
        gridLineColor = Color(hex: 0x2B2B2B, opacity: 0.10)
        gridCell = 24
        isLight = true
    }
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
