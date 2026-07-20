import Foundation
import Testing
@testable import Talaria

// #126: a briefing is recognized by payload category alone — tolerant of the
// producer's kind, honest when fields are missing (#58 lesson).

@Suite("Briefing recognition")
struct BriefingRecognitionTests {

    private func item(
        type: InboxItemType = .notification,
        payload: [String: String]? = nil,
        timestamp: Date = .now,
        body: String = "Body"
    ) -> InboxItem {
        InboxItem(type: type, title: "Title", body: body, timestamp: timestamp, payload: payload)
    }

    @Test("notification + category briefing is a briefing")
    func recognizesBriefing() {
        #expect(item(payload: ["category": "briefing"]).isBriefing)
    }

    @Test("Absent category, absent payload, or another category is NOT a briefing")
    func rejectsNonBriefings() {
        #expect(!item(payload: nil).isBriefing)
        #expect(!item(payload: [:]).isBriefing)
        #expect(!item(payload: ["category": "digest"]).isBriefing)
        #expect(!item(payload: ["speakable": "hi"]).isBriefing)
    }

    @Test("Recognition keys on category alone — a briefing payload on another kind still renders richly")
    func toleratesUnexpectedKind() {
        #expect(item(type: .reminder, payload: ["category": "briefing"]).isBriefing)
    }

    @Test("latestBriefing picks the newest briefing and ignores non-briefings")
    func latestSelection() {
        let old = item(payload: ["category": "briefing"], timestamp: Date(timeIntervalSinceReferenceDate: 1_000))
        let new = item(payload: ["category": "briefing"], timestamp: Date(timeIntervalSinceReferenceDate: 2_000))
        let noise = item(payload: nil, timestamp: Date(timeIntervalSinceReferenceDate: 3_000))
        #expect(InboxItem.latestBriefing(in: [old, noise, new])?.id == new.id)
        #expect(InboxItem.latestBriefing(in: [noise]) == nil)
        #expect(InboxItem.latestBriefing(in: []) == nil)
    }
}

@Suite("Briefing speakable text")
struct BriefingSpeakableTests {

    private func briefing(speakable: String?, body: String) -> InboxItem {
        var payload = ["category": "briefing"]
        if let speakable { payload["speakable"] = speakable }
        return InboxItem(type: .notification, title: "T", body: body, payload: payload)
    }

    @Test("speakable wins when present, trimmed")
    func speakableWins() {
        #expect(briefing(speakable: "  Good morning.  ", body: "ignored").briefingSpeakableText == "Good morning.")
    }

    @Test("Blank speakable falls back to the fence-stripped body")
    func blankSpeakableFallsBack() {
        #expect(briefing(speakable: "   ", body: "Hello there.").briefingSpeakableText == "Hello there.")
        #expect(briefing(speakable: nil, body: "Hello there.").briefingSpeakableText == "Hello there.")
    }

    @Test("Fallback drops fenced blocks — markers AND contents (chart JSON is not speech)")
    func fallbackStripsFences() {
        let body = "Sleep was solid.\n```chart\n{\"type\":\"bar\"}\n```\nThree events today."
        #expect(briefing(speakable: nil, body: body).briefingSpeakableText == "Sleep was solid.\nThree events today.")
    }

    @Test("Blank lines around a fence survive — typical markdown keeps its paragraph break")
    func blankLinesAroundFenceSurvive() {
        let body = "Sleep was solid.\n\n```chart\n{\"type\":\"bar\"}\n```\n\nThree events today."
        #expect(briefing(speakable: nil, body: body).briefingSpeakableText == "Sleep was solid.\n\n\nThree events today.")
    }

    @Test("Unterminated fence drops the tail — parity with the parser, which keeps it a code block")
    func unterminatedFenceDropsTail() {
        let body = "Intro line.\n```chart\n{\"type\":"
        #expect(InboxItem.strippingFencedBlocks(from: body) == "Intro line.")
    }
}

@Suite("Briefing widget snapshot")
struct BriefingWidgetSnapshotTests {

    @Test("Pre-#126 snapshot JSON (no briefing keys) still decodes")
    func oldSnapshotDecodes() throws {
        let old = #"{"hostOnline":true,"voiceSessionActive":false,"updatedAt":770000000}"#
        let data = try JSONDecoder().decode(HermesWidgetData.self, from: Data(old.utf8))
        #expect(data.briefingTitle == nil)
        #expect(data.briefingFirstLine == nil)
        #expect(data.briefingReceivedAt == nil)
    }

    @Test("Briefing fields round-trip through the app-group encoding")
    func roundTrip() throws {
        var data = HermesWidgetData.empty
        data.briefingTitle = "Morning briefing — Mon Jul 20"
        data.briefingFirstLine = "Sleep 7h 24m · 3 events today"
        data.briefingReceivedAt = Date(timeIntervalSinceReferenceDate: 770_000_000)
        let decoded = try JSONDecoder().decode(HermesWidgetData.self, from: JSONEncoder().encode(data))
        #expect(decoded.briefingTitle == data.briefingTitle)
        #expect(decoded.briefingFirstLine == data.briefingFirstLine)
        #expect(decoded.briefingReceivedAt == data.briefingReceivedAt)
    }

    @Test("Stamping fills title, condensed first line, and timestamp from the newest briefing")
    func stampsNewestBriefing() {
        let body = "## Sleep\n```chart\n{\"type\":\"bar\"}\n```\nYou slept 7h 24m — solid.\nMore detail."
        let older = InboxItem(
            type: .notification, title: "Old", body: "Old body",
            timestamp: Date(timeIntervalSinceReferenceDate: 1_000),
            payload: ["category": "briefing"]
        )
        let newer = InboxItem(
            type: .notification, title: "Morning briefing — Mon Jul 20", body: body,
            timestamp: Date(timeIntervalSinceReferenceDate: 2_000),
            payload: ["category": "briefing"]
        )
        var data = HermesWidgetData.empty
        data.stampBriefing(from: [older, newer])
        #expect(data.briefingTitle == "Morning briefing — Mon Jul 20")
        // First meaningful line: heading markers stripped → "Sleep" is the
        // first line that carries words; fences are skipped entirely.
        #expect(data.briefingFirstLine == "Sleep")
        #expect(data.briefingReceivedAt == Date(timeIntervalSinceReferenceDate: 2_000))
    }

    @Test("No briefing in the fetch leaves existing stamped values untouched — a mid-day empty fetch must not wipe the widget")
    func absentBriefingKeepsStampedValues() {
        var data = HermesWidgetData.empty
        data.briefingTitle = "Kept"
        data.briefingFirstLine = "Kept line"
        data.briefingReceivedAt = Date(timeIntervalSinceReferenceDate: 5)
        let noise = InboxItem(type: .alert, title: "A", body: "B")
        data.stampBriefing(from: [noise])
        #expect(data.briefingTitle == "Kept")
        #expect(data.briefingFirstLine == "Kept line")
        #expect(data.briefingReceivedAt == Date(timeIntervalSinceReferenceDate: 5))
    }
}

@Suite("InboxStore markRead")
@MainActor
struct InboxStoreMarkReadTests {

    @MainActor
    private final class StubInboxService: InboxServiceProtocol {
        var stubbedItems: [InboxItem] = []
        func fetchInbox(accessToken: String?) async throws -> [InboxItem] { stubbedItems }
        func submitAction(itemID: UUID, actionID: String, accessToken: String?) async throws -> InboxActionResult {
            Issue.record("markRead must never round-trip the relay")
            throw URLError(.badServerResponse)
        }
    }

    @MainActor
    private final class MemoryPersistence: AppPersistenceStoreProtocol {
        var inboxState = InboxLocalState()
        func loadInboxState() -> InboxLocalState { inboxState }
        func saveInboxState(_ state: InboxLocalState) { inboxState = state }
        func clearInboxState() { inboxState = InboxLocalState() }
        // Unused protocol surface — inert.
        func loadUserSettings() -> UserSettings? { nil }
        func saveUserSettings(_ settings: UserSettings) {}
        func loadSessionState(profileScope: UUID?) -> AppSessionState? { nil }
        func saveSessionState(_ state: AppSessionState, profileScope: UUID?) {}
        func clearSessionState(profileScope: UUID?) {}
        func loadPairedRelayConfiguration(profileScope: UUID?) -> PairedRelayConfiguration? { nil }
        func savePairedRelayConfiguration(_ configuration: PairedRelayConfiguration, profileScope: UUID?) {}
        func clearPairedRelayConfiguration(profileScope: UUID?) {}
        func loadBackendProfilesState() -> BackendProfilesState? { nil }
        func saveBackendProfilesState(_ state: BackendProfilesState) {}
        func clearBackendProfilesState() {}
        func loadSessionProfileIndex() -> SessionProfileIndex { SessionProfileIndex() }
        func saveSessionProfileIndex(_ index: SessionProfileIndex) {}
        func clearSessionProfileIndex() {}
        func loadSessionUsageIndex() -> SessionUsageIndex { SessionUsageIndex() }
        func saveSessionUsageIndex(_ index: SessionUsageIndex) {}
        func clearSessionUsageIndex() {}
        func loadSensorOutboxState() -> SensorOutboxState { SensorOutboxState() }
        func saveSensorOutboxState(_ state: SensorOutboxState) {}
        func clearSensorOutboxState() {}
        func loadConversationCache() -> Conversation? { nil }
        func saveConversationCache(_ conversation: Conversation) {}
        func clearConversationCache() {}
        func loadConversationJournal() -> ConversationJournal? { nil }
        func saveConversationJournal(_ journal: ConversationJournal) {}
        func clearConversationJournal() {}
        func loadConversationListState() -> ConversationListState { ConversationListState() }
        func saveConversationListState(_ state: ConversationListState) {}
        func clearConversationListState() {}
        func loadComposeOutboxState() -> ComposeOutboxState { ComposeOutboxState() }
        func saveComposeOutboxState(_ state: ComposeOutboxState) {}
        func clearComposeOutboxState() {}
        func loadHealthQueryAnchorData(for identifier: String) -> Data? { nil }
        func saveHealthQueryAnchorData(_ data: Data?, for identifier: String) {}
        func clearHealthQueryAnchorData() {}
    }

    private func makeStore(
        service: StubInboxService = StubInboxService(),
        persistence: MemoryPersistence = MemoryPersistence()
    ) async -> InboxStore {
        let sessionStore = AppSessionStore(
            bootstrapService: MockSessionBootstrapService(),
            syncCoordinator: MockSyncCoordinator(),
            secureStore: MockSecureStore(),
            persistence: persistence,
            notificationService: MockNotificationService(),
            environmentProvider: { .development }
        )
        await sessionStore.bootstrap()
        return InboxStore(inboxService: service, persistence: persistence, sessionStore: sessionStore)
    }

    @Test("markRead flips the item read + non-actionable without a relay round-trip")
    func marksReadLocally() async {
        let service = StubInboxService()
        let briefing = InboxItem(
            type: .notification, title: "Briefing", body: "B",
            payload: ["category": "briefing"]
        )
        service.stubbedItems = [briefing]
        let store = await makeStore(service: service)
        await store.loadInbox(force: true)

        store.markRead(briefing)

        #expect(store.items.first?.isRead == true)
        #expect(store.items.first?.status == .opened)
        #expect(store.items.first?.isActionable == false)
        #expect(store.unreadCount == 0)
    }

    @Test("markRead persists — a reloaded store still shows the item read")
    func persistsAcrossReload() async {
        let service = StubInboxService()
        let persistence = MemoryPersistence()
        let briefing = InboxItem(
            type: .notification, title: "Briefing", body: "B",
            payload: ["category": "briefing"]
        )
        service.stubbedItems = [briefing]
        let store = await makeStore(service: service, persistence: persistence)
        await store.loadInbox(force: true)
        store.markRead(briefing)

        let reloaded = await makeStore(service: service, persistence: persistence)
        await reloaded.loadInbox(force: true)
        #expect(reloaded.items.first?.isRead == true)
    }

    @Test("markRead is idempotent")
    func idempotent() async {
        let service = StubInboxService()
        let briefing = InboxItem(type: .notification, title: "B", body: "B", payload: ["category": "briefing"])
        service.stubbedItems = [briefing]
        let store = await makeStore(service: service)
        await store.loadInbox(force: true)
        store.markRead(briefing)
        store.markRead(briefing)
        #expect(store.items.count == 1)
        #expect(store.items.first?.isRead == true)
    }
}
