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
private let markdownImagePattern = /!\[([^\]]*)\]\(([^)]+)\)/

/// Image file extensions the parser recognizes.
private let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "svg"]

/// Known image hosting domains (always treated as images regardless of extension).
private let imageHostPatterns = ["fal.media", "fal-cdn", "replicate.delivery", "oaidalleapiprodscus"]

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

/// Extracts markdown images from a prose line, returning the remaining text
/// and any image segments found.
private func extractImages(from text: String) -> (cleanedText: String, images: [(url: URL, alt: String)]) {
    var images: [(url: URL, alt: String)] = []
    var cleaned = text

    for match in text.matches(of: markdownImagePattern).reversed() {
        let alt = String(match.1)
        let urlString = String(match.2)

        guard isImageURL(urlString), let url = URL(string: urlString) else { continue }

        images.insert((url: url, alt: alt), at: 0)
        cleaned.replaceSubrange(match.range, with: "")
    }

    return (cleaned, images)
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

        // Extract images from the prose block
        let (cleaned, images) = extractImages(from: text)

        let trimmedCleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCleaned.isEmpty {
            segments.append(.prose(text: trimmedCleaned))
        }
        for img in images {
            segments.append(.image(url: img.url, altText: img.alt))
        }
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
