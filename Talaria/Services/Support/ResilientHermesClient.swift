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
    /// #328 route 2: the ISSUED/NOT-ISSUED answer is `primary`'s, for the same
    /// reason the call is.
    @discardableResult
    func hardStopActiveRun() -> Bool {
        primary.hardStopActiveRun()
    }

    /// #322: same rule as `hardStopActiveRun` above — `sendStreaming` only
    /// ever rides `primary`, so only `primary` can have a run in flight and
    /// only `primary` can answer for one.
    var activeRunID: String? { primary.activeRunID }

    /// #357 (3C): same rule again — only `primary` can hold the run a steer
    /// addresses; a fallback forward would always `.noActiveRun`.
    func steerActiveRun(text: String) async -> SteerSubmitOutcome {
        await primary.steerActiveRun(text: text)
    }

    func finalRunUsage(runID: String) async -> TokenUsage? {
        await primary.finalRunUsage(runID: runID)
    }

    /// #304: same rule as `hardStopActiveRun` above — `sendStreaming` only
    /// ever rides `primary`, so an approval question can only have come from
    /// it, and forwarding the answer to `fallback` would be a POST that
    /// always `.unsupported`s dressed up as coverage.
    func answerApproval(runID: String, choice: String, endpoint: SessionsHermesClient.ResolvedEndpoint) async -> RunApprovalAnswerOutcome {
        await primary.answerApproval(runID: runID, choice: choice, endpoint: endpoint)
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

    /// #295: forwards to `primary`, matching `reconcileFromServer` and
    /// `hardStopActiveRun` above — `sendStreaming` only ever rides `primary`,
    /// so whether the active run is recoverable is only ever `primary`'s
    /// question to answer; `fallback` never has a run of its own in flight.
    /// Not load-bearing through `ChatBackendRouter` today (its own override
    /// answers from `runningBrain` without delegating here), but correct on
    /// its own terms if this client is ever wired directly.
    var currentRunIsServerRecoverable: Bool {
        primary.currentRunIsServerRecoverable
    }
}
