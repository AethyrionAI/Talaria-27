import Foundation
import Testing
@testable import Talaria

/// Lane B — mixed-document ordering: the new block types must interleave
/// with prose, images, and code blocks without reordering anything, and the
/// pre-existing three-segment behaviors must survive unchanged.
struct MarkdownInterleavingTests {

    @Test func fullDocumentPreservesOrder() throws {
        let markdown = """
        # Report

        Intro paragraph.

        - point one
        - point two

        > a quoted aside

        ```swift
        let x = 1
        ```

        | K | V |
        | --- | --- |
        | a | 1 |

        ![chart](https://example.com/chart.png)

        Closing prose.
        """
        let segments = parseMarkdownSegments(markdown)
        #expect(segments.map(\.kindLabel) == [
            "heading", "prose", "list", "quote", "code", "table", "image", "prose"
        ])
        #expect(segments[0].headingValue?.text == "Report")
        #expect(segments[1].proseText == "Intro paragraph.")
        #expect(segments[2].listItems?.map(\.text) == ["point one", "point two"])
        #expect(segments[3].quoteValue?.text == "a quoted aside")
        #expect(segments[4].codeValue?.language == "swift")
        #expect(segments[5].tableValue?.rows == [["a", "1"]])
        #expect(segments[6].imageValue?.url.absoluteString == "https://example.com/chart.png")
        #expect(segments[7].proseText == "Closing prose.")
    }

    @Test func proseImageProseStillInterleaves() {
        // Pre-Lane-B behavior: images embedded in prose split it in place.
        let markdown = "before ![alt](https://example.com/a.png) after"
        let segments = parseMarkdownSegments(markdown)
        #expect(segments.map(\.kindLabel) == ["prose", "image", "prose"])
        #expect(segments[0].proseText == "before")
        #expect(segments[2].proseText == "after")
    }

    @Test func streamingUnclosedFenceStillEmitsCode() throws {
        let segments = parseMarkdownSegments("intro\n```python\nprint(1)", isStreaming: true)
        #expect(segments.map(\.kindLabel) == ["prose", "code"])
        let code = try #require(segments[1].codeValue)
        #expect(code.language == "python")
        #expect(code.code == "print(1)")
    }

    @Test func nonStreamingUnclosedEmptyFenceFallsBackToProse() {
        // Matches the pre-Lane-B fallback: an unclosed fence with no content
        // outside streaming re-renders as literal prose.
        let segments = parseMarkdownSegments("text\n```swift")
        #expect(segments.map(\.kindLabel) == ["prose", "prose"])
        #expect(segments.last?.proseText?.contains("```swift") == true)
    }

    @Test func plainProseIsUntouched() {
        let segments = parseMarkdownSegments("just a plain **bold** sentence")
        #expect(segments.count == 1)
        #expect(segments.first?.proseText == "just a plain **bold** sentence")
    }

    @Test func adjacentBlocksWithoutBlankLinesStillSplit() {
        let markdown = "## Title\n- item\n> quote\ntail prose"
        let segments = parseMarkdownSegments(markdown)
        #expect(segments.map(\.kindLabel) == ["heading", "list", "quote", "prose"])
    }

    @Test func listFollowedByFenceDoesNotSwallowCode() throws {
        let markdown = "- item\n```\ncode\n```"
        let segments = parseMarkdownSegments(markdown)
        #expect(segments.map(\.kindLabel) == ["list", "code"])
        let code = try #require(segments[1].codeValue)
        #expect(code.code == "code")
    }

    @Test func imageInsideListItemStaysInlineText() throws {
        // Image extraction applies to prose only; inside a list item the
        // syntax stays inline text.
        let items = try #require(
            parseMarkdownSegments("- see ![alt](https://example.com/a.png)").first?.listItems
        )
        #expect(items[0].text == "see ![alt](https://example.com/a.png)")
    }

    @Test func emptyContentYieldsNoSegments() {
        #expect(parseMarkdownSegments("").isEmpty)
    }
}
