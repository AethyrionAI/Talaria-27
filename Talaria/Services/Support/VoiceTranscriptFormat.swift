import Foundation

/// The wire shape of the **synthesized voice-session turn** — the one message
/// in this app that is not the user speaking.
///
/// `ChatStore.appendVoiceTranscript` POSTs a completed voice session to the
/// backend as an ordinary text turn so the agent has the exchange as context.
/// That turn is a TRANSCRIPT: a bracketed header, then one `User:` or
/// `Talaria:` line per spoken turn. Every other message the backend sees is
/// something the user typed.
///
/// **Why the shape needs a name (#340 bar 340-F3, Owen's ruling of
/// 2026-09-04).** #340's fallback resolves an empty `due` argument out of the
/// CURRENT TURN's user text. On the voice path that text is the whole
/// transcript, so a `Talaria:` line — the ASSISTANT's own words — could set the
/// due date of a reminder the user asked for with no time at all. That is
/// #340's founding wrong-value shape reached through a different door: not a
/// missing date, but somebody else's date. The preconditions are narrow (the
/// brain has to resolve local, and a tool call has to happen on the synthesized
/// turn) and the failure is silent, which is exactly the combination that
/// argues for closing it structurally rather than watching for it.
///
/// **Two readers, one definition.** `voiceTranscriptTurnText` writes this
/// shape and `LocalChatBackend.beltUserText` reads it back; a second copy of
/// the header string would drift the first time either side was edited, and
/// the reader would then silently stop recognising the writer's output —
/// failing OPEN, with the assistant's lines mined again and nothing red.
enum VoiceTranscriptFormat {

    /// The header line `voiceTranscriptTurnText` opens with. It is the marker
    /// that identifies a synthesized transcript, so a user who happens to type
    /// `User: remind me at 4` is never treated as one.
    static let header = "[Voice session transcript — shared for context. No reply needed.]"

    /// The per-line speaker labels.
    static let userPrefix = "User: "
    static let assistantPrefix = "Talaria: "

    /// The USER's own spoken words inside a synthesized transcript, joined by
    /// newlines — or `nil` when `text` is not one of these transcripts at all.
    ///
    /// **`nil` and "" are different answers and callers must keep them so.**
    /// `nil` means *this is an ordinary message, use it unchanged*; `""` means
    /// *this IS a transcript and the user said nothing in it* — a session of
    /// assistant lines only, whose correct belt text is empty rather than the
    /// assistant's speech.
    ///
    /// The `User: ` label is stripped: what the fallback wants to read is the
    /// sentence, and a leading label is one more token for `NSDataDetector` to
    /// walk past.
    static func userLines(in text: String) -> String? {
        guard text.hasPrefix(header) else { return nil }
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.hasPrefix(userPrefix) }
            .map { $0.dropFirst(userPrefix.count) }
        return lines.joined(separator: "\n")
    }
}
