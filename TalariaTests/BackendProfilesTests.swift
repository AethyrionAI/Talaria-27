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
            notificationService: MockNotificationService(),
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
        #expect(migrated.name == "OJAMD")
        #expect(migrated.gatewayBaseURL == "http://ojamd:8642")
        #expect(migrated.relayBaseURL == "http://100.110.102.59:8000/v1")
        #expect(migrated.shimBaseURL == "http://ojamd:8765")
        #expect(migrated.usesLegacyCredentialKeys)
        // The migrated profile IS the active profile AND the sensor destination.
        #expect(first.activeProfileID == migrated.id)
        #expect(first.sensorDestinationProfileID == migrated.id)

        // Second construction over the same persistence: the SAME profile,
        // not a second migration.
        let second = BackendProfilesStore(persistence: persistence, migrationSeeds: Self.ojamdSeeds)
        #expect(second.profiles.count == 1)
        #expect(second.activeProfile?.id == migrated.id)
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

        let scope = UUID()
        #expect(BackendProfileScopedKeys.accessToken(scope) == "session.accessToken.\(scope.uuidString)")
        #expect(BackendProfileScopedKeys.pairedRelayConfiguration(scope).hasSuffix(scope.uuidString))
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
        let persistence = makePersistence("clean-slate")
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
        let persistence = makePersistence("re-pair")
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
        let persistence = makePersistence("failed-redeem")
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

        // Make the Mac active; OJAMD remains the pinned sensor destination —
        // still undeletable.
        let activatedMac = profilesStore.setActiveProfile(mac.id)
        #expect(activatedMac)
        #expect(throws: BackendProfilesStore.DeleteError.profileIsSensorDestination) {
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
