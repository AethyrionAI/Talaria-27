import Foundation

@MainActor
@Observable
final class ChatStore {
    var conversation: Conversation?
    var isLoading = false
    private var isPollingEnabled = false
    private var pollingTask: Task<Void, Never>?

    private let hermesClient: any HermesClientProtocol

    init(hermesClient: any HermesClientProtocol) {
        self.hermesClient = hermesClient
    }

    func loadConversationIfNeeded() async {
        guard conversation == nil else { return }
        await loadConversation()
    }

    func loadConversation() async {
        isLoading = true
        defer { isLoading = false }
        conversation = await hermesClient.loadConversation()
        restartPendingPollingIfNeeded()
    }

    func sendMessage(_ content: String) async {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return }
        guard hasPendingDuplicateMessage(trimmedContent) == false else { return }

        let clientMessageID = UUID()
        let optimistic = Message(id: clientMessageID, sender: .user, content: trimmedContent, status: .sending)
        if conversation == nil {
            conversation = Conversation(title: "Hermes")
        }
        conversation?.messages.append(optimistic)
        conversation?.lastActivity = optimistic.timestamp

        let response = await hermesClient.send(message: trimmedContent, clientMessageID: clientMessageID)
        conversation = hermesClient.currentConversation

        if conversation == nil && response.status == .failed {
            conversation = Conversation(title: "Hermes")
            conversation?.messages.append(response)
            conversation?.lastActivity = response.timestamp
        }

        restartPendingPollingIfNeeded()
    }

    func setPollingEnabled(_ isEnabled: Bool) {
        isPollingEnabled = isEnabled
        if isEnabled {
            restartPendingPollingIfNeeded()
        } else {
            pollingTask?.cancel()
            pollingTask = nil
        }
    }

    func reset() {
        pollingTask?.cancel()
        pollingTask = nil
        isPollingEnabled = false
        conversation = nil
        isLoading = false
    }

    private var hasPendingMessages: Bool {
        conversation?.messages.contains(where: { $0.sender == .user && $0.status == .sending }) == true
    }

    private func hasPendingDuplicateMessage(_ content: String) -> Bool {
        conversation?.messages.contains(where: {
            $0.sender == .user
                && $0.status == .sending
                && $0.content.trimmingCharacters(in: .whitespacesAndNewlines) == content
        }) == true
    }

    private func restartPendingPollingIfNeeded() {
        guard isPollingEnabled, hasPendingMessages else {
            pollingTask?.cancel()
            pollingTask = nil
            return
        }

        guard pollingTask == nil else { return }

        pollingTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                self.conversation = await self.hermesClient.loadConversation()
                if self.hasPendingMessages == false {
                    break
                }
            }

            if self.pollingTask?.isCancelled == false {
                self.pollingTask = nil
            }
        }
    }
}
