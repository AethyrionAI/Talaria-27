import Foundation

/// Row-level summary of a stored local session (#190) — everything the
/// sessions drawer needs, denormalized so listing never decodes transcripts.
struct LocalSessionSummary: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let preview: String?
    let messageCount: Int
    let createdAt: Date
    let lastActivity: Date
}

/// #190: keyed, durable storage for standalone (on-device) chat sessions —
/// the real store behind `LocalChatBackend`'s sessions surface. The
/// UserDefaults single-slot conversation cache STAYS the kill/relaunch
/// restore path; this store is what makes "New" stop destroying history.
///
/// Also carries the last-known snapshot of server-side sessions (remote
/// stubs), so the drawer can keep a user's Hermes history visible — dimmed,
/// with a reason — after the host is no longer configured, instead of lying
/// by omission.
@MainActor
protocol LocalSessionStoring {
    /// Insert-or-update, keyed by `conversation.id` — running twice with the
    /// same conversation must never produce two rows (the #190 migration's
    /// idempotency rides on this).
    func upsertSession(_ conversation: Conversation)

    /// Stored sessions, most recent `lastActivity` first.
    func sessionSummaries() -> [LocalSessionSummary]

    /// Full transcript for a stored session; nil when the id is unknown.
    func conversation(withID id: UUID) -> Conversation?

    func hasSession(withID id: UUID) -> Bool

    /// Replaces the remote-session snapshot with `infos` — the last list a
    /// live host actually returned. Sessions the host no longer lists drop
    /// out; the snapshot never invents rows.
    func recordRemoteSessionStubs(_ infos: [HermesSessionInfo])

    /// The recorded remote-session snapshot, most recent `lastActive` first.
    func remoteSessionStubs() -> [HermesSessionInfo]
}
