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

    @Test func pairedDeviceWithoutBlobGrandfathersEverythingOn() {
        let defaults = isolatedDefaults()
        var settings = UserSettings()
        let mutated = SensorStreamingGrandfathering.migrateIfNeeded(
            settings: &settings, isPaired: true, hadPersistedSettings: false, defaults: defaults)
        #expect(mutated)
        #expect(settings.sensorStreamingEnabled == true)
        #expect(settings.motionCollectionEnabled == true)
        #expect(settings.healthCollectionEnabled == true)
        #expect(settings.locationCollectionEnabled == true)
    }

    @Test func pairedDeviceWithBlobKeepsPriorRevokes() {
        let defaults = isolatedDefaults()
        var settings = UserSettings(healthCollectionEnabled: false, locationCollectionEnabled: true)
        _ = SensorStreamingGrandfathering.migrateIfNeeded(
            settings: &settings, isPaired: true, hadPersistedSettings: true, defaults: defaults)
        #expect(settings.sensorStreamingEnabled == true)
        #expect(settings.motionCollectionEnabled == true)
        #expect(settings.healthCollectionEnabled == false)  // #6 revoke honored
        #expect(settings.locationCollectionEnabled == true)
    }

    @Test func freshDeviceStaysOptedOut() {
        let defaults = isolatedDefaults()
        var settings = UserSettings()
        let mutated = SensorStreamingGrandfathering.migrateIfNeeded(
            settings: &settings, isPaired: false, hadPersistedSettings: false, defaults: defaults)
        #expect(!mutated)
        #expect(settings.sensorStreamingEnabled == false)
        #expect(defaults.bool(forKey: SensorStreamingGrandfathering.migrationDoneKey))
    }

    @Test func migrationRunsExactlyOnce() {
        let defaults = isolatedDefaults()
        var settings = UserSettings()
        _ = SensorStreamingGrandfathering.migrateIfNeeded(
            settings: &settings, isPaired: false, hadPersistedSettings: false, defaults: defaults)
        // A later pair must not re-trigger grandfathering — pairing after
        // the migration means the user chose the new opt-in world.
        let second = SensorStreamingGrandfathering.migrateIfNeeded(
            settings: &settings, isPaired: true, hadPersistedSettings: true, defaults: defaults)
        #expect(!second)
        #expect(settings.sensorStreamingEnabled == false)
    }
}

// MARK: - #137 capture-loop gating

/// Inert persistence for gate tests — no disk, no UserDefaults.
@MainActor
private final class InertPersistenceStore: AppPersistenceStoreProtocol {
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
