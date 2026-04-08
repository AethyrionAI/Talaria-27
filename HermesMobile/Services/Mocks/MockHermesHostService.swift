import Foundation

@MainActor
final class MockHermesHostService: HermesHostServiceProtocol {
    var currentHost: HermesHostStatus? = HermesHostStatus(
        id: UUID(),
        displayName: "Mock Hermes Host",
        hostname: "mock-hermes.local",
        platform: "macos",
        connectorVersion: "0.1.0",
        hermesCommand: "hermes",
        hermesVersion: "hermes mock",
        hermesModel: "gpt-5.4-mini",
        lastSeenAt: .now,
        lastConnectedAt: .now,
        isOnline: true
    )

    func fetchCurrentHost(accessToken: String?) async throws -> HermesHostStatus? {
        currentHost
    }

    func createEnrollmentCode(accessToken: String?) async throws -> HostEnrollmentCode {
        HostEnrollmentCode(
            setupCode: "HC1:mock-host-setup-code",
            expiresAt: .now.addingTimeInterval(900),
            relayHost: "relay.example.test"
        )
    }

    func revokeCurrentHost(accessToken: String?) async throws {
        currentHost = nil
    }
}
