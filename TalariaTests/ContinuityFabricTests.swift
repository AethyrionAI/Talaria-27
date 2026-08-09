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
    func composeOutboxEnqueueDedupesByTranscriptRow() {
        var state = ComposeOutboxState()
        let rowID = UUID()
        let entryID = state.enqueueUnreachable(transcriptRowID: rowID, text: "offline turn")
        let second = state.enqueueUnreachable(transcriptRowID: rowID, text: "offline turn")
        #expect(state.pendingTurns.count == 1)
        // The dedupe hands back the EXISTING entry's id, so a re-park can
        // still address the entry by identity (#306 T1).
        #expect(second == entryID)
        state.remove(entryID: entryID)
        #expect(state.isEmpty)
    }

    @Test
    func composeOutboxEntryIDIsNotTheTranscriptRowID() {
        // #306 T1 — the broken fusion: the entry's durable id and the
        // transcript row's clientMessageID are two identities with two jobs.
        var state = ComposeOutboxState()
        let rowID = UUID()
        let entryID = state.enqueueUnreachable(transcriptRowID: rowID, text: "parked")
        let turn = state.pendingTurns[0]
        #expect(entryID != rowID)
        #expect(turn.id == entryID)
        #expect(turn.transcriptRowID == rowID)
        #expect(turn.reason == .unreachable)
        #expect(turn.phase == .released)
    }

    @Test @MainActor
    func composeOutboxPersistsAndClearsWhenEmpty() {
        let persistence = Self.makePersistence()
        var state = ComposeOutboxState()
        state.enqueueUnreachable(transcriptRowID: UUID(), text: "park me")
        persistence.saveComposeOutboxState(state)
        #expect(persistence.loadComposeOutboxState().pendingTurns.first?.text == "park me")

        // Saving an emptied state clears the stored blob (the sensor-outbox
        // hygiene pattern).
        persistence.saveComposeOutboxState(ComposeOutboxState())
        #expect(persistence.loadComposeOutboxState().isEmpty)
    }

    @Test @MainActor
    func legacyOutboxPayloadDecodesWithoutEmptyingTheOutbox() throws {
        // #306 T1 decode-compat bar: a pre-#306 payload carries only the
        // fused {id, text, composedAt} shape. `UserDefaultsAppPersistenceStore`
        // returns a DEFAULT on decode failure, so a schema break here would
        // silently empty a real user's parked turns — this pins the legacy
        // payload surviving the reshape with its old semantics intact.
        struct LegacyTurn: Codable {
            let id: UUID
            let text: String
            let composedAt: Date
        }
        struct LegacyState: Codable {
            var pendingTurns: [LegacyTurn]
        }
        let suiteName = "continuity-fabric-legacy-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)

        let fusedID = UUID()
        let composedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let legacy = LegacyState(pendingTurns: [
            LegacyTurn(id: fusedID, text: "parked before the reshape", composedAt: composedAt),
        ])
        defaults.set(try encoder.encode(legacy), forKey: "hermes.composeOutboxState")

        let loaded = persistence.loadComposeOutboxState()
        #expect(loaded.pendingTurns.count == 1)
        let turn = try #require(loaded.pendingTurns.first)
        #expect(turn.text == "parked before the reshape")
        // The fused id keeps BOTH jobs it already had.
        #expect(turn.id == fusedID)
        #expect(turn.transcriptRowID == fusedID)
        #expect(turn.reason == .unreachable)
        #expect(turn.phase == .released)
        #expect(turn.threadKey == nil)
    }

    @Test @MainActor
    func reshapedOutboxStateRoundTrips() throws {
        let persistence = Self.makePersistence()
        // Whole-second dates: the store's ISO8601 coding drops sub-second
        // precision, and this test asserts value equality across the trip.
        let composedAt = Date(timeIntervalSince1970: 1_750_000_100)
        var state = ComposeOutboxState()
        state.enqueueUnreachable(
            transcriptRowID: UUID(), text: "parked", threadKey: "api_1", composedAt: composedAt
        )
        var held = state.hold(text: "held mid-turn", threadKey: "api_1", composedAt: composedAt)
        held.phase = .surfaced
        state.update(held)

        persistence.saveComposeOutboxState(state)
        let loaded = persistence.loadComposeOutboxState()
        #expect(loaded == state)
        let reloadedHeld = try #require(loaded.pendingTurns.first(where: { $0.reason == .heldDuringTurn }))
        #expect(reloadedHeld.id == held.id)
        #expect(reloadedHeld.phase == .surfaced)
        #expect(reloadedHeld.transcriptRowID == nil)
        #expect(reloadedHeld.threadKey == "api_1")
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
        /// #240: scripted server history for the drain-time adoption guard.
        /// nil = fetch failed / no server-backed session — drain as before.
        var reconcileConversation: Conversation?

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

        func reconcileFromServer() async -> Conversation? { reconcileConversation }
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

    // MARK: - #240: drain-time adoption guard

    @Test @MainActor
    func drainAdoptsTurnAlreadyDeliveredServerSide() async throws {
        let persistence = Self.makePersistence()
        let client = ScriptedClient()
        client.scripts = [[.unreachable("down")]]
        let store = ChatStore(hermesClient: client, persistence: persistence)

        await store.sendMessage("was the steam sale worth it")
        #expect(store.hasQueuedComposeTurns)

        // The server already holds the question: the park was the
        // accepted-but-pre-run.started misclassification (#240) — the turn
        // WAS delivered; only the client's stream died.
        var serverConvo = Conversation(title: Conversation.defaultTitle)
        serverConvo.messages = [
            Message(sender: .user, content: "was the steam sale worth it", status: .delivered),
            Message(sender: .hermes, content: "Yes — 60% off.", status: .delivered),
        ]
        client.reconcileConversation = serverConvo

        await store.drainComposeOutboxIfPossible()

        // Adopted, not re-sent: the park-time send stays the only send.
        #expect(client.sentMessages == ["was the steam sale worth it"])
        #expect(!store.hasQueuedComposeTurns)
        #expect(persistence.loadComposeOutboxState().isEmpty)
        #expect(store.conversation?.messages.contains(where: { $0.status == .queued }) == false)
    }

    @Test @MainActor
    func drainStillResendsTurnAbsentFromServerHistory() async throws {
        let persistence = Self.makePersistence()
        let client = ScriptedClient()
        client.scripts = [
            [.unreachable("down")],
            [.finished(Message(sender: .hermes, content: "delivered at last", status: .delivered), nil, nil)],
        ]
        let store = ChatStore(hermesClient: client, persistence: persistence)

        await store.sendMessage("never made it")

        var serverConvo = Conversation(title: Conversation.defaultTitle)
        serverConvo.messages = [
            Message(sender: .user, content: "some other question", status: .delivered),
        ]
        client.reconcileConversation = serverConvo

        await store.drainComposeOutboxIfPossible()

        #expect(client.sentMessages == ["never made it", "never made it"])
        #expect(!store.hasQueuedComposeTurns)
    }

    @Test @MainActor
    func drainWithNilHistoryFetchDrainsAsToday() async throws {
        let persistence = Self.makePersistence()
        let client = ScriptedClient()
        client.scripts = [
            [.unreachable("down")],
            [.finished(Message(sender: .hermes, content: "delivered at last", status: .delivered), nil, nil)],
        ]
        let store = ChatStore(hermesClient: client, persistence: persistence)

        await store.sendMessage("offline drain")
        // reconcileConversation stays nil — the fetch "failed"; the guard is
        // an optimization, not a gate (offline drains must still work).

        await store.drainComposeOutboxIfPossible()

        #expect(client.sentMessages == ["offline drain", "offline drain"])
        #expect(!store.hasQueuedComposeTurns)
    }

    @Test
    func adoptionPredicateMatchesTrimmedTextWithinClockSkewWindow() {
        let composedAt = Date(timeIntervalSince1970: 1_000_000)
        let turn = ComposeOutboxState.PendingTurn(
            reason: .unreachable, transcriptRowID: UUID(),
            text: "  hello there \n", composedAt: composedAt, phase: .released
        )

        let match = Message(sender: .user, content: "hello there", timestamp: composedAt.addingTimeInterval(-59), status: .delivered)
        #expect(ChatStore.historyAdoptsQueuedTurn(turn, serverMessages: [match]))

        let tooOld = Message(sender: .user, content: "hello there", timestamp: composedAt.addingTimeInterval(-61), status: .delivered)
        #expect(!ChatStore.historyAdoptsQueuedTurn(turn, serverMessages: [tooOld]))
    }

    @Test
    func adoptionPredicateIgnoresNonUserAndDifferentText() {
        let composedAt = Date.now
        let turn = ComposeOutboxState.PendingTurn(
            reason: .unreachable, transcriptRowID: UUID(),
            text: "hello", composedAt: composedAt, phase: .released
        )

        let hermesEcho = Message(sender: .hermes, content: "hello", timestamp: composedAt, status: .delivered)
        let different = Message(sender: .user, content: "hello?", timestamp: composedAt, status: .delivered)
        #expect(!ChatStore.historyAdoptsQueuedTurn(turn, serverMessages: [hermesEcho, different]))
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
        outbox.enqueueUnreachable(transcriptRowID: turnID, text: "waiting out the outage")
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

    // MARK: - #306: the mid-turn hold meets the outbox (bars 306-G / 306-H)

    /// Hands each stream's continuation to the test so a hold can be
    /// committed MID-turn and the terminal driven explicitly. Sends made
    /// under `autoFinishSends` (the drain's re-sends) complete immediately.
    @MainActor
    private final class HoldableStreamClient: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .connected
        var currentConversation: Conversation?
        private(set) var sentMessages: [String] = []
        private(set) var continuations: [AsyncStream<StreamingUpdate>.Continuation] = []
        var autoFinishSends = false
        var reconcileConversation: Conversation?

        func connect() async {}
        func disconnect() async {}

        func send(message: String, attachments: [PendingAttachment], clientMessageID: UUID) async -> Message {
            Message(sender: .hermes, content: "unused", status: .delivered)
        }

        func sendStreaming(
            message: String,
            attachments: [PendingAttachment],
            clientMessageID: UUID
        ) -> AsyncStream<StreamingUpdate> {
            sentMessages.append(message)
            let autoFinish = autoFinishSends
            return AsyncStream { continuation in
                continuation.yield(.messageSent(jobID: UUID()))
                if autoFinish {
                    continuation.yield(.finished(
                        Message(sender: .hermes, content: "auto-reply: \(message)", status: .delivered),
                        nil, nil
                    ))
                    continuation.finish()
                } else {
                    self.continuations.append(continuation)
                }
            }
        }

        func loadConversation() async -> Conversation {
            currentConversation ?? Conversation(title: Conversation.defaultTitle)
        }

        func clearConversation() async throws -> Conversation {
            Conversation(title: Conversation.defaultTitle)
        }

        func openSession(_ id: String) async throws -> Conversation {
            Conversation(title: "session \(id)")
        }

        func reconcileFromServer() async -> Conversation? { reconcileConversation }
    }

    @MainActor
    private func pollUntil(
        timeout: Duration = .seconds(5),
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    @Test @MainActor
    func unreachableDemotesHeldTurnIntoTheSameOutboxBehindTheParkedTurn() async throws {
        // Bar 306-G: a mid-turn hold whose turn ends `.unreachable` lands in
        // the SAME outbox BEHIND the just-parked turn; the drain then posts
        // everything oldest-first; nothing is lost. One store, one order.
        let persistence = Self.makePersistence()
        let client = HoldableStreamClient()
        let store = ChatStore(hermesClient: client, persistence: persistence)

        // An earlier offline park.
        let firstTask = Task { @MainActor in await store.sendMessage("park me") }
        var live = await pollUntil { client.continuations.count == 1 }
        #expect(live)
        client.continuations[0].yield(.unreachable("down"))
        client.continuations[0].finish()
        _ = await firstTask.value
        #expect(store.hasQueuedComposeTurns)

        // A second turn goes out; the user queues a follow-up mid-turn; the
        // turn then fails to reach the host at all.
        let secondTask = Task { @MainActor in await store.sendMessage("turn two") }
        live = await pollUntil { client.continuations.count == 2 }
        #expect(live)
        #expect(store.holdComposedTurn("held follow"))
        client.continuations[1].yield(.unreachable("still down"))
        client.continuations[1].finish()
        _ = await secondTask.value

        // Same store, correct order: parked turns first, the demoted hold
        // BEHIND the turn that just failed.
        #expect(persistence.loadComposeOutboxState().pendingTurns.map(\.text)
            == ["park me", "turn two", "held follow"])

        // Reachability returns — the drain posts oldest-first.
        client.autoFinishSends = true
        await store.drainComposeOutboxIfPossible()

        let parkIdx = try #require(client.sentMessages.lastIndex(of: "park me"))
        let twoIdx = try #require(client.sentMessages.lastIndex(of: "turn two"))
        let heldIdx = try #require(client.sentMessages.lastIndex(of: "held follow"))
        #expect(parkIdx < twoIdx && twoIdx < heldIdx, "306-G: oldest-first, neither lost")
        #expect(persistence.loadComposeOutboxState().isEmpty)
        #expect(store.currentThreadHeldTurn == nil)
    }

    @Test @MainActor
    func heldTurnIsThreadScopedAcrossSessionSwitches() async throws {
        // Bar 306-H: a message held in thread A is not posted, not visible,
        // and not fired while thread B runs; returning to A restores it.
        let persistence = Self.makePersistence()
        let client = HoldableStreamClient()
        let store = ChatStore(hermesClient: client, persistence: persistence)

        await store.openSession("A")

        let turnInA = Task { @MainActor in await store.sendMessage("turn in A") }
        let live = await pollUntil { client.continuations.count == 1 }
        #expect(live)
        #expect(store.holdComposedTurn("held in A"))

        // Walk away to thread B mid-turn — `abandonPendingRun` is the seam.
        await store.openSession("B")
        _ = await turnInA.value

        #expect(store.currentThreadHeldTurn == nil, "306-H: A's hold must not be visible in B")

        // A full completed turn in B must not fire A's hold.
        client.autoFinishSends = true
        await store.sendMessage("turn in B")
        try? await Task.sleep(for: .milliseconds(150))
        #expect(!client.sentMessages.contains("held in A"), "306-H: A's hold must never fire in B")

        // Returning to A restores it — surfaced, because the turn it waited
        // on was abandoned by the walk-away (matrix row 11).
        await store.openSession("A")
        let restored = try #require(store.currentThreadHeldTurn)
        #expect(restored.text == "held in A")
        #expect(restored.phase == .surfaced)
    }

    @Test @MainActor
    func heldTurnSurvivesNewChatAndReturnsWithItsThread() async throws {
        // #306 row 11, the NEW CHAT arm (review round 1 fix): M-15 made New
        // Chat non-destructive — the departing thread stays in the drawer,
        // reopenable — so a held message PARKS with its thread instead of
        // dying with the clear, surfaces, never fires into the fresh thread,
        // and is restored on return. (`.unreachable` parks keep the #90
        // die-with-the-clear precedent — pinned separately by
        // `clearConversationResetsJournalAndOutbox`.)
        let persistence = Self.makePersistence()
        let client = HoldableStreamClient()
        let store = ChatStore(hermesClient: client, persistence: persistence)

        await store.openSession("A")
        let turnInA = Task { @MainActor in await store.sendMessage("turn in A") }
        let live = await pollUntil { client.continuations.count == 1 }
        #expect(live)
        #expect(store.holdComposedTurn("held across new chat"))

        try await store.clearConversation()
        _ = await turnInA.value

        // The fresh thread sees nothing of A's hold…
        #expect(store.currentThreadHeldTurn == nil)
        // …and it survives durably, parked with thread A.
        #expect(persistence.loadComposeOutboxState().pendingTurns.contains {
            $0.text == "held across new chat" && $0.threadKey == "A"
        })

        // A full completed turn in the new chat fires nothing of A's.
        client.autoFinishSends = true
        await store.sendMessage("turn in new chat")
        try? await Task.sleep(for: .milliseconds(150))
        #expect(!client.sentMessages.contains("held across new chat"))

        // Reopening A from the drawer restores the hold, surfaced.
        await store.openSession("A")
        let restored = try #require(store.currentThreadHeldTurn)
        #expect(restored.text == "held across new chat")
        #expect(restored.phase == .surfaced)
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
