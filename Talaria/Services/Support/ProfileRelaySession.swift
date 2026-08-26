import Foundation

/// Per-profile relay READS for the paths that must reach a NON-ACTIVE backend
/// (Lane M PR 2).
///
/// **#309 Lane A (2026-08-25) deleted this type's refresh half.**
/// `refreshAccessToken(forProfileID:)` / `performRefresh` were the FOURTH
/// constructor of `LiveSessionBootstrapService` — the dormant-profile arm of
/// the same doomed `auth/refresh` round trip — and `DormantTokenRefreshPolicy`
/// existed only to decide when to fire it. Both are gone with the bootstrap
/// chain, along with `AppContainer.refreshDormantProfileTokensIfNeeded` and
/// the `onTokensRefreshed` stamp it drove. What is left is pure local reads
/// (pairing record, tokens, session state) that the Settings screens and
/// `ContentView` still ask for; the whole file goes with Lane C's
/// `RelayAPIClient` deletion.
@MainActor
final class ProfileRelaySessionFactory {
    private let persistence: any AppPersistenceStoreProtocol
    private let secureStore: any SecureStoreProtocol
    private let profileResolver: @MainActor (UUID) -> BackendProfile?

    init(
        persistence: any AppPersistenceStoreProtocol,
        secureStore: any SecureStoreProtocol,
        profileResolver: @escaping @MainActor (UUID) -> BackendProfile?
    ) {
        self.persistence = persistence
        self.secureStore = secureStore
        self.profileResolver = profileResolver
    }

    // MARK: - Reads (any profile)

    /// The relay base URL a profile's traffic should use: its pairing-minted
    /// URL when paired (authoritative — pairing may have adjusted the host),
    /// else the profile's configured relay endpoint.
    func relayBaseURL(forProfileID profileID: UUID) -> String? {
        guard let profile = profileResolver(profileID) else { return nil }
        let scope = profile.credentialScopeID
        if let paired = persistence.loadPairedRelayConfiguration(profileScope: scope) {
            return paired.baseURLString
        }
        // #310: `resolvedRelayBaseURL` already folds nil and "" together; the
        // trim stays because a whitespace-only field is a third way to mean
        // "none" and the type cannot see it.
        let configured = (profile.resolvedRelayBaseURL ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return configured.isEmpty ? nil : configured
    }

    func isPaired(profileID: UUID) -> Bool {
        guard let profile = profileResolver(profileID) else { return false }
        return persistence.loadPairedRelayConfiguration(profileScope: profile.credentialScopeID) != nil
    }

    func accessToken(forProfileID profileID: UUID) async -> String? {
        guard let profile = profileResolver(profileID) else { return nil }
        return await secureStore.retrieve(key: BackendProfileScopedKeys.accessToken(profile.credentialScopeID))
    }

    /// The persisted relay session state for a profile (deviceID etc.) —
    /// needed by per-relay push registration (M-7).
    func sessionState(forProfileID profileID: UUID) -> AppSessionState? {
        guard let profile = profileResolver(profileID) else { return nil }
        return persistence.loadSessionState(profileScope: profile.credentialScopeID)
    }

    /// A relay client bound to the profile's CURRENT base URL (resolved per
    /// request, so a re-pair onto a new host is picked up live).
    func apiClient(forProfileID profileID: UUID) -> RelayAPIClient {
        RelayAPIClient { [weak self] in
            self?.relayBaseURL(forProfileID: profileID) ?? ""
        }
    }
}
