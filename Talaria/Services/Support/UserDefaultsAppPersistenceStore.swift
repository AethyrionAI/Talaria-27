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
        static let healthAnchorPrefix = "hermes.healthAnchor."
    }

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

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

    func loadPairedRelayConfiguration() -> PairedRelayConfiguration? {
        load(PairedRelayConfiguration.self, key: Keys.pairedRelayConfiguration)
    }

    func savePairedRelayConfiguration(_ configuration: PairedRelayConfiguration) {
        save(configuration, key: Keys.pairedRelayConfiguration)
    }

    func clearPairedRelayConfiguration() {
        defaults.removeObject(forKey: Keys.pairedRelayConfiguration)
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
        return try? decoder.decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
