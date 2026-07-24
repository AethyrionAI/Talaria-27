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
    /// #146: THE record of this profile's push registration — the exact APNs
    /// token its relay last acked, nil when nothing is registered. #133 added
    /// it alongside a parallel `pushTokenRegistered` Bool, and two records of
    /// one fact drifted: a skip-on-exact-match kept the token while the Bool
    /// stayed false, so Diagnostics read TOKEN HELD · AWAITING RELAY forever
    /// against a live server-side registration. The Bool is now DERIVED (see
    /// below), so there is nothing left to diverge.
    ///
    /// Old persisted blobs carry only the Bool: they decode as nil (not
    /// registered) and the next `registerPushTokenIfNeeded` — which runs on
    /// every foreground — re-registers and records the token. Self-healing in
    /// one launch.
    var registeredPushToken: String?

    /// Whether this profile's relay holds a push registration. Derived, never
    /// stored: the only way to be registered is to have an acked token.
    var pushTokenRegistered: Bool { registeredPushToken != nil }

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
        self.registeredPushToken = registeredPushToken
    }
}
