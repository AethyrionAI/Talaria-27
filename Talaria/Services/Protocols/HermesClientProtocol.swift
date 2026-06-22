import Foundation

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
    func switchModel(_ identifier: String) async throws
}

extension HermesClientProtocol {
    // Default no-ops so model-less clients (mock / legacy relay) conform without
    // change. Model-capable clients (SessionsHermesClient) and the resilient
    // wrapper override these. Declaring them as requirements above (not just here)
    // keeps dynamic dispatch through `any HermesClientProtocol` intact.
    func availableModels() async throws -> [String] { [] }
    func switchModel(_ identifier: String) async throws {}
}
