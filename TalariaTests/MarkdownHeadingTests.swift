import Foundation
import Testing
@testable import Talaria

/// Lane B — ATX heading parsing: level detection, the space-after-hashes
/// rule, closing-hash stripping, and placement among other blocks.
struct MarkdownHeadingTests {

    @Test func parsesAllSixLevels() throws {
        for level in 1...6 {
            let hashes = String(repeating: "#", count: level)
            let segments = parseMarkdownSegments("\(hashes) Title")
            #expect(segments.count == 1)
            let heading = try #require(segments.first?.headingValue)
            #expect(heading.level == level)
            #expect(heading.text == "Title")
        }
    }

    @Test func sevenHashesIsProse() {
        let segments = parseMarkdownSegments("####### Not a heading")
        #expect(segments.count == 1)
        #expect(segments.first?.proseText == "####### Not a heading")
    }

    @Test func hashWithoutSpaceIsProse() {
        // `#hashtag` must not render as a heading.
        let segments = parseMarkdownSegments("#hashtag content")
        #expect(segments.count == 1)
        #expect(segments.first?.proseText == "#hashtag content")
    }

    @Test func stripsClosingHashRun() throws {
        let heading = try #require(parseMarkdownSegments("## Title ##").first?.headingValue)
        #expect(heading.level == 2)
        #expect(heading.text == "Title")
    }

    @Test func emptyHeadingIsNotEmitted() {
        // "#" or "## " with no text renders nothing useful — stays prose.
        #expect(parseMarkdownSegments("## ").first?.headingValue == nil)
        #expect(parseMarkdownSegments("#").first?.headingValue == nil)
    }

    @Test func headingKeepsInlineMarkdown() throws {
        let heading = try #require(parseMarkdownSegments("# **Bold** and `code`").first?.headingValue)
        #expect(heading.text == "**Bold** and `code`")
    }

    @Test func headingSplitsSurroundingProse() throws {
        let segments = parseMarkdownSegments("intro line\n## Section\nbody line")
        #expect(segments.map(\.kindLabel) == ["prose", "heading", "prose"])
        #expect(segments[0].proseText == "intro line")
        let heading = try #require(segments[1].headingValue)
        #expect(heading.level == 2)
        #expect(heading.text == "Section")
        #expect(segments[2].proseText == "body line")
    }

    @Test func headingInsideCodeFenceStaysCode() throws {
        let segments = parseMarkdownSegments("```\n# not a heading\n```")
        #expect(segments.count == 1)
        let code = try #require(segments.first?.codeValue)
        #expect(code.code == "# not a heading")
    }
}
