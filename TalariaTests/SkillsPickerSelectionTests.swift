import Foundation
import Testing
@testable import Talaria

/// #156b D6 — D5's value-preservation contract: the picker parses and
/// re-emits the cron field's comma-separated string (the wire format the
/// PATCH surface expects — unchanged), and values the fetched skill list
/// doesn't know survive every edit they weren't deliberately removed by.
struct SkillsPickerSelectionTests {

    // MARK: - Seeding + round trip

    @Test func customValuesSurviveARoundTrip() {
        let selection = SkillsPickerSelection(commaSeparated: "known-skill, legacy-custom")
        #expect(selection.commaSeparatedValue == "known-skill, legacy-custom")
    }

    @Test func seedingPreservesOrder() {
        let selection = SkillsPickerSelection(commaSeparated: "zeta, alpha, mike")
        #expect(selection.selected == ["zeta", "alpha", "mike"])
    }

    @Test func seedingSplitsLikeParsedSkills() {
        // Comma or newline separated, whitespace trimmed, empties dropped —
        // the same grammar `CronJobDraft.parsedSkills` sends on the wire.
        let selection = SkillsPickerSelection(commaSeparated: " a ,\nb,, c\n")
        #expect(selection.selected == ["a", "b", "c"])
    }

    @Test func seedingDeduplicates() {
        let selection = SkillsPickerSelection(commaSeparated: "a, b, a")
        #expect(selection.selected == ["a", "b"])
    }

    @Test func emptySeedIsEmptySelection() {
        #expect(SkillsPickerSelection(commaSeparated: "").selected.isEmpty)
        #expect(SkillsPickerSelection(commaSeparated: "  ").commaSeparatedValue == "")
    }

    // MARK: - Toggling

    @Test func toggleOnAppendsAtEnd() {
        var selection = SkillsPickerSelection(commaSeparated: "legacy-custom")
        selection.toggle("fresh-skill")
        #expect(selection.commaSeparatedValue == "legacy-custom, fresh-skill")
    }

    @Test func toggleOffRemovesOnlyThatValue() {
        var selection = SkillsPickerSelection(commaSeparated: "a, custom-x, b")
        selection.toggle("a")
        #expect(selection.commaSeparatedValue == "custom-x, b")
    }

    @Test func editingAroundACustomValueNeverClobbersIt() {
        // The D5 contract end-to-end: seed with a hand-typed value, make an
        // unrelated edit, the custom value is still there.
        var selection = SkillsPickerSelection(commaSeparated: "hand-typed-thing, known-a")
        selection.toggle("known-b")
        selection.toggle("known-a")
        #expect(selection.commaSeparatedValue == "hand-typed-thing, known-b")
    }

    @Test func customValueIsRemovableDeliberately() {
        var selection = SkillsPickerSelection(commaSeparated: "hand-typed-thing")
        selection.toggle("hand-typed-thing")
        #expect(selection.commaSeparatedValue == "")
    }

    // MARK: - Custom detection

    @Test func customValuesAreTheOnesTheHostListLacks() {
        let selection = SkillsPickerSelection(commaSeparated: "known-a, legacy-x, known-b, hand-y")
        let custom = selection.customValues(knownNames: ["known-a", "known-b", "other-known"])
        #expect(custom == ["legacy-x", "hand-y"])
    }

    @Test func customMatchingIsCaseSensitive() {
        // Skill names are exact host-side identifiers — "PDF" is not "pdf".
        let selection = SkillsPickerSelection(commaSeparated: "PDF")
        #expect(selection.customValues(knownNames: ["pdf"]) == ["PDF"])
    }

    @Test func isSelectedReflectsSeededValues() {
        let selection = SkillsPickerSelection(commaSeparated: "a, b")
        #expect(selection.isSelected("a"))
        #expect(!selection.isSelected("c"))
    }
}

/// #168 D6 — the field's MODE, the half `SkillsPickerSelection` never covered.
/// EDIT AS TEXT shipped with exactly one write site and no way back, so the
/// picker's whole value-preservation contract was unreachable from the UI
/// while 1088 tests stayed green. These are the assertions that would have
/// caught it.
struct SkillsFieldModeTests {

    // MARK: - Round trip (the #168a regression guard)

    @Test func startsOnThePickerWhenTheHostListExists() {
        let mode = SkillsFieldMode()
        #expect(mode.showsPicker(hasPickerSkills: true))
        #expect(!mode.isFreeText)
    }

    @Test func editAsTextThenUsePickerReturnsToThePicker() {
        var mode = SkillsFieldMode()
        mode.editAsText()
        #expect(!mode.showsPicker(hasPickerSkills: true))
        mode.usePicker()
        #expect(mode.showsPicker(hasPickerSkills: true))
        #expect(mode == SkillsFieldMode())
    }

    @Test func freeTextModeOffersTheReturnPath() {
        var mode = SkillsFieldMode()
        mode.editAsText()
        #expect(mode.offersReturnToPicker(hasPickerSkills: true))
        // …and not the escape it is already in.
        #expect(!mode.offersEditAsText(hasPickerSkills: true))
    }

    @Test func pickerModeOffersTheEscapeAndNotTheReturn() {
        let mode = SkillsFieldMode()
        #expect(mode.offersEditAsText(hasPickerSkills: true))
        #expect(!mode.offersReturnToPicker(hasPickerSkills: true))
    }

    @Test func transitionsAreIdempotent() {
        var mode = SkillsFieldMode()
        mode.editAsText()
        mode.editAsText()
        #expect(mode.isFreeText)
        mode.usePicker()
        mode.usePicker()
        #expect(!mode.isFreeText)
    }

    // MARK: - The second dead-end guard (#168a)

    @Test func noHostListMeansNoModeToggleInEitherDirection() {
        // Free text is the only mode there is; a toggle would open a door
        // onto a picker that cannot show.
        var mode = SkillsFieldMode()
        #expect(!mode.showsPicker(hasPickerSkills: false))
        #expect(!mode.offersEditAsText(hasPickerSkills: false))
        #expect(!mode.offersReturnToPicker(hasPickerSkills: false))
        mode.editAsText()
        #expect(!mode.showsPicker(hasPickerSkills: false))
        #expect(!mode.offersReturnToPicker(hasPickerSkills: false))
    }

    // MARK: - Retry gate (#168b)

    @Test func retryIsOfferedOnlyWhenDegradedAndRefetchable() {
        #expect(SkillsFieldMode.offersRetry(hasPickerSkills: false, canRetry: true))
        // A picker is already up — nothing to retry for.
        #expect(!SkillsFieldMode.offersRetry(hasPickerSkills: true, canRetry: true))
        // No refetch path (bare container / preview): a RETRY that cannot
        // fetch is the same dead end as a picker that cannot open.
        #expect(!SkillsFieldMode.offersRetry(hasPickerSkills: false, canRetry: false))
        #expect(!SkillsFieldMode.offersRetry(hasPickerSkills: true, canRetry: false))
    }
}

/// #168 D6 — the assertion the #171 device pass could not reach, now that the
/// return path exists: a value the host list has never heard of, typed in free
/// text, survives the trip back to the picker and is reported as custom.
struct SkillsFieldRoundTripTests {

    /// Stands in for the sheet's `skillsText` binding: the mode owns no text,
    /// so a round trip must leave this byte-identical.
    private func roundTrip(_ text: String) -> (mode: SkillsFieldMode, text: String) {
        var mode = SkillsFieldMode()
        var skillsText = text
        mode.editAsText()
        // Free-text mode edits only the string; the mode never touches it.
        skillsText += ", hand-typed-thing"
        mode.usePicker()
        return (mode, skillsText)
    }

    @Test func aValueTypedAsTextSurvivesTheReturnToThePicker() {
        let (mode, text) = roundTrip("known-a")
        #expect(mode.showsPicker(hasPickerSkills: true))

        let selection = SkillsPickerSelection(commaSeparated: text)
        #expect(selection.selected == ["known-a", "hand-typed-thing"])
        #expect(selection.isSelected("hand-typed-thing"))
        #expect(
            selection.customValues(knownNames: ["known-a", "known-b"]) == ["hand-typed-thing"]
        )
    }

    @Test func theRoundTripPreservesTheSelectionSetExactly() {
        var mode = SkillsFieldMode()
        let text = "known-a, legacy-x, known-b"
        let before = SkillsPickerSelection(commaSeparated: text)
        mode.editAsText()
        mode.usePicker()
        let after = SkillsPickerSelection(commaSeparated: text)
        #expect(before == after)
        #expect(after.commaSeparatedValue == "known-a, legacy-x, known-b")
    }
}
