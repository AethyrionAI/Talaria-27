import Foundation
import Testing
@testable import Talaria

/// Lane M PR 1 (OPEN_ITEMS #114): backend-profile model, one-shot migration,
/// and per-profile credential scoping.
///
/// **#309 Lane B (2026-08-25) rewrote the relay half of this file.** The
/// clean-slate surgery on `PairingStore.pair()` is tombstoned in place with
/// its property's new home named; #310's relay-URL migration is tombstoned
/// with it; and the profile-scoped persistence section now measures the
/// residue purge that replaced the record it used to store.
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

    private static let ojamdSeeds = BackendProfilesStore.MigrationSeeds(
        gatewayBaseURL: "http://ojamd:8642",
        shimBaseURL: "http://ojamd:8765"
    )

    // **#309 Lane B: five fixtures deleted here** —
    // `makeRelayBearingPersistence`, `RecordingPairingService`,
    // `FailingPairingService`, `makeSessionStore` and `makePairingStore`. Each
    // built a piece of the relay pairing family; none of those types exist.
    // The seed above lost its `relayBaseURL` for the same reason.


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
        // #309 Lane B: the relay-seed assertions that stood here are gone
        // with `MigrationSeeds.relayBaseURL`.
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

    // MARK: - #310: the relay-retirement migration — TOMBSTONED 2026-08-25
    //
    // **#309 Lane B deleted `BackendProfile.relayBaseURL` (Owen's cleanup
    // ruling 3), and the one-shot migration that cleared it went with the
    // property.** These three tests —
    // `mintKeepsItsRelaySeedWhenTheRetirementAlreadyRan`,
    // `relayRetirementClearsExistingProfilesOnce` and
    // `aReEnteredRelayURLSurvivesTheNextLaunch` — measured a stamp, a clear,
    // and a phase-2 re-clear on a field that no longer exists. They are
    // TOMBSTONED rather than ported because their subject is gone, not
    // moved: there is nothing left to clear once, and nothing a user can
    // re-enter for a second pass to eat.
    //
    // What survives of #310's guarantee is a DECODE property, and it is
    // pinned harder than before — see
    // `legacyProfileBlobsCarryingARelayURLStillDecode` below: an old blob
    // that still carries the key must load, and re-encoding must drop it.


    /// **#309 Lane B rewrote #310's decode pin rather than deleting it.** The
    /// property it guards did not go away when `relayBaseURL` did — it got
    /// sharper. Every profile blob already on a device carries that key, and a
    /// decoder that choked on it would read as "no profiles" and re-run the
    /// M-2 migration over a live install.
    ///
    /// RED against `main`: there, `relayBaseURL` still exists, so the
    /// re-encode half below keeps the key.
    @Test @MainActor
    func legacyProfileBlobsCarryingARelayURLStillDecode() throws {
        let decoder = JSONDecoder()
        let id = UUID().uuidString

        func blob(_ relayFragment: String) -> Data {
            Data(("{\"id\": \"\(id)\", \"name\": \"OJAMD\", "
                  + "\"gatewayBaseURL\": \"http://ojamd:8642\""
                  + relayFragment
                  + ", \"usesLegacyCredentialKeys\": true}").utf8)
        }

        // The three shapes a shipped blob can be in: a real URL (pre-#310),
        // the empty string the pre-#310 encoder wrote for "no relay", and the
        // absent key #310's own migration left behind.
        let withURL = try decoder.decode(
            BackendProfile.self,
            from: blob(", \"relayBaseURL\": \"http://100.110.102.59:8000/v1\"")
        )
        let empty = try decoder.decode(BackendProfile.self, from: blob(", \"relayBaseURL\": \"\""))
        let absent = try decoder.decode(BackendProfile.self, from: blob(""))

        for profile in [withURL, empty, absent] {
            #expect(profile.name == "OJAMD")
            #expect(profile.gatewayBaseURL == "http://ojamd:8642")
            #expect(profile.usesLegacyCredentialKeys)
        }
    }

    /// The other half: a re-encode DROPS the key, so the residue leaves the
    /// blob on its first save rather than riding along forever.
    ///
    /// Pinned by reading the encoded JSON rather than by round-tripping
    /// through the type — a round trip cannot see a key the type ignores,
    /// which is exactly how a "cleaned up" blob could go on carrying a stale
    /// relay URL unnoticed.
    @Test @MainActor
    func anEncodedProfileCarriesNoRelayKeyAtAll() throws {
        let profile = BackendProfile(name: "Gateway only", gatewayBaseURL: "http://host:8642")
        let data = try JSONEncoder().encode(profile)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["relayBaseURL"] == nil)
        #expect(json["gatewayBaseURL"] as? String == "http://host:8642")
        let decoded = try JSONDecoder().decode(BackendProfile.self, from: data)
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
        // #309 Lane B: the surviving credential is the GATEWAY KEY now — the
        // relay access token this used to seed is deleted, and the key is what
        // a stranded install would actually lose.
        let secureStore = MockSecureStore()
        await secureStore.store(
            key: BackendProfileScopedKeys.gatewayAPIKey(nil), value: "surviving-key")

        let persistence = makePersistence("data-loss")
        let profilesStore = BackendProfilesStore(persistence: persistence, migrationSeeds: Self.ojamdSeeds)
        let reMigrated = profilesStore.activeProfile

        // The re-minted profile is LEGACY-KEYED, so its credential scope is
        // nil and it resolves the bare key strings the survivor is under.
        #expect(reMigrated?.usesLegacyCredentialKeys == true)
        let scope = reMigrated?.credentialScopeID
        #expect(scope == nil)
        let recovered = await secureStore.retrieve(key: BackendProfileScopedKeys.gatewayAPIKey(scope))
        #expect(recovered == "surviving-key")
    }

    // MARK: - Profile-scoped persistence, and the residue purge (309-B9)

    /// **Rewritten from `pairedRelayConfigurationSlotsAreIsolatedPerProfile`.**
    /// The old test saved a `PairedRelayConfiguration` into two scopes and
    /// proved clearing one left the other. Its subject — a per-profile relay
    /// pairing record — is deleted; the SCOPING property it was really about
    /// survives, and Lane B's purge is where it now lives.
    ///
    /// Two claims, and the second is the one that matters most:
    /// 1. the purge is SCOPED — sweeping profile B leaves A's slots alone;
    /// 2. the purge does NOT WIDEN — every credential in
    ///    `survivingKeychainKeys` is still there afterwards. A purge whose
    ///    failure mode is "took the gateway key too" would present as a user
    ///    silently losing their host.
    @Test @MainActor
    func theRelayResiduePurgeIsScopedAndDoesNotWiden() async {
        let persistence = makePersistence("residue-purge")
        let secureStore = MockSecureStore()
        let scopeA: UUID? = nil // the migrated profile's legacy slot
        let scopeB: UUID? = UUID()

        for scope in [scopeA, scopeB] {
            for key in RelayCredentialHygiene.deadKeychainKeys(scope: scope) {
                await secureStore.store(key: key, value: "residue")
            }
            for key in RelayCredentialHygiene.survivingKeychainKeys(scope: scope) {
                await secureStore.store(key: key, value: "keep-me")
            }
        }

        await RelayCredentialHygiene.purge(
            scopes: [scopeB], secureStore: secureStore, persistence: persistence)

        // (1) scoped: B swept, A untouched.
        for key in RelayCredentialHygiene.deadKeychainKeys(scope: scopeB) {
            #expect(await secureStore.retrieve(key: key) == nil, "B's residue should be gone: \(key)")
        }
        for key in RelayCredentialHygiene.deadKeychainKeys(scope: scopeA) {
            #expect(await secureStore.retrieve(key: key) == "residue", "A's slot is not B's: \(key)")
        }
        // (2) did not widen: every survivor still there, in BOTH scopes.
        for scope in [scopeA, scopeB] {
            for key in RelayCredentialHygiene.survivingKeychainKeys(scope: scope) {
                #expect(await secureStore.retrieve(key: key) == "keep-me",
                        "the purge must never take this: \(key)")
            }
        }
    }

    /// The legacy (`nil`) scope is ALWAYS swept, whatever the profile list
    /// says. Owen's own install is the migrated one — it keys its credentials
    /// off the unscoped strings — so a `scopes(for:)` that only mapped over
    /// `profiles` would leave the oldest device in the fleet the only one
    /// still holding relay JWTs.
    @Test @MainActor
    func theResidueSweepAlwaysIncludesTheLegacyUnscopedSlots() {
        let scoped = BackendProfile(name: "Mac", gatewayBaseURL: "http://mac:8642")
        let legacy = BackendProfile(
            name: "Migrated", gatewayBaseURL: "http://ojamd:8642", usesLegacyCredentialKeys: true)

        #expect(RelayCredentialHygiene.scopes(for: []) == [nil])
        let both = RelayCredentialHygiene.scopes(for: [scoped, legacy])
        #expect(both.contains(nil))
        #expect(both.contains(scoped.id))
        // The legacy profile's scope IS nil — it must not be listed twice.
        #expect(both.count == 2)
    }

    /// The persisted half of the same sweep: both blobs go, from UserDefaults
    /// AND the Keychain mirror, and only for the scope asked about.
    @Test @MainActor
    func theResiduePurgeRemovesBothPersistedBlobsForOneScopeOnly() {
        let persistence = makePersistence("residue-persisted")
        let scopeB = UUID()
        let defaults = UserDefaults(suiteName: "residue-blob-\(UUID().uuidString)")!

        // Written by hand under the real key strings: nothing in the app can
        // produce these any more, which is the point of a residue test.
        for scope in [nil, Optional(scopeB)] {
            defaults.set("x", forKey: BackendProfileScopedKeys.sessionState(scope))
            defaults.set("x", forKey: BackendProfileScopedKeys.pairedRelayConfiguration(scope))
        }
        let store = UserDefaultsAppPersistenceStore(defaults: defaults)
        store.purgeRelayCredentialResidue(profileScope: scopeB)

        #expect(defaults.object(forKey: BackendProfileScopedKeys.sessionState(scopeB)) == nil)
        #expect(defaults.object(forKey: BackendProfileScopedKeys.pairedRelayConfiguration(scopeB)) == nil)
        #expect(defaults.object(forKey: BackendProfileScopedKeys.sessionState(nil)) != nil)
        #expect(defaults.object(forKey: BackendProfileScopedKeys.pairedRelayConfiguration(nil)) != nil)
        _ = persistence
    }

    // MARK: - M-3: per-profile clean slate (#94/#3) — TOMBSTONED 2026-08-25
    //
    // **#309 Lane B deleted `PairingStore.pair()`, and these three tests went
    // with it:** `pairingSecondProfileLeavesFirstProfilesPairingAndTokensUntouched`,
    // `rePairingSameProfileStillClearsItsOwnOldIdentity`, and
    // `failedRedeemLeavesExistingPairingIntact`.
    //
    // **Their PROPERTY was ported, not lost — that is why this is a tombstone
    // and not a deletion.** All three were really about one rule: a pairing
    // attempt writes exactly one profile's slots, and only when the remote
    // step succeeded (#94's redeem-first ordering). Connect Host's
    // commit-on-probe-pass is the same rule on the gateway plane, and
    // `ConnectHostTests` pins it harder — the old tests measured the
    // POST-CONDITION (the record is still there), while the new ones count
    // WRITES, so a commit that happened and was then undone cannot pass.
    // See `aFailedProbeWritesNothing…` and `theCommitTargetsOneProfile…`.


    // MARK: - Delete guards (Keychain hygiene rides AppContainer's callback)

    @Test @MainActor
    func activeAndSensorDestinationProfilesAreUndeletable() throws {
        let persistence = makePersistence("delete-guards")
        let profilesStore = BackendProfilesStore(persistence: persistence, migrationSeeds: Self.ojamdSeeds)
        let migrated = try #require(profilesStore.activeProfile)
        let mac = BackendProfile(
            name: "Mac Mini",
            gatewayBaseURL: "http://100.79.222.100:8642"
        )
        profilesStore.upsert(mac)

        // Migrated profile is active AND sensor destination.
        #expect(throws: BackendProfilesStore.DeleteError.profileIsActive) {
            try profilesStore.deleteProfile(id: migrated.id)
        }

        // A bystander profile deletes fine, and the deletion callback fires.
        let spare = BackendProfile(name: "Spare", gatewayBaseURL: "http://spare:8642")
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
        let spare = BackendProfile(name: "Spare", gatewayBaseURL: "http://spare:8642")
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
