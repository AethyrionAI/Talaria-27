import Foundation
import Testing
@testable import Talaria

/// Lane C item 1 — `/save` must not report success on a silent failure.
/// `exportConversationToFile()` now throws (nothing to save, Documents
/// missing, write/serialization error) and returns the written file URL so
/// ChatScreen can name the file and offer the share sheet.
struct ConversationExportTests {

    @MainActor
    private final class InertClient: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .disconnected
        var currentConversation: Conversation?

        func connect() async {}
        func disconnect() async {}

        func send(message: String, attachments: [PendingAttachment], clientMessageID: UUID) async -> Message {
            Message(sender: .hermes, content: "ok", status: .delivered)
        }

        func sendStreaming(
            message: String,
            attachments: [PendingAttachment],
            clientMessageID: UUID
        ) -> AsyncStream<StreamingUpdate> {
            AsyncStream { $0.finish() }
        }

        func loadConversation() async -> Conversation {
            Conversation(title: Conversation.defaultTitle)
        }

        func clearConversation() async throws -> Conversation {
            Conversation(title: Conversation.defaultTitle)
        }
    }

    @MainActor private func makeChatStore() -> ChatStore {
        let suiteName = "conversation-export-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return ChatStore(
            hermesClient: InertClient(),
            persistence: UserDefaultsAppPersistenceStore(defaults: defaults)
        )
    }

    @Test @MainActor
    func exportWithoutConversationThrowsNothingToSave() {
        let chatStore = makeChatStore()

        #expect(throws: ChatStore.ExportError.nothingToSave) {
            try chatStore.exportConversationToFile()
        }
    }

    @Test @MainActor
    func exportWritesFileAndReturnsItsURL() throws {
        let chatStore = makeChatStore()
        chatStore.conversation = Conversation(
            title: "Probe transcript",
            messages: [
                Message(sender: .user, content: "ping", status: .delivered),
                Message(sender: .hermes, content: "pong", status: .delivered),
            ]
        )

        let fileURL = try chatStore.exportConversationToFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        #expect(fileURL.lastPathComponent.hasPrefix("hermes_conversation_"))
        #expect(fileURL.pathExtension == "json")

        let data = try Data(contentsOf: fileURL)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(root["title"] as? String == "Probe transcript")
        #expect(root["messageCount"] as? Int == 2)

        let messages = try #require(root["messages"] as? [[String: Any]])
        #expect(messages.map { $0["content"] as? String } == ["ping", "pong"])
    }
}
