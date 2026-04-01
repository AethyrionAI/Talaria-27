import Foundation

@MainActor
final class LiveHermesClient: HermesClientProtocol {
    private struct ConversationResponse: Decodable {
        let conversation: RelayConversation
    }

    private struct MessageResponse: Decodable {
        let replyState: String
        let conversation: RelayConversation
        let userMessage: RelayMessage?
        let message: RelayMessage?
    }

    private struct RelayConversation: Decodable {
        let id: UUID
        let title: String
        let updatedAt: Date
        let messages: [RelayMessage]
    }

    private struct RelayMessage: Decodable {
        let id: UUID
        let role: MessageSender
        let text: String
        let timestamp: Date
        let deliveryStatus: String?
        let jobId: UUID?
    }

    private struct MessageCreateBody: Encodable {
        let conversationId: UUID?
        let text: String
        let clientMessageId: UUID
    }

    var connectionStatus: ConnectionStatus = .disconnected
    var currentConversation: Conversation?

    private let apiClient: RelayAPIClient
    private let accessTokenProvider: @MainActor () async -> String?
    private let allowDemoFallback: Bool

    init(
        apiClient: RelayAPIClient,
        accessTokenProvider: @escaping @MainActor () async -> String?,
        allowDemoFallback: Bool = true
    ) {
        self.apiClient = apiClient
        self.accessTokenProvider = accessTokenProvider
        self.allowDemoFallback = allowDemoFallback
    }

    func connect() async {
        connectionStatus = .connecting
        do {
            let token = await accessTokenProvider()
            let response: ConversationResponse = try await apiClient.get(
                path: "conversations/current",
                accessToken: token
            )
            currentConversation = mapConversation(response.conversation)
            connectionStatus = .connected
        } catch {
            connectionStatus = .error
        }
    }

    func disconnect() async {
        connectionStatus = .disconnected
    }

    func send(message: String, clientMessageID: UUID) async -> Message {
        do {
            let token = await accessTokenProvider()
            let response: MessageResponse = try await apiClient.post(
                path: "messages",
                body: MessageCreateBody(
                    conversationId: currentConversation?.id,
                    text: message,
                    clientMessageId: clientMessageID
                ),
                accessToken: token
            )
            currentConversation = mapConversation(response.conversation)
            connectionStatus = .connected
            if let message = response.message {
                return mapMessage(message)
            }
            if let userMessage = response.userMessage {
                return mapMessage(userMessage)
            }
            return Message(sender: .system, content: "Hermes did not return a message.", status: .failed)
        } catch {
            connectionStatus = .error
            return Message(sender: .system, content: "Hermes relay is unavailable right now.", status: .failed)
        }
    }

    func loadConversation() async -> Conversation {
        do {
            let token = await accessTokenProvider()
            let response: ConversationResponse = try await apiClient.get(
                path: "conversations/current",
                accessToken: token
            )
            let conversation = mapConversation(response.conversation)
            currentConversation = conversation
            connectionStatus = .connected
            return conversation
        } catch {
            connectionStatus = .error
            return currentConversation ?? fallbackConversation()
        }
    }

    private func fallbackConversation() -> Conversation {
        if allowDemoFallback {
            return DemoData.sampleConversation
        }

        return Conversation(title: "Hermes")
    }

    private func mapConversation(_ relayConversation: RelayConversation) -> Conversation {
        Conversation(
            id: relayConversation.id,
            title: relayConversation.title,
            messages: relayConversation.messages.map(mapMessage),
            lastActivity: relayConversation.updatedAt
        )
    }

    private func mapMessage(_ relayMessage: RelayMessage) -> Message {
        Message(
            id: relayMessage.id,
            sender: relayMessage.role,
            content: relayMessage.text,
            timestamp: relayMessage.timestamp,
            jobID: relayMessage.jobId,
            status: mapDeliveryStatus(relayMessage.deliveryStatus, sender: relayMessage.role)
        )
    }

    private func mapDeliveryStatus(_ deliveryStatus: String?, sender: MessageSender) -> MessageStatus {
        switch deliveryStatus {
        case "pending":
            return .sending
        case "sent":
            return .sent
        case "delivered":
            return .delivered
        case "failed":
            return .failed
        default:
            return sender == .user ? .sent : .delivered
        }
    }
}
