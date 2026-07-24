import Foundation
import Testing
@testable import Talaria

// Lane F — conversation management (#96 search, #97 pin/archive). Three
// UI-independent suites over the store/view-model layer: search matching +
// display honesty, pin/archive persistence + migration, and the drawer's
// data-source rule (pinned sort, archived filter).

// MARK: - #96: search matching + display honesty

struct ConversationSearchTests {

    private static func entry(
        _ role: ConversationJournal.Entry.Role,
        _ text: String
    ) -> ConversationJournal.Entry {
        ConversationJournal.Entry(role: role, text: text)
    }

    private static func info(
        id: String,
        title: String? = nil,
        preview: String? = nil,
        messageCount: Int = 0,
        lastActive: Date? = nil,
        isActive: Bool = false
    ) -> HermesSessionInfo {
        HermesSessionInfo(
            id: id, title: title, preview: preview, model: nil, source: nil,
            messageCount: messageCount, lastActive: lastActive, isActive: isActive
        )
    }

    // MARK: Matching

    @Test func localBodyTextMatchIsCaseInsensitive() {
        let entries = [Self.entry(.user, "Deploy the RELAY sidecar tonight")]
        let hits = ConversationSearch.searchJournal(entries: entries, query: "relay")
        #expect(hits.count == 1)
        #expect(hits.first?.role == .user)
        #expect(hits.first?.snippet.contains("RELAY") == true)
    }

    @Test func matchIsDiacriticInsensitiveBothDirections() {
        let accented = [Self.entry(.assistant, "Notes from the café about your résumé")]
        #expect(ConversationSearch.searchJournal(entries: accented, query: "cafe").count == 1)
        #expect(ConversationSearch.searchJournal(entries: accented, query: "RESUME").count == 1)

        let plain = [Self.entry(.user, "resume the run after lunch")]
        #expect(ConversationSearch.searchJournal(entries: plain, query: "résumé").count == 1)
    }

    @Test func emptyAndWhitespaceQueriesMatchNothing() {
        let entries = [Self.entry(.user, "anything at all")]
        #expect(ConversationSearch.searchJournal(entries: entries, query: "").isEmpty)
        #expect(ConversationSearch.searchJournal(entries: entries, query: "   ").isEmpty)

        let sessions = [Self.info(id: "api_1", title: "Anything")]
        #expect(ConversationSearch.searchSessions(sessions, query: "").isEmpty)
        #expect(ConversationSearch.searchSessions(sessions, query: " \n ").isEmpty)
    }

    @Test func noHitQueryReturnsEmpty() {
        let entries = [Self.entry(.user, "talk about the weather")]
        #expect(ConversationSearch.searchJournal(entries: entries, query: "zebra").isEmpty)

        let sessions = [Self.info(id: "api_1", title: "Weather talk", preview: "sunny")]
        #expect(ConversationSearch.searchSessions(sessions, query: "zebra").isEmpty)
    }

    @Test func localHitsPreserveTranscriptOrderAndRole() {
        let entries = [
            Self.entry(.user, "first needle here"),
            Self.entry(.assistant, "nothing relevant"),
            Self.entry(.assistant, "second needle there"),
        ]
        let hits = ConversationSearch.searchJournal(entries: entries, query: "needle")
        #expect(hits.map(\.id) == [0, 2])
        #expect(hits.map(\.role) == [.user, .assistant])
    }

    @Test func serverSessionsMatchOnTitleAndPreview() {
        let sessions = [
            Self.info(id: "api_title", title: "Tokyo trip planning"),
            Self.info(id: "api_preview", preview: "flights to Tokyo shortlisted"),
            Self.info(id: "api_neither", title: "Invoice triage", preview: "3 approved"),
        ]
        let hits = ConversationSearch.searchSessions(sessions, query: "tokyo")
        #expect(hits.map(\.id) == ["api_title", "api_preview"])
    }

    @Test func sessionWithNoRealTextNeverMatches() {
        // No title, no preview — nothing real to match against, so nothing
        // is fabricated to match (messageCount is metadata, not text).
        let sessions = [Self.info(id: "api_bare", messageCount: 3)]
        #expect(ConversationSearch.searchSessions(sessions, query: "3").isEmpty)
    }

    // MARK: Display honesty ("—" for missing, never placeholder data)

    @Test func missingServerFieldsRenderAsDash() {
        let bare = ConversationSearch.ServerHit(
            id: "api_bare", title: nil, preview: nil,
            messageCount: 0, lastActive: nil, isActive: false
        )
        #expect(bare.displayTitle == "—")
        #expect(bare.displayDetail == "—")
        #expect(ConversationSearch.timeLabel(for: nil) == "—")
    }

    @Test func titleOnlySessionShowsDashDetail() {
        let hit = ConversationSearch.ServerHit(
            id: "api_t", title: "Titled", preview: nil,
            messageCount: 2, lastActive: nil, isActive: false
        )
        #expect(hit.displayTitle == "Titled")
        #expect(hit.displayDetail == "—")
    }

    @Test func previewStandsInForMissingTitleWithoutDuplicating() {
        let hit = ConversationSearch.ServerHit(
            id: "api_p", title: nil, preview: "the only real text",
            messageCount: 2, lastActive: nil, isActive: false
        )
        #expect(hit.displayTitle == "the only real text")
        #expect(hit.displayDetail == "—")
    }

    @Test func emptyStringFieldsNormalizeToMissing() {
        let sessions = [Self.info(id: "api_e", title: "", preview: "real preview text")]
        let hits = ConversationSearch.searchSessions(sessions, query: "real preview")
        #expect(hits.count == 1)
        // The empty title is missing data, not a "" title.
        #expect(hits.first?.title == nil)
        #expect(hits.first?.displayTitle == "real preview text")
    }

    @Test func timeLabelForTodayUsesClock() {
        let label = ConversationSearch.timeLabel(for: .now)
        #expect(label.contains(":"))
    }

    // MARK: Snippets

    @Test func snippetWindowsAroundMatchWithHonestEllipses() {
        let long = String(repeating: "a", count: 200) + " NEEDLE " + String(repeating: "b", count: 200)
        let snippet = ConversationSearch.snippet(of: long, around: "needle")
        #expect(snippet.localizedStandardContains("needle"))
        #expect(snippet.hasPrefix("…"))
        #expect(snippet.hasSuffix("…"))
        #expect(snippet.count < long.count)
    }

    @Test func snippetKeepsShortTextWholeWithoutEllipses() {
        let snippet = ConversationSearch.snippet(of: "short needle text", around: "needle")
        #expect(snippet == "short needle text")
    }

    @Test func snippetCollapsesNewlines() {
        let snippet = ConversationSearch.snippet(of: "line one\nNEEDLE\nline three", around: "needle")
        #expect(!snippet.contains("\n"))
        #expect(snippet.localizedStandardContains("needle"))
    }

    // MARK: Debounced model (corpus seams injected; performSearch = the
    // post-debounce work)

    @Test @MainActor func modelSearchesBothCorpora() {
        let model = ConversationSearchModel()
        model.journalEntriesProvider = { [Self.entry(.user, "the needle is local")] }
        model.serverSessionsProvider = { [Self.info(id: "api_1", title: "Needle on the server")] }

        model.performSearch("needle")
        #expect(model.results.local.count == 1)
        #expect(model.results.server.count == 1)
        #expect(model.hasSearched)
    }

    @Test @MainActor func clearingQueryResetsToPromptState() {
        let model = ConversationSearchModel()
        model.journalEntriesProvider = { [Self.entry(.user, "needle")] }
        model.performSearch("needle")
        #expect(!model.results.isEmpty)

        model.query = ""
        #expect(model.results.isEmpty)
        #expect(!model.hasSearched)
    }

    @Test @MainActor func typingDebouncesIntoOneResolvedSearch() async throws {
        let model = ConversationSearchModel()
        model.debounceInterval = .milliseconds(10)
        model.journalEntriesProvider = { [Self.entry(.user, "needle in the journal")] }

        model.query = "nee"
        model.query = "needle"
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.results.local.count == 1)
        #expect(model.hasSearched)
    }

    // MARK: ChatStore corpus snapshot

    private struct StubError: Error {}

    @MainActor
    private final class SessionListClient: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .connected
        var currentConversation: Conversation?
        var sessions: [HermesSessionInfo] = []
        var shouldThrow = false

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
            if shouldThrow { throw StubError() }
            return sessions
        }
    }

    @Test @MainActor func loadSessionsSnapshotsSearchCorpusAndKeepsItAcrossAFailedRefresh() async {
        let client = SessionListClient()
        client.sessions = [Self.info(id: "api_1", title: "First")]
        let store = ChatStore(hermesClient: client, persistence: TestPersistence.make("search-corpus"))

        _ = await store.loadSessions()
        #expect(store.lastLoadedSessions.map(\.id) == ["api_1"])

        // A transient failure must not wipe the corpus — stale-but-real
        // beats empty. `force` is required here since #175: without it the
        // snapshot would answer and the failing client would never be
        // reached, so this test would pass while asserting nothing.
        client.shouldThrow = true
        _ = await store.loadSessions(force: true)
        #expect(store.lastLoadedSessions.map(\.id) == ["api_1"])
    }
}

// MARK: - #97: pin/archive persistence + migration

struct PinArchivePersistenceTests {

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

    // MARK: Journal migration

    @Test func legacyJournalPayloadMigratesFlagsToFalse() throws {
        // A pre-#97 persisted journal: no isPinned/isArchived keys. It must
        // decode (NOT reset to a fresh journal) with both flags defaulted.
        let legacy = """
        {"conversationID":"00000000-0000-0000-0000-000000000001",\
        "entries":[{"role":"user","text":"hello"},{"role":"assistant","text":"hi"}],\
        "activeHop":{"apiSessionId":"api_1","seenEntryCount":2}}
        """
        let decoded = try JSONDecoder().decode(ConversationJournal.self, from: Data(legacy.utf8))
        #expect(decoded.isPinned == false)
        #expect(decoded.isArchived == false)
        #expect(decoded.entries.count == 2)
        #expect(decoded.activeHop?.apiSessionId == "api_1")
        #expect(decoded.conversationID == UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    }

    @Test func journalFlagsRoundTripThroughCodable() throws {
        var journal = ConversationJournal(entries: [.init(role: .user, text: "x")])
        journal.isPinned = true
        journal.isArchived = true
        let decoded = try JSONDecoder().decode(
            ConversationJournal.self,
            from: JSONEncoder().encode(journal)
        )
        #expect(decoded.isPinned)
        #expect(decoded.isArchived)
    }

    // MARK: Journal store persistence

    @Test @MainActor func journalStoreFlagsPersistAcrossInstances() {
        let persistence = TestPersistence.make("journal-flags")
        let convo = Self.conversation(turns: [(.user, "hi"), (.hermes, "hey")])

        let first = ConversationJournalStore(persistence: persistence)
        first.sync(with: convo)
        first.setPinned(true)
        first.setArchived(true)

        let second = ConversationJournalStore(persistence: persistence)
        #expect(second.isPinned)
        #expect(second.isArchived)
        #expect(second.journal.conversationID == convo.id)
    }

    @Test @MainActor func journalFlagsSurviveSyncAndResetOnForeignConversation() {
        let persistence = TestPersistence.make("journal-flags-sync")
        let store = ConversationJournalStore(persistence: persistence)
        var convo = Self.conversation(turns: [(.user, "q1"), (.hermes, "a1")])
        store.sync(with: convo)
        store.setPinned(true)

        // Same conversation growing: the flag rides along.
        convo.messages.append(Message(sender: .user, content: "q2", status: .delivered))
        convo.messages.append(Message(sender: .hermes, content: "a2", status: .delivered))
        store.sync(with: convo, lastExchangeViaActiveHop: false)
        #expect(store.isPinned)

        // A foreign conversation (fresh chat): new identity, default flags.
        store.sync(with: Self.conversation(turns: [(.user, "new thread")]))
        #expect(store.isPinned == false)
        #expect(store.isArchived == false)
    }

    // MARK: Server-session overlay

    @Test @MainActor func overlayDefaultsEmptyAndPersistsAcrossInstances() {
        let persistence = TestPersistence.make("overlay")
        let first = ConversationListStateStore(persistence: persistence)
        #expect(first.isPinned("api_1") == false)
        #expect(first.isArchived("api_2") == false)

        first.setPinned(true, sessionID: "api_1")
        first.toggleArchived(sessionID: "api_2")

        // Relaunch: both flags survive; unrelated ids stay clean.
        let second = ConversationListStateStore(persistence: persistence)
        #expect(second.isPinned("api_1"))
        #expect(second.isArchived("api_2"))
        #expect(second.isPinned("api_2") == false)
        #expect(second.isArchived("api_1") == false)
    }

    @Test @MainActor func overlayTogglesBackOffCleanly() {
        let persistence = TestPersistence.make("overlay-toggle")
        let store = ConversationListStateStore(persistence: persistence)
        store.togglePinned(sessionID: "api_1")
        store.togglePinned(sessionID: "api_1")
        store.setArchived(true, sessionID: "api_1")
        store.setArchived(false, sessionID: "api_1")

        let reloaded = ConversationListStateStore(persistence: persistence)
        #expect(reloaded.isPinned("api_1") == false)
        #expect(reloaded.isArchived("api_1") == false)
        #expect(reloaded.state == ConversationListState())
    }
}

// MARK: - #97: the drawer's data-source rule

struct DrawerDataSourceTests {

    @MainActor
    private static func summary(
        _ id: String,
        title: String = "Untitled",
        group: SessionsDrawerModel.Group = .today,
        isActive: Bool = false
    ) -> SessionsDrawerModel.SessionSummary {
        SessionsDrawerModel.SessionSummary(
            id: id, title: title, subtitle: "subtitle",
            timeLabel: "09:00", group: group, isActive: isActive
        )
    }

    @Test @MainActor func pinFloatsRowAboveRecencyGroups() {
        let sessions = [
            Self.summary("today-1", title: "Fresh", group: .today),
            Self.summary("earlier-1", title: "Old but important", group: .earlier),
        ]
        let grouped = SessionsDrawerModel.grouped(
            sessions: sessions, query: "",
            pinnedIDs: ["earlier-1"], archivedIDs: [], showingArchived: false
        )
        #expect(grouped.first?.group == .pinned)
        #expect(grouped.first?.items.map(\.id) == ["earlier-1"])
        #expect(grouped.first?.items.first?.isPinned == true)
        // The pinned row left its recency group; the rest are untouched.
        #expect(grouped.map(\.group) == [.pinned, .today])
    }

    @Test @MainActor func noPinCapEveryPinFloats() {
        let sessions = (0..<6).map { Self.summary("s\($0)", group: .earlier) }
        let pinned: Set<String> = ["s0", "s1", "s2", "s3", "s4"]
        let grouped = SessionsDrawerModel.grouped(
            sessions: sessions, query: "",
            pinnedIDs: pinned, archivedIDs: [], showingArchived: false
        )
        #expect(grouped.first?.group == .pinned)
        #expect(grouped.first?.items.count == 5)
        // Fetch (recency) order preserved within the section.
        #expect(grouped.first?.items.map(\.id) == ["s0", "s1", "s2", "s3", "s4"])
    }

    @Test @MainActor func archivedRowsHiddenFromMainListAndShownByFilter() {
        let sessions = [
            Self.summary("keep", group: .today),
            Self.summary("hide", group: .today),
        ]
        let main = SessionsDrawerModel.grouped(
            sessions: sessions, query: "",
            pinnedIDs: [], archivedIDs: ["hide"], showingArchived: false
        )
        #expect(main.flatMap(\.items).map(\.id) == ["keep"])

        let archivedView = SessionsDrawerModel.grouped(
            sessions: sessions, query: "",
            pinnedIDs: [], archivedIDs: ["hide"], showingArchived: true
        )
        #expect(archivedView.count == 1)
        #expect(archivedView.first?.group == .archived)
        #expect(archivedView.first?.items.map(\.id) == ["hide"])
    }

    @Test @MainActor func archivedWinsOverPinForVisibility() {
        // A row can be both — archived hides it from the main list; the
        // archived view still shows its pin glyph (latent, restored on
        // unarchive).
        let sessions = [Self.summary("both", group: .today)]
        let main = SessionsDrawerModel.grouped(
            sessions: sessions, query: "",
            pinnedIDs: ["both"], archivedIDs: ["both"], showingArchived: false
        )
        #expect(main.isEmpty)

        let archivedView = SessionsDrawerModel.grouped(
            sessions: sessions, query: "",
            pinnedIDs: ["both"], archivedIDs: ["both"], showingArchived: true
        )
        #expect(archivedView.first?.items.first?.isPinned == true)
    }

    @Test @MainActor func queryFilterIsDiacriticInsensitiveAndAppliesInBothViews() {
        let sessions = [
            Self.summary("cafe", title: "Café planning", group: .today),
            Self.summary("other", title: "Weather", group: .today),
        ]
        let main = SessionsDrawerModel.grouped(
            sessions: sessions, query: "cafe",
            pinnedIDs: [], archivedIDs: [], showingArchived: false
        )
        #expect(main.flatMap(\.items).map(\.id) == ["cafe"])

        let archivedView = SessionsDrawerModel.grouped(
            sessions: sessions, query: "weather",
            pinnedIDs: [], archivedIDs: ["cafe", "other"], showingArchived: true
        )
        #expect(archivedView.flatMap(\.items).map(\.id) == ["other"])
    }

    @Test @MainActor func emptyArchiveViewReturnsNoSections() {
        let sessions = [Self.summary("s1", group: .today)]
        let archivedView = SessionsDrawerModel.grouped(
            sessions: sessions, query: "",
            pinnedIDs: [], archivedIDs: [], showingArchived: true
        )
        #expect(archivedView.isEmpty)
    }

    // MARK: Model integration (overlay writes + journal mirror)

    @Test @MainActor func togglePinWritesOverlayAndMirrorsOnlyTheHopRowToJournal() {
        let persistence = TestPersistence.make("drawer-mirror")
        let listState = ConversationListStateStore(persistence: persistence)
        let journalStore = ConversationJournalStore(persistence: persistence)
        journalStore.sync(with: Conversation(
            title: Conversation.defaultTitle,
            messages: [Message(sender: .user, content: "hi", status: .delivered)]
        ))
        journalStore.beginHop(apiSessionId: "api_current", primingUsage: nil)

        let model = SessionsDrawerModel()
        model.listState = listState
        model.journal = journalStore
        model.sessions = [
            Self.summary("api_current", group: .today, isActive: true),
            Self.summary("api_other", group: .earlier),
        ]

        // Pinning the hop-carrying row mirrors onto the journal's durable
        // flag (session ids are ephemeral per #93 — the journal copy is what
        // survives the next hop).
        model.togglePin(model.sessions[0])
        #expect(listState.isPinned("api_current"))
        #expect(journalStore.isPinned)

        // A non-hop row only writes the overlay.
        model.togglePin(model.sessions[1])
        model.toggleArchive(model.sessions[1])
        #expect(listState.isPinned("api_other"))
        #expect(listState.isArchived("api_other"))
        #expect(journalStore.isArchived == false)

        // Unpinning the hop row mirrors the flag back off.
        model.togglePin(model.sessions[0])
        #expect(listState.isPinned("api_current") == false)
        #expect(journalStore.isPinned == false)
    }

    @Test @MainActor func archivedCountCountsOnlyFetchedSessions() {
        let persistence = TestPersistence.make("drawer-count")
        let listState = ConversationListStateStore(persistence: persistence)
        let model = SessionsDrawerModel()
        model.listState = listState
        model.sessions = [Self.summary("api_1"), Self.summary("api_2")]

        // A stale overlay id (session the host no longer returns) is not a
        // visible archived row.
        listState.setArchived(true, sessionID: "ghost")
        #expect(model.archivedCount == 0)

        listState.setArchived(true, sessionID: "api_1")
        #expect(model.archivedCount == 1)
    }

    @Test @MainActor func unarchivingLastRowExitsTheArchivedView() {
        let persistence = TestPersistence.make("drawer-exit")
        let listState = ConversationListStateStore(persistence: persistence)
        let model = SessionsDrawerModel()
        model.listState = listState
        model.sessions = [Self.summary("api_1")]

        model.toggleArchive(model.sessions[0])
        model.showingArchived = true
        model.toggleArchive(model.sessions[0])
        #expect(model.showingArchived == false)
    }
}

// MARK: - Shared fixtures

private enum TestPersistence {
    @MainActor static func make(_ label: String) -> UserDefaultsAppPersistenceStore {
        let suiteName = "conversation-management-\(label)-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsAppPersistenceStore(defaults: defaults)
    }
}
