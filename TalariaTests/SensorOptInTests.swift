import Foundation
import Testing
@testable import Talaria

// MARK: - #137 settings surface

@MainActor
struct SensorOptInSettingsTests {
    @Test func freshInstallDefaultsAreFullyOptedOut() {
        let settings = UserSettings()
        #expect(settings.sensorStreamingEnabled == false)
        #expect(settings.motionCollectionEnabled == false)
        #expect(settings.healthCollectionEnabled == false)
        #expect(settings.locationCollectionEnabled == false)
    }

    @Test func demoDataFallbackIsFullyOptedOut() {
        // SettingsStore's no-blob fallback must not opt anyone in.
        let settings = DemoData.sampleUserSettings
        #expect(settings.sensorStreamingEnabled == false)
        #expect(settings.healthCollectionEnabled == false)
        #expect(settings.locationCollectionEnabled == false)
        #expect(settings.motionCollectionEnabled == false)
    }

    @Test func legacyBlobDecodesMasterOffButKeepsRevokeSemantics() throws {
        // Pre-#137 blob: none of the new keys. Master/motion default OFF —
        // grandfathering decides, not the decoder. Health/location keep the
        // pre-#6 "absent means not revoked" reading so a grandfathered
        // device's revoke state survives untouched.
        let decoded = try JSONDecoder().decode(UserSettings.self, from: Data("{}".utf8))
        #expect(decoded.sensorStreamingEnabled == false)
        #expect(decoded.motionCollectionEnabled == false)
        #expect(decoded.healthCollectionEnabled == true)
        #expect(decoded.locationCollectionEnabled == true)
    }

    @Test func optInRoundTrips() throws {
        var settings = UserSettings()
        settings.sensorStreamingEnabled = true
        settings.motionCollectionEnabled = true
        let decoded = try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.sensorStreamingEnabled == true)
        #expect(decoded.motionCollectionEnabled == true)
    }
}

// MARK: - #137 grandfathering migration

@MainActor
struct SensorGrandfatheringTests {
    private func isolatedDefaults() -> UserDefaults {
        let suite = "sensor-optin-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    // MARK: - What a surviving pairing does and does not authorise (#137)

    @Test func pairedDeviceWithoutBlobGrandfathersStreamingOnlyNotHealthOrLocation() {
        // #137 half 2. No stored settings blob is NO EVIDENCE OF CONSENT.
        // Granting health and location here treated a stored credential as a
        // proxy for user intent — the inversion that let a reinstall override
        // a deliberate opt-OUT on device. Streaming and motion still
        // grandfather: every pre-#137 sensor start was gated on `isPaired`
        // alone, so pairing WAS the app-level streaming consent.
        let persistence = InertPersistenceStore()
        var settings = UserSettings(healthCollectionEnabled: true, locationCollectionEnabled: true)
        let mutated = SensorStreamingGrandfathering.migrateIfNeeded(
            settings: &settings, isPaired: true, hadPersistedSettings: false, persistence: persistence)
        #expect(mutated)
        #expect(settings.sensorStreamingEnabled == true)
        #expect(settings.motionCollectionEnabled == true)
        #expect(settings.healthCollectionEnabled == false)
        #expect(settings.locationCollectionEnabled == false)
    }

    @Test func pairedDeviceWithBlobKeepsPriorRevokes() {
        let persistence = InertPersistenceStore()
        var settings = UserSettings(healthCollectionEnabled: false, locationCollectionEnabled: true)
        _ = SensorStreamingGrandfathering.migrateIfNeeded(
            settings: &settings, isPaired: true, hadPersistedSettings: true, persistence: persistence)
        #expect(settings.sensorStreamingEnabled == true)
        #expect(settings.motionCollectionEnabled == true)
        #expect(settings.healthCollectionEnabled == false)  // #6 revoke honored
        #expect(settings.locationCollectionEnabled == true)  // …and so is a real grant
    }

    @Test func freshDeviceStaysOptedOut() {
        let persistence = InertPersistenceStore()
        var settings = UserSettings()
        let mutated = SensorStreamingGrandfathering.migrateIfNeeded(
            settings: &settings, isPaired: false, hadPersistedSettings: false, persistence: persistence)
        #expect(!mutated)
        #expect(settings.sensorStreamingEnabled == false)
        #expect(persistence.loadSensorStreamingMigrationStamp())
    }

    @Test func migrationRunsExactlyOnce() {
        let persistence = InertPersistenceStore()
        var settings = UserSettings()
        _ = SensorStreamingGrandfathering.migrateIfNeeded(
            settings: &settings, isPaired: false, hadPersistedSettings: false, persistence: persistence)
        // A later pair must not re-trigger grandfathering — pairing after
        // the migration means the user chose the new opt-in world.
        let second = SensorStreamingGrandfathering.migrateIfNeeded(
            settings: &settings, isPaired: true, hadPersistedSettings: true, persistence: persistence)
        #expect(!second)
        #expect(settings.sensorStreamingEnabled == false)
    }

    // MARK: - The stamp's lifetime (#137 half 1)

    @Test func aStampThatOutlivedTheAppContainerDeclinesToReMigrate() {
        // The #137 device sequence: app DELETED, then reinstalled with the
        // Keychain pairing intact and no opt-in performed. Under the old
        // UserDefaults stamp the wiped container read as "never migrated" and
        // the migration re-fired, resurrecting the permission wall and
        // overriding a deliberate opt-out. The stamp now shares the PAIRING's
        // storage, so a surviving pairing carries a surviving stamp.
        let persistence = InertPersistenceStore()
        persistence.saveSensorStreamingMigrationStamp()
        var settings = UserSettings()
        let mutated = SensorStreamingGrandfathering.migrateIfNeeded(
            settings: &settings, isPaired: true, hadPersistedSettings: false, persistence: persistence)
        #expect(!mutated)
        #expect(settings.sensorStreamingEnabled == false)
        #expect(settings.motionCollectionEnabled == false)
    }
}

// MARK: - #137 the stamp's storage

@MainActor
struct SensorMigrationStampStorageTests {
    private func isolatedDefaults() -> UserDefaults {
        let suite = "sensor-stamp-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// Keychain-free by construction: `keychainMirror` is nil here, which is
    /// also what the unsigned test build needs — `CODE_SIGNING_ALLOWED=NO`
    /// strips the entitlements and the simulator keychain then rejects every
    /// SecItem write silently. The mirrored half is a device assertion.
    @Test func stampRoundTripsAndStartsUnset() {
        let store = UserDefaultsAppPersistenceStore(defaults: isolatedDefaults())
        #expect(!store.loadSensorStreamingMigrationStamp())
        store.saveSensorStreamingMigrationStamp()
        #expect(store.loadSensorStreamingMigrationStamp())
    }

    @Test func aStampWrittenBeforeThisFixStillReadsAsMigrated() {
        // Upgrade path: installs that already ran the migration stamped the
        // raw UserDefaults key. Re-keying would have re-fired the migration
        // on every one of them — the same defect, shipped wider.
        let defaults = isolatedDefaults()
        defaults.set(true, forKey: SensorStreamingGrandfathering.migrationDoneKey)
        let store = UserDefaultsAppPersistenceStore(defaults: defaults)
        #expect(store.loadSensorStreamingMigrationStamp())
    }
}

// MARK: - #137 capture-loop gating

/// Inert persistence for gate tests — no disk, no UserDefaults. The one piece
/// of state it does keep is the #137 migration stamp, so the grandfathering
/// tests can drive both of its lifetimes (never stamped / stamped by a prior
/// install) without touching a keychain the unsigned test build cannot write.
@MainActor
private final class InertPersistenceStore: AppPersistenceStoreProtocol {
    private var sensorMigrationStamped = false
    func loadSensorStreamingMigrationStamp() -> Bool { sensorMigrationStamped }
    func saveSensorStreamingMigrationStamp() { sensorMigrationStamped = true }
    func clearSensorStreamingMigrationStamp() { sensorMigrationStamped = false }

    func loadSensorOutboxState() -> SensorOutboxState { SensorOutboxState() }
    func saveSensorOutboxState(_ state: SensorOutboxState) {}
    func clearSensorOutboxState() {}
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
    func loadSessionUsageIndex() -> SessionUsageIndex { SessionUsageIndex() }
    func saveSessionUsageIndex(_ index: SessionUsageIndex) {}
    func clearSessionUsageIndex() {}
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

@MainActor
struct SensorStreamingGateTests {
    /// The health gate stays FALSE in every case here: start() with health on
    /// fires a live HealthKit auth request, and sim builds strip the
    /// entitlement (never assert HealthKit outcomes — dispatch rule).
    private func makeService(
        master: @escaping @MainActor () -> Bool,
        location: @escaping @MainActor () -> Bool = { false },
        motion: LiveMotionService? = nil,
        motionEnabled: @escaping @MainActor () -> Bool = { false }
    ) -> (SensorUploadService, LiveLocationService) {
        let locationService = LiveLocationService()
        let service = SensorUploadService(
            apiClient: RelayAPIClient(baseURLProvider: { "http://127.0.0.1:9" }),
            accessTokenProvider: { nil },
            persistence: InertPersistenceStore(),
            isPairedProvider: { false },
            isSensorStreamingEnabled: master,
            isHealthCollectionEnabled: { false },
            isLocationCollectionEnabled: location,
            isMotionCollectionEnabled: motionEnabled,
            locationService: locationService,
            healthService: LiveHealthService(),
            motionService: motion,
            notificationCenter: NotificationCenter()
        )
        return (service, locationService)
    }

    @Test func masterOffMeansStartNeverActivates() {
        let (service, locationService) = makeService(master: { false }, location: { true })
        service.start()
        #expect(service.sensorDiagnostics.isActive == false)
        #expect(locationService.onLocationUpdate == nil)
    }

    @Test func masterOnWithAllSensorsOffIdlesEverySource() {
        let (service, locationService) = makeService(master: { true })
        service.start()
        #expect(service.sensorDiagnostics.isActive == true)
        #expect(locationService.onLocationUpdate == nil)
        service.stop()
    }

    @Test func masterOnWithLocationOnWiresCapture() {
        let (service, locationService) = makeService(master: { true }, location: { true })
        service.start()
        #expect(locationService.onLocationUpdate != nil)
        service.stop()
    }

    @Test func motionGateOffLeavesMotionUnwired() {
        let motionService = LiveMotionService()
        let (service, _) = makeService(master: { true }, motion: motionService, motionEnabled: { false })
        service.start()
        #expect(motionService.onActivityUpdate == nil)
        service.stop()
    }
}
