import Foundation
import os

/// **The relay-era credential purge (#309 Lane B, bar 309-B9).**
///
/// Four slots per profile outlived the code that read them: the relay session's
/// `accessToken` and `refreshToken` (Keychain), and the `pairedRelayConfiguration`
/// and `sessionState` blobs (UserDefaults, with a Keychain mirror on the first).
/// Nothing in the app can read any of them any more — `AppSessionStore`,
/// `PairingStore` and their models are deleted — so what is left is a JWT and a
/// relay user id sitting in a Keychain nobody will ever open.
///
/// **It sweeps EVERY profile's slots, not just the active one, and that is the
/// point.** The old family had TWO writers: `AppSessionStore` wrote the active
/// profile's tokens and `ProfileRelaySessionFactory` wrote dormant profiles'
/// during the refresh pass. A purge that knew only the first writer would leave
/// exactly the half-cleared ghosts #133 taught us to fear — a state that reads
/// as "no session" from one angle and "still paired" from another.
///
/// **What it must never touch,** pinned by test:
/// `gatewayAPIKey` (the chat plane's credential), `talariaDeviceToken` and
/// `talariaDeviceID` (the plugin link's), `shimToken`, and
/// `talaria.installationID` — the #133/#143 durable identity, which has never
/// been scoped and is never cleared.
@MainActor
enum RelayCredentialHygiene {

    private static let logger = Logger(
        subsystem: TalariaLog.subsystem, category: "RelayCredentialHygiene")

    /// The dead Keychain slots, per scope. Named here rather than inlined so
    /// the list can be read against `BackendProfileScopedKeys` by eye and by
    /// test — a purge whose scope is implicit is a purge that widens quietly.
    // harness-visible
    static func deadKeychainKeys(scope: UUID?) -> [String] {
        [
            BackendProfileScopedKeys.accessToken(scope),
            BackendProfileScopedKeys.refreshToken(scope),
        ]
    }

    /// Slots that MUST survive. Not used by `purge` — used by its test, which
    /// is the only way "the purge did not widen" gets measured rather than
    /// asserted.
    // harness-visible
    static func survivingKeychainKeys(scope: UUID?) -> [String] {
        [
            BackendProfileScopedKeys.gatewayAPIKey(scope),
            BackendProfileScopedKeys.shimToken(scope),
            BackendProfileScopedKeys.talariaDeviceToken(scope),
            BackendProfileScopedKeys.talariaDeviceID(scope),
        ]
    }

    /// Idempotent by construction: deleting an absent Keychain item is a no-op,
    /// and the persistence purge removes keys rather than rewriting them. The
    /// stamp is an optimisation, not a correctness requirement — a lost stamp
    /// costs one extra sweep, never a wrong outcome.
    static func purge(
        scopes: [UUID?],
        secureStore: any SecureStoreProtocol,
        persistence: any AppPersistenceStoreProtocol
    ) async {
        for scope in scopes {
            for key in deadKeychainKeys(scope: scope) {
                await secureStore.delete(key: key)
            }
            persistence.purgeRelayCredentialResidue(profileScope: scope)
        }
        logger.notice("purge: swept \(scopes.count, privacy: .public) credential scope(s) of relay residue")
    }

    /// Every scope that could hold residue: one per profile, plus `nil` — the
    /// LEGACY unscoped slots the pre-profile app wrote and the migrated first
    /// profile still uses. Omitting `nil` would leave the oldest install in the
    /// fleet — Owen's — the only one not swept.
    // harness-visible
    static func scopes(for profiles: [BackendProfile]) -> [UUID?] {
        var seen: [UUID?] = [nil]
        for profile in profiles where !seen.contains(profile.credentialScopeID) {
            seen.append(profile.credentialScopeID)
        }
        return seen
    }
}
