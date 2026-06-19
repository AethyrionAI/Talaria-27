import Foundation

@MainActor
final class LiveSessionBootstrapService: SessionBootstrapServiceProtocol {
    private struct DeviceRegisterBody: Encodable {
        struct Device: Encodable {
            let platform: String
            let deviceName: String
            let appVersion: String
            let buildNumber: String
            let bundleId: String
            let installationId: UUID
            let deviceModel: String
            let systemVersion: String
        }

        struct Client: Encodable {
            let environment: String
        }

        let device: Device
        let client: Client
    }

    private struct DeviceRegisterResponse: Decodable {
        struct SessionData: Decodable {
            let connectionStatus: ConnectionStatus
            let isMockMode: Bool
            let backendEndpoint: String
            let lastSyncAt: Date?
        }

        struct AuthData: Decodable {
            let accessToken: String
            let refreshToken: String
            let expiresAt: Date
        }

        let deviceId: UUID
        let deviceRegistered: Bool
        let session: SessionData
        let auth: AuthData
    }

    private struct SessionResponse: Decodable {
        struct UserData: Decodable {
            let id: UUID
            let displayName: String
        }

        struct DeviceData: Decodable {
            let id: UUID
            let registered: Bool
        }

        struct SessionData: Decodable {
            let connectionStatus: ConnectionStatus
            let isMockMode: Bool
            let backendEndpoint: String
            let lastSyncAt: Date?
        }

        struct PushData: Decodable {
            let tokenRegistered: Bool
        }

        let user: UserData
        let device: DeviceData
        let session: SessionData
        let push: PushData
    }

    private struct RefreshBody: Encodable {
        let refreshToken: String
    }

    private struct RefreshResponse: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date
    }

    private struct EmptyBody: Encodable {}

    private struct RevokeResponse: Decodable {
        let revoked: Bool
    }

    private let apiClient: RelayAPIClient

    init(apiClient: RelayAPIClient) {
        self.apiClient = apiClient
    }

    func registerDevice(_ request: DeviceRegistrationRequest) async throws -> SessionBootstrapResponse {
        let body = DeviceRegisterBody(
            device: .init(
                platform: "ios",
                deviceName: request.deviceName,
                appVersion: request.appVersion,
                buildNumber: request.buildNumber,
                bundleId: request.bundleID,
                installationId: request.installationID,
                deviceModel: request.deviceModel,
                systemVersion: request.systemVersion
            ),
            client: .init(environment: request.environment.rawValue)
        )

        let response: DeviceRegisterResponse = try await apiClient.post(path: "device/register", body: body)

        return SessionBootstrapResponse(
            state: AppSessionState(
                deviceID: response.deviceId,
                installationID: request.installationID,
                deviceRegistered: response.deviceRegistered,
                connectionStatus: response.session.connectionStatus,
                syncStatus: .synced,
                isMockMode: response.session.isMockMode,
                backendEndpoint: response.session.backendEndpoint,
                lastSyncAt: response.session.lastSyncAt,
                pushTokenRegistered: false
            ),
            tokens: AuthTokens(
                accessToken: response.auth.accessToken,
                refreshToken: response.auth.refreshToken,
                expiresAt: response.auth.expiresAt
            )
        )
    }

    func loadSession(accessToken: String?) async throws -> AppSessionState {
        let response: SessionResponse = try await apiClient.get(path: "session", accessToken: accessToken)

        return AppSessionState(
            userID: response.user.id,
            displayName: response.user.displayName,
            deviceID: response.device.id,
            installationID: UUID(),
            deviceRegistered: response.device.registered,
            connectionStatus: response.session.connectionStatus,
            syncStatus: .synced,
            isMockMode: response.session.isMockMode,
            backendEndpoint: response.session.backendEndpoint,
            lastSyncAt: response.session.lastSyncAt,
            pushTokenRegistered: response.push.tokenRegistered
        )
    }

    func refreshAuth(refreshToken: String) async throws -> AuthTokens {
        let response: RefreshResponse = try await apiClient.post(
            path: "auth/refresh",
            body: RefreshBody(refreshToken: refreshToken)
        )

        return AuthTokens(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: response.expiresAt
        )
    }

    func revokeCurrentSession(accessToken: String?) async throws {
        let _: RevokeResponse = try await apiClient.post(
            path: "auth/revoke",
            body: EmptyBody(),
            accessToken: accessToken
        )
    }
}
