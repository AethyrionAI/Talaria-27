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

        // A misconfigured relay can report its own `backendEndpoint` as a
        // link-local IPv6 (fe80::…) even though the device just reached it at a
        // routable address to redeem the code. Link-local addresses only route on
        // a single link and need an interface scope, so trusting that value yields
        // "No route to host" on every later request. Keep the address that worked.
        let resolvedEndpoint = Self.routableEndpoint(
            reported: response.session.backendEndpoint,
            fallback: request.relayBaseURLString
        )

        return PairingRedeemResult(
            configuration: PairedRelayConfiguration(
                baseURLString: resolvedEndpoint,
                hostDisplayName: URL(string: resolvedEndpoint)?.host ?? resolvedEndpoint,
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
                backendEndpoint: resolvedEndpoint,
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

    // MARK: - Endpoint resolution

    /// Returns the relay's reported endpoint when it's routable, otherwise the
    /// fallback address the device already used successfully to redeem the code.
    private static func routableEndpoint(reported: String, fallback: String) -> String {
        guard let host = URL(string: reported)?.host, !host.isEmpty else { return fallback }
        return isUnroutableHost(host) ? fallback : reported
    }

    /// True for hosts a phone can't reach across the network: IPv6 link-local
    /// (fe80::/10), IPv4 link-local (169.254/16), and the unspecified address.
    private static func isUnroutableHost(_ host: String) -> Bool {
        let normalized = host
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .lowercased()
        if normalized.hasPrefix("fe80:") { return true }
        if normalized.hasPrefix("169.254.") { return true }
        if normalized == "::" || normalized == "0.0.0.0" { return true }
        return false
    }
}
