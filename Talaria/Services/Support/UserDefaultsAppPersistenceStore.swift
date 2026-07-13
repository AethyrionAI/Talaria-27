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
    /// Write-through cache for the sensor outbox (#104): loads read here
    /// first so the async write path below can never serve a stale outbox
    /// to an in-process reader.
    private var sensorOutboxCache: SensorOutboxState?
    /// Tail of the FIFO sensor-outbox write chain. Internal read-only so
    /// tests can await durability deterministically.
    private(set) var sensorOutboxWriteTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, keychainMirror: KeychainSecureStore? = nil) {
        self.defaults = defaults
        self.keychainMirror = keychainMirror
        self.encoder = Self.makeEncoder()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    /// Single source of the store's encode config. The off-main sensor-outbox
    /// write path builds its own encoder from this same factory (JSONEncoder
    /// is not Sendable), so the bytes it writes always stay decodable by the
    /// instance `decoder` — a divergence would present as the #42
    /// silent-wipe decode failure.
    private nonisolated static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
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

    // The sensor outbox is this store's one hot write path — it rewrites on
    // sensor ticks (debounced service-side, #104), and the encode cost scales
    // with the backlog. So its encode + defaults write run OFF the main
    // actor: ops chain FIFO on the previous write task, which keeps an older
    // in-flight save from overtaking a newer save or clear (that would
    // resurrect stale outbox bytes on disk). Reads stay synchronous through
    // a main-actor write-through cache, so in-process load-after-save is
    // exact even while a write is still in flight — start()'s reload cannot
    // observe a pre-flush snapshot. The chain runs at .userInitiated: it
    // carries at most one debounced write per window, and the lifecycle
    // flush needs the write to land inside the post-background runway.

    func loadSensorOutboxState() -> SensorOutboxState {
        if let sensorOutboxCache { return sensorOutboxCache }
        let loaded = load(SensorOutboxState.self, key: Keys.sensorOutboxState) ?? SensorOutboxState()
        sensorOutboxCache = loaded
        return loaded
    }

    func saveSensorOutboxState(_ state: SensorOutboxState) {
        // Steady-state dedupe: a drained-then-idle pipeline flushes the same
        // state repeatedly — skip the encode + write when nothing changed.
        guard state != sensorOutboxCache else { return }
        sensorOutboxCache = state
        enqueueSensorOutboxWrite(state)
    }

    func clearSensorOutboxState() {
        guard sensorOutboxCache != SensorOutboxState() else { return }
        sensorOutboxCache = SensorOutboxState()
        // Clears are destructive privacy actions (unpair/reset): remove
        // synchronously so a process death right after can't preserve the
        // old bytes — AND through the chain, so an in-flight older save
        // can't land later and resurrect them.
        defaults.removeObject(forKey: Keys.sensorOutboxState)
        enqueueSensorOutboxWrite(nil)
    }

    /// nil = remove the key. FIFO: each op awaits its predecessor, so writes
    /// land in call order.
    private func enqueueSensorOutboxWrite(_ state: SensorOutboxState?) {
        let previous = sensorOutboxWriteTask
        // UserDefaults is documented thread-safe; the annotation carries it
        // into the detached task without a lock we don't need.
        nonisolated(unsafe) let defaults = self.defaults
        let key = Keys.sensorOutboxState
        sensorOutboxWriteTask = Task.detached(priority: .userInitiated) {
            await previous?.value
            if let state {
                guard let data = try? Self.makeEncoder().encode(state) else { return }
                defaults.set(data, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
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
