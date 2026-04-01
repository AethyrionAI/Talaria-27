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

    func send(message: String, clientMessageID: UUID) async -> Message {
        let response = await primary.send(message: message, clientMessageID: clientMessageID)
        if allowsFallback() && response.status == .failed {
            return await fallback.send(message: message, clientMessageID: clientMessageID)
        }
        return response
    }

    func loadConversation() async -> Conversation {
        let conversation = await primary.loadConversation()
        if allowsFallback() && primary.connectionStatus == .error {
            return await fallback.loadConversation()
        }
        return conversation
    }
}
