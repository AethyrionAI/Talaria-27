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
///
/// What that signal buys is deliberately narrow (#137, 2026-07-24): STREAMING
/// and motion, never health or location. Pairing is evidence the device was
/// streaming; it is not evidence of consent for the two sensors that carry
/// their own #6 revoke gates.
@MainActor
enum SensorStreamingGrandfathering {
    /// The key the done-stamp has always used. Storage moved to the
    /// persistence store's Keychain-mirrored stamp (#137) — the string stays
    /// so shipped installs that already stamped it still read as migrated.
    static let migrationDoneKey = "talaria.sensorStreamingMigrated"

    /// Applies the one-shot migration. `hadPersistedSettings` distinguishes a
    /// stored blob — whose health/location flags are real #6 decisions and are
    /// left exactly as they are — from the fresh-install defaults, which are
    /// no decision at all and grant nothing. Returns true when it mutated
    /// `settings`.
    ///
    /// The done-stamp lives in `persistence`, not `UserDefaults`: it is
    /// Keychain-mirrored there and so shares the PAIRING's lifetime. Under the
    /// old lifetime a reinstall wiped the stamp while the pairing survived, so
    /// the migration re-fired on an ordinary user path and re-enabled sensors
    /// the user had deliberately switched off.
    @discardableResult
    static func migrateIfNeeded(
        settings: inout UserSettings,
        isPaired: Bool,
        hadPersistedSettings: Bool,
        persistence: any AppPersistenceStoreProtocol
    ) -> Bool {
        guard !persistence.loadSensorStreamingMigrationStamp() else { return false }
        persistence.saveSensorStreamingMigrationStamp()
        guard isPaired else { return false }

        settings.sensorStreamingEnabled = true
        // Motion never had a #6 revoke gate — it was always streaming.
        settings.motionCollectionEnabled = true
        if !hadPersistedSettings {
            // Paired but NO stored blob. This used to read the pre-#137
            // defaults as a grant and switch health and location ON — which
            // is how a reinstall came to override a deliberate opt-OUT on
            // device. No settings blob is no evidence of consent: a stored
            // credential is not a proxy for user intent, and these two are
            // the sensors with their own #6 revoke gates. Forced OFF rather
            // than left alone so the guarantee holds whatever the caller
            // handed in.
            settings.healthCollectionEnabled = false
            settings.locationCollectionEnabled = false
        }
        return true
    }
}
