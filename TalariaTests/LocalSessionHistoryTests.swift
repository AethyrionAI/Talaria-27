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
            sessions[id]
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
        private(set) var openedIDs: [String] = []

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
            if let listError { throw listError }
            return sessions
        }

        func openSession(_ id: String) async throws -> Conversation {
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

    @Test @MainActor
    func routerListStillThrowsWhenConfiguredHermesFails() async throws {
        let hermes = ScriptedClient()
        hermes.listError = StubError()
        let router = makeRouter(hermes: hermes, local: ScriptedClient(), configured: true)
        await #expect(throws: (any Error).self) {
            _ = try await router.listSessions()
        }
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
}
