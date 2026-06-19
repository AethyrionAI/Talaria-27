import Foundation

@MainActor
protocol AppPersistenceStoreProtocol {
    func loadUserSettings() -> UserSettings?
    func saveUserSettings(_ settings: UserSettings)
    func loadSessionState() -> AppSessionState?
    func saveSessionState(_ state: AppSessionState)
    func clearSessionState()
    func loadInboxState() -> InboxLocalState
    func saveInboxState(_ state: InboxLocalState)
    func clearInboxState()
    func loadPairedRelayConfiguration() -> PairedRelayConfiguration?
    func savePairedRelayConfiguration(_ configuration: PairedRelayConfiguration)
    func clearPairedRelayConfiguration()
    func loadSensorOutboxState() -> SensorOutboxState
    func saveSensorOutboxState(_ state: SensorOutboxState)
    func clearSensorOutboxState()
    func loadConversationCache() -> Conversation?
    func saveConversationCache(_ conversation: Conversation)
    func clearConversationCache()
    func loadHealthQueryAnchorData(for identifier: String) -> Data?
    func saveHealthQueryAnchorData(_ data: Data?, for identifier: String)
    func clearHealthQueryAnchorData()
}
