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
    func injectVoiceTranscript(voiceSessionId: UUID) async throws -> Conversation

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
}
