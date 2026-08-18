import Foundation
import Testing
@testable import Talaria

/// #362 3D-D against the REAL ChatStore: the correlator's transcript surface
/// is the store's own conversation slot, persistence is the real sidecar, and
/// `openSession` is the retry call site. Harness follows
/// `AgentFileChipPersistenceTests` (real persistence + journal, a client
/// double whose `openSession` returns the server's stored transcript —
/// name + preview, never attachments).
struct ArtifactMirrorChatStoreTests {

    @MainActor private func makePersistence() -> UserDefaultsAppPersistenceStore {
        let suiteName = "artifact-mirror-chatstore-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsAppPersistenceStore(defaults: defaults)
    }

    @MainActor
    private final class StoredTranscriptClient: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .connected
        var currentConversation: Conversation?
        var storedTranscripts: [String: Conversation] = [:]

        func connect() async {}
        func disconnect() async {}
        func send(message: String, attachments: [PendingAttachment], clientMessageID: UUID) async -> Message {
            Message(sender: .hermes, content: "ok", status: .delivered)
        }
        func sendStreaming(
            message: String, attachments: [PendingAttachment], clientMessageID: UUID
        ) -> AsyncStream<StreamingUpdate> {
            AsyncStream { $0.finish() }
        }
        func loadConversation() async -> Conversation {
            if let currentConversation { return currentConversation }
            let fresh = Conversation(title: Conversation.defaultTitle)
            currentConversation = fresh
            return fresh
        }
        func clearConversation() async throws -> Conversation {
            let fresh = Conversation(title: Conversation.defaultTitle)
            currentConversation = fresh
            return fresh
        }
        func openSession(_ id: String) async throws -> Conversation {
            storedTranscripts[id] ?? Conversation(title: Conversation.defaultTitle)
        }
    }

    private static func storedRow(
        sender: MessageSender, content: String, sessionID: String, serverRowID: Int,
        writePath: String? = nil
    ) -> Message {
        Message(
            id: SessionsHermesClient.stableMessageID(sessionId: sessionID, serverRowID: serverRowID),
            sender: sender,
            content: content,
            timestamp: Date(timeIntervalSince1970: 1_754_500_000 + Double(serverRowID)),
            status: .delivered,
            toolActivities: writePath.map {
                [ToolActivity(label: "write_file", startedAt: .now, isActive: false, detail: $0, anchorOffset: content.count)]
            } ?? []
        )
    }

    @MainActor
    private func makeStore() -> (ChatStore, StoredTranscriptClient) {
        let persistence = makePersistence()
        let journal = ConversationJournalStore(persistence: persistence)
        let client = StoredTranscriptClient()
        let store = ChatStore(hermesClient: client, persistence: persistence, journal: journal)
        client.storedTranscripts["api_A"] = Conversation(title: "Writer", messages: [
            Self.storedRow(sender: .user, content: "write it", sessionID: "api_A", serverRowID: 1),
            Self.storedRow(
                sender: .hermes, content: "Wrote notes/a.txt.", sessionID: "api_A",
                serverRowID: 2, writePath: "notes/a.txt"
            ),
        ])
        client.storedTranscripts["api_B"] = Conversation(title: "Other", messages: [
            Self.storedRow(sender: .user, content: "hi", sessionID: "api_B", serverRowID: 1),
            Self.storedRow(sender: .hermes, content: "hello", sessionID: "api_B", serverRowID: 2),
        ])
        return (store, client)
    }

    private func mirrorItem(content: String = "line one\n") -> ArtifactMirrorItem {
        ArtifactMirrorItem(
            platformItemID: "item-1", sessionID: "api_A", path: "notes/a.txt",
            content: content, turnID: nil, toolCallID: nil, hostTimestamp: nil
        )
    }

    /// 3D-D late arm: the item drains AFTER the run completed and the thread
    /// was refetched — it attaches to the refetched (server-id) message and
    /// the chip survives leaving and reopening the thread via the sidecar.
    @Test @MainActor
    func lateItemAttachesToRefetchedTranscriptAndSurvivesReopen() async throws {
        let (store, _) = makeStore()
        await store.openSession("api_A")
        #expect(store.conversation?.messages.last?.attachments.isEmpty == true)

        store.artifactMirror.receive(mirrorItem())

        var reply = try #require(store.conversation?.messages.last)
        #expect(reply.attachments.count == 1)
        #expect(reply.attachments.first?.fileName == "a.txt")
        #expect(reply.attachments.first?.localStoragePath != nil)
        #expect(reply.attachments.first?.anchorOffset == "Wrote notes/a.txt.".count)

        await store.openSession("api_B")
        await store.openSession("api_A")

        reply = try #require(store.conversation?.messages.last)
        #expect(reply.attachments.count == 1)
        #expect(reply.attachments.first?.fileName == "a.txt")
        // The write_file CARD is still there too — card AND chip (#277).
        #expect(reply.toolActivities.count == 1)
    }

    /// 3D-D cross-thread arm, pinning the `openSession` retry call site: an
    /// item drained while ANOTHER thread was open attaches the moment its
    /// own thread opens.
    @Test @MainActor
    func heldItemAttachesWhenItsThreadOpensLater() async throws {
        let (store, _) = makeStore()
        await store.openSession("api_B")

        store.artifactMirror.receive(mirrorItem())
        // Held: the open thread is api_B, the item belongs to api_A.
        #expect(store.conversation?.messages.last?.attachments.isEmpty == true)
        #expect(store.artifactMirror.pendingCountForDiagnostics == 1)

        await store.openSession("api_A")

        let reply = try #require(store.conversation?.messages.last)
        #expect(reply.attachments.count == 1)
        #expect(reply.attachments.first?.fileName == "a.txt")
        #expect(store.artifactMirror.pendingCountForDiagnostics == 0)
    }

    /// The drop arm at store level: an item for a session no thread ever
    /// opens changes nothing anywhere — no attachment, no sidecar row.
    @Test @MainActor
    func foreignSessionItemNeverTouchesTheOpenThread() async throws {
        let (store, _) = makeStore()
        await store.openSession("api_A")

        store.artifactMirror.receive(
            ArtifactMirrorItem(
                platformItemID: "item-x", sessionID: "SOMEONE_ELSE", path: "notes/a.txt",
                content: "not yours", turnID: nil, toolCallID: nil, hostTimestamp: nil
            )
        )

        let reply = try #require(store.conversation?.messages.last)
        #expect(reply.attachments.isEmpty)
        #expect(store.artifactMirror.pendingCountForDiagnostics == 1)
    }
}
