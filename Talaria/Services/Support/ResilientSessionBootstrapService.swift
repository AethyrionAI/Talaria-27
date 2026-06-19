import Foundation

@MainActor
final class ResilientSessionBootstrapService: SessionBootstrapServiceProtocol {
    private let primary: any SessionBootstrapServiceProtocol
    private let fallback: any SessionBootstrapServiceProtocol
    private let allowsFallback: @MainActor () -> Bool

    init(
        primary: any SessionBootstrapServiceProtocol,
        fallback: any SessionBootstrapServiceProtocol,
        allowsFallback: @escaping @MainActor () -> Bool = { true }
    ) {
        self.primary = primary
        self.fallback = fallback
        self.allowsFallback = allowsFallback
    }

    func registerDevice(_ request: DeviceRegistrationRequest) async throws -> SessionBootstrapResponse {
        do {
            return try await primary.registerDevice(request)
        } catch {
            guard allowsFallback() else { throw error }
            return try await fallback.registerDevice(request)
        }
    }

    func loadSession(accessToken: String?) async throws -> AppSessionState {
        do {
            return try await primary.loadSession(accessToken: accessToken)
        } catch {
            guard allowsFallback() else { throw error }
            return try await fallback.loadSession(accessToken: accessToken)
        }
    }

    func refreshAuth(refreshToken: String) async throws -> AuthTokens {
        do {
            return try await primary.refreshAuth(refreshToken: refreshToken)
        } catch {
            guard allowsFallback() else { throw error }
            return try await fallback.refreshAuth(refreshToken: refreshToken)
        }
    }

    func revokeCurrentSession(accessToken: String?) async throws {
        do {
            try await primary.revokeCurrentSession(accessToken: accessToken)
        } catch {
            guard allowsFallback() else { throw error }
            try await fallback.revokeCurrentSession(accessToken: accessToken)
        }
    }
}
