import Foundation

@MainActor
protocol AppPersistenceStoreProtocol {
    func loadUserSettings() -> UserSettings?
    func saveUserSettings(_ settings: UserSettings)
    // Relay session state — profile-scoped (Lane M): a nil scope resolves the
    // legacy pre-profile key, which the migrated first profile keeps.
    func loadSessionState(profileScope: UUID?) -> AppSessionState?
    func saveSessionState(_ state: AppSessionState, profileScope: UUID?)
    func clearSessionState(profileScope: UUID?)
    func loadInboxState() -> InboxLocalState
    func saveInboxState(_ state: InboxLocalState)
    func clearInboxState()
    // Paired relay configuration — profile-scoped (Lane M), same nil-scope
    // rule. Pairing profile B must never touch profile A's record (#114).
    func loadPairedRelayConfiguration(profileScope: UUID?) -> PairedRelayConfiguration?
    func savePairedRelayConfiguration(_ configuration: PairedRelayConfiguration, profileScope: UUID?)
    func clearPairedRelayConfiguration(profileScope: UUID?)
    // Backend profiles (Lane M / #114) — the profile list plus active +
    // sensor-destination ids, one blob, Keychain-mirrored like the pairing
    // config so profile UUIDs survive reinstalls with the credentials they key.
    func loadBackendProfilesState() -> BackendProfilesState?
    func saveBackendProfilesState(_ state: BackendProfilesState)
    func clearBackendProfilesState()
    // Session→birth-profile index (Lane M / M-1).
    func loadSessionProfileIndex() -> SessionProfileIndex
    func saveSessionProfileIndex(_ index: SessionProfileIndex)
    func clearSessionProfileIndex()
    // Session→last-run-usage index (#25) — the CTX gauge's resume cache.
    func loadSessionUsageIndex() -> SessionUsageIndex
    func saveSessionUsageIndex(_ index: SessionUsageIndex)
    func clearSessionUsageIndex()
    func loadSensorOutboxState() -> SensorOutboxState
    func saveSensorOutboxState(_ state: SensorOutboxState)
    func clearSensorOutboxState()
    func loadConversationCache() -> Conversation?
    func saveConversationCache(_ conversation: Conversation)
    func clearConversationCache()
    func loadConversationJournal() -> ConversationJournal?
    func saveConversationJournal(_ journal: ConversationJournal)
    func clearConversationJournal()
    func loadConversationListState() -> ConversationListState
    func saveConversationListState(_ state: ConversationListState)
    func clearConversationListState()
    func loadComposeOutboxState() -> ComposeOutboxState
    func saveComposeOutboxState(_ state: ComposeOutboxState)
    func clearComposeOutboxState()
    func loadHealthQueryAnchorData(for identifier: String) -> Data?
    func saveHealthQueryAnchorData(_ data: Data?, for identifier: String)
    func clearHealthQueryAnchorData()

    /// #137: whether the sensor opt-in grandfathering has already been
    /// considered on this device. Keychain-mirrored in the real store, so it
    /// shares the PAIRING's lifetime rather than the app container's — a
    /// reinstall with a surviving pairing must not re-run the migration.
    func loadSensorStreamingMigrationStamp() -> Bool
    func saveSensorStreamingMigrationStamp()

    /// DEBUG ONLY (#137, 2026-07-24). The stamp is deliberately MONOTONIC in
    /// shipping builds: clearing it on unpair would let a re-pair re-run the
    /// migration against an un-stamped, paired device and switch streaming and
    /// motion ON without consent — the exact inversion half 2 of #137 closes.
    /// Guarding the requirement makes that monotonicity structural rather than
    /// a convention nobody happens to have broken yet: in release there is no
    /// clear to call. It exists at all because #137's own fresh-install device
    /// pass is otherwise unrunnable without erasing the device.
    #if DEBUG
    func clearSensorStreamingMigrationStamp()
    #endif
}

// Legacy-key conveniences: the pre-Lane-M call shape, forwarding to the
// nil (legacy) scope. Kept so single-profile call sites and existing tests
// read exactly as before.
extension AppPersistenceStoreProtocol {
    /// Test doubles that never migrate anything read as never-stamped. The
    /// real store overrides all three (#137); a double that needs to model a
    /// prior install's stamp overrides them too.
    func loadSensorStreamingMigrationStamp() -> Bool { false }
    func saveSensorStreamingMigrationStamp() {}
    #if DEBUG
    func clearSensorStreamingMigrationStamp() {}
    #endif

    func loadSessionState() -> AppSessionState? {
        loadSessionState(profileScope: nil)
    }

    func saveSessionState(_ state: AppSessionState) {
        saveSessionState(state, profileScope: nil)
    }

    func clearSessionState() {
        clearSessionState(profileScope: nil)
    }

    func loadPairedRelayConfiguration() -> PairedRelayConfiguration? {
        loadPairedRelayConfiguration(profileScope: nil)
    }

    func savePairedRelayConfiguration(_ configuration: PairedRelayConfiguration) {
        savePairedRelayConfiguration(configuration, profileScope: nil)
    }

    func clearPairedRelayConfiguration() {
        clearPairedRelayConfiguration(profileScope: nil)
    }
}
