import Foundation
import Testing
@testable import Talaria

/// Lane B — list parsing: bullet and ordered markers, ordinal capture,
/// indentation-driven nesting, blank-line tolerance, and continuation lines.
struct MarkdownListTests {

    @Test func parsesUnorderedMarkers() throws {
        let segments = parseMarkdownSegments("- dash\n* star\n+ plus")
        #expect(segments.count == 1)
        let items = try #require(segments.first?.listItems)
        #expect(items.map(\.text) == ["dash", "star", "plus"])
        #expect(items.allSatisfy { $0.ordinal == nil })
        #expect(items.allSatisfy { $0.depth == 0 })
    }

    @Test func parsesOrderedMarkersAndOrdinals() throws {
        let items = try #require(parseMarkdownSegments("1. first\n2) second\n10. tenth").first?.listItems)
        #expect(items.map(\.text) == ["first", "second", "tenth"])
        #expect(items.map(\.ordinal) == [1, 2, 10])
    }

    @Test func nestedIndentationSetsDepth() throws {
        let markdown = """
        - top
          - child
            - grandchild
          - child two
        - top two
        """
        let items = try #require(parseMarkdownSegments(markdown).first?.listItems)
        #expect(items.map(\.depth) == [0, 1, 2, 1, 0])
        #expect(items.map(\.text) == ["top", "child", "grandchild", "child two", "top two"])
    }

    @Test func fourSpaceIndentAlsoNests() throws {
        let items = try #require(parseMarkdownSegments("- top\n    - child").first?.listItems)
        #expect(items.map(\.depth) == [0, 1])
    }

    @Test func mixedOrderedInsideUnorderedKeepsOrdinals() throws {
        let markdown = """
        - bullet
          1. nested one
          2. nested two
        """
        let items = try #require(parseMarkdownSegments(markdown).first?.listItems)
        #expect(items.map(\.depth) == [0, 1, 1])
        #expect(items.map(\.ordinal) == [nil, 1, 2])
    }

    @Test func singleBlankLineKeepsListTogether() throws {
        let segments = parseMarkdownSegments("- one\n\n- two")
        #expect(segments.count == 1)
        let items = try #require(segments.first?.listItems)
        #expect(items.map(\.text) == ["one", "two"])
    }

    @Test func doubleBlankLineSplitsLists() {
        let segments = parseMarkdownSegments("- one\n\n\n- two")
        #expect(segments.map(\.kindLabel) == ["list", "list"])
    }

    @Test func indentedContinuationJoinsPreviousItem() throws {
        let items = try #require(parseMarkdownSegments("- first line\n  wrapped tail").first?.listItems)
        #expect(items.count == 1)
        #expect(items[0].text == "first line\nwrapped tail")
    }

    @Test func fourDigitNumberIsProseNotList() {
        // A year at line start must not become an ordered item.
        let segments = parseMarkdownSegments("2026. was quite a year")
        #expect(segments.count == 1)
        #expect(segments.first?.proseText == "2026. was quite a year")
    }

    @Test func markerWithoutSpaceIsProse() {
        // `*emphasis*` and `-dash` are not list items.
        #expect(parseMarkdownSegments("*emphasis* text").first?.listItems == nil)
        #expect(parseMarkdownSegments("-dash text").first?.listItems == nil)
    }

    @Test func listEndsAtUnindentedProse() throws {
        let segments = parseMarkdownSegments("- item\nplain prose after")
        #expect(segments.map(\.kindLabel) == ["list", "prose"])
        #expect(segments[1].proseText == "plain prose after")
    }

    @Test func itemsKeepInlineMarkdown() throws {
        let items = try #require(parseMarkdownSegments("- **bold** and `code`").first?.listItems)
        #expect(items[0].text == "**bold** and `code`")
    }

    @Test func listInsideCodeFenceStaysCode() throws {
        let code = try #require(parseMarkdownSegments("```\n- not a list\n```").first?.codeValue)
        #expect(code.code == "- not a list")
    }
}
