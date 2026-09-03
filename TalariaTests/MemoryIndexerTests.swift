import Foundation
import Testing
@testable import Talaria

/// #422 bar 422-B: what the local memory corpus is allowed to contain.
///
/// One pin per exclusion, deliberately. The corpus is the USER'S OWN WORDS
/// (Owen's 09-02 rulings: assistant turns EXCLUDED, voice turns INCLUDED), and
/// every row a wrong sender contributes is a memory the user never authored —
/// the failure this bar exists to make loud. A single "only user turns" test
/// would go green with three of the five senders wired wrong.
@Suite("422-B capture")
@MainActor
struct MemoryIndexerTests {
    private func conversation(_ messages: [Message]) -> Conversation {
        Conversation(id: UUID(), title: "t", messages: messages)
    }

    private func msg(_ sender: MessageSender, _ text: String, priming: Bool = false) -> Message {
        Message(sender: sender, content: text, isContextPriming: priming)
    }

    private func indexed(_ messages: [Message]) throws -> Int {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        MemoryIndexer(store: store, embedder: EmbeddingService()).index(conversation(messages))
        return store.indexCount()
    }

    @Test func userTurnsAreIndexed() throws {
        #expect(try indexed([msg(.user, "My dentist is Dr. Patel.")]) == 1)
    }

    @Test func voiceUserTurnsAreIndexed() throws {
        #expect(try indexed([msg(.voiceUser, "My dentist is Dr. Patel.")]) == 1)
    }

    @Test func assistantTurnsAreNot() throws {
        #expect(try indexed([msg(.hermes, "Noted — Dr. Patel.")]) == 0)
    }

    @Test func voiceAssistantTurnsAreNot() throws {
        #expect(try indexed([msg(.voiceHermes, "Noted.")]) == 0)
    }

    @Test func systemTurnsAreNot() throws {
        #expect(try indexed([msg(.system, "Context transplanted.")]) == 0)
    }

    /// P1 (#90)'s context-transplant rows are `.user`-sendered by construction
    /// — a wall of re-primed history the user never typed at this moment. They
    /// are the one exclusion the sender predicate cannot make.
    @Test func primingRowsAreNotEvenWhenSenderIsUser() throws {
        #expect(try indexed([msg(.user, "wall of primer", priming: true)]) == 0)
    }

    @Test func aLongTurnYieldsManyRowsAndAShortOneYieldsOne() throws {
        let long = String(repeating: "This sentence has exactly eight words in it. ", count: 60)
        #expect(try indexed([msg(.user, long)]) >= 6)
    }

    // MARK: - The settle seam

    /// Yields exactly one `.finished` assistant turn stamped on-device — the
    /// minimal client for driving ChatStore's settle path. Same shape as
    /// `LocalSessionHistoryTests.SettlingClient`, restated because that
    /// suite's fixtures are private to it.
    @MainActor
    private final class SettlingClient: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .connected
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
            let reply = Message(
                sender: .hermes, content: "reply", status: .delivered,
                brain: ChatBackendRouter.Brain.onDevice.rawValue
            )
            return AsyncStream { continuation in
                continuation.yield(.finished(reply, nil, nil))
                continuation.finish()
            }
        }

        func loadConversation() async -> Conversation {
            currentConversation ?? Conversation(title: Conversation.defaultTitle)
        }

        func clearConversation() async throws -> Conversation {
            Conversation(title: Conversation.defaultTitle)
        }
    }

    /// Dict-backed `LocalSessionStoring` — membership IS the local-origin
    /// verdict the indexer relies on (#190B), so the seam test drives the real
    /// one rather than forcing it true.
    @MainActor
    private final class MembershipStore: LocalSessionStoring {
        private var sessions: [UUID: Conversation] = [:]
        func upsertSession(_ conversation: Conversation) { sessions[conversation.id] = conversation }
        func sessionSummaries() -> [LocalSessionSummary] { [] }
        func conversation(withID id: UUID) -> Conversation? { sessions[id] }
        func hasSession(withID id: UUID) -> Bool { sessions[id] != nil }
        func recordRemoteSessionStubs(_ infos: [HermesSessionInfo]) {}
        func remoteSessionStubs() -> [HermesSessionInfo] { [] }
    }

    private func scratchPersistence() -> UserDefaultsAppPersistenceStore {
        let suiteName = "memory-indexer-seam-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsAppPersistenceStore(defaults: defaults)
    }

    /// The wiring bar: a turn that settles on a local brain must reach the
    /// indexer, not merely the session store. Both live on the SAME seam by
    /// design — `recordLocalOriginAfterSettledTurn` — so the assertion is that
    /// the seam feeds both, through ChatStore's real send path.
    @Test func aSettledLocalTurnIndexesThroughTheSeam() async throws {
        let memory = try #require(MemoryStore.make(inMemoryOnly: true))
        let sessions = MembershipStore()
        let chatStore = ChatStore(hermesClient: SettlingClient(), persistence: scratchPersistence())
        chatStore.localSessions = sessions
        chatStore.isLocalSessionThread = { sessions.hasSession(withID: $0.id) }
        chatStore.memoryIndexer = MemoryIndexer(store: memory, embedder: EmbeddingService())

        #expect(memory.indexCount() == 0, "nothing is indexed before a turn settles")

        await chatStore.sendMessage("My dentist is Dr. Patel.")

        let conversationID = try #require(chatStore.conversation?.id)
        #expect(sessions.hasSession(withID: conversationID), "the thread is born local")
        #expect(memory.indexCount() > 0, "a settled local turn must reach the memory index")
    }
}
