import SwiftUI

// MARK: - Design Tokens
// All visual constants for Talaria. No magic numbers in view code.

enum Design {

    // MARK: - Brand

    enum Brand {
        /// Hermes warm terracotta accent.
        static let accent = Color(hex: 0xFFBF00)
        static let accentGradient = LinearGradient(
            colors: [accent, accent.opacity(0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Colors

    enum Colors {
        /// Deep charcoal background.
        static let background = Color(hex: 0x2D2D2B)
        /// Warm off-white foreground text.
        static let foreground = Color(hex: 0xF9F9F7)
        /// Muted foreground at 80% contrast.
        static let secondaryForeground = foreground.opacity(0.6)
        /// Subtle surface for cards and elevated elements.
        static let surface = Color.white.opacity(0.08)
        /// Border/divider at low opacity.
        static let divider = Color.white.opacity(0.1)
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
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 28
        static let full: CGFloat = .infinity
    }

    // MARK: - Typography

    enum Typography {
        static let heroTitle: Font = .largeTitle.bold()
        static let screenTitle: Font = .title.bold()
        static let screenTitle2: Font = .title2.bold()
        static let sectionTitle: Font = .title3.bold()
        static let headline: Font = .headline
        static let body: Font = .body
        static let callout: Font = .callout
        static let footnote: Font = .footnote
        static let caption: Font = .caption
        static let caption2: Font = .caption2
    }

    // MARK: - Animation

    enum Motion {
        static let quickResponse: Animation = .spring(response: 0.25, dampingFraction: 0.8)
        static let standard: Animation = .spring(response: 0.35, dampingFraction: 0.75)
        static let expressive: Animation = .spring(response: 0.5, dampingFraction: 0.7)
        static let gentle: Animation = .spring(response: 0.6, dampingFraction: 0.85)
        static let pulse: Animation = .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
        static let breathe: Animation = .easeInOut(duration: 2.0).repeatForever(autoreverses: true)
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
        static let voiceOrbSize: CGFloat = 140
        static let glassCircleButton: CGFloat = 40
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
