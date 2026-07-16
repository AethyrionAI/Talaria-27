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
}

// Legacy-key conveniences: the pre-Lane-M call shape, forwarding to the
// nil (legacy) scope. Kept so single-profile call sites and existing tests
// read exactly as before.
extension AppPersistenceStoreProtocol {
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
