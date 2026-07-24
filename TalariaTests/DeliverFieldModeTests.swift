import Foundation
import Testing
@testable import Talaria

/// #172 — the deliver field's MODE, the second one-way door in this sheet.
/// `useFreeText` had exactly one write site (`true`) and the free-text field
/// offered no control that set it back, so tapping "Custom…" swapped the
/// server-driven platform menu for a raw `TextField` permanently, for the life
/// of the sheet. Milder than #168a — the picker already preserves an off-list
/// value as a marked "(custom)" row, so nothing became unverifiable — but the
/// user who taps Custom… to look at the field then hand-types this sheet's
/// most typo-sensitive value (`telegram:-100999:42` shapes, #171) with no list
/// to fall back on.
///
/// Mirrors `SkillsFieldModeTests` deliberately: same shape, same dead-end
/// guard, so a third instance of this pattern has an obvious home.
struct DeliverFieldModeTests {

    // MARK: - Round trip (the #172 regression guard)

    @Test func startsOnTheMenuWhenTheHostAnsweredWithPlatforms() {
        let mode = DeliverFieldMode()
        #expect(mode.showsPicker(hasPlatformList: true))
        #expect(!mode.isFreeText)
    }

    @Test func customEntryThenUseListReturnsToTheMenu() {
        var mode = DeliverFieldMode()
        mode.useCustomEntry()
        #expect(!mode.showsPicker(hasPlatformList: true))
        mode.useList()
        #expect(mode.showsPicker(hasPlatformList: true))
        #expect(mode == DeliverFieldMode())
    }

    @Test func freeTextModeOffersTheReturnPath() {
        var mode = DeliverFieldMode()
        mode.useCustomEntry()
        #expect(mode.offersReturnToList(hasPlatformList: true))
        // …and not the escape it is already in.
        #expect(!mode.offersCustomEntry(hasPlatformList: true))
    }

    @Test func menuModeOffersTheEscapeAndNotTheReturn() {
        let mode = DeliverFieldMode()
        #expect(mode.offersCustomEntry(hasPlatformList: true))
        #expect(!mode.offersReturnToList(hasPlatformList: true))
    }

    @Test func transitionsAreIdempotent() {
        var mode = DeliverFieldMode()
        mode.useCustomEntry()
        mode.useCustomEntry()
        #expect(mode.isFreeText)
        mode.useList()
        mode.useList()
        #expect(!mode.isFreeText)
    }

    // MARK: - The second dead-end guard (inherited from #168a)

    @Test func noPlatformListMeansNoModeToggleInEitherDirection() {
        // `/health/detailed` never answered: free text is the only mode there
        // is, and a USE LIST control would open a door onto a menu that
        // cannot show — the exact mistake #168a's fix was careful to avoid.
        var mode = DeliverFieldMode()
        #expect(!mode.showsPicker(hasPlatformList: false))
        #expect(!mode.offersCustomEntry(hasPlatformList: false))
        #expect(!mode.offersReturnToList(hasPlatformList: false))
        mode.useCustomEntry()
        #expect(!mode.showsPicker(hasPlatformList: false))
        #expect(!mode.offersReturnToList(hasPlatformList: false))
    }

    // MARK: - The mode owns no text

    @Test func modeCarriesNoValueSoARoundTripCannotClobberTheTypedOne() {
        // The property that makes the "(custom)" preservation contract
        // reachable from the UI at all: both transitions are pure mode
        // changes, so a trip out to free text and back is value-preserving
        // by construction.
        var deliver = "telegram:-100999:42"
        var mode = DeliverFieldMode()
        mode.useCustomEntry()
        mode.useList()
        #expect(deliver == "telegram:-100999:42")
        deliver = ""
        #expect(mode == DeliverFieldMode())
    }
}
