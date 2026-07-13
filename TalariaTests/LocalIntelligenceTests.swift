import Foundation
import FoundationModels
import Testing
@testable import Talaria

/// #4.8 — the deterministic layer of LocalIntelligenceService: the truncation
/// fallback card (what every non-AI device gets), line sanitization, and
/// first-meaningful-line extraction. The FoundationModels generation path
/// requires Apple Intelligence hardware and is device-verified, not
/// unit-tested — these tests pin down everything around it.
struct LocalIntelligenceTests {

    // MARK: Fallback card (model unavailable)

    @Test func fallbackCardUsesFirstUserLineAndFirstReplyLine() {
        let card = LocalIntelligenceService.fallbackCard(
            userText: "How do I set up a reverse proxy for my home lab?\nMore detail below.",
            assistantText: "Use Caddy — it's the simplest option for a home lab.\nHere's why…"
        )
        #expect(card.title == "How do I set up a reverse proxy for my home lab?")
        #expect(card.preview == "Use Caddy — it's the simplest option for a home lab")
    }

    @Test func fallbackCardTruncatesLongLinesOnWordBoundaries() {
        let card = LocalIntelligenceService.fallbackCard(
            userText: "Please give me a very detailed explanation of how transformer attention heads work internally",
            assistantText: String(repeating: "word ", count: 60)
        )
        #expect(card.title.count <= 49) // 48 + ellipsis
        #expect(card.title.hasSuffix("…"))
        #expect(!card.title.dropLast().hasSuffix(" ")) // cut on a boundary, no dangling space
        #expect(card.preview.count <= 91)
    }

    @Test func fallbackCardHandlesAttachmentOnlyTurn() {
        // Attachment-only sends have placeholder-ish user text; the reply is
        // the only meaningful source. #61: the title borrows the reply's first
        // line, so the preview must NOT repeat it — with no distinct second
        // line the card is title-only.
        let card = LocalIntelligenceService.fallbackCard(
            userText: "",
            assistantText: "That photo shows the Golden Gate Bridge at sunset."
        )
        // The reply is 50 chars — over the 48-char title cap, so the title
        // word-boundary-truncates; the preview stays empty (no distinct line).
        #expect(card.title == "That photo shows the Golden Gate Bridge at…")
        #expect(card.preview.isEmpty)
    }

    // #61: the empty-user regression (device pass 2026-07-11 FAIL — "repeats
    // the first line on both lines"). When the user turn has no meaningful
    // line the title has to borrow the reply's first line; the preview must
    // NOT echo that same line.
    @Test func fallbackCardEmptyUserTurnDoesNotDuplicateReplyLine() {
        // Single-line reply → title carries the line, preview stays empty
        // rather than repeating it.
        let single = LocalIntelligenceService.fallbackCard(
            userText: "",
            assistantText: "That photo shows the Golden Gate Bridge at sunset."
        )
        #expect(!single.title.isEmpty)
        #expect(single.preview.isEmpty)
        #expect(LocalIntelligenceService.degenerateCardReason(title: single.title, preview: single.preview) == nil)

        // Multi-line reply → title from line 1, preview from a DISTINCT line 2.
        let multi = LocalIntelligenceService.fallbackCard(
            userText: "   ",
            assistantText: "That photo shows the Golden Gate Bridge.\nIt was taken at sunset from Marin."
        )
        #expect(multi.title == "That photo shows the Golden Gate Bridge")
        #expect(multi.preview == "It was taken at sunset from Marin")
        #expect(multi.title != multi.preview)
    }

    @Test func fallbackCardIsEmptyWhenNothingMeaningful() {
        let card = LocalIntelligenceService.fallbackCard(userText: "  \n\n", assistantText: "```\n```")
        #expect(card.title.isEmpty)
        #expect(card.preview.isEmpty)
        // ChatStore guards on empty title and keeps the placeholder — that's
        // the "real data only" contract.
    }

    // MARK: First meaningful line

    @Test func firstMeaningfulLineSkipsFencedCodeAndStripsHeadings() {
        // The fence's contents are skipped too — a code line must never
        // become a conversation title.
        #expect(LocalIntelligenceService.firstMeaningfulLine(of: "```swift\nlet x = 1\n```\n## Setup\nDo this first") == "Setup")
        #expect(LocalIntelligenceService.firstMeaningfulLine(of: "\n\n## Setup steps\nbody") == "Setup steps")
        #expect(LocalIntelligenceService.firstMeaningfulLine(of: "   \n\t\n") == nil)
    }

    // MARK: Line sanitization

    @Test func condensedLineCollapsesWhitespaceAndStripsWrapping() {
        #expect(LocalIntelligenceService.condensedLine("  \"Reverse   proxy\nsetup.\"  ", limit: 48) == "Reverse proxy setup")
        #expect(LocalIntelligenceService.condensedLine("`Home lab DNS`", limit: 48) == "Home lab DNS")
        #expect(LocalIntelligenceService.condensedLine("“Smart quotes”", limit: 48) == "Smart quotes")
    }

    @Test func condensedLineKeepsMeaningfulTerminators() {
        // A trailing question mark is meaning, not decoration.
        #expect(LocalIntelligenceService.condensedLine("What is a monad?", limit: 48) == "What is a monad?")
        #expect(LocalIntelligenceService.condensedLine("Done.", limit: 48) == "Done")
        #expect(LocalIntelligenceService.condensedLine("First; second;", limit: 48) == "First; second")
    }

    @Test func condensedLineWordBoundaryTruncation() {
        let long = "alpha bravo charlie delta echo foxtrot golf hotel india juliett"
        let cut = LocalIntelligenceService.condensedLine(long, limit: 20)
        #expect(cut == "alpha bravo charlie…")
        // A single unbroken token longer than the limit still truncates hard.
        let unbroken = LocalIntelligenceService.condensedLine(String(repeating: "x", count: 60), limit: 20)
        #expect(unbroken.count == 21)
        #expect(unbroken.hasSuffix("…"))
    }

    @Test func condensedLineShortInputPassesThrough() {
        #expect(LocalIntelligenceService.condensedLine("Sensor sync", limit: 48) == "Sensor sync")
        #expect(LocalIntelligenceService.condensedLine("", limit: 48) == "")
    }

    // MARK: Degenerate-card guard (#61)

    @Test func degenerateCardTripsOnIdenticalTitleAndPreview() {
        // Case, whitespace, and trailing separators fold away first.
        let reason = LocalIntelligenceService.degenerateCardReason(
            title: "Reverse proxy setup",
            preview: "Reverse  PROXY setup."
        )
        #expect(reason?.contains("identical") == true)
    }

    @Test func degenerateCardTripsOnContainment() {
        // A preview that mostly IS the title — the shape two truncations of
        // the same degenerate run take.
        let reason = LocalIntelligenceService.degenerateCardReason(
            title: "Set up a reverse proxy on the home lab",
            preview: "Set up a reverse proxy on the home lab, then test it"
        )
        #expect(reason?.contains("containment") == true)
    }

    @Test func degenerateCardTripsOnRepetition() {
        // The observed #61 device symptom: the same repeated raw text
        // truncated into both fields. The 47-char folded title carries two
        // full copies plus a partial — enough under the long-run rule.
        let reason = LocalIntelligenceService.degenerateCardReason(
            title: "Checking the weather Checking the weather Check…",
            preview: "Checking the weather Checking the weather Checking the weather Checking the…"
        )
        #expect(reason?.contains("repeats") == true)
    }

    @Test func degenerateCardTripsOnRepetitionBehindAPreamble() {
        // A healthy lead-in must not hide the loop — the run reaches the
        // truncation cut and dominates the field.
        let reason = LocalIntelligenceService.degenerateCardReason(
            title: "Weather check",
            preview: "Sunny outlook, but sunny and warm sunny and warm sunny and warm sunny and warm"
        )
        #expect(reason?.contains("preview repeats") == true)
    }

    @Test func degenerateCardCatchesTruncatedLoopShapesEndToEnd() {
        // The exact #61 production pipeline: the same looped raw text pushed
        // through condensedLine at both field limits. Medium unit (33 chars,
        // caught by the two-copy run rule)…
        let mediumUnit = String(repeating: "I can absolutely help with that. ", count: 4)
        #expect(LocalIntelligenceService.degenerateCardReason(
            title: LocalIntelligenceService.condensedLine(mediumUnit, limit: 48),
            preview: LocalIntelligenceService.condensedLine(mediumUnit, limit: 90)
        ) != nil)
        // …and a long unit (51 chars — invisible to the repetition scan in a
        // 90-char field, caught by the prefix-echo rule).
        let longUnit = String(repeating: "The model keeps repeating this whole long sentence ", count: 2)
        #expect(LocalIntelligenceService.degenerateCardReason(
            title: LocalIntelligenceService.condensedLine(longUnit, limit: 48),
            preview: LocalIntelligenceService.condensedLine(longUnit, limit: 90)
        ) != nil)
    }

    @Test func degenerateCardTripsWhenOnlyOneFieldRepeats() {
        let reason = LocalIntelligenceService.degenerateCardReason(
            title: "Weather check",
            preview: "sunny and warm sunny and warm sunny and warm sunny and warm"
        )
        #expect(reason?.contains("preview repeats") == true)
    }

    @Test func degenerateCardPassesHealthyCards() {
        // Distinct title and preview.
        #expect(LocalIntelligenceService.degenerateCardReason(
            title: "Reverse proxy setup",
            preview: "Choosing Caddy to expose a home lab service safely"
        ) == nil)
        // A short title echoed inside a much longer preview is normal
        // phrasing, not degeneracy.
        #expect(LocalIntelligenceService.degenerateCardReason(
            title: "Tokyo trip",
            preview: "Planning a Tokyo trip with a two-day Kyoto side visit in April"
        ) == nil)
        // Naturally doubled names stay under the repeat threshold.
        #expect(LocalIntelligenceService.degenerateCardReason(
            title: "New York, New York",
            preview: "Best sights to see on a first visit to Manhattan"
        ) == nil)
    }

    @Test func repeatedRunUnitToleratesTruncation() {
        // condensedLine cuts mid-unit and appends an ellipsis — the partial
        // final copy must still count as the same run.
        #expect(LocalIntelligenceService.repeatedRunUnit(in: "error loop error loop error loop error lo…") == "error loop ")
        #expect(LocalIntelligenceService.repeatedRunUnit(in: "A healthy preview about one clear topic") == nil)
    }

    @Test func repeatedRunUnitIgnoresShortRefrainsAndShortText() {
        // Fundamental period 3 ("ha ") sits below the minimum unit; its
        // 6-character multiple must not qualify in its place.
        #expect(LocalIntelligenceService.repeatedRunUnit(in: "ha ha ha ha ha ha ha ha") == nil)
        #expect(LocalIntelligenceService.repeatedRunUnit(in: "cha-cha-cha") == nil)
        #expect(LocalIntelligenceService.repeatedRunUnit(in: "") == nil)
    }

    // MARK: Bounded generation options (#102 guardrail on this service's call sites)

    @Test func generationOptionsCarryDefensiveTokenCaps() {
        #expect(LocalIntelligenceService.cardGenerationOptions.maximumResponseTokens == 256)
        #expect(LocalIntelligenceService.cardGenerationOptions.temperature == 0.3)
        #expect(LocalIntelligenceService.reasoningGenerationOptions.maximumResponseTokens == 128)
        #expect(LocalIntelligenceService.reasoningGenerationOptions.temperature == 0.3)
        #expect(LocalIntelligenceService.contextBriefGenerationOptions.maximumResponseTokens == 1024)
        #expect(LocalIntelligenceService.contextBriefGenerationOptions.temperature == 0.2)
    }
}
