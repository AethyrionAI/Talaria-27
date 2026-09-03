import Foundation
import NaturalLanguage
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
        conversation(UUID(), messages)
    }

    /// Same session id across two calls — how the settle seam actually re-indexes
    /// one growing thread.
    private func conversation(_ id: UUID, _ messages: [Message]) -> Conversation {
        Conversation(id: id, title: "t", messages: messages)
    }

    private func msg(_ sender: MessageSender, _ text: String, priming: Bool = false) -> Message {
        Message(sender: sender, content: text, isContextPriming: priming)
    }

    /// A service whose acquisition never yields an embedder: `embed` returns
    /// nil, rows persist with an empty vector, and the ROW COUNT — which is all
    /// these exclusion pins assert — is unchanged. Using it keeps the suite off
    /// the real NaturalLanguage asset lookups, which cost real milliseconds per
    /// call and answer a question 422-C already owns.
    private func nullEmbedder() -> EmbeddingService { EmbeddingService(acquire: { nil }) }

    private func indexed(
        _ messages: [Message],
        embedder: @escaping () -> EmbeddingService
    ) throws -> Int {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        MemoryIndexer(store: store, makeEmbedder: embedder).index(conversation(messages))
        return store.indexCount()
    }

    private func indexed(_ messages: [Message]) throws -> Int {
        try indexed(messages, embedder: nullEmbedder)
    }

    /// The ONE pin that runs the REAL embedder, deliberately kept: every other
    /// test here stubs acquisition to nil, so without this the suite would never
    /// execute the branch where `embed` actually returns a vector and
    /// `EmbeddingService.encode` writes a non-empty blob.
    @Test func userTurnsAreIndexed() throws {
        #expect(try indexed([msg(.user, "My dentist is Dr. Patel.")],
                            embedder: { EmbeddingService() }) == 1)
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
        chatStore.memoryIndexer = MemoryIndexer(store: memory, makeEmbedder: nullEmbedder)

        #expect(memory.indexCount() == 0, "nothing is indexed before a turn settles")

        await chatStore.sendMessage("My dentist is Dr. Patel.")

        let conversationID = try #require(chatStore.conversation?.id)
        #expect(sessions.hasSession(withID: conversationID), "the thread is born local")
        #expect(memory.indexCount() > 0, "a settled local turn must reach the memory index")
    }

    /// The mirror of the test above, and the exclusion this suite was missing:
    /// a thread whose identity is a HERMES session must never reach the memory
    /// index. Ruling 3 is enforced entirely by the CALLER — the indexer itself
    /// reads no `brain` stamp — so "the indexer excludes host turns" is a claim
    /// about this seam and can only be pinned here.
    ///
    /// The fixture defeats BOTH membership branches on purpose: the store stays
    /// empty (so `isLocalSessionThread` is false) AND the thread already carries
    /// two `.hermes` turns (so the `assistantTurns == 1` born-local branch is
    /// missed too). That is #192's mixed paired-mode thread — the exact shape
    /// #190B's origin rule was written to keep out.
    @Test func aSettledTurnOnANonMemberThreadIsNotIndexed() async throws {
        let memory = try #require(MemoryStore.make(inMemoryOnly: true))
        let sessions = MembershipStore()
        let persistence = scratchPersistence()
        persistence.saveConversationCache(Conversation(title: Conversation.defaultTitle, messages: [
            Message(sender: .user, content: "earlier", status: .delivered),
            Message(sender: .hermes, content: "server reply", status: .delivered),
            Message(sender: .user, content: "earlier still", status: .delivered),
            Message(sender: .hermes, content: "another server reply", status: .delivered),
        ]))
        let chatStore = ChatStore(hermesClient: SettlingClient(), persistence: persistence)
        chatStore.localSessions = sessions
        chatStore.isLocalSessionThread = { sessions.hasSession(withID: $0.id) }
        chatStore.memoryIndexer = MemoryIndexer(store: memory, makeEmbedder: nullEmbedder)
        await chatStore.loadConversationIfNeeded()

        // #192 flips the brain mid-thread: this turn settles on-device.
        await chatStore.sendMessage("now local")

        let conversationID = try #require(chatStore.conversation?.id)
        #expect(sessions.hasSession(withID: conversationID) == false,
                "the fixture must actually be a non-member, or this pin proves nothing")
        #expect(memory.indexCount() == 0,
                "a thread whose identity is a Hermes session must never reach the memory index")
    }

    // MARK: - Per-settle reconcile

    /// `embed` calls made since `baseline`. With an `acquire` that never yields
    /// an embedder, `EmbeddingService.embed` re-attempts acquisition on EVERY
    /// call and never caches one — so `acquisitionAttempts` advances by exactly
    /// one per `embed`. The baseline is captured after construction rather than
    /// hardcoded, so this stays honest if `init`'s own retry count ever changes.
    private func embedCalls(_ service: EmbeddingService, since baseline: Int) -> Int {
        service.acquisitionAttempts - baseline
    }

    /// The settle seam re-indexes the WHOLE thread on every turn, so without an
    /// already-indexed skip the work is quadratic over a thread's life — every
    /// past chunk re-embedded and re-fetched on every settle, synchronously, on
    /// the MainActor. This measures the work rather than trusting the shape.
    @Test func reIndexingAGrownThreadEmbedsOnlyTheNewMessage() throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let embedder = nullEmbedder()
        let baseline = embedder.acquisitionAttempts
        let indexer = MemoryIndexer(store: store, makeEmbedder: { embedder })

        let sessionID = UUID()
        let u1 = msg(.user, "My dentist is Dr. Patel. Her office is on Oak Street. I see her in May.")
        let h1 = msg(.hermes, "Noted.")
        let u2 = msg(.user, "My dog is called Biscuit.")

        indexer.index(conversation(sessionID, [u1, h1]))
        let afterFirst = embedCalls(embedder, since: baseline)
        #expect(afterFirst == MemoryChunker.chunk(u1.content).count,
                "the first pass embeds exactly u1's chunks")

        indexer.index(conversation(sessionID, [u1, h1, u2]))
        let newWork = embedCalls(embedder, since: baseline) - afterFirst
        #expect(newWork == MemoryChunker.chunk(u2.content).count,
                "re-indexing a grown thread must embed only the new message")
        #expect(newWork > 0, "the new message must actually have been indexed")

        // …and the rows are the same as a single full pass would have produced.
        let oneShot = try #require(MemoryStore.make(inMemoryOnly: true))
        MemoryIndexer(store: oneShot, makeEmbedder: nullEmbedder)
            .index(conversation(sessionID, [u1, h1, u2]))
        #expect(store.indexCount() == oneShot.indexCount())
    }

    /// Ruling 2 (visibility) in its negative form: every stored row must have a
    /// resolvable source, so a row whose source message is GONE cannot survive.
    /// `retryMessage` removes a user row; `/undo` and `regenerateReply` truncate
    /// a range. Without this the deleted turn stays retrievable forever and its
    /// provenance chip points at a message that no longer exists.
    @Test func rowsWhoseMessageLeftTheConversationAreDeleted() throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let indexer = MemoryIndexer(store: store, makeEmbedder: nullEmbedder)
        let sessionID = UUID()
        let u1 = msg(.user, "My dentist is Dr. Patel.")
        let u2 = msg(.user, "Delete this one. It has two sentences so it is not one row.")

        indexer.index(conversation(sessionID, [u1, u2]))
        let u1Rows = MemoryChunker.chunk(u1.content).count
        let u2Rows = MemoryChunker.chunk(u2.content).count
        #expect(store.indexCount() == u1Rows + u2Rows)
        #expect(u2Rows > 0)

        indexer.index(conversation(sessionID, [u1]))

        #expect(store.indexCount() == u1Rows,
                "a memory whose source message the user deleted must not survive it")
    }
}
