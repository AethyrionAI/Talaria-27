import Foundation
import Testing
@testable import Talaria

/// Theme-framework foundation invariants (issue #24): seasonal rotation, holiday
/// date windows (incl. year wrap), the catalog model, the reserved `locked`
/// flag, and `UserSettings.effectiveAppearanceTheme` mode behavior. Palette
/// values are NOT touched here — Deep Field byte-identity stays guarded by
/// DesignThemeTests.
struct ThemeCatalogTests {

    /// A gregorian/UTC calendar so month/day boundaries are deterministic.
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    // MARK: Seasons (Northern-Hemisphere meteorological)

    @Test func seasonBoundariesByMonth() {
        #expect(ThemeCatalog.season(on: date(2026, 1, 15), calendar: utc) == .winter)
        #expect(ThemeCatalog.season(on: date(2026, 2, 15), calendar: utc) == .winter)
        #expect(ThemeCatalog.season(on: date(2026, 3, 15), calendar: utc) == .spring)
        #expect(ThemeCatalog.season(on: date(2026, 5, 31), calendar: utc) == .spring)
        #expect(ThemeCatalog.season(on: date(2026, 6, 1), calendar: utc) == .summer)
        #expect(ThemeCatalog.season(on: date(2026, 8, 20), calendar: utc) == .summer)
        #expect(ThemeCatalog.season(on: date(2026, 9, 1), calendar: utc) == .autumn)
        #expect(ThemeCatalog.season(on: date(2026, 11, 30), calendar: utc) == .autumn)
        #expect(ThemeCatalog.season(on: date(2026, 12, 1), calendar: utc) == .winter)
    }

    @Test func seasonalThemeMappingIsStable() {
        #expect(ThemeCatalog.seasonalTheme(on: date(2026, 1, 15), calendar: utc) == .winterFrost)
        #expect(ThemeCatalog.seasonalTheme(on: date(2026, 4, 15), calendar: utc) == .springSprout)
        #expect(ThemeCatalog.seasonalTheme(on: date(2026, 7, 15), calendar: utc) == .summerSolar)
        #expect(ThemeCatalog.seasonalTheme(on: date(2026, 10, 15), calendar: utc) == .autumnHarvest)
    }

    // MARK: Date windows

    @Test func dateWindowNormalRange() {
        let october = DateWindow(startMonth: 10, startDay: 1, endMonth: 10, endDay: 31)
        #expect(october.contains(date(2026, 10, 1), calendar: utc))
        #expect(october.contains(date(2026, 10, 15), calendar: utc))
        #expect(october.contains(date(2026, 10, 31), calendar: utc))
        #expect(!october.contains(date(2026, 9, 30), calendar: utc))
        #expect(!october.contains(date(2026, 11, 1), calendar: utc))
    }

    @Test func dateWindowWrapsYearBoundary() {
        // Dec 20 – Jan 5 (the holiday break).
        let window = DateWindow(startMonth: 12, startDay: 20, endMonth: 1, endDay: 5)
        #expect(window.contains(date(2026, 12, 20), calendar: utc))
        #expect(window.contains(date(2026, 12, 31), calendar: utc))
        #expect(window.contains(date(2026, 1, 1), calendar: utc))
        #expect(window.contains(date(2026, 1, 5), calendar: utc))
        #expect(!window.contains(date(2026, 1, 6), calendar: utc))
        #expect(!window.contains(date(2026, 6, 1), calendar: utc))
    }

    // MARK: Availability (holiday windowing)

    @Test func flagshipsAreAlwaysAvailable() {
        // Any date of the year surfaces all four flagship themes.
        for month in 1...12 {
            let available = ThemeCatalog.availableDefinitions(on: date(2026, month, 15), calendar: utc)
            let themes = Set(available.map(\.appearanceTheme))
            #expect(themes == Set(AppearanceTheme.allCases))
        }
    }

    @Test func holidayThemeAppearsOnlyInWindow() {
        let halloween = ThemeDefinition(
            id: "halloween", displayName: "Halloween", subtitle: nil,
            appearanceTheme: .solarForge,
            availability: .holiday(DateWindow(startMonth: 10, startDay: 24, endMonth: 11, endDay: 1)),
            locked: true
        )
        let catalog = ThemeCatalog.flagship + [halloween]

        let inWindow = ThemeCatalog.availableDefinitions(on: date(2026, 10, 28), in: catalog, calendar: utc)
        let outOfWindow = ThemeCatalog.availableDefinitions(on: date(2026, 6, 1), in: catalog, calendar: utc)

        #expect(inWindow.contains(halloween))
        #expect(!outOfWindow.contains(halloween))
        // Flagships remain regardless.
        #expect(outOfWindow.count == ThemeCatalog.flagship.count)
    }

    // MARK: Catalog model

    @Test func allDefinitionsCoverEveryRenderTheme() {
        for theme in AppearanceTheme.allCases {
            #expect(ThemeCatalog.all.contains { $0.appearanceTheme == theme })
        }
    }

    @Test func idsAreUniqueAndFlagshipIdsMatchRawValue() {
        let ids = ThemeCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        for definition in ThemeCatalog.flagship {
            #expect(definition.id == definition.appearanceTheme.rawValue)
        }
    }

    @Test func shippedThemesAreUnlocked() {
        // The locked flag exists from day one but nothing ships locked yet (#24).
        #expect(ThemeCatalog.all.allSatisfy { $0.locked == false })
    }

    @Test func seasonalAvailabilityExposesItsSeason() {
        // `.seasonal` definitions surface their season (which the resolver uses
        // to override the default map). Checked on a synthetic definition so the
        // shipped catalog (flagship-only) stays untouched.
        let def = ThemeDefinition(id: "spring-special", displayName: "Bloom", subtitle: nil,
                                  appearanceTheme: .paperTape, availability: .seasonal(.spring), locked: false)
        #expect(def.season == .spring)
        let always = ThemeDefinition(id: "x", displayName: "X", subtitle: nil,
                                     appearanceTheme: .deepField, availability: .always, locked: false)
        #expect(always.season == nil)
    }

    // MARK: UserSettings effective theme

    @Test func manualModeIgnoresSeason() {
        var settings = UserSettings()
        settings.appearanceThemeMode = .manual
        settings.appearanceTheme = .paperTape
        // Deep winter, but manual pin holds.
        #expect(settings.effectiveAppearanceTheme(on: date(2026, 1, 1)) == .paperTape)
    }

    @Test func automaticModeFollowsSeason() {
        var settings = UserSettings()
        settings.appearanceThemeMode = .automatic
        let midSummer = date(2026, 7, 15)
        #expect(settings.effectiveAppearanceTheme(on: midSummer) == ThemeCatalog.seasonalTheme(on: midSummer))
    }

    @Test func modeDefaultsToManualAndRoundTrips() throws {
        // Absent key decodes to manual (back-compat with pre-#24 blobs).
        let legacy = try JSONDecoder().decode(UserSettings.self, from: Data("{}".utf8))
        #expect(legacy.appearanceThemeMode == .manual)

        var settings = UserSettings()
        settings.appearanceThemeMode = .automatic
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(UserSettings.self, from: data)
        #expect(decoded.appearanceThemeMode == .automatic)
    }
}
