import Foundation
import Testing
@testable import Talaria

/// #190 — standalone sessions become a real store, not a single slot: the
/// local backend lists/opens stored sessions, ChatStore's walk-away teardown
/// persists the outgoing thread, the legacy single-slot cache is adopted
/// idempotently, the router unifies the drawer's list across sources, and
/// read-aloud stops on a session switch (the audible #184 leak).
struct LocalSessionHistoryTests {

    // MARK: - Shared fixtures

    /// Dict-backed `LocalSessionStoring` so backend/store interactions are
    /// asserted without a live SwiftData container.
    @MainActor
    private final class FakeSessionStore: LocalSessionStoring {
        private(set) var sessions: [UUID: Conversation] = [:]
        private(set) var upsertedIDs: [UUID] = []
        private(set) var stubs: [HermesSessionInfo] = []
        /// #190B: ids whose row exists but whose transcript reads as
        /// undecodable — models the store's decode-nil path.
        var unreadableIDs: Set<UUID> = []

        func upsertSession(_ conversation: Conversation) {
            sessions[conversation.id] = conversation
            upsertedIDs.append(conversation.id)
        }

        func sessionSummaries() -> [LocalSessionSummary] {
            sessions.values
                .sorted { $0.lastActivity > $1.lastActivity }
                .map { convo in
                    LocalSessionSummary(
                        id: convo.id,
                        title: convo.title,
                        preview: convo.generatedPreview ?? convo.lastMessage?.content,
                        messageCount: convo.messages.count,
                        createdAt: convo.messages.first?.timestamp ?? convo.lastActivity,
                        lastActivity: convo.lastActivity
                    )
                }
        }

        func conversation(withID id: UUID) -> Conversation? {
            guard !unreadableIDs.contains(id) else { return nil }
            return sessions[id]
        }

        func hasSession(withID id: UUID) -> Bool {
            sessions[id] != nil
        }

        func recordRemoteSessionStubs(_ infos: [HermesSessionInfo]) {
            stubs = infos
        }

        func remoteSessionStubs() -> [HermesSessionInfo] {
            stubs
        }
    }

    @MainActor private func makePersistence() -> UserDefaultsAppPersistenceStore {
        let suiteName = "local-session-history-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsAppPersistenceStore(defaults: defaults)
    }

    @MainActor private func makeScratchDefaults() -> UserDefaults {
        let suiteName = "local-session-router-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func localConversation(
        id: UUID = UUID(),
        prompt: String,
        reply: String,
        lastActivity: Date
    ) -> Conversation {
        Conversation(
            id: id,
            title: "Hermes",
            messages: [
                Message(sender: .user, content: prompt, status: .delivered),
                Message(sender: .hermes, content: reply, status: .delivered, brain: "on-device"),
            ],
            lastActivity: lastActivity
        )
    }

    private func remoteInfo(id: String, lastActive: Date?) -> HermesSessionInfo {
        HermesSessionInfo(
            id: id, title: "Server \(id)", preview: nil, model: "opus",
            source: "chat", messageCount: 3, lastActive: lastActive, isActive: false
        )
    }

    // MARK: - LocalChatBackend sessions (#190 Phase 2)

    @MainActor private func makeBackend(
        persistence: UserDefaultsAppPersistenceStore,
        store: FakeSessionStore,
        isLocalThread: @escaping @MainActor (Conversation) -> Bool = { _ in true }
    ) -> LocalChatBackend {
        LocalChatBackend(
            persistence: persistence,
            intelligence: LocalIntelligenceService(),
            sessionStore: store,
            isLocalThread: isLocalThread
        )
    }

    @Test @MainActor
    func backendListsStoredSessionsMostRecentFirst() async throws {
        let persistence = makePersistence()
        let store = FakeSessionStore()
        let older = localConversation(prompt: "first", reply: "one", lastActivity: Date(timeIntervalSince1970: 1_000))
        let newer = localConversation(prompt: "second", reply: "two", lastActivity: Date(timeIntervalSince1970: 2_000))
        store.upsertSession(older)
        store.upsertSession(newer)
        let backend = makeBackend(persistence: persistence, store: store)

        let infos = try await backend.listSessions()
        #expect(infos.map(\.id) == [newer.id.uuidString, older.id.uuidString])
        #expect(infos.allSatisfy { $0.source == LocalChatBackend.localSessionSource })
    }

    @Test @MainActor
    func backendMergesLiveConversationOverItsStaleStoredRow() async throws {
        let persistence = makePersistence()
        let store = FakeSessionStore()
        let id = UUID()
        // The store holds the copy persisted at the last walk-away…
        store.upsertSession(localConversation(id: id, prompt: "old", reply: "old", lastActivity: Date(timeIntervalSince1970: 1_000)))
        // …while the cache (the live thread's restore source) has moved on.
        var live = localConversation(id: id, prompt: "old", reply: "old", lastActivity: Date(timeIntervalSince1970: 9_000))
        live.messages.append(Message(sender: .user, content: "newer", status: .delivered))
        persistence.saveConversationCache(live)
        let backend = makeBackend(persistence: persistence, store: store)

        let infos = try await backend.listSessions()
        #expect(infos.count == 1)
        #expect(infos.first?.messageCount == 3, "the live copy outranks its stale stored row")
        #expect(infos.first?.isActive == true)
    }

    @Test @MainActor
    func backendOpensStoredSessionByID() async throws {
        let persistence = makePersistence()
        let store = FakeSessionStore()
        let stored = localConversation(prompt: "stored", reply: "kept", lastActivity: Date(timeIntervalSince1970: 4_000))
        store.upsertSession(stored)
        let backend = makeBackend(persistence: persistence, store: store)

        let opened = try await backend.openSession(stored.id.uuidString)
        #expect(opened == stored)
        // The opened session is now the live thread.
        let current = await backend.loadConversation()
        #expect(current.id == stored.id)
    }

    /// #233: switching to a stored conversation is a conversation boundary —
    /// the wee-hour AM/PM ask re-arms there exactly like the #30 escalation
    /// offer resets. (Reopening the SAME conversation is the early-return
    /// path and deliberately keeps the latch.)
    @Test @MainActor
    func openingAStoredSessionResetsTheWeeHourAskLatch() async throws {
        let persistence = makePersistence()
        let store = FakeSessionStore()
        let stored = localConversation(prompt: "stored", reply: "kept", lastActivity: Date(timeIntervalSince1970: 4_000))
        store.upsertSession(stored)
        let backend = makeBackend(persistence: persistence, store: store)
        let relay = ToolEventRelay()
        backend.installTools([], relay: relay)

        #expect(relay.claimEarlyMorningAsk())
        _ = try await backend.openSession(stored.id.uuidString)
        #expect(relay.claimEarlyMorningAsk())
    }

    @Test @MainActor
    func backendOpenSessionUnknownIDThrows() async throws {
        let persistence = makePersistence()
        let backend = makeBackend(persistence: persistence, store: FakeSessionStore())
        await #expect(throws: (any Error).self) {
            _ = try await backend.openSession(UUID().uuidString)
        }
    }

    // MARK: - Legacy single-slot adoption (#190 Phase 3)

    @Test @MainActor
    func legacyCachedConversationIsAdoptedAsFirstSession() async throws {
        let persistence = makePersistence()
        let store = FakeSessionStore()
        let legacy = localConversation(prompt: "pre-upgrade", reply: "kept", lastActivity: Date(timeIntervalSince1970: 2_000))
        persistence.saveConversationCache(legacy)

        let backend = makeBackend(persistence: persistence, store: store)
        _ = try await backend.listSessions()

        #expect(store.sessions[legacy.id] != nil, "the upgrade must not drop the existing conversation")
        // The cache itself stays — it is the kill/relaunch restore path.
        #expect(persistence.loadConversationCache()?.id == legacy.id)
    }

    @Test @MainActor
    func legacyAdoptionIsIdempotentAcrossRelaunches() async throws {
        let persistence = makePersistence()
        let store = FakeSessionStore()
        let legacy = localConversation(prompt: "once", reply: "only", lastActivity: Date(timeIntervalSince1970: 2_000))
        persistence.saveConversationCache(legacy)

        let firstLaunch = makeBackend(persistence: persistence, store: store)
        _ = try await firstLaunch.listSessions()
        _ = try await firstLaunch.listSessions()
        // A fresh backend over the same store + cache is a relaunch.
        let secondLaunch = makeBackend(persistence: persistence, store: store)
        _ = try await secondLaunch.listSessions()

        #expect(store.sessions.count == 1, "running the migration twice must not produce two copies")
    }

    @Test @MainActor
    func nonLocalCachedConversationIsNotAdopted() async throws {
        let persistence = makePersistence()
        let store = FakeSessionStore()
        persistence.saveConversationCache(
            localConversation(prompt: "hermes thread", reply: "server", lastActivity: .now)
        )

        let backend = makeBackend(persistence: persistence, store: store, isLocalThread: { _ in false })
        let infos = try await backend.listSessions()

        #expect(store.sessions.isEmpty, "a paired-mode thread must not enter the local store")
        #expect(infos.isEmpty)
    }

    // MARK: - ChatStore walk-away persistence (#190 Phase 2, via #184's primitive)

    @MainActor
    private final class SessionSwitchingClient: HermesClientProtocol {
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
            AsyncStream { $0.finish() }
        }

        func loadConversation() async -> Conversation {
            currentConversation ?? Conversation(title: "Hermes")
        }

        func clearConversation() async throws -> Conversation {
            Conversation(title: "Hermes")
        }

        func openSession(_ id: String) async throws -> Conversation {
            Conversation(title: "S2", messages: [
                Message(sender: .hermes, content: "S2 history", status: .delivered),
            ])
        }
    }

    @MainActor
    private func makeChatStore(
        persistence: UserDefaultsAppPersistenceStore,
        store: FakeSessionStore,
        outgoing: Conversation,
        isLocal: @escaping @MainActor (Conversation) -> Bool = { _ in true }
    ) async -> ChatStore {
        persistence.saveConversationCache(outgoing)
        let chatStore = ChatStore(hermesClient: SessionSwitchingClient(), persistence: persistence)
        chatStore.localSessions = store
        chatStore.isLocalSessionThread = isLocal
        await chatStore.loadConversationIfNeeded()
        return chatStore
    }

    @Test @MainActor
    func newChatPersistsOutgoingConversationBeforeClearing() async throws {
        let persistence = makePersistence()
        let store = FakeSessionStore()
        let outgoing = localConversation(prompt: "keep me", reply: "kept", lastActivity: Date(timeIntervalSince1970: 3_000))
        let chatStore = await makeChatStore(persistence: persistence, store: store, outgoing: outgoing)

        try await chatStore.clearConversation()

        #expect(store.sessions[outgoing.id]?.messages.count == 2, "New must persist the outgoing thread before it clears")
        #expect(chatStore.conversation?.messages.isEmpty == true)
    }

    @Test @MainActor
    func openSessionPersistsOutgoingConversation() async throws {
        let persistence = makePersistence()
        let store = FakeSessionStore()
        let outgoing = localConversation(prompt: "departing", reply: "thread", lastActivity: Date(timeIntervalSince1970: 3_000))
        let chatStore = await makeChatStore(persistence: persistence, store: store, outgoing: outgoing)

        await chatStore.openSession("S2")

        #expect(store.sessions[outgoing.id] != nil, "switching sessions must persist the departing thread")
        #expect(chatStore.conversation?.title == "S2")
    }

    @Test @MainActor
    func resetPersistsOutgoingConversation() async throws {
        let persistence = makePersistence()
        let store = FakeSessionStore()
        let outgoing = localConversation(prompt: "pairing over", reply: "bye", lastActivity: Date(timeIntervalSince1970: 3_000))
        let chatStore = await makeChatStore(persistence: persistence, store: store, outgoing: outgoing)

        chatStore.reset()

        #expect(store.sessions[outgoing.id] != nil, "the pairing-lifecycle reset must not destroy standalone history")
    }

    @Test @MainActor
    func walkAwayDoesNotPersistNonLocalOrEmptyThreads() async throws {
        let persistence = makePersistence()
        let hermesStore = FakeSessionStore()
        let hermesThread = localConversation(prompt: "hermes", reply: "thread", lastActivity: .now)
        let hermesChatStore = await makeChatStore(
            persistence: persistence,
            store: hermesStore,
            outgoing: hermesThread,
            isLocal: { _ in false }
        )
        try await hermesChatStore.clearConversation()
        #expect(hermesStore.sessions.isEmpty, "a Hermes thread must never enter the local store")

        let emptyStore = FakeSessionStore()
        let emptyPersistence = makePersistence()
        let emptyChatStore = await makeChatStore(
            persistence: emptyPersistence,
            store: emptyStore,
            outgoing: Conversation(title: "Hermes")
        )
        try await emptyChatStore.clearConversation()
        #expect(emptyStore.sessions.isEmpty, "an empty thread is not history")
    }

    // MARK: - Read-aloud stops on session switch (#190, closing #184's audible leak)

    @Test @MainActor
    func openSessionStopsReadAloud() async throws {
        let persistence = makePersistence()
        let chatStore = ChatStore(hermesClient: SessionSwitchingClient(), persistence: persistence)
        let speech = SpeechOutputService()
        speech.managesAudioSession = false
        chatStore.speechOutput = speech

        let speakingID = UUID()
        speech.enqueueStreamChunk("Reading session one aloud. ", messageID: speakingID)
        #expect(speech.speakingMessageID == speakingID)

        await chatStore.openSession("S2")

        #expect(speech.speakingMessageID == nil, "audio from session A must not keep playing over session B")
    }

    // MARK: - Router: the unified drawer list (#190 Phase 4)

    @MainActor
    private final class ScriptedClient: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .connected
        var currentConversation: Conversation?
        var sessions: [HermesSessionInfo] = []
        var listError: Error?
        var openError: Error?
        private(set) var openedIDs: [String] = []
        /// 425-D: when set, `listSessions()` parks here — the window in which
        /// an interim publication either happened or did not. Nil for every
        /// pre-existing test, which therefore behaves exactly as before.
        var listGate: ListGate?
        /// Non-vacuity witness: an assertion made about the parked window is
        /// only meaningful once the call has actually arrived.
        private(set) var listCallCount = 0

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

        func loadConversation() async -> Conversation { Conversation(title: "Hermes") }
        func clearConversation() async throws -> Conversation { Conversation(title: "Hermes") }

        func listSessions() async throws -> [HermesSessionInfo] {
            listCallCount += 1
            if let listGate { await listGate.park() }
            if let listError { throw listError }
            return sessions
        }

        func openSession(_ id: String) async throws -> Conversation {
            if let openError { throw openError }
            openedIDs.append(id)
            return Conversation(title: "opened \(id)")
        }
    }

    private struct StubError: Error {}

    @MainActor
    private func makeRouter(
        hermes: ScriptedClient,
        local: ScriptedClient,
        configured: Bool
    ) -> ChatBackendRouter {
        ChatBackendRouter(
            hermes: hermes,
            local: local,
            isHermesConfigured: { configured },
            hasHermesHost: { configured },
            defaults: makeScratchDefaults()
        )
    }

    @Test @MainActor
    func routerMergesBothSourcesByRecency() async throws {
        let hermes = ScriptedClient()
        let local = ScriptedClient()
        hermes.sessions = [
            remoteInfo(id: "h-new", lastActive: Date(timeIntervalSince1970: 3_000)),
            remoteInfo(id: "h-old", lastActive: Date(timeIntervalSince1970: 1_000)),
        ]
        let localID = UUID().uuidString
        local.sessions = [
            HermesSessionInfo(
                id: localID, title: "Local", preview: nil, model: "on-device",
                source: "local", messageCount: 2,
                lastActive: Date(timeIntervalSince1970: 2_000), isActive: false
            ),
        ]
        var recorded: [HermesSessionInfo] = []
        let router = makeRouter(hermes: hermes, local: local, configured: true)
        router.recordRemoteSessions = { recorded = $0 }

        let merged = try await router.listSessions()

        #expect(merged.map(\.id) == ["h-new", localID, "h-old"], "one unified list, sorted globally by recency")
        #expect(recorded.map(\.id) == ["h-new", "h-old"], "a live Hermes list must be snapshotted for the post-unpair drawer")
    }

    @Test @MainActor
    func routerSurfacesRemoteStubsDimmedWhenUnconfigured() async throws {
        let hermes = ScriptedClient()
        let local = ScriptedClient()
        let localID = UUID().uuidString
        local.sessions = [
            HermesSessionInfo(
                id: localID, title: "Local", preview: nil, model: "on-device",
                source: "local", messageCount: 2,
                lastActive: Date(timeIntervalSince1970: 2_000), isActive: true
            ),
        ]
        let router = makeRouter(hermes: hermes, local: local, configured: false)
        router.remoteSessionStubs = { [self.remoteInfo(id: "h-gone", lastActive: Date(timeIntervalSince1970: 9_000))] }

        let merged = try await router.listSessions()

        #expect(merged.map(\.id) == ["h-gone", localID])
        let stub = try #require(merged.first)
        #expect(stub.isResumable == false, "an unpaired host's sessions stay visible, not hidden")
        #expect(stub.unresumableReason == ChatBackendRouter.unresumableReason)
    }

    // MARK: - Router: the shelf survives an unreachable host (#425)
    //
    // SUPERSEDES `routerListStillThrowsWhenConfiguredHermesFails`, which
    // pinned the #190 note's "a HERMES failure still throws exactly as
    // before" as if it were a promise. It was the defect: the router fetched
    // the local rows FIRST and then discarded them with the throw, and
    // `ChatStore.loadSessions` served `lastLoadedSessions` — zero rows in any
    // launch that had not completed one successful host list. Owen's phone
    // dropped off the tailnet on 2026-09-04 and the whole shelf went blank,
    // Local and PCC threads included.

    /// **425-A.** A configured host whose `listSessions()` throws must not
    /// take the local shelf down with it: every local row survives, the last
    /// host snapshot rides along dimmed, and the call does NOT throw.
    ///
    /// Isolating mutation M-A: restore the rethrow in
    /// `ChatBackendRouter.listSessions()` → this row reds.
    @Test @MainActor
    func routerServesLocalRowsWhenConfiguredHostIsUnreachable() async throws {
        let hermes = ScriptedClient()
        let local = ScriptedClient()
        hermes.listError = StubError()
        let localNewID = UUID().uuidString
        let localOldID = UUID().uuidString
        local.sessions = [
            HermesSessionInfo(
                id: localNewID, title: "Local new", preview: nil, model: "on-device",
                source: "local", messageCount: 2,
                lastActive: Date(timeIntervalSince1970: 4_000), isActive: false
            ),
            HermesSessionInfo(
                id: localOldID, title: "Local old", preview: nil, model: "on-device",
                source: "local", messageCount: 4,
                lastActive: Date(timeIntervalSince1970: 2_000), isActive: false
            ),
        ]
        let router = makeRouter(hermes: hermes, local: local, configured: true)
        router.remoteSessionStubs = {
            [
                self.remoteInfo(id: "h-new", lastActive: Date(timeIntervalSince1970: 5_000)),
                self.remoteInfo(id: "h-old", lastActive: Date(timeIntervalSince1970: 1_000)),
            ]
        }

        let merged = try await router.listSessions()

        #expect(merged.map(\.id) == ["h-new", localNewID, localOldID, "h-old"],
                "an unreachable host must cost the shelf nothing it already had on the phone")
        let localRows = merged.filter { $0.id == localNewID || $0.id == localOldID }
        #expect(localRows.count == 2, "every local row survives a host-list failure")
        #expect(localRows.allSatisfy { $0.isResumable },
                "a local row opens on the local backend — the host being away cannot make it unopenable")
        let stubs = merged.filter { $0.id == "h-new" || $0.id == "h-old" }
        #expect(stubs.count == 2, "the last host snapshot stays visible rather than vanishing")
        #expect(stubs.allSatisfy { $0.isResumable == false },
                "a row this app cannot open right now must say so, not offer a tap that fails")
        #expect(stubs.allSatisfy { $0.unresumableReason == ChatBackendRouter.hostUnreachableReason },
                "the dimmed reason names the true cause: the host is unreachable, not unpaired")
    }

    /// **425-D (fix round 1).** A CANCELLED load is not an unreachable host,
    /// and must not be degraded into one.
    ///
    /// Two screens list sessions from a cancellable `.task`
    /// (`SettingsChannelsScreen`, `SessionsSettingsScreen`); dismissing the
    /// sheet cancels the in-flight `URLSession` fetch, which surfaces as
    /// `URLError(.cancelled)` out of `SessionsHermesClient.listSessions`'
    /// single-profile path. Swallowing that would make `ChatStore.loadSessions`
    /// take its SUCCESS path — writing the dimmed list into
    /// `lastLoadedSessions` and stamping `lastSessionsLoadAt`, so a good list
    /// from a slow-but-REACHABLE host is replaced by unopenable rows and
    /// CACHED for the 15 s snapshot TTL. A cancellation is the caller walking
    /// away, not the host being away.
    ///
    /// Isolating mutation M-D: drop the cancellation re-throw at the top of
    /// the catch → this row and its `CancellationError` twin red, nothing else.
    @Test @MainActor
    func routerRethrowsAURLCancellationInsteadOfServingTheDegradedList() async throws {
        let hermes = ScriptedClient()
        let local = ScriptedClient()
        hermes.listError = URLError(.cancelled)
        local.sessions = [
            HermesSessionInfo(
                id: UUID().uuidString, title: "Local", preview: nil, model: "on-device",
                source: "local", messageCount: 2,
                lastActive: Date(timeIntervalSince1970: 2_000), isActive: false
            ),
        ]
        let router = makeRouter(hermes: hermes, local: local, configured: true)
        router.remoteSessionStubs = { [self.remoteInfo(id: "h-stale", lastActive: Date(timeIntervalSince1970: 9_000))] }

        let thrown = await #expect(throws: URLError.self) {
            _ = try await router.listSessions()
        }

        #expect(thrown?.code == .cancelled,
                "a cancelled fetch must reach ChatStore so it serves its last good list, not a dimmed one")
    }

    /// **425-D, second half.** The structured-concurrency spelling of the same
    /// thing: a cancelled `Task` throws `CancellationError`, which carries no
    /// `URLError` code, so it needs its own arm in the guard.
    ///
    /// Isolating mutation M-D: drop the cancellation re-throw → this row reds.
    @Test @MainActor
    func routerRethrowsCancellationErrorInsteadOfServingTheDegradedList() async throws {
        let hermes = ScriptedClient()
        hermes.listError = CancellationError()
        let router = makeRouter(hermes: hermes, local: ScriptedClient(), configured: true)
        var recordedCalls: [[HermesSessionInfo]] = []
        router.recordRemoteSessions = { recordedCalls.append($0) }
        router.remoteSessionStubs = { [self.remoteInfo(id: "h-stale", lastActive: Date(timeIntervalSince1970: 9_000))] }

        await #expect(throws: CancellationError.self) {
            _ = try await router.listSessions()
        }

        #expect(recordedCalls.isEmpty, "a cancelled round is not a snapshot either")
    }

    /// **425-E (fix round 1).** An EMPTY host list is a SUCCESS, not a
    /// failure. `SessionsHermesClient.listSessions` throws only when NO
    /// configured host answered; a host that answers "no sessions" is
    /// reachable, so the catch must not run, nothing dims, and the empty list
    /// IS the snapshot — a host whose last session was deleted must not keep
    /// showing yesterday's stubs forever.
    @Test @MainActor
    func routerTreatsAnEmptyHostListAsASuccessAndSnapshotsIt() async throws {
        let hermes = ScriptedClient()
        let local = ScriptedClient()
        hermes.sessions = []
        let localID = UUID().uuidString
        local.sessions = [
            HermesSessionInfo(
                id: localID, title: "Local", preview: nil, model: "on-device",
                source: "local", messageCount: 2,
                lastActive: Date(timeIntervalSince1970: 2_000), isActive: false
            ),
        ]
        let router = makeRouter(hermes: hermes, local: local, configured: true)
        var recordedCalls: [[HermesSessionInfo]] = []
        router.recordRemoteSessions = { recordedCalls.append($0) }
        router.remoteSessionStubs = { [self.remoteInfo(id: "h-stale", lastActive: Date(timeIntervalSince1970: 9_000))] }

        let merged = try await router.listSessions()

        #expect(merged.map(\.id) == [localID],
                "an empty host list contributes nothing — the stale stubs must NOT be substituted for it")
        #expect(merged.allSatisfy { $0.isResumable }, "nothing dims while the host answers")
        #expect(recordedCalls.count == 1, "an empty answer is still an answer, and still the snapshot")
        #expect(recordedCalls.first?.isEmpty == true,
                "the host said zero — recording it is how a deleted last session stops haunting the drawer")
    }

    /// **425-C, failure half.** The stub snapshot IS the last real host list.
    /// Recording an empty/failed list over it would delete the only remote
    /// history the drawer has — so the failure path must not call
    /// `recordRemoteSessions` at all.
    ///
    /// Deliberately reads through `try?`: this row is about the RECORDING
    /// call, not about whether the router throws (that is 425-A's). Keeping
    /// it throw-insensitive is what makes M-A and M-C isolate cleanly.
    ///
    /// Isolating mutation M-C: call `recordRemoteSessions` on the failure
    /// path → this row reds.
    @Test @MainActor
    func routerDoesNotOverwriteTheRemoteSnapshotWhenTheHostListFails() async throws {
        let hermes = ScriptedClient()
        hermes.listError = StubError()
        let router = makeRouter(hermes: hermes, local: ScriptedClient(), configured: true)
        var recordedCalls: [[HermesSessionInfo]] = []
        router.recordRemoteSessions = { recordedCalls.append($0) }
        router.remoteSessionStubs = { [self.remoteInfo(id: "h-keep", lastActive: Date(timeIntervalSince1970: 5_000))] }

        _ = try? await router.listSessions()

        #expect(recordedCalls.isEmpty,
                "a failed host list is not a snapshot — recording it would erase the real one")
    }

    /// **425-F (fix round 1).** The degenerate corner of the failure path: no
    /// local rows and no snapshot to serve. The honest answer is an empty
    /// list, not a throw — a first launch on a phone that has never reached
    /// the host shows "no conversations yet", which is true, instead of an
    /// error the drawer would have to invent a story for.
    @Test @MainActor
    func routerFailurePathReturnsAnHonestEmptyListWhenThereIsNothingToServe() async throws {
        let hermes = ScriptedClient()
        hermes.listError = StubError()
        let router = makeRouter(hermes: hermes, local: ScriptedClient(), configured: true)
        router.remoteSessionStubs = { [] }

        let merged = try await router.listSessions()

        #expect(merged.isEmpty, "nothing to show is not the same as failing to show it")
    }

    /// **425-C, success half.** A reachable host is untouched: the live list
    /// is snapshotted and the merge is the pre-fix merge.
    @Test @MainActor
    func routerRecordsTheRemoteSnapshotWhenTheHostListSucceeds() async throws {
        let hermes = ScriptedClient()
        let local = ScriptedClient()
        hermes.sessions = [
            remoteInfo(id: "h-a", lastActive: Date(timeIntervalSince1970: 6_000)),
            remoteInfo(id: "h-b", lastActive: Date(timeIntervalSince1970: 1_500)),
        ]
        let localID = UUID().uuidString
        local.sessions = [
            HermesSessionInfo(
                id: localID, title: "Local", preview: nil, model: "on-device",
                source: "local", messageCount: 1,
                lastActive: Date(timeIntervalSince1970: 3_000), isActive: false
            ),
        ]
        let router = makeRouter(hermes: hermes, local: local, configured: true)
        var recordedCalls: [[HermesSessionInfo]] = []
        router.recordRemoteSessions = { recordedCalls.append($0) }
        // Present but unused on the success path — a live list never falls
        // back to its own snapshot.
        router.remoteSessionStubs = { [self.remoteInfo(id: "h-stale", lastActive: Date(timeIntervalSince1970: 9_000))] }

        let merged = try await router.listSessions()

        #expect(merged.map(\.id) == ["h-a", localID, "h-b"],
                "a reachable host keeps the #190 merge exactly as it was")
        #expect(merged.allSatisfy { $0.isResumable }, "nothing dims while the host answers")
        #expect(recordedCalls.count == 1, "one live list, one snapshot write")
        #expect(recordedCalls.first?.map(\.id) == ["h-a", "h-b"],
                "the snapshot is the host's own list, not the merged one")
    }

    /// **425-B, structural half.** The not-configured branch is the shape the
    /// failure path was modelled on, and it must stay byte-identical — in
    /// particular it keeps carrying `unresumableReason` ("unpaired"), never
    /// the new unreachable wording. A host with no key is not a host that
    /// timed out, and the drawer row is the only place the user learns which.
    ///
    /// Fails LOUDLY when the file cannot be read: a check that did not run
    /// must say so rather than pass.
    @Test func notConfiguredBranchOfTheRouterListIsUnchanged() throws {
        let path = "Talaria/Services/Support/ChatBackendRouter.swift"
        let source = try #require(
            try? String(
                contentsOf: URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent()   // TalariaTests/
                    .deletingLastPathComponent()   // repo root
                    .appendingPathComponent(path),
                encoding: .utf8
            ),
            "cannot read \(path) — this check did not run"
        )
        let expected = """
                guard isHermesConfigured() else {
                    let stubs = (remoteSessionStubs?() ?? []).map {
                        $0.asUnresumable(reason: Self.unresumableReason)
                    }
                    return Self.sortedByRecency(localSessions + stubs)
                }
        """
        #expect(source.contains(expected),
                "the not-configured branch of listSessions() changed; #425 was scoped to the host-FAILURE path only")
    }

    // MARK: - Router: the shelf paints the local half FIRST (425-D)
    //
    // 425 stopped the local rows being THROWN AWAY when the host list threw.
    // Owen's device pass (build 3257, 2026-09-04 ~18:55) then showed the
    // other half of the same defect: the correct degraded shelf arrived
    // ~20 s late — "the shelf was EMPTY … and then, about the time it took
    // to type the report, the rows appeared" — because `refreshSessions`
    // awaits `loadSessions` awaits the router's MERGED list awaits the host's
    // request timeout. The local rows are in hand from the first
    // millisecond.

    /// 425-D: a one-shot gate a `@MainActor` fixture parks on.
    ///
    /// `entered` is what makes an assertion about the parked window
    /// non-vacuous: a test that asserted before the host call had even
    /// started would be asserting about nothing. Bounded at 4 s on the same
    /// rule `RecoveryOwnershipTests.park` follows — a gate a test forgets to
    /// release must fail an explicit assertion, never hang the suite.
    @MainActor
    private final class ListGate {
        private(set) var entered = false
        private var released = false

        func park() async {
            entered = true
            var pumps = 0
            while !released, pumps < 400 {
                try? await Task.sleep(for: .milliseconds(10))
                pumps += 1
            }
        }

        func release() { released = true }
    }

    /// Every interim list the client published, in order.
    ///
    /// A class rather than a captured local `var`, and the reason is NOT the
    /// interim closure — that one is not `@Sendable` at all (the protocol is
    /// `@MainActor`, so it never crosses isolation). It is that two of the
    /// rows below build the closure INSIDE a `Task { }`, whose own closure IS
    /// `@Sendable` and therefore cannot capture a mutable local. The `Latch`
    /// shape `RecoveryOwnershipTests` uses, for the same reason.
    @MainActor
    private final class InterimLog {
        var publications: [[HermesSessionInfo]] = []
    }

    /// Bounded pump. A condition that never becomes true must fail an
    /// explicit assertion at the call site, never spin out the suite.
    @MainActor
    private func waitUntil(limit: Int = 400, _ condition: @MainActor () -> Bool) async {
        var pumps = 0
        while !condition(), pumps < limit {
            try? await Task.sleep(for: .milliseconds(10))
            pumps += 1
        }
    }

    /// **425-D1, router half.** With the host's list still in flight, the
    /// router has already published every local row plus the last host
    /// snapshot, dimmed — and the merged list still replaces it when the host
    /// answers.
    ///
    /// The gate is what makes this a bar rather than a coincidence: the
    /// interim is asserted while the host call is PARKED, so no ordering can
    /// be read into a lucky scheduling.
    ///
    /// Isolating mutation M-D1: delete the interim publication from
    /// `ChatBackendRouter.listSessions(interim:)` → this row and
    /// `chatStoreHandsTheInterimPublicationToItsCaller` red.
    @Test @MainActor
    func routerPublishesTheLocalHalfBeforeTheHostListResolves() async throws {
        let hermes = ScriptedClient()
        let local = ScriptedClient()
        let gate = ListGate()
        hermes.listGate = gate
        hermes.sessions = [remoteInfo(id: "h-live", lastActive: Date(timeIntervalSince1970: 6_000))]
        let localID = UUID().uuidString
        local.sessions = [
            HermesSessionInfo(
                id: localID, title: "Local", preview: nil, model: "on-device",
                source: "local", messageCount: 2,
                lastActive: Date(timeIntervalSince1970: 4_000), isActive: false
            ),
        ]
        let router = makeRouter(hermes: hermes, local: local, configured: true)
        router.remoteSessionStubs = { [self.remoteInfo(id: "h-stub", lastActive: Date(timeIntervalSince1970: 5_000))] }

        let observed = InterimLog()
        let round = Task { @MainActor in
            try await router.listSessions(interim: { observed.publications.append($0) })
        }
        await waitUntil { hermes.listCallCount == 1 && gate.entered }

        #expect(hermes.listCallCount == 1,
                "the host list never started — every assertion in this parked window would be vacuous")
        #expect(gate.entered, "the host call is not parked; this test is not measuring the window it claims")
        #expect(observed.publications.count == 1,
                "the shelf must not wait on the host for rows the phone already has (Owen's 20 s empty shelf)")
        let interim = try #require(observed.publications.first)
        #expect(interim.map(\.id) == ["h-stub", localID],
                "the interim is the local half, recency-sorted like any other list")
        #expect(interim.first(where: { $0.id == localID })?.isResumable == true,
                "a local row opens on the local backend — waiting on the host cannot make it unopenable")
        let stub = try #require(interim.first)
        #expect(stub.isResumable == false, "a host row is not openable until the host has answered")
        #expect(stub.unresumableReason == ChatBackendRouter.hostPendingReason,
                "the host has not failed yet — it has not been ASKED yet; the unreachable wording here would be a false alarm on every healthy launch")

        gate.release()
        let merged = try await round.value

        #expect(merged.map(\.id) == ["h-live", localID],
                "the merged list replaces the interim — the live host row, never the stub")
        #expect(merged.allSatisfy { $0.isResumable }, "the interim's dimming does not survive a host that answered")
        #expect(observed.publications.count == 1, "at most ONE interim per round")
    }

    /// **425-D1, composed half.** The seam the device actually rides:
    /// `ChatStore.loadSessions` hands its caller's interim closure to the
    /// router and hands back the merged list. A store that swallowed the
    /// closure would leave every router-level row green and the shelf blank
    /// for the host's timeout — the composed-path blind spot this project has
    /// been bitten by four times.
    ///
    /// Isolating mutation M-D1: delete the interim publication → this row
    /// reds (the store's own forwarding is what mutation M-D1b covers).
    @Test @MainActor
    func chatStoreHandsTheInterimPublicationToItsCaller() async throws {
        let hermes = ScriptedClient()
        let local = ScriptedClient()
        let gate = ListGate()
        hermes.listGate = gate
        hermes.listError = StubError()          // the unreachable host of #425
        let localID = UUID().uuidString
        local.sessions = [
            HermesSessionInfo(
                id: localID, title: "Local", preview: nil, model: "on-device",
                source: "local", messageCount: 2,
                lastActive: Date(timeIntervalSince1970: 4_000), isActive: false
            ),
        ]
        let router = makeRouter(hermes: hermes, local: local, configured: true)
        router.remoteSessionStubs = { [self.remoteInfo(id: "h-stub", lastActive: Date(timeIntervalSince1970: 5_000))] }
        let chatStore = ChatStore(hermesClient: router, persistence: makePersistence())

        let observed = InterimLog()
        let round = Task { @MainActor in
            await chatStore.loadSessions(force: true, interim: { observed.publications.append($0) })
        }
        await waitUntil { hermes.listCallCount == 1 && gate.entered }

        #expect(gate.entered, "the host call is not parked; this test is not measuring the window it claims")
        #expect(observed.publications.map { $0.map(\.id) } == [["h-stub", localID]],
                "the store must pass the interim through — swallowing it restores the 20 s blank shelf with every router test still green")

        gate.release()
        let final = await round.value

        #expect(final.map(\.id) == ["h-stub", localID],
                "an unreachable host still degrades to the #425 shape — the interim is a preview of it, not a replacement for it")
        #expect(final.first?.unresumableReason == ChatBackendRouter.hostUnreachableReason,
                "once the host has actually failed, the row names the timeout rather than the wait")
        #expect(chatStore.lastLoadedSessions.map(\.id) == ["h-stub", localID],
                "the FINAL list is the search corpus; an interim must never be cached as one")
    }

    /// **425-D3 (fix round 1).** A COLD load that is CANCELLED after the
    /// interim was painted must not blank the shelf it just filled.
    ///
    /// The sequence the review found: blank → local rows appear (the interim)
    /// → **blank again, "NO SESSIONS YET"**. `ChatStore.loadSessions`' catch
    /// serves `lastLoadedSessions`, which on a launch that has not yet
    /// completed one successful host list is `[]`, and `refreshSessions`
    /// assigns the return unconditionally. The router degrades every host
    /// failure EXCEPT a cancellation, so this is reachable exactly where a
    /// `URLError(.cancelled)` comes back out of the single-profile path with
    /// nobody having walked away.
    ///
    /// The rule is "the better of the two, never the emptier": a NON-EMPTY
    /// `lastLoadedSessions` still wins — that is
    /// `failedSessionsRefreshServesLastRealList`, unchanged — and only an
    /// EMPTY one yields to an interim that was actually published.
    ///
    /// Isolating mutation: restore the bare `return lastLoadedSessions` →
    /// this row reds and nothing else does.
    @Test @MainActor
    func aCancelledColdLoadServesTheInterimItAlreadyPainted() async throws {
        let hermes = ScriptedClient()
        let local = ScriptedClient()
        hermes.listError = URLError(.cancelled)
        let localID = UUID().uuidString
        local.sessions = [
            HermesSessionInfo(
                id: localID, title: "Local", preview: nil, model: "on-device",
                source: "local", messageCount: 2,
                lastActive: Date(timeIntervalSince1970: 4_000), isActive: false
            ),
        ]
        let router = makeRouter(hermes: hermes, local: local, configured: true)
        router.remoteSessionStubs = { [self.remoteInfo(id: "h-stub", lastActive: Date(timeIntervalSince1970: 5_000))] }
        let chatStore = ChatStore(hermesClient: router, persistence: makePersistence())
        #expect(chatStore.lastLoadedSessions.isEmpty,
                "the premise: a cold launch that has never completed a host list — without it this row measures nothing")

        let observed = InterimLog()
        let final = await chatStore.loadSessions(force: true, interim: { observed.publications.append($0) })

        #expect(observed.publications.map { $0.map(\.id) } == [["h-stub", localID]],
                "the interim was painted BEFORE the cancellation — that is what makes this the shelf-blanking case rather than an ordinary empty load")
        #expect(final.map(\.id) == ["h-stub", localID],
                "the shelf must keep the rows it just painted: returning [] here is blank → local rows → blank again, which is the defect wearing the fix's clothes")
        #expect(final.first(where: { $0.id == localID })?.isResumable == true,
                "and the local row it serves is the real one — a cancelled host cannot make an on-device thread unopenable")
        #expect(chatStore.lastLoadedSessions.isEmpty,
                "serving the interim is still not CACHING it: the search corpus stays a list a host actually answered")

        // The other half of "not cached": a served interim must not stamp
        // `lastSessionsLoadAt` either, or the next unforced load would answer
        // from a 15 s snapshot no host ever produced. `lastSessionsLoadAt` is
        // private, so this reads it the only honest way — by whether the next
        // load reaches the client at all.
        _ = await chatStore.loadSessions()
        #expect(hermes.listCallCount == 2,
                "the next unforced load must RETRY the host — an interim served on the throw path is not a snapshot")
    }

    /// **425-D1, source witness.** The drawer is the site that matters: a
    /// store that publishes an interim nobody assigns fixes nothing. No
    /// runtime test can reach `ChatScreen.refreshSessions` (a private method
    /// on a SwiftUI `View`), so this reads the repo's own bytes — the
    /// `RepoSourceWitness` idiom, failing loudly rather than vacuously.
    ///
    /// Isolating mutation M-D1b: drop the `interim:` argument from
    /// `refreshSessions` → this row reds and nothing else does.
    @Test(.enabled(if: RepoSourceWitness.repoSourcesAreReadable,
                   "reads the repo's own sources — simulator only"))
    func chatScreenRefreshSessionsConsumesTheInterimPublication() throws {
        let path = "Talaria/Features/Chat/ChatScreen.swift"
        let anchor = "private func refreshSessions(force: Bool = false) async {"
        let whole = try RepoSourceWitness.source(path)
        #expect(whole.components(separatedBy: anchor).count == 2,
                "\(anchor) is not unique in \(path) — this pin cannot say which one it read")
        let body = try RepoSourceWitness.functionBody(from: anchor, in: path, boundary: "\n    /// ")
        #expect(!body.contains("func "),
                "the slice swallowed a neighbour: the boundary stops at the next DOC COMMENT, so an undocumented neighbour could satisfy this pin instead")
        #expect(body.contains("chatStore.loadSessions(force: force, interim:"),
                "the drawer no longer consumes the interim publication — the local rows are held hostage by the host's timeout again (425-D)")
        #expect(body.contains("sessionsModel.sessions.isEmpty"),
                "the interim must be suppressed while the shelf already has rows; replacing a good list with a dimmed preview is the flicker 425-D forbids")
        // Fix round 1: the two checks above pass a closure that PAINTS
        // NOTHING. Deleting the assignment inside it — keeping the guard and
        // the `interim:` argument — leaves the shelf blank for the host's
        // full timeout with this pin still green, which is the defect itself.
        // So pin the assignment: twice in the body (interim, then final), and
        // the FIRST of them before the await, i.e. inside the closure.
        let assignment = "sessionsModel.sessions = infos.map"
        #expect(body.components(separatedBy: assignment).count - 1 == 2,
                "refreshSessions must assign the shelf TWICE — once from the interim, once from the return; one assignment means the closure it passes paints nothing")
        let firstAssignment = try #require(body.range(of: assignment)?.lowerBound,
                                           "no shelf assignment at all in refreshSessions")
        let hostAwait = try #require(body.range(of: "await chatStore.loadSessions(force: force, interim:")?.lowerBound,
                                     "no awaited load in refreshSessions")
        #expect(firstAssignment < hostAwait,
                "the interim's assignment must sit INSIDE the closure, BEFORE the host is awaited — an assignment that runs only after the await is the 20 s blank shelf again")
    }

    /// **425-D2.** A REACHABLE host's FINAL list is what it was before this
    /// lane: the same ids in the same order with the same resumable flags,
    /// and the same single snapshot write. The interim is visibly NOT that
    /// list, which is what makes the mutation isolate.
    ///
    /// Isolating mutation M-D2: return the interim list as the answer (skip
    /// the merge) → this row reds.
    @Test @MainActor
    func reachableHostFinalListIsUnchangedByTheInterimPublication() async throws {
        let hermes = ScriptedClient()
        let local = ScriptedClient()
        hermes.sessions = [
            remoteInfo(id: "h-a", lastActive: Date(timeIntervalSince1970: 6_000)),
            remoteInfo(id: "h-b", lastActive: Date(timeIntervalSince1970: 1_500)),
        ]
        let localID = UUID().uuidString
        local.sessions = [
            HermesSessionInfo(
                id: localID, title: "Local", preview: nil, model: "on-device",
                source: "local", messageCount: 1,
                lastActive: Date(timeIntervalSince1970: 3_000), isActive: false
            ),
        ]
        let router = makeRouter(hermes: hermes, local: local, configured: true)
        var recordedCalls: [[HermesSessionInfo]] = []
        router.recordRemoteSessions = { recordedCalls.append($0) }
        router.remoteSessionStubs = { [self.remoteInfo(id: "h-stale", lastActive: Date(timeIntervalSince1970: 9_000))] }

        let observed = InterimLog()
        let merged = try await router.listSessions(interim: { observed.publications.append($0) })

        #expect(merged.map(\.id) == ["h-a", localID, "h-b"],
                "a reachable host keeps the #190 merge exactly as it was — the interim is a paint, not an answer")
        #expect(merged.map(\.isResumable) == [true, true, true], "nothing dims once the host has answered")
        #expect(merged.map(\.unresumableReason) == [nil, nil, nil], "and no row carries a reason it no longer has")
        #expect(recordedCalls.count == 1, "one live list, one snapshot write — the interim is not a snapshot")
        #expect(recordedCalls.first?.map(\.id) == ["h-a", "h-b"])

        let interim = try #require(observed.publications.first, "the interim still fires on the reachable path — it cannot know yet")
        #expect(interim.map(\.id) == ["h-stale", localID],
                "the interim is the stale snapshot plus the local rows, which is exactly why it must not be the answer")
        #expect(interim.map(\.isResumable) == [false, true])
    }

    // MARK: - 425-F2: the blank one screen over
    //
    // The 425-D review's follow-up (2). Settings → Sessions awaits the same
    // blocking `loadSessions()` the drawer used to, so with an unreachable
    // host its Recent list reads "No sessions yet" for the host's full
    // request timeout — local chats and all. The conduit 425-D built is
    // available to it; these rows are what make the adoption a measurement
    // rather than a claim.

    /// **425-F2.** With the host's list parked, the settings screen's model
    /// already holds the rows the phone had all along.
    ///
    /// The gate is what makes this a bar rather than a coincidence: the rows
    /// are asserted while the host call is PARKED, so no ordering can be read
    /// into a lucky scheduling.
    ///
    /// Isolating mutation: revert `SessionsSettingsListModel.load` to the bare
    /// `chatStore.loadSessions(force:)` → this row reds and nothing else does.
    @Test @MainActor
    func settingsSessionListPaintsLocalRowsBeforeTheHostResolves() async throws {
        let hermes = ScriptedClient()
        let local = ScriptedClient()
        let gate = ListGate()
        hermes.listGate = gate
        hermes.listError = StubError()          // the unreachable host of #425
        local.sessions = [
            HermesSessionInfo(
                id: UUID().uuidString, title: "Local one", preview: nil, model: "on-device",
                source: "local", messageCount: 2,
                lastActive: Date(timeIntervalSince1970: 4_000), isActive: false
            ),
            HermesSessionInfo(
                id: UUID().uuidString, title: "Local two", preview: nil, model: "on-device",
                source: "local", messageCount: 5,
                lastActive: Date(timeIntervalSince1970: 3_000), isActive: false
            ),
        ]
        let router = makeRouter(hermes: hermes, local: local, configured: true)
        let chatStore = ChatStore(hermesClient: router, persistence: makePersistence())
        let model = SessionsSettingsListModel()

        let round = Task { @MainActor in await model.load(from: chatStore, force: true) }
        await waitUntil { hermes.listCallCount == 1 && gate.entered }

        #expect(hermes.listCallCount == 1,
                "the host list never started — every assertion in this parked window would be vacuous")
        #expect(gate.entered, "the host call is not parked; this test is not measuring the window it claims")
        #expect(model.sortedSessions.map(\.title) == ["Local one", "Local two"],
                "the local rows are in hand from the first millisecond — holding them hostage to the host's timeout is the 20 s blank, one screen over")
        #expect(model.showsEmptyCopy == false,
                "\"No sessions yet\" is a claim about the account; over two local chats it is simply false")

        gate.release()
        await round.value

        #expect(model.sortedSessions.map(\.title) == ["Local one", "Local two"],
                "the answer supersedes the interim — an unreachable host still degrades to the #425 shape")
        #expect(model.hasLoaded)
        #expect(model.showsEmptyCopy == false)
        #expect(model.isLoading == false)
    }

    /// **425-F2, the other half.** The empty copy still renders when the list
    /// is GENUINELY empty — and never before a load has answered.
    ///
    /// A fix that simply deleted "No sessions yet" would pass the row above
    /// and lie to a user with no sessions at all; this is what stops it.
    @Test @MainActor
    func settingsSessionEmptyCopyRendersOnlyWhenGenuinelyEmpty() async throws {
        let model = SessionsSettingsListModel()
        #expect(model.showsEmptyCopy == false,
                "before any load there is no answer to report — an untried load is not an empty account")
        #expect(model.showsLoadingRow)

        let hermes = ScriptedClient()          // no sessions on either side
        let local = ScriptedClient()
        let router = makeRouter(hermes: hermes, local: local, configured: true)
        let chatStore = ChatStore(hermesClient: router, persistence: makePersistence())

        await model.load(from: chatStore, force: true)

        #expect(model.sessions.isEmpty)
        #expect(model.showsEmptyCopy,
                "a load that answered with nothing IS the empty account — the copy is the truth here")
        #expect(model.showsLoadingRow == false)
    }

    /// **425-F2, the composed half.** A model nobody consumes fixes nothing —
    /// the M-D1b lesson, one screen over. No runtime test can reach
    /// `SessionsSettingsScreen.load()` (a private method on a SwiftUI `View`),
    /// so this reads the repo's own bytes.
    ///
    /// Isolating mutation: point the screen's `load()` back at
    /// `container.chatStore.loadSessions()` → this row reds and nothing else
    /// does.
    @Test(.enabled(if: RepoSourceWitness.repoSourcesAreReadable,
                   "reads the repo's own sources — simulator only"))
    func settingsSessionsScreenLoadGoesThroughTheModel() throws {
        let path = "Talaria/Features/Settings/SessionsSettingsScreen.swift"
        let anchor = "private func load() async {"
        let whole = try RepoSourceWitness.source(path)
        #expect(whole.components(separatedBy: anchor).count == 2,
                "\(anchor) is not unique in \(path) — this pin cannot say which one it read")
        let body = try RepoSourceWitness.functionBody(from: anchor, in: path,
                                                      boundary: "\n    private func ")
        #expect(!body.contains("func "),
                "the slice swallowed a neighbour: the boundary stops at the next member, so a neighbour's lines could satisfy this pin instead")
        #expect(body.contains("list.load(from: container.chatStore"),
                "the screen no longer loads through the model — its rows are held hostage by the host's timeout again (425-F2)")
        #expect(!body.contains("container.chatStore.loadSessions("),
                "the bare, blocking call is back in the screen")
    }

    @Test @MainActor
    func routerRoutesLocalSessionIDsToLocalBackendWhileHermesActive() async throws {
        let hermes = ScriptedClient()
        let local = ScriptedClient()
        let localID = UUID().uuidString
        let router = makeRouter(hermes: hermes, local: local, configured: true)
        router.isLocalSessionID = { $0 == localID }

        _ = try await router.openSession(localID)
        #expect(local.openedIDs == [localID], "a local session id must open on the local backend even while Hermes is active")
        #expect(hermes.openedIDs.isEmpty)

        _ = try await router.openSession("h-1")
        #expect(hermes.openedIDs == ["h-1"], "Hermes ids keep routing exactly as before")
    }

    // MARK: - Symmetric membership routing (#190B change 1)

    @Test @MainActor
    func routerRoutesRemoteIDsToHermesWhileLocalBrainIsActive() async throws {
        let hermes = ScriptedClient()
        let local = ScriptedClient()
        let router = makeRouter(hermes: hermes, local: local, configured: true)
        router.isLocalSessionID = { _ in false }
        // Pin the next conversation on-device so the ACTIVE brain is local —
        // the exact state the 2026-07-26 device fail was tapped in.
        router.setPreferredBrain(.onDevice, forConversation: nil)
        #expect(router.activeBrain == .onDevice)

        _ = try await router.openSession("h-1")

        #expect(hermes.openedIDs == ["h-1"], "a Hermes row tapped while the local brain is active must open on Hermes")
        #expect(local.openedIDs.isEmpty, "the old active-brain fallback sent this tap to LocalChatBackend, which threw sessionNotFound")
    }

    @Test @MainActor
    func routerFallsBackToActiveBrainForRemoteIDsOnlyWhenHermesUnconfigured() async throws {
        let hermes = ScriptedClient()
        let local = ScriptedClient()
        let router = makeRouter(hermes: hermes, local: local, configured: false)
        router.isLocalSessionID = { _ in false }

        _ = try await router.openSession("h-stub")

        #expect(local.openedIDs == ["h-stub"], "with no Hermes configured the active (local) brain still fields the open")
        #expect(hermes.openedIDs.isEmpty)
    }

    // MARK: - Open failure is rendered state, not a log line (#190B change 2)

    @Test @MainActor
    func failedOpenBecomesRenderableStateAndSuccessClearsIt() async throws {
        let client = ScriptedClient()
        client.openError = LocalChatBackendError.sessionNotFound("gone")
        let chatStore = ChatStore(hermesClient: client, persistence: makePersistence())

        await chatStore.openSession("gone")

        let failure = try #require(chatStore.sessionOpenFailure, "a deterministic open failure must be state the UI can render")
        #expect(failure.sessionID == "gone")
        #expect(!failure.message.isEmpty)

        client.openError = nil
        await chatStore.openSession("s-ok")
        #expect(chatStore.sessionOpenFailure == nil, "the next successful open clears the failure")
    }

    @Test @MainActor
    func newChatClearsOpenFailureState() async throws {
        let client = ScriptedClient()
        client.openError = StubError()
        let chatStore = ChatStore(hermesClient: client, persistence: makePersistence())

        await chatStore.openSession("nope")
        #expect(chatStore.sessionOpenFailure != nil)

        try await chatStore.clearConversation()
        #expect(chatStore.sessionOpenFailure == nil, "walking away from the failed open dismisses it")
    }

    @Test @MainActor
    func unreadableStoredTranscriptThrowsDistinctlyFromUnknownID() async throws {
        let store = FakeSessionStore()
        let stored = localConversation(prompt: "was here", reply: "once", lastActivity: .now)
        store.upsertSession(stored)
        store.unreadableIDs = [stored.id]
        let backend = makeBackend(persistence: makePersistence(), store: store)

        do {
            _ = try await backend.openSession(stored.id.uuidString)
            Issue.record("an unreadable stored transcript must throw")
        } catch LocalChatBackendError.sessionUnreadable {
            // Expected: the row exists — telling the user it doesn't would be
            // the decode-nil path lying twice.
        } catch {
            Issue.record("expected sessionUnreadable, got \(error)")
        }
    }

    // MARK: - Origin-based store membership (#190B change 3)

    /// Yields exactly one `.finished` assistant turn, stamped with the given
    /// brain — the minimal client for driving ChatStore's settle path.
    @MainActor
    private final class SettlingClient: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .connected
        var currentConversation: Conversation?
        var finishBrain: String?

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
            let reply = Message(sender: .hermes, content: "reply", status: .delivered, brain: finishBrain)
            return AsyncStream { continuation in
                continuation.yield(.finished(reply, nil, nil))
                continuation.finish()
            }
        }

        func loadConversation() async -> Conversation {
            currentConversation ?? Conversation(title: "Hermes")
        }

        func clearConversation() async throws -> Conversation {
            Conversation(title: "Hermes")
        }
    }

    /// The wired discriminator shape since #190B: membership IS locality.
    @MainActor
    private func membershipDiscriminator(_ store: FakeSessionStore) -> @MainActor (Conversation) -> Bool {
        { store.hasSession(withID: $0.id) }
    }

    @Test @MainActor
    func firstLocalSettledTurnEstablishesStoreMembership() async throws {
        let store = FakeSessionStore()
        let client = SettlingClient()
        client.finishBrain = ChatBackendRouter.Brain.onDevice.rawValue
        let chatStore = ChatStore(hermesClient: client, persistence: makePersistence())
        chatStore.localSessions = store
        chatStore.isLocalSessionThread = membershipDiscriminator(store)

        await chatStore.sendMessage("hello there")

        let conversationID = try #require(chatStore.conversation?.id)
        #expect(store.hasSession(withID: conversationID), "a thread born local enters the store the moment its first turn settles")

        await chatStore.sendMessage("and again")
        #expect(store.sessions[conversationID]?.messages.count == 4, "later settles refresh the stored copy")
    }

    @Test @MainActor
    func mixedHermesThreadNeverEntersTheLocalStore() async throws {
        let store = FakeSessionStore()
        let client = SettlingClient()
        client.finishBrain = ChatBackendRouter.Brain.onDevice.rawValue
        let persistence = makePersistence()
        // A paired-mode Hermes thread: prior assistant turns un-stamped (the
        // historical Hermes default) — its identity is a Hermes session.
        persistence.saveConversationCache(Conversation(title: "Hermes", messages: [
            Message(sender: .user, content: "earlier", status: .delivered),
            Message(sender: .hermes, content: "server reply", status: .delivered),
        ]))
        let chatStore = ChatStore(hermesClient: client, persistence: persistence)
        chatStore.localSessions = store
        chatStore.isLocalSessionThread = membershipDiscriminator(store)
        await chatStore.loadConversationIfNeeded()

        // #192 flips the brain mid-thread: this turn settles on-device.
        await chatStore.sendMessage("now local")
        #expect(store.sessions.isEmpty, "a mixed thread whose identity is a Hermes session must not enter the store")

        // The walk-away persist reaches the same verdict.
        try await chatStore.clearConversation()
        #expect(store.sessions.isEmpty)
    }

    @Test @MainActor
    func settledHermesTurnEstablishesNothing() async throws {
        let store = FakeSessionStore()
        let client = SettlingClient()
        client.finishBrain = ChatBackendRouter.Brain.hermes.rawValue
        let chatStore = ChatStore(hermesClient: client, persistence: makePersistence())
        chatStore.localSessions = store
        chatStore.isLocalSessionThread = membershipDiscriminator(store)

        await chatStore.sendMessage("routed to Hermes")

        #expect(store.sessions.isEmpty, "a thread born on Hermes has no local origin to record")
    }

    // MARK: - A failed refresh must not empty the drawer (#190B change 5)

    @Test @MainActor
    func failedSessionsRefreshServesLastRealList() async throws {
        let client = ScriptedClient()
        client.sessions = [remoteInfo(id: "h-1", lastActive: .now)]
        let chatStore = ChatStore(hermesClient: client, persistence: makePersistence())

        let first = await chatStore.loadSessions(force: true)
        #expect(first.map(\.id) == ["h-1"])

        client.listError = StubError()
        let second = await chatStore.loadSessions(force: true)
        #expect(second.map(\.id) == ["h-1"], "a failed refresh serves the stale-but-real list — [] emptied the drawer on device")
    }

    // MARK: - Drawer origin markers (#190 Phase 4)

    private func summary(
        id: String,
        origin: SessionsDrawerModel.SessionOrigin?
    ) -> SessionsDrawerModel.SessionSummary {
        SessionsDrawerModel.SessionSummary(
            id: id, title: id, subtitle: "", timeLabel: "1:00",
            group: .today, origin: origin
        )
    }

    @Test
    func originGlyphsSuppressedForSingleSource() {
        #expect(SessionsDrawerModel.showsOriginGlyphs(sessions: []) == false)
        #expect(SessionsDrawerModel.showsOriginGlyphs(sessions: [
            summary(id: "a", origin: .local),
            summary(id: "b", origin: .local),
        ]) == false, "free-tier users have one source — the marker is pure noise for them")
    }

    @Test
    func originGlyphsAppearOnceSourcesMix() {
        #expect(SessionsDrawerModel.showsOriginGlyphs(sessions: [
            summary(id: "a", origin: .local),
            summary(id: "b", origin: .remote),
        ]) == true)
    }

    @Test @MainActor
    func sessionSummaryMapsOriginAndUnresumableState() {
        let local = ChatScreen.sessionSummary(from: HermesSessionInfo(
            id: UUID().uuidString, title: "Local", preview: "p", model: "on-device",
            source: "local", messageCount: 2, lastActive: .now, isActive: true
        ))
        #expect(local.origin == .local)
        #expect(local.isUnresumable == false)

        let stub = ChatScreen.sessionSummary(from: remoteInfo(
            id: "h-gone", lastActive: .now
        ).asUnresumable(reason: ChatBackendRouter.unresumableReason))
        #expect(stub.origin == .remote)
        #expect(stub.isUnresumable == true)
        #expect(stub.subtitle == ChatBackendRouter.unresumableReason, "a dimmed row carries its reason")
    }

    // MARK: - #180 lane 180-L / L1: a drawer row never prints one string twice
    //
    // Bars 180-A (RED on the defect, two shapes) and 180-B (the green-today
    // regression PIN). The rule being applied is `HostFedListPresentation`'s
    // rule 5 corollary — *a fallback may NARROW a claim; it may never
    // SUBSTITUTE a different one* — and its in-repo precedent is
    // `LocalIntelligenceService.fallbackCard` (`:452-458`), which solved the
    // identical render for the on-device card on 2026-07-11 and was never
    // generalized to the server-fed row.

    /// **180-A row (i) — #177's shape.** Hermes derives BOTH `title` and
    /// `preview` from the first user message, so the server-fed drawer sends
    /// them identical by construction. Before L1 the title branch took
    /// `title` and the subtitle ladder took `preview`, printing the same
    /// string on both lines of the row the paid-tier user actually looks at.
    @Test @MainActor
    func serverRowWithIdenticalTitleAndPreviewDoesNotPrintItTwice() {
        let row = ChatScreen.sessionSummary(from: HermesSessionInfo(
            id: "h-dupe", title: "what's the weather in London",
            preview: "what's the weather in London", model: "opus",
            source: "chat", messageCount: 4, lastActive: .now, isActive: false
        ))

        #expect(row.title == "what's the weather in London")
        #expect(row.title != row.subtitle,
                "#177: the server sends title == preview; the row must not print it twice")
        #expect(row.subtitle == "4 messages",
                "the ladder steps to the next rung rather than echoing")
    }

    /// **180-A row (ii) — #280's shape.** `title: nil` with a preview: the
    /// title branch substitutes the preview, and the subtitle rung then
    /// repeats it. This BELTS #280's drawer symptom — it does not close
    /// #280, whose bar 280-A asserts `conversation.title !=
    /// Conversation.defaultTitle` and which this change does not touch.
    @Test @MainActor
    func titlelessRowDoesNotEchoItsPreviewOnBothLines() {
        let row = ChatScreen.sessionSummary(from: HermesSessionInfo(
            id: "local-1", title: nil, preview: "remind me to call mum",
            model: "on-device", source: LocalChatBackend.localSessionSource,
            messageCount: 2, lastActive: .now, isActive: false
        ))

        #expect(row.title == "remind me to call mum",
                "the substitution STAYS — a row whose only text is its preview should still show it, once")
        #expect(row.title != row.subtitle)
        #expect(row.subtitle == "2 messages")
    }

    /// **180-A, the empty corner.** Title == preview on a thread with no
    /// counted messages: the ladder's last rung has to carry the row.
    @Test @MainActor
    func duplicateRowWithNoMessagesFallsToTheFinalRung() {
        let row = ChatScreen.sessionSummary(from: HermesSessionInfo(
            id: "h-empty", title: "[screenshot]", preview: "[screenshot]",
            model: "opus", source: "chat", messageCount: 0, lastActive: .now, isActive: false
        ))

        #expect(row.title == "[screenshot]")
        #expect(row.subtitle == "No messages")
        #expect(row.title != row.subtitle)
    }

    /// **180-B — the regression PIN. GREEN TODAY BY CONSTRUCTION, and that is
    /// recorded rather than implied:** a bar that was never red is a pin, not
    /// a proof. Its job is to fail if L1 over-reaches and "fixes" 180-A by
    /// deleting the subtitle.
    @Test @MainActor
    func distinctTitleAndPreviewKeepBothLines() {
        let row = ChatScreen.sessionSummary(from: HermesSessionInfo(
            id: "h-1", title: "Weekly review", preview: "Let's start with Monday",
            model: "opus", source: "chat", messageCount: 9, lastActive: .now, isActive: false
        ))

        #expect(row.title == "Weekly review")
        #expect(row.subtitle == "Let's start with Monday",
                "a genuinely distinct preview is the subtitle — L1 must not eat it")
    }

    /// **180-B, second half — the three ladder rungs #190 owns are unchanged.**
    @Test @MainActor
    func the190SubtitleLadderRungsSurviveL1() {
        // Rung 1: an unresumable row carries its honest reason, not a preview
        // it cannot deliver on.
        let dimmed = ChatScreen.sessionSummary(from: remoteInfo(id: "h-gone", lastActive: .now)
            .asUnresumable(reason: ChatBackendRouter.unresumableReason))
        #expect(dimmed.subtitle == ChatBackendRouter.unresumableReason)

        // Rung 2: no preview, messages counted — plural and singular.
        let counted = ChatScreen.sessionSummary(from: HermesSessionInfo(
            id: "h-2", title: "Named", preview: nil, model: "opus",
            source: "chat", messageCount: 3, lastActive: .now, isActive: false))
        #expect(counted.subtitle == "3 messages")

        let one = ChatScreen.sessionSummary(from: HermesSessionInfo(
            id: "h-3", title: "Named", preview: nil, model: "opus",
            source: "chat", messageCount: 1, lastActive: .now, isActive: false))
        #expect(one.subtitle == "1 message")

        // Rung 3: nothing at all.
        let empty = ChatScreen.sessionSummary(from: HermesSessionInfo(
            id: "h-4", title: "Named", preview: nil, model: "opus",
            source: "chat", messageCount: 0, lastActive: .now, isActive: false))
        #expect(empty.subtitle == "No messages")
        #expect(empty.title == "Named")
    }
}
