import SwiftUI

// MARK: - Design Tokens
// All visual constants for Talaria. No magic numbers or raw hex in view code —
// every view consumes `Design.*`.
//
// Visual language: "Arc-Reactor HUD" — a cool cyan heads-up-display over a deep
// near-black radial field, with mono telemetry labels, cyan hairlines, glowing
// CTAs, and an amber "Forge" warning accent. See design/Talaria.dc.html.

enum Design {

    // MARK: - Brand

    enum Brand {
        /// Arc-reactor cyan — THE theme accent (`#54e6f0`).
        static let accent = Color(hex: 0x54E6F0)
        /// Bright cyan highlight (`#cdf8fb`).
        static let accentBright = Color(hex: 0xCDF8FB)
        /// Deep cyan (`#14636e`) — orb core falloff, deep fills.
        static let accentDeep = Color(hex: 0x14636E)
        /// Secondary "Forge" amber (`#ffc14d`) — warnings / running state.
        static let forge = Color(hex: 0xFFC14D)

        /// Primary CTA gradient — soft cyan fill for glowing buttons.
        static let accentGradient = LinearGradient(
            colors: [accent.opacity(0.30), accent.opacity(0.10)],
            startPoint: .top,
            endPoint: .bottom
        )
        /// Orb core radial — bright center → cyan → deep.
        static let reactorCore = RadialGradient(
            colors: [accentBright, accent, accentDeep],
            center: UnitPoint(x: 0.5, y: 0.4),
            startRadius: 0,
            endRadius: 22
        )
    }

    // MARK: - Colors

    enum Colors {
        /// Deep base background (`#06080c`).
        static let background = Color(hex: 0x06080C)

        // Foreground ramp (cool slate-cyan).
        /// Primary foreground text (`#e8eef5`).
        static let foreground = Color(hex: 0xE8EEF5)
        /// Brightest foreground (`#eaf6f8`) — headings on glow.
        static let foregroundBright = Color(hex: 0xEAF6F8)
        /// Secondary foreground (`#7c93a6`).
        static let secondaryForeground = Color(hex: 0x7C93A6)
        /// Muted label foreground (`#5d7488`) — mono telemetry.
        static let mutedForeground = Color(hex: 0x5D7488)
        /// Dim foreground (`#4d6273`) — faintest captions.
        static let dimForeground = Color(hex: 0x4D6273)
        /// Cool steel text used on list rows (`#cfe1ea`).
        static let coolForeground = Color(hex: 0xCFE1EA)

        /// Translucent dark panel surface (`rgba(8,18,26,.6)`).
        static let surface = Color(hex: 0x08121A, opacity: 0.6)
        /// Slightly lighter neutral chip surface (`rgba(120,150,175,.08)`).
        static let chipSurface = Color(hex: 0x7896AF, opacity: 0.08)
        /// Faint cyan-tinted panel fill (`rgba(84,230,240,.06)`).
        static let surfaceTint = accentTint(0.06)

        /// Neutral subtle border / divider (`rgba(120,150,175,.16)`).
        static let divider = Color(hex: 0x7896AF, opacity: 0.16)
        /// Neutral border at chip strength (`rgba(120,150,175,.22)`).
        static let chipBorder = Color(hex: 0x7896AF, opacity: 0.22)

        /// Status / danger red (`#e0625f`).
        static let danger = Color(hex: 0xE0625F)
        /// Bright danger glyph (`#ff8a86`).
        static let dangerBright = Color(hex: 0xFF8A86)

        // --- Cyan hairline helpers ---------------------------------------
        /// Cyan accent at an arbitrary opacity (`rgba(84,230,240,a)`).
        static func accentTint(_ opacity: Double) -> Color {
            Brand.accent.opacity(opacity)
        }
        /// Default cyan hairline border (`rgba(84,230,240,.14)`).
        static let cyanHairline = accentTint(0.14)
        /// Stronger cyan border (`rgba(84,230,240,.3)`).
        static let cyanBorder = accentTint(0.30)

        /// Modal/drawer backdrop scrim.
        static let scrim = Color(hex: 0x02060A, opacity: 0.85)

        /// Sessions-drawer vertical gradient.
        static let drawerGradient = LinearGradient(
            colors: [Color(hex: 0x0A1822), Color(hex: 0x060C13), Color(hex: 0x05090F)],
            startPoint: .top,
            endPoint: .bottom
        )

        // --- Screen background gradient ----------------------------------
        /// Screen radial gradient: `radial(120% 70% at 50% -8%, #0c2730 → #070d15 → #04070c)`.
        static let screenGradient = RadialGradient(
            stops: [
                .init(color: Color(hex: 0x0C2730), location: 0.0),
                .init(color: Color(hex: 0x070D15), location: 0.52),
                .init(color: Color(hex: 0x04070C), location: 1.0),
            ],
            center: UnitPoint(x: 0.5, y: -0.08),
            startRadius: 0,
            endRadius: 760
        )
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
        /// Global glow intensity knob (the design's `--glowK`).
        static let k: Double = 1.0
    }
}

// MARK: - Color Hex Extension

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
