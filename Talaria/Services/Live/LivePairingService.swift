import Foundation

@MainActor
final class LivePairingService: PairingServiceProtocol {
    private struct PairingRedeemBody: Encodable {
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

        let code: String
        let device: Device
        let client: Client
    }

    private struct PairingRedeemResponse: Decodable {
        struct UserData: Decodable {
            let id: UUID
            let displayName: String
        }

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

        let user: UserData
        let deviceId: UUID
        let deviceRegistered: Bool
        let session: SessionData
        let auth: AuthData
    }

    func normalizePairingCode(_ rawCode: String) throws -> String {
        try PhonePairingCode.normalize(rawCode)
    }

    func redeemPairingCode(
        _ normalizedCode: String,
        request: DeviceRegistrationRequest
    ) async throws -> PairingRedeemResult {
        let apiClient = RelayAPIClient(baseURLProvider: { request.relayBaseURLString })
        let response: PairingRedeemResponse = try await apiClient.post(
            path: "phone-pairing/redeem",
            body: PairingRedeemBody(
                code: normalizedCode,
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
        )

        return PairingRedeemResult(
            configuration: PairedRelayConfiguration(
                baseURLString: response.session.backendEndpoint,
                hostDisplayName: URL(string: response.session.backendEndpoint)?.host ?? response.session.backendEndpoint,
                pairedAt: .now
            ),
            state: AppSessionState(
                userID: response.user.id,
                displayName: response.user.displayName,
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
}
