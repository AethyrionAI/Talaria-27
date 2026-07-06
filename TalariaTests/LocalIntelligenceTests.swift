import Foundation
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
        // the only meaningful source for both fields.
        let card = LocalIntelligenceService.fallbackCard(
            userText: "",
            assistantText: "That photo shows the Golden Gate Bridge at sunset."
        )
        #expect(card.title == "That photo shows the Golden Gate Bridge at sunset")
        #expect(card.preview == "That photo shows the Golden Gate Bridge at sunset")
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
}
