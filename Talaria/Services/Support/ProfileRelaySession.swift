import Foundation
import os

private let profileRelayLog = Logger(subsystem: "org.aethyrion.talaria", category: "ProfileRelaySession")

/// Per-profile relay access for the paths that must reach a NON-ACTIVE
/// backend (Lane M PR 2): the pinned sensor destination (M-8), push
/// registration/watches on every paired relay (M-7), and the dormant-token
/// freshness pass (M-9).
///
/// The ACTIVE profile stays `AppSessionStore`'s business — it owns that
/// profile's single-flight refresh and the #15 re-register ladder, and two
/// refreshers racing one rotating refresh token would strand the loser. This
/// factory therefore only ever REFRESHES dormant profiles; reads are safe for
/// any profile.
@MainActor
final class ProfileRelaySessionFactory {
    private let persistence: any AppPersistenceStoreProtocol
    private let secureStore: any SecureStoreProtocol
    private let profileResolver: @MainActor (UUID) -> BackendProfile?
    private let activeProfileIDProvider: @MainActor () -> UUID?
    /// Fires after a successful dormant refresh so the profiles store can
    /// stamp `lastTokenRefreshAt`.
    var onTokensRefreshed: (@MainActor (UUID) -> Void)?

    /// Single-flight per profile: concurrent refresh callers for the same
    /// dormant profile coalesce onto one relay round trip.
    private var refreshTasks: [UUID: Task<String?, Never>] = [:]

    init(
        persistence: any AppPersistenceStoreProtocol,
        secureStore: any SecureStoreProtocol,
        profileResolver: @escaping @MainActor (UUID) -> BackendProfile?,
        activeProfileIDProvider: @escaping @MainActor () -> UUID?
    ) {
        self.persistence = persistence
        self.secureStore = secureStore
        self.profileResolver = profileResolver
        self.activeProfileIDProvider = activeProfileIDProvider
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
        let configured = profile.relayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
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

    /// Persists a profile's push-registration flag (M-7) — the dormant-relay
    /// counterpart of `sessionStore.state.pushTokenRegistered`.
    func markPushTokenRegistered(_ registered: Bool, profileID: UUID) {
        guard let profile = profileResolver(profileID) else { return }
        let scope = profile.credentialScopeID
        guard var state = persistence.loadSessionState(profileScope: scope) else { return }
        state.pushTokenRegistered = registered
        persistence.saveSessionState(state, profileScope: scope)
    }

    // MARK: - Refresh (dormant profiles only)

    /// Refreshes a DORMANT profile's relay tokens against its own relay and
    /// returns the fresh access token (nil on any failure — callers treat it
    /// like the existing refresher ladder's nil: don't retry with the stale
    /// token). Refuses the active profile: `AppSessionStore` owns that
    /// refresh, and racing its rotation would strand one of the two.
    func refreshAccessToken(forProfileID profileID: UUID) async -> String? {
        guard profileID != activeProfileIDProvider() else {
            profileRelayLog.error("refresh: refused for the ACTIVE profile — AppSessionStore owns it")
            return nil
        }
        if let running = refreshTasks[profileID] {
            return await running.value
        }
        let task = Task { await performRefresh(profileID: profileID) }
        refreshTasks[profileID] = task
        let token = await task.value
        refreshTasks[profileID] = nil
        return token
    }

    private func performRefresh(profileID: UUID) async -> String? {
        guard let profile = profileResolver(profileID) else { return nil }
        let scope = profile.credentialScopeID
        guard let refreshToken = await secureStore.retrieve(key: BackendProfileScopedKeys.refreshToken(scope)),
              !refreshToken.isEmpty else {
            return nil
        }
        let bootstrap = LiveSessionBootstrapService(apiClient: apiClient(forProfileID: profileID))
        do {
            let tokens = try await bootstrap.refreshAuth(refreshToken: refreshToken)
            await secureStore.store(key: BackendProfileScopedKeys.accessToken(scope), value: tokens.accessToken)
            await secureStore.store(key: BackendProfileScopedKeys.refreshToken(scope), value: tokens.refreshToken)
            onTokensRefreshed?(profileID)
            profileRelayLog.notice("refresh: dormant profile '\(profile.name, privacy: .public)' tokens rotated")
            return tokens.accessToken
        } catch {
            profileRelayLog.notice("refresh: dormant profile '\(profile.name, privacy: .public)' failed — \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

/// M-9: which dormant profiles are due a token refresh. Pure so the
/// no-thrash rules are unit-testable: a profile is due when it is paired,
/// not active, its last known refresh is older than `refreshInterval`
/// (or unknown), and this process hasn't attempted it within
/// `attemptFloor` — failures must not retry on every foreground.
enum DormantTokenRefreshPolicy {
    static let refreshInterval: TimeInterval = 7 * 24 * 60 * 60
    static let attemptFloor: TimeInterval = 6 * 60 * 60

    static func profilesDue(
        profiles: [BackendProfile],
        activeProfileID: UUID?,
        isPaired: (BackendProfile) -> Bool,
        lastAttempts: [UUID: Date],
        now: Date = .now
    ) -> [BackendProfile] {
        profiles.filter { profile in
            guard profile.id != activeProfileID, isPaired(profile) else { return false }
            if let attempted = lastAttempts[profile.id],
               now.timeIntervalSince(attempted) < attemptFloor {
                return false
            }
            guard let refreshed = profile.lastTokenRefreshAt else { return true }
            return now.timeIntervalSince(refreshed) >= refreshInterval
        }
    }
}
