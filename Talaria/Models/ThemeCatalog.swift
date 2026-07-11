import Foundation

// MARK: - Theme catalog / framework foundation (issues #24 + #49)
//
// A data-driven description of the app's themes: identity, availability
// (seasonal auto-rotation, holiday date windows), and the `locked` gate. The
// render layer is data too (#49): each definition's colors live in the shared
// `ThemePaletteCatalog` (Shared/ThemePaletteCore.swift — compiled into the
// widget target as well), reachable here via `paletteDefinition`.
//
// Today every definition renders through a flagship `AppearanceTheme`. A future
// seasonal/holiday theme with a bespoke palette is one `ThemeID` +
// `ThemePaletteCatalog` entry + one definition here — no switch-arm edits.

/// Northern-Hemisphere meteorological season (hemisphere hardcoded per the
/// issue's stated scope). Meteorological (month-based) boundaries are used over
/// astronomical ones — they're stable, need no ephemeris, and are trivially
/// testable.
enum Season: String, CaseIterable, Hashable, Sendable {
    case winter, spring, summer, autumn

    var displayLabel: String {
        switch self {
        case .winter: "Winter"
        case .spring: "Spring"
        case .summer: "Summer"
        case .autumn: "Autumn"
        }
    }
}

/// A recurring, year-agnostic calendar window (month/day .. month/day, inclusive)
/// used to gate holiday/special themes. Handles ranges that wrap the year
/// boundary (e.g. Dec 20 – Jan 5).
struct DateWindow: Hashable, Sendable {
    let startMonth: Int
    let startDay: Int
    let endMonth: Int
    let endDay: Int

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        let current = month * 100 + day
        let start = startMonth * 100 + startDay
        let end = endMonth * 100 + endDay
        if start <= end {
            return current >= start && current <= end
        }
        // Wraps the new year: inside if after the start OR before the end.
        return current >= start || current <= end
    }
}

/// When a theme is offered in the picker.
enum ThemeAvailability: Hashable, Sendable {
    /// Always selectable.
    case always
    /// Always selectable, and auto-applied during `season` when the app's theme
    /// mode is `.automatic`.
    case seasonal(Season)
    /// Present in the picker ONLY inside `window` — outside it the theme is
    /// simply absent from the list (issue #24).
    case holiday(DateWindow)
}

/// One catalog theme: identity + how it renders + when it's offered + gating.
struct ThemeDefinition: Identifiable, Hashable, Sendable {
    /// Stable id (persist-safe). Flagship ids equal their `AppearanceTheme`
    /// raw value; future special themes use their own (e.g. "halloween").
    let id: String
    let displayName: String
    let subtitle: String?
    /// The persisted render identity this definition maps onto. Flagship themes
    /// map 1:1; a future bespoke-palette theme gets its own `AppearanceTheme`
    /// case when the palette core is data-driven (see the plan).
    let appearanceTheme: AppearanceTheme
    let availability: ThemeAvailability
    /// Reserved premium/paid gate, baked in from day one (issue #24) so a future
    /// tier is a flag flip, not a retrofit. Every shipped theme is `false` today.
    let locked: Bool

    var season: Season? {
        if case let .seasonal(season) = availability { return season }
        return nil
    }

    /// The render-layer palette payload this definition renders with — the
    /// data `ThemePalette(theme:accent:)` resolves from (#49). Owned by the
    /// shared `ThemePaletteCatalog` (not stored here) so the widget target,
    /// which never sees this app-level catalog, reads the same table.
    var paletteDefinition: ThemePaletteDefinition {
        ThemePaletteCatalog.definition(for: appearanceTheme.themeID)
    }
}

/// One titled group of the theme picker — the gallery taxonomy's sections
/// (Flagship / Neon Arcade Collection / Special Edition / Seasonal).
struct ThemeSection: Identifiable, Sendable {
    let title: String
    let definitions: [ThemeDefinition]
    var id: String { title }
}

enum ThemeCatalog {

    // MARK: Definitions

    /// The four shipped flagship themes, 1:1 with the render enum. They stay
    /// always-available: they're core brand identities, not seasonal content.
    static let flagship: [ThemeDefinition] = [
        ThemeDefinition(id: AppearanceTheme.deepField.rawValue, displayName: "Deep Field",
                        subtitle: "Cyan Arc", appearanceTheme: .deepField,
                        availability: .always, locked: false),
        ThemeDefinition(id: AppearanceTheme.solarForge.rawValue, displayName: "Solar Forge",
                        subtitle: "Forge Amber", appearanceTheme: .solarForge,
                        availability: .always, locked: false),
        ThemeDefinition(id: AppearanceTheme.terminal.rawValue, displayName: "Terminal",
                        subtitle: "Phosphor Green", appearanceTheme: .terminal,
                        availability: .always, locked: false),
        ThemeDefinition(id: AppearanceTheme.paperTape.rawValue, displayName: "Paper Tape",
                        subtitle: "Tracker Red", appearanceTheme: .paperTape,
                        availability: .always, locked: false),
    ]

    /// Neon Arcade Collection — the gallery's signature themes (issue #54;
    /// `design/themes/`). Batch 1 (#91) adds Glitch Garden / Witch's Brew /
    /// Holo Sushi; the remaining four collection themes join in batch 2.
    /// Neon Arcade #01 is the gallery's own chrome, not a portable theme
    /// (Lane E Phase 2 discovery).
    static let neonArcadeCollection: [ThemeDefinition] = [
        ThemeDefinition(id: AppearanceTheme.cerealBox.rawValue, displayName: "Cereal Box",
                        subtitle: "Breakfast", appearanceTheme: .cerealBox,
                        availability: .always, locked: false),
        ThemeDefinition(id: AppearanceTheme.bubblegumMecha.rawValue, displayName: "Bubblegum Mecha",
                        subtitle: "Sugar", appearanceTheme: .bubblegumMecha,
                        availability: .always, locked: false),
        ThemeDefinition(id: AppearanceTheme.retroSciFi.rawValue, displayName: "Retro Sci-Fi",
                        subtitle: "Retro", appearanceTheme: .retroSciFi,
                        availability: .always, locked: false),
        ThemeDefinition(id: AppearanceTheme.glitchGarden.rawValue, displayName: "Glitch Garden",
                        subtitle: "Vine Green", appearanceTheme: .glitchGarden,
                        availability: .always, locked: false),
        ThemeDefinition(id: AppearanceTheme.witchsBrew.rawValue, displayName: "Witch's Brew",
                        subtitle: "Poison Green", appearanceTheme: .witchsBrew,
                        availability: .always, locked: false),
        ThemeDefinition(id: AppearanceTheme.holoSushi.rawValue, displayName: "Holo Sushi",
                        subtitle: "Roe Pink", appearanceTheme: .holoSushi,
                        availability: .always, locked: false),
        ThemeDefinition(id: AppearanceTheme.lunarDiner.rawValue, displayName: "Lunar Diner",
                        subtitle: "Soda Pink", appearanceTheme: .lunarDiner,
                        availability: .always, locked: false),
        ThemeDefinition(id: AppearanceTheme.cyberCactus.rawValue, displayName: "Cyber Cactus",
                        subtitle: "Sunset", appearanceTheme: .cyberCactus,
                        availability: .always, locked: false),
        ThemeDefinition(id: AppearanceTheme.discoInferno.rawValue, displayName: "Disco Inferno",
                        subtitle: "Disco Gold", appearanceTheme: .discoInferno,
                        availability: .always, locked: false),
    ]

    /// Special Edition — bespoke art-directed themes beyond a recolor (motion
    /// field, custom orb). Batches 1–3 shipped the gallery trio; batch 4 (#91)
    /// adds the three Claude-Design exports. The gallery's "Neon Arcade #01"
    /// card is the gallery chrome itself, not an SE (Lane E Phase 2 discovery).
    static let specialEdition: [ThemeDefinition] = [
        ThemeDefinition(id: AppearanceTheme.eventHorizon.rawValue, displayName: "Event Horizon",
                        subtitle: "Singularity", appearanceTheme: .eventHorizon,
                        availability: .always, locked: false),
        ThemeDefinition(id: AppearanceTheme.graffitiGalaxy.rawValue, displayName: "Graffiti Galaxy",
                        subtitle: "Spray Cap", appearanceTheme: .graffitiGalaxy,
                        availability: .always, locked: false),
        ThemeDefinition(id: AppearanceTheme.karaokeSupernova.rawValue, displayName: "Karaoke Supernova",
                        subtitle: "Mirror Ball", appearanceTheme: .karaokeSupernova,
                        availability: .always, locked: false),
        ThemeDefinition(id: AppearanceTheme.midnightAquarium.rawValue, displayName: "Midnight Aquarium",
                        subtitle: "Moon Jelly", appearanceTheme: .midnightAquarium,
                        availability: .always, locked: false),
    ]

    /// The four meteorological-season themes; holiday themes become additional
    /// entries with `.holiday(DateWindow(...))` and `locked: true` as needed (#24).
    static let seasonal: [ThemeDefinition] = [
        ThemeDefinition(id: AppearanceTheme.winterFrost.rawValue, displayName: "Winter Frost",
                        subtitle: "Ice", appearanceTheme: .winterFrost,
                        availability: .seasonal(.winter), locked: false),
        ThemeDefinition(id: AppearanceTheme.springSprout.rawValue, displayName: "Spring Sprout",
                        subtitle: "Blossom", appearanceTheme: .springSprout,
                        availability: .seasonal(.spring), locked: false),
        ThemeDefinition(id: AppearanceTheme.summerSolar.rawValue, displayName: "Summer Solar",
                        subtitle: "Mango", appearanceTheme: .summerSolar,
                        availability: .seasonal(.summer), locked: false),
        ThemeDefinition(id: AppearanceTheme.autumnHarvest.rawValue, displayName: "Autumn Harvest",
                        subtitle: "Pumpkin", appearanceTheme: .autumnHarvest,
                        availability: .seasonal(.autumn), locked: false),
    ]

    /// The picker's titled sections, in display order — mirrors the gallery
    /// taxonomy (`design/themes/index.html`). Section availability still runs
    /// through `availableDefinitions(on:in:)` per group.
    static let sections: [ThemeSection] = [
        ThemeSection(title: "Flagship", definitions: flagship),
        ThemeSection(title: "Neon Arcade Collection", definitions: neonArcadeCollection),
        ThemeSection(title: "Special Edition", definitions: specialEdition),
        ThemeSection(title: "Seasonal", definitions: seasonal),
    ]

    /// Every known definition (order: the gallery taxonomy — flagship, Neon
    /// Arcade Collection, Special Edition, seasonal).
    static var all: [ThemeDefinition] {
        flagship + neonArcadeCollection + specialEdition + seasonal
    }

    /// Definitions to show in the picker for `date`: flagship + seasonal always
    /// appear; holiday definitions only inside their window. Locked definitions
    /// are still listed (shown with a lock) so users can see what a paid tier
    /// would unlock.
    static func availableDefinitions(on date: Date, calendar: Calendar = .current) -> [ThemeDefinition] {
        availableDefinitions(on: date, in: all, calendar: calendar)
    }

    /// Testable core of `availableDefinitions` — filters an explicit definition
    /// list so holiday windowing can be exercised against a synthetic catalog.
    static func availableDefinitions(
        on date: Date,
        in definitions: [ThemeDefinition],
        calendar: Calendar = .current
    ) -> [ThemeDefinition] {
        definitions.filter { definition in
            switch definition.availability {
            case .always, .seasonal:
                return true
            case let .holiday(window):
                return window.contains(date, calendar: calendar)
            }
        }
    }

    static func definition(id: String) -> ThemeDefinition? {
        all.first { $0.id == id }
    }

    // MARK: Seasonal rotation

    /// Meteorological season for `date` (Northern Hemisphere).
    static func season(on date: Date, calendar: Calendar = .current) -> Season {
        switch calendar.component(.month, from: date) {
        case 12, 1, 2: return .winter
        case 3, 4, 5: return .spring
        case 6, 7, 8: return .summer
        default: return .autumn
        }
    }

    /// The theme automatic mode applies for `date`.
    ///
    /// v1 maps each season to an existing flagship palette (documented placeholder
    /// pending curated seasonal palettes — a content follow-up). A `.seasonal`
    /// definition, if present, wins over this default mapping for its season.
    static func seasonalTheme(on date: Date, calendar: Calendar = .current) -> AppearanceTheme {
        let season = season(on: date, calendar: calendar)
        if let match = all.first(where: { $0.season == season }) {
            return match.appearanceTheme
        }
        switch season {
        case .winter: return .deepField   // cold blue
        case .spring: return .terminal    // fresh green
        case .summer: return .solarForge  // warm amber
        case .autumn: return .paperTape   // warm paper
        }
    }
}
