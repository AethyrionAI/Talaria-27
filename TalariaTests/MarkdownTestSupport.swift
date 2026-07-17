import Foundation
@testable import Talaria

// Shared case accessors for the markdown parser suites — Swift Testing
// `#expect` reads far better against these than nested `if case` pyramids.
extension MarkdownSegment {

    var proseText: String? {
        if case .prose(_, let text) = self { return text }
        return nil
    }

    var codeValue: (language: String?, code: String)? {
        if case .codeBlock(_, let language, let code) = self { return (language, code) }
        return nil
    }

    var imageValue: (url: URL, altText: String)? {
        if case .image(_, let url, let altText) = self { return (url, altText) }
        return nil
    }

    var headingValue: (level: Int, text: String)? {
        if case .heading(_, let level, let text) = self { return (level, text) }
        return nil
    }

    var quoteValue: (level: Int, text: String)? {
        if case .blockQuote(_, let level, let text) = self { return (level, text) }
        return nil
    }

    var listItems: [MarkdownListItem]? {
        if case .list(_, let items) = self { return items }
        return nil
    }

    var tableValue: (header: [String], alignments: [MarkdownTableAlignment], rows: [[String]])? {
        if case .table(_, let header, let alignments, let rows) = self { return (header, alignments, rows) }
        return nil
    }

    var chartValue: (spec: ChartSpec, source: String)? {
        if case .chart(_, let spec, let source) = self { return (spec, source) }
        return nil
    }

    /// Segment kind as a short label, for interleaving-order assertions.
    var kindLabel: String {
        switch self {
        case .prose: return "prose"
        case .codeBlock: return "code"
        case .image: return "image"
        case .heading: return "heading"
        case .blockQuote: return "quote"
        case .list: return "list"
        case .table: return "table"
        case .chart: return "chart"
        }
    }
}
