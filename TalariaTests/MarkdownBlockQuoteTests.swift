import Foundation
import Testing
@testable import Talaria

/// Lane B — block-quote parsing: marker stripping, multi-line merging,
/// nesting depth grouping, and termination at plain lines.
struct MarkdownBlockQuoteTests {

    @Test func parsesSingleLineQuote() throws {
        let segments = parseMarkdownSegments("> quoted text")
        #expect(segments.count == 1)
        let quote = try #require(segments.first?.quoteValue)
        #expect(quote.level == 1)
        #expect(quote.text == "quoted text")
    }

    @Test func mergesConsecutiveLinesAtSameDepth() throws {
        let quote = try #require(parseMarkdownSegments("> line one\n> line two").first?.quoteValue)
        #expect(quote.level == 1)
        #expect(quote.text == "line one\nline two")
    }

    @Test func nestedDepthStartsNewSegment() throws {
        let segments = parseMarkdownSegments("> outer\n>> inner\n> outer again")
        #expect(segments.map(\.kindLabel) == ["quote", "quote", "quote"])
        let outer = try #require(segments[0].quoteValue)
        let inner = try #require(segments[1].quoteValue)
        let outerAgain = try #require(segments[2].quoteValue)
        #expect(outer.level == 1)
        #expect(outer.text == "outer")
        #expect(inner.level == 2)
        #expect(inner.text == "inner")
        #expect(outerAgain.level == 1)
        #expect(outerAgain.text == "outer again")
    }

    @Test func spacedNestedMarkersCountAsDepth() throws {
        // `> > text` is depth 2, same as `>> text`.
        let quote = try #require(parseMarkdownSegments("> > spaced nesting").first?.quoteValue)
        #expect(quote.level == 2)
        #expect(quote.text == "spaced nesting")
    }

    @Test func quoteEndsAtPlainLine() throws {
        let segments = parseMarkdownSegments("> quoted\nplain prose after")
        #expect(segments.map(\.kindLabel) == ["quote", "prose"])
        #expect(segments[1].proseText == "plain prose after")
    }

    @Test func blankLineSplitsQuotes() {
        let segments = parseMarkdownSegments("> first\n\n> second")
        #expect(segments.map(\.kindLabel) == ["quote", "quote"])
        #expect(segments[0].quoteValue?.text == "first")
        #expect(segments[1].quoteValue?.text == "second")
    }

    @Test func emptyMarkerLinesJoinParagraphsWithinQuote() throws {
        // A bare ">" continuation keeps the quote as one segment.
        let quote = try #require(parseMarkdownSegments("> para one\n>\n> para two").first?.quoteValue)
        #expect(quote.level == 1)
        #expect(quote.text.hasPrefix("para one"))
        #expect(quote.text.hasSuffix("para two"))
    }

    @Test func markerOnlyQuoteEmitsNothing() {
        #expect(parseMarkdownSegments(">\n>").isEmpty)
    }

    @Test func quoteKeepsInlineMarkdown() throws {
        let quote = try #require(parseMarkdownSegments("> **bold** claim").first?.quoteValue)
        #expect(quote.text == "**bold** claim")
    }

    @Test func quoteInsideCodeFenceStaysCode() throws {
        let code = try #require(parseMarkdownSegments("```\n> not a quote\n```").first?.codeValue)
        #expect(code.code == "> not a quote")
    }
}
