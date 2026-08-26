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

    func fetchCurrentHost() async throws -> HermesHostStatus? {
        currentHost
    }
}
