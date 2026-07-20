import Foundation

struct AppSessionState: Codable, Hashable, Sendable {
    var userID: UUID?
    var displayName: String?
    var deviceID: UUID?
    var installationID: UUID
    var deviceRegistered: Bool
    var connectionStatus: ConnectionStatus
    var syncStatus: SyncStatus
    var isMockMode: Bool
    var backendEndpoint: String
    var lastSyncAt: Date?
    var pushTokenRegistered: Bool
    /// #133: the exact APNs token this profile's relay last acked — the
    /// dormant-path guard compares against it so re-registration only fires
    /// on a real token change, mirroring the active path's
    /// `currentPushToken` check. Optional: absent on pre-#133 states.
    var registeredPushToken: String?

    init(
        userID: UUID? = nil,
        displayName: String? = nil,
        deviceID: UUID? = nil,
        installationID: UUID = UUID(),
        deviceRegistered: Bool = false,
        connectionStatus: ConnectionStatus = .disconnected,
        syncStatus: SyncStatus = .offline,
        isMockMode: Bool = true,
        backendEndpoint: String = "",
        lastSyncAt: Date? = nil,
        pushTokenRegistered: Bool = false,
        registeredPushToken: String? = nil
    ) {
        self.userID = userID
        self.displayName = displayName
        self.deviceID = deviceID
        self.installationID = installationID
        self.deviceRegistered = deviceRegistered
        self.connectionStatus = connectionStatus
        self.syncStatus = syncStatus
        self.isMockMode = isMockMode
        self.backendEndpoint = backendEndpoint
        self.lastSyncAt = lastSyncAt
        self.pushTokenRegistered = pushTokenRegistered
        self.registeredPushToken = registeredPushToken
    }
}
