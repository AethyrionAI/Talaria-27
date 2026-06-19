import Foundation

@MainActor
protocol SessionBootstrapServiceProtocol {
    func registerDevice(_ request: DeviceRegistrationRequest) async throws -> SessionBootstrapResponse
    func loadSession(accessToken: String?) async throws -> AppSessionState
    func refreshAuth(refreshToken: String) async throws -> AuthTokens
    func revokeCurrentSession(accessToken: String?) async throws
}
