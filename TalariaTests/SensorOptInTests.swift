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
