import Foundation
import os

private let pairingLog = Logger(subsystem: "org.aethyrion.talaria", category: "PairingStore")

@MainActor
@Observable
final class PairingStore {
    private static let onboardingKey = "hermes.needsPermissionsOnboarding"

    var pairedRelayConfiguration: PairedRelayConfiguration?
    var isWorking = false
    var lastErrorMessage: String?
    var needsPermissionsOnboarding = false
    var onPairingChanged: (@MainActor (Bool) async -> Void)?

    /// True when the restored session authenticates as a different relay user
    /// than the one this pairing minted — the reinstall-resurrected-identity
    /// signature (#3/#46). Surfaced in Diagnostics; cleared by a re-pair.
    private(set) var identityMismatchDetected = false

    private let pairingService: any PairingServiceProtocol
    private let sessionStore: AppSessionStore
    private let persistence: any AppPersistenceStoreProtocol
    private let environmentProvider: @MainActor () -> AppEnvironment
    private let relayBaseURLProvider: @MainActor () -> String?
    /// Lane M: resolves a backend profile — nil argument means the ACTIVE
    /// profile. The default (always nil) is the pre-profile world: one
    /// implicit backend on the legacy credential keys, which is also what
    /// existing tests construct.
    private let profileResolver: @MainActor (UUID?) -> BackendProfile?

    /// Lane M: when set, `pair(using:)` redeems into THIS profile's slot
    /// instead of the active one (the per-profile pair flow, M-12). Survives
    /// failed attempts (a retry must keep targeting the user's pick);
    /// cleared on success and when the pairing screen is left.
    var pairingTargetProfileID: UUID?

    init(
        pairingService: any PairingServiceProtocol,
        sessionStore: AppSessionStore,
        persistence: any AppPersistenceStoreProtocol,
        environmentProvider: @escaping @MainActor () -> AppEnvironment,
        relayBaseURLProvider: @escaping @MainActor () -> String?,
        profileResolver: @escaping @MainActor (UUID?) -> BackendProfile? = { _ in nil }
    ) {
        self.pairingService = pairingService
        self.sessionStore = sessionStore
        self.persistence = persistence
        self.environmentProvider = environmentProvider
        self.relayBaseURLProvider = relayBaseURLProvider
        self.profileResolver = profileResolver
        self.pairedRelayConfiguration = persistence.loadPairedRelayConfiguration(
            profileScope: profileResolver(nil)?.credentialScopeID
        )
        self.needsPermissionsOnboarding = UserDefaults.standard.bool(forKey: Self.onboardingKey)
    }

    /// Whether the ACTIVE profile is paired — `pairedRelayConfiguration`
    /// always mirrors the active profile's slot.
    var isPaired: Bool {
        pairedRelayConfiguration != nil
    }

    /// The active profile's credential scope (nil = legacy keys — the
    /// migrated profile, or a pre-profile test construction).
    private var activeCredentialScope: UUID? {
        profileResolver(nil)?.credentialScopeID
    }

    /// Pre-unlock staleness recovery: construction during a pre-first-unlock
    /// background launch (post-reboot location relaunch) reads the persisted
    /// pairing as absent — Keychain and protected defaults are sealed — and
    /// caches nil for the process's whole lifetime, so foregrounding that
    /// same process shows NOT PAIRED even though nothing was lost. Re-read
    /// once protected data is available; assignment flips `isPaired`
    /// reactively for every observer.
    func reloadPersistedConfigurationIfNeeded() {
        guard pairedRelayConfiguration == nil else { return }
        if let restored = persistence.loadPairedRelayConfiguration(profileScope: activeCredentialScope) {
            pairedRelayConfiguration = restored
            pairingLog.notice("reload: persisted pairing recovered after protected data became available")
        }
    }

    func normalizePairingCode(_ rawCode: String) throws -> String {
        try pairingService.normalizePairingCode(rawCode)
    }

    /// Lane M (M-6): re-reads the pairing record for the newly ACTIVE
    /// profile after a switch. Identity-mismatch state is per-pairing, so it
    /// resets; `validateRestoredIdentity()` re-evaluates it once the new
    /// profile's session bootstraps.
    func rebindToActiveProfile() {
        pairedRelayConfiguration = persistence.loadPairedRelayConfiguration(profileScope: activeCredentialScope)
        identityMismatchDetected = false
        lastErrorMessage = nil
    }

    /// Lane M: fires with the profile whose relay tokens a successful pair
    /// just minted — the container stamps token freshness for M-9.
    var onProfileTokensMinted: (@MainActor (UUID?) -> Void)?

    @discardableResult
    func pair(using rawSetupCode: String) async -> Bool {
        isWorking = true
        lastErrorMessage = nil
        // Lane M: resolve the target slot up front — the active profile
        // unless a per-profile pair flow named another (M-12).
        let targetProfile = profileResolver(pairingTargetProfileID)
        let targetScope = targetProfile?.credentialScopeID
        let targetIsActive = targetProfile?.id == nil || targetProfile?.id == profileResolver(nil)?.id
        defer { isWorking = false }

        do {
            let normalizedCode = try pairingService.normalizePairingCode(rawSetupCode)
            let rawRelayBaseURL = targetProfile?.relayBaseURL ?? relayBaseURLProvider()
            guard let relayBaseURLString = RelayConfiguration.normalizeBaseURL(rawRelayBaseURL) else {
                lastErrorMessage = "Enter a valid relay URL ending with /v1 before pairing."
                return false
            }
            let request = DeviceRegistrationRequest.current(
                installationID: sessionStore.state.installationID,
                environment: environmentProvider(),
                relayBaseURLString: relayBaseURLString
            )
            let result = try await pairingService.redeemPairingCode(
                normalizedCode,
                request: request
            )

            // #3/#46: adopt the new identity on a clean slate. A reinstall can
            // resurrect a previous (possibly revoked) relay identity from the
            // Keychain — no stale credential may survive a successful re-pair.
            // Scoped to the relay identity: the Hermes API key and shim token
            // are user-entered config for the independent chat path, not
            // minted credentials, and must survive a re-pair.
            //
            // Lane M (#114): the clean slate is PER-PROFILE — redeeming into
            // profile B clears only B's prior record; every other profile's
            // pairing, tokens, and Keychain mirror stay untouched. #3's
            // protection survives within each profile (re-pairing a host
            // still wipes that host's old identity). Redeem-first ordering
            // preserved (#94): a failed redeem throws above, before anything
            // is cleared.
            await sessionStore.clearSession(credentialScope: targetScope)
            persistence.clearPairedRelayConfiguration(profileScope: targetScope)

            persistence.savePairedRelayConfiguration(result.configuration, profileScope: targetScope)
            await sessionStore.applyPairedSession(state: result.state, tokens: result.tokens, credentialScope: targetScope)
            if targetIsActive {
                identityMismatchDetected = false
                pairedRelayConfiguration = result.configuration
                setNeedsPermissionsOnboarding(true)
            }
            lastErrorMessage = nil
            pairingTargetProfileID = nil
            onProfileTokensMinted?(targetProfile?.id)
            pairingLog.notice("pair: adopted relay user \(result.state.userID?.uuidString ?? "unknown", privacy: .public) on a clean slate (profile \(targetProfile?.name ?? "default", privacy: .public))")
            if targetIsActive {
                await onPairingChanged?(true)
            }
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    func disconnect() async {
        isWorking = true
        lastErrorMessage = nil
        defer { isWorking = false }

        await sessionStore.revokeCurrentSession()
        await clearLocalPairing(notify: true)
    }

    /// Lane M (M-12): forgets ONE profile's pairing. The active profile takes
    /// the full `disconnect()` path (server-side revoke + reset notify); a
    /// dormant profile's slot is cleared locally — its relay session can't be
    /// revoked through the active bootstrap client, and a dormant forget must
    /// not log the active profile out.
    func forgetPairing(profileID: UUID) async {
        guard let profile = profileResolver(profileID) else { return }
        if profile.id == profileResolver(nil)?.id {
            await disconnect()
            return
        }
        let scope = profile.credentialScopeID
        persistence.clearPairedRelayConfiguration(profileScope: scope)
        await sessionStore.clearSession(credentialScope: scope)
        pairingLog.notice("forgetPairing: cleared dormant profile '\(profile.name, privacy: .public)'")
    }

    func completePermissionsOnboarding() {
        setNeedsPermissionsOnboarding(false)
    }

    func clearLocalPairing(notify: Bool = true) async {
        // Scoped to the ACTIVE profile (Lane M): unpairing one backend never
        // clears another's slot.
        persistence.clearPairedRelayConfiguration(profileScope: activeCredentialScope)
        pairedRelayConfiguration = nil
        lastErrorMessage = nil
        identityMismatchDetected = false
        setNeedsPermissionsOnboarding(false)
        await sessionStore.clearSession()
        if notify {
            await onPairingChanged?(false)
        }
    }

    // MARK: - Identity validation (#3/#46)

    /// The relay user this pairing minted, when known. Pairings saved before
    /// `relayUserID` existed report nil (validation degrades to a no-op until
    /// the next re-pair records it).
    var expectedRelayUserID: UUID? {
        pairedRelayConfiguration?.relayUserID
    }

    /// Compares the restored/bootstrapped session's user against the pairing's
    /// minted user. Call after a session bootstrap. A mismatch means the
    /// Keychain resurrected an identity from a previous install — the session
    /// is flagged (Diagnostics shows RE-PAIR) rather than destroyed, so the
    /// user decides when to re-pair.
    func validateRestoredIdentity() {
        guard let expected = expectedRelayUserID,
              let actual = sessionStore.state.userID else {
            identityMismatchDetected = false
            return
        }
        let mismatch = expected != actual
        if mismatch, !identityMismatchDetected {
            pairingLog.error("validateRestoredIdentity: session user \(actual.uuidString, privacy: .public) ≠ paired user \(expected.uuidString, privacy: .public) — stale Keychain identity (#3). Re-pair required.")
        }
        identityMismatchDetected = mismatch
    }

    private func setNeedsPermissionsOnboarding(_ value: Bool) {
        needsPermissionsOnboarding = value
        UserDefaults.standard.set(value, forKey: Self.onboardingKey)
    }
}
