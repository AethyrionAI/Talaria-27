import Foundation
import Testing
@testable import Talaria

/// Lane B — GFM pipe-table parsing: delimiter-row detection, alignments,
/// row normalization, escaped pipes, and non-table pipe lines staying prose.
struct MarkdownTableTests {

    @Test func parsesBasicTable() throws {
        let markdown = """
        | Name | Value |
        | --- | --- |
        | alpha | 1 |
        | beta | 2 |
        """
        let segments = parseMarkdownSegments(markdown)
        #expect(segments.count == 1)
        let table = try #require(segments.first?.tableValue)
        #expect(table.header == ["Name", "Value"])
        #expect(table.rows == [["alpha", "1"], ["beta", "2"]])
        #expect(table.alignments == [.leading, .leading])
    }

    @Test func parsesAlignments() throws {
        let markdown = """
        | L | C | R |
        | :--- | :---: | ---: |
        | a | b | c |
        """
        let table = try #require(parseMarkdownSegments(markdown).first?.tableValue)
        #expect(table.alignments == [.leading, .center, .trailing])
    }

    @Test func worksWithoutOuterPipes() throws {
        let markdown = """
        Name | Value
        --- | ---
        alpha | 1
        """
        let table = try #require(parseMarkdownSegments(markdown).first?.tableValue)
        #expect(table.header == ["Name", "Value"])
        #expect(table.rows == [["alpha", "1"]])
    }

    @Test func normalizesShortAndLongRows() throws {
        let markdown = """
        | A | B |
        | --- | --- |
        | only |
        | one | two | three |
        """
        let table = try #require(parseMarkdownSegments(markdown).first?.tableValue)
        #expect(table.rows == [["only", ""], ["one", "two"]])
    }

    @Test func escapedPipeStaysInCell() throws {
        let markdown = """
        | Expr | Result |
        | --- | --- |
        | a \\| b | or |
        """
        let table = try #require(parseMarkdownSegments(markdown).first?.tableValue)
        #expect(table.rows == [["a | b", "or"]])
    }

    @Test func pipeLineWithoutDelimiterIsProse() {
        let segments = parseMarkdownSegments("this | is just prose\nmore prose")
        #expect(segments.count == 1)
        #expect(segments.first?.proseText == "this | is just prose\nmore prose")
    }

    @Test func headerDelimiterCountMismatchIsProse() {
        // Two header cells but three delimiter cells — not a table.
        let segments = parseMarkdownSegments("| a | b |\n| --- | --- | --- |")
        #expect(segments.allSatisfy { $0.tableValue == nil })
    }

    @Test func tableEndsAtNonPipeLine() throws {
        let markdown = """
        | A | B |
        | --- | --- |
        | 1 | 2 |
        after the table
        """
        let segments = parseMarkdownSegments(markdown)
        #expect(segments.map(\.kindLabel) == ["table", "prose"])
        let table = try #require(segments[0].tableValue)
        #expect(table.rows.count == 1)
        #expect(segments[1].proseText == "after the table")
    }

    @Test func headerOnlyTableParses() throws {
        let table = try #require(parseMarkdownSegments("| A | B |\n| --- | --- |").first?.tableValue)
        #expect(table.header == ["A", "B"])
        #expect(table.rows.isEmpty)
    }

    @Test func cellsKeepInlineMarkdown() throws {
        let markdown = """
        | Col |
        | --- |
        | **bold** cell |
        """
        let table = try #require(parseMarkdownSegments(markdown).first?.tableValue)
        #expect(table.rows == [["**bold** cell"]])
    }

    @Test func tableInsideCodeFenceStaysCode() throws {
        let code = try #require(parseMarkdownSegments("```\n| a | b |\n| --- | --- |\n```").first?.codeValue)
        #expect(code.code == "| a | b |\n| --- | --- |")
    }

    @Test func streamingHeaderWithoutDelimiterYetIsProse() {
        // Mid-stream: the header row arrived but the delimiter row hasn't.
        let segments = parseMarkdownSegments("| A | B |", isStreaming: true)
        #expect(segments.count == 1)
        #expect(segments.first?.proseText == "| A | B |")
    }
}
