import Foundation
import Testing
@testable import Talaria

/// P1 continuity fabric (OPEN_ITEMS #90) — the deterministic half: journal
/// identity + hop bookkeeping, the offline compose outbox, and ChatStore's
/// integration (priming notices, queue/drain, session totals). The
/// model-dependent condenser half lives in CondenserFidelityTests.
struct ContinuityFabricTests {

    @MainActor private static func makePersistence() -> UserDefaultsAppPersistenceStore {
        let suiteName = "continuity-fabric-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsAppPersistenceStore(defaults: defaults)
    }

    private static func conversation(
        id: UUID = UUID(),
        turns: [(MessageSender, String)]
    ) -> Conversation {
        Conversation(
            id: id,
            title: Conversation.defaultTitle,
            messages: turns.map { Message(sender: $0.0, content: $0.1, status: .delivered) }
        )
    }

    // MARK: - Journal: identity + entry derivation

    @Test @MainActor
    func syncAdoptsForeignConversationAndDropsHop() {
        let persistence = Self.makePersistence()
        let store = ConversationJournalStore(persistence: persistence)
        store.beginHop(apiSessionId: "api_old", primingUsage: nil)

        // A conversation the journal has never seen (pre-journal cache
        // migration, fresh chat): identity adopts, entries derive, hop drops
        // — the next Hermes turn must transplant.
        let convo = Self.conversation(turns: [(.user, "hello"), (.hermes, "hi there")])
        store.sync(with: convo)

        #expect(store.journal.conversationID == convo.id)
        #expect(store.entries.count == 2)
        #expect(store.activeHop == nil)
        #expect(store.activeHopIsCurrent == false)
    }

    @Test @MainActor
    func entriesSkipSystemFailedAndStreamingRows() {
        var convo = Self.conversation(turns: [(.user, "question"), (.hermes, "answer")])
        convo.messages.append(Message(sender: .system, content: "[Voice session ended]", status: .delivered))
        convo.messages.append(Message(sender: .user, content: "failed send", status: .failed))
        convo.messages.append(Message(sender: .hermes, content: "mid-stream", status: .sending, isStreaming: true))
        convo.messages.append(Message(
            sender: .system,
            content: "[Context transplanted into a fresh session]",
            status: .delivered,
            usage: TokenUsage(promptTokens: 900, completionTokens: 8, totalTokens: 908),
            isContextPriming: true
        ))
        // Voice turns ARE conversation content.
        convo.messages.append(Message(sender: .voiceUser, content: "spoken question", status: .delivered))
        convo.messages.append(Message(sender: .voiceHermes, content: "spoken answer", status: .delivered))

        let entries = ConversationJournalStore.entries(from: convo)
        #expect(entries.map(\.text) == ["question", "answer", "spoken question", "spoken answer"])
        #expect(entries.map(\.role) == [.user, .assistant, .user, .assistant])
    }

    @Test @MainActor
    func journalPersistsAcrossStoreInstances() {
        let persistence = Self.makePersistence()
        let convo = Self.conversation(turns: [(.user, "remember me"), (.hermes, "always")])

        let first = ConversationJournalStore(persistence: persistence)
        first.sync(with: convo)
        first.beginHop(apiSessionId: "api_123", primingUsage: TokenUsage(promptTokens: 500, completionTokens: 5, totalTokens: 505))

        // A relaunch: the identity, entries, hop handle, and priming receipt
        // all survive — this is what lets the same server session resume
        // without re-priming.
        let second = ConversationJournalStore(persistence: persistence)
        #expect(second.journal.conversationID == convo.id)
        #expect(second.entries.count == 2)
        #expect(second.activeHop?.apiSessionId == "api_123")
        #expect(second.activeHop?.primingUsage?.totalTokens == 505)
        #expect(second.activeHopIsCurrent)
    }

    // MARK: - Journal: hop waterline

    @Test @MainActor
    func hermesExchangeBumpsWaterlineLocalExchangeDoesNot() {
        let persistence = Self.makePersistence()
        let store = ConversationJournalStore(persistence: persistence)
        var convo = Self.conversation(turns: [(.user, "q1"), (.hermes, "a1")])
        store.sync(with: convo)
        store.beginHop(apiSessionId: "api_1", primingUsage: nil)
        #expect(store.activeHopIsCurrent)

        // A Hermes-brain exchange rides the hop: waterline follows.
        convo.messages.append(Message(sender: .user, content: "q2", status: .delivered))
        convo.messages.append(Message(sender: .hermes, content: "a2", status: .delivered))
        store.sync(with: convo, lastExchangeViaActiveHop: true)
        #expect(store.activeHopIsCurrent)

        // A local-brain exchange does NOT: the hop goes stale, which is what
        // makes the next Hermes turn start a fresh transplanted session.
        convo.messages.append(Message(sender: .user, content: "q3", status: .delivered))
        convo.messages.append(Message(sender: .hermes, content: "a3 (local)", status: .delivered))
        store.sync(with: convo, lastExchangeViaActiveHop: false)
        #expect(store.activeHop != nil)
        #expect(store.activeHopIsCurrent == false)
    }

    @Test @MainActor
    func truncationClampsWaterlineAndKeepsHopCurrent() {
        let persistence = Self.makePersistence()
        let store = ConversationJournalStore(persistence: persistence)
        var convo = Self.conversation(turns: [(.user, "q1"), (.hermes, "a1"), (.user, "q2"), (.hermes, "a2")])
        store.sync(with: convo)
        store.beginHop(apiSessionId: "api_1", primingUsage: nil)

        // #44 regenerate/edit truncation: entries shrink; the clamp keeps the
        // hop readable as current (the server session keeps its history — the
        // documented /retry caveat).
        convo.messages.removeSubrange(2...)
        store.sync(with: convo)
        #expect(store.entries.count == 2)
        #expect(store.activeHop?.seenEntryCount == 2)
        #expect(store.activeHopIsCurrent)
    }

    @Test @MainActor
    func adoptServerSessionRebuildsUnderCurrentHop() {
        let persistence = Self.makePersistence()
        let store = ConversationJournalStore(persistence: persistence)
        store.sync(with: Self.conversation(turns: [(.user, "old thread")]))

        let opened = Self.conversation(turns: [(.user, "from drawer"), (.hermes, "server history")])
        store.adoptServerSession(id: "api_drawer", conversation: opened)

        #expect(store.journal.conversationID == opened.id)
        #expect(store.entries.count == 2)
        #expect(store.activeHop?.apiSessionId == "api_drawer")
        // The opened session's history IS its context — nothing to transplant.
        #expect(store.activeHopIsCurrent)
    }

    @Test @MainActor
    func endHopKeepsEntries() {
        let persistence = Self.makePersistence()
        let store = ConversationJournalStore(persistence: persistence)
        store.sync(with: Self.conversation(turns: [(.user, "kept"), (.hermes, "also kept")]))
        store.beginHop(apiSessionId: "api_1", primingUsage: nil)

        // Ending a hop (model switch, stale 404) discards ONLY the handle —
        // the journal is the durable primary.
        store.endHop()
        #expect(store.activeHop == nil)
        #expect(store.entries.count == 2)
    }

    // MARK: - Compose outbox state

    @Test
    func composeOutboxEnqueueDedupesById() {
        var state = ComposeOutboxState()
        let id = UUID()
        state.enqueue(id: id, text: "offline turn")
        state.enqueue(id: id, text: "offline turn")
        #expect(state.pendingTurns.count == 1)
        state.remove(id: id)
        #expect(state.isEmpty)
    }

    @Test @MainActor
    func composeOutboxPersistsAndClearsWhenEmpty() {
        let persistence = Self.makePersistence()
        var state = ComposeOutboxState()
        state.enqueue(id: UUID(), text: "park me")
        persistence.saveComposeOutboxState(state)
        #expect(persistence.loadComposeOutboxState().pendingTurns.first?.text == "park me")

        // Saving an emptied state clears the stored blob (the sensor-outbox
        // hygiene pattern).
        persistence.saveComposeOutboxState(ComposeOutboxState())
        #expect(persistence.loadComposeOutboxState().isEmpty)
    }

    // MARK: - ChatStore integration fakes

    /// Scriptable client: emits a fixed update sequence per send, so the
    /// unreachable-queue and priming-notice paths are drivable without a
    /// server.
    @MainActor
    private final class ScriptedClient: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .connected
        var currentConversation: Conversation?
        /// Dequeued front-first, one script per sendStreaming call; the last
        /// script repeats once the queue drains.
        var scripts: [[StreamingUpdate]] = []
        private(set) var sentMessages: [String] = []

        func connect() async {}
        func disconnect() async {}

        func send(message: String, attachments: [PendingAttachment], clientMessageID: UUID) async -> Message {
            Message(sender: .hermes, content: "sync ok", status: .delivered)
        }

        func sendStreaming(
            message: String,
            attachments: [PendingAttachment],
            clientMessageID: UUID
        ) -> AsyncStream<StreamingUpdate> {
            sentMessages.append(message)
            let script = scripts.count > 1 ? scripts.removeFirst() : (scripts.first ?? [])
            return AsyncStream { continuation in
                for update in script {
                    continuation.yield(update)
                }
                continuation.finish()
            }
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
    }

    // MARK: - ChatStore: priming notice + totals

    @Test @MainActor
    func contextPrimedInsertsNoticeWithUsageBeforeReply() async throws {
        let persistence = Self.makePersistence()
        let client = ScriptedClient()
        let primingUsage = TokenUsage(promptTokens: 1200, completionTokens: 9, totalTokens: 1209)
        let turnUsage = TokenUsage(promptTokens: 1500, completionTokens: 40, totalTokens: 1540)
        client.scripts = [[
            .contextPrimed(primingUsage),
            .textDelta("Answer"),
            .finished(Message(sender: .hermes, content: "Answer", status: .delivered), turnUsage, nil),
        ]]
        let store = ChatStore(hermesClient: client, persistence: persistence)

        await store.sendMessage("continue the thread")

        let messages = try #require(store.conversation?.messages)
        let noticeIdx = try #require(messages.firstIndex(where: { $0.isContextPriming }))
        let replyIdx = try #require(messages.firstIndex(where: { $0.sender == .hermes && $0.content == "Answer" }))
        #expect(messages[noticeIdx].sender == .system)
        #expect(messages[noticeIdx].usage?.totalTokens == 1209)
        #expect(messages[noticeIdx].content.contains("1,209"))
        #expect(noticeIdx < replyIdx)

        // Session totals: priming accumulates SEPARATELY from metered turns.
        let totals = try #require(store.sessionUsageTotals)
        #expect(totals.meteredTurns == 1)
        #expect(totals.promptTokens == 1500)
        #expect(totals.primingHops == 1)
        #expect(totals.primingTokens == 1209)
    }

    @Test @MainActor
    func nilUsagePrimingStillCountsAsAHop() async throws {
        let persistence = Self.makePersistence()
        let client = ScriptedClient()
        client.scripts = [[
            .contextPrimed(nil),
            .finished(Message(sender: .hermes, content: "ok", status: .delivered), nil, nil),
        ]]
        let store = ChatStore(hermesClient: client, persistence: persistence)

        await store.sendMessage("hop with no reported usage")

        // A hop demonstrably happened — the count must not depend on the
        // server reporting usage for the priming run.
        let totals = try #require(store.sessionUsageTotals)
        #expect(totals.primingHops == 1)
        #expect(totals.primingTokens == 0)
        let notice = try #require(store.conversation?.messages.first(where: { $0.isContextPriming }))
        #expect(notice.content == "[Context transplanted into a fresh session]")
        #expect(notice.usage == nil)
    }

    @Test @MainActor
    func primingNoticeSurvivesTheCacheRoundTrip() async throws {
        let persistence = Self.makePersistence()
        let client = ScriptedClient()
        client.scripts = [[
            .contextPrimed(TokenUsage(promptTokens: 700, completionTokens: 6, totalTokens: 706)),
            .finished(Message(sender: .hermes, content: "ok", status: .delivered), nil, nil),
        ]]
        let store = ChatStore(hermesClient: client, persistence: persistence)
        await store.sendMessage("hop")

        let cached = try #require(persistence.loadConversationCache())
        let notice = try #require(cached.messages.first(where: { $0.isContextPriming }))
        #expect(notice.usage?.totalTokens == 706)
    }

    // MARK: - ChatStore: offline queue + drain

    @Test @MainActor
    func unreachableSendQueuesDurablyInsteadOfFailing() async throws {
        let persistence = Self.makePersistence()
        let client = ScriptedClient()
        client.scripts = [[.unreachable("Could not connect to the host.")]]
        let store = ChatStore(hermesClient: client, persistence: persistence)

        await store.sendMessage("send me later")

        let messages = try #require(store.conversation?.messages)
        let queued = try #require(messages.first(where: { $0.sender == .user }))
        #expect(queued.status == .queued)
        // No failure row, no lingering placeholder.
        #expect(!messages.contains(where: { $0.status == .failed }))
        #expect(!messages.contains(where: { $0.sender == .hermes }))
        // The turn is parked durably.
        #expect(persistence.loadComposeOutboxState().pendingTurns.map(\.text) == ["send me later"])
        #expect(store.hasQueuedComposeTurns)
    }

    @Test @MainActor
    func drainSendsQueuedTurnWhenReachable() async throws {
        let persistence = Self.makePersistence()
        let client = ScriptedClient()
        client.scripts = [
            [.unreachable("Could not connect to the host.")],
            [.finished(Message(sender: .hermes, content: "delivered at last", status: .delivered), nil, nil)],
        ]
        let store = ChatStore(hermesClient: client, persistence: persistence)

        await store.sendMessage("park then send")
        #expect(store.hasQueuedComposeTurns)

        await store.drainComposeOutboxIfPossible()

        #expect(!store.hasQueuedComposeTurns)
        #expect(persistence.loadComposeOutboxState().isEmpty)
        let messages = try #require(store.conversation?.messages)
        // The queued row was replaced by the live re-send + its reply.
        #expect(messages.filter { $0.sender == .user }.count == 1)
        #expect(messages.first(where: { $0.sender == .user })?.status == .delivered)
        #expect(messages.contains(where: { $0.sender == .hermes && $0.content == "delivered at last" }))
        #expect(client.sentMessages == ["park then send", "park then send"])
    }

    @Test @MainActor
    func drainStopsAndRequeuesWhileStillUnreachable() async throws {
        let persistence = Self.makePersistence()
        let client = ScriptedClient()
        // Every send keeps failing as unreachable.
        client.scripts = [[.unreachable("Still down.")]]
        let store = ChatStore(hermesClient: client, persistence: persistence)

        await store.sendMessage("first")
        await store.drainComposeOutboxIfPossible()

        // Still exactly one queued turn — re-queued, not dropped, not duplicated.
        #expect(persistence.loadComposeOutboxState().pendingTurns.map(\.text) == ["first"])
        let queuedRows = store.conversation?.messages.filter { $0.status == .queued } ?? []
        #expect(queuedRows.count == 1)
    }

    @Test @MainActor
    func drainDropsTurnThatDuplicatesAPendingRow() async throws {
        let persistence = Self.makePersistence()
        let client = ScriptedClient()
        client.scripts = [[.unreachable("down")]]
        let store = ChatStore(hermesClient: client, persistence: persistence)

        await store.sendMessage("dup")
        #expect(store.hasQueuedComposeTurns)

        // Simulate polling-fallback residue: an identical row already pending
        // in the transcript. The drained turn's re-send trips the duplicate
        // guard — the outbox copy must be dropped (the pending row IS the
        // message), never lost into the void with the flag left stale.
        store.conversation?.messages.append(Message(sender: .user, content: "dup", status: .sending))
        await store.drainComposeOutboxIfPossible()

        #expect(!store.hasQueuedComposeTurns)
        #expect(persistence.loadComposeOutboxState().isEmpty)
        // The pending row still represents the message.
        #expect(store.conversation?.messages.contains(where: { $0.content == "dup" && $0.status == .sending }) == true)
    }

    @Test @MainActor
    func attachmentSendsStillFailHonestlyWhenUnreachable() async throws {
        let persistence = Self.makePersistence()
        let client = ScriptedClient()
        client.scripts = [[.unreachable("Could not connect to the host.")]]
        let store = ChatStore(hermesClient: client, persistence: persistence)

        let attachment = PendingAttachment(
            kind: .image,
            fileName: "photo.jpg",
            mimeType: "image/jpeg",
            data: Data([0xFF, 0xD8]),
            localStoragePath: nil,
            thumbnailData: nil
        )
        await store.sendMessage("look at this", attachments: [attachment])

        // Attachments have no durable wire form to park (#90 v1) — the send
        // fails honestly instead of queueing.
        let messages = try #require(store.conversation?.messages)
        #expect(messages.first(where: { $0.sender == .user })?.status == .failed)
        #expect(persistence.loadComposeOutboxState().isEmpty)
    }

    @Test @MainActor
    func coldLoadFlipsOrphanedQueuedRowsToFailed() async throws {
        let persistence = Self.makePersistence()
        // A cache with a queued row whose outbox entry vanished — it can
        // never drain, so cold load must give it the retry affordance.
        var convo = Conversation(title: Conversation.defaultTitle)
        convo.messages.append(Message(sender: .user, content: "stranded", status: .queued))
        persistence.saveConversationCache(convo)

        let store = ChatStore(hermesClient: ScriptedClient(), persistence: persistence)
        await store.loadConversationIfNeeded()

        #expect(store.conversation?.messages.first?.status == .failed)
    }

    @Test @MainActor
    func queuedRowsWithLiveOutboxEntriesSurviveColdLoad() async throws {
        let persistence = Self.makePersistence()
        let turnID = UUID()
        var convo = Conversation(title: Conversation.defaultTitle)
        convo.messages.append(Message(
            id: turnID,
            clientMessageID: turnID,
            sender: .user,
            content: "waiting out the outage",
            status: .queued
        ))
        persistence.saveConversationCache(convo)
        var outbox = ComposeOutboxState()
        outbox.enqueue(id: turnID, text: "waiting out the outage")
        persistence.saveComposeOutboxState(outbox)

        let client = ScriptedClient()
        client.scripts = [[.unreachable("Still down.")]]
        let store = ChatStore(hermesClient: client, persistence: persistence)
        await store.loadConversationIfNeeded()

        // The queued row is durable by design — it survives relaunch intact
        // (the load-time drain kick re-queues against a still-down host).
        let row = try #require(store.conversation?.messages.first(where: { $0.sender == .user }))
        #expect(row.status == .queued)
        #expect(store.hasQueuedComposeTurns)
    }

    // MARK: - ChatStore: journal wiring

    @Test @MainActor
    func finishedHermesExchangeJournalsAndBumpsWaterline() async throws {
        let persistence = Self.makePersistence()
        let journal = ConversationJournalStore(persistence: persistence)
        let client = ScriptedClient()
        client.scripts = [[
            .finished(
                Message(sender: .hermes, content: "the answer", status: .delivered, brain: ChatBackendRouter.Brain.hermes.rawValue),
                nil,
                nil
            ),
        ]]
        let store = ChatStore(hermesClient: client, persistence: persistence, journal: journal)
        // Adopt the thread's identity first (what launch does), THEN hop —
        // a hop on a foreign identity would rightly die at the next sync.
        await store.loadConversationIfNeeded()
        journal.beginHop(apiSessionId: "api_live", primingUsage: nil)

        await store.sendMessage("the question")

        #expect(journal.entries.map(\.text).contains("the question"))
        #expect(journal.entries.map(\.text).contains("the answer"))
        // The exchange rode the hop — the waterline covers it.
        #expect(journal.activeHopIsCurrent)
    }

    @Test @MainActor
    func finishedLocalExchangeLeavesHopStale() async throws {
        let persistence = Self.makePersistence()
        let journal = ConversationJournalStore(persistence: persistence)
        let client = ScriptedClient()
        client.scripts = [[
            .finished(
                Message(sender: .hermes, content: "local answer", status: .delivered, brain: ChatBackendRouter.Brain.onDevice.rawValue),
                nil,
                nil
            ),
        ]]
        let store = ChatStore(hermesClient: client, persistence: persistence, journal: journal)
        await store.loadConversationIfNeeded()
        journal.beginHop(apiSessionId: "api_live", primingUsage: nil)

        await store.sendMessage("local question")

        // Journaled — but the hop didn't carry it, so it reads stale and the
        // next Hermes turn transplants.
        #expect(journal.entries.count == 2)
        #expect(journal.activeHop != nil)
        #expect(journal.activeHopIsCurrent == false)
    }

    @Test @MainActor
    func clearConversationResetsJournalAndOutbox() async throws {
        let persistence = Self.makePersistence()
        let journal = ConversationJournalStore(persistence: persistence)
        let client = ScriptedClient()
        client.scripts = [[.unreachable("down")]]
        let store = ChatStore(hermesClient: client, persistence: persistence, journal: journal)

        await store.sendMessage("queued into the old thread")
        #expect(store.hasQueuedComposeTurns)

        try await store.clearConversation()

        #expect(!store.hasQueuedComposeTurns)
        #expect(persistence.loadComposeOutboxState().isEmpty)
        #expect(journal.entries.isEmpty)
        #expect(journal.activeHop == nil)
        #expect(journal.journal.conversationID == store.conversation?.id)
    }

    // MARK: - Identity stability (the churn fix)

    @Test @MainActor
    func refreshMergeKeepsLocalConversationIdentity() async throws {
        let persistence = Self.makePersistence()
        let journal = ConversationJournalStore(persistence: persistence)
        let client = ScriptedClient()
        client.scripts = [[
            .finished(Message(sender: .hermes, content: "reply", status: .delivered), nil, nil),
        ]]
        let store = ChatStore(hermesClient: client, persistence: persistence, journal: journal)

        await store.loadConversationIfNeeded()
        let originalID = try #require(store.conversation?.id)

        // The client mints a NEW Conversation UUID for its post-turn view —
        // the merge must keep the local identity (otherwise the journal
        // resets and the hop drops on every refresh).
        client.currentConversation = Conversation(
            title: Conversation.defaultTitle,
            messages: [Message(sender: .hermes, content: "reply", status: .delivered)]
        )
        await store.sendMessage("hello")

        #expect(store.conversation?.id == originalID)
        #expect(journal.journal.conversationID == originalID)
    }
}
