import Foundation

@MainActor
final class MockPairingService: PairingServiceProtocol {
    func normalizePairingCode(_ rawCode: String) throws -> String {
        try PhonePairingCode.normalize(rawCode)
    }

    func redeemPairingCode(
        _ normalizedCode: String,
        request: DeviceRegistrationRequest
    ) async throws -> PairingRedeemResult {
        let normalizedCode = try normalizePairingCode(normalizedCode)
        return PairingRedeemResult(
            configuration: PairedRelayConfiguration(
                baseURLString: request.environment.baseURLString,
                hostDisplayName: URL(string: request.environment.baseURLString)?.host ?? request.environment.baseURLString,
                pairedAt: .now
            ),
            state: AppSessionState(
                userID: UUID(),
                displayName: "Morgan",
                deviceID: UUID(),
                installationID: request.installationID,
                deviceRegistered: true,
                connectionStatus: .connected,
                syncStatus: .synced,
                isMockMode: false,
                backendEndpoint: request.environment.baseURLString,
                lastSyncAt: .now,
                pushTokenRegistered: false
            ),
            tokens: AuthTokens(
                accessToken: "mock-paired-access-token-\(normalizedCode)",
                refreshToken: "mock-paired-refresh-token-\(normalizedCode)",
                expiresAt: .distantFuture
            )
        )
    }
}
