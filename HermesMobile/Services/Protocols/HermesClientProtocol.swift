import Foundation

@MainActor
protocol HermesClientProtocol {
    var connectionStatus: ConnectionStatus { get }
    var currentConversation: Conversation? { get }
    func connect() async
    func disconnect() async
    func send(message: String, clientMessageID: UUID) async -> Message
    func loadConversation() async -> Conversation
}
