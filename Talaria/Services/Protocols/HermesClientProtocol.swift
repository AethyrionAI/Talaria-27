import Foundation

/// Lightweight summary of a Hermes session, returned by `listSessions()`.
/// Service-layer DTO — the UI maps this to its own `SessionSummary`.
struct HermesSessionInfo: Identifiable, Hashable, Sendable {
    let id: String
    let title: String?
    let preview: String?
    let model: String?
    let source: String?
    let messageCount: Int
    let lastActive: Date?
    let isActive: Bool
    /// Lane M (#114): the backend profile this session lives on — session
    /// ids are server-scoped. Nil from single-backend clients (local brain,
    /// mocks, profile-less constructions).
    let profileID: UUID?
    /// Display name of that profile, carried for the drawer's foreign-host
    /// badge so the UI never re-resolves ids.
    let profileName: String?
    /// #122: cumulative billing/usage from the Sessions LIST/DETAIL endpoints
    /// (a cost surface, never a context meter — see #25). Nil when the wire
    /// omitted it (old/sparse session) or the client has no such data (local
    /// brain, mocks) — an absent value hides the cost row, never shows zeros.
    let usage: SessionUsage?
    /// #190: false only for remote-stub rows — sessions the drawer still
    /// shows (dimmed) but no configured host can open right now.
    let isResumable: Bool
    /// Honest one-line reason shown on an unresumable row. Nil while
    /// `isResumable` is true.
    let unresumableReason: String?

    init(
        id: String,
        title: String?,
        preview: String?,
        model: String?,
        source: String?,
        messageCount: Int,
        lastActive: Date?,
        isActive: Bool,
        profileID: UUID? = nil,
        profileName: String? = nil,
        usage: SessionUsage? = nil,
        isResumable: Bool = true,
        unresumableReason: String? = nil
    ) {
        self.id = id
        self.title = title
        self.preview = preview
        self.model = model
        self.source = source
        self.messageCount = messageCount
        self.lastActive = lastActive
        self.isActive = isActive
        self.profileID = profileID
        self.profileName = profileName
        self.usage = usage
        self.isResumable = isResumable
        self.unresumableReason = unresumableReason
    }

    /// #190: the same session, re-marked as unopenable — how the router
    /// surfaces remote stubs once no configured host can resume them.
    func asUnresumable(reason: String) -> HermesSessionInfo {
        HermesSessionInfo(
            id: id,
            title: title,
            preview: preview,
            model: model,
            source: source,
            messageCount: messageCount,
            lastActive: lastActive,
            isActive: false,
            profileID: profileID,
            profileName: profileName,
            usage: usage,
            isResumable: false,
            unresumableReason: reason
        )
    }
}

@MainActor
protocol HermesClientProtocol {
    var connectionStatus: ConnectionStatus { get }
    var currentConversation: Conversation? { get }
    func connect() async
    func disconnect() async
    func send(message: String, attachments: [PendingAttachment], clientMessageID: UUID) async -> Message
    func sendStreaming(message: String, attachments: [PendingAttachment], clientMessageID: UUID) -> AsyncStream<StreamingUpdate>
    func loadConversation() async -> Conversation
    func clearConversation() async throws -> Conversation

    /// Lists the model identifiers the connected host exposes (e.g. /v1/models).
    func availableModels() async throws -> [String]

    /// Requests a model switch. Per the Hermes Sessions API this applies to the
    /// NEXT session, so callers should start a fresh session for it to take effect.
    /// Returns the host's response text — it carries the authoritative
    /// "Context: N tokens" for the switched model (#4). Nil when the client
    /// has no response to report.
    @discardableResult
    func switchModel(_ identifier: String) async throws -> String?

    /// Lists recent sessions from the host's Sessions API.
    func listSessions() async throws -> [HermesSessionInfo]

    /// Opens an existing session: adopts its id and returns its message history
    /// as a Conversation. New messages continue that thread.
    func openSession(_ id: String) async throws -> Conversation

    /// Re-fetches the current session's messages from the host (GET /messages)
    /// so a run that completed while the stream was dropped can be reconciled.
    /// Returns nil for clients without a server-backed session (relay / mock).
    func reconcileFromServer() async -> Conversation?

    /// #192: the consumer walked away from the in-flight run (clear, session
    /// switch, a continued-send expiring) — NOT the explicit Stop tap.
    /// Clients holding per-run state release it here so an abandoned stream
    /// can never wedge later routing; the default is a no-op. Sessions-plane
    /// parity (#283 review ruling): this MUST NOT reach the network — a
    /// walk-away lets the host keep generating, so switching threads or
    /// clearing mid-turn doesn't throw away an answer the write-half would
    /// otherwise have preserved. `ChatStore.cancelStreaming(hardStopHost:)`
    /// calls this UNCONDITIONALLY, on every path — explicit Stop and
    /// walk-away alike — because releasing the routing lock is always
    /// correct; only `hardStopActiveRun()` below is gated by that
    /// parameter.
    func abandonActiveRun()

    /// #283 Task 7 (S23): the explicit user Stop tap's real server-side
    /// interrupt. `ChatStore.cancelStreaming(hardStopHost:)` is its one call
    /// site, gated by that parameter: `true` (the default — the in-app Stop
    /// button, and Siri's Cancel via `AskHermesIntent`/
    /// `AskHermesLongRunSupport`) fires it; `false` (the ONE other caller,
    /// the continued-send expiration handler — the system revoking a
    /// background task's budget with NO user action) skips it, so the host
    /// run is left alone rather than hard-killed on a turn the user never
    /// asked to stop. A real server-side interrupt for clients that can
    /// issue one (the Hermes runs plane's `POST /v1/runs/{id}/stop`); the
    /// default is a no-op for clients with nothing to interrupt server-side
    /// (mock / relay / the on-device brain). Distinct from `abandonActiveRun`
    /// above: a walk-away must never hard-kill a run the user didn't ask to
    /// stop, so this is the ONLY door that touches the network.
    ///
    /// #291 close-out (tracker #295): skipping this call does NOT "degrade
    /// to the ordinary recovery poll" — there is no client-side
    /// host-recovery poll on the expiration path. See
    /// `ChatStore.cancelStreaming(hardStopHost:)`'s doc for the corrected
    /// account and the open decision (#295) on whether that path should
    /// instead arm the genuine `pendingRun` / `reconcileFromServer()` route.
    func hardStopActiveRun()

    /// #78: the consumer TRUNCATED the thread (regenerate, edit-and-resend)
    /// and this conversation is now the whole of it. Every client that keeps
    /// its own mirror in `currentConversation` must adopt it here.
    ///
    /// Not optional politeness — ChatStore treats a client's mirror as an
    /// authoritative refresh source and merges it back over the rendered
    /// transcript at the end of every turn, on every ~2s poll tick, and on
    /// the streaming fallback path. `mergeConversationMetadata` takes the
    /// refresh source as the BASE ordering, so a mirror that still holds the
    /// removed rows restores them IN PLACE and leaves the regenerated reply
    /// stranded at the tail — the whole of #78's device symptom.
    ///
    /// The default is a no-op for mirror-less clients.
    func adoptTruncatedConversation(_ conversation: Conversation)
}

extension HermesClientProtocol {
    // Default no-ops so model-less clients (mock / legacy relay) conform without
    // change. Model-capable clients (SessionsHermesClient) and the resilient
    // wrapper override these. Declaring them as requirements above (not just here)
    // keeps dynamic dispatch through `any HermesClientProtocol` intact.
    func availableModels() async throws -> [String] { [] }
    func switchModel(_ identifier: String) async throws -> String? { nil }
    func listSessions() async throws -> [HermesSessionInfo] { [] }
    func openSession(_ id: String) async throws -> Conversation { await loadConversation() }
    func reconcileFromServer() async -> Conversation? { nil }
    func abandonActiveRun() {}
    func hardStopActiveRun() {}
    func adoptTruncatedConversation(_ conversation: Conversation) {}
}
