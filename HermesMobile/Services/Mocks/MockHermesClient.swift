import Foundation

@MainActor
@Observable
final class MockHermesClient: HermesClientProtocol {
    var connectionStatus: ConnectionStatus = .connected
    var currentConversation: Conversation?

    private let responseDelay: TimeInterval = 1.5

    func connect() async {
        connectionStatus = .connecting
        try? await Task.sleep(for: .seconds(0.8))
        connectionStatus = .connected
    }

    func disconnect() async {
        connectionStatus = .disconnected
    }

    func send(message content: String, clientMessageID: UUID) async -> Message {
        let userMessage = Message(
            sender: .user,
            content: content,
            status: .sent
        )

        currentConversation?.messages.append(userMessage)

        // Simulate Hermes thinking and responding
        try? await Task.sleep(for: .seconds(responseDelay))

        let response = generateResponse(for: content)
        let hermesMessage = Message(
            sender: .hermes,
            content: response,
            status: .delivered
        )

        currentConversation?.messages.append(hermesMessage)

        return hermesMessage
    }

    func loadConversation() async -> Conversation {
        let conversation = DemoData.sampleConversation
        currentConversation = conversation
        return conversation
    }

    private func generateResponse(for input: String) -> String {
        let responses = [
            "I've looked into that for you. Based on what I can see, here's what I'd suggest...",
            "That's a great question. Let me break it down for you step by step.",
            "I've been thinking about this. Here are a few options we could consider.",
            "Understood. I'll take care of that right away. Is there anything else you need?",
            "I found some interesting information about that. Let me share what I've gathered.",
            "Good thinking. I've already started working on it. You should see results shortly.",
        ]
        return responses.randomElement() ?? responses[0]
    }
}
