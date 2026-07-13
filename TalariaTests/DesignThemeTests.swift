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
        // Distinct ENVIRONMENTS, not necessarily distinct hero hexes: the
        // gallery ships Cereal Box and Cyber Cactus with the identical
        // #FF5078 hero (verbatim in both handoffs), so the accent check
        // allows a shared base when the environments differ.
        let palettes = ThemeID.allCases.map { ThemePalette(theme: $0, accent: .cyan) }
        for (i, a) in palettes.enumerated() {
            for b in palettes.dropFirst(i + 1) {
                #expect(a.background != b.background || a.surface != b.surface)
                #expect(a.base != b.base || a.background != b.background)
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

    @Test func lightThemesMatchExpectedSet() {
        // Canary for computed `isLight` (derived from each theme's palette). retroSciFi
        // reads light off its palette; seasonal summerSolar/autumnHarvest read dark.
        // Midnight Marquee ships two light palettes (Lane L).
        let lightThemes: Set<AppearanceTheme> = [.paperTape, .retroSciFi, .springSprout, .winterFrost,
                                                 .pulpNoir, .stickerBombToybox]
        for theme in AppearanceTheme.allCases {
            #expect(theme.isLight == lightThemes.contains(theme))
            #expect(ThemePalette(theme: theme.themeID, accent: .cyan).isLight == theme.isLight)
        }
    }

    @Test func heroSlotResolvesToThemeCanonicalHue() {
        // Slot .cyan is always the theme's hero accent.
        #expect(ThemePalette(theme: .solarForge, accent: .cyan).base == Color(hex: 0xFFC14D))
        #expect(ThemePalette(theme: .terminal, accent: .cyan).base == Color(hex: 0x33FF00))
        #expect(ThemePalette(theme: .paperTape, accent: .cyan).base == Color(hex: 0xB5382E))
        #expect(ThemePalette(theme: .winterFrost, accent: .cyan).base == Color(hex: 0x3AB3F0))
        #expect(ThemePalette(theme: .summerSolar, accent: .cyan).base == Color(hex: 0xFFA028))
        #expect(ThemePalette(theme: .springSprout, accent: .cyan).base == Color(hex: 0xFF6B8A))
        #expect(ThemePalette(theme: .autumnHarvest, accent: .cyan).base == Color(hex: 0xFF8C28))
        // Batch 1 gallery ports.
        #expect(ThemePalette(theme: .glitchGarden, accent: .cyan).base == Color(hex: 0x39FF14))
        #expect(ThemePalette(theme: .witchsBrew, accent: .cyan).base == Color(hex: 0x4ADE80))
        #expect(ThemePalette(theme: .holoSushi, accent: .cyan).base == Color(hex: 0xFF69B4))
        // Batch 2.
        #expect(ThemePalette(theme: .lunarDiner, accent: .cyan).base == Color(hex: 0xFF9AB4))
        #expect(ThemePalette(theme: .cyberCactus, accent: .cyan).base == Color(hex: 0xFF5078))
        #expect(ThemePalette(theme: .discoInferno, accent: .cyan).base == Color(hex: 0xFFD700))
        // Batch 3 — Special Editions.
        #expect(ThemePalette(theme: .graffitiGalaxy, accent: .cyan).base == Color(hex: 0xFF006E))
        #expect(ThemePalette(theme: .karaokeSupernova, accent: .cyan).base == Color(hex: 0xFF00AA))
        // Batch 4 — Claude-Design Special Editions.
        #expect(ThemePalette(theme: .midnightAquarium, accent: .cyan).base == Color(hex: 0xFF7AD9))
        #expect(ThemePalette(theme: .moltenForge, accent: .cyan).base == Color(hex: 0xFF6A1A))
        // Midnight Marquee (Lane L — Final Lineup hero hexes).
        #expect(ThemePalette(theme: .luchaLibre, accent: .cyan).base == Color(hex: 0x3D6BFF))
        #expect(ThemePalette(theme: .kaijuAttack, accent: .cyan).base == Color(hex: 0x6AFF57))
        #expect(ThemePalette(theme: .pulpNoir, accent: .cyan).base == Color(hex: 0x276F6D))
        #expect(ThemePalette(theme: .casinoLucky7s, accent: .cyan).base == Color(hex: 0x4F9DFF))
        #expect(ThemePalette(theme: .cosmicBowling, accent: .cyan).base == Color(hex: 0x00B3A4))
        #expect(ThemePalette(theme: .stickerBombToybox, accent: .cyan).base == Color(hex: 0x4BBF22))
    }

    @Test func contextualAccentLabels() {
        #expect(AppearanceAccent.cyan.displayLabel(for: .deepField) == "Cyan · Arc")
        #expect(AppearanceAccent.cyan.displayLabel(for: .terminal) == "Green · Phosphor")
        #expect(AppearanceAccent.cyan.displayLabel(for: .paperTape) == "Red · Tracker")
        #expect(AppearanceAccent.amber.displayLabel(for: .solarForge) == "Cyan · Plasma")
        #expect(AppearanceAccent.cyan.displayLabel(for: .winterFrost) == "Ice · Winter")
        #expect(AppearanceAccent.cyan.displayLabel(for: .summerSolar) == "Mango · Summer")
        #expect(AppearanceAccent.cyan.displayLabel(for: .springSprout) == "Blossom · Spring")
        #expect(AppearanceAccent.cyan.displayLabel(for: .autumnHarvest) == "Pumpkin · Autumn")
        #expect(AppearanceAccent.cyan.displayLabel(for: .glitchGarden) == "Vine · Garden")
        #expect(AppearanceAccent.amber.displayLabel(for: .witchsBrew) == "Mystic · Brew")
        #expect(AppearanceAccent.violet.displayLabel(for: .holoSushi) == "Nori · Sushi")
        // Disco keeps the handoff-native slot names (EH precedent).
        #expect(AppearanceAccent.cyan.displayLabel(for: .discoInferno) == "Disco Gold")
        #expect(AppearanceAccent.amber.displayLabel(for: .discoInferno) == "Mirror Silver")
        #expect(AppearanceAccent.violet.displayLabel(for: .discoInferno) == "Hellfire Crimson")
        // The Special Editions likewise.
        #expect(AppearanceAccent.cyan.displayLabel(for: .graffitiGalaxy) == "Hot Pink")
        #expect(AppearanceAccent.amber.displayLabel(for: .graffitiGalaxy) == "Electric Violet")
        #expect(AppearanceAccent.cyan.displayLabel(for: .karaokeSupernova) == "Magenta")
        // Batch 4 keeps the handoff-native slot names.
        #expect(AppearanceAccent.cyan.displayLabel(for: .midnightAquarium) == "Jelly Pink")
        #expect(AppearanceAccent.amber.displayLabel(for: .midnightAquarium) == "Biolume Cyan")
        #expect(AppearanceAccent.violet.displayLabel(for: .midnightAquarium) == "Anemone Violet")
        #expect(AppearanceAccent.cyan.displayLabel(for: .moltenForge) == "Lava Orange")
        #expect(AppearanceAccent.amber.displayLabel(for: .moltenForge) == "Spark Gold")
        #expect(AppearanceAccent.violet.displayLabel(for: .moltenForge) == "Hammered Steel")
        // Midnight Marquee keeps the handoff-native slot names (Lane L).
        #expect(AppearanceAccent.cyan.displayLabel(for: .luchaLibre) == "Royal Blue")
        #expect(AppearanceAccent.amber.displayLabel(for: .luchaLibre) == "Pyro Orange")
        #expect(AppearanceAccent.violet.displayLabel(for: .luchaLibre) == "Chrome Silver")
        #expect(AppearanceAccent.cyan.displayLabel(for: .kaijuAttack) == "Radioactive Green")
        #expect(AppearanceAccent.cyan.displayLabel(for: .pulpNoir) == "Library Teal")
        #expect(AppearanceAccent.amber.displayLabel(for: .pulpNoir) == "Mustard Gold")
        #expect(AppearanceAccent.cyan.displayLabel(for: .casinoLucky7s) == "Chip Blue")
        #expect(AppearanceAccent.cyan.displayLabel(for: .cosmicBowling) == "Alley Teal")
        #expect(AppearanceAccent.violet.displayLabel(for: .stickerBombToybox) == "Grape Pop")
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
        #expect(ThemePalette(theme: .winterFrost, accent: .cyan).orbStyle == .arcReactor)
        #expect(ThemePalette(theme: .summerSolar, accent: .cyan).orbStyle == .arcReactor)
        #expect(ThemePalette(theme: .springSprout, accent: .cyan).orbStyle == .arcReactor)
        #expect(ThemePalette(theme: .autumnHarvest, accent: .cyan).orbStyle == .arcReactor)
        // Event Horizon's bespoke composition (Lane E Task 2).
        #expect(ThemePalette(theme: .eventHorizon, accent: .cyan).orbStyle == .singularity)
        // Gallery-port compositions (Lane E Phase 3 batch 1): the three new
        // NAC themes plus the recolor retrofits' handoff orbs.
        #expect(ThemePalette(theme: .glitchGarden, accent: .cyan).orbStyle == .glitchSeed)
        #expect(ThemePalette(theme: .witchsBrew, accent: .cyan).orbStyle == .cauldronBrew)
        #expect(ThemePalette(theme: .holoSushi, accent: .cyan).orbStyle == .holoNigiri)
        #expect(ThemePalette(theme: .cerealBox, accent: .cyan).orbStyle == .prizeWheel)
        #expect(ThemePalette(theme: .bubblegumMecha, accent: .cyan).orbStyle == .candyMecha)
        #expect(ThemePalette(theme: .retroSciFi, accent: .cyan).orbStyle == .rocketBadge)
        // Batch 2.
        #expect(ThemePalette(theme: .lunarDiner, accent: .cyan).orbStyle == .jukeboxGlow)
        #expect(ThemePalette(theme: .cyberCactus, accent: .cyan).orbStyle == .cactusBloom)
        #expect(ThemePalette(theme: .discoInferno, accent: .cyan).orbStyle == .discoBall)
        // Batch 3 — Special Editions.
        #expect(ThemePalette(theme: .graffitiGalaxy, accent: .cyan).orbStyle == .sprayCap)
        #expect(ThemePalette(theme: .karaokeSupernova, accent: .cyan).orbStyle == .mirrorBall)
        // Batch 4 — Claude-Design Special Editions.
        #expect(ThemePalette(theme: .midnightAquarium, accent: .cyan).orbStyle == .moonJelly)
        #expect(ThemePalette(theme: .moltenForge, accent: .cyan).orbStyle == .crucible)
        // Midnight Marquee (Lane L).
        #expect(ThemePalette(theme: .luchaLibre, accent: .cyan).orbStyle == .rudoMask)
        #expect(ThemePalette(theme: .kaijuAttack, accent: .cyan).orbStyle == .kaijuSiren)
        #expect(ThemePalette(theme: .pulpNoir, accent: .cyan).orbStyle == .dimeStamp)
        #expect(ThemePalette(theme: .casinoLucky7s, accent: .cyan).orbStyle == .luckySevens)
        #expect(ThemePalette(theme: .cosmicBowling, accent: .cyan).orbStyle == .houseBall)
        #expect(ThemePalette(theme: .stickerBombToybox, accent: .cyan).orbStyle == .stickerStar)
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
