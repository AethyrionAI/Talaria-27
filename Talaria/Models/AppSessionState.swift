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
        pushTokenRegistered: Bool = false
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
    }
}
