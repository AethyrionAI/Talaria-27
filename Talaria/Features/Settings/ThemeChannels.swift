import SwiftUI
import UIKit

// MARK: - #244: the Appearance channel browser's list (pure, testable)
//
// One theme per full-bleed channel. Channel 00 is Seasonal AUTO (resolves the
// current season's theme; landing on it writes `.automatic` mode); the rest
// are the catalog's picker identities in section order, availability-filtered
// exactly as the retired grid was.

enum ThemeChannels {
    struct Channel: Equatable, Identifiable {
        enum Kind: Equatable { case automatic, theme }
        let kind: Kind
        let definition: ThemeDefinition
        let sectionTitle: String

        var id: String { kind == .automatic ? "auto" : definition.id }

        /// Terminal pins every accent slot to its hero hue (#12) — the
        /// browser hides the accent dots on such a channel.
        var locksAccent: Bool {
            // Non-adaptive themes resolve identically for either scheme; the
            // one adaptive theme (Comic Book) locks nothing in either half.
            definition.appearanceTheme.themeID(for: .dark).lockedAccentSlot != nil
        }
    }

    static let automaticSectionTitle = "Auto \u{00b7} Seasonal"

    static func build(on date: Date = Date()) -> [Channel] {
        var channels: [Channel] = []
        let seasonal = ThemeCatalog.seasonalTheme(on: date)
        if let resolved = ThemeCatalog.all.first(where: { $0.appearanceTheme == seasonal }) {
            channels.append(Channel(kind: .automatic, definition: resolved, sectionTitle: Self.automaticSectionTitle))
        }
        for section in ThemeCatalog.sections {
            for definition in ThemeCatalog.availableDefinitions(on: date, in: section.definitions) {
                channels.append(Channel(kind: .theme, definition: definition, sectionTitle: section.title))
            }
        }
        return channels
    }

    /// Uppercase RRGGBB for a resolved color — real computed values; the
    /// palette definitions keep no raw hex strings (#244 spec). Resolution is
    /// trait-independent for the palette colors in play (all built from
    /// `Color(hex:)` literals).
    static func hexLabel(for color: Color) -> String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func byte(_ component: CGFloat) -> Int { Int((component * 255).rounded()) }
        return String(format: "%02X%02X%02X", byte(red), byte(green), byte(blue))
    }
}
