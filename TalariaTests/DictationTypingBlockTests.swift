import Foundation
import Testing

/// #407 — text typed while dictation is live was DISCARDED on the next
/// transcript tick: `mergedDictationText` recomputes from a base snapshot
/// captured at dictation start, so interleaved typing predates nothing and
/// vanishes. Owen ruled BLOCK TYPING WHILE DICTATING (2026-08-24): the
/// composer goes read-only for exactly the dictation window.
///
/// The mechanism is one modifier — SwiftUI's `disabled` gates USER
/// interaction only, so the dictation merge's programmatic writes to the
/// `text` binding keep flowing (407-B) and typing returns the instant
/// `isListening` flips (407-C, the same flag, no second mechanism).
struct DictationTypingBlockTests {

    /// 407-A, #399-shape: the composer editor carries the dictation gate.
    /// Scoped to the TextEditor's own modifier chain so a `.disabled`
    /// somewhere else in the file cannot satisfy it vacuously.
    @Test func composerEditorIsDisabledForExactlyTheDictationWindow() throws {
        let barPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Talaria/Features/Chat/ChatInputBar.swift")
        let source = try #require(
            try? String(contentsOf: barPath, encoding: .utf8),
            "ChatInputBar.swift unreadable — this pin must fail loudly, not vacuously"
        )
        guard let editorRange = source.range(of: "TextEditor(text: $text)") else {
            Issue.record("the composer TextEditor is gone — re-point this pin at its successor")
            return
        }
        let modifierChain = String(source[editorRange.upperBound...].prefix(900))
        #expect(
            modifierChain.contains(".disabled(speechService.isListening)"),
            "407-A: typing during dictation must be blocked at the editor, for exactly the listening window"
        )
    }
}
