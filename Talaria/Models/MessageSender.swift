import Foundation

enum MessageSender: String, Codable, Hashable, Sendable {
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
}
