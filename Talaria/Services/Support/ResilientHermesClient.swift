import Foundation

@MainActor
final class ResilientHermesClient: HermesClientProtocol {
    var connectionStatus: ConnectionStatus {
        primary.connectionStatus
    }

    var currentConversation: Conversation? {
        primary.currentConversation ?? fallback.currentConversation
    }

    private let primary: any HermesClientProtocol
    private let fallback: any HermesClientProtocol
    private let allowsFallback: @MainActor () -> Bool

    init(
        primary: any HermesClientProtocol,
        fallback: any HermesClientProtocol,
        allowsFallback: @escaping @MainActor () -> Bool = { true }
    ) {
        self.primary = primary
        self.fallback = fallback
        self.allowsFallback = allowsFallback
    }

    func connect() async {
        await primary.connect()
        if allowsFallback() && primary.connectionStatus == .error {
            await fallback.connect()
        }
    }

    func disconnect() async {
        await primary.disconnect()
        await fallback.disconnect()
    }

    func send(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) async -> Message {
        let response = await primary.send(message: message, attachments: attachments, clientMessageID: clientMessageID)
        if allowsFallback() && response.status == .failed {
            return await fallback.send(message: message, attachments: attachments, clientMessageID: clientMessageID)
        }
        return response
    }

    func sendStreaming(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) -> AsyncStream<StreamingUpdate> {
        primary.sendStreaming(message: message, attachments: attachments, clientMessageID: clientMessageID)
    }

    func loadConversation() async -> Conversation {
        let conversation = await primary.loadConversation()
        if allowsFallback() && primary.connectionStatus == .error {
            return await fallback.loadConversation()
        }
        return conversation
    }

    func clearConversation() async throws -> Conversation {
        try await primary.clearConversation()
    }

    /// #78: both sides, because `currentConversation` above reads
    /// `primary ?? fallback` — truncating only the primary leaves the
    /// fallback's mirror ready to restore the removed rows the moment the
    /// primary has nothing to offer.
    func adoptTruncatedConversation(_ conversation: Conversation) {
        primary.adoptTruncatedConversation(conversation)
        fallback.adoptTruncatedConversation(conversation)
    }

    /// #283 review ruling: `abandonActiveRun` (the walk-away teardown) is
    /// deliberately NOT overridden here — the protocol default no-op is
    /// correct, matching this type's pre-#283 state. `sendStreaming` above
    /// only ever rides `primary`, so `hardStopActiveRun` — the explicit Stop
    /// tap's real server-side interrupt — only ever needs to reach it too;
    /// forwarding to `fallback` as well would be a POST that always no-ops
    /// (nothing there ever set `activeRunContext`) dressed up as coverage.
    func hardStopActiveRun() {
        primary.hardStopActiveRun()
    }

    func availableModels() async throws -> [String] {
        try await primary.availableModels()
    }

    @discardableResult
    func switchModel(_ identifier: String) async throws -> String? {
        try await primary.switchModel(identifier)
    }

    func listSessions() async throws -> [HermesSessionInfo] {
        try await primary.listSessions()
    }

    func openSession(_ id: String) async throws -> Conversation {
        try await primary.openSession(id)
    }

    func reconcileFromServer() async -> Conversation? {
        await primary.reconcileFromServer()
    }
}
