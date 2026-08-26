import Foundation

/// The durable identity of THIS app installation (#133/#143), and the
/// `install_id` the talaria plugin's `create_paired_device` rotation keys on.
///
/// **Ported here by #309 Lane A (2026-08-25) from `AppSessionStore.init`,
/// byte-for-byte in behaviour.** It lived inside the relay session store only
/// because the id used to ride inside `AppSessionState`; the relay bootstrap
/// chain that store existed for is deleted, and this is the one piece of it
/// that must outlive the deletion. Giving it its own owner also removes the
/// coupling that caused the original defect: an installation id that lives
/// inside a profile-scoped, clearable session is a session id wearing the
/// wrong name.
///
/// **The measurement that framed it (Mac relay, 2026-08-02): 99 device rows
/// against 99 distinct installation ids** — a perfect 1:1. The relay upserted
/// on installation and was behaving correctly the whole time; the app minted
/// 99 identities, because `AppSessionStore.init` fell back to
/// `AppSessionState()` (a fresh `UUID()`) whenever `clearSession` had deleted
/// the profile-scoped state. unpair → cold launch → new identity → a new
/// device row → one more active push registration for the SAME APNs token →
/// #143's duplicate notifications.
///
/// Pinned by `InstallationIdentityTests`, which ported with this code.
///
/// `@MainActor` because `AppPersistenceStoreProtocol` is — the logic used to
/// inherit that isolation from `AppSessionStore`, and a free-floating enum has
/// to state it.
@MainActor
enum InstallationIdentity {

    /// Reads the durable id, minting and persisting one the first time.
    ///
    /// Idempotent: the mint happens exactly once per installation, and every
    /// later call reads the same value back. The write is deliberately eager
    /// (rather than lazy on first USE) so a launch that reads the id and then
    /// dies still leaves the same identity behind.
    static func resolve(persistence: any AppPersistenceStoreProtocol) -> UUID {
        if let durable = persistence.loadInstallationID() { return durable }
        let minted = UUID()
        persistence.saveInstallationID(minted)
        return minted
    }

    /// Stamps the durable id onto a session state loaded from persistence.
    ///
    /// **STAMP, do not adopt.** A state persisted before the #133 fix — or
    /// under a different profile scope — carries its own churned id, and
    /// adopting it would re-identify the device on the next profile switch
    /// and mint another device row. Fixing only the construction path left
    /// exactly this door open once already; `rebindToCurrentScope` is the
    /// door.
    static func stamp(_ id: UUID, onto state: AppSessionState) -> AppSessionState {
        var stamped = state
        stamped.installationID = id
        return stamped
    }
}
