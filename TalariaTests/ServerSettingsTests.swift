import Foundation
import Testing
@testable import Talaria

/// Lane M PR 3 (OPEN_ITEMS #114): the Server settings surface — activation
/// flow, the unkeyed-profile nudge (M-14), the profile editor draft, probe
/// classification, and the hosted-relay retirement's decode compatibility
/// (M-13).
///
/// **#309 Lane B (2026-08-25):** the per-profile FORGET PAIRING section is
/// tombstoned in place with its property's new home named, and the editor
/// draft lost its relay field with `BackendProfile.relayBaseURL`.
@Suite(.serialized)
struct ServerSettingsTests {

    @MainActor
    private func makePersistence(_ label: String) -> UserDefaultsAppPersistenceStore {
        let suiteName = "server-settings-\(label)-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsAppPersistenceStore(defaults: defaults)
    }

    private static let ojamdSeeds = BackendProfilesStore.MigrationSeeds(
        gatewayBaseURL: "http://ojamd:8642",
        shimBaseURL: "http://ojamd:8765"
    )

    // MARK: - M-17: activation flow

    @Test @MainActor
    func activationSwitchesActiveProfileAndFiresCallbackOnce() async throws {
        let persistence = makePersistence("activation")
        let profilesStore = BackendProfilesStore(persistence: persistence, migrationSeeds: Self.ojamdSeeds)
        let ojamd = try #require(profilesStore.activeProfile)
        let mac = BackendProfile(name: "Mac Mini", gatewayBaseURL: "http://macmini:8642")
        profilesStore.upsert(mac)

        var activated: [BackendProfile] = []
        profilesStore.onActiveProfileChanged = { activated.append($0) }

        let switched = profilesStore.setActiveProfile(mac.id)
        #expect(switched)
        #expect(profilesStore.activeProfileID == mac.id)

        // Re-activating the already-active profile is a no-op.
        let reactivated = profilesStore.setActiveProfile(mac.id)
        #expect(reactivated == false)
        // Unknown ids are refused.
        let unknown = profilesStore.setActiveProfile(UUID())
        #expect(unknown == false)

        // The callback fires as a Task — drain the main queue.
        for _ in 0..<10 { await Task.yield() }
        #expect(activated.map(\.id) == [mac.id])

        // Persisted: a reloaded store sees the switch.
        let reloaded = BackendProfilesStore(persistence: persistence, migrationSeeds: Self.ojamdSeeds)
        #expect(reloaded.activeProfileID == mac.id)
        #expect(reloaded.profile(id: ojamd.id) != nil)
    }

    // MARK: - M-12: per-profile forget hygiene — TOMBSTONED 2026-08-25
    //
    // **#309 Lane B deleted `PairingStore.forgetPairing` and the FORGET
    // PAIRING row it backed**, so `forgettingDormantProfilePairingLeavesActiveProfileIntact`
    // has no subject. The row was already living on borrowed time: Lane C
    // found it could only be offered on profiles that still held a relay-era
    // pairing RECORD, and offering it anywhere else would have been a button
    // that silently did nothing.
    //
    // **Its property survives in two places, both stronger.** Per-scope
    // credential isolation is `theRelayResiduePurgeIsScopedAndDoesNotWiden`
    // (BackendProfilesTests), which additionally proves the sweep does not
    // widen onto the gateway key. And "forgetting one host leaves the others
    // alone" is `ConnectHostTests`'
    // `disconnectClearsOnlyTheTargetProfilesCredentials`.


    // MARK: - M-14: unkeyed-profile nudge

    /// **#309 Lane C re-keyed the first argument** (`isPaired` →
    /// `hasGatewayEndpoint`). The truth table is unchanged and deliberately
    /// so — this is the same rule about the same user-visible notice — but the
    /// left-hand fact is now "the profile names a gateway", not "the profile
    /// holds a relay pairing". Re-homing it onto gateway CREDENTIALS instead
    /// would have made the rule vacuous: credentials include the key, so
    /// `hasGatewayCredentials && key.isEmpty` is false by construction and the
    /// notice could never render. That is why this test keeps a two-fact
    /// signature rather than collapsing to one.
    @Test @MainActor
    func unkeyedNudgeShowsOnlyForProfilesWithAGatewayAndNoKey() {
        #expect(UplinkSettingsScreen.unkeyedNudgeVisible(hasGatewayEndpoint: true, apiKey: ""))
        #expect(UplinkSettingsScreen.unkeyedNudgeVisible(hasGatewayEndpoint: true, apiKey: "   "))
        #expect(UplinkSettingsScreen.unkeyedNudgeVisible(hasGatewayEndpoint: true, apiKey: "abc123") == false)
        #expect(UplinkSettingsScreen.unkeyedNudgeVisible(hasGatewayEndpoint: false, apiKey: "") == false)
        #expect(UplinkSettingsScreen.unkeyedNudgeVisible(hasGatewayEndpoint: false, apiKey: "abc123") == false)
    }

    // MARK: - #151: Test Connection verdicts

    /// The verdict defers to `ServerProbeResult.classify`, so the Uplink and
    /// Server screens can never disagree about what a 401 means.
    @Test @MainActor
    func testConnectionVerdictJoinsTheSharedProbeVocabulary() {
        #expect(UplinkSettingsScreen.outcome(statusCode: 200, latencyMillis: 42) == .passed(latencyMillis: 42))
        #expect(UplinkSettingsScreen.outcome(statusCode: 204, latencyMillis: 7) == .passed(latencyMillis: 7))
        #expect(UplinkSettingsScreen.outcome(statusCode: 401, latencyMillis: 9) == .failed(.authRejected))
        #expect(UplinkSettingsScreen.outcome(statusCode: 403, latencyMillis: 9) == .failed(.authRejected))
        #expect(UplinkSettingsScreen.outcome(statusCode: 404, latencyMillis: 9) == .failed(.unexpectedStatus(404)))
        #expect(UplinkSettingsScreen.outcome(statusCode: 502, latencyMillis: 9) == .failed(.unexpectedStatus(502)))
        // "NO KEY" is the Server screen's word for the same condition.
        #expect(ConnectionTestFailure.authRejected.label == ServerProbeResult.unauthorized.label)
    }

    /// #145/#136 named three distinct network shapes. A control that
    /// collapsed them into one "failed" is what made the old button useless.
    @Test @MainActor
    func testConnectionDistinguishesTheThreeNetworkShapes() {
        #expect(UplinkSettingsScreen.failure(for: .cannotConnectToHost) == .refused)
        #expect(UplinkSettingsScreen.failure(for: .timedOut) == .timedOut)
        #expect(UplinkSettingsScreen.failure(for: .cannotFindHost) == .hostNotFound)
        #expect(UplinkSettingsScreen.failure(for: .dnsLookupFailed) == .hostNotFound)

        // Each shape names a different fix — the labels and the remedies
        // must not converge.
        let shapes: [ConnectionTestFailure] = [.refused, .timedOut, .hostNotFound, .authRejected]
        #expect(Set(shapes.map(\.label)).count == shapes.count)
        #expect(Set(shapes.map(\.detail)).count == shapes.count)
    }

    /// The Sessions client stamps `timeoutInterval = 300` on every request, so
    /// reusing its health path here would hang the button for five minutes
    /// against a black-holed host — its own defect.
    @Test @MainActor
    func testConnectionProbeUsesItsOwnShortBudget() {
        #expect(UplinkSettingsScreen.probeTimeout == 5)
    }

    @Test @MainActor
    func testConnectionReportsAnUnsetEndpointWithoutTouchingTheNetwork() async {
        let blank = await UplinkSettingsScreen.probe(baseURL: "   ", apiKey: "key")
        guard case .failed(.notConfigured) = blank else {
            Issue.record("an empty base URL should fail as notConfigured — got \(blank)")
            return
        }
    }

    // MARK: - M-12: profile editor draft

    @Test @MainActor
    func profileEditorDraftValidatesEndpointsAndAppliesPreservingIdentity() {
        var draft = ProfileEditorDraft()
        #expect(draft.validationMessage != nil) // no name

        draft.name = "Mac Mini"
        #expect(draft.validationMessage != nil) // no gateway

        draft.gatewayBaseURL = "macmini:8642"
        #expect(draft.validationMessage != nil) // not absolute http(s)

        draft.gatewayBaseURL = "http://100.79.222.100:8642"
        #expect(draft.isValid)

        draft.note = "  Apple ecosystem  "
        #expect(draft.isValid)

        // Applying onto an existing profile preserves identity + scope.
        let existing = BackendProfile(
            name: "Old", gatewayBaseURL: "http://old:8642",
            usesLegacyCredentialKeys: true
        )
        let updated = draft.apply(to: existing)
        #expect(updated.id == existing.id)
        #expect(updated.usesLegacyCredentialKeys)
        #expect(updated.name == "Mac Mini")
        // #223 Lane 5: the editor no longer touches shimBaseURL — an existing
        // profile's stored value survives apply() untouched.
        #expect(updated.shimBaseURL == existing.shimBaseURL)
        #expect(updated.note == "Apple ecosystem")

        // A fresh apply mints a new, non-legacy profile.
        let minted = draft.apply(to: nil)
        #expect(minted.id != existing.id)
        #expect(minted.usesLegacyCredentialKeys == false)
    }

    // MARK: - M-12: probe classification

    @Test @MainActor
    func probeClassificationMapsStatusCodesHonestly() {
        #expect(ServerProbeResult.classify(statusCode: 200) == .online)
        #expect(ServerProbeResult.classify(statusCode: 204) == .online)
        #expect(ServerProbeResult.classify(statusCode: 401) == .unauthorized)
        #expect(ServerProbeResult.classify(statusCode: 403) == .unauthorized)
        #expect(ServerProbeResult.classify(statusCode: 404) == .offline)
        #expect(ServerProbeResult.classify(statusCode: 500) == .offline)
        #expect(ServerProbeResult.unknown.label == "—")
    }

    // #251-2A's token-only PLUGIN LINK pin lived here until #269-A replaced
    // the mechanism: the row now composes a live probe with the credential,
    // and every behavior (including the empty-string-is-not-a-token rule)
    // is pinned in TalariaLinkObservationTests.

    // MARK: - M-13: hosted-relay retirement decode compatibility — TOMBSTONED
    //
    // **#309 Lane B deleted `RelayConfiguration`**, so
    // `legacyRelayConfigurationBlobsDecodeWithHostedKeysIgnored` has no type
    // to decode into. It proved a pre-Lane-M blob's dead `relayMode` /
    // `hostedRelay*` keys were ignored rather than fatal.
    //
    // **The property it guarded is now stronger and lives one level up.** The
    // whole struct is a dead key on `UserSettings` — `init(from:)` never asks
    // for `relayConfiguration` — so the tolerance is structural rather than
    // per-field, and it is pinned where it can actually fail:
    // `aLegacyUserSettingsBlobWithARelayConfigurationStillDecodes` below.

    /// **#309 Lane B's replacement for the M-13 decode pin.** Every settings
    /// blob on every device carries `relayConfiguration`; a decoder that
    /// choked on it would read as "no settings" and silently reset the user's
    /// preferences on the first launch after the update.
    ///
    /// RED against `main`: there, the key is decoded into a real property.
    @Test @MainActor
    func aLegacyUserSettingsBlobWithARelayConfigurationStillDecodes() throws {
        let legacyJSON = """
        {
            "environment": "production",
            "verboseLogging": true,
            "relayConfiguration": {
                "relayMode": "hosted",
                "customRelayBaseURL": "http://ojamd:8000/v1",
                "hostedRelayEnabled": true
            }
        }
        """
        let decoded = try JSONDecoder().decode(UserSettings.self, from: Data(legacyJSON.utf8))
        #expect(decoded.verboseLogging, "the blob's real settings must survive the dead key")

        // …and the dead key does not come back on the next save.
        let reEncoded = try JSONEncoder().encode(decoded)
        let json = try #require(try JSONSerialization.jsonObject(with: reEncoded) as? [String: Any])
        #expect(json["relayConfiguration"] == nil)
    }
}
