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
}
