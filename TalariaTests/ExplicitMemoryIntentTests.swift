import Foundation
import Testing
@testable import Talaria

/// #422 bar 422-E — the deterministic explicit-note path. No model in the
/// loop: every trigger form below is a fixed-string match, and the captured
/// text is asserted VERBATIM against the source (ruling 1 — no paraphrase
/// anywhere in the memory path).
@Suite("422-E explicit notes")
struct ExplicitMemoryIntentTests {

    // MARK: - The brief's trigger-form pins

    @Test(arguments: ["Remember that my sister lives in Austin", "remember: my sister lives in Austin",
                      "Please remember that my sister lives in Austin", "Don't forget that my sister lives in Austin",
                      "Note that my sister lives in Austin", "For future reference, my sister lives in Austin"])
    func everyTriggerFormStoresTheUsersWordsVerbatim(prompt: String) {
        #expect(ExplicitMemoryIntent.parse(prompt) == "my sister lives in Austin")
    }

    @Test(arguments: ["Remember to call mom", "Remind me to take the bins out", "Set a reminder for 6:30", "remember me"])
    func reminderShapesNeverMatch(prompt: String) { #expect(ExplicitMemoryIntent.parse(prompt) == nil) }

    /// **A correction to the brief's pre-registered fixture.** The brief's
    /// example body was `String(repeating: "x", count: 900)` — homogeneous
    /// content where every 500-character window is identical, so
    /// `long.hasSuffix(note!)` is TRUE for ANY correct head-truncating
    /// implementation (the trailing 500 characters of an all-'x' run equal
    /// the leading 500). The assertion as originally written could never be
    /// satisfied, by a correct implementation or a buggy one — it does not
    /// discriminate. Fixed here by making the LAST character distinct
    /// ("x" × 899 + "y"), so a correct head-truncation (which never reaches
    /// the "y") is provably NOT a suffix of the source, while a hypothetical
    /// tail-truncation (which would include the "y") is provably NOT a
    /// prefix of the body. The cap-at-500 and no-paraphrase claims are
    /// unchanged; only the fixture's ability to prove them is fixed.
    @Test func anOverLongNoteIsCappedAt500WithNoParaphrase() {
        let long = "Remember that " + String(repeating: "x", count: 899) + "y"
        let note = ExplicitMemoryIntent.parse(long)
        #expect(note?.count == 500)
        #expect(long.hasSuffix(note!) == false && long.dropFirst("Remember that ".count).hasPrefix(note!))
    }

    // MARK: - `parseResult` — the truncation notice (Task 11 exposes it; the
    // Memory screen's visible notice is Task 16's, per the controller notes)

    @Test func parseResultReportsNoTruncationForAnOrdinaryNote() {
        let result = ExplicitMemoryIntent.parseResult("Remember that my sister lives in Austin")
        #expect(result?.note == "my sister lives in Austin")
        #expect(result?.truncated == false)
    }

    @Test func parseResultReportsTruncationOnlyWhenTheCapActuallyCut() {
        let long = "Remember that " + String(repeating: "x", count: 899) + "y"
        let result = ExplicitMemoryIntent.parseResult(long)
        #expect(result?.note.count == 500)
        #expect(result?.truncated == true)
    }

    @Test func parseResultIsNilForReminderShapesJustLikeParse() {
        #expect(ExplicitMemoryIntent.parseResult("Remember to call mom") == nil)
    }

    @Test func parseAndParseResultNeverDisagree() {
        for prompt in ["Remember that my sister lives in Austin", "Remember to call mom", "note that it rains"] {
            #expect(ExplicitMemoryIntent.parse(prompt) == ExplicitMemoryIntent.parseResult(prompt)?.note)
        }
    }

    // MARK: - Edge shapes (not in the brief, cheap to pin)

    @Test func aBareTriggerWithNothingAfterItDoesNotMatch() {
        #expect(ExplicitMemoryIntent.parse("Remember that") == nil, "the trigger alone has no fact to store")
        #expect(ExplicitMemoryIntent.parse("Remember that   ") == nil, "whitespace-only body is still empty")
    }

    @Test func leadingAndTrailingWhitespaceOnTheWholePromptIsIgnored() {
        #expect(ExplicitMemoryIntent.parse("   Remember that my sister lives in Austin   ")
            == "my sister lives in Austin")
    }

    @Test func matchingIsCaseInsensitiveOnTheTriggerOnly() {
        #expect(ExplicitMemoryIntent.parse("REMEMBER THAT my sister lives in Austin")
            == "my sister lives in Austin", "the trigger matches case-insensitively")
    }

    @Test func caseInsideTheBodyIsPreservedVerbatim() {
        #expect(ExplicitMemoryIntent.parse("Remember that My Sister Lives In AUSTIN")
            == "My Sister Lives In AUSTIN", "ruling 1 — no re-casing, no paraphrase")
    }

    /// Fix round 1 minor: the 7th trigger form was in `triggers` from the
    /// start but had no test asserting it matches on its own.
    @Test func doNotForgetThatIsRecognizedOnItsOwn() {
        #expect(ExplicitMemoryIntent.parse("Do not forget that my sister lives in Austin")
            == "my sister lives in Austin")
    }

    // MARK: - Apostrophe variants (fix round 1, Important item 4)
    //
    // `"don't forget that "` is spelled with a straight `'`, but iOS Smart
    // Punctuation and dictation both type the curly U+2019 — so the trigger
    // as written was UNREACHABLE from real device input. These pins fail
    // against the pre-fix parser (a plain `hasPrefix` on the un-folded,
    // lowercased text) and pass once apostrophe-folding is applied to the
    // MATCH only.

    @Test func aCurlyApostropheInTheTriggerStillMatches() {
        #expect(ExplicitMemoryIntent.parse("Don\u{2019}t forget that my sister lives in Austin")
            == "my sister lives in Austin")
    }

    /// The other curly-quote-adjacent variant `ActionClaimDetector` folds —
    /// same list, same reason (the two files must not silently drift apart
    /// on which characters count as "an apostrophe").
    @Test func aGraveAccentStandingInForAnApostropheStillMatches() {
        #expect(ExplicitMemoryIntent.parse("Don\u{00B4}t forget that my sister lives in Austin")
            == "my sister lives in Austin")
    }

    /// **Matching only, never rewriting.** A curly apostrophe INSIDE the
    /// note's own words (not the trigger) must survive verbatim — folding it
    /// to straight would be exactly the paraphrase ruling 1 forbids.
    @Test func aCurlyApostropheInsideTheNoteItselfIsStoredVerbatim() {
        #expect(ExplicitMemoryIntent.parse("Remember that my sister\u{2019}s address is 12 Elm Street")
            == "my sister\u{2019}s address is 12 Elm Street")
    }
}
