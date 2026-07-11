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

    @Test func lineFieldsAndTitleShadowsDefaultToNil() {
        // Every shipped theme — Event Horizon included — carries none of the
        // Phase 2 fields until a Phase 3 port sets them deliberately.
        for theme in ThemeID.allCases {
            let art = ThemeArtDirectionCatalog.artDirection(for: theme)
            #expect(art.lineTexture == nil)
            #expect(art.scanlineOverlay == nil)
            #expect(art.titleShadow == nil)
        }
    }

    @Test func glowPoolsStayStaticByDefault() {
        // The pulse fields must default inert so existing pools render
        // byte-identically (no TimelineView on the static path).
        let pool = ThemeGlowPool(color: .white, centerX: 0.5, centerY: 0.5, radiusFraction: 0.5)
        #expect(pool.pulsePeriod == nil)
        for art in ThemeArtDirectionCatalog.overrides.values {
            for pool in art.glowPools {
                #expect(pool.pulsePeriod == nil)
            }
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

    @Test func galleryOrbStylesAreDataOnlyUntilPhase3() {
        // Phase 2 lands the twelve compositions unwired: every shipped
        // palette still selects a pre-existing orb style, so no theme's
        // rendering changes. Phase 3 flips these deliberately.
        let prePhase3: Set<ThemeOrbStyle> = [
            .arcReactor, .forgeSun, .crtCrosshair, .paperReel, .singularity,
        ]
        for theme in ThemeID.allCases {
            let palette = ThemePalette(theme: theme, accent: .cyan)
            #expect(prePhase3.contains(palette.orbStyle))
        }
    }

    @Test func onlyEventHorizonOverridesArtDirection() {
        // Every other shipped theme resolves to the identity treatment —
        // update this list deliberately when a new handoff is ported.
        for theme in ThemeID.allCases {
            let art = ThemeArtDirectionCatalog.artDirection(for: theme)
            if theme == .eventHorizon {
                #expect(art != .standard)
            } else {
                #expect(art == .standard)
            }
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

    @Test func atmosphereMotionDefaultsToNil() {
        // The motion engine must be inert for every theme without a spec —
        // `.standard` (and therefore all un-listed themes) carries none.
        #expect(ThemeArtDirection.standard.atmosphereMotion == nil)
        for theme in ThemeID.allCases where theme != .eventHorizon {
            #expect(ThemeArtDirectionCatalog.artDirection(for: theme).atmosphereMotion == nil)
        }
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
