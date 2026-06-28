import Foundation

@MainActor
@Observable
final class PairingStore {
    private static let onboardingKey = "hermes.needsPermissionsOnboarding"
    /// Keychain account under which the pairing config is mirrored (#41). The
    /// Keychain survives a same-identity reinstall (which wipes UserDefaults), so
    /// this copy lets the app recover pairing instead of forcing a re-pair.
    private static let pairingConfigKeychainKey = "hermes.pairedRelayConfiguration"
    private static let keychainEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private static let keychainDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    var pairedRelayConfiguration: PairedRelayConfiguration?
    var isWorking = false
    var lastErrorMessage: String?
    var needsPermissionsOnboarding = false
    var onPairingChanged: (@MainActor (Bool) async -> Void)?

    private let pairingService: any PairingServiceProtocol
    private let sessionStore: AppSessionStore
    private let persistence: any AppPersistenceStoreProtocol
    private let environmentProvider: @MainActor () -> AppEnvironment
    private let relayBaseURLProvider: @MainActor () -> String?
    private let secureStore: (any SecureStoreProtocol)?

    init(
        pairingService: any PairingServiceProtocol,
        sessionStore: AppSessionStore,
        persistence: any AppPersistenceStoreProtocol,
        environmentProvider: @escaping @MainActor () -> AppEnvironment,
        relayBaseURLProvider: @escaping @MainActor () -> String?,
        secureStore: (any SecureStoreProtocol)? = nil
    ) {
        self.pairingService = pairingService
        self.sessionStore = sessionStore
        self.persistence = persistence
        self.environmentProvider = environmentProvider
        self.relayBaseURLProvider = relayBaseURLProvider
        self.secureStore = secureStore
        self.pairedRelayConfiguration = persistence.loadPairedRelayConfiguration()
        self.needsPermissionsOnboarding = UserDefaults.standard.bool(forKey: Self.onboardingKey)
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
            guard let relayBaseURLString = RelayConfiguration.normalizeBaseURL(relayBaseURLProvider()) else {
                lastErrorMessage = "Enter a valid relay URL ending with /v1 before pairing."
                return false
            }
            let request = DeviceRegistrationRequest.current(
                installationID: sessionStore.state.installationID,
                environment: environmentProvider(),
                relayBaseURLString: relayBaseURLString
            )
            let result = try await pairingService.redeemPairingCode(
                normalizedCode,
                request: request
            )

            persistence.savePairedRelayConfiguration(result.configuration)
            await storeConfigurationInKeychain(result.configuration)
            pairedRelayConfiguration = result.configuration
            lastErrorMessage = nil
            setNeedsPermissionsOnboarding(true)
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

    func completePermissionsOnboarding() {
        setNeedsPermissionsOnboarding(false)
    }

    func clearLocalPairing(notify: Bool = true) async {
        persistence.clearPairedRelayConfiguration()
        await secureStore?.delete(key: Self.pairingConfigKeychainKey)
        pairedRelayConfiguration = nil
        lastErrorMessage = nil
        setNeedsPermissionsOnboarding(false)
        await sessionStore.clearSession()
        if notify {
            await onPairingChanged?(false)
        }
    }

    /// Reconcile pairing state against the Keychain mirror at launch (#41).
    /// UserDefaults (the primary store for the config) is wiped by a clean
    /// reinstall, but the Keychain survives a same-identity reinstall — so:
    ///  • if UserDefaults still has the config, back it up to the Keychain
    ///    (covers users paired before this mirror existed);
    ///  • if UserDefaults lost it but the Keychain kept it, restore the config
    ///    and re-hydrate UserDefaults, recovering pairing with no re-pair.
    /// A signing-identity change rotates the Keychain access group too, so
    /// neither copy survives that case — a re-pair is unavoidable there.
    func hydratePairingFromKeychainIfNeeded() async {
        if let configuration = pairedRelayConfiguration {
            await storeConfigurationInKeychain(configuration)
            return
        }
        guard
            let secureStore,
            let stored = await secureStore.retrieve(key: Self.pairingConfigKeychainKey),
            let data = stored.data(using: .utf8),
            let configuration = try? Self.keychainDecoder.decode(PairedRelayConfiguration.self, from: data)
        else {
            return
        }
        persistence.savePairedRelayConfiguration(configuration)
        pairedRelayConfiguration = configuration
        TalariaLog.event("PairingStore: recovered pairing from Keychain after UserDefaults wipe")
    }

    private func storeConfigurationInKeychain(_ configuration: PairedRelayConfiguration) async {
        guard let secureStore else { return }
        guard
            let data = try? Self.keychainEncoder.encode(configuration),
            let json = String(data: data, encoding: .utf8)
        else {
            return
        }
        await secureStore.store(key: Self.pairingConfigKeychainKey, value: json)
    }

    private func setNeedsPermissionsOnboarding(_ value: Bool) {
        needsPermissionsOnboarding = value
        UserDefaults.standard.set(value, forKey: Self.onboardingKey)
    }
}
