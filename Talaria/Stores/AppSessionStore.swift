import Foundation

/// What is LEFT of the relay session store after #309 Lane A (2026-08-25).
///
/// **The bootstrap / refresh / revoke chain is DELETED.** `bootstrap()`,
/// `refreshSession()`, `refreshAccessTokenIfNeeded()`, `performTokenRefresh`,
/// `recoverSessionByReRegistering()` (#15's silent re-registration ladder) and
/// `revokeCurrentSession()` all spoke to `device/register`, `session`,
/// `auth/refresh` and `auth/revoke` on a relay that is retired on BOTH hosts —
/// on the cold-launch hot path, on every profile switch of a relay-bearing
/// profile, and behind every 401 the app ever saw. Deleting them removes real
/// doomed traffic from real installs (#365's stall, design doc §2).
///
/// What survives, and why:
/// - `state` and its persistence, because `AppSessionState` still feeds the
///   Diagnostics / About / Uplink read surfaces (Lane B retires those).
/// - the access/refresh Keychain slots, because `PairingStore` still writes
///   them on a redeem and the relay-fed stores still read the access token
///   (Lane B and Lane C respectively).
/// - the durable installation identity, which moved OUT to
///   `InstallationIdentity` — see #133/#143 there.
///
/// The type itself, and everything above, dies with Lanes B/C.
@MainActor
@Observable
final class AppSessionStore {

    var state: AppSessionState {
        didSet { persistence.saveSessionState(state, profileScope: credentialScope) }
    }
    var lastErrorMessage: String?

    private let secureStore: any SecureStoreProtocol
    private let persistence: any AppPersistenceStoreProtocol
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
        secureStore: any SecureStoreProtocol,
        persistence: any AppPersistenceStoreProtocol,
        credentialScopeProvider: @escaping @MainActor () -> UUID? = { nil }
    ) {
        self.secureStore = secureStore
        self.persistence = persistence
        self.credentialScopeProvider = credentialScopeProvider
        // #133/#143 — resolve the DURABLE installation identity first, then
        // stamp it onto whatever session state we load. The resolution itself
        // lives in `InstallationIdentity` since #309 Lane A; the ORDER here is
        // the load-bearing part and did not change.
        let resolvedID = InstallationIdentity.resolve(persistence: persistence)
        let loaded = persistence.loadSessionState(profileScope: credentialScopeProvider()) ?? AppSessionState()
        // A state persisted before this fix carries its own (churned) id —
        // the durable one wins, so an upgrade converges on ONE identity
        // instead of grandfathering whichever it last minted.
        self.state = InstallationIdentity.stamp(resolvedID, onto: loaded)
    }

    func currentAccessToken() async -> String? {
        await secureStore.retrieve(key: BackendProfileScopedKeys.accessToken(credentialScope))
    }

    func applyPairedSession(state: AppSessionState, tokens: AuthTokens) async {
        lastErrorMessage = nil
        await persist(tokens: tokens)
        self.state = InstallationIdentity.stamp(self.state.installationID, onto: state)
    }

    /// Lane M (M-6): re-reads the persisted session for the CURRENT
    /// credential scope — call immediately after the active profile changes,
    /// before anything else touches `state` (its didSet persists against the
    /// live scope). A profile with no persisted session starts fresh,
    /// retaining the installation id (one app install, many relays).
    func rebindToCurrentScope() {
        lastErrorMessage = nil
        if let persisted = persistence.loadSessionState(profileScope: credentialScope) {
            // #133/#143: STAMP, do not adopt. A state persisted before the
            // durable-identity fix — or under a different scope — carries its
            // own churned installation id, and `state = persisted` would
            // re-identify this device on the next profile switch and mint
            // another relay device row. Fixing only `init` left exactly this
            // door open; pinned by
            // `aProfileSwitchDoesNotAdoptAPersistedStatesStaleIdentity`,
            // which failed here before this line changed.
            state = InstallationIdentity.stamp(state.installationID, onto: persisted)
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
        state = AppSessionState(
            installationID: retainedInstallationID,
            backendEndpoint: retainedEndpoint
        )
        persistence.clearSessionState(profileScope: scope)
    }

    private func persist(tokens: AuthTokens) async {
        await secureStore.store(key: BackendProfileScopedKeys.accessToken(credentialScope), value: tokens.accessToken)
        await secureStore.store(key: BackendProfileScopedKeys.refreshToken(credentialScope), value: tokens.refreshToken)
    }
}
