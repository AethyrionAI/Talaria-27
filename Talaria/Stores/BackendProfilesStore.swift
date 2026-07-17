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
        var name: String = "OJAMD"
        var gatewayBaseURL: String
        var relayBaseURL: String?
        var shimBaseURL: String?
    }

    enum DeleteError: Error, Equatable {
        case notFound
        /// The active profile cannot be deleted — switch first.
        case profileIsActive
        /// The sensor-destination profile cannot be deleted — repin first.
        case profileIsSensorDestination
    }

    private(set) var state: BackendProfilesState {
        didSet { persistence.saveBackendProfilesState(state) }
    }

    /// Fires after the active profile changes (new value = the activated
    /// profile). AppContainer wires the rebinding side effects here.
    var onActiveProfileChanged: (@MainActor (BackendProfile) async -> Void)?
    /// Fires after a profile is deleted, with the removed record — the
    /// container deletes its Keychain items (delete hygiene, Lane M).
    var onProfileDeleted: (@MainActor (BackendProfile) -> Void)?

    private let persistence: any AppPersistenceStoreProtocol

    init(
        persistence: any AppPersistenceStoreProtocol,
        migrationSeeds: MigrationSeeds
    ) {
        self.persistence = persistence
        if let stored = persistence.loadBackendProfilesState(), !stored.profiles.isEmpty {
            let normalized = Self.normalized(stored)
            self.state = normalized
            if normalized != stored {
                persistence.saveBackendProfilesState(normalized)
            }
        } else {
            // One-shot migration (M-2): current config → one profile, active
            // and sensor destination. Idempotent by construction — it only
            // runs when no profile survives in either store, and re-running
            // it re-adopts the same legacy credential keys.
            let migrated = BackendProfile(
                name: migrationSeeds.name,
                gatewayBaseURL: migrationSeeds.gatewayBaseURL,
                relayBaseURL: migrationSeeds.relayBaseURL ?? "",
                shimBaseURL: migrationSeeds.shimBaseURL,
                usesLegacyCredentialKeys: true
            )
            let fresh = BackendProfilesState(
                profiles: [migrated],
                activeProfileID: migrated.id,
                sensorDestinationProfileID: migrated.id
            )
            self.state = fresh
            persistence.saveBackendProfilesState(fresh)
            profilesLog.notice("migration: minted profile '\(migrationSeeds.name, privacy: .public)' from pre-profile configuration (legacy credential keys)")
        }
    }

    // MARK: - Reads

    var profiles: [BackendProfile] { state.profiles }

    var activeProfile: BackendProfile? { state.activeProfile }

    var activeProfileID: UUID? { state.activeProfile?.id }

    var sensorDestinationProfileID: UUID? {
        state.profile(id: state.sensorDestinationProfileID)?.id ?? state.activeProfile?.id
    }

    var sensorDestinationProfile: BackendProfile? {
        state.profile(id: state.sensorDestinationProfileID) ?? state.activeProfile
    }

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
        Task { await onActiveProfileChanged?(target) }
        return true
    }

    /// Re-pins the sensor destination (M-8). Independent of the active
    /// profile by design.
    @discardableResult
    func setSensorDestination(_ id: UUID) -> Bool {
        guard state.profile(id: id) != nil else { return false }
        guard state.sensorDestinationProfileID != id else { return true }
        var updated = state
        updated.sensorDestinationProfileID = id
        state = updated
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

    /// Deletes a profile. The active profile and the sensor-destination
    /// profile are undeletable (house rule) — switch/repin first.
    func deleteProfile(id: UUID) throws {
        guard let index = state.profiles.firstIndex(where: { $0.id == id }) else {
            throw DeleteError.notFound
        }
        guard activeProfileID != id else { throw DeleteError.profileIsActive }
        guard sensorDestinationProfileID != id else { throw DeleteError.profileIsSensorDestination }
        var updated = state
        let removed = updated.profiles.remove(at: index)
        state = Self.normalized(updated)
        profilesLog.notice("deleted profile '\(removed.name, privacy: .public)'")
        onProfileDeleted?(removed)
    }

    // MARK: - Normalization

    /// Self-heal for dangling ids: the active and sensor-destination ids must
    /// always resolve to an existing profile (fall back to the first).
    private static func normalized(_ state: BackendProfilesState) -> BackendProfilesState {
        var normalized = state
        if normalized.profile(id: normalized.activeProfileID) == nil {
            normalized.activeProfileID = normalized.profiles.first?.id
        }
        if normalized.profile(id: normalized.sensorDestinationProfileID) == nil {
            normalized.sensorDestinationProfileID = normalized.activeProfileID
        }
        return normalized
    }
}
