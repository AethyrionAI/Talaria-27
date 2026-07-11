import SwiftUI

/// Token kinds the lightweight code scanner distinguishes.
enum CodeTokenKind: Equatable {
    case keyword
    case string
    case comment
    case number
}

/// A classified span of a code block. Anything not covered by a token renders
/// in the base code color.
struct CodeToken: Equatable {
    let kind: CodeTokenKind
    let range: Range<String.Index>
}

/// Lightweight, dependency-free syntax highlighting for fenced code blocks.
///
/// A single linear scan classifies comments, strings, numbers, and keywords
/// per language profile (resolved from the fence's language tag). Unknown
/// languages fall back to a generic profile — double-quoted strings and
/// numbers only — so prose-ish content never gets false keyword coloring.
/// The scan is O(n) and re-runs safely on every streaming delta.
enum CodeSyntaxHighlighter {

    /// Scans `code` and returns classified token spans in source order.
    static func tokens(in code: String, language: String?) -> [CodeToken] {
        let profile = LanguageProfile.profile(for: language)
        var tokens: [CodeToken] = []
        var i = code.startIndex
        // Tracks whether the previous character can end an identifier, so a
        // digit run inside `abc123` is not flagged as a number.
        var prevWasWordChar = false

        while i < code.endIndex {
            let ch = code[i]
            let rest = code[i...]

            if profile.lineComments.contains(where: { rest.hasPrefix($0) }) {
                let end = rest.firstIndex(of: "\n") ?? code.endIndex
                tokens.append(CodeToken(kind: .comment, range: i..<end))
                i = end
                prevWasWordChar = false
                continue
            }

            if let block = profile.blockComment, rest.hasPrefix(block.open) {
                let bodyStart = code.index(i, offsetBy: block.open.count)
                if let close = code.range(of: block.close, range: bodyStart..<code.endIndex) {
                    tokens.append(CodeToken(kind: .comment, range: i..<close.upperBound))
                    i = close.upperBound
                } else {
                    tokens.append(CodeToken(kind: .comment, range: i..<code.endIndex))
                    i = code.endIndex
                }
                prevWasWordChar = false
                continue
            }

            if let triple = profile.tripleQuotes.first(where: { rest.hasPrefix($0) }) {
                let bodyStart = code.index(i, offsetBy: triple.count)
                if let close = code.range(of: triple, range: bodyStart..<code.endIndex) {
                    tokens.append(CodeToken(kind: .string, range: i..<close.upperBound))
                    i = close.upperBound
                } else {
                    tokens.append(CodeToken(kind: .string, range: i..<code.endIndex))
                    i = code.endIndex
                }
                prevWasWordChar = false
                continue
            }

            if profile.stringDelimiters.contains(ch) {
                let multiline = profile.multilineStringDelimiters.contains(ch)
                var j = code.index(after: i)
                while j < code.endIndex {
                    let cj = code[j]
                    if cj == "\\" {
                        j = code.index(after: j)
                        if j < code.endIndex { j = code.index(after: j) }
                        continue
                    }
                    if cj == ch {
                        j = code.index(after: j)
                        break
                    }
                    // An unterminated single-line string stops at the newline.
                    if cj == "\n" && !multiline { break }
                    j = code.index(after: j)
                }
                tokens.append(CodeToken(kind: .string, range: i..<j))
                i = j
                prevWasWordChar = false
                continue
            }

            if ch.isWholeNumber && !prevWasWordChar {
                var j = code.index(after: i)
                while j < code.endIndex {
                    let cj = code[j]
                    // Letters cover hex/exponent/suffix forms (0x1F, 1e9, 10u).
                    if cj.isLetter || cj.isWholeNumber || cj == "." || cj == "_" {
                        j = code.index(after: j)
                    } else {
                        break
                    }
                }
                tokens.append(CodeToken(kind: .number, range: i..<j))
                i = j
                prevWasWordChar = true
                continue
            }

            if ch.isLetter || ch == "_" || ch == "$" {
                var j = code.index(after: i)
                while j < code.endIndex {
                    let cj = code[j]
                    if cj.isLetter || cj.isWholeNumber || cj == "_" || cj == "$" {
                        j = code.index(after: j)
                    } else {
                        break
                    }
                }
                if profile.keywords.contains(String(code[i..<j])) {
                    tokens.append(CodeToken(kind: .keyword, range: i..<j))
                }
                i = j
                prevWasWordChar = true
                continue
            }

            prevWasWordChar = false
            i = code.index(after: i)
        }

        return tokens
    }

    /// Renders `code` as an AttributedString with token spans colored from
    /// the live theme palette; everything else uses `baseColor`.
    @MainActor
    static func highlighted(_ code: String, language: String?, baseColor: Color) -> AttributedString {
        var result = AttributedString()
        var cursor = code.startIndex

        func appendPlain(_ range: Range<String.Index>) {
            guard !range.isEmpty else { return }
            var piece = AttributedString(String(code[range]))
            piece.foregroundColor = baseColor
            result += piece
        }

        for token in tokens(in: code, language: language) {
            appendPlain(cursor..<token.range.lowerBound)
            var piece = AttributedString(String(code[token.range]))
            piece.foregroundColor = color(for: token.kind)
            result += piece
            cursor = token.range.upperBound
        }
        appendPlain(cursor..<code.endIndex)

        return result
    }

    @MainActor
    private static func color(for kind: CodeTokenKind) -> Color {
        switch kind {
        case .keyword: return Design.Brand.accentBright
        case .string: return Design.Brand.forge
        case .comment: return Design.Colors.dimForeground
        case .number: return Design.Brand.accent
        }
    }
}

// MARK: - Language profiles

private struct LanguageProfile {
    var keywords: Set<String> = []
    var lineComments: [String] = []
    var blockComment: (open: String, close: String)? = nil
    var stringDelimiters: Set<Character> = []
    var multilineStringDelimiters: Set<Character> = []
    var tripleQuotes: [String] = []

    static func profile(for language: String?) -> LanguageProfile {
        switch language?.lowercased() {
        case "swift":
            return LanguageProfile(
                keywords: [
                    "actor", "any", "as", "associatedtype", "async", "await", "break", "case",
                    "catch", "class", "continue", "convenience", "default", "defer", "deinit",
                    "do", "else", "enum", "extension", "fallthrough", "false", "fileprivate",
                    "final", "for", "func", "guard", "if", "import", "in", "indirect", "init",
                    "inout", "internal", "is", "lazy", "let", "mutating", "nil", "nonisolated",
                    "open", "operator", "override", "private", "protocol", "public", "repeat",
                    "required", "rethrows", "return", "self", "Self", "some", "static", "struct",
                    "subscript", "super", "switch", "throw", "throws", "true", "try", "typealias",
                    "unowned", "var", "weak", "where", "while"
                ],
                lineComments: ["//"],
                blockComment: (open: "/*", close: "*/"),
                stringDelimiters: ["\""],
                tripleQuotes: ["\"\"\""]
            )
        case "python", "py":
            return LanguageProfile(
                keywords: [
                    "False", "None", "True", "and", "as", "assert", "async", "await", "break",
                    "case", "class", "continue", "def", "del", "elif", "else", "except",
                    "finally", "for", "from", "global", "if", "import", "in", "is", "lambda",
                    "match", "nonlocal", "not", "or", "pass", "raise", "return", "self", "try",
                    "while", "with", "yield"
                ],
                lineComments: ["#"],
                stringDelimiters: ["\"", "'"],
                tripleQuotes: ["\"\"\"", "'''"]
            )
        case "javascript", "js", "typescript", "ts", "jsx", "tsx":
            return LanguageProfile(
                keywords: [
                    "abstract", "any", "as", "async", "await", "boolean", "break", "case",
                    "catch", "class", "const", "continue", "debugger", "declare", "default",
                    "delete", "do", "else", "enum", "export", "extends", "false", "finally",
                    "for", "function", "if", "implements", "import", "in", "instanceof",
                    "interface", "keyof", "let", "namespace", "never", "new", "null", "number",
                    "of", "private", "protected", "public", "readonly", "return", "static",
                    "string", "super", "switch", "this", "throw", "true", "try", "type",
                    "typeof", "undefined", "unknown", "var", "void", "while", "with", "yield"
                ],
                lineComments: ["//"],
                blockComment: (open: "/*", close: "*/"),
                stringDelimiters: ["\"", "'", "`"],
                multilineStringDelimiters: ["`"]
            )
        case "json":
            return LanguageProfile(
                keywords: ["false", "null", "true"],
                stringDelimiters: ["\""]
            )
        case "bash", "sh", "shell", "zsh", "console":
            return LanguageProfile(
                keywords: [
                    "alias", "break", "case", "cd", "continue", "declare", "do", "done", "echo",
                    "elif", "else", "esac", "eval", "exec", "exit", "export", "fi", "for",
                    "function", "if", "in", "local", "printf", "read", "readonly", "return",
                    "select", "set", "shift", "source", "test", "then", "time", "trap", "unset",
                    "until", "while"
                ],
                lineComments: ["#"],
                stringDelimiters: ["\"", "'"]
            )
        case "yaml", "yml":
            return LanguageProfile(
                keywords: ["false", "no", "null", "true", "yes"],
                lineComments: ["#"],
                stringDelimiters: ["\"", "'"]
            )
        case "c", "cpp", "c++", "h", "hpp", "objc", "objective-c", "java", "kotlin", "kt",
             "go", "golang", "rust", "rs", "cs", "csharp", "php":
            return LanguageProfile(
                keywords: [
                    "auto", "bool", "break", "case", "catch", "char", "class", "const",
                    "continue", "default", "defer", "delete", "do", "double", "else", "enum",
                    "extern", "false", "final", "finally", "float", "fn", "for", "func", "go",
                    "goto", "if", "impl", "import", "in", "inline", "int", "interface", "let",
                    "long", "match", "mut", "namespace", "new", "nil", "null", "nullptr",
                    "override", "package", "private", "protected", "pub", "public", "return",
                    "self", "short", "signed", "sizeof", "static", "struct", "super", "switch",
                    "template", "this", "throw", "throws", "trait", "true", "try", "type",
                    "typedef", "typename", "union", "unsigned", "use", "using", "var",
                    "virtual", "void", "volatile", "when", "where", "while"
                ],
                lineComments: ["//"],
                blockComment: (open: "/*", close: "*/"),
                stringDelimiters: ["\"", "'"]
            )
        default:
            // Unknown / untagged code: strings + numbers only. No keyword or
            // comment guesses on content we can't identify.
            return LanguageProfile(stringDelimiters: ["\""])
        }
    }
}
