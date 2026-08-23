import Foundation
import os

private let profilesLog = Logger(subsystem: "org.aethyrion.talaria", category: "BackendProfilesStore")

/// Owns the named backend profiles (Lane M / OPEN_ITEMS #114): the profile
/// list, which one is ACTIVE (default target for new sessions + the
/// relay-plane interactive surfaces), and which one is the pinned SENSOR
/// DESTINATION. Every mutation persists (UserDefaults + Keychain mirror, the
/// #41 dual-store) so profile UUIDs — which key all per-profile credentials —
/// survive clean reinstalls.
///
/// Construction runs the ONE-SHOT migration: an install with no persisted
/// profiles gets a single profile minted from the pre-profile configuration
/// (the "OJAMD" seed), marked `usesLegacyCredentialKeys` so its Keychain and
/// persistence entries stay under the original key strings — nothing is
/// copied or renamed, which is what keeps the migration idempotent and unable
/// to strand an existing pairing. With exactly one profile the app behaves
/// identically to pre-profile builds.
@MainActor
@Observable
final class BackendProfilesStore {
    /// Seeds for the one-shot migration — the pre-profile app-wide values
    /// that become the first profile's endpoints.
    struct MigrationSeeds {
        /// **#384: was `"OJAMD"` — Owen's box, as the profile's NAME.** So a
        /// stranger's fresh install did not merely point at his host, it was
        /// *called* it. The third personal-host literal this item's trace
        /// found and its entry never named.
        ///
        /// Owen's own install is unaffected: M-2 is one-shot and already ran
        /// there, so his profile keeps the name it was minted with (384-D).
        var name: String = "My Hermes"
        var gatewayBaseURL: String
        var relayBaseURL: String?
        var shimBaseURL: String?
    }

    enum DeleteError: Error, Equatable {
        case notFound
        /// The active profile cannot be deleted — switch first.
        case profileIsActive
    }

    private(set) var state: BackendProfilesState {
        didSet { persistence.saveBackendProfilesState(state) }
    }

    /// Fires after the active profile changes (new value = the activated
    /// profile). AppContainer wires the rebinding side effects here.
    ///
    /// #285: invocations are SERIALIZED and cancel-superseding — see
    /// `setActiveProfile`. A handler that suspends must checkpoint on
    /// `Task.isCancelled` after its awaits: cancellation is the signal that
    /// a newer activation superseded this one and its remaining shared-state
    /// writes must not land.
    var onActiveProfileChanged: (@MainActor (BackendProfile) async -> Void)?
    /// Fires after a profile is deleted, with the removed record — the
    /// container deletes its Keychain items (delete hygiene, Lane M).
    var onProfileDeleted: (@MainActor (BackendProfile) -> Void)?

    /// #285: the activation-dispatch chain — the `AppContainer`
    /// bootstrap-generation idiom (#136) applied to profile switches. The
    /// generation stamps which activation is CURRENT; the task handle is the
    /// predecessor a newer activation cancels and then waits out.
    private var activationGeneration = 0
    private var activationTask: Task<Void, Never>?

    private let persistence: any AppPersistenceStoreProtocol

    init(
        persistence: any AppPersistenceStoreProtocol,
        migrationSeeds: MigrationSeeds
    ) {
        self.persistence = persistence
        let loaded: BackendProfilesState
        var mustPersist: Bool
        if let stored = persistence.loadBackendProfilesState(), !stored.profiles.isEmpty {
            loaded = Self.normalized(stored)
            mustPersist = loaded != stored
        } else {
            // One-shot migration (M-2): current config → one profile, active
            // and sensor destination. Idempotent by construction — it only
            // runs when no profile survives in either store, and re-running
            // it re-adopts the same legacy credential keys.
            let migrated = BackendProfile(
                name: migrationSeeds.name,
                gatewayBaseURL: migrationSeeds.gatewayBaseURL,
                relayBaseURL: migrationSeeds.relayBaseURL,
                shimBaseURL: migrationSeeds.shimBaseURL,
                usesLegacyCredentialKeys: true
            )
            loaded = BackendProfilesState(
                profiles: [migrated],
                activeProfileID: migrated.id
            )
            mustPersist = true
            profilesLog.notice("migration: minted profile '\(migrationSeeds.name, privacy: .public)' from pre-profile configuration (legacy credential keys)")
        }

        // #310 — the RELAY-RETIREMENT migration, applied AFTER whichever
        // branch above produced the state, so both converge on the same end
        // state instead of the M-2 mint keeping a seed the retirement would
        // have cleared a moment later.
        //
        // Owen's ruling, 2026-08-20: existing profiles' relay URLs are
        // CLEARED. Both hosts' relays are retired (#346 OJAMD 2026-08-10,
        // #375 Mac 2026-08-18), so every persisted profile points at
        // something dead — which is what costs the #365 profile-switch stall.
        //
        // ⚠️ THIS IS DELIBERATELY NOT IN `normalized(_:)`, and that is the
        // whole design. `normalized` runs on EVERY load and on every upsert;
        // a clear living there would silently wipe a relay URL the user had
        // just typed back in, on the very next save. The stamp is what makes
        // this one-shot, and bar 310-B's phase 2 is what proves it.
        let migratedState: BackendProfilesState
        if persistence.loadRelayRetirementMigrationStamp() {
            migratedState = loaded
        } else {
            migratedState = Self.clearingRelayURLs(loaded)
            // ⚠️ THE STAMP IS WRITTEN BEFORE THE STATE, DELIBERATELY — the
            // opposite ordering looks safer and is worse.
            //
            // Both orderings have a torn-write window on this best-effort
            // dual store, and they fail in opposite directions:
            //   • stamp LAST — if the stamp write is the one that fails, the
            //     next launch re-runs the migration and CLEARS A URL THE USER
            //     MAY HAVE RE-ENTERED in between. That is bar 310-B phase 2's
            //     failure, reached through a crash instead of through a
            //     normalization pass.
            //   • stamp FIRST (this) — if the state write fails, the URLs
            //     simply stay and the #365 stall persists. The migration
            //     failed to HELP; it did not DESTROY.
            //
            // A migration that can fail to help is strictly preferable to one
            // that can eat user input, so the stamp goes first. Do not
            // "correct" this to write-then-stamp.
            persistence.saveRelayRetirementMigrationStamp()
            if migratedState != loaded {
                mustPersist = true
                // Logged PUBLIC and BEFORE the write lands, because the write
                // overwrites both halves of the #41 dual store: after this
                // line the old string exists nowhere in persistence, and a
                // revert of #310 restores the TYPE, not the value. This log
                // is the only recovery route, so it must not be redacted.
                for profile in loaded.profiles where profile.hasRelay {
                    profilesLog.notice("""
                        relay retirement (#310): cleared relay URL for profile \
                        '\(profile.name, privacy: .public)' — was \
                        '\(profile.relayBaseURL ?? "", privacy: .public)'
                        """)
                }
            }
        }

        self.state = migratedState
        if mustPersist {
            persistence.saveBackendProfilesState(migratedState)
        }
    }

    // MARK: - Reads

    var profiles: [BackendProfile] { state.profiles }

    var activeProfile: BackendProfile? { state.activeProfile }

    var activeProfileID: UUID? { state.activeProfile?.id }

    func profile(id: UUID?) -> BackendProfile? {
        state.profile(id: id)
    }

    /// Resolves a profile for credential/routing purposes: an explicit id
    /// when known, else the active profile.
    func resolvedProfile(id: UUID?) -> BackendProfile? {
        state.profile(id: id) ?? state.activeProfile
    }

    // MARK: - Mutations

    /// Adds a new profile or updates an existing one in place. The migrated
    /// profile's `usesLegacyCredentialKeys` flag is preserved on update — the
    /// credential scope is not editable.
    func upsert(_ profile: BackendProfile) {
        var updated = state
        if let index = updated.profiles.firstIndex(where: { $0.id == profile.id }) {
            var merged = profile
            merged.usesLegacyCredentialKeys = updated.profiles[index].usesLegacyCredentialKeys
            updated.profiles[index] = merged
        } else {
            updated.profiles.append(profile)
        }
        state = Self.normalized(updated)
    }

    /// In-place edit of the active profile — the settings screens' write path.
    func updateActiveProfile(_ mutate: (inout BackendProfile) -> Void) {
        guard let active = state.activeProfile,
              let index = state.profiles.firstIndex(where: { $0.id == active.id }) else { return }
        var updated = state
        var profile = updated.profiles[index]
        let scope = profile.usesLegacyCredentialKeys
        mutate(&profile)
        profile.usesLegacyCredentialKeys = scope
        guard profile != updated.profiles[index] else { return }
        updated.profiles[index] = profile
        state = updated
    }

    /// Activates a profile. Returns false when the id is unknown or already
    /// active. Side effects (pairing/session rebind, inbox reset, …) ride
    /// `onActiveProfileChanged` — wired by AppContainer.
    @discardableResult
    func setActiveProfile(_ id: UUID) -> Bool {
        guard let target = state.profile(id: id), state.activeProfile?.id != id else { return false }
        var updated = state
        updated.activeProfileID = id
        state = updated
        profilesLog.notice("active profile → '\(target.name, privacy: .public)'")
        // #285: the scope moved SYNCHRONOUSLY above; the side effects are
        // dispatched serialized and cancel-superseding (the #136 bootstrap
        // idiom). A rapid A→B→C must not interleave two handlers' awaits:
        // the superseded dispatch is cancelled — if its handler never
        // started, the generation guard below stops it from starting; if it
        // is mid-flight, its own `Task.isCancelled` checkpoints stop its
        // remaining writes — and the newer dispatch WAITS OUT the corpse so
        // nothing stale can land after it. Last writer wins, always.
        activationGeneration += 1
        let generation = activationGeneration
        let predecessor = activationTask
        predecessor?.cancel()
        activationTask = Task { [weak self] in
            await predecessor?.value
            guard let self, self.activationGeneration == generation, !Task.isCancelled else { return }
            await self.onActiveProfileChanged?(target)
        }
        return true
    }

    /// M-9: records that a profile's relay tokens were just minted/refreshed,
    /// so the dormant-refresh pass can skip it for the next window.
    func stampTokenRefresh(profileID: UUID?, at date: Date = .now) {
        guard let profileID,
              let index = state.profiles.firstIndex(where: { $0.id == profileID }) else { return }
        var updated = state
        updated.profiles[index].lastTokenRefreshAt = date
        state = updated
    }

    /// Deletes a profile. The active profile is undeletable (house rule) —
    /// switch first.
    func deleteProfile(id: UUID) throws {
        guard let index = state.profiles.firstIndex(where: { $0.id == id }) else {
            throw DeleteError.notFound
        }
        guard activeProfileID != id else { throw DeleteError.profileIsActive }
        var updated = state
        let removed = updated.profiles.remove(at: index)
        state = Self.normalized(updated)
        profilesLog.notice("deleted profile '\(removed.name, privacy: .public)'")
        onProfileDeleted?(removed)
    }

    // MARK: - Normalization

    /// #310: the relay-retirement transform — every profile loses its relay
    /// URL. Pure, so the one-shot decision (the stamp) and the transform stay
    /// separable and testable apart from each other.
    ///
    /// It is `private static` and called from exactly ONE place, the
    /// initializer's stamped branch. If a future lane finds itself wanting to
    /// call this from `normalized(_:)` or from `upsert(_:)`, that is the
    /// defect 310-B was written to catch — the answer is a new one-shot stamp,
    /// never a repeating clear.
    private static func clearingRelayURLs(_ state: BackendProfilesState) -> BackendProfilesState {
        var cleared = state
        for index in cleared.profiles.indices {
            cleared.profiles[index].relayBaseURL = nil
        }
        return cleared
    }

    /// Self-heal for dangling ids: the active id must always resolve to an
    /// existing profile (fall back to the first).
    private static func normalized(_ state: BackendProfilesState) -> BackendProfilesState {
        var normalized = state
        if normalized.profile(id: normalized.activeProfileID) == nil {
            normalized.activeProfileID = normalized.profiles.first?.id
        }
        return normalized
    }
}
