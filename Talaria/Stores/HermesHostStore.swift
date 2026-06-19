import Foundation

enum HermesHostConnectionState: Equatable, Sendable {
    case online
    case offline
    case unreachable
    case notConnected
}

@MainActor
@Observable
final class HermesHostStore {
    var currentHost: HermesHostStatus?
    var activeEnrollmentCode: HostEnrollmentCode?
    var isLoading = false
    var isWorking = false
    var lastErrorMessage: String?
    var onHostChanged: (@MainActor () -> Void)?

    private let hostService: any HermesHostServiceProtocol
    private let accessTokenProvider: @MainActor () async -> String?

    init(
        hostService: any HermesHostServiceProtocol,
        accessTokenProvider: @escaping @MainActor () async -> String?
    ) {
        self.hostService = hostService
        self.accessTokenProvider = accessTokenProvider
    }

    var isHostOnline: Bool {
        currentHost?.isOnline == true
    }

    var connectionState: HermesHostConnectionState {
        if currentHost?.isOnline == true {
            return .online
        }

        if currentHost != nil {
            return lastErrorMessage == nil ? .offline : .unreachable
        }

        if lastErrorMessage != nil {
            return .unreachable
        }

        return .notConnected
    }

    func refresh() async {
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            currentHost = try await hostService.fetchCurrentHost(accessToken: await accessTokenProvider())
            lastErrorMessage = nil
            onHostChanged?()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func generateEnrollmentCode() async {
        guard !isWorking else { return }

        isWorking = true
        defer { isWorking = false }

        do {
            activeEnrollmentCode = try await hostService.createEnrollmentCode(accessToken: await accessTokenProvider())
            currentHost = try await hostService.fetchCurrentHost(accessToken: await accessTokenProvider())
            lastErrorMessage = nil
            onHostChanged?()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func revokeCurrentHost() async {
        guard !isWorking else { return }

        isWorking = true
        defer { isWorking = false }

        do {
            try await hostService.revokeCurrentHost(accessToken: await accessTokenProvider())
            currentHost = nil
            activeEnrollmentCode = nil
            lastErrorMessage = nil
            onHostChanged?()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func reset() {
        currentHost = nil
        activeEnrollmentCode = nil
        isLoading = false
        isWorking = false
        lastErrorMessage = nil
        onHostChanged?()
    }
}
