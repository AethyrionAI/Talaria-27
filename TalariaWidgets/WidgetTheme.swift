import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Widget theme selection
// Each placed widget can pick its own theme in the edit sheet (long-press →
// Edit Widget). `.matchApp` (the default) follows the app's persisted
// appearance via the App Group snapshot; the explicit themes render with
// their hero accent. Palettes come from Shared/ThemePaletteCore.swift — the
// same tables the app uses.

enum WidgetTheme: String, AppEnum {
    case matchApp
    case deepField
    case solarForge
    case terminal
    case paperTape

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Theme")

    static let caseDisplayRepresentations: [WidgetTheme: DisplayRepresentation] = [
        .matchApp: DisplayRepresentation(title: "Match App"),
        .deepField: DisplayRepresentation(title: "Deep Field"),
        .solarForge: DisplayRepresentation(title: "Solar Forge"),
        .terminal: DisplayRepresentation(title: "Terminal"),
        .paperTape: DisplayRepresentation(title: "Paper Tape"),
    ]

    /// Resolve to a concrete palette. `.matchApp` reads the appearance the app
    /// last wrote into the shared snapshot (absent → Deep Field × cyan, the
    /// app default); explicit themes use their hero accent slot.
    func resolvedPalette(data: HermesWidgetData) -> ThemePalette {
        switch self {
        case .matchApp:
            let theme = data.appearanceTheme.flatMap(ThemeID.init(rawValue:)) ?? .deepField
            let accent = data.appearanceAccent.flatMap(AccentSlot.init(rawValue:)) ?? .cyan
            return ThemePalette(theme: theme, accent: accent)
        case .deepField, .solarForge, .terminal, .paperTape:
            // Explicit cases share their raw values with ThemeID, so they
            // resolve by id (#49) — adding a theme is one new case + display
            // title (AppEnum needs static metadata), no palette arms.
            return ThemePalette(theme: ThemeID(rawValue: rawValue) ?? .deepField, accent: .cyan)
        }
    }
}

/// Per-widget configuration — currently just the theme.
struct HermesWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Talaria Widget"
    static let description = IntentDescription("Choose the widget's visual theme.")

    @Parameter(title: "Theme", default: .matchApp)
    var theme: WidgetTheme
}

// MARK: - Shared themed pieces

/// The widget's container background: the theme's screen gradient. Accessory
/// (lock-screen) families ignore container backgrounds, so this only shows on
/// Home Screen families.
struct WidgetThemeBackground: View {
    let palette: ThemePalette

    var body: some View {
        LinearGradient(
            colors: palette.screenGradientStops.map(\.color),
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// Tiny static reactor glyph — ring + core in the palette's accent.
struct WidgetOrbGlyph: View {
    let palette: ThemePalette
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(palette.base.opacity(0.4), lineWidth: 1)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [palette.bright, palette.base, palette.deep],
                        center: UnitPoint(x: 0.5, y: 0.4),
                        startRadius: 0,
                        endRadius: size * 0.3
                    )
                )
                .padding(size * 0.24)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
