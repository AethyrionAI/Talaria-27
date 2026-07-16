import Foundation
import Testing
@testable import Talaria

/// #116: the post-pair provisioning bundle — fill rules (empty-only vs the
/// explicit refresh rotation), per-profile Keychain scoping, and the wire
/// payload decode.
@Suite(.serialized)
struct ProvisioningServiceTests {

    // MARK: - Fixtures

    @MainActor
    private func makePersistence(_ label: String) -> UserDefaultsAppPersistenceStore {
        let suiteName = "provisioning-\(label)-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsAppPersistenceStore(defaults: defaults)
    }

    private static let ojamdSeeds = BackendProfilesStore.MigrationSeeds(
        gatewayBaseURL: "http://ojamd:8642",
        relayBaseURL: "http://ojamd:8000/v1",
        shimBaseURL: "http://ojamd:8765"
    )

    private static let macDescriptor = RelayProvisioningDescriptor(
        shimBaseURL: "http://100.79.222.100:8765",
        shimToken: "provisioned-shim-token",
        gatewayBaseURL: "http://100.79.222.100:8642"
    )

    @MainActor
    private func makeService(
        profilesStore: BackendProfilesStore,
        secureStore: MockSecureStore,
        descriptor: @escaping @MainActor (BackendProfile) async throws -> RelayProvisioningDescriptor
    ) -> ProvisioningService {
        ProvisioningService(
            profileResolver: { profilesStore.profile(id: $0) },
            upsertProfile: { profilesStore.upsert($0) },
            readShimToken: { profile in
                await secureStore.retrieve(key: BackendProfileScopedKeys.shimToken(profile.credentialScopeID))
            },
            writeShimToken: { value, profile in
                await secureStore.store(key: BackendProfileScopedKeys.shimToken(profile.credentialScopeID), value: value)
            },
            fetchDescriptor: descriptor
        )
    }

    // MARK: - Fill rules

    @Test @MainActor
    func autoFillFillsEmptyFieldsOnly() async throws {
        let profilesStore = BackendProfilesStore(persistence: makePersistence("fill"), migrationSeeds: Self.ojamdSeeds)
        let secureStore = MockSecureStore()
        // A freshly added profile with nothing but a relay URL — the exact
        // post-QR-pair shape the auto-fill exists for.
        let mac = BackendProfile(name: "Mac Mini", gatewayBaseURL: "", relayBaseURL: "http://100.79.222.100:8000/v1")
        profilesStore.upsert(mac)
        let service = makeService(profilesStore: profilesStore, secureStore: secureStore) { _ in Self.macDescriptor }

        let outcome = try await service.applyProvisioning(profileID: mac.id, mode: .fillEmptyOnly)

        #expect(outcome == ProvisioningService.Outcome(
            filledShimBaseURL: true, filledShimToken: true, filledGatewayBaseURL: true, descriptorWasEmpty: false
        ))
        let updated = try #require(profilesStore.profile(id: mac.id))
        #expect(updated.shimBaseURL == "http://100.79.222.100:8765")
        #expect(updated.gatewayBaseURL == "http://100.79.222.100:8642")
        let token = await secureStore.retrieve(key: BackendProfileScopedKeys.shimToken(mac.credentialScopeID))
        #expect(token == "provisioned-shim-token")
    }

    @Test @MainActor
    func manualValuesSurviveAutoFill() async throws {
        let profilesStore = BackendProfilesStore(persistence: makePersistence("manual"), migrationSeeds: Self.ojamdSeeds)
        let secureStore = MockSecureStore()
        let mac = BackendProfile(
            name: "Mac Mini",
            gatewayBaseURL: "https://mac.tailnet.example:9642",
            relayBaseURL: "http://100.79.222.100:8000/v1",
            shimBaseURL: "https://mac.tailnet.example:9765"
        )
        profilesStore.upsert(mac)
        await secureStore.store(key: BackendProfileScopedKeys.shimToken(mac.credentialScopeID), value: "manually-pasted-token")
        let service = makeService(profilesStore: profilesStore, secureStore: secureStore) { _ in Self.macDescriptor }

        let outcome = try await service.applyProvisioning(profileID: mac.id, mode: .fillEmptyOnly)

        #expect(outcome.didFillAnything == false)
        let untouched = try #require(profilesStore.profile(id: mac.id))
        #expect(untouched.shimBaseURL == "https://mac.tailnet.example:9765")
        #expect(untouched.gatewayBaseURL == "https://mac.tailnet.example:9642")
        let token = await secureStore.retrieve(key: BackendProfileScopedKeys.shimToken(mac.credentialScopeID))
        #expect(token == "manually-pasted-token")
        #expect(outcome.summary(profileName: "Mac Mini") == "Mac Mini: provisioning already up to date.")
    }

    @Test @MainActor
    func refreshRotatesTheTokenButNeverOverwritesURLs() async throws {
        let profilesStore = BackendProfilesStore(persistence: makePersistence("refresh"), migrationSeeds: Self.ojamdSeeds)
        let secureStore = MockSecureStore()
        let mac = BackendProfile(
            name: "Mac Mini",
            gatewayBaseURL: "https://mac.tailnet.example:9642",
            relayBaseURL: "http://100.79.222.100:8000/v1",
            shimBaseURL: "https://mac.tailnet.example:9765"
        )
        profilesStore.upsert(mac)
        await secureStore.store(key: BackendProfileScopedKeys.shimToken(mac.credentialScopeID), value: "stale-rotated-out-token")
        let service = makeService(profilesStore: profilesStore, secureStore: secureStore) { _ in Self.macDescriptor }

        let outcome = try await service.applyProvisioning(profileID: mac.id, mode: .refresh)

        // The rotation path: token replaced, endpoints sacred.
        #expect(outcome.filledShimToken)
        #expect(outcome.filledShimBaseURL == false)
        #expect(outcome.filledGatewayBaseURL == false)
        let token = await secureStore.retrieve(key: BackendProfileScopedKeys.shimToken(mac.credentialScopeID))
        #expect(token == "provisioned-shim-token")
        let untouched = try #require(profilesStore.profile(id: mac.id))
        #expect(untouched.shimBaseURL == "https://mac.tailnet.example:9765")
        #expect(untouched.gatewayBaseURL == "https://mac.tailnet.example:9642")
    }

    @Test @MainActor
    func emptyDescriptorFillsNothingAndSaysSo() async throws {
        let profilesStore = BackendProfilesStore(persistence: makePersistence("empty"), migrationSeeds: Self.ojamdSeeds)
        let secureStore = MockSecureStore()
        let mac = BackendProfile(name: "Mac Mini", gatewayBaseURL: "", relayBaseURL: "http://100.79.222.100:8000/v1")
        profilesStore.upsert(mac)
        // Whitespace-only values normalize to absent — same as the relay's
        // explicit all-null empty shape.
        let service = makeService(profilesStore: profilesStore, secureStore: secureStore) { _ in
            RelayProvisioningDescriptor(shimBaseURL: "  ", shimToken: nil, gatewayBaseURL: "")
        }

        let outcome = try await service.applyProvisioning(profileID: mac.id, mode: .fillEmptyOnly)

        #expect(outcome.descriptorWasEmpty)
        #expect(outcome.didFillAnything == false)
        #expect(outcome.summary(profileName: "Mac Mini") == "Mac Mini: host reported no provisioning.")
        let untouched = try #require(profilesStore.profile(id: mac.id))
        #expect(untouched.shimBaseURL == nil)
        #expect(untouched.gatewayBaseURL.isEmpty)
        let token = await secureStore.retrieve(key: BackendProfileScopedKeys.shimToken(mac.credentialScopeID))
        #expect(token == nil)
    }

    @Test @MainActor
    func shimTokenWritesArePerProfileScoped() async throws {
        let profilesStore = BackendProfilesStore(persistence: makePersistence("scoping"), migrationSeeds: Self.ojamdSeeds)
        let secureStore = MockSecureStore()
        let migrated = try #require(profilesStore.activeProfile)
        #expect(migrated.usesLegacyCredentialKeys)
        await secureStore.store(key: "talaria.modelsShimToken", value: "ojamd-legacy-token")
        let mac = BackendProfile(name: "Mac Mini", gatewayBaseURL: "", relayBaseURL: "http://100.79.222.100:8000/v1")
        profilesStore.upsert(mac)
        let service = makeService(profilesStore: profilesStore, secureStore: secureStore) { _ in Self.macDescriptor }

        _ = try await service.applyProvisioning(profileID: mac.id, mode: .fillEmptyOnly)

        // Mac's token landed under ITS scoped key…
        let macScope = try #require(mac.credentialScopeID)
        let macToken = await secureStore.retrieve(key: "talaria.modelsShimToken.\(macScope.uuidString)")
        #expect(macToken == "provisioned-shim-token")
        // …and the migrated profile's legacy slot is untouched.
        let legacyToken = await secureStore.retrieve(key: "talaria.modelsShimToken")
        #expect(legacyToken == "ojamd-legacy-token")
    }

    @Test @MainActor
    func fetchFailurePropagatesAndWritesNothing() async throws {
        let profilesStore = BackendProfilesStore(persistence: makePersistence("failure"), migrationSeeds: Self.ojamdSeeds)
        let secureStore = MockSecureStore()
        let mac = BackendProfile(name: "Mac Mini", gatewayBaseURL: "", relayBaseURL: "http://100.79.222.100:8000/v1")
        profilesStore.upsert(mac)
        let service = makeService(profilesStore: profilesStore, secureStore: secureStore) { _ in
            throw ProvisioningService.ServiceError.notPaired
        }

        await #expect(throws: ProvisioningService.ServiceError.notPaired) {
            try await service.applyProvisioning(profileID: mac.id, mode: .fillEmptyOnly)
        }
        let token = await secureStore.retrieve(key: BackendProfileScopedKeys.shimToken(mac.credentialScopeID))
        #expect(token == nil)
        let untouched = try #require(profilesStore.profile(id: mac.id))
        #expect(untouched.shimBaseURL == nil)
    }

    // MARK: - Wire payload decode

    @Test @MainActor
    func deviceProvisioningResponseDecodesRelayShape() throws {
        // The relay's data payload — camelCase fields, explicit nulls allowed.
        let json = """
        {
            "provisioning": {
                "shimBaseURL": "http://100.79.222.100:8765",
                "shimToken": "shim-token-abc",
                "gatewayBaseURL": null
            },
            "updatedAt": "2026-07-16T12:00:00Z"
        }
        """
        let decoded = try RelayCoders.makeDecoder().decode(DeviceProvisioningResponse.self, from: Data(json.utf8))
        #expect(decoded.provisioning.shimBaseURL == "http://100.79.222.100:8765")
        #expect(decoded.provisioning.shimToken == "shim-token-abc")
        #expect(decoded.provisioning.gatewayBaseURL == nil)
        #expect(decoded.provisioning.isEmpty == false)
        #expect(decoded.updatedAt == Date(timeIntervalSince1970: 1_784_203_200))

        // The explicit empty shape decodes as empty — absence stays absence.
        let empty = """
        {"provisioning": {"shimBaseURL": null, "shimToken": null, "gatewayBaseURL": null}, "updatedAt": null}
        """
        let decodedEmpty = try RelayCoders.makeDecoder().decode(DeviceProvisioningResponse.self, from: Data(empty.utf8))
        #expect(decodedEmpty.provisioning.isEmpty)
        #expect(decodedEmpty.updatedAt == nil)
    }
}
