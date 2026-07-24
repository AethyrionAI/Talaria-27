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
        let mintedUserID = UUID()
        return PairingRedeemResult(
            configuration: PairedRelayConfiguration(
                baseURLString: request.relayBaseURLString,
                hostDisplayName: URL(string: request.relayBaseURLString)?.host ?? request.relayBaseURLString,
                pairedAt: .now,
                relayUserID: mintedUserID
            ),
            state: AppSessionState(
                userID: mintedUserID,
                displayName: "Morgan",
                deviceID: UUID(),
                installationID: request.installationID,
                deviceRegistered: true,
                connectionStatus: .connected,
                syncStatus: .synced,
                isMockMode: false,
                backendEndpoint: request.relayBaseURLString,
                lastSyncAt: .now,
                registeredPushToken: nil
            ),
            tokens: AuthTokens(
                accessToken: "mock-paired-access-token-\(normalizedCode)",
                refreshToken: "mock-paired-refresh-token-\(normalizedCode)",
                expiresAt: .distantFuture
            )
        )
    }
}
