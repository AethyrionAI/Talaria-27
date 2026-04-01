import Foundation

@MainActor
@Observable
final class PairingStore {
    var pairedRelayConfiguration: PairedRelayConfiguration?
    var isWorking = false
    var lastErrorMessage: String?
    var onPairingChanged: (@MainActor (Bool) async -> Void)?

    private let pairingService: any PairingServiceProtocol
    private let sessionStore: AppSessionStore
    private let persistence: any AppPersistenceStoreProtocol
    private let environmentProvider: @MainActor () -> AppEnvironment

    init(
        pairingService: any PairingServiceProtocol,
        sessionStore: AppSessionStore,
        persistence: any AppPersistenceStoreProtocol,
        environmentProvider: @escaping @MainActor () -> AppEnvironment
    ) {
        self.pairingService = pairingService
        self.sessionStore = sessionStore
        self.persistence = persistence
        self.environmentProvider = environmentProvider
        self.pairedRelayConfiguration = persistence.loadPairedRelayConfiguration()
    }

    var isPaired: Bool {
        pairedRelayConfiguration != nil
    }

    func normalizePairingCode(_ rawCode: String) throws -> String {
        try pairingService.normalizePairingCode(rawCode)
    }

    @discardableResult
    func pair(using rawSetupCode: String) async -> Bool {
        isWorking = true
        lastErrorMessage = nil
        defer { isWorking = false }

        do {
            let normalizedCode = try pairingService.normalizePairingCode(rawSetupCode)
            let request = DeviceRegistrationRequest.current(
                installationID: sessionStore.state.installationID,
                environment: environmentProvider()
            )
            let result = try await pairingService.redeemPairingCode(
                normalizedCode,
                request: request
            )

            persistence.savePairedRelayConfiguration(result.configuration)
            pairedRelayConfiguration = result.configuration
            lastErrorMessage = nil
            await sessionStore.applyPairedSession(state: result.state, tokens: result.tokens)
            await onPairingChanged?(true)
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    func disconnect() async {
        isWorking = true
        lastErrorMessage = nil
        defer { isWorking = false }

        await sessionStore.revokeCurrentSession()
        await clearLocalPairing(notify: true)
    }

    func clearLocalPairing(notify: Bool = true) async {
        persistence.clearPairedRelayConfiguration()
        pairedRelayConfiguration = nil
        lastErrorMessage = nil
        await sessionStore.clearSession()
        if notify {
            await onPairingChanged?(false)
        }
    }
}
