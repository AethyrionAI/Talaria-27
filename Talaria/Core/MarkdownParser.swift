import Foundation

/// A segment of parsed markdown content — prose, fenced code block, image,
/// heading, block quote, list, or pipe table.
enum MarkdownSegment: Identifiable {
    case prose(id: UUID = UUID(), text: String)
    case codeBlock(id: UUID = UUID(), language: String?, code: String)
    case image(id: UUID = UUID(), url: URL, altText: String)
    /// ATX heading (`# Title` … `###### Title`). `text` keeps its inline
    /// markdown (`**bold**`, `` `code` ``) for the renderer.
    case heading(id: UUID = UUID(), level: Int, text: String)
    /// Block quote. `level` is the `>` nesting depth (1-based); consecutive
    /// quote lines at the same depth merge into one segment, and a depth
    /// change starts a new segment so nesting renders as deeper indentation.
    case blockQuote(id: UUID = UUID(), level: Int, text: String)
    /// Ordered / unordered list. Nesting is per-item
    /// (`MarkdownListItem.depth`), so one segment carries a whole contiguous
    /// list block — including depth changes and ordered/unordered mixing.
    case list(id: UUID = UUID(), items: [MarkdownListItem])
    /// GFM pipe table. Every row is normalized to `header.count` cells
    /// (excess cells dropped, missing cells empty — GitHub behavior).
    case table(id: UUID = UUID(), header: [String], alignments: [MarkdownTableAlignment], rows: [[String]])

    var id: UUID {
        switch self {
        case .prose(let id, _): return id
        case .codeBlock(let id, _, _): return id
        case .image(let id, _, _): return id
        case .heading(let id, _, _): return id
        case .blockQuote(let id, _, _): return id
        case .list(let id, _): return id
        case .table(let id, _, _, _): return id
        }
    }
}

/// One item of a markdown list segment.
struct MarkdownListItem: Identifiable {
    let id = UUID()
    /// Item text with inline markdown preserved; indented continuation lines
    /// are appended with newlines.
    var text: String
    /// 0-based nesting depth derived from leading indentation.
    let depth: Int
    /// The literal number of an ordered item (`3.` → 3); nil for bullets.
    let ordinal: Int?
}

/// Column alignment parsed from a table's delimiter row (`:---`, `:---:`, `---:`).
enum MarkdownTableAlignment: Equatable {
    case leading, center, trailing
}

// Regex for markdown images: ![alt text](url)
// nonisolated(unsafe) satisfies Swift 6.2 strict concurrency for global Regex.
nonisolated(unsafe) private let markdownImagePattern = /!\[([^\]]*)\]\(([^)]+)\)/
// HTML img tags: <img src="url"> or <img src="url"/> or <img src="url"></img>
nonisolated(unsafe) private let htmlImagePattern = /<img\s+src=["']?(https?:\/\/[^\s"'<>]+)["']?\s*\/?\s*>(\s*<\/img>)?/

/// Image file extensions the parser recognizes.
private let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "svg"]

/// Known image hosting domains (always treated as images regardless of extension).
private let imageHostPatterns: [String] = ["fal.media", "fal-cdn", "replicate.delivery", "oaidalleapiprodscus"]

/// Returns true if the URL looks like an image.
private func isImageURL(_ urlString: String) -> Bool {
    let lower = urlString.lowercased()
    // Check extension
    if let ext = URL(string: lower)?.pathExtension, imageExtensions.contains(ext) {
        return true
    }
    // Check known image hosts
    for host in imageHostPatterns {
        if lower.contains(host) { return true }
    }
    return false
}

/// An image match found in prose text.
private struct ImageMatch: Comparable {
    let range: Range<String.Index>
    let url: String
    let alt: String

    static func < (lhs: ImageMatch, rhs: ImageMatch) -> Bool {
        lhs.range.lowerBound < rhs.range.lowerBound
    }
}

/// Splits prose text into interleaved prose and image segments, preserving order.
/// Handles both markdown ![alt](url) and HTML <img src="url"> syntax.
private func splitProseAndImages(_ text: String) -> [MarkdownSegment] {
    // Collect all image matches from both patterns
    var imageMatches: [ImageMatch] = []

    for match in text.matches(of: markdownImagePattern) {
        imageMatches.append(ImageMatch(range: match.range, url: String(match.2), alt: String(match.1)))
    }
    for match in text.matches(of: htmlImagePattern) {
        imageMatches.append(ImageMatch(range: match.range, url: String(match.1), alt: ""))
    }

    imageMatches.sort()

    guard !imageMatches.isEmpty else {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? [] : [.prose(text: trimmed)]
    }

    var segments: [MarkdownSegment] = []
    var lastEnd = text.startIndex

    for img in imageMatches {
        // Skip overlapping matches
        guard img.range.lowerBound >= lastEnd else { continue }

        // Emit prose before this image
        let before = String(text[lastEnd..<img.range.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !before.isEmpty {
            segments.append(.prose(text: before))
        }

        // If it's in image syntax (![alt](url) or <img src="url">), treat it
        // as an image unconditionally. AsyncImage handles the load; if the URL
        // isn't actually an image, the failure state shows alt text gracefully.
        if let url = URL(string: img.url), url.scheme == "http" || url.scheme == "https" {
            segments.append(.image(url: url, altText: img.alt))
        } else {
            let raw = String(text[img.range])
            segments.append(.prose(text: raw))
        }

        lastEnd = img.range.upperBound
    }

    // Emit prose after the last image
    let after = String(text[lastEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
    if !after.isEmpty {
        segments.append(.prose(text: after))
    }

    return segments
}

// MARK: - Block-level line classifiers

/// Width of a line's leading whitespace (space = 1, tab = 4).
private func leadingWhitespaceWidth(_ line: String) -> Int {
    var width = 0
    for ch in line {
        if ch == " " { width += 1 } else if ch == "\t" { width += 4 } else { break }
    }
    return width
}

/// Parses an ATX heading line (`## Title`). Requires 1–6 `#`s followed by a
/// space (so `#hashtag` stays prose) and at most 3 leading spaces. A trailing
/// closing-hash run (`## Title ##`) is stripped per CommonMark.
private func headingLine(_ line: String) -> (level: Int, text: String)? {
    guard leadingWhitespaceWidth(line) <= 3 else { return nil }
    let trimmed = line.drop(while: { $0 == " " })
    var level = 0
    var idx = trimmed.startIndex
    while idx < trimmed.endIndex, trimmed[idx] == "#" {
        level += 1
        idx = trimmed.index(after: idx)
    }
    guard (1...6).contains(level), idx < trimmed.endIndex else { return nil }
    guard trimmed[idx] == " " || trimmed[idx] == "\t" else { return nil }
    var text = String(trimmed[idx...]).trimmingCharacters(in: .whitespaces)
    if let closing = text.range(of: #"\s+#+\s*$"#, options: .regularExpression) {
        text.removeSubrange(closing)
    } else if text.allSatisfy({ $0 == "#" }) {
        text = ""
    }
    guard !text.isEmpty else { return nil }
    return (level, text)
}

/// Parses a block-quote line, returning its `>` depth (1-based) and the
/// content after the markers. One optional space is consumed after each
/// marker, so `> > text` and `>> text` are both depth 2.
private func quoteLine(_ line: String) -> (depth: Int, content: String)? {
    guard leadingWhitespaceWidth(line) <= 3 else { return nil }
    var idx = line.startIndex
    while idx < line.endIndex, line[idx] == " " { idx = line.index(after: idx) }
    var depth = 0
    while idx < line.endIndex, line[idx] == ">" {
        depth += 1
        idx = line.index(after: idx)
        if idx < line.endIndex, line[idx] == " " { idx = line.index(after: idx) }
    }
    guard depth > 0 else { return nil }
    return (depth, String(line[idx...]))
}

/// Parses a list-item line: `-`/`*`/`+` bullets or `1.`/`1)` ordered markers
/// (1–3 digits, so a year like `2026.` stays prose), each requiring a
/// trailing space and non-empty text.
private func listItemLine(_ line: String) -> (indent: Int, ordinal: Int?, text: String)? {
    let indent = leadingWhitespaceWidth(line)
    var idx = line.startIndex
    while idx < line.endIndex, line[idx] == " " || line[idx] == "\t" { idx = line.index(after: idx) }
    guard idx < line.endIndex else { return nil }

    let ch = line[idx]
    if ch == "-" || ch == "*" || ch == "+" {
        let after = line.index(after: idx)
        guard after < line.endIndex, line[after] == " " || line[after] == "\t" else { return nil }
        let text = String(line[after...]).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (indent, nil, text)
    }

    if ch.isWholeNumber {
        var numEnd = idx
        var digits = 0
        while numEnd < line.endIndex, line[numEnd].isWholeNumber {
            digits += 1
            numEnd = line.index(after: numEnd)
        }
        guard digits <= 3, numEnd < line.endIndex else { return nil }
        guard line[numEnd] == "." || line[numEnd] == ")" else { return nil }
        let after = line.index(after: numEnd)
        guard after < line.endIndex, line[after] == " " || line[after] == "\t" else { return nil }
        let text = String(line[after...]).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, let ordinal = Int(line[idx..<numEnd]) else { return nil }
        return (indent, ordinal, text)
    }

    return nil
}

/// Resolves a list item's nesting depth from its indent width using a stack
/// of seen indents: shallower indents pop back to their level, and an indent
/// at least 2 columns deeper than the current level pushes a new one.
private func resolvedDepth(indent: Int, stack: inout [Int]) -> Int {
    while let last = stack.last, indent < last { stack.removeLast() }
    if let last = stack.last {
        if indent >= last + 2 { stack.append(indent) }
    } else {
        stack.append(indent)
    }
    return min(stack.count - 1, 5)
}

/// Splits a table row into trimmed cells. One leading/trailing outer pipe is
/// stripped, and `\|` escapes a literal pipe inside a cell.
private func splitTableRow(_ line: String) -> [String] {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return [] }

    var cells: [String] = []
    var current = ""
    var escaped = false
    for ch in trimmed {
        if escaped {
            if ch != "|" { current.append("\\") }
            current.append(ch)
            escaped = false
        } else if ch == "\\" {
            escaped = true
        } else if ch == "|" {
            cells.append(current)
            current = ""
        } else {
            current.append(ch)
        }
    }
    if escaped { current.append("\\") }
    cells.append(current)

    if trimmed.hasPrefix("|") { cells.removeFirst() }
    if cells.count > 0, trimmed.hasSuffix("|"), cells.last?.isEmpty == true { cells.removeLast() }
    return cells.map { $0.trimmingCharacters(in: .whitespaces) }
}

/// Parses a table delimiter row (`| --- | :---: | ---: |`) into per-column
/// alignments, or nil if the line isn't a valid delimiter row.
private func tableAlignments(_ line: String) -> [MarkdownTableAlignment]? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.contains("|"), trimmed.contains("-") else { return nil }
    guard trimmed.allSatisfy({ $0 == "|" || $0 == "-" || $0 == ":" || $0 == " " || $0 == "\t" }) else { return nil }

    let cells = splitTableRow(trimmed)
    guard !cells.isEmpty else { return nil }

    var alignments: [MarkdownTableAlignment] = []
    for cell in cells {
        var body = Substring(cell)
        let leadingColon = body.hasPrefix(":")
        if leadingColon { body = body.dropFirst() }
        let trailingColon = body.hasSuffix(":")
        if trailingColon { body = body.dropLast() }
        guard !body.isEmpty, body.allSatisfy({ $0 == "-" }) else { return nil }
        if leadingColon && trailingColon {
            alignments.append(.center)
        } else if trailingColon {
            alignments.append(.trailing)
        } else {
            alignments.append(.leading)
        }
    }
    return alignments
}

// MARK: - Parser

/// Parses markdown content into block segments: prose, fenced code blocks,
/// images, headings, block quotes, lists, and pipe tables.
///
/// Prose segments retain inline markdown (`**bold**`, `` `code` ``, `[links]()`,
/// etc.) that `AttributedString(markdown:)` handles natively; heading, quote,
/// list-item, and table-cell text does the same for the renderer.
///
/// Markdown images (`![alt](url)`) are extracted from prose as `.image`
/// segments and rendered separately as async-loaded images. (Inside list
/// items, quotes, and table cells they stay inline text.)
///
/// During streaming, an unclosed fence at the end of content is still emitted
/// as a `.codeBlock` so the user sees code as it arrives; a table header whose
/// delimiter row hasn't streamed in yet renders as prose until it does.
func parseMarkdownSegments(_ content: String, isStreaming: Bool = false) -> [MarkdownSegment] {
    guard !content.isEmpty else { return [] }

    let lines = content.components(separatedBy: "\n")
    var segments: [MarkdownSegment] = []
    var currentProse: [String] = []
    var currentCode: [String] = []
    var codeLanguage: String?
    var insideCodeBlock = false

    func flushProse() {
        guard !currentProse.isEmpty else { return }
        let text = currentProse.joined(separator: "\n")
        currentProse = []
        segments.append(contentsOf: splitProseAndImages(text))
    }

    /// Consumes consecutive quote lines starting at `start`, grouping equal
    /// depths into segments. Returns the index of the first non-quote line.
    func collectBlockQuote(from start: Int) -> Int {
        var i = start
        var currentDepth = 0
        var quoteLines: [String] = []

        func flushQuote() {
            guard !quoteLines.isEmpty else { return }
            let text = quoteLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            quoteLines = []
            if !text.isEmpty {
                segments.append(.blockQuote(level: currentDepth, text: text))
            }
        }

        while i < lines.count, let (depth, content) = quoteLine(lines[i]) {
            if depth != currentDepth {
                flushQuote()
                currentDepth = depth
            }
            quoteLines.append(content)
            i += 1
        }
        flushQuote()
        return i
    }

    /// Consumes a contiguous list starting at `start`. A single blank line
    /// between items keeps the list together; two end it. A non-blank,
    /// non-item line indented ≥ 2 columns continues the previous item.
    /// Returns the index of the first line past the list.
    func collectList(from start: Int) -> Int {
        var i = start
        var items: [MarkdownListItem] = []
        var indentStack: [Int] = []
        var pendingBlank = false

        while i < lines.count {
            let line = lines[i]
            if let (indent, ordinal, text) = listItemLine(line) {
                let depth = resolvedDepth(indent: indent, stack: &indentStack)
                items.append(MarkdownListItem(text: text, depth: depth, ordinal: ordinal))
                pendingBlank = false
                i += 1
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if pendingBlank { break }
                pendingBlank = true
                i += 1
            } else if !pendingBlank, !line.hasPrefix("```"), leadingWhitespaceWidth(line) >= 2, !items.isEmpty {
                items[items.count - 1].text += "\n" + line.trimmingCharacters(in: .whitespaces)
                i += 1
            } else {
                break
            }
        }

        if !items.isEmpty {
            segments.append(.list(items: items))
        }
        return i
    }

    /// Attempts to parse a pipe table whose header row is at `start` and
    /// delimiter row at `start + 1`. Returns the table segment and the index
    /// past the last row, or nil if this isn't a table.
    func parseTable(at start: Int) -> (segment: MarkdownSegment, next: Int)? {
        let headerLine = lines[start]
        guard headerLine.contains("|"), start + 1 < lines.count,
              let alignments = tableAlignments(lines[start + 1]) else { return nil }
        let header = splitTableRow(headerLine)
        guard !header.isEmpty, header.count == alignments.count else { return nil }

        var rows: [[String]] = []
        var i = start + 2
        while i < lines.count {
            let line = lines[i]
            guard line.contains("|"), !line.hasPrefix("```"),
                  !line.trimmingCharacters(in: .whitespaces).isEmpty else { break }
            var cells = splitTableRow(line)
            if cells.count < header.count {
                cells.append(contentsOf: Array(repeating: "", count: header.count - cells.count))
            } else if cells.count > header.count {
                cells = Array(cells.prefix(header.count))
            }
            rows.append(cells)
            i += 1
        }
        return (.table(header: header, alignments: alignments, rows: rows), i)
    }

    var i = 0
    while i < lines.count {
        let line = lines[i]

        if insideCodeBlock {
            if line.hasPrefix("```") {
                insideCodeBlock = false
                let code = currentCode.joined(separator: "\n")
                segments.append(.codeBlock(language: codeLanguage, code: code))
                currentCode = []
                codeLanguage = nil
            } else {
                currentCode.append(line)
            }
            i += 1
            continue
        }

        if line.hasPrefix("```") {
            flushProse()
            insideCodeBlock = true
            let langTag = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            codeLanguage = langTag.isEmpty ? nil : langTag
            currentCode = []
            i += 1
            continue
        }

        if let (level, text) = headingLine(line) {
            flushProse()
            segments.append(.heading(level: level, text: text))
            i += 1
            continue
        }

        if quoteLine(line) != nil {
            flushProse()
            i = collectBlockQuote(from: i)
            continue
        }

        if listItemLine(line) != nil {
            flushProse()
            i = collectList(from: i)
            continue
        }

        if let (table, next) = parseTable(at: i) {
            flushProse()
            segments.append(table)
            i = next
            continue
        }

        currentProse.append(line)
        i += 1
    }

    // Flush remaining content
    if insideCodeBlock {
        let code = currentCode.joined(separator: "\n")
        if isStreaming || !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.append(.codeBlock(language: codeLanguage, code: code))
        } else {
            currentProse.append("```\(codeLanguage ?? "")")
            currentProse.append(contentsOf: currentCode)
            flushProse()
        }
    } else {
        flushProse()
    }

    return segments
}
