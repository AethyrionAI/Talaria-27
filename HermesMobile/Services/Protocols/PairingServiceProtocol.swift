import Foundation

@MainActor
protocol PairingServiceProtocol {
    func normalizePairingCode(_ rawCode: String) throws -> String
    func redeemPairingCode(
        _ normalizedCode: String,
        request: DeviceRegistrationRequest
    ) async throws -> PairingRedeemResult
}
