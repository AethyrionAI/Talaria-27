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
        let items = try await service.fetchInbox()

        #expect(items.map { $0.payload?["platformID"] } == ["b", "a"])
    }

    /// Same-second items are the NORMAL case, not an edge one: the plugin
    /// stamps `timespec="seconds"` and one agent turn emits its batch inside
    /// a single second. `sorted(by:)` is not guaranteed stable, so timestamp
    /// alone leaves those rows free to reorder between two reads of an
    /// unchanged cache. Merged a→b, the id tiebreak pins b→a.
    @Test func fetchOrdersSameSecondItemsDeterministically() async throws {
        let persistence = MemoryPersistence()
        var state = InboxLocalState()
        TalariaPlatformInboxService.merge(
            [
                platformItem(id: "aaa", text: "first", createdAt: "2026-08-05T21:00:00+00:00"),
                platformItem(id: "bbb", text: "second", createdAt: "2026-08-05T21:00:00+00:00"),
            ],
            into: &state
        )
        persistence.saveInboxState(state)

        let service = TalariaPlatformInboxService(persistence: persistence)
        let items = try await service.fetchInbox()

        #expect(items.map { $0.payload?["platformID"] } == ["bbb", "aaa"])
    }

    /// The tiebreak must not outrank the timestamp — an older item with a
    /// higher id still sorts below a newer one.
    @Test func fetchKeepsNewestFirstAcrossDifferentSeconds() async throws {
        let persistence = MemoryPersistence()
        var state = InboxLocalState()
        TalariaPlatformInboxService.merge(
            [
                platformItem(id: "zzz", text: "old", createdAt: "2026-08-04T21:00:00+00:00"),
                platformItem(id: "aaa", text: "new", createdAt: "2026-08-05T21:00:00+00:00"),
            ],
            into: &state
        )
        persistence.saveInboxState(state)

        let service = TalariaPlatformInboxService(persistence: persistence)
        let items = try await service.fetchInbox()

        #expect(items.map { $0.payload?["platformID"] } == ["aaa", "zzz"])
    }

    // MARK: - Decode tolerance

    @Test func decodeToleranceOldStateBlobStillLoads() throws {
        let legacyJSON = #"{"readItemIDs":[],"dismissedItemIDs":[],"localItems":[]}"#

        let state = try JSONDecoder().decode(InboxLocalState.self, from: Data(legacyJSON.utf8))

        #expect(state.platformItems.isEmpty)
    }

    // MARK: - Store integration

    /// A locally-persisted app item (the `localItems` half of the blob —
    /// #113's producer is gone since #352, but persisted rows survive
    /// tolerant decode) still leads drained platform items on screen.
    @Test func localAlertsLeadDrainedPlatformItems() async {
        let persistence = MemoryPersistence()
        persistence.inboxState.localItems.append(Self.localAlertFixture())
        let store = await makeStore(persistence: persistence)
        store.receivePlatformItems([platformItem(id: "a", text: "from the agent")])

        await store.loadInbox(force: true)

        #expect(store.items.count == 2)
        #expect(store.items.first?.type == .alert)
        #expect(store.items.last?.payload?["platformID"] == "a")
    }

    /// The clobber guard: InboxStore is the single writer of the persisted
    /// inbox blob. A drain that merged straight into persistence would be
    /// erased by the store's very next `localState` write (a markRead here;
    /// in production, any markRead/dismiss), silently losing delivered items.
    @Test func drainedItemsSurviveALaterStoreWrite() async throws {
        let persistence = MemoryPersistence()
        persistence.inboxState.localItems.append(Self.localAlertFixture())
        let store = await makeStore(persistence: persistence)
        store.receivePlatformItems([platformItem(id: "a")])
        #expect(persistence.inboxState.platformItems.count == 1)

        await store.loadInbox(force: true)
        let localAlert = try #require(store.items.first { $0.type == .alert })
        store.markRead(localAlert)

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

    /// `reset()` runs on every pairing change and every profile switch. The
    /// platform cache is the ONLY copy of these messages — the plugin drops
    /// an item from its outbox the moment the phone acks it — so clearing it
    /// there deletes the user's agent history outright.
    ///
    /// #354 design correction (2026-08-18): the marks BELONGING to surviving
    /// platform rows survive with them. The prior pin asserted
    /// `readItemIDs.isEmpty` after reset — that design was the read-mark
    /// resurrection Owen reported (items preserved, their marks cleared, so
    /// every reset re-badged old agent messages as NEW). Marks are
    /// annotations ON the rows: they share the rows' lifetime, not the
    /// relay session's.
    @Test func resetPreservesPlatformItemsWithTheirReadMarks() async throws {
        let persistence = MemoryPersistence()
        let store = await makeStore(persistence: persistence)
        store.receivePlatformItems([platformItem(id: "a", text: "from the agent")])
        await store.loadInbox(force: true)
        let landed = try #require(store.items.first)
        store.markRead(landed)
        #expect(persistence.inboxState.readItemIDs.isEmpty == false)

        store.reset()
        await store.loadInbox(force: true)

        #expect(store.items.map { $0.payload?["platformID"] } == ["a"])
        #expect(persistence.inboxState.platformItems.count == 1)
        #expect(persistence.inboxState.readItemIDs == [landed.stableIdentifier])
        #expect(store.items.first?.isRead == true)
        #expect(store.unreadCount == 0)
    }

    /// The dismiss half of the same correction: a dismissed platform row
    /// stayed hidden only while its dismissed mark lived, so reset used to
    /// resurrect those too.
    @Test func resetKeepsDismissedPlatformItemsDismissed() async throws {
        let persistence = MemoryPersistence()
        let store = await makeStore(persistence: persistence)
        store.receivePlatformItems([platformItem(id: "a"), platformItem(id: "b")])
        await store.loadInbox(force: true)
        let dismissed = try #require(store.items.first { $0.payload?["platformID"] == "b" })
        await store.dismiss(dismissed)
        #expect(store.items.count == 1)

        store.reset()
        await store.loadInbox(force: true)

        #expect(store.items.map { $0.payload?["platformID"] } == ["a"])
        #expect(persistence.inboxState.dismissedItemIDs == [dismissed.stableIdentifier])
    }

    /// Marks whose rows do NOT survive the reset die with them — the
    /// preservation is scoped to surviving rows, not a blanket keep.
    @Test func resetStillClearsMarksForClearedRows() async throws {
        let persistence = MemoryPersistence()
        persistence.inboxState.localItems.append(Self.localAlertFixture())
        let store = await makeStore(persistence: persistence)
        store.receivePlatformItems([platformItem(id: "a")])
        await store.loadInbox(force: true)
        let alert = try #require(store.items.first { $0.type == .alert })
        store.markRead(alert)

        store.reset()

        #expect(persistence.inboxState.readItemIDs.contains(alert.stableIdentifier) == false)
    }

    /// #354's reported shape end-to-end: the marks survive reset AND a store
    /// relaunch (new store over the same persistence — the cold-launch half
    /// of "every rebuild re-badges my items as NEW").
    @Test func readMarksSurviveResetAcrossAStoreRelaunch() async throws {
        let persistence = MemoryPersistence()
        let first = await makeStore(persistence: persistence)
        first.receivePlatformItems([platformItem(id: "a")])
        await first.loadInbox(force: true)
        first.markRead(try #require(first.items.first))
        first.reset()

        let relaunched = await makeStore(persistence: persistence)
        await relaunched.loadInbox(force: true)

        #expect(relaunched.items.count == 1)
        #expect(relaunched.unreadCount == 0)
    }

    /// Local app items are NOT preserved across reset — they are operational
    /// state about this device, not agent history.
    @Test func resetStillClearsLocalAlerts() async {
        let persistence = MemoryPersistence()
        persistence.inboxState.localItems.append(Self.localAlertFixture())
        let store = await makeStore(persistence: persistence)
        store.receivePlatformItems([platformItem(id: "a")])

        store.reset()
        await store.loadInbox(force: true)

        #expect(persistence.inboxState.localItems.isEmpty)
        #expect(store.items.count == 1)
        #expect(store.items.first?.type == .notification)
    }

    // MARK: - #354 user-side delete / clear-all

    /// Platform rows are the device's own copy — the server row was acked
    /// and dropped the moment it drained — so the user may delete them
    /// outright. The row goes, its marks go with it, and the persisted blob
    /// agrees. (#144's deactivate-never-delete governs SERVER rows, not the
    /// user's local copy.)
    @Test func deleteRemovesAPlatformRowAndItsMarks() async throws {
        let persistence = MemoryPersistence()
        let store = await makeStore(persistence: persistence)
        store.receivePlatformItems([platformItem(id: "a"), platformItem(id: "b")])
        await store.loadInbox(force: true)
        let doomed = try #require(store.items.first { $0.payload?["platformID"] == "a" })
        store.markRead(doomed)

        store.delete(doomed)

        #expect(store.items.map { $0.payload?["platformID"] } == ["b"])
        #expect(persistence.inboxState.platformItems.map { $0.payload?["platformID"] } == ["b"])
        #expect(persistence.inboxState.readItemIDs.contains(doomed.stableIdentifier) == false)
    }

    /// A local app row deletes the same way — it is also a device-local copy.
    @Test func deleteRemovesALocalRow() async throws {
        let persistence = MemoryPersistence()
        persistence.inboxState.localItems.append(Self.localAlertFixture())
        let store = await makeStore(persistence: persistence)
        await store.loadInbox(force: true)
        let alert = try #require(store.items.first { $0.type == .alert })

        store.delete(alert)

        #expect(store.items.isEmpty)
        #expect(persistence.inboxState.localItems.isEmpty)
    }

    @Test func deleteIsIdempotent() async throws {
        let persistence = MemoryPersistence()
        let store = await makeStore(persistence: persistence)
        store.receivePlatformItems([platformItem(id: "a")])
        await store.loadInbox(force: true)
        let doomed = try #require(store.items.first)

        store.delete(doomed)
        store.delete(doomed)

        #expect(store.items.isEmpty)
        #expect(persistence.inboxState.platformItems.isEmpty)
    }

    /// Rows the store does not own (relay-fetched) are not deletable — their
    /// lifecycle is dismiss. Delete on one is a no-op everywhere, and the
    /// affordance says so up front.
    @Test func deleteLeavesRelayFetchedRowsAlone() async throws {
        let persistence = MemoryPersistence()
        let relayRow = InboxItem(
            type: .approval,
            title: "Approve",
            body: "relay-fetched",
            isActionable: true
        )
        let store = await makeStore(persistence: persistence, service: StubRelayInboxService(rows: [relayRow]))
        await store.loadInbox(force: true)
        let fetched = try #require(store.items.first)
        #expect(store.canDelete(fetched) == false)

        store.delete(fetched)

        #expect(store.items.count == 1)
    }

    /// The affordance the UI keys swipe-delete on: owned rows (platform +
    /// local) offer delete; relay-fetched rows do not.
    @Test func deleteAvailabilityMatchesRowOrigin() async throws {
        let persistence = MemoryPersistence()
        persistence.inboxState.localItems.append(Self.localAlertFixture())
        let store = await makeStore(persistence: persistence)
        store.receivePlatformItems([platformItem(id: "a")])
        await store.loadInbox(force: true)

        let platform = try #require(store.items.first { $0.type == .notification })
        let local = try #require(store.items.first { $0.type == .alert })
        #expect(store.canDelete(platform) == true)
        #expect(store.canDelete(local) == true)
    }

    /// Clear-all is the bulk form: every owned row and its marks go, in one
    /// persisted write. Marks belonging to rows the store does NOT own
    /// (relay annotations) survive untouched.
    @Test func clearAllRemovesOwnedRowsWithTheirMarks() async throws {
        let persistence = MemoryPersistence()
        persistence.inboxState.localItems.append(Self.localAlertFixture())
        persistence.inboxState.readItemIDs.insert("FOREIGN-RELAY-MARK")
        let store = await makeStore(persistence: persistence)
        store.receivePlatformItems([platformItem(id: "a"), platformItem(id: "b")])
        await store.loadInbox(force: true)
        store.markRead(try #require(store.items.first { $0.payload?["platformID"] == "a" }))

        store.clearAllInboxItems()

        #expect(store.items.isEmpty)
        #expect(persistence.inboxState.platformItems.isEmpty)
        #expect(persistence.inboxState.localItems.isEmpty)
        #expect(persistence.inboxState.readItemIDs == ["FOREIGN-RELAY-MARK"])
    }

    /// #352 (bar 352-F sibling): a persisted #113 connector-outage alert has
    /// no producer and no clearer left — the store drops it on init, from
    /// memory AND from the persisted blob, so it can't sit in the inbox
    /// forever.
    @Test func initDropsRetiredConnectorOutageAlerts() async {
        let persistence = MemoryPersistence()
        persistence.inboxState.localItems.append(
            Self.localAlertFixture(payloadValue: "connector-outage"))
        let store = await makeStore(persistence: persistence)

        await store.loadInbox(force: true)

        #expect(persistence.inboxState.localItems.isEmpty)
        #expect(store.items.isEmpty)
    }

    /// The shape the retired #113 outage alert persisted with — kept as the
    /// local-item fixture so these tests keep exercising the `localItems`
    /// half of the blob (tolerant decode keeps old rows alive on upgrade).
    /// The default payload value is deliberately NOT "connector-outage": the
    /// #352 init drop removes that kind, and these fixtures must survive it.
    private static func localAlertFixture(payloadValue: String = "test-fixture") -> InboxItem {
        InboxItem(
            type: .alert,
            title: "Local alert",
            body: "App-generated operational alert.",
            priority: .high,
            payload: ["talaria.localAlert": payloadValue],
            primaryAction: InboxActionDescriptor(id: "acknowledge", title: "Acknowledge"),
            secondaryAction: InboxActionDescriptor(id: "dismiss", title: "Dismiss", isDestructive: true)
        )
    }

    // MARK: - Read state (Task 11 ruling)

    /// A platform row has no detail screen and no action buttons, so a tap is
    /// the only read signal it can offer — `InboxScreen` routes one here, and
    /// the unread count is what the user actually sees move.
    @Test func markingAPlatformItemReadClearsTheUnreadCount() async throws {
        let persistence = MemoryPersistence()
        let store = await makeStore(persistence: persistence)
        store.receivePlatformItems([platformItem(id: "a", text: "from the agent")])
        await store.loadInbox(force: true)
        #expect(store.unreadCount == 1)

        store.markRead(try #require(store.items.first))

        #expect(store.unreadCount == 0)
        #expect(store.items.first?.isRead == true)
    }

    /// The read mark survives the next fetch — it lives in `readItemIDs`,
    /// keyed on the row identity the merge mints once and keeps.
    @Test func aReadPlatformItemStaysReadAcrossAReload() async throws {
        let persistence = MemoryPersistence()
        let store = await makeStore(persistence: persistence)
        store.receivePlatformItems([platformItem(id: "a")])
        await store.loadInbox(force: true)
        store.markRead(try #require(store.items.first))

        await store.loadInbox(force: true)

        #expect(store.unreadCount == 0)
    }

    /// The tap rule itself: briefings open, actionable rows are left alone
    /// (marking one read recomputes `isActionable` and would strip its
    /// buttons), everything else — the platform items — marks read.
    @Test func rowTapActionRoutesByKind() {
        let platform = talariaInboxItem(from: platformItem(id: "a"))
        #expect(InboxRowTapAction.resolve(for: platform) == .markRead)

        let actionable = InboxItem(
            type: .approval,
            title: "Approve",
            body: "body",
            isActionable: true,
            primaryAction: InboxActionDescriptor(id: "approve", title: "Approve")
        )
        #expect(InboxRowTapAction.resolve(for: actionable) == .ignore)

        // #126: a briefing keeps its detail push, even though it is also
        // non-actionable — the branch order matters.
        let briefing = InboxItem(
            type: .notification,
            title: "Daily briefing",
            body: "body",
            isActionable: false,
            payload: [InboxItem.BriefingPayloadKey.category: InboxItem.briefingCategoryValue]
        )
        #expect(InboxRowTapAction.resolve(for: briefing) == .openBriefing)
    }

    // MARK: - Harness

    private func makeStore(
        persistence: MemoryPersistence,
        service: (any InboxServiceProtocol)? = nil
    ) async -> InboxStore {
        return InboxStore(
            inboxService: service ?? TalariaPlatformInboxService(persistence: persistence),
            persistence: persistence
        )
    }

    /// #354: a stand-in for the legacy relay feed — rows the store does NOT
    /// own and must refuse to delete.
    @MainActor
    private final class StubRelayInboxService: InboxServiceProtocol {
        let rows: [InboxItem]
        init(rows: [InboxItem]) { self.rows = rows }
        func fetchInbox() async throws -> [InboxItem] { rows }
        func submitAction(itemID: UUID, actionID: String) async throws -> InboxActionResult {
            InboxActionResult(itemID: itemID, actionID: actionID, status: .completed, completedAt: .now)
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
        func loadConversationCache() -> Conversation? { nil }
        func saveConversationCache(_ conversation: Conversation) {}
        func clearConversationCache() {}
        func loadPendingRunRecord() -> PendingRunRecord? { nil }
        func savePendingRunRecord(_ record: PendingRunRecord) {}
        func clearPendingRunRecord() {}
        func loadConversationJournal() -> ConversationJournal? { nil }
        func saveConversationJournal(_ journal: ConversationJournal) {}
        func clearConversationJournal() {}
        func loadConversationListState() -> ConversationListState { ConversationListState() }
        func saveConversationListState(_ state: ConversationListState) {}
        func clearConversationListState() {}
        func loadComposeOutboxState() -> ComposeOutboxState { ComposeOutboxState() }
        func saveComposeOutboxState(_ state: ComposeOutboxState) {}
        func clearComposeOutboxState() {}
    }
}
