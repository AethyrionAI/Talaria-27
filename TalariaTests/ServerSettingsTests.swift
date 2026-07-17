import Foundation
import Testing
@testable import Talaria

/// Lane M PR 3 (OPEN_ITEMS #114): the Server settings surface — activation
/// flow, per-profile pairing hygiene, the unkeyed-profile nudge (M-14), the
/// profile editor draft, probe classification, and the hosted-relay
/// retirement's decode compatibility (M-13).
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
        relayBaseURL: "http://ojamd:8000/v1",
        shimBaseURL: "http://ojamd:8765"
    )

    // MARK: - M-17: activation flow

    @Test @MainActor
    func activationSwitchesActiveProfileAndFiresCallbackOnce() async throws {
        let persistence = makePersistence("activation")
        let profilesStore = BackendProfilesStore(persistence: persistence, migrationSeeds: Self.ojamdSeeds)
        let ojamd = try #require(profilesStore.activeProfile)
        let mac = BackendProfile(name: "Mac Mini", gatewayBaseURL: "http://macmini:8642", relayBaseURL: "http://macmini:8000/v1")
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

    // MARK: - M-12: per-profile forget hygiene

    @Test @MainActor
    func forgettingDormantProfilePairingLeavesActiveProfileIntact() async throws {
        let persistence = makePersistence("forget")
        let secureStore = MockSecureStore()
        let profilesStore = BackendProfilesStore(persistence: persistence, migrationSeeds: Self.ojamdSeeds)
        let mac = BackendProfile(name: "Mac Mini", gatewayBaseURL: "http://macmini:8642", relayBaseURL: "http://macmini:8000/v1")
        profilesStore.upsert(mac)

        let sessionStore = AppSessionStore(
            bootstrapService: MockSessionBootstrapService(),
            syncCoordinator: MockSyncCoordinator(),
            secureStore: secureStore,
            persistence: persistence,
            notificationService: MockNotificationService(),
            environmentProvider: { .production },
            credentialScopeProvider: { profilesStore.activeProfile?.credentialScopeID }
        )
        let pairingStore = PairingStore(
            pairingService: MockPairingService(),
            sessionStore: sessionStore,
            persistence: persistence,
            environmentProvider: { .production },
            relayBaseURLProvider: { profilesStore.activeProfile?.relayBaseURL },
            profileResolver: { id in profilesStore.resolvedProfile(id: id) }
        )

        // Seed BOTH slots as paired: OJAMD (active, legacy scope) + Mac.
        let ojamdConfig = PairedRelayConfiguration(
            baseURLString: "http://ojamd:8000/v1", hostDisplayName: "ojamd", pairedAt: Date(timeIntervalSince1970: 1_752_600_000), relayUserID: UUID()
        )
        persistence.savePairedRelayConfiguration(ojamdConfig, profileScope: nil)
        await secureStore.store(key: "session.accessToken", value: "ojamd-token")
        let macScope = try #require(mac.credentialScopeID)
        persistence.savePairedRelayConfiguration(
            PairedRelayConfiguration(baseURLString: "http://macmini:8000/v1", hostDisplayName: "mac", pairedAt: Date(timeIntervalSince1970: 1_752_600_000), relayUserID: UUID()),
            profileScope: macScope
        )
        await secureStore.store(key: BackendProfileScopedKeys.accessToken(macScope), value: "mac-token")
        pairingStore.rebindToActiveProfile()
        #expect(pairingStore.isPaired)

        // Forget the DORMANT Mac pairing.
        await pairingStore.forgetPairing(profileID: mac.id)

        // Mac's slot is gone…
        #expect(persistence.loadPairedRelayConfiguration(profileScope: macScope) == nil)
        let macToken = await secureStore.retrieve(key: BackendProfileScopedKeys.accessToken(macScope))
        #expect(macToken == nil)
        // …and the ACTIVE profile is completely untouched.
        #expect(pairingStore.isPaired)
        #expect(persistence.loadPairedRelayConfiguration(profileScope: nil) == ojamdConfig)
        let ojamdToken = await secureStore.retrieve(key: "session.accessToken")
        #expect(ojamdToken == "ojamd-token")
    }

    // MARK: - M-14: unkeyed-profile nudge

    @Test @MainActor
    func unkeyedNudgeShowsOnlyForPairedProfilesWithoutAKey() {
        #expect(UplinkSettingsScreen.unkeyedNudgeVisible(isPaired: true, apiKey: ""))
        #expect(UplinkSettingsScreen.unkeyedNudgeVisible(isPaired: true, apiKey: "   "))
        #expect(UplinkSettingsScreen.unkeyedNudgeVisible(isPaired: true, apiKey: "abc123") == false)
        #expect(UplinkSettingsScreen.unkeyedNudgeVisible(isPaired: false, apiKey: "") == false)
        #expect(UplinkSettingsScreen.unkeyedNudgeVisible(isPaired: false, apiKey: "abc123") == false)
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
        #expect(draft.isValid) // relay + shim are optional

        draft.relayBaseURL = "not a url"
        #expect(draft.validationMessage != nil)
        draft.relayBaseURL = "http://100.79.222.100:8000"
        #expect(draft.isValid) // normalizes to …/v1 on apply

        draft.shimBaseURL = "100.79.222.100:8765"
        #expect(draft.validationMessage != nil)
        draft.shimBaseURL = "http://100.79.222.100:8765"
        draft.note = "  Apple ecosystem  "
        #expect(draft.isValid)

        // Applying onto an existing profile preserves identity + scope.
        let existing = BackendProfile(
            name: "Old", gatewayBaseURL: "http://old:8642", relayBaseURL: "",
            usesLegacyCredentialKeys: true
        )
        let updated = draft.apply(to: existing)
        #expect(updated.id == existing.id)
        #expect(updated.usesLegacyCredentialKeys)
        #expect(updated.name == "Mac Mini")
        #expect(updated.relayBaseURL == "http://100.79.222.100:8000/v1")
        #expect(updated.shimBaseURL == "http://100.79.222.100:8765")
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

    // MARK: - #116: honest two-step shim probe

    @Test @MainActor
    func shimProbeClassificationIsHonestAboutAuth() {
        // No HTTP answer from /healthz at all → offline.
        #expect(ServerProbeResult.classifyShimProbe(healthzStatus: nil, authedStatus: nil) == .offline)
        // /healthz answered but unhealthy → its status decides.
        #expect(ServerProbeResult.classifyShimProbe(healthzStatus: 500, authedStatus: nil) == .offline)
        // THE #116 fix: /healthz green + authed call refused = answering but
        // unkeyed — NO KEY, never the old always-green healthz dot.
        #expect(ServerProbeResult.classifyShimProbe(healthzStatus: 200, authedStatus: 401) == .unauthorized)
        #expect(ServerProbeResult.classifyShimProbe(healthzStatus: 200, authedStatus: 403) == .unauthorized)
        // Healthy AND the token works → online.
        #expect(ServerProbeResult.classifyShimProbe(healthzStatus: 200, authedStatus: 200) == .online)
        // Healthy /healthz but the authed call died or errored → offline,
        // not a fake green.
        #expect(ServerProbeResult.classifyShimProbe(healthzStatus: 200, authedStatus: nil) == .offline)
        #expect(ServerProbeResult.classifyShimProbe(healthzStatus: 200, authedStatus: 500) == .offline)
    }

    // MARK: - M-13: hosted-relay retirement decode compatibility

    @Test @MainActor
    func legacyRelayConfigurationBlobsDecodeWithHostedKeysIgnored() throws {
        // A pre-Lane-M persisted blob: relayMode + hosted keys present.
        let legacyJSON = """
        {
            "relayMode": "hosted",
            "customRelayBaseURL": "http://ojamd:8000/v1",
            "hostedRelayBaseURL": "https://hosted.example.com/v1",
            "hostedRelayEnabled": true
        }
        """
        let decoded = try JSONDecoder().decode(RelayConfiguration.self, from: Data(legacyJSON.utf8))
        #expect(decoded.customRelayBaseURL == "http://ojamd:8000/v1")
        #expect(decoded.activeBaseURLString == "http://ojamd:8000/v1")

        // Round-trips cleanly through the new shape.
        let reEncoded = try JSONEncoder().encode(decoded)
        let reDecoded = try JSONDecoder().decode(RelayConfiguration.self, from: reEncoded)
        #expect(reDecoded == decoded)
    }
}
