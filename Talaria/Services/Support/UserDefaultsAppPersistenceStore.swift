import Foundation

@MainActor
final class UserDefaultsAppPersistenceStore: AppPersistenceStoreProtocol {
    private enum Keys {
        static let userSettings = "hermes.userSettings"
        static let inboxState = "hermes.inboxState"
        static let backendProfiles = "hermes.backendProfiles"
        static let sessionProfileIndex = "hermes.sessionProfileIndex"
        static let sessionUsageIndex = "hermes.sessionUsageIndex"
        static let conversationCache = "hermes.conversationCache"
        // #329: the pending run's durable record; cleared with the cache.
        static let pendingRunRecord = "hermes.pendingRunRecord"
        static let conversationJournal = "hermes.conversationJournal"
        static let conversationListState = "hermes.conversationListState"
        static let composeOutboxState = "hermes.composeOutboxState"
        // #277: agent-file chip records per server session id. Sits beside
        // the conversation cache and is cleared with it on unpair/reset —
        // it names what the agent wrote, so it must not outlive the pairing.
        static let agentAttachmentSidecar = "hermes.agentAttachmentSidecar"
        static let turnReceiptSidecar = "hermes.turnReceiptSidecar"
        // #137: deliberately the SAME string the migration first stamped into
        // UserDefaults. Re-keying would have read every already-migrated
        // install as never-migrated and re-fired the migration on all of
        // them — the defect, shipped wider.
        static let sensorStreamingMigrated = "talaria.sensorStreamingMigrated"
        static let relayRetirementMigrated = "talaria.relayRetirementMigrated"
        // #133/#143: the installation id is deliberately NOT profile-scoped
        // and is never cleared by unpair. It identifies this app INSTALL, not
        // a session or a relay — it used to ride inside the profile-scoped
        // `AppSessionState`, which `clearSession` deletes, so every
        // unpair + cold launch minted a fresh identity and the relay
        // (correctly) minted a fresh device row. Measured 2026-08-02 on the
        // Mac relay: 99 device rows against 99 distinct installation ids.
        static let installationID = "talaria.installationID"
        // Session state + pairing config are profile-scoped (Lane M): keys
        // derive from BackendProfileScopedKeys, where a nil scope yields the
        // pre-profile strings ("hermes.sessionState" /
        // "hermes.pairedRelayConfiguration") the migrated profile keeps.
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
        self.encoder = Self.makeEncoder()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        purgeRetiredSensorUploadArtifacts()
    }

    /// #352: the sensor-upload pipeline is retired. Its persisted outbox (a
    /// pending GPS fix + up to 500 health samples) and HealthKit query
    /// anchors have no reader left — remove them. Unconditional and
    /// idempotent: removing an absent key is free, and no surviving path
    /// recreates either key family. Key strings are inlined because their
    /// `Keys` constants died with the pipeline; they are retired names, never
    /// to be reused.
    private func purgeRetiredSensorUploadArtifacts() {
        defaults.removeObject(forKey: "hermes.sensorOutboxState")
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix("hermes.healthAnchor.") {
            defaults.removeObject(forKey: key)
        }
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

    /// #133/#143 — app-wide, scope-free, and NOT cleared by unpair. See the
    /// note on `Keys.installationID`.
    func loadInstallationID() -> UUID? {
        guard let raw = defaults.string(forKey: Keys.installationID) else { return nil }
        return UUID(uuidString: raw)
    }

    func saveInstallationID(_ id: UUID) {
        defaults.set(id.uuidString, forKey: Keys.installationID)
    }

    /// #309 Lane B (bar 309-B9). Removes BOTH dead blobs for one scope, from
    /// UserDefaults AND the Keychain mirror — `pairedRelayConfiguration` was
    /// dual-stored (#41), so a UserDefaults-only sweep would leave the mirror
    /// holding a relay user id forever and a reinstall would restore it.
    ///
    /// NOTE: deliberately does NOT touch `Keys.installationID` — that coupling
    /// was the #133/#143 root cause, and it outlives every credential here.
    func purgeRelayCredentialResidue(profileScope: UUID?) {
        let sessionKey = BackendProfileScopedKeys.sessionState(profileScope)
        let pairingKey = BackendProfileScopedKeys.pairedRelayConfiguration(profileScope)
        defaults.removeObject(forKey: sessionKey)
        keychainMirror?.deleteSync(key: sessionKey)
        defaults.removeObject(forKey: pairingKey)
        keychainMirror?.deleteSync(key: pairingKey)
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
    // Profile-scoped since Lane M — each backend profile has its own slot.

    // Backend profiles ride the same dual-store (Lane M): the profile UUIDs
    // key every per-profile credential, so they must survive reinstalls
    // together with the Keychain entries they scope.

    func loadBackendProfilesState() -> BackendProfilesState? {
        loadDualStored(BackendProfilesState.self, key: Keys.backendProfiles)
    }

    func saveBackendProfilesState(_ state: BackendProfilesState) {
        saveDualStored(state, key: Keys.backendProfiles)
    }

    func clearBackendProfilesState() {
        defaults.removeObject(forKey: Keys.backendProfiles)
        keychainMirror?.deleteSync(key: Keys.backendProfiles)
    }

    // #137: the sensor opt-in migration's done-stamp. UserDefaults alone was
    // the wrong lifetime — it dies with the app container while the pairing
    // does not, so a reinstall over a surviving Keychain pairing read as
    // "never migrated" and re-fired, resurrecting the permission wall and
    // overriding a deliberate opt-OUT (device, whoGoesThere). Mirrored rather
    // than dual-stored through loadDualStored: the value is a bare Bool
    // already written under this key by shipped builds, not a Codable blob.

    func loadSensorStreamingMigrationStamp() -> Bool {
        if keychainMirror?.retrieveSync(key: Keys.sensorStreamingMigrated) != nil { return true }
        guard defaults.bool(forKey: Keys.sensorStreamingMigrated) else { return false }
        // Upgrade path, mirroring loadDualStored's: stamped before the stamp
        // was mirrored, so back-fill the Keychain now — otherwise this
        // install stays one reinstall away from the original defect.
        keychainMirror?.storeSync(key: Keys.sensorStreamingMigrated, value: "1")
        return true
    }

    func saveSensorStreamingMigrationStamp() {
        defaults.set(true, forKey: Keys.sensorStreamingMigrated)
        keychainMirror?.storeSync(key: Keys.sensorStreamingMigrated, value: "1")
    }

    // #310: the relay-retirement stamp. Keychain-mirrored for the SAME reason
    // the sensor stamp above is, and the failure it prevents is sharper here:
    // an unmirrored stamp dies with the app container, so a reinstall over a
    // surviving pairing would read as "never migrated" and re-clear a relay
    // URL the user had deliberately typed back in. That is bar 310-B's
    // phase-2 failure arriving through a second door — persistence loss
    // rather than a normalization pass — and only the mirror closes it.

    func loadRelayRetirementMigrationStamp() -> Bool {
        // ⚠️ ORDER REVERSED vs the sensor stamp above, deliberately:
        // UserDefaults FIRST, Keychain only as the fallback.
        //
        // This runs inside `BackendProfilesStore.init`, which is on the
        // LAUNCH CRITICAL PATH (#136's partition). Reading the Keychain first
        // — as the sensor stamp does — puts a synchronous Keychain hit in
        // front of the first frame on EVERY launch, forever, to answer a
        // question UserDefaults can already answer on all but the first one.
        //
        // The semantics are identical: the mirror exists so the stamp
        // survives a reinstall that wipes UserDefaults, and that case is
        // exactly the one where `defaults.bool` is false. Checking it second
        // costs nothing and skips the Keychain entirely on the normal path.
        if defaults.bool(forKey: Keys.relayRetirementMigrated) { return true }
        guard keychainMirror?.retrieveSync(key: Keys.relayRetirementMigrated) != nil else { return false }
        // Reinstall path: the mirror survived, UserDefaults did not. Restore
        // the cheap copy so subsequent launches never reach the Keychain.
        defaults.set(true, forKey: Keys.relayRetirementMigrated)
        return true
    }

    func saveRelayRetirementMigrationStamp() {
        defaults.set(true, forKey: Keys.relayRetirementMigrated)
        keychainMirror?.storeSync(key: Keys.relayRetirementMigrated, value: "1")
    }

    /// DEBUG ONLY — see the protocol. Must clear BOTH halves: `load` returns
    /// true on the Keychain mirror alone, so a UserDefaults-only reset would
    /// silently do nothing and cost a device pass to discover.
    #if DEBUG
    func clearSensorStreamingMigrationStamp() {
        defaults.removeObject(forKey: Keys.sensorStreamingMigrated)
        keychainMirror?.deleteSync(key: Keys.sensorStreamingMigrated)
    }
    #endif

    func loadSessionProfileIndex() -> SessionProfileIndex {
        load(SessionProfileIndex.self, key: Keys.sessionProfileIndex) ?? SessionProfileIndex()
    }

    func saveSessionProfileIndex(_ index: SessionProfileIndex) {
        save(index, key: Keys.sessionProfileIndex)
    }

    func clearSessionProfileIndex() {
        defaults.removeObject(forKey: Keys.sessionProfileIndex)
    }

    // #25: a malformed blob decodes to nil in load(_:key:) and lands here as
    // a fresh empty index — the gauge degrades to "unknown", never to a wrong
    // number and never to a throw.
    func loadSessionUsageIndex() -> SessionUsageIndex {
        load(SessionUsageIndex.self, key: Keys.sessionUsageIndex) ?? SessionUsageIndex()
    }

    func saveSessionUsageIndex(_ index: SessionUsageIndex) {
        save(index, key: Keys.sessionUsageIndex)
    }

    func clearSessionUsageIndex() {
        defaults.removeObject(forKey: Keys.sessionUsageIndex)
    }

    /// The #41 dual-store read: Keychain wins, whichever side is missing is
    /// re-hydrated. Extracted from the pairing-config path so the backend
    /// profiles blob gets identical reinstall-recovery semantics.
    private func loadDualStored<T: Codable>(_ type: T.Type, key: String) -> T? {
        let defaultsCopy = load(type, key: key)
        guard let keychainMirror else { return defaultsCopy }

        if let json = keychainMirror.retrieveSync(key: key) {
            do {
                let keychainCopy = try decoder.decode(type, from: Data(json.utf8))
                if defaultsCopy == nil {
                    // Reinstall recovery: the UserDefaults container was wiped
                    // but the Keychain copy survived — re-hydrate UserDefaults.
                    save(keychainCopy, key: key)
                }
                return keychainCopy
            } catch {
                TalariaLog.event("persistence: decode of \(type) (Keychain mirror) failed for key \(key): \(error)")
            }
        }

        if let defaultsCopy {
            // Upgrade path for values saved before the Keychain mirror
            // existed: back-fill the Keychain from the UserDefaults copy.
            mirrorToKeychain(defaultsCopy, key: key)
        }
        return defaultsCopy
    }

    private func saveDualStored<T: Codable>(_ value: T, key: String) {
        save(value, key: key)
        mirrorToKeychain(value, key: key)
    }

    private func mirrorToKeychain<T: Encodable>(_ value: T, key: String) {
        guard let keychainMirror,
              let data = try? encoder.encode(value),
              let json = String(data: data, encoding: .utf8) else { return }
        keychainMirror.storeSync(key: key, value: json)
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

    func loadPendingRunRecord() -> PendingRunRecord? {
        load(PendingRunRecord.self, key: Keys.pendingRunRecord)
    }

    func savePendingRunRecord(_ record: PendingRunRecord) {
        save(record, key: Keys.pendingRunRecord)
    }

    func clearPendingRunRecord() {
        defaults.removeObject(forKey: Keys.pendingRunRecord)
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

    // #277: the agent-file chip sidecar. A decode failure lands in `load` and
    // reads as "no records" — the chip is absent, exactly as it was before
    // this existed, and never a throw at session-open time.
    func loadAgentAttachmentSidecar() -> AgentAttachmentSidecar {
        load(AgentAttachmentSidecar.self, key: Keys.agentAttachmentSidecar) ?? AgentAttachmentSidecar()
    }

    func saveAgentAttachmentSidecar(_ sidecar: AgentAttachmentSidecar) {
        if sidecar.threads.isEmpty {
            defaults.removeObject(forKey: Keys.agentAttachmentSidecar)
        } else {
            save(sidecar, key: Keys.agentAttachmentSidecar)
        }
    }

    func clearAgentAttachmentSidecar() {
        defaults.removeObject(forKey: Keys.agentAttachmentSidecar)
    }

    // #330: the turn-receipt sidecar. Same tolerance posture as the chip
    // sidecar above — a decode failure reads as "no receipts", which is
    // exactly the pre-#330 behaviour, and never a throw at session-open time.
    func loadTurnReceiptSidecar() -> TurnReceiptSidecar {
        load(TurnReceiptSidecar.self, key: Keys.turnReceiptSidecar) ?? TurnReceiptSidecar()
    }

    func saveTurnReceiptSidecar(_ sidecar: TurnReceiptSidecar) {
        if sidecar.threads.isEmpty {
            defaults.removeObject(forKey: Keys.turnReceiptSidecar)
        } else {
            save(sidecar, key: Keys.turnReceiptSidecar)
        }
    }

    func clearTurnReceiptSidecar() {
        defaults.removeObject(forKey: Keys.turnReceiptSidecar)
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
