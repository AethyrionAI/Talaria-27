import Foundation

/// #137 one-shot grandfathering: devices already streaming sensors when the
/// opt-in redesign lands must keep streaming without a new consent wall.
///
/// Signal: an ACTIVE PAIRING. Every pre-#137 sensor start was gated on
/// `isPaired` and nothing else beyond the #6 revoke flags, so pairing WAS the
/// app-level sensor consent — the permissions onboarding ran exactly once, at
/// pair. The alternatives are all weaker: outbox history is cleared from disk
/// on every full drain (unreliable negative), HealthKit read grants are
/// unreadable by design (in-memory only), and `locationSyncPreference` covers
/// a single sensor.
enum SensorStreamingGrandfathering {
    static let migrationDoneKey = "talaria.sensorStreamingMigrated"

    /// Applies the one-shot migration. `hadPersistedSettings` distinguishes a
    /// stored blob (whose health/location flags are real #6 decisions) from
    /// the fresh-install defaults, which are opt-out post-#137 and would
    /// otherwise silently stop a paired device that never touched Settings.
    /// Returns true when it mutated `settings`.
    @discardableResult
    static func migrateIfNeeded(
        settings: inout UserSettings,
        isPaired: Bool,
        hadPersistedSettings: Bool,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard !defaults.bool(forKey: migrationDoneKey) else { return false }
        defaults.set(true, forKey: migrationDoneKey)
        guard isPaired else { return false }

        settings.sensorStreamingEnabled = true
        // Motion never had a #6 revoke gate — it was always streaming.
        settings.motionCollectionEnabled = true
        if !hadPersistedSettings {
            // Paired but no stored blob: the pre-#137 defaults applied.
            settings.healthCollectionEnabled = true
            settings.locationCollectionEnabled = true
        }
        return true
    }
}
