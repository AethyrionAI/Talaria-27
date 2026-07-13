import Foundation
import Testing
@testable import Talaria

/// Invariants for the data-driven app-icon catalog (issue #25). These guard the
/// contract the picker relies on: exactly one primary, stable/unique ids and OS
/// names, a preview per entry, and lossless resolution from an OS icon name.
struct AppIconCatalogTests {

    @Test func exactlyOnePrimary() {
        let primaries = AppIconCatalog.all.filter(\.isPrimary)
        #expect(primaries.count == 1)
        #expect(AppIconCatalog.all.first == AppIconCatalog.primary)
        #expect(AppIconCatalog.primary.isPrimary)
        #expect(AppIconCatalog.primary.alternateIconName == nil)
    }

    @Test func idsAreUnique() {
        let ids = AppIconCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func alternateNamesAreUniqueAndNonEmpty() {
        let names = AppIconCatalog.all.compactMap(\.alternateIconName)
        #expect(Set(names).count == names.count)
        let hasEmptyName = names.contains(where: \.isEmpty)
        #expect(!hasEmptyName)
        // One name per non-primary entry.
        #expect(names.count == AppIconCatalog.all.count - 1)
    }

    @Test func everyOptionHasAPreview() {
        for option in AppIconCatalog.all {
            #expect(!option.previewImageName.isEmpty)
        }
    }

    @Test func resolveByOSNameRoundTrips() {
        for option in AppIconCatalog.all {
            #expect(AppIconCatalog.option(forAlternateIconName: option.alternateIconName).id == option.id)
        }
    }

    @Test func unknownOrNilNameFallsBackToPrimary() {
        #expect(AppIconCatalog.option(forAlternateIconName: nil).isPrimary)
        #expect(AppIconCatalog.option(forAlternateIconName: "NotARealIcon").isPrimary)
    }

    @Test func lookupByIDMatchesList() {
        for option in AppIconCatalog.all {
            #expect(AppIconCatalog.option(id: option.id) == option)
        }
        #expect(AppIconCatalog.option(id: "nope") == nil)
    }

    // MARK: Sections (Lane K + Lane L)

    @Test func sectionsMirrorTheGalleryTaxonomy() {
        #expect(AppIconCatalog.sections.map(\.title) ==
                ["Flagship", "Neon Arcade Collection", "Special Edition",
                 "Midnight Marquee", "Seasonal"])
    }

    @Test func sectionsFlattenToAllInDisplayOrder() {
        #expect(AppIconCatalog.sections.flatMap(\.options) == AppIconCatalog.all)
    }

    @Test func laneKBatchIsFullyWired() {
        // Default + 4 flagship + 10 Neon Arcade Collection + 4 Seasonal.
        #expect(AppIconCatalog.flagship.count == 5)
        #expect(AppIconCatalog.neonArcadeCollection.count == 10)
        #expect(AppIconCatalog.seasonal.count == 4)
        // Deep Sea Diner stays cut (icon<->theme parity).
        #expect(AppIconCatalog.option(id: "deepSeaDiner") == nil)
        #expect(AppIconCatalog.option(forAlternateIconName: "DeepSeaDiner").isPrimary)
    }

    @Test func laneLBatchIsFullyWired() {
        // The five reserved SE icons + the eight Midnight Marquee icons —
        // 31 alternates + the Default primary, 32 picker entries total.
        #expect(AppIconCatalog.specialEdition.count == 5)
        #expect(AppIconCatalog.midnightMarquee.count == 8)
        #expect(AppIconCatalog.all.count == 32)
        #expect(AppIconCatalog.all.compactMap(\.alternateIconName).count == 31)
        // Comic Book ships BOTH variants as separately selectable icons —
        // fully independent of the adaptive theme selection (Lane K
        // coupling rule).
        #expect(AppIconCatalog.option(id: "comicVillain")?.alternateIconName == "ComicVillain")
        #expect(AppIconCatalog.option(id: "comicFunnies")?.alternateIconName == "ComicFunnies")
    }

    /// Every alternate's picker thumbnail follows the shared asset convention
    /// (`IconPreview-<Name>` for OS name `<Name>`), so an OS-name/preview typo
    /// can't ship a working icon with a broken or mismatched thumbnail.
    @Test func previewNamesFollowTheAssetConvention() {
        for option in AppIconCatalog.all where !option.isPrimary {
            let name = option.alternateIconName ?? ""
            #expect(option.previewImageName == "IconPreview-\(name)")
        }
    }
}
