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
/// **Mechanism:** the installation id lived inside `AppSessionState`, which is
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
@MainActor
struct InstallationIdentityTests {

    private func makePersistence(_ suite: String) -> UserDefaultsAppPersistenceStore {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return UserDefaultsAppPersistenceStore(defaults: defaults)
    }

    private func makeStore(_ persistence: UserDefaultsAppPersistenceStore) -> AppSessionStore {
        AppSessionStore(
            bootstrapService: MockSessionBootstrapService(),
            syncCoordinator: MockSyncCoordinator(),
            secureStore: MockSecureStore(),
            persistence: persistence,
            notificationService: MockNotificationService(),
            environmentProvider: { .development }
        )
    }

    /// THE defect. Unpair clears the profile-scoped session state; the next
    /// COLD LAUNCH constructs a store with nothing persisted. Before the fix
    /// that minted a brand-new identity and the relay minted a brand-new
    /// device row — 99 times over.
    @Test func identitySurvivesUnpairFollowedByAColdLaunch() async {
        let persistence = makePersistence("install-identity-unpair-\(UUID().uuidString)")

        let firstLaunch = makeStore(persistence)
        let original = firstLaunch.state.installationID

        await firstLaunch.clearSession()          // unpair
        let coldLaunch = makeStore(persistence)   // relaunch: init reads persistence

        #expect(coldLaunch.state.installationID == original,
                "unpair + cold launch minted a NEW installation identity — this is the #133/#143 churn")
    }

    /// The plainest case, and the one that must never regress: two launches
    /// with nothing else happening are the same installation.
    @Test func identityIsStableAcrossAnOrdinaryRelaunch() {
        let persistence = makePersistence("install-identity-relaunch-\(UUID().uuidString)")
        let first = makeStore(persistence).state.installationID
        let second = makeStore(persistence).state.installationID
        #expect(first == second)
    }

    /// One physical install, many relays (Lane M). Switching or clearing a
    /// PROFILE must not re-identify the device — the id is app-wide, not
    /// scope-wide, and a per-scope id is precisely what let two profiles
    /// produce two device rows for one handset.
    @Test func identityIsSharedAcrossProfileScopes() async {
        let persistence = makePersistence("install-identity-scopes-\(UUID().uuidString)")
        let scopeA = UUID()
        let scopeB = UUID()

        let storeA = AppSessionStore(
            bootstrapService: MockSessionBootstrapService(),
            syncCoordinator: MockSyncCoordinator(),
            secureStore: MockSecureStore(),
            persistence: persistence,
            notificationService: MockNotificationService(),
            environmentProvider: { .development },
            credentialScopeProvider: { scopeA }
        )
        let storeB = AppSessionStore(
            bootstrapService: MockSessionBootstrapService(),
            syncCoordinator: MockSyncCoordinator(),
            secureStore: MockSecureStore(),
            persistence: persistence,
            notificationService: MockNotificationService(),
            environmentProvider: { .development },
            credentialScopeProvider: { scopeB }
        )

        #expect(storeA.state.installationID == storeB.state.installationID)
    }

    /// The id is minted ONCE and then read back — not regenerated per call.
    @Test func theIdentityIsPersistedOnFirstUse() {
        let persistence = makePersistence("install-identity-persist-\(UUID().uuidString)")
        #expect(persistence.loadInstallationID() == nil)

        let minted = makeStore(persistence).state.installationID

        #expect(persistence.loadInstallationID() == minted)
    }

    /// The partial-fix trap. Fixing only `init` leaves
    /// `rebindToCurrentScope()` assigning a persisted state DIRECTLY
    /// (`state = persisted`) — and a state persisted before this fix, or
    /// under another scope, carries its own churned id. Adopting it would
    /// re-identify the device on the next profile switch and mint another
    /// relay device row, which is the whole defect coming back through the
    /// one door the first patch left open.
    @Test func aProfileSwitchDoesNotAdoptAPersistedStatesStaleIdentity() {
        let persistence = makePersistence("install-identity-rebind-\(UUID().uuidString)")
        let scope = UUID()

        // A pre-fix (or foreign-scope) session state carrying its OWN id.
        let stale = AppSessionState(installationID: UUID(), deviceRegistered: true)
        persistence.saveSessionState(stale, profileScope: scope)

        let store = AppSessionStore(
            bootstrapService: MockSessionBootstrapService(),
            syncCoordinator: MockSyncCoordinator(),
            secureStore: MockSecureStore(),
            persistence: persistence,
            notificationService: MockNotificationService(),
            environmentProvider: { .development },
            credentialScopeProvider: { scope }
        )
        let durable = persistence.loadInstallationID()
        #expect(durable != nil)
        #expect(stale.installationID != durable, "fixture must differ, or this test proves nothing")

        store.rebindToCurrentScope()

        #expect(store.state.installationID == durable,
                "rebind adopted the persisted state's stale identity — #133/#143 churn via the profile-switch path")
    }

    /// `clearSessionState` must not take the installation id with it — that
    /// coupling IS the bug. Asserted at the persistence layer so a future
    /// refactor of the store cannot silently reintroduce it.
    @Test func clearingSessionStateLeavesTheInstallationIdAlone() {
        let persistence = makePersistence("install-identity-clear-\(UUID().uuidString)")
        let minted = makeStore(persistence).state.installationID

        persistence.clearSessionState(profileScope: nil)
        persistence.clearSessionState(profileScope: UUID())

        #expect(persistence.loadInstallationID() == minted)
    }
}
