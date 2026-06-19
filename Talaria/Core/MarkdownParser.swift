import Foundation

/// A segment of parsed markdown content — prose, fenced code block, or an image.
enum MarkdownSegment: Identifiable {
    case prose(id: UUID = UUID(), text: String)
    case codeBlock(id: UUID = UUID(), language: String?, code: String)
    case image(id: UUID = UUID(), url: URL, altText: String)

    var id: UUID {
        switch self {
        case .prose(let id, _): return id
        case .codeBlock(let id, _, _): return id
        case .image(let id, _, _): return id
        }
    }
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

/// Parses markdown content into alternating prose, fenced code block, and image segments.
///
/// Prose segments retain inline markdown (`**bold**`, `` `code` ``, `[links]()`, etc.)
/// that `AttributedString(markdown:)` handles natively.
///
/// Markdown images (`![alt](url)`) are extracted as `.image` segments and rendered
/// separately as async-loaded images.
///
/// During streaming, an unclosed fence at the end of content is still emitted as a
/// `.codeBlock` so the user sees code as it arrives.
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

    for line in lines {
        if !insideCodeBlock {
            if line.hasPrefix("```") {
                flushProse()
                insideCodeBlock = true
                let langTag = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                codeLanguage = langTag.isEmpty ? nil : langTag
                currentCode = []
            } else {
                currentProse.append(line)
            }
        } else {
            if line.hasPrefix("```") {
                insideCodeBlock = false
                let code = currentCode.joined(separator: "\n")
                segments.append(.codeBlock(language: codeLanguage, code: code))
                currentCode = []
                codeLanguage = nil
            } else {
                currentCode.append(line)
            }
        }
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
