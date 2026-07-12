import Foundation

@MainActor
final class UserDefaultsAppPersistenceStore: AppPersistenceStoreProtocol {
    private enum Keys {
        static let userSettings = "hermes.userSettings"
        static let sessionState = "hermes.sessionState"
        static let inboxState = "hermes.inboxState"
        static let pairedRelayConfiguration = "hermes.pairedRelayConfiguration"
        static let sensorOutboxState = "hermes.sensorOutboxState"
        static let conversationCache = "hermes.conversationCache"
        static let conversationJournal = "hermes.conversationJournal"
        static let conversationListState = "hermes.conversationListState"
        static let composeOutboxState = "hermes.composeOutboxState"
        static let healthAnchorPrefix = "hermes.healthAnchor."
    }

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    /// Mirrors the pairing config into the Keychain, which — unlike this
    /// UserDefaults container — survives clean reinstalls and signing
    /// transitions (#41). Optional so tests can run UserDefaults-only.
    private let keychainMirror: KeychainSecureStore?

    init(defaults: UserDefaults = .standard, keychainMirror: KeychainSecureStore? = nil) {
        self.defaults = defaults
        self.keychainMirror = keychainMirror

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func loadUserSettings() -> UserSettings? {
        load(UserSettings.self, key: Keys.userSettings)
    }

    func saveUserSettings(_ settings: UserSettings) {
        save(settings, key: Keys.userSettings)
    }

    func loadSessionState() -> AppSessionState? {
        load(AppSessionState.self, key: Keys.sessionState)
    }

    func saveSessionState(_ state: AppSessionState) {
        save(state, key: Keys.sessionState)
    }

    func clearSessionState() {
        defaults.removeObject(forKey: Keys.sessionState)
    }

    func loadInboxState() -> InboxLocalState {
        load(InboxLocalState.self, key: Keys.inboxState) ?? InboxLocalState()
    }

    func saveInboxState(_ state: InboxLocalState) {
        save(state, key: Keys.inboxState)
    }

    func clearInboxState() {
        defaults.removeObject(forKey: Keys.inboxState)
    }

    // The pairing config is dual-stored (#41): UserDefaults (primary, fast) +
    // Keychain (survives the clean-install container wipes that forced
    // re-pairs even though session tokens were sitting safe in the Keychain).
    // Load prefers the Keychain and re-hydrates whichever store is missing.

    func loadPairedRelayConfiguration() -> PairedRelayConfiguration? {
        let defaultsCopy = load(PairedRelayConfiguration.self, key: Keys.pairedRelayConfiguration)
        guard let keychainMirror else { return defaultsCopy }

        if let json = keychainMirror.retrieveSync(key: Keys.pairedRelayConfiguration) {
            do {
                let keychainCopy = try decoder.decode(PairedRelayConfiguration.self, from: Data(json.utf8))
                if defaultsCopy == nil {
                    // Reinstall recovery: the UserDefaults container was wiped
                    // but the Keychain copy survived — re-hydrate UserDefaults.
                    save(keychainCopy, key: Keys.pairedRelayConfiguration)
                }
                return keychainCopy
            } catch {
                TalariaLog.event("persistence: decode of PairedRelayConfiguration (Keychain mirror) failed: \(error)")
            }
        }

        if let defaultsCopy {
            // Upgrade path for installs paired before the Keychain mirror
            // existed: back-fill the Keychain from the UserDefaults copy.
            mirrorToKeychain(defaultsCopy)
        }
        return defaultsCopy
    }

    func savePairedRelayConfiguration(_ configuration: PairedRelayConfiguration) {
        save(configuration, key: Keys.pairedRelayConfiguration)
        mirrorToKeychain(configuration)
    }

    func clearPairedRelayConfiguration() {
        defaults.removeObject(forKey: Keys.pairedRelayConfiguration)
        keychainMirror?.deleteSync(key: Keys.pairedRelayConfiguration)
    }

    private func mirrorToKeychain(_ configuration: PairedRelayConfiguration) {
        guard let keychainMirror,
              let data = try? encoder.encode(configuration),
              let json = String(data: data, encoding: .utf8) else { return }
        keychainMirror.storeSync(key: Keys.pairedRelayConfiguration, value: json)
    }

    func loadSensorOutboxState() -> SensorOutboxState {
        load(SensorOutboxState.self, key: Keys.sensorOutboxState) ?? SensorOutboxState()
    }

    func saveSensorOutboxState(_ state: SensorOutboxState) {
        save(state, key: Keys.sensorOutboxState)
    }

    func clearSensorOutboxState() {
        defaults.removeObject(forKey: Keys.sensorOutboxState)
    }

    func loadConversationCache() -> Conversation? {
        load(Conversation.self, key: Keys.conversationCache)
    }

    func saveConversationCache(_ conversation: Conversation) {
        save(conversation, key: Keys.conversationCache)
    }

    func clearConversationCache() {
        defaults.removeObject(forKey: Keys.conversationCache)
    }

    func loadConversationJournal() -> ConversationJournal? {
        load(ConversationJournal.self, key: Keys.conversationJournal)
    }

    func saveConversationJournal(_ journal: ConversationJournal) {
        save(journal, key: Keys.conversationJournal)
    }

    func clearConversationJournal() {
        defaults.removeObject(forKey: Keys.conversationJournal)
    }

    func loadConversationListState() -> ConversationListState {
        load(ConversationListState.self, key: Keys.conversationListState) ?? ConversationListState()
    }

    func saveConversationListState(_ state: ConversationListState) {
        save(state, key: Keys.conversationListState)
    }

    func clearConversationListState() {
        defaults.removeObject(forKey: Keys.conversationListState)
    }

    func loadComposeOutboxState() -> ComposeOutboxState {
        load(ComposeOutboxState.self, key: Keys.composeOutboxState) ?? ComposeOutboxState()
    }

    func saveComposeOutboxState(_ state: ComposeOutboxState) {
        if state.isEmpty {
            defaults.removeObject(forKey: Keys.composeOutboxState)
        } else {
            save(state, key: Keys.composeOutboxState)
        }
    }

    func clearComposeOutboxState() {
        defaults.removeObject(forKey: Keys.composeOutboxState)
    }

    func loadHealthQueryAnchorData(for identifier: String) -> Data? {
        defaults.data(forKey: Keys.healthAnchorPrefix + identifier)
    }

    func saveHealthQueryAnchorData(_ data: Data?, for identifier: String) {
        let key = Keys.healthAnchorPrefix + identifier
        if let data {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    func clearHealthQueryAnchorData() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Keys.healthAnchorPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            // Always-on: a decode failure here presents downstream as missing
            // state (e.g. a schema change reading as a silent unpair, #42) —
            // this line is what tells that apart from a real container wipe.
            TalariaLog.event("persistence: decode of \(type) failed for key \(key): \(error)")
            return nil
        }
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
