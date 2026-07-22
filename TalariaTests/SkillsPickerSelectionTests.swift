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
