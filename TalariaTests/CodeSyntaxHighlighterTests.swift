import Foundation
import Testing
@testable import Talaria

/// Lane B — code-block syntax scanning: keyword/string/comment/number
/// classification per language profile, and the conservative generic
/// fallback for unknown languages.
struct CodeSyntaxHighlighterTests {

    private func spans(ofKind kind: CodeTokenKind, in code: String, language: String?) -> [String] {
        CodeSyntaxHighlighter.tokens(in: code, language: language)
            .filter { $0.kind == kind }
            .map { String(code[$0.range]) }
    }

    // MARK: Swift

    @Test func swiftKeywordsStringsNumbers() {
        let code = #"let count = 42\#nfunc greet() { return "hi" }"#
        #expect(spans(ofKind: .keyword, in: code, language: "swift") == ["let", "func", "return"])
        #expect(spans(ofKind: .number, in: code, language: "swift") == ["42"])
        #expect(spans(ofKind: .string, in: code, language: "swift") == ["\"hi\""])
    }

    @Test func swiftLineAndBlockComments() {
        let code = "// line note\nlet x = 1 /* inline\nblock */"
        #expect(spans(ofKind: .comment, in: code, language: "swift") == ["// line note", "/* inline\nblock */"])
    }

    @Test func keywordInsideIdentifierIsNotFlagged() {
        // `letter` contains `let`; `variance` contains `var`.
        let code = "letter + variance"
        #expect(spans(ofKind: .keyword, in: code, language: "swift").isEmpty)
    }

    @Test func commentMarkerInsideStringIsString() {
        let code = #"let url = "https://example.com""#
        #expect(spans(ofKind: .comment, in: code, language: "swift").isEmpty)
        #expect(spans(ofKind: .string, in: code, language: "swift") == ["\"https://example.com\""])
    }

    @Test func escapedQuoteStaysInsideString() {
        let code = #"print("a \" b")"#
        #expect(spans(ofKind: .string, in: code, language: "swift") == [#""a \" b""#])
    }

    // MARK: Python

    @Test func pythonHashCommentAndTripleString() {
        let code = "# setup\ndef f():\n    \"\"\"doc\nstring\"\"\"\n    return None"
        #expect(spans(ofKind: .comment, in: code, language: "python") == ["# setup"])
        #expect(spans(ofKind: .string, in: code, language: "python") == ["\"\"\"doc\nstring\"\"\""])
        #expect(spans(ofKind: .keyword, in: code, language: "python") == ["def", "return", "None"])
    }

    // MARK: JavaScript / TypeScript

    @Test func javascriptTemplateLiteralSpansLines() {
        let code = "const t = `line one\nline two`;"
        #expect(spans(ofKind: .string, in: code, language: "js") == ["`line one\nline two`"])
        #expect(spans(ofKind: .keyword, in: code, language: "js") == ["const"])
    }

    // MARK: JSON

    @Test func jsonLiteralsAndNumbers() {
        let code = #"{"ok": true, "missing": null, "count": 3}"#
        #expect(spans(ofKind: .keyword, in: code, language: "json") == ["true", "null"])
        #expect(spans(ofKind: .number, in: code, language: "json") == ["3"])
    }

    // MARK: Bash

    @Test func bashCommentAndKeywords() {
        let code = "# deploy\nif [ -f x ]; then\n  echo \"ok\"\nfi"
        #expect(spans(ofKind: .comment, in: code, language: "bash") == ["# deploy"])
        #expect(spans(ofKind: .keyword, in: code, language: "bash") == ["if", "then", "echo", "fi"])
    }

    // MARK: Generic fallback

    @Test func unknownLanguageOnlyFlagsStringsAndNumbers() {
        let code = "let x = \"text\" // 42"
        let tokens = CodeSyntaxHighlighter.tokens(in: code, language: "brainfuck")
        // No keyword or comment guessing on unidentified languages.
        #expect(tokens.allSatisfy { $0.kind == .string || $0.kind == .number })
        #expect(spans(ofKind: .string, in: code, language: "brainfuck") == ["\"text\""])
        #expect(spans(ofKind: .number, in: code, language: "brainfuck") == ["42"])
    }

    @Test func nilLanguageUsesGenericProfile() {
        let code = "print(\"hello\")"
        #expect(spans(ofKind: .keyword, in: code, language: nil).isEmpty)
        #expect(spans(ofKind: .string, in: code, language: nil) == ["\"hello\""])
    }

    @Test func numberAfterIdentifierIsNotANumber() {
        #expect(spans(ofKind: .number, in: "value2 + 7", language: "swift") == ["7"])
    }

    @Test func hexAndUnderscoreNumbersScanWhole() {
        #expect(spans(ofKind: .number, in: "0xFF_EC + 1_000", language: "swift") == ["0xFF_EC", "1_000"])
    }

    @Test func tokensCoverDisjointRangesInOrder() {
        let code = "let s = \"a\" // done"
        let tokens = CodeSyntaxHighlighter.tokens(in: code, language: "swift")
        for (a, b) in zip(tokens, tokens.dropFirst()) {
            #expect(a.range.upperBound <= b.range.lowerBound)
        }
    }
}
