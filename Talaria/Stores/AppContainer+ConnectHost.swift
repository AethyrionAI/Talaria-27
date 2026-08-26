import Foundation
import os

/// **What a push onto `.connectHost` decided, frozen at the tap.**
///
/// 🔴 **`startsInWizard` is snapshotted here on purpose, and the alternative
/// is a measured defect.** The obvious shape — let `ContentView` derive
/// wizard-vs-screen from `hasGatewayCredentials` — puts an OBSERVABLE
/// predicate inside `navigationDestination`'s builder, so the moment the
/// wizard's own commit writes the credentials, SwiftUI re-evaluates the
/// destination and swaps the wizard out for the Settings screen. The user
/// never sees the green card or step 3; the flow ends by silently becoming a
/// different screen.
///
/// It was written that way first and `testConnectingAHostViaSettingsEntryPoint
/// LandsBackInChat` failed on it — a UI journey catching what no unit test
/// could, because the defect lives in the navigation graph rather than in any
/// one view. Freezing the decision at the push makes the destination a pure
/// function of the route, which is the only shape that cannot flip.
struct ConnectHostEntry: Hashable, Sendable {
    /// `nil` means the ACTIVE profile — every entry point except the Server
    /// screen's per-profile row.
    let profileID: UUID?
    /// True when this push should present the wizard (no host yet).
    let startsInWizard: Bool
    /// **Design B3's "Add another host" — MINT a profile rather than fill the
    /// active one.** Without this the roster's add button resolved to
    /// `.activeProfile` (a nil `profileID` means "the active one" everywhere
    /// else) and adding a second host would have overwritten the first.
    var mintsNewHost: Bool = false

    var target: ConnectHostTarget {
        if mintsNewHost { return .newHost }
        guard let profileID else { return .activeProfile }
        return .profile(profileID)
    }
}

/// Which profile a Connect Host flow is about to write into.
enum ConnectHostTarget: Equatable, Sendable, Hashable {
    /// The profile the app is currently using — the ordinary case, and the one
    /// a fresh install takes: #384 ships no default host, so the seeded profile
    /// carries an EMPTY `gatewayBaseURL` until this flow fills it.
    case activeProfile
    /// A named profile — the roster's per-host edit (design B3).
    case profile(UUID)
    /// Mint a new profile and make it active — design B3's "Add another host".
    case newHost
}

/// The last thing this screen actually MEASURED.
///
/// Held for the life of the Connect Host surface rather than persisted, and
/// that is the honest scope: after a cold launch the app genuinely does not
/// know whether the stored host is up, and `notChecked` says so until
/// something asks. Persisting a latency across launches would let the card
/// print a number nothing had re-measured — #350's defect with extra steps.
@MainActor
final class ConnectHostMeasurement {
    var modelsSeen: Int?
    var latencyMilliseconds: Int?
    var reachability: ConnectHostRosterEntry.Reachability = .notChecked
    var lastAnsweredAt: Date?
    /// **Which profile the commit actually wrote.** Only `.newHost` needs it,
    /// and it needs it badly: that target resolves to no profile BEFORE a
    /// commit (correctly — "Add another host" must show the empty form, not
    /// the active host's card) and must resolve to the minted one AFTER.
    /// Without this the wizard's step 2 rendered nothing at all on the
    /// add-a-second-host path.
    var committedProfileID: UUID?

    func record(_ outcome: HostProbeOutcome, at date: Date = .now) {
        latencyMilliseconds = outcome.latencyMilliseconds
        switch outcome {
        case .connected(let ms, let models):
            modelsSeen = models
            reachability = .reachable(milliseconds: ms)
            lastAnsweredAt = date
        case .keyRefused(let ms), .notHermes(let ms):
            // Something answered — that IS reachability, and conflating it
            // with "down" is what sends a user to check their network over a
            // mistyped key.
            reachability = .reachable(milliseconds: ms)
            lastAnsweredAt = date
        case .noAnswer:
            reachability = .noAnswer
        }
    }
}

extension AppContainer {

    private static let connectHostLogger = Logger(
        subsystem: TalariaLog.subsystem, category: "ConnectHost")

    /// The push a Connect Host entry point makes. Reads the predicate ONCE,
    /// here, where it is a fact about the moment the user tapped.
    ///
    /// `profileID == nil` resolves the active profile; a fresh install with no
    /// profile at all has no host either, so it starts in the wizard.
    func connectHostEntry(profileID: UUID? = nil) -> ConnectHostEntry {
        let resolved = profileID ?? profilesStore?.activeProfileID
        let hasHost = resolved.map { hasGatewayCredentials(forProfileID: $0) } ?? false
        return ConnectHostEntry(profileID: profileID, startsInWizard: !hasHost)
    }

    /// #127's classification, on the same frozen fact — a profile that already
    /// holds a host is an existing connection and fails OPEN.
    func connectAttempt(for entry: ConnectHostEntry) -> ConnectAttempt {
        entry.startsInWizard ? .newConnect : .existingPairing
    }

    /// Builds the Connect Host state machine's world.
    ///
    /// **Everything that WRITES is behind `commit`,** which `ConnectHostModel`
    /// calls on exactly one path — a green probe (bar 309-B4). The reads are
    /// deliberately live closures rather than snapshots so a profile switch
    /// underneath the screen re-renders it against the new profile.
    func makeConnectHostEnvironment(
        target: ConnectHostTarget = .activeProfile,
        measurement: ConnectHostMeasurement = ConnectHostMeasurement()
    ) -> ConnectHostModel.Environment {
        ConnectHostModel.Environment(
            probe: { [weak self] gatewayBaseURL, apiKey in
                // The UI-test arm, and it is the direct heir of
                // `MockPairingService`: under the test doubles any well-formed
                // pair of values connects, because a UITest has no host to
                // reach and the journey under test is the FLOW, not the wire.
                // The wire is `ConnectHostProbeTests`' subject, on stubs that
                // can fail four different ways.
                if self?.usesMockServices == true {
                    return .connected(latencyMilliseconds: 18, modelsSeen: 3)
                }
                return await GatewayHermesHostService.probeCandidateHost(
                    gatewayBaseURL: gatewayBaseURL, apiKey: apiKey
                )
            },
            commit: { [weak self] draft, outcome in
                guard let self else { return }
                measurement.record(outcome)
                measurement.committedProfileID =
                    await self.commitConnectHost(draft: draft, target: target)
            },
            currentHost: { [weak self] in
                self?.connectedHost(target: target, measurement: measurement)
            },
            roster: { [weak self] in
                self?.connectHostRoster(measurement: measurement) ?? []
            },
            recheckCommitted: { [weak self] in
                guard let self else { return .noAnswer(detail: "NO ANSWER") }
                let outcome = await self.recheckConnectedHost(
                    target: target, measurement: measurement)
                measurement.record(outcome)
                return outcome
            },
            disconnect: { [weak self] in
                guard let self else { return .forgottenHostNotTold }
                let outcome = await self.disconnectConnectedHost(
                    target: target, measurement: measurement)
                measurement.reachability = .notChecked
                measurement.modelsSeen = nil
                measurement.lastAnsweredAt = nil
                measurement.committedProfileID = nil
                return outcome
            },
            activate: { [weak self] profileID in
                self?.profilesStore?.setActiveProfile(profileID)
            }
        )
    }

    // MARK: The one write path

    /// Persists a probed-good host. Called ONLY from `commit` above. Returns
    /// the profile it wrote, which is the only way a `.newHost` flow can name
    /// the profile it just minted.
    @discardableResult
    private func commitConnectHost(
        draft: ConnectHostModel.Draft, target: ConnectHostTarget
    ) async -> UUID? {
        guard let profilesStore else { return nil }

        let existing: BackendProfile?
        switch target {
        case .activeProfile: existing = profilesStore.activeProfile
        case .profile(let id): existing = profilesStore.profile(id: id)
        case .newHost: existing = nil
        }

        var profile = existing ?? BackendProfile(name: draft.resolvedName, gatewayBaseURL: "")
        profile.name = draft.resolvedName
        profile.gatewayBaseURL = draft.trimmedGateway
        profilesStore.upsert(profile)
        await saveGatewayAPIKey(draft.trimmedKey, for: profile)
        if profilesStore.activeProfileID != profile.id {
            profilesStore.setActiveProfile(profile.id)
        }
        Self.connectHostLogger.notice(
            "commit: host '\(profile.name, privacy: .public)' saved after a green check")
        // The lifecycle transition #136's reset-race tests pin: a launch that
        // had no host to talk to has host-backed work to redo. Same seam the
        // relay redeem used, reached from the one place a host can now appear.
        //
        // **NOT AWAITED, and that is Lane C's judgement applied again.**
        // `handleHostConnected()` runs `initialize()`, whose host-backed half
        // is network work; awaiting it here would park the wizard on its
        // spinner for as long as the new host takes to answer — and the phone
        // has just proved the host answers, so there is nothing to wait FOR.
        // The credentials are already persisted above; everything downstream
        // is a refresh. (#365's stall, one door further along.)
        Task { @MainActor [weak self] in await self?.handleHostConnected() }
        return profile.id
    }

    /// The wizard's "Name this host" field, and the only write the flow makes
    /// after the commit. A label is not a credential: renaming touches the
    /// profile's `name` and nothing else, so it cannot un-connect a host.
    func renameConnectedHost(to rawName: String, target: ConnectHostTarget) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let profilesStore else { return }
        let resolved: BackendProfile?
        switch target {
        case .activeProfile, .newHost: resolved = profilesStore.activeProfile
        case .profile(let id): resolved = profilesStore.profile(id: id)
        }
        guard var profile = resolved, profile.name != name else { return }
        profile.name = name
        profilesStore.upsert(profile)
    }

    // MARK: Reads

    private func resolvedProfile(
        for target: ConnectHostTarget, measurement: ConnectHostMeasurement? = nil
    ) -> BackendProfile? {
        switch target {
        case .activeProfile: profilesStore?.activeProfile
        case .profile(let id): profilesStore?.profile(id: id)
        // `nil` until this flow's own commit names one — see
        // `ConnectHostMeasurement.committedProfileID`.
        case .newHost: measurement?.committedProfileID.flatMap { profilesStore?.profile(id: $0) }
        }
    }

    /// The connected-host card's data — or `nil`, which is the EMPTY state and
    /// not an error (design A1).
    private func connectedHost(
        target: ConnectHostTarget,
        measurement: ConnectHostMeasurement
    ) -> ConnectedHost? {
        guard let profile = resolvedProfile(for: target, measurement: measurement),
              profile.hasGateway else { return nil }
        let hasKey = hasGatewayCredentials(forProfileID: profile.id)

        // The standing host refresh is the app's OTHER measurement of the same
        // fact; take whichever is real, and `notChecked` when neither is.
        var reachability = measurement.reachability
        var lastAnswered = measurement.lastAnsweredAt
        if profile.id == profilesStore?.activeProfileID {
            switch hostStore.connectionState {
            case .online:
                reachability = .reachable(milliseconds: measurement.latencyMilliseconds)
                lastAnswered = hostStore.currentHost?.lastSeenAt ?? lastAnswered
            case .unreachable, .offline:
                if case .notChecked = reachability { reachability = .noAnswer }
            case .notConnected, .checking:
                break
            }
        }

        return ConnectedHost(
            profileID: profile.id,
            name: profile.name,
            address: Self.displayAddress(profile.gatewayBaseURL),
            hasStoredKey: hasKey,
            lastAnsweredAt: lastAnswered,
            modelsSeen: measurement.modelsSeen,
            reachability: reachability
        )
    }

    /// Design B3's list. Only the ACTIVE profile can carry a measurement here
    /// — the others honestly read NOT CHECKED, because nothing has asked them.
    private func connectHostRoster(measurement: ConnectHostMeasurement) -> [ConnectHostRosterEntry] {
        guard let profilesStore else { return [] }
        let activeID = profilesStore.activeProfileID
        return profilesStore.profiles.map { profile in
            ConnectHostRosterEntry(
                id: profile.id,
                name: profile.name,
                address: Self.displayAddress(profile.gatewayBaseURL),
                isActive: profile.id == activeID,
                keyState: hasGatewayCredentials(forProfileID: profile.id) ? .stored : .missing,
                reachability: profile.id == activeID ? measurement.reachability : .notChecked
            )
        }
    }

    /// "Check now" on the resting card: re-measures with the STORED key, which
    /// this model never sees.
    private func recheckConnectedHost(
        target: ConnectHostTarget, measurement: ConnectHostMeasurement
    ) async -> HostProbeOutcome {
        guard let profile = resolvedProfile(for: target, measurement: measurement),
              profile.hasGateway else {
            return .noAnswer(detail: "NO ANSWER")
        }
        let key = await gatewayAPIKey(for: profile) ?? ""
        let outcome = await GatewayHermesHostService.probeCandidateHost(
            gatewayBaseURL: profile.gatewayBaseURL, apiKey: key
        )
        // Keep the app's standing host state in step with what the user just
        // watched happen — two surfaces disagreeing about one host is the
        // failure #180 registers.
        await hostStore.refresh()
        return outcome
    }

    // MARK: Disconnect — both halves (bar 309-B6)

    /// Tells the host first, forgets locally second, and reports which of the
    /// two actually happened.
    ///
    /// **The order is the mechanism.** The plugin's `unpair` verb is authorised
    /// by the device token this same call is about to delete, so the POST has
    /// to go out while the credential still exists. There is no deferred
    /// retry: a queue would have to RETAIN the credentials the card promises to
    /// remove, which is why the unreachable case gets honest copy instead
    /// (`ConnectHostCopy.disconnectRowBlurbUnreachable`).
    private func disconnectConnectedHost(
        target: ConnectHostTarget, measurement: ConnectHostMeasurement
    ) async -> HostDisconnectOutcome {
        guard let profile = resolvedProfile(for: target, measurement: measurement)
        else { return .forgottenHostNotTold }
        // The link resolves its credentials through the ACTIVE profile's scope
        // (#285's frozen turn context), so a dormant profile's host cannot be
        // told from here — and the copy says so rather than the code
        // pretending. Disconnecting a dormant host is a switch away.
        let isActive = profile.id == profilesStore?.activeProfileID
        let told = isActive ? await (talariaPlatformLink?.unpairFromHost() ?? false) : false
        await forgetHostCredentials(for: profile)
        if isActive { await handleHostDisconnected() }
        Self.connectHostLogger.notice(
            "disconnect: local forget done; host told = \(told, privacy: .public)")
        return told ? .forgottenAndHostTold : .forgottenHostNotTold
    }

    /// Clears BOTH credential families for one profile — the gateway key the
    /// chat plane uses and the talaria device token/id the plugin link mints —
    /// **and the ADDRESS with them.**
    ///
    /// 🔴 **The address goes because the card says it does.** Design B4's first
    /// bullet is *"This phone forgets the address and key"*, and an earlier
    /// draft of this method kept the endpoint on the theory that "a profile
    /// with an address and no key is an honest HOST SET — KEY MISSING". It is
    /// honest, and it is not what the user was told, and it leaves the Connect
    /// Host screen resting on a half-configured card forever instead of on the
    /// empty state that names the local brain. The UI journey caught it: after
    /// a disconnect the screen never returned to A1.
    ///
    /// The PROFILE survives — it is the container the credentials are scoped
    /// to, and removing it is the Server screen's louder, separately-confirmed
    /// Delete.
    private func forgetHostCredentials(for profile: BackendProfile) async {
        if let profilesStore {
            var cleared = profile
            cleared.gatewayBaseURL = ""
            profilesStore.upsert(cleared)
        }
        // The gateway key rides `saveGatewayAPIKey("")` rather than a raw
        // delete: that path also clears the in-memory box and the per-profile
        // cache the chat client reads synchronously, so a forgotten host stops
        // being routable in the same turn rather than at the next launch.
        await saveGatewayAPIKey("", for: profile)
        guard let secureStore else { return }
        let scope = profile.credentialScopeID
        for key in Self.disconnectClearedKeys(scope: scope) {
            await secureStore.delete(key: key)
        }
        hostStore.reset()
    }

    /// **What Disconnect clears, as DATA rather than as three statements.**
    ///
    /// Every entry is derived from the target scope, which is what makes the
    /// #94/#3 per-profile isolation structural: there is no way to name
    /// another profile's slot from here. A test proves both halves of the set
    /// — that it covers BOTH credential families (the gateway key the chat
    /// plane uses and the plugin link's device token/id, whose surviving half
    /// would re-pair this phone to a host it just left), and that it does not
    /// widen onto `shimToken` or the durable installation identity.
    // harness-visible
    static func disconnectClearedKeys(scope: UUID?) -> [String] {
        [
            BackendProfileScopedKeys.gatewayAPIKey(scope),
            BackendProfileScopedKeys.talariaDeviceToken(scope),
            BackendProfileScopedKeys.talariaDeviceID(scope),
        ]
    }

    /// `100.110.102.59:8642` — what the card prints. The scheme is dropped
    /// because every one of these is http over the tailnet and the prefix is
    /// noise; the raw string is used verbatim when it will not parse, so a
    /// weird address is shown as typed rather than mangled.
    // harness-visible
    static func displayAddress(_ gatewayBaseURL: String) -> String {
        let trimmed = gatewayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let host = url.host, !host.isEmpty else {
            return trimmed
        }
        if let port = url.port { return "\(host):\(port)" }
        return host
    }
}
