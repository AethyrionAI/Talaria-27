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

    @Test func eventHorizonUsesHandoffSlotNames() {
        #expect(AppearanceAccent.cyan.displayLabel(for: .eventHorizon) == "Accretion Violet")
        #expect(AppearanceAccent.amber.displayLabel(for: .eventHorizon) == "Hawking Cyan")
        #expect(AppearanceAccent.violet.displayLabel(for: .eventHorizon) == "Supernova Gold")
    }

    @Test func eventHorizonSelectsTheStarfieldTexture() {
        #expect(ThemePalette(theme: .eventHorizon, accent: .cyan).texture == .starfield)
    }
}
