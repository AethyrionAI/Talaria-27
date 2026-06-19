import Foundation

@MainActor
protocol HermesHostServiceProtocol {
    func fetchCurrentHost(accessToken: String?) async throws -> HermesHostStatus?
    func createEnrollmentCode(accessToken: String?) async throws -> HostEnrollmentCode
    func revokeCurrentHost(accessToken: String?) async throws
}
