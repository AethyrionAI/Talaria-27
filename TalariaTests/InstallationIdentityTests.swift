import Foundation
import Testing
@testable import Talaria

/// OPEN_ITEMS #133 / #143 — one root cause, two symptoms.
///
/// **The measurement that framed this (Mac relay, 2026-08-02): 99 device rows
/// against 99 distinct `installation_id`s — a perfect 1:1.** The relay upserts
/// on installation and was behaving correctly the whole time; the app minted
/// 99 identities. The two rows for the one real handset carry different
/// installation ids a week apart (`3b6f41e8` born 07-16, `c718cc64` born
/// 07-23), which is the churn in two rows.
///
/// **Mechanism:** the installation id lived inside `AppSessionState`, which was
/// PROFILE-SCOPED and deleted by `clearSession`. `AppSessionStore.init` fell
/// back to `AppSessionState()` when no state was persisted — and that mints a
/// fresh `UUID()`. So unpair → cold launch → new identity → the relay
/// correctly creates a new device row → its `upsert_push_registration` keys on
/// the new device → one more active registration carrying the SAME APNs token
/// → `active_push_registrations_for_user` fans out per row → #143's duplicate
/// notifications.
///
/// An installation id identifies an app INSTALLATION. It must outlive pairing,
/// unpairing, and profile scope — otherwise it is a session id wearing the
/// wrong name.
///
/// ---
///
/// **PORTED TWICE, NEVER TOMBSTONED.** #309 Lane A moved the logic out of
/// `AppSessionStore.init` into `InstallationIdentity`; Lane B deleted the
/// store, `AppSessionState`, and the profile-scoped session blob the id used
/// to ride inside. These tests followed the code both times, and the second
/// move is the more interesting one:
///
/// **Three of the six defects below are now STRUCTURALLY IMPOSSIBLE rather
/// than guarded against, and the tests say which.** There is no session state
/// to clear, no per-scope store to construct, and no `stamp(_:onto:)` for a
/// rebind to mis-apply — the id is one unscoped key that nothing but
/// `InstallationIdentity` reads or writes, and the residue purge is written to
/// avoid it by name. The tests still assert the OUTCOMES, because "impossible
/// by construction" is a claim about today's construction: they will fail the
/// day someone re-couples the two, which is the only thing they were ever for.
@MainActor
struct InstallationIdentityTests {

    private func makePersistence(_ suite: String) -> UserDefaultsAppPersistenceStore {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return UserDefaultsAppPersistenceStore(defaults: defaults)
    }

    /// THE defect. Disconnect clears the profile's credentials; the next COLD
    /// LAUNCH resolves the identity with nothing session-shaped persisted.
    /// Before the fix that minted a brand-new identity and the relay minted a
    /// brand-new device row — 99 times over.
    ///
    /// The "unpair" is now the residue purge plus a credential wipe, which is
    /// what Connect Host's Disconnect actually does.
    @Test func identitySurvivesUnpairFollowedByAColdLaunch() async {
        let persistence = makePersistence("install-identity-unpair-\(UUID().uuidString)")
        let secureStore = MockSecureStore()

        let original = InstallationIdentity.resolve(persistence: persistence)

        await RelayCredentialHygiene.purge(
            scopes: [nil, UUID()], secureStore: secureStore, persistence: persistence)

        let afterColdLaunch = InstallationIdentity.resolve(persistence: persistence)

        #expect(afterColdLaunch == original,
                "unpair + cold launch minted a NEW installation identity — this is the #133/#143 churn")
    }

    /// The plainest case, and the one that must never regress: two launches
    /// with nothing else happening are the same installation.
    @Test func identityIsStableAcrossAnOrdinaryRelaunch() {
        let persistence = makePersistence("install-identity-relaunch-\(UUID().uuidString)")
        let first = InstallationIdentity.resolve(persistence: persistence)
        let second = InstallationIdentity.resolve(persistence: persistence)
        #expect(first == second)
    }

    /// One physical install, many hosts (Lane M). Switching or clearing a
    /// PROFILE must not re-identify the device — the id is app-wide, not
    /// scope-wide, and a per-scope id is precisely what let two profiles
    /// produce two device rows for one handset.
    ///
    /// Since Lane B the resolver takes NO scope at all, so this reads as a
    /// tautology — and that is the point. It is the pin that reds if a future
    /// lane reintroduces a scope parameter "for symmetry".
    @Test func identityIsSharedAcrossProfileScopes() async {
        let persistence = makePersistence("install-identity-scopes-\(UUID().uuidString)")
        let secureStore = MockSecureStore()
        let scopeA = UUID()
        let scopeB = UUID()

        let underA = InstallationIdentity.resolve(persistence: persistence)
        // Sweep BOTH scopes between the reads: a scope-coupled identity would
        // not survive its own scope being purged.
        await RelayCredentialHygiene.purge(
            scopes: [scopeA, scopeB], secureStore: secureStore, persistence: persistence)
        let underB = InstallationIdentity.resolve(persistence: persistence)

        #expect(underA == underB)
    }

    /// The id is minted ONCE and then read back — not regenerated per call.
    @Test func theIdentityIsPersistedOnFirstUse() {
        let persistence = makePersistence("install-identity-persist-\(UUID().uuidString)")
        #expect(persistence.loadInstallationID() == nil)

        let minted = InstallationIdentity.resolve(persistence: persistence)

        #expect(persistence.loadInstallationID() == minted)
    }

    /// **The partial-fix trap, re-pointed at the mechanism that replaced it.**
    ///
    /// The original defect's second door was `rebindToCurrentScope()` adopting
    /// a persisted state's own churned id on a profile switch. There is no
    /// persisted state and no rebind any more — Lane B deleted `stamp(_:onto:)`
    /// with `AppSessionState`. What could reopen the door is the RESIDUE PURGE
    /// widening onto `talaria.installationID`, which lives in the same
    /// UserDefaults and looks adjacent to the keys the purge does take.
    ///
    /// So the test asks the same question of the new code: after a full sweep
    /// of every scope, is the device still itself?
    @Test func theResiduePurgeDoesNotTakeTheInstallationIdWithIt() async {
        let persistence = makePersistence("install-identity-purge-\(UUID().uuidString)")
        let secureStore = MockSecureStore()
        let minted = InstallationIdentity.resolve(persistence: persistence)

        // Every scope shape a real install can present: legacy-unscoped, and
        // two profile scopes.
        await RelayCredentialHygiene.purge(
            scopes: [nil, UUID(), UUID()], secureStore: secureStore, persistence: persistence)

        #expect(persistence.loadInstallationID() == minted,
                "the residue purge took the installation id — #133/#143 churn through a new door")
        #expect(InstallationIdentity.resolve(persistence: persistence) == minted)
    }

    /// The persistence-layer half of the same rule, asserted directly so a
    /// future refactor of the purge cannot silently reintroduce the coupling
    /// that IS the bug.
    @Test func purgingResidueLeavesTheInstallationIdAlone() {
        let persistence = makePersistence("install-identity-clear-\(UUID().uuidString)")
        let minted = InstallationIdentity.resolve(persistence: persistence)

        persistence.purgeRelayCredentialResidue(profileScope: nil)
        persistence.purgeRelayCredentialResidue(profileScope: UUID())

        #expect(persistence.loadInstallationID() == minted)
    }
}
