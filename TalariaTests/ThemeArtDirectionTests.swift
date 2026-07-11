import SwiftUI
import Testing
@testable import Talaria

/// Art-direction layer invariants (design/THEME_ART_DIRECTION_PLAN.md):
/// the default treatment must be inert so un-listed themes — Deep Field
/// above all — render byte-identically to the pre-art-direction app.
struct ThemeArtDirectionTests {

    @Test func standardArtDirectionIsInert() {
        let standard = ThemeArtDirection.standard
        #expect(standard.glowPools.isEmpty)
        #expect(standard.emberTint == nil)
        #expect(standard.starfield == nil)
        #expect(standard.panelHalo == nil)
        #expect(standard.atmosphereMotion == nil)
        #expect(standard.titleGlow == nil)
        // Phase 2 spec types must default off — a theme without an entry
        // renders byte-identically through every new slot.
        #expect(standard.radialSpokes == nil)
        #expect(standard.lineTexture == nil)
        #expect(standard.scanlineOverlay == nil)
        #expect(standard.titleShadow == nil)
    }

    // MARK: Phase 2 schema extension (Lane E)

    @Test func lineFieldsAndTitleShadowsAreDeliberatePerTheme() {
        // The Phase 2 slots stay nil except where a port sets them — update
        // these sets deliberately per batch.
        let lineTextures: Set<ThemeID> = [.holoSushi, .cyberCactus, .graffitiGalaxy]
        let scanlineOverlays: Set<ThemeID> = [
            .glitchGarden, .bubblegumMecha, .retroSciFi, .discoInferno,
        ]
        let titleShadows: Set<ThemeID> = [.glitchGarden, .retroSciFi, .graffitiGalaxy]
        for theme in ThemeID.allCases {
            let art = ThemeArtDirectionCatalog.artDirection(for: theme)
            #expect((art.lineTexture != nil) == lineTextures.contains(theme))
            #expect((art.scanlineOverlay != nil) == scanlineOverlays.contains(theme))
            #expect((art.titleShadow != nil) == titleShadows.contains(theme))
        }
    }

    @Test func glowPoolsStayStaticExceptKaraoke() {
        // The pulse fields default inert (no TimelineView on the static
        // path); only Karaoke Supernova's roomPulse spotlights breathe.
        let pool = ThemeGlowPool(color: .white, centerX: 0.5, centerY: 0.5, radiusFraction: 0.5)
        #expect(pool.pulsePeriod == nil)
        for theme in ThemeID.allCases where theme != .karaokeSupernova {
            for pool in ThemeArtDirectionCatalog.artDirection(for: theme).glowPools {
                #expect(pool.pulsePeriod == nil)
            }
        }
        // Karaoke: stage bloom static, the three room spotlights at 5s/.6.
        let karaoke = ThemeArtDirectionCatalog.artDirection(for: .karaokeSupernova).glowPools
        #expect(karaoke.count == 4)
        #expect(karaoke.first?.pulsePeriod == nil)
        for pool in karaoke.dropFirst() {
            #expect(pool.pulsePeriod == 5)
            #expect(pool.pulseMinOpacity == 0.6)
        }
    }

    @Test func eventHorizonAtmosphereKeepsPreLaserDefaults() {
        // The Layer extensions (non-square tiles, laser bars, halftone
        // hardness) must not touch the device-verdict-approved Event Horizon
        // rendering: every layer stays a square-tiled soft round speck.
        let spec = ThemeArtDirectionCatalog.artDirection(for: .eventHorizon).atmosphereMotion
        for layer in spec?.layers ?? [] {
            #expect(layer.tileHeight == nil)
            #expect(layer.barHeight == nil)
            #expect(layer.blurScale == 1.0)
        }
    }

    @Test func lineFieldSpecCarriesRenderableGeometry() {
        // Representative Phase 3 payloads — the renderer requires positive
        // spacing and draws nothing otherwise, so pin the shapes here.
        let dualGrid = ThemeLineFieldSpec(layers: [
            .init(angleDegrees: 90, hue: Color(hex: 0x00F0FF), alpha: 0.04, spacing: 24),
            .init(angleDegrees: 0, hue: Color(hex: 0xFF69B4), alpha: 0.04, spacing: 24),
        ], fieldOpacity: 0.35)
        let sprayStreaks = ThemeLineFieldSpec(layers: [
            .init(angleDegrees: 135, hue: Color(hex: 0xFF006E), alpha: 0.10,
                  spacing: 40, lineWidth: 2.5, segmentLength: 12),
        ], fieldOpacity: 0.45)

        for spec in [dualGrid, sprayStreaks] {
            #expect((0...1).contains(spec.fieldOpacity))
            for layer in spec.layers {
                #expect(layer.spacing > 0)
                #expect(layer.lineWidth > 0)
                #expect((0...1).contains(layer.alpha))
                if let segment = layer.segmentLength {
                    #expect(segment > 0)
                }
            }
        }
        // Continuous vs streak mode is the segmentLength distinction.
        #expect(dualGrid.layers.allSatisfy { $0.segmentLength == nil })
        #expect(sprayStreaks.layers.allSatisfy { $0.segmentLength != nil })
    }

    @Test func titleShadowSpecDefaultsAreInkAndStatic() {
        // blur defaults to 0 (ink layer — ignores the glow pref) and
        // glitchPeriod to nil (no jitter timeline).
        let layer = ThemeTitleShadowSpec.Layer(
            hue: Color(hex: 0xFFD600), alpha: 1.0, offsetX: 4, offsetY: 4)
        let spec = ThemeTitleShadowSpec(layers: [layer])
        #expect(layer.blur == 0)
        #expect(spec.glitchPeriod == nil)
    }

    @Test func atmosphereBarLayersStaySeamless() {
        // Laser-bar layers (Karaoke Supernova) keep the whole-tile drift
        // invariant on BOTH axes of a non-square tile.
        let laser = AtmosphereMotionSpec.Layer(
            tileSize: 120, driftX: -120, driftY: 180,
            hue: Color(hex: 0xFF00AA), speckAlpha: 0.35,
            speckRadius: 1, tileHeight: 180, barHeight: 80)
        let tileH = laser.tileHeight ?? laser.tileSize
        #expect(abs(laser.driftX).truncatingRemainder(dividingBy: laser.tileSize) == 0)
        #expect(abs(laser.driftY).truncatingRemainder(dividingBy: tileH) == 0)
        #expect((laser.barHeight ?? 0) > 0)
    }

    @Test func everyGalleryOrbStyleHasExactlyOneTheme() {
        // Batch 3 completes the port: each of the twelve gallery
        // compositions is the orb of exactly one theme (the per-theme
        // mapping is pinned in DesignThemeTests.orbStyleIsThemeData).
        let galleryStyles: [ThemeOrbStyle] = [
            .glitchSeed, .cauldronBrew, .holoNigiri, .prizeWheel, .candyMecha,
            .jukeboxGlow, .cactusBloom, .anglerLure, .discoBall, .sprayCap,
            .mirrorBall, .rocketBadge,
        ]
        let selected = ThemeID.allCases.map { ThemePalette(theme: $0, accent: .cyan).orbStyle }
        for style in galleryStyles {
            #expect(selected.filter { $0 == style }.count == 1)
        }
    }

    // MARK: Batch 3 pinned handoff values (Special Editions)

    @Test func graffitiGalaxySitsAtHandoffLevels() {
        let art = ThemeArtDirectionCatalog.artDirection(for: .graffitiGalaxy)
        // Four spray-streak layers (40px tiles, 12px fades) + two chat-band
        // layers (30px, continuous), alphas pre-multiplied by their CSS
        // layer opacities.
        #expect(art.lineTexture?.layers.count == 6)
        let streaks = art.lineTexture?.layers.filter { $0.segmentLength != nil } ?? []
        #expect(streaks.count == 4)
        #expect(streaks.allSatisfy { $0.spacing == 40 && $0.segmentLength == 12 })
        #expect(Set(streaks.map(\.angleDegrees)) == [135, 225, 45, 315])
        // Panel halo carries the design's chat frame (EH compression).
        #expect(art.panelHalo != nil)
        #expect(art.panelHalo?.glowRadius == 40)
        // Tag title: two ink offsets + one pink glow, no jitter.
        #expect(art.titleShadow?.layers.count == 3)
        #expect(art.titleShadow?.glitchPeriod == nil)
        #expect(art.titleShadow?.layers[0].offsetX == 3)
        #expect(art.titleShadow?.layers[1].offsetX == 6)
        #expect(art.titleShadow?.layers[2].blur == 40)
    }

    @Test func karaokeLaserSweepMatchesTheHandoff() {
        let spec = ThemeArtDirectionCatalog.artDirection(for: .karaokeSupernova).atmosphereMotion
        #expect(spec?.period == 18)
        #expect(spec?.fieldOpacity == 0.35)
        #expect(spec?.layers.count == 4)
        #expect(spec?.layers.map(\.tileSize) == [120, 160, 200, 140])
        #expect(spec?.layers.map(\.tileHeight) == [180, 220, 260, 200])
        #expect(spec?.layers.map(\.speckAlpha) == [0.35, 0.30, 0.25, 0.30])
        // Every layer is a laser bar panning exactly one tile per loop on
        // BOTH axes — the seamless invariant on non-square tiles.
        for layer in spec?.layers ?? [] {
            #expect(layer.barHeight == 80)
            let tileH = layer.tileHeight ?? layer.tileSize
            #expect(abs(layer.driftX) == layer.tileSize)
            #expect(abs(layer.driftY) == tileH)
        }
        // The gallery's hottest declared glow rides the palette.
        #expect(ThemePalette(theme: .karaokeSupernova, accent: .cyan).glowScale == 1.35)
    }

    @Test func onlyPortedThemesOverrideArtDirection() {
        // Every un-ported theme resolves to the identity treatment — update
        // this list deliberately when a new handoff is ported (batch 1 added
        // the three new NAC themes + the three recolor drama retrofits).
        let ported: Set<ThemeID> = [
            .eventHorizon,
            .glitchGarden, .witchsBrew, .holoSushi,
            .cerealBox, .bubblegumMecha, .retroSciFi,
            .lunarDiner, .cyberCactus, .deepSeaDiner, .discoInferno,
            .graffitiGalaxy, .karaokeSupernova,
        ]
        for theme in ThemeID.allCases {
            let art = ThemeArtDirectionCatalog.artDirection(for: theme)
            #expect((art != .standard) == ported.contains(theme))
        }
    }

    @Test func eventHorizonCarriesTheHandoffAtmosphere() {
        let art = ThemeArtDirectionCatalog.artDirection(for: .eventHorizon)
        #expect(!art.glowPools.isEmpty)
        // Four speck hues: accretion violet, Hawking cyan, supernova gold,
        // singularity magenta (theme-event-horizon.html `.page-bg`).
        #expect(art.starfield?.colors.count == 4)
        #expect(art.panelHalo != nil)
    }

    @Test func eventHorizonIntensitySitsAtHandoffLevels() {
        // Task 3 pinned the override AT the handoff's values — a regression
        // that quietly re-tames them should fail here, not on device.
        // Device-verdict correction: 3 pools, not 5 — the card/bubble washes
        // were wrongly promoted to screen-scale blooms (bright teal swamp).
        let art = ThemeArtDirectionCatalog.artDirection(for: .eventHorizon)
        #expect(art.glowPools.count == 3)
        #expect(art.panelHalo?.glowRadius == 40)
        #expect(art.titleGlow != nil)
        #expect(art.starfield?.count == 104)
        // .spin-ring — the lensing starburst: gold 2°/2° at .03, 30s turn.
        #expect(art.radialSpokes != nil)
        #expect(art.radialSpokes?.spokeAlpha == 0.03)
        #expect(art.radialSpokes?.segmentDegrees == 2)
        #expect(art.radialSpokes?.period == 30)
    }

    @Test func radialSpokesDefaultToNil() {
        // The spoke field must be inert for every theme without a spec.
        #expect(ThemeArtDirection.standard.radialSpokes == nil)
        for theme in ThemeID.allCases where theme != .eventHorizon {
            #expect(ThemeArtDirectionCatalog.artDirection(for: theme).radialSpokes == nil)
        }
    }

    @Test func starfieldThemesCurateTheirSpeckColors() {
        // `.starfield` has no theme-neutral look — any palette selecting it
        // must ship art-direction speck hues (the accent fallback in
        // ThemeTextureView is a fail-soft, not a design).
        for theme in ThemeID.allCases {
            let palette = ThemePalette(theme: theme, accent: .cyan)
            if palette.texture == .starfield {
                let colors = ThemeArtDirectionCatalog.artDirection(for: theme).starfield?.colors
                #expect(colors?.isEmpty == false)
            }
        }
    }

    @Test func glowPoolGeometryIsRenderable() {
        for art in ThemeArtDirectionCatalog.overrides.values {
            for pool in art.glowPools {
                #expect(pool.radiusFraction > 0)
            }
            if let starfield = art.starfield {
                #expect(starfield.count > 0)
                #expect(starfield.driftScale >= 0)
            }
        }
    }

    // MARK: Atmosphere motion (Lane E Task 1)

    @Test func atmosphereMotionIsDeliberatePerTheme() {
        // The engine stays inert for every theme without a spec. Batch 1
        // added the static (zero-drift) speck/halftone fields.
        #expect(ThemeArtDirection.standard.atmosphereMotion == nil)
        let fields: Set<ThemeID> = [
            .eventHorizon, .witchsBrew, .cerealBox, .bubblegumMecha, .retroSciFi,
            .lunarDiner, .deepSeaDiner, .discoInferno, .karaokeSupernova,
        ]
        for theme in ThemeID.allCases {
            let art = ThemeArtDirectionCatalog.artDirection(for: theme)
            #expect((art.atmosphereMotion != nil) == fields.contains(theme))
        }
    }

    @Test func staticAtmosphereFieldsNeverDrift() {
        // Batch 1's speck fields are STATIC by design (the CSS never pans
        // them) — zero drift on every layer, so Reduce Motion and the
        // animated path render identically. Only Event Horizon drifts today.
        for theme in [ThemeID.witchsBrew, .cerealBox, .bubblegumMecha, .retroSciFi,
                      .lunarDiner, .deepSeaDiner, .discoInferno] {
            let spec = ThemeArtDirectionCatalog.artDirection(for: theme).atmosphereMotion
            #expect(spec != nil)
            for layer in spec?.layers ?? [] {
                #expect(layer.driftX == 0)
                #expect(layer.driftY == 0)
                #expect(layer.speckAlpha > 0)
                #expect(layer.speckRadius > 0)
            }
            #expect((spec?.period ?? 0) > 0)
            #expect((0...1).contains(spec?.fieldOpacity ?? -1))
        }
    }

    // MARK: Batch 1 pinned handoff values

    @Test func glitchGardenSitsAtHandoffLevels() {
        let art = ThemeArtDirectionCatalog.artDirection(for: .glitchGarden)
        #expect(art.glowPools.count == 2)
        // Scanlines: black .35 rows, 2px on 4px pitch, .25 page layer.
        #expect(art.scanlineOverlay?.layers.count == 1)
        #expect(art.scanlineOverlay?.layers.first?.spacing == 4)
        #expect(art.scanlineOverlay?.layers.first?.lineWidth == 2)
        #expect(art.scanlineOverlay?.fieldOpacity == 0.25)
        // Chromatic title: ±2px ink pair + 24px glow, 3s jitter.
        #expect(art.titleShadow?.layers.count == 3)
        #expect(art.titleShadow?.layers[0].offsetX == 2)
        #expect(art.titleShadow?.layers[1].offsetX == -2)
        #expect(art.titleShadow?.layers[2].blur == 24)
        #expect(art.titleShadow?.glitchPeriod == 3)
        // The design's own grid is palette data: 40px green lines.
        let palette = ThemePalette(theme: .glitchGarden, accent: .cyan)
        #expect(palette.gridCell == 40)
        #expect(palette.gridStyle == .lines)
    }

    @Test func witchsBrewSitsAtHandoffLevels() {
        let art = ThemeArtDirectionCatalog.artDirection(for: .witchsBrew)
        #expect(art.glowPools.count == 2)
        // Three static speck tiles at the handoff's 120/180/220.
        #expect(art.atmosphereMotion?.layers.map(\.tileSize) == [120, 180, 220])
        #expect(art.atmosphereMotion?.fieldOpacity == 0.25)
        #expect(art.titleGlow != nil)
    }

    @Test func holoSushiSitsAtHandoffLevels() {
        let art = ThemeArtDirectionCatalog.artDirection(for: .holoSushi)
        #expect(art.glowPools.count == 2)
        // The dual-tone holo grid: verticals × horizontals, 24px, ×.35.
        #expect(art.lineTexture?.layers.map(\.angleDegrees) == [90, 0])
        #expect(art.lineTexture?.layers.allSatisfy { $0.spacing == 24 && $0.segmentLength == nil } == true)
        #expect(art.lineTexture?.fieldOpacity == 0.35)
        #expect(art.titleGlow != nil)
    }

    @Test func cyberCactusCrosshatchSitsAtHandoffLevels() {
        let art = ThemeArtDirectionCatalog.artDirection(for: .cyberCactus)
        #expect(art.lineTexture?.layers.map(\.angleDegrees) == [45, -45])
        #expect(art.lineTexture?.layers.allSatisfy { $0.spacing == 11 && $0.alpha == 0.03 } == true)
        #expect(art.lineTexture?.fieldOpacity == 0.25)
    }

    @Test func discoInfernoSitsAtHandoffLevels() {
        let art = ThemeArtDirectionCatalog.artDirection(for: .discoInferno)
        // The loudest sparkle field in the gallery: gold .45 / silver .35.
        #expect(art.atmosphereMotion?.layers.map(\.speckAlpha) == [0.45, 0.35])
        #expect(art.atmosphereMotion?.layers.map(\.tileSize) == [24, 12])
        #expect(art.atmosphereMotion?.fieldOpacity == 0.35)
        #expect(art.scanlineOverlay != nil)
        // The gold dot grid is palette data at the handoff's pitch.
        let palette = ThemePalette(theme: .discoInferno, accent: .cyan)
        #expect(palette.gridStyle == .dots)
        #expect(palette.gridCell == 10)
        #expect(palette.glowScale == 1.2)
    }

    @Test func dinerStarlightLatticesMatchTheHandoff() {
        // Lunar and Deep Sea share the white 60/120 marine-snow lattice.
        for theme in [ThemeID.lunarDiner, .deepSeaDiner] {
            let spec = ThemeArtDirectionCatalog.artDirection(for: theme).atmosphereMotion
            #expect(spec?.layers.map(\.tileSize) == [60, 120])
            #expect(spec?.layers.map(\.speckAlpha) == [0.15, 0.08])
            #expect(spec?.fieldOpacity == 0.3)
        }
    }

    @Test func retroSciFiHalftoneIsCrispPrint() {
        // Two full-strength offset dot lattices on a .18 layer; the blur is
        // nearly off (comic dots, not starlight — deliberate rule-1 inverse).
        let spec = ThemeArtDirectionCatalog.artDirection(for: .retroSciFi).atmosphereMotion
        #expect(spec?.layers.count == 2)
        #expect(spec?.layers.allSatisfy { $0.tileSize == 12 && $0.speckAlpha == 1.0 } == true)
        #expect(spec?.layers.allSatisfy { $0.blurScale == 0.25 } == true)
        #expect(spec?.fieldOpacity == 0.18)
        // Half-tile lattice offset via anchors.
        #expect(spec?.layers[0].anchorX == 0.5)
        #expect(spec?.layers[1].anchorX == 0.0)
    }

    @Test func eventHorizonAtmosphereMatchesTheHandoffDrift() {
        let spec = ThemeArtDirectionCatalog.artDirection(for: .eventHorizon).atmosphereMotion
        #expect(spec != nil)
        // Four layers, tile sizes verbatim from `.page-bg` background-size.
        #expect(spec?.layers.map(\.tileSize) == [90, 120, 150, 110])
        #expect((spec?.period ?? 0) > 0)
        #expect((0...1).contains(spec?.fieldOpacity ?? -1))
        // Seamless loop: each layer pans a whole tile multiple per period
        // (the handoff pans exactly one tile), and every speck is drawable.
        for layer in spec?.layers ?? [] {
            #expect(abs(layer.driftX).truncatingRemainder(dividingBy: layer.tileSize) == 0)
            #expect(abs(layer.driftY).truncatingRemainder(dividingBy: layer.tileSize) == 0)
            #expect(layer.speckAlpha > 0)
            #expect(layer.speckRadius > 0)
            #expect((0...1).contains(layer.anchorX))
            #expect((0...1).contains(layer.anchorY))
        }
    }

    @Test func atmospherePresetsDifferOnTheDocumentedAxes() {
        let faithful = ThemeArtDirectionCatalog.eventHorizonAtmosphere(preset: .faithful)
        let punchy = ThemeArtDirectionCatalog.eventHorizonAtmosphere(preset: .punchy)
        let subtle = ThemeArtDirectionCatalog.eventHorizonAtmosphere(preset: .subtle)

        // A faithful — the handoff verbatim.
        #expect(faithful.period == 24)
        #expect(faithful.fieldOpacity == 0.45)
        #expect(faithful.layers.map(\.speckAlpha) == [0.12, 0.10, 0.08, 0.10])
        // B punchy — fieldOpacity 0.65, period 18s, speck alphas ×1.5.
        #expect(punchy.period == 18)
        #expect(punchy.fieldOpacity == 0.65)
        #expect(punchy.layers.map(\.speckAlpha) == faithful.layers.map { $0.speckAlpha * 1.5 })
        // C subtle — fieldOpacity 0.35, period 30s, alphas as faithful.
        #expect(subtle.period == 30)
        #expect(subtle.fieldOpacity == 0.35)
        #expect(subtle.layers.map(\.speckAlpha) == faithful.layers.map(\.speckAlpha))
    }

    @Test func eventHorizonUsesHandoffSlotNames() {
        #expect(AppearanceAccent.cyan.displayLabel(for: .eventHorizon) == "Accretion Violet")
        #expect(AppearanceAccent.amber.displayLabel(for: .eventHorizon) == "Hawking Cyan")
        #expect(AppearanceAccent.violet.displayLabel(for: .eventHorizon) == "Supernova Gold")
    }

    @Test func eventHorizonSelectsTheStarfieldTexture() {
        #expect(ThemePalette(theme: .eventHorizon, accent: .cyan).texture == .starfield)
    }
}
