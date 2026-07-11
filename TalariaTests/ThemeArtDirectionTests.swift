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
        // these sets deliberately per batch (batch 4: Midnight Aquarium's
        // caustics, Haunted VHS's CRT rows + chromatic title).
        let lineTextures: Set<ThemeID> = [
            .holoSushi, .cyberCactus, .graffitiGalaxy, .midnightAquarium,
        ]
        let scanlineOverlays: Set<ThemeID> = [
            .glitchGarden, .bubblegumMecha, .retroSciFi, .discoInferno, .hauntedVHS,
        ]
        let titleShadows: Set<ThemeID> = [
            .glitchGarden, .retroSciFi, .graffitiGalaxy, .hauntedVHS,
        ]
        for theme in ThemeID.allCases {
            let art = ThemeArtDirectionCatalog.artDirection(for: theme)
            #expect((art.lineTexture != nil) == lineTextures.contains(theme))
            #expect((art.scanlineOverlay != nil) == scanlineOverlays.contains(theme))
            #expect((art.titleShadow != nil) == titleShadows.contains(theme))
        }
    }

    @Test func glowPoolPulseIsDeliberatePerTheme() {
        // The pulse fields default inert (no TimelineView on the static
        // path); only Karaoke Supernova's roomPulse spotlights and Molten
        // Forge's heatShimmer pool breathe — update deliberately per batch.
        let pool = ThemeGlowPool(color: .white, centerX: 0.5, centerY: 0.5, radiusFraction: 0.5)
        #expect(pool.pulsePeriod == nil)
        let pulsing: Set<ThemeID> = [.karaokeSupernova, .moltenForge]
        for theme in ThemeID.allCases where !pulsing.contains(theme) {
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
        // Molten Forge: lava bloom static, the heatShimmer pool at 4s
        // breathing the CSS's exact .10–.17 range (.17 × .59 ≈ .10).
        let molten = ThemeArtDirectionCatalog.artDirection(for: .moltenForge).glowPools
        #expect(molten.count == 2)
        #expect(molten.first?.pulsePeriod == nil)
        #expect(molten.last?.pulsePeriod == 4)
        #expect(molten.last?.pulseMinOpacity == 0.59)
        #expect(molten.last?.centerY == 1.0)
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

    @Test func galleryOrbStylesAreNeverShared() {
        // Each gallery composition belongs to at most ONE theme (the
        // per-theme mapping is pinned in DesignThemeTests.orbStyleIsThemeData).
        // Batch 4 adds the three Claude-Design compositions as owned.
        // `.anglerLure` STAYS an intentional orphan (Owen decision, batch-4
        // dispatch) — its theme (Deep Sea Diner) was cut on device verdict
        // 2026-07-11 (too close to Deep Field); the composition stays as
        // reusable data.
        let galleryStyles: [ThemeOrbStyle] = [
            .glitchSeed, .cauldronBrew, .holoNigiri, .prizeWheel, .candyMecha,
            .jukeboxGlow, .cactusBloom, .anglerLure, .discoBall, .sprayCap,
            .mirrorBall, .rocketBadge, .moonJelly, .crucible, .phosphor,
        ]
        let orphans: Set<ThemeOrbStyle> = [.anglerLure]
        let selected = ThemeID.allCases.map { ThemePalette(theme: $0, accent: .cyan).orbStyle }
        for style in galleryStyles {
            let count = selected.filter { $0 == style }.count
            #expect(count == (orphans.contains(style) ? 0 : 1))
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

    // MARK: Batch 4 primitives (Claude-Design SEs) — inert defaults

    @Test func batchFourPrimitivesDefaultInert() {
        // Every new knob must be off unless a spec sets it, so all prior
        // themes render byte-identically through the new machinery.
        let lineLayer = ThemeLineFieldSpec.Layer(
            angleDegrees: 0, hue: Color(hex: 0xFFFFFF), alpha: 0.1, spacing: 10)
        #expect(lineLayer.driftX == 0)
        #expect(lineLayer.driftY == 0)
        #expect(ThemeLineFieldSpec(layers: [lineLayer], fieldOpacity: 1).driftPeriod == nil)

        let ribbon = ThemeCornerRibbonSpec(text: "X", textColor: .white, background: .black)
        #expect(ribbon.blinkPeriod == nil)
        #expect(ribbon.blinkMinOpacity == 0.15)

        let motion = AtmosphereMotionSpec(layers: [], period: 1, fieldOpacity: 1)
        #expect(motion.stepCount == nil)

        #expect(ThemeArtDirection.standard.sweepBar == nil)
        for theme in ThemeID.allCases where theme != .hauntedVHS {
            #expect(ThemeArtDirectionCatalog.artDirection(for: theme).sweepBar == nil)
        }
        // Pre-batch-4 adopters of the extended specs stay static: Graffiti
        // Galaxy's TAG never blinks, no earlier line field drifts, no
        // earlier atmosphere quantizes its pan.
        #expect(ThemeArtDirectionCatalog.artDirection(for: .graffitiGalaxy)
            .cornerRibbon?.blinkPeriod == nil)
        for theme in ThemeID.allCases where theme != .midnightAquarium {
            #expect(ThemeArtDirectionCatalog.artDirection(for: theme)
                .lineTexture?.driftPeriod == nil)
        }
        for theme in ThemeID.allCases where theme != .hauntedVHS {
            #expect(ThemeArtDirectionCatalog.artDirection(for: theme)
                .atmosphereMotion?.stepCount == nil)
        }
    }

    // MARK: Batch 4 pinned handoff values (Claude-Design Special Editions)

    @Test func midnightAquariumSitsAtHandoffLevels() {
        let art = ThemeArtDirectionCatalog.artDirection(for: .midnightAquarium)
        // bubbleRise: three non-square columns (130×520 / 170×640 / 210×760),
        // one tile height UP per 14s loop, alphas .4/.35/.3 on a .4 field.
        let bubbles = art.atmosphereMotion
        #expect(bubbles?.period == 14)
        #expect(bubbles?.fieldOpacity == 0.4)
        #expect(bubbles?.layers.map(\.tileSize) == [130, 170, 210])
        #expect(bubbles?.layers.map(\.tileHeight) == [520, 640, 760])
        #expect(bubbles?.layers.map(\.speckAlpha) == [0.4, 0.35, 0.3])
        for layer in bubbles?.layers ?? [] {
            // The seamless axis: exactly one tile height up per loop. The
            // lateral wander (20/−30/10) is verbatim CSS and snaps at the
            // loop point in the reference too.
            #expect(layer.driftY == -(layer.tileHeight ?? layer.tileSize))
            #expect(layer.barHeight == nil)
        }
        // causticDrift: ±105° lattices, 4px lines on 38/50 pitch, drifting
        // (240,120)/(−240,−80) per 16s loop on a .6 field.
        let caustics = art.lineTexture
        #expect(caustics?.driftPeriod == 16)
        #expect(caustics?.fieldOpacity == 0.6)
        #expect(caustics?.layers.map(\.angleDegrees) == [105, -105])
        #expect(caustics?.layers.map(\.spacing) == [38, 50])
        #expect(caustics?.layers.allSatisfy { $0.lineWidth == 4 && $0.segmentLength == nil } == true)
        #expect(caustics?.layers.map(\.driftX) == [240, -240])
        #expect(caustics?.layers.map(\.driftY) == [120, -80])
        #expect(art.panelHalo?.glowRadius == 40)
        #expect(art.titleGlow != nil)
    }

    @Test func moltenForgeSitsAtHandoffLevels() {
        let art = ThemeArtDirectionCatalog.artDirection(for: .moltenForge)
        // emberRise: three non-square columns (120×420 / 160×560 / 200×680),
        // one tile height UP per 10s loop, alphas .5/.45/.4 on a .45 field —
        // ember red #FF3B2D rides the third layer (the fourth hue).
        let embers = art.atmosphereMotion
        #expect(embers?.period == 10)
        #expect(embers?.fieldOpacity == 0.45)
        #expect(embers?.layers.map(\.tileSize) == [120, 160, 200])
        #expect(embers?.layers.map(\.tileHeight) == [420, 560, 680])
        #expect(embers?.layers.map(\.speckAlpha) == [0.5, 0.45, 0.4])
        for layer in embers?.layers ?? [] {
            #expect(layer.driftY == -(layer.tileHeight ?? layer.tileSize))
        }
        #expect(art.panelHalo?.glowRadius == 40)
        #expect(art.titleGlow != nil)
        // heatShimmer pool pins live in glowPoolPulseIsDeliberatePerTheme.
        // The Solar Forge lineage stays untouched: no ember tint reuse.
        #expect(art.emberTint == nil)
    }

    @Test func hauntedVHSSitsAtHandoffLevels() {
        let art = ThemeArtDirectionCatalog.artDirection(for: .hauntedVHS)
        // staticDrift: three square noise tiles (70/110/90), four discrete
        // jumps per 0.9s loop (steps(4)), alphas .16/.14/.12 on a .35 field.
        let statics = art.atmosphereMotion
        #expect(statics?.period == 0.9)
        #expect(statics?.stepCount == 4)
        #expect(statics?.fieldOpacity == 0.35)
        #expect(statics?.layers.map(\.tileSize) == [70, 110, 90])
        #expect(statics?.layers.map(\.speckAlpha) == [0.16, 0.14, 0.12])
        for layer in statics?.layers ?? [] {
            // Whole-tile jumps keep the wrap seamless on both axes.
            #expect(abs(layer.driftX) == layer.tileSize)
            #expect(abs(layer.driftY) == layer.tileSize)
        }
        // CRT rows, verbatim: 1px black .28 on 3px pitch, .5 layer.
        #expect(art.scanlineOverlay?.layers.count == 1)
        #expect(art.scanlineOverlay?.layers.first?.spacing == 3)
        #expect(art.scanlineOverlay?.layers.first?.lineWidth == 1)
        #expect(art.scanlineOverlay?.layers.first?.alpha == 0.28)
        #expect(art.scanlineOverlay?.fieldOpacity == 0.5)
        // trackingBar: 46px band sweeping −18% → 118% every 6s.
        #expect(art.sweepBar?.height == 46)
        #expect(art.sweepBar?.period == 6)
        #expect(art.sweepBar?.travelStart == -0.18)
        #expect(art.sweepBar?.travelEnd == 1.18)
        #expect(art.sweepBar?.shoulderAlpha == 0.07)
        #expect(art.sweepBar?.centerAlpha == 0.12)
        // vhsJitter: ±3px chromatic inks on the 5s glitch cadence.
        #expect(art.titleShadow?.layers.count == 2)
        #expect(art.titleShadow?.layers[0].offsetX == 3)
        #expect(art.titleShadow?.layers[1].offsetX == -3)
        #expect(art.titleShadow?.glitchPeriod == 5)
        #expect(art.titleGlow != nil)
        // recBlink: the REC ribbon blinks at 1.1s, dimming to .15.
        #expect(art.cornerRibbon?.text == "● REC")
        #expect(art.cornerRibbon?.blinkPeriod == 1.1)
        #expect(art.cornerRibbon?.blinkMinOpacity == 0.15)
        #expect(art.panelHalo?.glowRadius == 40)
    }

    @Test func moltenForgeVariantsShareNoHueWithSolarForge() {
        // Owen's differentiation mandate (batch-4 dispatch): Molten Forge's
        // accent variants must use hues Solar Forge's variants do NOT.
        // Compare the full accent families across every slot — no color may
        // repeat (hue angles: Molten 21°/46°/202° vs Solar 39°/184°/259°).
        func family(_ theme: ThemeID) -> [Color] {
            AccentSlot.allCases.flatMap { slot -> [Color] in
                let p = ThemePalette(theme: theme, accent: slot)
                return [p.base, p.bright, p.deep, p.coreHighlight, p.coreShadow]
            }
        }
        let molten = family(.moltenForge)
        let solar = Set(family(.solarForge))
        #expect(Set(molten).count == molten.count)
        for color in molten {
            #expect(!solar.contains(color))
        }
    }

    @Test func onlyPortedThemesOverrideArtDirection() {
        // Every un-ported theme resolves to the identity treatment — update
        // this list deliberately when a new handoff is ported (batch 1 added
        // the three new NAC themes + the three recolor drama retrofits).
        let ported: Set<ThemeID> = [
            .eventHorizon,
            .glitchGarden, .witchsBrew, .holoSushi,
            .cerealBox, .bubblegumMecha, .retroSciFi,
            .lunarDiner, .cyberCactus, .discoInferno,
            .graffitiGalaxy, .karaokeSupernova,
            .midnightAquarium, .moltenForge, .hauntedVHS,
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

    @Test func cornerRibbonAndTopStripDefaultToNil() {
        // Both correction-round primitives must be inert for every theme
        // that doesn't set them — ribbons: Graffiti Galaxy + Haunted VHS
        // (batch 4); top strip: Graffiti Galaxy only.
        #expect(ThemeArtDirection.standard.cornerRibbon == nil)
        #expect(ThemeArtDirection.standard.panelTopStrip == nil)
        let ribbons: Set<ThemeID> = [.graffitiGalaxy, .hauntedVHS]
        for theme in ThemeID.allCases {
            let art = ThemeArtDirectionCatalog.artDirection(for: theme)
            #expect((art.cornerRibbon != nil) == ribbons.contains(theme))
            #expect((art.panelTopStrip != nil) == (theme == .graffitiGalaxy))
        }
    }

    @Test func graffitiGalaxyCarriesRibbonAndTopStrip() {
        // chat-screen::after — 'TAG', citron on pink; card::before — 4px
        // 90° four-hue strip at .7. Verbatim pins.
        let art = ThemeArtDirectionCatalog.artDirection(for: .graffitiGalaxy)
        #expect(art.cornerRibbon?.text == "TAG")
        #expect(art.panelTopStrip?.colors.count == 4)
        #expect(art.panelTopStrip?.height == 4)
        #expect(art.panelTopStrip?.opacity == 0.7)
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
            .lunarDiner, .discoInferno, .karaokeSupernova,
            .midnightAquarium, .moltenForge, .hauntedVHS,
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
                      .lunarDiner, .discoInferno] {
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
        // Lunar Diner's white 60/120 marine-snow lattice (Deep Sea Diner
        // shared it before being cut — too close to Deep Field, 2026-07-11).
        for theme in [ThemeID.lunarDiner] {
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
