import Foundation
import Testing
@testable import Talaria

// #113: the trigger/dedupe/clear rules for the connector-down inbox alert,
// tested as the pure decision function they are — no drain harness, no I/O.

@Suite("ConnectorOutageAlertPolicy")
struct ConnectorOutageAlertPolicyTests {

    @Test("Alert raises on the 3rd consecutive retry-exhausted cycle, not before")
    func raisesAtThreshold() {
        var policy = ConnectorOutageAlertPolicy()
        #expect(policy.record(.retryExhausted) == .none)
        #expect(policy.record(.retryExhausted) == .none)
        #expect(policy.record(.retryExhausted) == .raiseAlert)
    }

    @Test("Dedupe: the outage keeps exhausting but the alert fires exactly once")
    func raisesOnlyOncePerOutage() {
        var policy = ConnectorOutageAlertPolicy()
        for _ in 0..<3 { _ = policy.record(.retryExhausted) }
        #expect(policy.record(.retryExhausted) == .none)
        #expect(policy.record(.retryExhausted) == .none)
        #expect(policy.alertActive)
    }

    @Test("A delivery before the threshold resets the streak")
    func deliveryResetsStreak() {
        var policy = ConnectorOutageAlertPolicy()
        #expect(policy.record(.retryExhausted) == .none)
        #expect(policy.record(.retryExhausted) == .none)
        #expect(policy.record(.delivered) == .none)  // nothing raised yet — nothing to clear
        #expect(policy.record(.retryExhausted) == .none)
        #expect(policy.record(.retryExhausted) == .none)
        #expect(policy.record(.retryExhausted) == .raiseAlert)
    }

    @Test("An inconclusive cycle breaks the streak — the signature is CONSECUTIVE exhaustion")
    func inconclusiveBreaksStreak() {
        var policy = ConnectorOutageAlertPolicy()
        #expect(policy.record(.retryExhausted) == .none)
        #expect(policy.record(.retryExhausted) == .none)
        #expect(policy.record(.inconclusive) == .none)
        #expect(policy.record(.retryExhausted) == .none)  // streak restarted at 1
        #expect(policy.record(.retryExhausted) == .none)
        #expect(policy.record(.retryExhausted) == .raiseAlert)
    }

    @Test("Only a delivery clears an active alert — inconclusive cycles never do")
    func clearsOnlyOnDelivery() {
        var policy = ConnectorOutageAlertPolicy()
        for _ in 0..<3 { _ = policy.record(.retryExhausted) }
        #expect(policy.alertActive)
        #expect(policy.record(.inconclusive) == .none)
        #expect(policy.alertActive)
        #expect(policy.record(.delivered) == .clearAlert)
        #expect(!policy.alertActive)
        #expect(policy.record(.delivered) == .none)  // clear fires once
    }

    @Test("After a clear, a fresh outage must re-accumulate the full streak to re-raise")
    func reRaisesAfterRecovery() {
        var policy = ConnectorOutageAlertPolicy()
        for _ in 0..<3 { _ = policy.record(.retryExhausted) }
        #expect(policy.record(.delivered) == .clearAlert)
        #expect(policy.record(.retryExhausted) == .none)
        #expect(policy.record(.retryExhausted) == .none)
        #expect(policy.record(.retryExhausted) == .raiseAlert)
    }

    @Test("Threshold constant matches the dispatched N=3")
    func thresholdIsThree() {
        #expect(ConnectorOutageAlertPolicy.consecutiveExhaustionThreshold == 3)
    }
}

// The inbox side: raise is deduped, clear removes, and the local item
// survives both a successful and a failed relay fetch.

@Suite("InboxStore connector-outage alert")
@MainActor
struct InboxStoreConnectorOutageAlertTests {

    @MainActor
    private final class StubInboxService: InboxServiceProtocol {
        var stubbedItems: [InboxItem] = []
        var shouldFail = false

        func fetchInbox(accessToken: String?) async throws -> [InboxItem] {
            if shouldFail { throw URLError(.cannotConnectToHost) }
            return stubbedItems
        }

        func submitAction(itemID: UUID, actionID: String, accessToken: String?) async throws -> InboxActionResult {
            Issue.record("local items must never round-trip the relay")
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

    @Test("Raise enqueues exactly one alert; repeat raises are no-ops")
    func raiseIsDeduped() async {
        let store = await makeStore()
        store.raiseConnectorOutageAlert()
        store.raiseConnectorOutageAlert()
        let alerts = store.items.filter { $0.type == .alert }
        #expect(alerts.count == 1)
        #expect(store.unreadCount == 1)
    }

    @Test("Clear removes the alert; clearing with none live is safe")
    func clearRemoves() async {
        let store = await makeStore()
        store.clearConnectorOutageAlert()  // nothing live — must not trap
        store.raiseConnectorOutageAlert()
        store.clearConnectorOutageAlert()
        #expect(store.items.isEmpty)
        #expect(store.unreadCount == 0)
    }

    @Test("The alert survives a successful relay fetch, ahead of fetched rows")
    func alertSurvivesFetch() async {
        let service = StubInboxService()
        service.stubbedItems = [
            InboxItem(serverID: UUID(), type: .notification, title: "Server row", body: "from relay")
        ]
        let store = await makeStore(service: service)
        store.raiseConnectorOutageAlert()
        await store.loadInbox(force: true)
        #expect(store.items.count == 2)
        #expect(store.items.first?.type == .alert)
    }

    @Test("The alert survives a FAILED relay fetch — both symptoms share a cause")
    func alertSurvivesFetchFailure() async {
        let service = StubInboxService()
        service.shouldFail = true
        let store = await makeStore(service: service)
        store.raiseConnectorOutageAlert()
        await store.loadInbox(force: true)
        #expect(store.lastErrorMessage != nil)
        #expect(store.items.count == 1)
        #expect(store.items.first?.type == .alert)
    }

    @Test("Dismissing the alert resolves locally — no relay call, item gone")
    func dismissIsLocal() async {
        let store = await makeStore()
        store.raiseConnectorOutageAlert()
        guard let alert = store.items.first else {
            Issue.record("alert missing after raise")
            return
        }
        await store.dismiss(alert)
        #expect(store.items.isEmpty)
        // A later raise (policy re-fires only after a clear + fresh streak)
        // gets a fresh identity, so the old dismissal can't suppress it.
        store.raiseConnectorOutageAlert()
        #expect(store.items.count == 1)
    }

    @Test("Acknowledge marks the alert read but keeps it visible")
    func acknowledgeMarksRead() async {
        let store = await makeStore()
        store.raiseConnectorOutageAlert()
        guard let alert = store.items.first else {
            Issue.record("alert missing after raise")
            return
        }
        await store.performPrimaryAction(for: alert)
        #expect(store.items.count == 1)
        #expect(store.items.first?.isRead == true)
        #expect(store.unreadCount == 0)
    }

    @Test("Pre-#113 persisted inbox state (no localItems key) decodes additively")
    func legacyStateDecodes() throws {
        let legacyJSON = Data(#"{"readItemIDs":["a"],"dismissedItemIDs":["b"]}"#.utf8)
        let decoded = try JSONDecoder().decode(InboxLocalState.self, from: legacyJSON)
        #expect(decoded.readItemIDs == ["a"])
        #expect(decoded.dismissedItemIDs == ["b"])
        #expect(decoded.localItems.isEmpty)
    }

    @Test("A live alert round-trips persistence — it must survive a relaunch mid-outage")
    func alertPersistsAcrossRelaunch() async throws {
        let persistence = MemoryPersistence()
        let store = await makeStore(persistence: persistence)
        store.raiseConnectorOutageAlert()

        // Same persisted bytes, fresh store — the relaunch shape.
        let encoded = try JSONEncoder().encode(persistence.inboxState)
        persistence.inboxState = try JSONDecoder().decode(InboxLocalState.self, from: encoded)
        let relaunched = await makeStore(persistence: persistence)
        await relaunched.loadInbox(force: true)
        #expect(relaunched.items.count == 1)
        #expect(relaunched.items.first?.type == .alert)
    }
}
