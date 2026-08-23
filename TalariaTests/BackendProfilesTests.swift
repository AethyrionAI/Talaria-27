import Foundation
import Testing
@testable import Talaria

/// Lane M PR 1 (OPEN_ITEMS #114): backend-profile model, one-shot migration,
/// and the per-profile clean-slate surgery on `PairingStore.pair()` (#94/#3).
@Suite(.serialized)
struct BackendProfilesTests {

    // MARK: - Fixtures

    @MainActor
    private func makePersistence(_ label: String) -> UserDefaultsAppPersistenceStore {
        let suiteName = "backend-profiles-\(label)-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsAppPersistenceStore(defaults: defaults)
    }

    /// #310: persistence for tests whose subject is the RELAY PLANE (pairing,
    /// tokens, the #94/#3 clean slate) rather than the retirement itself.
    ///
    /// Stamping the relay-retirement migration as already run means the M-2
    /// seed keeps its relay URL, so `pair()` has a relay to redeem against.
    /// Without this the three pairing tests below fail at
    /// "Enter a valid relay URL ending with /v1 before pairing" — a true
    /// statement about a relay-less profile, and nothing at all to do with
    /// what those tests exist to pin.
    @MainActor
    private func makeRelayBearingPersistence(_ label: String) -> UserDefaultsAppPersistenceStore {
        let persistence = makePersistence(label)
        persistence.saveRelayRetirementMigrationStamp()
        return persistence
    }

    private static let ojamdSeeds = BackendProfilesStore.MigrationSeeds(
        gatewayBaseURL: "http://ojamd:8642",
        relayBaseURL: "http://100.110.102.59:8000/v1",
        shimBaseURL: "http://ojamd:8765"
    )

    @MainActor
    private final class RecordingPairingService: PairingServiceProtocol {
        private(set) var lastMintedUserID: UUID?
        private(set) var lastRelayBaseURL: String?

        func normalizePairingCode(_ rawCode: String) throws -> String {
            try PhonePairingCode.normalize(rawCode)
        }

        func redeemPairingCode(
            _ normalizedCode: String,
            request: DeviceRegistrationRequest
        ) async throws -> PairingRedeemResult {
            let mintedUserID = UUID()
            lastMintedUserID = mintedUserID
            lastRelayBaseURL = request.relayBaseURLString
            return PairingRedeemResult(
                configuration: PairedRelayConfiguration(
                    baseURLString: request.relayBaseURLString,
                    hostDisplayName: URL(string: request.relayBaseURLString)?.host ?? request.relayBaseURLString,
                    pairedAt: Date(timeIntervalSince1970: 1_752_600_000), // whole-second: the store's ISO8601 round-trip drops fractional seconds
                    relayUserID: mintedUserID
                ),
                state: AppSessionState(
                    userID: mintedUserID,
                    displayName: "Morgan",
                    deviceID: UUID(),
                    installationID: request.installationID,
                    deviceRegistered: true,
                    connectionStatus: .connected,
                    syncStatus: .synced,
                    isMockMode: false,
                    backendEndpoint: request.relayBaseURLString,
                    lastSyncAt: .now
                ),
                tokens: AuthTokens(
                    accessToken: "paired-access-token-\(normalizedCode)",
                    refreshToken: "paired-refresh-token-\(normalizedCode)",
                    expiresAt: .distantFuture
                )
            )
        }
    }

    /// Redeem always fails AFTER code normalization — the #94 ordering probe.
    @MainActor
    private final class FailingPairingService: PairingServiceProtocol {
        struct RedeemFailed: Error {}

        func normalizePairingCode(_ rawCode: String) throws -> String {
            try PhonePairingCode.normalize(rawCode)
        }

        func redeemPairingCode(
            _ normalizedCode: String,
            request: DeviceRegistrationRequest
        ) async throws -> PairingRedeemResult {
            throw RedeemFailed()
        }
    }

    @MainActor
    private func makeSessionStore(
        persistence: UserDefaultsAppPersistenceStore,
        secureStore: MockSecureStore,
        profilesStore: BackendProfilesStore
    ) -> AppSessionStore {
        AppSessionStore(
            bootstrapService: MockSessionBootstrapService(),
            syncCoordinator: MockSyncCoordinator(),
            secureStore: secureStore,
            persistence: persistence,
            environmentProvider: { .production },
            credentialScopeProvider: { profilesStore.activeProfile?.credentialScopeID }
        )
    }

    @MainActor
    private func makePairingStore(
        service: any PairingServiceProtocol,
        sessionStore: AppSessionStore,
        persistence: UserDefaultsAppPersistenceStore,
        profilesStore: BackendProfilesStore
    ) -> PairingStore {
        PairingStore(
            pairingService: service,
            sessionStore: sessionStore,
            persistence: persistence,
            environmentProvider: { .production },
            relayBaseURLProvider: { profilesStore.activeProfile?.relayBaseURL },
            profileResolver: { id in profilesStore.resolvedProfile(id: id) }
        )
    }

    // MARK: - M-2: migration

    @Test @MainActor
    func migrationMintsOneLegacyKeyedProfileAndIsIdempotent() throws {
        let persistence = makePersistence("migration")

        let first = BackendProfilesStore(persistence: persistence, migrationSeeds: Self.ojamdSeeds)
        #expect(first.profiles.count == 1)
        let migrated = try #require(first.activeProfile)
        // **#384: this asserted the literal `"OJAMD"`.** The fixture passes no
        // `name`, so it was implicitly pinning the DEFAULT — which was Owen's
        // personal host and is now neutral. The test's INTENT is that the mint
        // honours its seed's name, so it now says that structurally: a future
        // rename cannot fail this spuriously, and #384's
        // `theMintedProfileIsNotNamedAfterAPersonalHost` is what guards the
        // default from becoming personal again. One property per test.
        #expect(migrated.name == BackendProfilesStore.MigrationSeeds(gatewayBaseURL: "").name)
        #expect(!migrated.name.localizedCaseInsensitiveContains("ojamd"))
        #expect(migrated.gatewayBaseURL == "http://ojamd:8642")
        // #310 (2026-08-20): this line used to assert the relay SEED survived
        // the mint. It no longer does, and the change is a ruling rather than
        // a regression — the relay-retirement migration runs on whatever
        // state the M-2 branch produced, so a fresh mint and an existing
        // install converge on the same relay-less end state instead of the
        // mint keeping a seed the retirement would clear a moment later.
        //
        // That this is the RETIREMENT's doing and not the mint dropping its
        // seed is what `mintKeepsItsRelaySeedWhenTheRetirementAlreadyRan`
        // below controls for. Without that control, a bug where M-2 stopped
        // reading `migrationSeeds.relayBaseURL` at all would pass here.
        #expect(migrated.relayBaseURL == nil)
        #expect(migrated.shimBaseURL == "http://ojamd:8765")
        #expect(migrated.usesLegacyCredentialKeys)
        // The migrated profile IS the active profile.
        #expect(first.activeProfileID == migrated.id)

        // Second construction over the same persistence: the SAME profile,
        // not a second migration.
        let second = BackendProfilesStore(persistence: persistence, migrationSeeds: Self.ojamdSeeds)
        #expect(second.profiles.count == 1)
        #expect(second.activeProfile?.id == migrated.id)
    }

    // MARK: - #310: the relay-retirement migration
    //
    // Bars 310-A and 310-B, pre-registered in OPEN_ITEMS #310 before this
    // code. Owen ruled on 2026-08-20 that existing profiles' relay URLs are
    // CLEARED: both hosts' relays are retired (#346 OJAMD, #375 Mac), so every
    // persisted profile points at something dead, and that dead URL is what
    // buys #365's ~10 s profile-switch stall.

    /// The control that keeps `migrationMintsOneLegacyKeyedProfile…` honest.
    ///
    /// With the retirement stamp ALREADY set, the M-2 mint's relay seed
    /// survives — which is what proves the nil in that test is the retirement
    /// clearing a seed rather than the mint never reading one. Delete this
    /// test and a regression where `MigrationSeeds.relayBaseURL` stops being
    /// used at all becomes invisible.
    @Test @MainActor
    func mintKeepsItsRelaySeedWhenTheRetirementAlreadyRan() throws {
        let persistence = makePersistence("mint-seed-after-retirement")
        persistence.saveRelayRetirementMigrationStamp()

        let store = BackendProfilesStore(persistence: persistence, migrationSeeds: Self.ojamdSeeds)
        let minted = try #require(store.activeProfile)
        #expect(minted.relayBaseURL == "http://100.110.102.59:8000/v1")
        #expect(minted.hasRelay)
    }

    /// **310-B, phase 1** — an install that already has profiles loses every
    /// relay URL exactly once, and the stamp records that it happened.
    @Test @MainActor
    func relayRetirementClearsExistingProfilesOnce() throws {
        let persistence = makePersistence("relay-retirement-clears")
        // Two profiles, both relay-bearing — the shape of Owen's own install.
        let ojamd = BackendProfile(
            name: "OJAMD",
            gatewayBaseURL: "http://100.110.102.59:8642",
            relayBaseURL: "http://100.110.102.59:8000/v1",
            usesLegacyCredentialKeys: true
        )
        let mac = BackendProfile(
            name: "Mac Mini",
            gatewayBaseURL: "http://100.79.222.100:8642",
            relayBaseURL: "http://100.79.222.100:8000/v1"
        )
        persistence.saveBackendProfilesState(
            BackendProfilesState(profiles: [ojamd, mac], activeProfileID: ojamd.id)
        )
        #expect(!persistence.loadRelayRetirementMigrationStamp())

        let store = BackendProfilesStore(persistence: persistence, migrationSeeds: Self.ojamdSeeds)

        #expect(store.profiles.count == 2)
        #expect(store.profiles.allSatisfy { $0.relayBaseURL == nil })
        #expect(store.profiles.allSatisfy { !$0.hasRelay })
        #expect(persistence.loadRelayRetirementMigrationStamp())
        // Identity and credential scope are untouched — this migration edits
        // ONE field. A cleared relay must never restyle the Keychain scope,
        // or every existing pairing detaches from its credentials.
        #expect(store.activeProfileID == ojamd.id)
        #expect(store.profile(id: ojamd.id)?.usesLegacyCredentialKeys == true)
        #expect(store.profile(id: mac.id)?.usesLegacyCredentialKeys == false)
        // Persisted, not merely in memory: a state that only cleared in RAM
        // would re-stall on the very next launch while this test stayed green.
        let reloaded = try #require(persistence.loadBackendProfilesState())
        #expect(reloaded.profiles.allSatisfy { $0.relayBaseURL == nil })
    }

    /// **310-B, phase 2 — THE BAR.**
    ///
    /// A relay URL the user types back in must SURVIVE the next launch. This
    /// is the half that fails under the obvious wrong implementation: folding
    /// the clear into `normalized(_:)`, which runs on every load and on every
    /// `upsert`, would wipe the re-entered URL immediately while phase 1
    /// above stayed green.
    @Test @MainActor
    func aReEnteredRelayURLSurvivesTheNextLaunch() throws {
        let persistence = makePersistence("relay-retirement-reentry")
        let profile = BackendProfile(
            name: "OJAMD",
            gatewayBaseURL: "http://100.110.102.59:8642",
            relayBaseURL: "http://100.110.102.59:8000/v1"
        )
        persistence.saveBackendProfilesState(
            BackendProfilesState(profiles: [profile], activeProfileID: profile.id)
        )

        // Launch 1: the retirement fires.
        let first = BackendProfilesStore(persistence: persistence, migrationSeeds: Self.ojamdSeeds)
        #expect(first.activeProfile?.relayBaseURL == nil)

        // The user re-enters a relay URL (the Server settings write path).
        first.updateActiveProfile { $0.relayBaseURL = "http://relay.re-entered.test:8000/v1" }
        #expect(first.activeProfile?.relayBaseURL == "http://relay.re-entered.test:8000/v1")

        // Launch 2: a fresh store over the same persistence. The retirement
        // is stamped, so it must not fire again.
        let second = BackendProfilesStore(persistence: persistence, migrationSeeds: Self.ojamdSeeds)
        #expect(second.activeProfile?.relayBaseURL == "http://relay.re-entered.test:8000/v1")
        #expect(second.activeProfile?.hasRelay == true)

        // And an upsert — the OTHER path through `normalized(_:)` — must not
        // clear it either. Named separately because `updateActiveProfile`
        // does NOT go through `normalized`, so the assertion above alone
        // leaves the upsert path uncovered.
        var edited = try #require(second.activeProfile)
        edited.note = "still has a relay"
        second.upsert(edited)
        #expect(second.activeProfile?.relayBaseURL == "http://relay.re-entered.test:8000/v1")
    }

    /// **310-A** — persisted blobs written by the SHIPPING build still decode.
    ///
    /// Deliberately over LITERAL JSON, never a round-trip through the new
    /// encoder: a round-trip cannot produce the shape only the old encoder
    /// wrote (`relayBaseURL` always present, sometimes `""`), so it would go
    /// green while a real user's blob decoded wrong. This is the §1.5
    /// persisted-state discipline — a miss here is a user-data regression,
    /// not a failing assertion.
    @Test @MainActor
    func legacyProfileBlobsDecodeUnderTheOptionalRelayType() throws {
        let decoder = JSONDecoder()
        let id = UUID().uuidString

        func blob(_ relayFragment: String) -> Data {
            Data("""
            {"id": "\(id)", "name": "OJAMD", "gatewayBaseURL": "http://ojamd:8642"\
            \(relayFragment), "usesLegacyCredentialKeys": true}
            """.utf8)
        }

        // (i) A real URL survives verbatim.
        let withURL = try decoder.decode(
            BackendProfile.self,
            from: blob(", \"relayBaseURL\": \"http://100.110.102.59:8000/v1\"")
        )
        #expect(withURL.relayBaseURL == "http://100.110.102.59:8000/v1")
        #expect(withURL.hasRelay)

        // (ii) The empty string the pre-#310 encoder wrote for "no relay"
        // decodes to nil — NOT to "", which would be handed to URL(string:)
        // and produce the relative-URL requests this item exists to stop.
        let empty = try decoder.decode(BackendProfile.self, from: blob(", \"relayBaseURL\": \"\""))
        #expect(empty.relayBaseURL == nil)
        #expect(!empty.hasRelay)

        // (iii) An absent key — what the new encoder writes for nil, and what
        // a blob from a future field-adding build could also look like.
        let absent = try decoder.decode(BackendProfile.self, from: blob(""))
        #expect(absent.relayBaseURL == nil)
        #expect(!absent.hasRelay)

        // Everything else round-trips regardless of which shape the relay took.
        for profile in [withURL, empty, absent] {
            #expect(profile.name == "OJAMD")
            #expect(profile.gatewayBaseURL == "http://ojamd:8642")
            #expect(profile.usesLegacyCredentialKeys)
        }
    }

    /// A nil relay encodes as an ABSENT key, and the pair round-trips. Pinned
    /// because the synthesized encoder's `encodeIfPresent` behaviour for
    /// Optionals is the thing case (iii) above depends on — if a future edit
    /// hand-writes `encode(to:)` and emits `""` for nil, (iii) would still
    /// pass while every newly-written blob carried the old ambiguity back.
    @Test @MainActor
    func aRelaylessProfileEncodesWithNoRelayKey() throws {
        let profile = BackendProfile(name: "Gateway only", gatewayBaseURL: "http://host:8642")
        let data = try JSONEncoder().encode(profile)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(json["relayBaseURL"] == nil)
        let decoded = try JSONDecoder().decode(BackendProfile.self, from: data)
        #expect(decoded.relayBaseURL == nil)
        #expect(decoded.id == profile.id)
    }

    @Test @MainActor
    func migratedProfileResolvesLegacyCredentialKeys() {
        // Single-profile parity: the migrated profile's credential scope is
        // nil, so every derived key is byte-identical to the pre-profile
        // strings — nothing in the Keychain or UserDefaults moves.
        #expect(BackendProfileScopedKeys.accessToken(nil) == "session.accessToken")
        #expect(BackendProfileScopedKeys.refreshToken(nil) == "session.refreshToken")
        #expect(BackendProfileScopedKeys.gatewayAPIKey(nil) == "hermes.apiServerKey")
        #expect(BackendProfileScopedKeys.shimToken(nil) == "talaria.modelsShimToken")
        #expect(BackendProfileScopedKeys.pairedRelayConfiguration(nil) == "hermes.pairedRelayConfiguration")
        #expect(BackendProfileScopedKeys.sessionState(nil) == "hermes.sessionState")
        // #251-2A: the talaria device credential's two halves. Pinned like
        // the rest because a renamed key string is a silently orphaned
        // Keychain entry — the app re-pairs and the old token lingers
        // forever, invisible to the profile-delete purge that enumerates
        // these exact names.
        #expect(BackendProfileScopedKeys.talariaDeviceToken(nil) == "talaria.platformDeviceToken")
        #expect(BackendProfileScopedKeys.talariaDeviceID(nil) == "talaria.platformDeviceToken.deviceID")

        let scope = UUID()
        #expect(BackendProfileScopedKeys.accessToken(scope) == "session.accessToken.\(scope.uuidString)")
        #expect(BackendProfileScopedKeys.pairedRelayConfiguration(scope).hasSuffix(scope.uuidString))
        // The device id is derived from the SCOPED token key, so the suffix
        // lands in the middle — pin the whole string, not just its tail.
        #expect(BackendProfileScopedKeys.talariaDeviceToken(scope) == "talaria.platformDeviceToken.\(scope.uuidString)")
        #expect(BackendProfileScopedKeys.talariaDeviceID(scope) == "talaria.platformDeviceToken.\(scope.uuidString).deviceID")
    }

    @Test @MainActor
    func reMigrationAfterDataLossStillResolvesLegacyCredentials() async {
        // The anti-stranding property behind mapping-not-renaming (#41): if
        // the profiles blob is ever lost, re-migration mints a NEW profile id
        // — but it is again legacy-keyed, so surviving Keychain credentials
        // still resolve.
        let secureStore = MockSecureStore()
        await secureStore.store(key: "session.accessToken", value: "surviving-token")

        let persistence = makePersistence("data-loss")
        let profilesStore = BackendProfilesStore(persistence: persistence, migrationSeeds: Self.ojamdSeeds)
        let sessionStore = makeSessionStore(
            persistence: persistence,
            secureStore: secureStore,
            profilesStore: profilesStore
        )

        let recovered = await sessionStore.currentAccessToken()
        #expect(recovered == "surviving-token")
    }

    // MARK: - Profile-scoped persistence

    @Test @MainActor
    func pairedRelayConfigurationSlotsAreIsolatedPerProfile() {
        let persistence = makePersistence("slots")
        let scopeA: UUID? = nil // the migrated profile's legacy slot
        let scopeB: UUID? = UUID()

        let configA = PairedRelayConfiguration(
            baseURLString: "http://a.example.test/v1",
            hostDisplayName: "a.example.test",
            pairedAt: Date(timeIntervalSince1970: 1_752_600_000), // whole-second: the store's ISO8601 round-trip drops fractional seconds
            relayUserID: UUID()
        )
        let configB = PairedRelayConfiguration(
            baseURLString: "http://b.example.test/v1",
            hostDisplayName: "b.example.test",
            pairedAt: Date(timeIntervalSince1970: 1_752_600_000), // whole-second: the store's ISO8601 round-trip drops fractional seconds
            relayUserID: UUID()
        )

        persistence.savePairedRelayConfiguration(configA, profileScope: scopeA)
        persistence.savePairedRelayConfiguration(configB, profileScope: scopeB)
        #expect(persistence.loadPairedRelayConfiguration(profileScope: scopeA) == configA)
        #expect(persistence.loadPairedRelayConfiguration(profileScope: scopeB) == configB)

        // Clearing one slot never touches the other.
        persistence.clearPairedRelayConfiguration(profileScope: scopeB)
        #expect(persistence.loadPairedRelayConfiguration(profileScope: scopeB) == nil)
        #expect(persistence.loadPairedRelayConfiguration(profileScope: scopeA) == configA)
    }

    // MARK: - M-3: per-profile clean slate (#94/#3)

    @Test @MainActor
    func pairingSecondProfileLeavesFirstProfilesPairingAndTokensUntouched() async throws {
        let persistence = makeRelayBearingPersistence("clean-slate")
        let secureStore = MockSecureStore()
        let profilesStore = BackendProfilesStore(persistence: persistence, migrationSeeds: Self.ojamdSeeds)
        let sessionStore = makeSessionStore(
            persistence: persistence,
            secureStore: secureStore,
            profilesStore: profilesStore
        )
        let service = RecordingPairingService()
        let pairingStore = makePairingStore(
            service: service,
            sessionStore: sessionStore,
            persistence: persistence,
            profilesStore: profilesStore
        )

        // Pair the migrated (active) profile — lands in the legacy slot.
        let pairedOJAMD = await pairingStore.pair(using: "abcd-efgh")
        #expect(pairedOJAMD)
        let ojamdConfig = try #require(persistence.loadPairedRelayConfiguration(profileScope: nil))
        #expect(ojamdConfig.baseURLString == "http://100.110.102.59:8000/v1")
        #expect(await secureStore.retrieve(key: "session.accessToken") == "paired-access-token-ABCDEFGH")

        // Add the Mac profile and make it active, then pair IT.
        let mac = BackendProfile(
            name: "Mac Mini",
            gatewayBaseURL: "http://100.79.222.100:8642",
            relayBaseURL: "http://100.79.222.100:8000/v1",
            shimBaseURL: "http://100.79.222.100:8765"
        )
        profilesStore.upsert(mac)
        let switchedToMac = profilesStore.setActiveProfile(mac.id)
        #expect(switchedToMac)
        let pairedMac = await pairingStore.pair(using: "jklm-npqr")
        #expect(pairedMac)

        // The Mac's slot holds its own record + tokens (profile-scoped keys),
        // redeemed against the MAC's relay URL.
        let macScope = try #require(mac.credentialScopeID)
        let macConfig = try #require(persistence.loadPairedRelayConfiguration(profileScope: macScope))
        #expect(macConfig.baseURLString == "http://100.79.222.100:8000/v1")
        #expect(service.lastRelayBaseURL == "http://100.79.222.100:8000/v1")
        let macToken = await secureStore.retrieve(key: BackendProfileScopedKeys.accessToken(macScope))
        #expect(macToken == "paired-access-token-JKLMNPQR")

        // THE LANE'S WHOLE POINT: OJAMD's pairing record and tokens survived
        // the Mac pair untouched.
        #expect(persistence.loadPairedRelayConfiguration(profileScope: nil) == ojamdConfig)
        #expect(await secureStore.retrieve(key: "session.accessToken") == "paired-access-token-ABCDEFGH")
        #expect(await secureStore.retrieve(key: "session.refreshToken") == "paired-refresh-token-ABCDEFGH")
    }

    @Test @MainActor
    func rePairingSameProfileStillClearsItsOwnOldIdentity() async throws {
        // #3's protection within one profile: re-pairing the active profile
        // replaces its record and tokens (clean slate), scoped to that slot.
        let persistence = makeRelayBearingPersistence("re-pair")
        let secureStore = MockSecureStore()
        let profilesStore = BackendProfilesStore(persistence: persistence, migrationSeeds: Self.ojamdSeeds)
        let sessionStore = makeSessionStore(
            persistence: persistence,
            secureStore: secureStore,
            profilesStore: profilesStore
        )
        let service = RecordingPairingService()
        let pairingStore = makePairingStore(
            service: service,
            sessionStore: sessionStore,
            persistence: persistence,
            profilesStore: profilesStore
        )

        let firstPair = await pairingStore.pair(using: "abcd-efgh")
        #expect(firstPair)
        let firstUser = try #require(service.lastMintedUserID)

        let secondPair = await pairingStore.pair(using: "jklm-npqr")
        #expect(secondPair)
        let config = try #require(persistence.loadPairedRelayConfiguration(profileScope: nil))
        #expect(config.relayUserID == service.lastMintedUserID)
        #expect(config.relayUserID != firstUser)
        #expect(await secureStore.retrieve(key: "session.accessToken") == "paired-access-token-JKLMNPQR")
    }

    @Test @MainActor
    func failedRedeemLeavesExistingPairingIntact() async throws {
        // #94: redeem-first ordering — the clean slate only runs AFTER a
        // successful redeem, so a failed pair never destroys the live pairing.
        let persistence = makeRelayBearingPersistence("failed-redeem")
        let secureStore = MockSecureStore()
        let profilesStore = BackendProfilesStore(persistence: persistence, migrationSeeds: Self.ojamdSeeds)
        let sessionStore = makeSessionStore(
            persistence: persistence,
            secureStore: secureStore,
            profilesStore: profilesStore
        )
        let goodStore = makePairingStore(
            service: RecordingPairingService(),
            sessionStore: sessionStore,
            persistence: persistence,
            profilesStore: profilesStore
        )
        let paired = await goodStore.pair(using: "abcd-efgh")
        #expect(paired)
        let existing = try #require(persistence.loadPairedRelayConfiguration(profileScope: nil))

        let failingStore = makePairingStore(
            service: FailingPairingService(),
            sessionStore: sessionStore,
            persistence: persistence,
            profilesStore: profilesStore
        )
        let failedPair = await failingStore.pair(using: "jklm-npqr")
        #expect(failedPair == false)
        #expect(failingStore.lastErrorMessage != nil)
        #expect(persistence.loadPairedRelayConfiguration(profileScope: nil) == existing)
        #expect(await secureStore.retrieve(key: "session.accessToken") == "paired-access-token-ABCDEFGH")
        #expect(failingStore.pairedRelayConfiguration == existing)
    }

    // MARK: - Delete guards (Keychain hygiene rides AppContainer's callback)

    @Test @MainActor
    func activeAndSensorDestinationProfilesAreUndeletable() throws {
        let persistence = makePersistence("delete-guards")
        let profilesStore = BackendProfilesStore(persistence: persistence, migrationSeeds: Self.ojamdSeeds)
        let migrated = try #require(profilesStore.activeProfile)
        let mac = BackendProfile(
            name: "Mac Mini",
            gatewayBaseURL: "http://100.79.222.100:8642",
            relayBaseURL: "http://100.79.222.100:8000/v1"
        )
        profilesStore.upsert(mac)

        // Migrated profile is active AND sensor destination.
        #expect(throws: BackendProfilesStore.DeleteError.profileIsActive) {
            try profilesStore.deleteProfile(id: migrated.id)
        }

        // A bystander profile deletes fine, and the deletion callback fires.
        let spare = BackendProfile(name: "Spare", gatewayBaseURL: "http://spare:8642", relayBaseURL: "")
        profilesStore.upsert(spare)
        var deleted: BackendProfile?
        profilesStore.onProfileDeleted = { deleted = $0 }
        try profilesStore.deleteProfile(id: spare.id)
        #expect(deleted?.id == spare.id)
        #expect(profilesStore.profile(id: spare.id) == nil)
    }

    /// #153 × #137: deleting a profile purges that profile's credentials, but
    /// the sensor-migration stamp is app-wide and MONOTONIC by design.
    /// Clearing it here would let a later re-pair re-run the migration and
    /// switch streaming and motion back on without consent.
    @Test @MainActor
    func deletingAProfileLeavesTheSensorMigrationStampIntact() throws {
        let persistence = makePersistence("delete-migration-stamp")
        persistence.saveSensorStreamingMigrationStamp()
        #expect(persistence.loadSensorStreamingMigrationStamp())

        let profilesStore = BackendProfilesStore(persistence: persistence, migrationSeeds: Self.ojamdSeeds)
        let spare = BackendProfile(name: "Spare", gatewayBaseURL: "http://spare:8642", relayBaseURL: "")
        profilesStore.upsert(spare)
        try profilesStore.deleteProfile(id: spare.id)

        #expect(persistence.loadSensorStreamingMigrationStamp())
    }

    // MARK: - M-1: session records carry their birth profile

    @Test @MainActor
    func hopAndSessionIndexRecordBirthProfile() {
        let persistence = makePersistence("birth-profile")
        let journal = ConversationJournalStore(persistence: persistence)
        let profileID = UUID()

        journal.beginHop(apiSessionId: "api_123", primingUsage: nil, profileID: profileID)
        #expect(journal.activeHop?.profileID == profileID)

        let index = SessionProfileIndexStore(persistence: persistence)
        index.record(sessionID: "api_123", profileID: profileID)
        #expect(index.profileID(forSessionID: "api_123") == profileID)

        // Birth host is immutable: a later record for a known id is ignored.
        index.record(sessionID: "api_123", profileID: UUID())
        #expect(index.profileID(forSessionID: "api_123") == profileID)

        // Persistence round-trip.
        let reloaded = SessionProfileIndexStore(persistence: persistence)
        #expect(reloaded.profileID(forSessionID: "api_123") == profileID)

        // Prune keeps only known-live ids.
        reloaded.record(sessionID: "api_456", profileID: profileID)
        reloaded.prune(keeping: ["api_456"])
        #expect(reloaded.profileID(forSessionID: "api_123") == nil)
        #expect(reloaded.profileID(forSessionID: "api_456") == profileID)
    }

    @Test @MainActor
    func preLaneMJournalDecodesWithNilHopProfile() throws {
        // A persisted hop written before profileID existed must decode (to
        // nil), not fail the whole journal decode.
        let legacyJSON = """
        {
            "conversationID": "\(UUID().uuidString)",
            "entries": [],
            "activeHop": { "apiSessionId": "api_legacy", "seenEntryCount": 2 }
        }
        """
        let journal = try JSONDecoder().decode(ConversationJournal.self, from: Data(legacyJSON.utf8))
        #expect(journal.activeHop?.apiSessionId == "api_legacy")
        #expect(journal.activeHop?.seenEntryCount == 2)
        #expect(journal.activeHop?.profileID == nil)
    }
}
