import Foundation

@MainActor
final class LiveHermesHostService: HermesHostServiceProtocol {
    private struct EmptyBody: Encodable {}

    private struct EnrollmentResponse: Decodable {
        let setupCode: String
        let expiresAt: Date?
        let relayHost: String
    }

    private struct CurrentHostResponse: Decodable {
        let host: RelayHost?
    }

    private struct RelayHost: Decodable {
        let id: UUID
        let displayName: String?
        let hostname: String?
        let platform: String?
        let connectorVersion: String?
        let hermesCommand: String?
        let hermesVersion: String?
        let hermesModel: String?
        let lastSeenAt: Date?
        let lastConnectedAt: Date?
        let isOnline: Bool
    }

    private let apiClient: RelayAPIClient
    private let accessTokenRefresher: @MainActor () async -> String?

    init(
        apiClient: RelayAPIClient,
        accessTokenRefresher: @escaping @MainActor () async -> String? = { nil }
    ) {
        self.apiClient = apiClient
        self.accessTokenRefresher = accessTokenRefresher
    }

    func fetchCurrentHost(accessToken: String?) async throws -> HermesHostStatus? {
        let response: CurrentHostResponse = try await performAuthorizedRequest(initialAccessToken: accessToken) { token in
            try await self.apiClient.get(
                path: "hosts/current",
                accessToken: token
            )
        }
        guard let host = response.host else { return nil }
        return mapHost(host)
    }

    func createEnrollmentCode(accessToken: String?) async throws -> HostEnrollmentCode {
        let response: EnrollmentResponse = try await performAuthorizedRequest(initialAccessToken: accessToken) { token in
            try await self.apiClient.post(
                path: "hosts/enrollment-codes",
                body: EmptyBody(),
                accessToken: token
            )
        }
        return HostEnrollmentCode(
            setupCode: response.setupCode,
            expiresAt: response.expiresAt,
            relayHost: response.relayHost
        )
    }

    func revokeCurrentHost(accessToken: String?) async throws {
        let _: EmptyResponse = try await performAuthorizedRequest(initialAccessToken: accessToken) { token in
            try await self.apiClient.post(
                path: "hosts/current/revoke",
                body: EmptyBody(),
                accessToken: token
            )
        }
    }

    private func mapHost(_ host: RelayHost) -> HermesHostStatus {
        HermesHostStatus(
            id: host.id,
            displayName: host.displayName,
            hostname: host.hostname,
            platform: host.platform,
            connectorVersion: host.connectorVersion,
            hermesCommand: host.hermesCommand,
            hermesVersion: host.hermesVersion,
            hermesModel: host.hermesModel,
            lastSeenAt: host.lastSeenAt,
            lastConnectedAt: host.lastConnectedAt,
            isOnline: host.isOnline
        )
    }

    private func performAuthorizedRequest<T>(
        initialAccessToken: String?,
        _ operation: @escaping @MainActor (_ accessToken: String?) async throws -> T
    ) async throws -> T {
        do {
            return try await operation(initialAccessToken)
        } catch RelayAPIClient.ClientError.unauthorized {
            guard let refreshedToken = await accessTokenRefresher(), !refreshedToken.isEmpty else {
                throw RelayAPIClient.ClientError.unauthorized("Expired or invalid access token.")
            }
            return try await operation(refreshedToken)
        }
    }
}

private struct EmptyResponse: Decodable {}
