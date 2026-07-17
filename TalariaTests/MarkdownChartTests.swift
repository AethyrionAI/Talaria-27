import Foundation
import Testing
@testable import Talaria

/// OPEN_ITEMS #100 PR 1 — the ```chart fence hinge in the markdown parser.
/// The hard constraint: the parser re-runs on every SSE delta, so a chart may
/// materialize ONLY from a closed fence whose spec decodes; every mid-stream
/// and failure state stays a `.codeBlock` with the body preserved
/// byte-for-byte.
struct MarkdownChartTests {

    private let validSpec = """
    {"type":"line","title":"Resting HR, 7d",
     "x":{"label":"Day","values":["Mon","Tue","Wed"]},
     "series":[{"name":"bpm","values":[58,61,57]}]}
    """

    // MARK: - Materialization

    @Test func closedValidFenceBecomesChart() throws {
        let markdown = "```chart\n\(validSpec)\n```"
        let segments = parseMarkdownSegments(markdown)
        #expect(segments.count == 1)
        let chart = try #require(segments.first?.chartValue)
        #expect(chart.spec.kind == .line)
        #expect(chart.spec.title == "Resting HR, 7d")
        #expect(chart.spec.series.first?.values == [58, 61, 57])
        #expect(chart.source == validSpec)
    }

    @Test func chartFenceKeepsNeighboringSegmentsIntact() throws {
        let markdown = "Here is your week:\n\n```chart\n\(validSpec)\n```\n\nAverage was 58.7 bpm."
        let segments = parseMarkdownSegments(markdown)
        #expect(segments.map(\.kindLabel) == ["prose", "chart", "prose"])
        #expect(segments.first?.proseText == "Here is your week:")
        #expect(segments.last?.proseText == "Average was 58.7 bpm.")
    }

    @Test func languageTagIsCaseInsensitive() throws {
        let markdown = "```Chart\n\(validSpec)\n```"
        #expect(parseMarkdownSegments(markdown).first?.chartValue != nil)
    }

    @Test func closedFenceMaterializesEvenWhileStreaming() throws {
        // The fence is whole; later content is still arriving. The chart may
        // draw — it will not change again.
        let markdown = "```chart\n\(validSpec)\n```\n\nAnd the trend sugg"
        let segments = parseMarkdownSegments(markdown, isStreaming: true)
        #expect(segments.map(\.kindLabel) == ["chart", "prose"])
    }

    // MARK: - Streaming safety: unterminated fences never chart

    @Test func unterminatedFenceWhileStreamingIsCodeBlock() throws {
        // Even a fully valid spec must not chart until the fence closes.
        let markdown = "```chart\n\(validSpec)"
        let segments = parseMarkdownSegments(markdown, isStreaming: true)
        #expect(segments.count == 1)
        let code = try #require(segments.first?.codeValue)
        #expect(code.language == "chart")
        #expect(code.code == validSpec)
    }

    @Test func partialJSONWhileStreamingIsCodeBlock() throws {
        let markdown = "```chart\n{\"type\":\"line\",\"x\":{\"va"
        let segments = parseMarkdownSegments(markdown, isStreaming: true)
        let code = try #require(segments.first?.codeValue)
        #expect(code.language == "chart")
        #expect(code.code == "{\"type\":\"line\",\"x\":{\"va")
    }

    @Test func unterminatedFenceAfterStreamingEndsIsCodeBlock() throws {
        // A message that ended mid-fence (isStreaming false) degrades the
        // same way — never a chart from an unclosed fence.
        let markdown = "```chart\n\(validSpec)"
        let segments = parseMarkdownSegments(markdown, isStreaming: false)
        let code = try #require(segments.first?.codeValue)
        #expect(code.language == "chart")
        #expect(code.code == validSpec)
    }

    // MARK: - Degradation: failures keep the fence as a code block

    @Test func malformedJSONFallsBackToCodeBlock() throws {
        let body = "{\"type\":\"line\",\"x\":{\"values\":[\"a\"],"
        let markdown = "```chart\n\(body)\n```"
        let segments = parseMarkdownSegments(markdown)
        #expect(segments.count == 1)
        let code = try #require(segments.first?.codeValue)
        #expect(code.language == "chart")
        #expect(code.code == body)
    }

    @Test func unknownChartTypeFallsBackToCodeBlock() throws {
        let body = #"{"type":"pie","x":{"values":["a","b"]},"series":[{"values":[1,2]}]}"#
        let segments = parseMarkdownSegments("```chart\n\(body)\n```")
        let code = try #require(segments.first?.codeValue)
        #expect(code.language == "chart")
        #expect(code.code == body)
    }

    @Test func raggedSpecFallsBackToCodeBlock() throws {
        let body = #"{"type":"line","x":{"values":["a","b","c"]},"series":[{"values":[1,2]}]}"#
        let segments = parseMarkdownSegments("```chart\n\(body)\n```")
        let code = try #require(segments.first?.codeValue)
        #expect(code.language == "chart")
        #expect(code.code == body)
    }

    @Test func emptyChartFenceFallsBackToCodeBlock() throws {
        let segments = parseMarkdownSegments("```chart\n```")
        let code = try #require(segments.first?.codeValue)
        #expect(code.language == "chart")
        #expect(code.code == "")
    }

    @Test func fallbackPreservesBodyByteForByte() throws {
        // Odd whitespace, unicode, trailing spaces — the fallback shows
        // exactly what arrived.
        let body = "  {\"type\":\"pie\", \"note\":\"°∆ trailing  \"}  "
        let segments = parseMarkdownSegments("```chart\n\(body)\n```")
        let code = try #require(segments.first?.codeValue)
        #expect(code.code == body)
    }

    // MARK: - Non-chart fences unaffected

    @Test func jsonFenceWithChartShapedBodyStaysCodeBlock() throws {
        let segments = parseMarkdownSegments("```json\n\(validSpec)\n```")
        let code = try #require(segments.first?.codeValue)
        #expect(code.language == "json")
        #expect(code.code == validSpec)
    }

    @Test func chartFenceBesideOtherFences() throws {
        let markdown = "```swift\nlet x = 1\n```\n\n```chart\n\(validSpec)\n```"
        let segments = parseMarkdownSegments(markdown)
        #expect(segments.map(\.kindLabel) == ["code", "chart"])
        #expect(segments.first?.codeValue?.language == "swift")
    }
}
