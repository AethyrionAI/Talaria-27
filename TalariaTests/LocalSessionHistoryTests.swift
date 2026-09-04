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
