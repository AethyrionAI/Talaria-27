import Foundation

/// **#309 Lane C left this file standing on purpose — it is LANE B's to
/// delete** (relay row 6, `POST phone-pairing/redeem`; design doc §5a), along
/// with `PairingStore`, `ConnectHermesScreen` and `PhonePairingCode`.
///
/// What Lane C had to do here was keep it COMPILING after `RelayAPIClient` was
/// deleted. The one call it made is inlined below, byte-for-byte in behaviour:
/// the same `{data: …}` envelope unwrap, the same lenient date decoding, the
/// same error mapping. No stub, no honest-failure rewrite — that would change
/// what the pairing screen does, and this lane does not own that screen.
@MainActor
final class LivePairingService: PairingServiceProtocol {
    /// The relay's response envelopes, at type scope because Swift forbids
    /// nesting a type inside a generic function.
    private struct RelayEnvelope<Payload: Decodable>: Decodable { let data: Payload }
    private struct RelayErrorEnvelope: Decodable {
        struct Payload: Decodable { let message: String }
        let error: Payload
    }
    private struct RelayFastAPIErrorEnvelope: Decodable { let detail: String }

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
        let body = PairingRedeemBody(
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
        let response: PairingRedeemResponse = try await Self.postRedeem(
            baseURLString: request.relayBaseURLString,
            body: body
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
                pairedAt: .now,
                relayUserID: response.user.id
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
                lastSyncAt: response.session.lastSyncAt
            ),
            tokens: AuthTokens(
                accessToken: response.auth.accessToken,
                refreshToken: response.auth.refreshToken,
                expiresAt: response.auth.expiresAt
            )
        )
    }

    // MARK: - The one relay request left in the app (#309 Lane C)

    /// `POST {relay}/phone-pairing/redeem`, inlined from the deleted
    /// `RelayAPIClient` with its behaviour intact: JSON in, the relay's
    /// `{"data": …}` envelope unwrapped, `RelayCoders`' lenient ISO dates, and
    /// the same status → `APIClientError` mapping (401 ⇒ `.unauthorized`,
    /// everything else ⇒ `.requestFailed`, error text preferred from the
    /// relay's own `{"error":{"message"}}` or FastAPI's `{"detail"}` envelope).
    ///
    /// The only intentional simplification: `payloadRejected` is gone with the
    /// enum case, so 400/422 now maps to `.requestFailed` here. Nothing ever
    /// caught the distinction on this path — it existed for the #24a sensor
    /// uploaders, whose pipeline #352 deleted.
    private static func postRedeem<T: Decodable>(
        baseURLString: String,
        body: some Encodable
    ) async throws -> T {
        let trimmedBase = baseURLString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(trimmedBase)/phone-pairing/redeem") else {
            throw APIClientError.invalidURL(trimmedBase)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try RelayCoders.makeEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.requestFailed("Relay returned an invalid response.")
        }

        let decoder = RelayCoders.makeDecoder()
        guard (200 ..< 300).contains(http.statusCode) else {
            let message: String
            if let envelope = try? decoder.decode(RelayErrorEnvelope.self, from: data) {
                message = envelope.error.message
            } else if let envelope = try? decoder.decode(RelayFastAPIErrorEnvelope.self, from: data) {
                message = envelope.detail
            } else {
                message = "Relay request failed with status \(http.statusCode)."
            }
            throw http.statusCode == 401
                ? APIClientError.unauthorized(message)
                : APIClientError.requestFailed(message)
        }

        return try decoder.decode(RelayEnvelope<T>.self, from: data).data
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
