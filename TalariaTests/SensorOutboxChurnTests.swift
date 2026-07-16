import Foundation
import Testing
import UIKit
@testable import Talaria

/// #104 — sensor-outbox churn hardening. Covers the three fixes:
/// debounced persistence with teardown flush, the health-backlog cap with
/// oldest-drop + diagnostics honesty, and the off-main serialized write path
/// (durability round-trip, FIFO ordering, decode compat with pre-#104 caches).
@MainActor
struct SensorOutboxChurnTests {

    // MARK: - Test doubles

    /// Counts persistence traffic without touching UserDefaults. Explicitly
    /// @MainActor: nested types do not inherit the suite's isolation.
    @MainActor
    private final class SpyPersistenceStore: AppPersistenceStoreProtocol {
        private(set) var savedSensorOutboxStates: [SensorOutboxState] = []
        private(set) var clearSensorOutboxCount = 0
        var stubbedSensorOutboxState = SensorOutboxState()

        var sensorOutboxSaveCount: Int { savedSensorOutboxStates.count }

        func loadSensorOutboxState() -> SensorOutboxState { stubbedSensorOutboxState }
        func saveSensorOutboxState(_ state: SensorOutboxState) { savedSensorOutboxStates.append(state) }
        func clearSensorOutboxState() { clearSensorOutboxCount += 1 }

        // Unused protocol surface — inert.
        func loadUserSettings() -> UserSettings? { nil }
        func saveUserSettings(_ settings: UserSettings) {}
        func loadSessionState(profileScope: UUID?) -> AppSessionState? { nil }
        func saveSessionState(_ state: AppSessionState, profileScope: UUID?) {}
        func clearSessionState(profileScope: UUID?) {}
        func loadInboxState() -> InboxLocalState { InboxLocalState() }
        func saveInboxState(_ state: InboxLocalState) {}
        func clearInboxState() {}
        func loadPairedRelayConfiguration(profileScope: UUID?) -> PairedRelayConfiguration? { nil }
        func savePairedRelayConfiguration(_ configuration: PairedRelayConfiguration, profileScope: UUID?) {}
        func clearPairedRelayConfiguration(profileScope: UUID?) {}
        func loadBackendProfilesState() -> BackendProfilesState? { nil }
        func saveBackendProfilesState(_ state: BackendProfilesState) {}
        func clearBackendProfilesState() {}
        func loadSessionProfileIndex() -> SessionProfileIndex { SessionProfileIndex() }
        func saveSessionProfileIndex(_ index: SessionProfileIndex) {}
        func clearSessionProfileIndex() {}
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

    /// Deterministic stand-in for the debounce interval: the trailing write
    /// parks here until the test releases it — no real sleeping, no clocks.
    @MainActor
    private final class DebounceGate {
        private var waiters: [CheckedContinuation<Void, Never>] = []
        var waiterCount: Int { waiters.count }

        func wait() async {
            await withCheckedContinuation { waiters.append($0) }
        }

        func release() {
            let parked = waiters
            waiters = []
            for waiter in parked { waiter.resume() }
        }
    }

    // MARK: - Helpers

    private func makeSensorService(
        persistence: any AppPersistenceStoreProtocol,
        gate: DebounceGate,
        notificationCenter: NotificationCenter = NotificationCenter()
    ) -> SensorUploadService {
        SensorUploadService(
            apiClient: RelayAPIClient(baseURLProvider: { "http://127.0.0.1:9" }),
            accessTokenProvider: { nil },
            persistence: persistence,
            isPairedProvider: { false },
            isHealthCollectionEnabled: { false },
            isLocationCollectionEnabled: { false },
            locationService: LiveLocationService(),
            healthService: LiveHealthService(),
            motionService: nil,
            notificationCenter: notificationCenter,
            persistDebounceWait: { @MainActor in await gate.wait() }
        )
    }

    /// Unique dedupe key per index: heart_rate is non-windowed, so the key
    /// includes startAt, which varies with the index.
    private func healthSample(_ index: Int) -> HealthSnapshot.Sample {
        HealthSnapshot.Sample(
            metric: "heart_rate",
            value: Double(index),
            unit: "bpm",
            startAt: Date(timeIntervalSince1970: Double(index)),
            endAt: nil
        )
    }

    private func locationUpdate(_ index: Int) -> LocationUpdate {
        LocationUpdate(
            latitude: 40.0 + Double(index) * 0.001,
            longitude: -73.0,
            altitude: nil,
            accuracy: 20,
            timestamp: Date(timeIntervalSince1970: Double(index))
        )
    }

    /// The trailing write task starts asynchronously on the main actor;
    /// yield until `count` waiters have parked on the gate (bounded so a
    /// regression fails fast instead of hanging). Takes an explicit count
    /// because a flush-cancelled task stays parked until the gate releases —
    /// waiting for "any waiter" would return before a NEW task parks.
    private func waitUntilParked(_ gate: DebounceGate, expecting count: Int = 1) async {
        for _ in 0..<1000 where gate.waiterCount < count {
            await Task.yield()
        }
    }

    private func makeIsolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "sensor-outbox-churn-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    // MARK: - Debounce / coalesce (#104 deliverable 1)

    @Test
    func rapidTicksCoalesceIntoOneTrailingSave() async {
        let store = SpyPersistenceStore()
        let gate = DebounceGate()
        let service = makeSensorService(persistence: store, gate: gate)

        for index in 0..<25 {
            service.recordHealthSamples([healthSample(index)])
        }
        service.recordLocationUpdate(locationUpdate(0))
        await waitUntilParked(gate)

        // All ticks landed inside the window: nothing written yet, exactly
        // one trailing write armed.
        #expect(store.sensorOutboxSaveCount == 0)
        #expect(gate.waiterCount == 1)

        // The window elapses → exactly one save, carrying every tick.
        let trailing = service.pendingOutboxPersistTask
        gate.release()
        await trailing?.value
        #expect(store.sensorOutboxSaveCount == 1)
        #expect(store.savedSensorOutboxStates.last?.pendingHealthSamples.count == 25)
        #expect(store.savedSensorOutboxStates.last?.pendingLocation != nil)

        // The debounce re-arms: a later tick schedules a fresh trailing
        // write, and the next window's save lands too.
        service.recordHealthSamples([healthSample(999)])
        await waitUntilParked(gate)
        #expect(store.sensorOutboxSaveCount == 1)
        let second = service.pendingOutboxPersistTask
        gate.release()
        await second?.value
        #expect(store.sensorOutboxSaveCount == 2)
        #expect(store.savedSensorOutboxStates.last?.pendingHealthSamples.count == 26)
    }

    @Test
    func stopFlushesThePendingWriteExactlyOnce() async {
        let store = SpyPersistenceStore()
        let gate = DebounceGate()
        let service = makeSensorService(persistence: store, gate: gate)

        service.recordHealthSamples([healthSample(1)])
        await waitUntilParked(gate)
        let trailing = service.pendingOutboxPersistTask
        #expect(store.sensorOutboxSaveCount == 0)

        service.stop()
        #expect(store.sensorOutboxSaveCount == 1)
        #expect(store.savedSensorOutboxStates.last?.pendingHealthSamples.count == 1)

        // The cancelled trailing task must not double-write once the window
        // "elapses".
        gate.release()
        await trailing?.value
        #expect(store.sensorOutboxSaveCount == 1)
    }

    @Test
    func lifecycleNotificationsFlushThePendingWrite() async {
        let store = SpyPersistenceStore()
        let gate = DebounceGate()
        let center = NotificationCenter()
        let service = makeSensorService(persistence: store, gate: gate, notificationCenter: center)

        service.recordHealthSamples([healthSample(1)])
        await waitUntilParked(gate)
        #expect(store.sensorOutboxSaveCount == 0)

        // Posted on the main thread with queue nil → delivered synchronously,
        // exactly like UIKit's real lifecycle posts.
        center.post(name: UIApplication.willResignActiveNotification, object: nil)
        #expect(store.sensorOutboxSaveCount == 1)

        // The first flush cancelled its trailing task, but that task stays
        // parked on the gate until release — so the SECOND task makes two.
        service.recordHealthSamples([healthSample(2)])
        await waitUntilParked(gate, expecting: 2)
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        #expect(store.sensorOutboxSaveCount == 2)

        // Clean state: a lifecycle flush with nothing dirty writes nothing.
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        #expect(store.sensorOutboxSaveCount == 2)

        // Both parked tasks were cancelled by the flushes: releasing them
        // must not produce extra saves.
        gate.release()
        await Task.yield()
        #expect(store.sensorOutboxSaveCount == 2)
    }

    @Test
    func flushWithoutPendingChangesIsANoOp() {
        let store = SpyPersistenceStore()
        let service = makeSensorService(persistence: store, gate: DebounceGate())

        service.flushOutboxPersistence()
        #expect(store.sensorOutboxSaveCount == 0)
        #expect(store.clearSensorOutboxCount == 0)
    }

    // MARK: - Backlog cap (#104 deliverable 2)

    @Test
    func backlogCapDropsOldestAndCountsTheLoss() async {
        let store = SpyPersistenceStore()
        let gate = DebounceGate()
        let service = makeSensorService(persistence: store, gate: gate)
        let cap = SensorUploadService.maxPendingHealthSamples

        // Exactly at the cap: nothing dropped, no flag.
        service.recordHealthSamples((0..<cap).map(healthSample))
        #expect(service.sensorDiagnostics.pendingHealthCount == cap)
        #expect(service.sensorDiagnostics.droppedHealthCount == 0)

        // Three past the cap: the three OLDEST fall out, count stays capped,
        // and the diagnostics surface reports the loss honestly.
        service.recordHealthSamples([healthSample(cap), healthSample(cap + 1), healthSample(cap + 2)])
        #expect(service.sensorDiagnostics.pendingHealthCount == cap)
        #expect(service.sensorDiagnostics.droppedHealthCount == 3)

        // The persisted state agrees: front of the queue is now sample 3,
        // the newest samples survived, and the tally rides along.
        service.flushOutboxPersistence()
        let saved = store.savedSensorOutboxStates.last
        #expect(saved?.pendingHealthSamples.count == cap)
        #expect(saved?.pendingHealthSamples.first?.value == 3)
        #expect(saved?.pendingHealthSamples.last?.value == Double(cap + 2))
        #expect(saved?.droppedHealthSampleCount == 3)

        gate.release()
    }

    @Test
    func underCapEnqueueDropsNothing() async {
        let store = SpyPersistenceStore()
        let gate = DebounceGate()
        let service = makeSensorService(persistence: store, gate: gate)

        service.recordHealthSamples((0..<10).map(healthSample))
        #expect(service.sensorDiagnostics.pendingHealthCount == 10)
        #expect(service.sensorDiagnostics.droppedHealthCount == 0)

        service.flushOutboxPersistence()
        #expect(store.savedSensorOutboxStates.last?.droppedHealthSampleCount == 0)

        gate.release()
    }

    @Test
    func enforceHealthBacklogCapIsOldestDropAndTallies() {
        var state = SensorOutboxState()
        state.enqueue(healthSamples: (0..<5).map(healthSample))

        let dropped = state.enforceHealthBacklogCap(3)
        #expect(dropped == 2)
        #expect(state.pendingHealthSamples.count == 3)
        #expect(state.pendingHealthSamples.first?.value == 2)
        #expect(state.droppedHealthSampleCount == 2)

        // Under the cap: no-op, tally untouched.
        #expect(state.enforceHealthBacklogCap(3) == 0)
        #expect(state.droppedHealthSampleCount == 2)
    }

    @Test
    func backlogCapShieldsTheInFlightPrefix() {
        var state = SensorOutboxState()
        state.enqueue(healthSamples: (0..<10).map(healthSample))

        // Three samples are mid-upload: the trim must drop the oldest
        // samples BEHIND them, never the in-flight prefix — otherwise the
        // post-delivery removal would delete never-uploaded samples.
        let dropped = state.enforceHealthBacklogCap(8, protectingPrefix: 3)
        #expect(dropped == 2)
        #expect(state.pendingHealthSamples.count == 8)
        #expect(state.pendingHealthSamples.prefix(3).map(\.value) == [0, 1, 2])
        #expect(state.pendingHealthSamples[3].value == 5)
        #expect(state.droppedHealthSampleCount == 2)
    }

    @Test
    func stopFlushIsDurableThroughTheRealStore() async {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAppPersistenceStore(defaults: defaults)
        let gate = DebounceGate()
        let service = makeSensorService(persistence: store, gate: gate)

        // The composed teardown seam: service flush → store's async write
        // chain → bytes on disk. This is the path the terminate/background
        // flush actually rides in production.
        service.recordHealthSamples([healthSample(1), healthSample(2)])
        service.stop()
        await store.sensorOutboxWriteTask?.value

        let reader = UserDefaultsAppPersistenceStore(defaults: defaults)
        #expect(reader.loadSensorOutboxState().pendingHealthSamples.count == 2)
        gate.release()
    }

    @Test
    func oversizedLoadedBacklogIsCappedOnStart() {
        let store = SpyPersistenceStore()
        let gate = DebounceGate()
        let cap = SensorUploadService.maxPendingHealthSamples
        var oversized = SensorOutboxState()
        oversized.enqueue(healthSamples: (0..<(cap + 40)).map(healthSample))
        store.stubbedSensorOutboxState = oversized

        let service = makeSensorService(persistence: store, gate: gate)
        service.start()

        #expect(service.sensorDiagnostics.pendingHealthCount == cap)
        #expect(service.sensorDiagnostics.droppedHealthCount == 40)

        // start() marks the trim dirty; teardown persists the capped state.
        service.stop()
        #expect(store.savedSensorOutboxStates.last?.pendingHealthSamples.count == cap)
        #expect(store.savedSensorOutboxStates.last?.droppedHealthSampleCount == 40)

        gate.release()
    }

    // MARK: - Off-main persisted writes (#104 deliverable 3)

    @Test
    func outboxRoundTripsThroughDefaultsViaTheAsyncWriteChain() async {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let writer = UserDefaultsAppPersistenceStore(defaults: defaults)
        var outbox = SensorOutboxState()
        outbox.enqueue(location: locationUpdate(7))
        outbox.enqueue(healthSamples: [healthSample(1), healthSample(2)])
        outbox.droppedHealthSampleCount = 4

        writer.saveSensorOutboxState(outbox)
        // Same-instance read is exact immediately (write-through cache),
        // even before the async write lands.
        #expect(writer.loadSensorOutboxState() == outbox)

        await writer.sensorOutboxWriteTask?.value

        // A separate store instance (cold cache) must decode the real bytes.
        let reader = UserDefaultsAppPersistenceStore(defaults: defaults)
        #expect(reader.loadSensorOutboxState() == outbox)
    }

    @Test
    func writeChainPreservesSaveThenClearOrdering() async {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let writer = UserDefaultsAppPersistenceStore(defaults: defaults)
        var outbox = SensorOutboxState()
        outbox.enqueue(healthSamples: [healthSample(1)])

        // save → clear: the clear must win on disk (a reordering here would
        // resurrect stale outbox bytes after a reset).
        writer.saveSensorOutboxState(outbox)
        writer.clearSensorOutboxState()
        await writer.sensorOutboxWriteTask?.value
        #expect(UserDefaultsAppPersistenceStore(defaults: defaults).loadSensorOutboxState() == SensorOutboxState())

        // clear → save: the save must win.
        writer.clearSensorOutboxState()
        writer.saveSensorOutboxState(outbox)
        await writer.sensorOutboxWriteTask?.value
        #expect(UserDefaultsAppPersistenceStore(defaults: defaults).loadSensorOutboxState() == outbox)
    }

    // MARK: - Decode compatibility (pre-#104 caches)

    @Test
    func preCapCacheBytesStillDecode() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // The exact shape UserDefaultsAppPersistenceStore wrote before #104:
        // no droppedHealthSampleCount key, iso8601 dates.
        let preCapJSON = """
        {"pendingLocation":{"latitude":40.5,"longitude":-73.9,"altitude":12.5,"accuracy":20,"recordedAt":"2026-07-11T12:00:00Z"},"pendingHealthSamples":[{"metric":"heart_rate","value":72,"unit":"bpm","startAt":"2026-07-11T12:00:00Z","endAt":null}]}
        """
        // Key literal mirrors UserDefaultsAppPersistenceStore.Keys.sensorOutboxState.
        defaults.set(Data(preCapJSON.utf8), forKey: "hermes.sensorOutboxState")

        let loaded = UserDefaultsAppPersistenceStore(defaults: defaults).loadSensorOutboxState()
        #expect(loaded.pendingLocation?.latitude == 40.5)
        #expect(loaded.pendingLocation?.altitude == 12.5)
        #expect(loaded.pendingHealthSamples.count == 1)
        #expect(loaded.pendingHealthSamples.first?.metric == "heart_rate")
        #expect(loaded.droppedHealthSampleCount == 0)
    }
}
