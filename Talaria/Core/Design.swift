import SwiftUI

// MARK: - Design Tokens
// All visual constants for Talaria. No magic numbers or raw hex in view code —
// every view consumes `Design.*`.
//
// Theming: a THEME (Deep Field / Solar Forge / Terminal / Paper Tape) owns the
// whole color environment; the ACCENT picks the energetic hue inside it. Both
// resolve live through `ThemeRuntime` → `ThemePalette` (Shared/
// ThemePaletteCore.swift — the single source of truth for color values), so
// flipping either pref re-skins every token-reading view. Deep Field × cyan is
// byte-identical to the original "Arc-Reactor HUD" design
// (design/Talaria.dc.html); see design/THEME_SYSTEM_PLAN.md for the system.

enum Design {

    // MARK: - Brand

    enum Brand {
        /// Arc-reactor accent — THE theme accent. Resolves live from the user's
        /// APPEARANCE → Accent pref via `ThemeRuntime`. Cyan default `#54e6f0`
        /// (byte-identical to the pre-theming constant).
        @MainActor static var accent: Color { ThemeRuntime.shared.palette.base }
        /// Bright accent highlight (cyan default `#cdf8fb`).
        @MainActor static var accentBright: Color { ThemeRuntime.shared.palette.bright }
        /// Deep accent (cyan default `#14636e`) — orb core falloff, deep fills.
        @MainActor static var accentDeep: Color { ThemeRuntime.shared.palette.deep }
        /// Secondary "Forge" warning accent. Theme-resolved; always separable
        /// from the active accent (e.g. status pips).
        @MainActor static var forge: Color { ThemeRuntime.shared.palette.forge }

        /// Primary CTA gradient — soft accent fill for glowing buttons.
        @MainActor static var accentGradient: LinearGradient {
            LinearGradient(
                colors: [accent.opacity(0.30), accent.opacity(0.10)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        /// Orb core radial — bright center → accent → deep.
        @MainActor static var reactorCore: RadialGradient {
            RadialGradient(
                colors: [accentBright, accent, accentDeep],
                center: UnitPoint(x: 0.5, y: 0.4),
                startRadius: 0,
                endRadius: 22
            )
        }
    }

    // MARK: - Colors

    enum Colors {
        /// Base screen background (Deep Field `#06080c`).
        @MainActor static var background: Color { ThemeRuntime.shared.palette.background }

        // Foreground ramp (theme-resolved; Deep Field = cool slate-cyan).
        /// Primary foreground text.
        @MainActor static var foreground: Color { ThemeRuntime.shared.palette.foreground }
        /// Highest-emphasis foreground — headings on glow.
        @MainActor static var foregroundBright: Color { ThemeRuntime.shared.palette.foregroundBright }
        /// Secondary foreground.
        @MainActor static var secondaryForeground: Color { ThemeRuntime.shared.palette.secondaryForeground }
        /// Muted label foreground — mono telemetry.
        @MainActor static var mutedForeground: Color { ThemeRuntime.shared.palette.mutedForeground }
        /// Dim foreground — faintest captions.
        @MainActor static var dimForeground: Color { ThemeRuntime.shared.palette.dimForeground }
        /// Cool steel text used on list rows.
        @MainActor static var coolForeground: Color { ThemeRuntime.shared.palette.coolForeground }

        /// Translucent panel surface.
        @MainActor static var surface: Color { ThemeRuntime.shared.palette.surface }
        /// Slightly lighter neutral chip surface.
        @MainActor static var chipSurface: Color { ThemeRuntime.shared.palette.chipSurface }
        /// Faint accent-tinted panel fill.
        @MainActor static var surfaceTint: Color { accentTint(0.06) }

        /// Neutral subtle border / divider.
        @MainActor static var divider: Color { ThemeRuntime.shared.palette.divider }
        /// Neutral border at chip strength.
        @MainActor static var chipBorder: Color { ThemeRuntime.shared.palette.chipBorder }

        /// Status / danger red.
        @MainActor static var danger: Color { ThemeRuntime.shared.palette.danger }
        /// High-emphasis danger glyph.
        @MainActor static var dangerBright: Color { ThemeRuntime.shared.palette.dangerBright }

        // --- Accent hairline helpers -------------------------------------
        /// Active accent at an arbitrary opacity.
        @MainActor static func accentTint(_ opacity: Double) -> Color {
            Brand.accent.opacity(opacity)
        }
        /// Default hairline border. Accent-tinted on the dark themes; ink on
        /// Paper Tape (borders shouldn't read as colored marks on paper).
        @MainActor static var hairline: Color { ThemeRuntime.shared.palette.hairline }
        /// Stronger border.
        @MainActor static var strongBorder: Color { ThemeRuntime.shared.palette.strongBorder }

        /// Modal/drawer backdrop scrim.
        @MainActor static var scrim: Color { ThemeRuntime.shared.palette.scrim }

        /// Sessions-drawer vertical gradient.
        @MainActor static var drawerGradient: LinearGradient {
            LinearGradient(
                colors: ThemeRuntime.shared.palette.drawerColors,
                startPoint: .top,
                endPoint: .bottom
            )
        }

        // --- Screen background gradient ----------------------------------
        /// Screen radial gradient (Deep Field:
        /// `radial(120% 70% at 50% -8%, #0c2730 → #070d15 → #04070c)`).
        @MainActor static var screenGradient: RadialGradient {
            RadialGradient(
                stops: ThemeRuntime.shared.palette.screenGradientStops.map {
                    Gradient.Stop(color: $0.color, location: $0.location)
                },
                center: UnitPoint(x: 0.5, y: -0.08),
                startRadius: 0,
                endRadius: 760
            )
        }
    }

    // MARK: - Spacing (4pt base grid)

    enum Spacing {
        static let xxxs: CGFloat = 2
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
        static let xxxl: CGFloat = 64
    }

    // MARK: - Corner Radii

    enum CornerRadius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 11
        static let lg: CGFloat = 14
        static let xl: CGFloat = 16
        static let xxl: CGFloat = 20
        static let full: CGFloat = .infinity
    }

    // MARK: - Typography
    //
    // Three bundled families (registered via Info.plist `UIAppFonts`):
    //  • Chakra Petch  → display, screen titles, buttons (uppercase, heavy tracking)
    //  • Space Grotesk → body & general UI text
    //  • JetBrains Mono → telemetry / labels / timestamps / codes / status lines
    //
    // All built with `Font.custom(_, size:, relativeTo:)` so Dynamic Type still
    // scales the bundled fonts. Use the helpers (`display`, `body`, `mono`) for
    // bespoke sizes; the role tokens below cover the common cases.

    enum Typography {

        // PostScript names of the bundled faces.
        enum FontName {
            static let chakraMedium = "ChakraPetch-Medium"
            static let chakraSemibold = "ChakraPetch-SemiBold"
            static let chakraBold = "ChakraPetch-Bold"

            static let groteskRegular = "SpaceGrotesk-Regular"
            static let groteskMedium = "SpaceGrotesk-Medium"
            static let groteskBold = "SpaceGrotesk-Bold"

            static let monoRegular = "JetBrainsMono-Regular"
            static let monoMedium = "JetBrainsMono-Medium"
            static let monoBold = "JetBrainsMono-Bold"
        }

        enum DisplayWeight { case medium, semibold, bold }
        enum BodyWeight { case regular, medium, bold }
        enum MonoWeight { case regular, medium, bold }

        // MARK: Font builders

        /// Chakra Petch — display / titles / buttons.
        static func display(
            _ size: CGFloat,
            weight: DisplayWeight = .bold,
            relativeTo textStyle: Font.TextStyle = .title
        ) -> Font {
            let name: String
            switch weight {
            case .medium: name = FontName.chakraMedium
            case .semibold: name = FontName.chakraSemibold
            case .bold: name = FontName.chakraBold
            }
            return .custom(name, size: size, relativeTo: textStyle)
        }

        /// Space Grotesk — body & general UI text.
        static func body(
            _ size: CGFloat,
            weight: BodyWeight = .regular,
            relativeTo textStyle: Font.TextStyle = .body
        ) -> Font {
            let name: String
            switch weight {
            case .regular: name = FontName.groteskRegular
            case .medium: name = FontName.groteskMedium
            case .bold: name = FontName.groteskBold
            }
            return .custom(name, size: size, relativeTo: textStyle)
        }

        /// JetBrains Mono — telemetry / labels / timestamps / codes.
        static func mono(
            _ size: CGFloat,
            weight: MonoWeight = .regular,
            relativeTo textStyle: Font.TextStyle = .caption
        ) -> Font {
            let name: String
            switch weight {
            case .regular: name = FontName.monoRegular
            case .medium: name = FontName.monoMedium
            case .bold: name = FontName.monoBold
            }
            return .custom(name, size: size, relativeTo: textStyle)
        }

        // MARK: Role tokens (mapped onto the families above)

        static let heroTitle: Font = display(34, weight: .bold, relativeTo: .largeTitle)
        static let screenTitle: Font = display(26, weight: .bold, relativeTo: .title)
        static let screenTitle2: Font = display(22, weight: .semibold, relativeTo: .title2)
        static let sectionTitle: Font = display(18, weight: .semibold, relativeTo: .title3)
        static let headline: Font = body(17, weight: .bold, relativeTo: .headline)
        static let body: Font = body(16, weight: .regular, relativeTo: .body)
        static let callout: Font = body(15, weight: .regular, relativeTo: .callout)
        static let footnote: Font = body(13, weight: .regular, relativeTo: .footnote)
        static let caption: Font = body(12, weight: .regular, relativeTo: .caption)
        static let caption2: Font = body(11, weight: .regular, relativeTo: .caption2)

        // Common telemetry/mono roles.
        static let monoLabel: Font = mono(11, weight: .medium, relativeTo: .caption)
        static let monoSmall: Font = mono(10, weight: .regular, relativeTo: .caption2)
        static let monoTiny: Font = mono(9, weight: .regular, relativeTo: .caption2)
    }

    // MARK: - Letter spacing (tracking) — design uses heavy em-tracking

    enum Tracking {
        /// Mono telemetry tracking (~.1em at 11pt).
        static let mono: CGFloat = 1.4
        /// Wide mono label tracking (~.2em).
        static let monoWide: CGFloat = 2.2
        /// Extra-wide mono section labels (~.24em).
        static let monoXWide: CGFloat = 2.6
        /// Display / title tracking.
        static let display: CGFloat = 3.0
        /// Button display tracking (~.2em).
        static let button: CGFloat = 2.4
    }

    // MARK: - Animation

    enum Motion {
        static let quickResponse: Animation = .spring(response: 0.25, dampingFraction: 0.8)
        static let standard: Animation = .spring(response: 0.35, dampingFraction: 0.75)
        static let expressive: Animation = .spring(response: 0.5, dampingFraction: 0.7)
        static let gentle: Animation = .spring(response: 0.6, dampingFraction: 0.85)
        static let pulse: Animation = .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
        static let breathe: Animation = .easeInOut(duration: 2.0).repeatForever(autoreverses: true)

        // --- HUD repeating motions (mirror the .dc.html @keyframes timings) ---

        /// Continuous clockwise rotation. `tal-spin`.
        static func spin(_ seconds: Double) -> Animation {
            .linear(duration: seconds).repeatForever(autoreverses: false)
        }
        /// Telemetry blink (`tal-blink`).
        static let blink: Animation = .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
        /// Reactor core breathe (`tal-breathe`, 3s).
        static let reactorBreathe: Animation = .easeInOut(duration: 3.0).repeatForever(autoreverses: true)
        /// Caret blink (`tal-caret`).
        static let caret: Animation = .linear(duration: 1.0).repeatForever(autoreverses: true)
        /// Scan-line sweep duration (seconds).
        static let scanDuration: Double = 7.0
        /// Reticle bob duration (seconds).
        static let reticleDuration: Double = 2.6
    }

    // MARK: - Size

    enum Size {
        static let minTapTarget: CGFloat = 44
        static let iconTiny: CGFloat = 10
        static let iconSmall: CGFloat = 16
        static let iconMedium: CGFloat = 24
        static let iconLarge: CGFloat = 32
        static let iconXL: CGFloat = 40
        static let iconHero: CGFloat = 60
        static let avatarSmall: CGFloat = 32
        static let avatarMedium: CGFloat = 48
        static let avatarLarge: CGFloat = 80
        static let thumbnailSmall: CGFloat = 64
        static let thumbnailMedium: CGFloat = 120
        static let thumbnailLarge: CGFloat = 200
        static let heroHeight: CGFloat = 300
        static let cardMinHeight: CGFloat = 160
        static let badgeSize: CGFloat = 22
        static let inputBarHeight: CGFloat = 52
        static let voiceOrbSize: CGFloat = 232
        static let glassCircleButton: CGFloat = 40

        // --- HUD reactor-orb presets -----------------------------------
        static let orbNav: CGFloat = 30
        static let orbAvatar: CGFloat = 26
        static let orbOnboarding: CGFloat = 74
        static let orbPanel: CGFloat = 42
        /// Corner-bracket arm length on framed views.
        static let bracket: CGFloat = 26
        /// HUD grid cell size.
        static let gridCell: CGFloat = 26
    }

    // MARK: - Glow

    enum Glow {
        /// Global glow intensity knob (the design's `--glowK`) — driven live by
        /// the user's APPEARANCE → Glow Intensity pref. Default 1.0 (unchanged).
        @MainActor static var k: Double { ThemeRuntime.shared.glowIntensity }
    }
}

// MARK: - Runtime theme

/// Live, app-wide theme state. The theme/accent-derived `Design.Brand.*` /
/// `Design.Colors.*` tokens resolve through this singleton, so flipping either
/// APPEARANCE pref re-skins every surface that reads those tokens during its
/// SwiftUI `body` — Swift's Observation registers the access automatically, so
/// there is no per-call-site wiring.
///
/// The single source of truth stays `SettingsStore.settings`; the app root
/// mirrors the five appearance prefs into this object via `apply(_:)`.
@MainActor
@Observable
final class ThemeRuntime {
    static let shared = ThemeRuntime()

    /// Active theme identity — owns the whole color environment.
    var theme: AppearanceTheme = .deepField
    /// Active accent slot — the energetic hue inside the theme.
    var accent: AppearanceAccent = .cyan
    /// HUD glow multiplier (APPEARANCE → Glow Intensity). Default 1.0.
    var glowIntensity: Double = 1.0
    /// Background grid density (APPEARANCE → Grid Density). Default `.faint`.
    var gridDensity: GridDensity = .faint
    /// App-level Reduce Motion override. Combined with the system setting at the
    /// motion modifiers — the app toggle can only *add* restriction.
    var appReduceMotion: Bool = false

    /// Fully resolved palette for the active (theme, accent). Values live in
    /// Shared/ThemePaletteCore.swift.
    var palette: ThemePalette { ThemePalette(theme: theme.themeID, accent: accent.slot) }

    private init() {}

    /// Mirror the appearance-related prefs from `UserSettings` into the runtime.
    /// Per-field guards avoid spurious Observation invalidations when an
    /// unrelated setting changes.
    func apply(_ settings: UserSettings) {
        // `.automatic` mode resolves the seasonal theme; `.manual` (the default)
        // returns the persisted theme unchanged (issue #24), so this is a no-op
        // for existing installs.
        let effectiveTheme = settings.effectiveAppearanceTheme()
        if theme != effectiveTheme { theme = effectiveTheme }
        if accent != settings.appearanceAccent { accent = settings.appearanceAccent }
        if glowIntensity != settings.hudGlowIntensity { glowIntensity = settings.hudGlowIntensity }
        if gridDensity != settings.gridDensity { gridDensity = settings.gridDensity }
        if appReduceMotion != settings.reduceMotion { appReduceMotion = settings.reduceMotion }
    }
}

// MARK: - Palette-core bridges
// UserSettings enums stay model-pure; these map them onto the Shared palette
// identities (same raw cases, explicit switch — no force-unwrapped rawValue).

extension AppearanceTheme {
    var themeID: ThemeID {
        switch self {
        case .deepField: .deepField
        case .solarForge: .solarForge
        case .terminal: .terminal
        case .paperTape: .paperTape
        case .winterFrost: .winterFrost
        case .summerSolar: .summerSolar
        case .springSprout: .springSprout
        case .autumnHarvest: .autumnHarvest
        case .cerealBox: .cerealBox
        case .bubblegumMecha: .bubblegumMecha
        case .retroSciFi: .retroSciFi
        case .eventHorizon: .eventHorizon
        }
    }
}

extension AppearanceAccent {
    var slot: AccentSlot {
        switch self {
        case .cyan: .cyan
        case .amber: .amber
        case .violet: .violet
        }
    }
}
