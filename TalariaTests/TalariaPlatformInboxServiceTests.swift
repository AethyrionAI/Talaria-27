import Foundation
import Testing
@testable import Talaria

/// #251-2A: the Inbox's feed after the relay retirement (spec §2.3). The
/// drain loop hands `TalariaPlatformItem`s to the merge; the service reads
/// the merged cache back. The dedupe key is the platform id — the lane's
/// answer to the #133/#143 duplicate-delivery history: a re-delivered item
/// (the server never saw the ack) must merge to NOTHING, not to a second row.
@MainActor
struct TalariaPlatformInboxServiceTests {

    // MARK: - Fixtures

    private func platformItem(
        id: String,
        text: String = "text",
        createdAt: String = "2026-08-05T21:00:00+00:00"
    ) -> TalariaPlatformItem {
        TalariaPlatformItem(id: id, kind: "message", text: text, createdAt: createdAt, meta: nil)
    }

    // MARK: - Mapping

    @Test func mapsPlatformItemToNotificationInboxItem() {
        let item = talariaInboxItem(from: platformItem(id: "abc123", text: "Morning briefing: all clear."))

        #expect(item.type == .notification)
        #expect(item.title == "Hermes")
        #expect(item.body == "Morning briefing: all clear.")
        #expect(item.isActionable == false)
        #expect(item.payload?["platformID"] == "abc123")
        #expect(item.primaryAction == nil)
        #expect(item.secondaryAction == nil)
    }

    /// The plugin sends `datetime.now(timezone.utc).isoformat(timespec="seconds")`
    /// — a `+00:00` offset, not `Z`. Pinned to a literal epoch because the
    /// newest-first test below would pass even with a dead parser (every item
    /// would fall back to `.now`, and `.now` happens to ascend with append
    /// order). This assertion is what actually proves the date is read.
    @Test func mapsOffsetTimestampToTheRealInstant() {
        let item = talariaInboxItem(from: platformItem(id: "a", createdAt: "2026-08-05T21:00:00+00:00"))

        #expect(item.timestamp == Date(timeIntervalSince1970: 1_785_963_600))
    }

    /// A fractional-seconds stamp needs a *different* formatter configuration
    /// (the plain one returns nil for it, and the fractional one returns nil
    /// for the plain form — verified both ways). Tolerated so a plugin that
    /// drops `timespec="seconds"` doesn't silently reset every timestamp.
    @Test func mapsFractionalSecondTimestamps() {
        let item = talariaInboxItem(from: platformItem(id: "a", createdAt: "2026-08-05T21:00:00.500+00:00"))

        #expect(item.timestamp == Date(timeIntervalSince1970: 1_785_963_600.5))
    }

    /// An unparseable stamp falls back to now rather than dropping the item —
    /// the text is the payload, the timestamp is decoration.
    @Test func mapsUnparseableTimestampToNow() {
        let item = talariaInboxItem(from: platformItem(id: "a", createdAt: "yesterday-ish"))

        #expect(abs(item.timestamp.timeIntervalSinceNow) < 5)
    }

    // MARK: - Merge / dedupe

    @Test func mergeDedupesOnPlatformID() {
        var state = InboxLocalState()
        let one = platformItem(id: "a", text: "one")

        TalariaPlatformInboxService.merge([one], into: &state)
        TalariaPlatformInboxService.merge([one], into: &state)

        #expect(state.platformItems.count == 1)
    }

    /// A duplicate inside ONE batch is the same failure with a shorter fuse —
    /// the known-id set has to grow as the batch is walked, not be snapshotted
    /// before it.
    @Test func mergeDedupesWithinASingleBatch() {
        var state = InboxLocalState()

        TalariaPlatformInboxService.merge([platformItem(id: "a"), platformItem(id: "a")], into: &state)

        #expect(state.platformItems.count == 1)
    }

    @Test func mergeKeepsExistingItemsAndAppendsNewOnes() {
        var state = InboxLocalState()
        TalariaPlatformInboxService.merge([platformItem(id: "a", text: "one")], into: &state)

        TalariaPlatformInboxService.merge(
            [platformItem(id: "a", text: "one"), platformItem(id: "b", text: "two")],
            into: &state
        )

        #expect(state.platformItems.map { $0.payload?["platformID"] } == ["a", "b"])
    }

    /// The merged row's `id` is minted once and persisted — that identity is
    /// what read/dismiss bookkeeping keys on (`stableIdentifier`), so a
    /// re-delivery must not renumber it.
    @Test func mergeKeepsTheOriginalRowIdentityOnRedelivery() {
        var state = InboxLocalState()
        TalariaPlatformInboxService.merge([platformItem(id: "a")], into: &state)
        let firstID = state.platformItems.first?.id

        TalariaPlatformInboxService.merge([platformItem(id: "a")], into: &state)

        #expect(state.platformItems.first?.id == firstID)
    }

    // MARK: - Fetch

    @Test func fetchReturnsPersistedPlatformItemsNewestFirst() async throws {
        let persistence = MemoryPersistence()
        var state = InboxLocalState()
        let old = platformItem(id: "a", text: "old", createdAt: "2026-08-04T21:00:00+00:00")
        let new = platformItem(id: "b", text: "new", createdAt: "2026-08-05T21:00:00+00:00")
        TalariaPlatformInboxService.merge([old, new], into: &state)
        persistence.saveInboxState(state)

        let service = TalariaPlatformInboxService(persistence: persistence)
        let items = try await service.fetchInbox(accessToken: nil)

        #expect(items.map { $0.payload?["platformID"] } == ["b", "a"])
    }

    // MARK: - Decode tolerance

    @Test func decodeToleranceOldStateBlobStillLoads() throws {
        let legacyJSON = #"{"readItemIDs":[],"dismissedItemIDs":[],"localItems":[]}"#

        let state = try JSONDecoder().decode(InboxLocalState.self, from: Data(legacyJSON.utf8))

        #expect(state.platformItems.isEmpty)
    }

    // MARK: - Store integration

    /// #113: locally-raised operational alerts still lead. The fetched source
    /// changed under InboxStore; the ordering contract did not.
    @Test func localAlertsLeadDrainedPlatformItems() async {
        let persistence = MemoryPersistence()
        let store = await makeStore(persistence: persistence)
        store.receivePlatformItems([platformItem(id: "a", text: "from the agent")])
        store.raiseConnectorOutageAlert()

        await store.loadInbox(force: true)

        #expect(store.items.count == 2)
        #expect(store.items.first?.type == .alert)
        #expect(store.items.last?.payload?["platformID"] == "a")
    }

    /// The clobber guard: InboxStore is the single writer of the persisted
    /// inbox blob. A drain that merged straight into persistence would be
    /// erased by the store's very next `localState` write (a #113 alert here;
    /// in production, any markRead/dismiss), silently losing delivered items.
    @Test func drainedItemsSurviveALaterStoreWrite() async {
        let persistence = MemoryPersistence()
        let store = await makeStore(persistence: persistence)
        store.receivePlatformItems([platformItem(id: "a")])
        #expect(persistence.inboxState.platformItems.count == 1)

        store.raiseConnectorOutageAlert()

        #expect(persistence.inboxState.platformItems.count == 1)
    }

    /// A re-delivered item merges to nothing all the way through the store —
    /// no second row in the persisted cache, no second row on screen.
    @Test func redeliveryThroughTheStoreAddsNothing() async {
        let persistence = MemoryPersistence()
        let store = await makeStore(persistence: persistence)
        store.receivePlatformItems([platformItem(id: "a")])
        store.receivePlatformItems([platformItem(id: "a")])

        await store.loadInbox(force: true)

        #expect(persistence.inboxState.platformItems.count == 1)
        #expect(store.items.count == 1)
    }

    // MARK: - Harness

    private func makeStore(persistence: MemoryPersistence) async -> InboxStore {
        let sessionStore = AppSessionStore(
            bootstrapService: MockSessionBootstrapService(),
            syncCoordinator: MockSyncCoordinator(),
            secureStore: MockSecureStore(),
            persistence: persistence,
            environmentProvider: { .development }
        )
        await sessionStore.bootstrap()
        return InboxStore(
            inboxService: TalariaPlatformInboxService(persistence: persistence),
            persistence: persistence,
            sessionStore: sessionStore
        )
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
        var storedInstallationID: UUID?
        func loadInstallationID() -> UUID? { storedInstallationID }
        func saveInstallationID(_ id: UUID) { storedInstallationID = id }
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
}
