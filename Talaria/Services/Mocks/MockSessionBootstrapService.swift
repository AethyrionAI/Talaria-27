import Foundation

@MainActor
final class MockSessionBootstrapService: SessionBootstrapServiceProtocol {
    private var state = AppSessionState(
        displayName: DemoData.sampleUserSettings.userName,
        deviceRegistered: true,
        connectionStatus: .connected,
        syncStatus: .synced,
        isMockMode: true,
        backendEndpoint: DemoData.sampleUserSettings.relayConfiguration.activeBaseURLString ?? "",
        lastSyncAt: .now,
        pushTokenRegistered: false
    )

    func registerDevice(_ request: DeviceRegistrationRequest) async throws -> SessionBootstrapResponse {
        state.installationID = request.installationID
        state.displayName = DemoData.sampleUserSettings.userName
        state.deviceID = UUID()
        state.deviceRegistered = true
        state.connectionStatus = .connected
        state.syncStatus = .synced
        state.backendEndpoint = request.relayBaseURLString
        state.lastSyncAt = .now

        return SessionBootstrapResponse(
            state: state,
            tokens: AuthTokens(
                accessToken: "mock-access-token",
                refreshToken: "mock-refresh-token",
                expiresAt: .now.addingTimeInterval(3600)
            )
        )
    }

    func loadSession(accessToken: String?) async throws -> AppSessionState {
        state.lastSyncAt = .now
        return state
    }

    func refreshAuth(refreshToken: String) async throws -> AuthTokens {
        AuthTokens(
            accessToken: "mock-access-token-\(UUID().uuidString)",
            refreshToken: "mock-refresh-token-\(UUID().uuidString)",
            expiresAt: .now.addingTimeInterval(3600)
        )
    }

    func revokeCurrentSession(accessToken: String?) async throws {}
}
