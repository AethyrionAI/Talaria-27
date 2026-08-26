import Foundation

/// #330: `CaseIterable` so the `/usage` diagnostic's per-sender census
/// enumerates the cases rather than hardcoding a list — a sixth case then
/// shows up in the report automatically instead of being silently omitted,
/// which is the same failure mode the two predicates below were written to
/// stop.
enum MessageSender: String, Codable, Hashable, Sendable, CaseIterable {
    case user
    case hermes
    case system
    case voiceUser = "voice_user"
    case voiceHermes = "voice_hermes"

    /// #275: the senders that represent a turn the USER produced — typed
    /// (`.user`) and DICTATED (`.voiceUser`).
    ///
    /// **Every backwards search for "the turn that produced this reply" must
    /// use this**, not `== .user`. Four separate sites matched the typed case
    /// alone (`regenerateReply`, `retryMessage`, `/retry`, `/undo`), so on a
    /// mixed voice/text thread the scan skipped the dictated turn, found an
    /// EARLIER typed one, truncated far more history than the user asked for
    /// and re-sent the wrong prompt — data destruction, not a cosmetic miss.
    /// One predicate means a sixth sender case has to answer this question
    /// explicitly instead of being silently excluded four times over.
    ///
    /// Not the same question as "is this an editable composed turn": Edit &
    /// Resend stays `.user`-only by decision (#44), because a voice-transcript
    /// row is a record of something spoken, not a draft.
    var isUserAuthored: Bool {
        self == .user || self == .voiceUser
    }

    /// #280: the senders that represent a turn the ASSISTANT produced —
    /// streamed (`.hermes`) and SPOKEN (`.voiceHermes`).
    ///
    /// The mirror of `isUserAuthored`, and it exists for the same reason. A
    /// voice-only thread's replies are `.voiceHermes`, so the card
    /// generator's `== .hermes` eligibility test rejected the whole thread —
    /// it early-returned at its own guard and the conversation kept the
    /// `"Hermes"` placeholder forever, which the drawer then rendered as its
    /// own preview printed on both lines.
    ///
    /// **Not the same question as "did this reply stream".** `.voiceHermes`
    /// rows never streamed and carry no reasoning, so
    /// `condensePendingReasoning` stays `.hermes`-only by decision (#280) —
    /// as does `recordLocalOriginAfterSettledTurn`, whose `.hermes` count is
    /// #190B's born-local semantics and not an assistant-authorship test.
    /// A sixth sender case has to answer THIS question explicitly.
    var isAgentAuthored: Bool {
        self == .hermes || self == .voiceHermes
    }
}
