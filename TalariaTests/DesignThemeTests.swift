import Foundation
import SwiftUI
import Testing
@testable import Talaria

/// Theme-system invariants: palette resolution, Deep Field legacy identity,
/// runtime mirroring, and persistence defaults. See design/THEME_SYSTEM_PLAN.md.
struct DesignThemeTests {

    // MARK: Palette resolution

    @Test func allThemeAccentCombinationsResolve() {
        for theme in ThemeID.allCases {
            for accent in AccentSlot.allCases {
                let palette = ThemePalette(theme: theme, accent: accent)
                #expect(palette.screenGradientStops.count == 3)
                #expect(palette.drawerColors.count == 3)
                #expect(palette.gridCell > 0)
                #expect(palette.glowScale >= 0)
            }
        }
    }

    @Test func themesProduceDistinctEnvironments() {
        let palettes = ThemeID.allCases.map { ThemePalette(theme: $0, accent: .cyan) }
        for (i, a) in palettes.enumerated() {
            for b in palettes.dropFirst(i + 1) {
                #expect(a.background != b.background || a.surface != b.surface)
                #expect(a.base != b.base)
            }
        }
    }

    @Test func accentSlotsAreDistinctWithinEachUnlockedTheme() {
        for theme in ThemeID.allCases where theme.lockedAccentSlot == nil {
            let bases = AccentSlot.allCases.map { ThemePalette(theme: theme, accent: $0).base }
            #expect(Set(bases).count == bases.count)
        }
    }

    @Test func terminalPinsEveryAccentSlotToPhosphorGreen() {
        // Terminal's identity IS the phosphor green (#12): whatever slot was
        // persisted under another theme, resolution lands on the hero palette.
        #expect(ThemeID.terminal.lockedAccentSlot == .cyan)
        let hero = ThemePalette(theme: .terminal, accent: .cyan)
        for accent in AccentSlot.allCases {
            let p = ThemePalette(theme: .terminal, accent: accent)
            #expect(p == hero)
            #expect(p.base == Color(hex: 0x33FF00))
        }
    }

    @Test func onlyTerminalLocksItsAccent() {
        for theme in ThemeID.allCases {
            #expect((theme.lockedAccentSlot != nil) == (theme == .terminal))
        }
    }

    // MARK: Deep Field legacy identity (byte-identical to pre-theming tokens)

    @Test func deepFieldCyanMatchesLegacyConstants() {
        let p = ThemePalette(theme: .deepField, accent: .cyan)
        #expect(p.base == Color(hex: 0x54E6F0))
        #expect(p.bright == Color(hex: 0xCDF8FB))
        #expect(p.deep == Color(hex: 0x14636E))
        #expect(p.background == Color(hex: 0x06080C))
        #expect(p.foreground == Color(hex: 0xE8EEF5))
        #expect(p.foregroundBright == Color(hex: 0xEAF6F8))
        #expect(p.secondaryForeground == Color(hex: 0x7C93A6))
        #expect(p.mutedForeground == Color(hex: 0x5D7488))
        #expect(p.dimForeground == Color(hex: 0x4D6273))
        #expect(p.coolForeground == Color(hex: 0xCFE1EA))
        #expect(p.surface == Color(hex: 0x08121A, opacity: 0.6))
        #expect(p.chipSurface == Color(hex: 0x7896AF, opacity: 0.08))
        #expect(p.divider == Color(hex: 0x7896AF, opacity: 0.16))
        #expect(p.chipBorder == Color(hex: 0x7896AF, opacity: 0.22))
        #expect(p.scrim == Color(hex: 0x02060A, opacity: 0.85))
        #expect(p.danger == Color(hex: 0xE0625F))
        #expect(p.dangerBright == Color(hex: 0xFF8A86))
        #expect(p.forge == Color(hex: 0xFFC14D))
        #expect(p.hairline == Color(hex: 0x54E6F0).opacity(0.14))
        #expect(p.strongBorder == Color(hex: 0x54E6F0).opacity(0.30))
        #expect(p.glowScale == 1.0)
        #expect(p.gridStyle == .lines)
        #expect(p.gridCell == 26)
        #expect(p.texture == ThemeBackgroundTexture.none)
        #expect(!p.isLight)
        #expect(p.screenGradientStops.map(\.color) ==
                [Color(hex: 0x0C2730), Color(hex: 0x070D15), Color(hex: 0x04070C)])
        #expect(p.drawerColors ==
                [Color(hex: 0x0A1822), Color(hex: 0x060C13), Color(hex: 0x05090F)])
    }

    @Test func deepFieldWarningSwapsUnderAmberAccent() {
        // Pre-theming behavior: forge goes orange under the amber accent so
        // warning stays separable from the accent.
        #expect(ThemePalette(theme: .deepField, accent: .amber).forge == Color(hex: 0xFF7A18))
        #expect(ThemePalette(theme: .deepField, accent: .violet).forge == Color(hex: 0xFFC14D))
    }

    // MARK: Theme behaviors

    @Test func paperTapeIsTheOnlyLightTheme() {
        for theme in AppearanceTheme.allCases {
            #expect(theme.isLight == (theme == .paperTape))
            #expect(ThemePalette(theme: theme.themeID, accent: .cyan).isLight == theme.isLight)
        }
    }

    @Test func heroSlotResolvesToThemeCanonicalHue() {
        // Slot .cyan is always the theme's hero accent.
        #expect(ThemePalette(theme: .solarForge, accent: .cyan).base == Color(hex: 0xFFC14D))
        #expect(ThemePalette(theme: .terminal, accent: .cyan).base == Color(hex: 0x33FF00))
        #expect(ThemePalette(theme: .paperTape, accent: .cyan).base == Color(hex: 0xB5382E))
    }

    @Test func contextualAccentLabels() {
        #expect(AppearanceAccent.cyan.displayLabel(for: .deepField) == "Cyan · Arc")
        #expect(AppearanceAccent.cyan.displayLabel(for: .terminal) == "Green · Phosphor")
        #expect(AppearanceAccent.cyan.displayLabel(for: .paperTape) == "Red · Tracker")
        #expect(AppearanceAccent.amber.displayLabel(for: .solarForge) == "Cyan · Plasma")
    }

    // MARK: Catalog resolution (#49)

    @Test func paletteCatalogCoversEveryTheme() {
        // Resolution is a pure catalog lookup — every render identity must
        // have a definition (definition(for:) falls back visibly otherwise).
        for theme in ThemeID.allCases {
            #expect(ThemePaletteCatalog.definitions[theme] != nil)
        }
    }

    @Test func themeDisplayNamesHaveASingleSource() {
        // AppearanceTheme.displayLabel delegates to the catalog definition,
        // so the two names can no longer drift apart (#49 reconcile).
        for theme in AppearanceTheme.allCases {
            #expect(theme.displayLabel == ThemeCatalog.definition(id: theme.rawValue)?.displayName)
        }
    }

    @Test func flagshipDefinitionsExposeTheirPalettePayload() {
        for definition in ThemeCatalog.flagship {
            #expect(definition.paletteDefinition ==
                    ThemePaletteCatalog.definition(for: definition.appearanceTheme.themeID))
        }
    }

    @Test func orbStyleIsThemeData() {
        // ReactorOrb dispatches on palette data, not theme identity — a new
        // catalog theme picks an existing composition without view edits.
        #expect(ThemePalette(theme: .deepField, accent: .cyan).orbStyle == .arcReactor)
        #expect(ThemePalette(theme: .solarForge, accent: .cyan).orbStyle == .forgeSun)
        #expect(ThemePalette(theme: .terminal, accent: .cyan).orbStyle == .crtCrosshair)
        #expect(ThemePalette(theme: .paperTape, accent: .cyan).orbStyle == .paperReel)
    }

    // MARK: Runtime mirroring

    @MainActor
    @Test func themeRuntimeAppliesAllFivePrefs() {
        let runtime = ThemeRuntime.shared
        let original = UserSettings(
            appearanceTheme: runtime.theme,
            appearanceAccent: runtime.accent,
            hudGlowIntensity: runtime.glowIntensity,
            gridDensity: runtime.gridDensity,
            reduceMotion: runtime.appReduceMotion
        )
        defer { runtime.apply(original) }

        let settings = UserSettings(
            appearanceTheme: .terminal,
            appearanceAccent: .violet,
            hudGlowIntensity: 0.4,
            gridDensity: .bold,
            reduceMotion: true
        )
        runtime.apply(settings)

        #expect(runtime.theme == .terminal)
        #expect(runtime.accent == .violet)
        #expect(runtime.glowIntensity == 0.4)
        #expect(runtime.gridDensity == .bold)
        #expect(runtime.appReduceMotion == true)
        #expect(runtime.palette == ThemePalette(theme: .terminal, accent: .violet))
    }

    // MARK: Persistence

    @Test func decodingWithoutThemeKeyDefaultsToDeepField() throws {
        let decoded = try JSONDecoder().decode(UserSettings.self, from: Data("{}".utf8))
        #expect(decoded.appearanceTheme == .deepField)
        #expect(decoded.appearanceAccent == .cyan)
    }

    @Test func themeRoundTripsThroughCoding() throws {
        var settings = UserSettings()
        settings.appearanceTheme = .paperTape
        settings.appearanceAccent = .amber
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(UserSettings.self, from: data)
        #expect(decoded.appearanceTheme == .paperTape)
        #expect(decoded.appearanceAccent == .amber)
    }
}
