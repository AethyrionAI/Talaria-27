import Foundation
import os

private let sessionLog = Logger(subsystem: "org.aethyrion.talaria", category: "AppSessionStore")

@MainActor
@Observable
final class AppSessionStore {

    /// How an on-demand access-token refresh resolved (#15). Distinguishes
    /// "retry the request with the fresh token" from "this credential set is
    /// dead and needs recovery" — the old `Void` return collapsed both into
    /// silence, so 401 handlers retried with the same stale token that had
    /// just been rejected.
    enum TokenRefreshOutcome: Equatable {
        /// New tokens were minted and persisted.
        case refreshed
        /// No refresh token in the secure store — nothing to refresh with.
        case missingRefreshToken
        /// The relay examined the refresh token and refused it; retrying the
        /// same token can never succeed.
        case rejected
        /// Network or server failure — the refresh token may still be good.
        case transientFailure
    }

    var state: AppSessionState {
        didSet { persistence.saveSessionState(state, profileScope: credentialScope) }
    }
    var isBootstrapping = false
    var lastErrorMessage: String?

    /// Single-flight per credential scope (Lane M): a dormant-profile switch
    /// mid-refresh must neither coalesce onto the old profile's round trip
    /// nor clobber its bookkeeping.
    private var tokenRefreshTasks: [String: Task<TokenRefreshOutcome, Never>] = [:]
    private var sessionRecoveryTask: Task<Bool, Never>?
    private var lastSessionRecoveryAttemptAt: Date?
    /// Floor between silent re-registration attempts so a relay that keeps
    /// rejecting fresh credentials can't be hammered once per failed request.
    private static let sessionRecoveryRetryInterval: TimeInterval = 60

    private let bootstrapService: any SessionBootstrapServiceProtocol
    private let syncCoordinator: any SyncCoordinatorProtocol
    private let secureStore: any SecureStoreProtocol
    private let persistence: any AppPersistenceStoreProtocol
    private let notificationService: any NotificationServiceProtocol
    private let environmentProvider: @MainActor () -> AppEnvironment
    /// Which backend profile's credential slot this store reads/writes
    /// (Lane M): the ACTIVE profile's `credentialScopeID`. The default (nil)
    /// resolves the legacy pre-profile keys — the migrated first profile's
    /// slot, and the exact pre-Lane-M behavior for tests that construct the
    /// store without profiles.
    private let credentialScopeProvider: @MainActor () -> UUID?

    /// The scope every token/state access resolves against, read live so a
    /// profile switch redirects the store without reconstruction.
    private var credentialScope: UUID? { credentialScopeProvider() }

    init(
        bootstrapService: any SessionBootstrapServiceProtocol,
        syncCoordinator: any SyncCoordinatorProtocol,
        secureStore: any SecureStoreProtocol,
        persistence: any AppPersistenceStoreProtocol,
        notificationService: any NotificationServiceProtocol,
        environmentProvider: @escaping @MainActor () -> AppEnvironment,
        credentialScopeProvider: @escaping @MainActor () -> UUID? = { nil }
    ) {
        self.bootstrapService = bootstrapService
        self.syncCoordinator = syncCoordinator
        self.secureStore = secureStore
        self.persistence = persistence
        self.notificationService = notificationService
        self.environmentProvider = environmentProvider
        self.credentialScopeProvider = credentialScopeProvider
        self.state = persistence.loadSessionState(profileScope: credentialScopeProvider()) ?? AppSessionState()
    }

    func bootstrap(forceRegistration: Bool = false) async {
        guard !isBootstrapping else { return }

        isBootstrapping = true
        lastErrorMessage = nil
        state.connectionStatus = .connecting
        state.syncStatus = .syncing

        defer { isBootstrapping = false }

        let request = makeRegistrationRequest()
        let accessTokenBeforeBootstrap = await currentAccessToken()
        let needsRegistration =
            forceRegistration
            || !state.deviceRegistered
            || state.deviceID == nil
            || accessTokenBeforeBootstrap == nil

        do {
            if needsRegistration {
                let response = try await bootstrapService.registerDevice(request)
                await applySessionState(response.state, tokens: response.tokens)
            }

            try await loadAndApplySessionState(installationID: request.installationID)
        } catch {
            // #136: cancellation is the app superseding this bootstrap
            // (re-pair / unpair / profile switch mid-launch) — bail before
            // the recovery ladder burns doomed round trips or smears error
            // state over the canceller's reset.
            if error is CancellationError { return }
            if await attemptRefreshAndReload(installationID: request.installationID) {
                return
            }
            // #15: launch-time self-heal. When the refresh path couldn't save
            // the session (refresh token gone or rejected) and this pass
            // didn't already try registering, a silent re-registration can
            // still mint fresh credentials for this known installation.
            if !needsRegistration, await recoverSessionByReRegistering() {
                return
            }

            lastErrorMessage = error.localizedDescription
            state.connectionStatus = .error
            state.syncStatus = .error
        }
    }

    func refreshSession() async {
        await syncCoordinator.sync()
        state.syncStatus = .syncing
        await bootstrap(forceRegistration: false)
    }

    func currentAccessToken() async -> String? {
        await secureStore.retrieve(key: BackendProfileScopedKeys.accessToken(credentialScope))
    }

    func currentRefreshToken() async -> String? {
        await secureStore.retrieve(key: BackendProfileScopedKeys.refreshToken(credentialScope))
    }

    /// Single-flight: concurrent 401s from talk, sensors, and the host
    /// service coalesce onto one relay round trip instead of racing the
    /// rotation (the loser's refresh would present an already-rotated token).
    /// Keyed by credential scope (Lane M) so a profile switch mid-refresh
    /// can't coalesce two profiles onto one rotation.
    @discardableResult
    func refreshAccessTokenIfNeeded() async -> TokenRefreshOutcome {
        let scope = credentialScope
        let key = scope?.uuidString ?? "legacy"
        if let running = tokenRefreshTasks[key] {
            return await running.value
        }
        let task = Task { await performTokenRefresh(scope: scope) }
        tokenRefreshTasks[key] = task
        let outcome = await task.value
        tokenRefreshTasks[key] = nil
        return outcome
    }

    /// The scope is CAPTURED at entry: refresh tokens rotate server-side, so
    /// the freshly minted pair must land in the slot of the profile that
    /// minted it even if the active profile flips mid-flight — writing it
    /// under the new profile's keys would strand the old profile on a dead
    /// refresh token.
    private func performTokenRefresh(scope: UUID?) async -> TokenRefreshOutcome {
        guard let refreshToken = await secureStore.retrieve(key: BackendProfileScopedKeys.refreshToken(scope)) else {
            return .missingRefreshToken
        }

        do {
            let tokens = try await bootstrapService.refreshAuth(refreshToken: refreshToken)
            await secureStore.store(key: BackendProfileScopedKeys.accessToken(scope), value: tokens.accessToken)
            await secureStore.store(key: BackendProfileScopedKeys.refreshToken(scope), value: tokens.refreshToken)
            return .refreshed
        } catch let error as RelayAPIClient.ClientError {
            lastErrorMessage = error.localizedDescription
            switch error {
            case .unauthorized, .payloadRejected:
                sessionLog.error("token refresh rejected by relay — credential set is dead: \(error.localizedDescription, privacy: .public)")
                return .rejected
            case .invalidURL, .requestFailed:
                return .transientFailure
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            return .transientFailure
        }
    }

    /// Last-resort self-heal for a dead credential set (#15): re-register
    /// this installation over the unauthenticated register route. The relay
    /// preserves the device→user binding server-side, so a previously paired
    /// device gets fresh tokens for the same user without a manual re-pair.
    /// Callers must re-validate identity afterwards
    /// (`PairingStore.validateRestoredIdentity()`).
    func recoverSessionByReRegistering() async -> Bool {
        if let sessionRecoveryTask {
            return await sessionRecoveryTask.value
        }
        // A never-registered installation has no identity to recover — it
        // must go through pairing.
        guard state.deviceRegistered else { return false }
        if let lastSessionRecoveryAttemptAt,
           Date.now.timeIntervalSince(lastSessionRecoveryAttemptAt) < Self.sessionRecoveryRetryInterval {
            return false
        }
        let task = Task { await performSessionRecovery() }
        sessionRecoveryTask = task
        let recovered = await task.value
        sessionRecoveryTask = nil
        return recovered
    }

    private func performSessionRecovery() async -> Bool {
        lastSessionRecoveryAttemptAt = .now
        let request = makeRegistrationRequest()
        sessionLog.notice("attempting silent re-registration to recover a dead relay session (#15)")
        do {
            let response = try await bootstrapService.registerDevice(request)
            await applySessionState(response.state, tokens: response.tokens)
            try await loadAndApplySessionState(installationID: request.installationID)
            sessionLog.notice("silent re-registration recovered the relay session")
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            sessionLog.error("silent re-registration failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func applyPairedSession(state: AppSessionState, tokens: AuthTokens) async {
        lastErrorMessage = nil
        await applySessionState(state, tokens: tokens)
    }

    /// Lane M (M-6): re-reads the persisted session for the CURRENT
    /// credential scope — call immediately after the active profile changes,
    /// before anything else touches `state` (its didSet persists against the
    /// live scope). A profile with no persisted session starts fresh,
    /// retaining the installation id (one app install, many relays).
    func rebindToCurrentScope() {
        lastErrorMessage = nil
        isBootstrapping = false
        if let persisted = persistence.loadSessionState(profileScope: credentialScope) {
            state = persisted
        } else {
            state = AppSessionState(installationID: state.installationID)
        }
    }

    /// Explicit-scope variant (Lane M): adopts a freshly paired session into
    /// a NAMED profile's credential slot. When the target is the current
    /// scope this is exactly `applyPairedSession`; for a non-active profile
    /// the tokens and state land in that profile's slot without disturbing
    /// the in-memory session the active profile is running on.
    func applyPairedSession(state pairedState: AppSessionState, tokens: AuthTokens, credentialScope scope: UUID?) async {
        guard scope != credentialScope else {
            await applyPairedSession(state: pairedState, tokens: tokens)
            return
        }
        await secureStore.store(key: BackendProfileScopedKeys.accessToken(scope), value: tokens.accessToken)
        await secureStore.store(key: BackendProfileScopedKeys.refreshToken(scope), value: tokens.refreshToken)
        persistence.saveSessionState(pairedState, profileScope: scope)
    }

    func revokeCurrentSession() async {
        do {
            try await bootstrapService.revokeCurrentSession(accessToken: await currentAccessToken())
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func clearSession() async {
        await clearSession(credentialScope: credentialScope)
    }

    /// Explicit-scope variant (Lane M): clears ONE profile's credential slot.
    /// The in-memory session resets only when the cleared slot is the one
    /// this store is currently running on — clearing a dormant profile (its
    /// re-pair clean-slate, its deletion) must not log out the active one.
    func clearSession(credentialScope scope: UUID?) async {
        await secureStore.delete(key: BackendProfileScopedKeys.accessToken(scope))
        await secureStore.delete(key: BackendProfileScopedKeys.refreshToken(scope))

        guard scope == credentialScope else {
            persistence.clearSessionState(profileScope: scope)
            return
        }
        let retainedInstallationID = state.installationID
        let retainedEndpoint = state.backendEndpoint
        lastErrorMessage = nil
        isBootstrapping = false
        state = AppSessionState(
            installationID: retainedInstallationID,
            backendEndpoint: retainedEndpoint
        )
        persistence.clearSessionState(profileScope: scope)
    }

    private func persist(tokens: AuthTokens) async throws {
        await secureStore.store(key: BackendProfileScopedKeys.accessToken(credentialScope), value: tokens.accessToken)
        await secureStore.store(key: BackendProfileScopedKeys.refreshToken(credentialScope), value: tokens.refreshToken)
    }

    private func makeRegistrationRequest() -> DeviceRegistrationRequest {
        DeviceRegistrationRequest.current(
            installationID: state.installationID,
            environment: environmentProvider()
        )
    }

    private func loadAndApplySessionState(installationID: UUID) async throws {
        let accessToken = await currentAccessToken()
        var loadedState = try await bootstrapService.loadSession(accessToken: accessToken)
        loadedState = mergeInstallationID(into: loadedState, from: installationID)
        loadedState.syncStatus = .synced
        loadedState.lastSyncAt = .now
        // The relay's /session response is authoritative for whether it holds an
        // active push registration for this device; the in-memory flag only adds
        // a registration that succeeded after this load (it starts false every
        // launch, so overwriting with it hid live server registrations).
        loadedState.pushTokenRegistered =
            loadedState.pushTokenRegistered || notificationService.isPushTokenRegistered
        state = loadedState
    }

    private func applySessionState(_ remoteState: AppSessionState, tokens: AuthTokens) async {
        try? await persist(tokens: tokens)
        state = mergeInstallationID(into: remoteState, from: state.installationID)
    }

    private func attemptRefreshAndReload(installationID: UUID) async -> Bool {
        guard await refreshAccessTokenIfNeeded() == .refreshed else { return false }

        do {
            try await loadAndApplySessionState(installationID: installationID)
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    private func mergeInstallationID(into state: AppSessionState, from installationID: UUID) -> AppSessionState {
        var mergedState = state
        mergedState.installationID = installationID
        return mergedState
    }
}
