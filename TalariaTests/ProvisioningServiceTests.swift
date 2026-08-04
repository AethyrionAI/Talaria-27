import Foundation
import Testing
@testable import Talaria

/// #116 → #223 Lane 5: the post-pair provisioning bundle, reduced to the
/// gateway base URL. Fill rules (empty-only, manual values sacred), the
/// tolerated-and-ignored shim fields, and the wire payload decode.
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

    /// An old relay still sends shim fields — they must be tolerated and IGNORED.
    private static let macDescriptor = RelayProvisioningDescriptor(
        shimBaseURL: "http://100.79.222.100:8765",
        shimToken: "provisioned-shim-token",
        gatewayBaseURL: "http://100.79.222.100:8642"
    )

    @MainActor
    private func makeService(
        profilesStore: BackendProfilesStore,
        descriptor: @escaping @MainActor (BackendProfile) async throws -> RelayProvisioningDescriptor
    ) -> ProvisioningService {
        ProvisioningService(
            profileResolver: { profilesStore.profile(id: $0) },
            upsertProfile: { profilesStore.upsert($0) },
            fetchDescriptor: descriptor
        )
    }

    // MARK: - Fill rules

    @Test @MainActor
    func autoFillFillsTheEmptyGatewayURLOnly() async throws {
        let profilesStore = BackendProfilesStore(persistence: makePersistence("fill"), migrationSeeds: Self.ojamdSeeds)
        // A freshly added profile with nothing but a relay URL — the exact
        // post-QR-pair shape the auto-fill exists for.
        let mac = BackendProfile(name: "Mac Mini", gatewayBaseURL: "", relayBaseURL: "http://100.79.222.100:8000/v1")
        profilesStore.upsert(mac)
        let service = makeService(profilesStore: profilesStore) { _ in Self.macDescriptor }

        let outcome = try await service.applyProvisioning(profileID: mac.id, mode: .fillEmptyOnly)

        #expect(outcome == ProvisioningService.Outcome(filledGatewayBaseURL: true, descriptorWasEmpty: false))
        let updated = try #require(profilesStore.profile(id: mac.id))
        #expect(updated.gatewayBaseURL == "http://100.79.222.100:8642")
        // #223 Lane 5: the descriptor's shim fields are IGNORED — no profile
        // shim URL fill, ever.
        #expect(updated.shimBaseURL == nil)
        #expect(outcome.summary(profileName: "Mac Mini") == "Mac Mini: updated gateway URL.")
    }

    @Test @MainActor
    func manualValuesSurviveAutoFill() async throws {
        let profilesStore = BackendProfilesStore(persistence: makePersistence("manual"), migrationSeeds: Self.ojamdSeeds)
        let mac = BackendProfile(
            name: "Mac Mini",
            gatewayBaseURL: "https://mac.tailnet.example:9642",
            relayBaseURL: "http://100.79.222.100:8000/v1"
        )
        profilesStore.upsert(mac)
        let service = makeService(profilesStore: profilesStore) { _ in Self.macDescriptor }

        let outcome = try await service.applyProvisioning(profileID: mac.id, mode: .fillEmptyOnly)

        #expect(outcome.didFillAnything == false)
        let untouched = try #require(profilesStore.profile(id: mac.id))
        #expect(untouched.gatewayBaseURL == "https://mac.tailnet.example:9642")
        #expect(outcome.summary(profileName: "Mac Mini") == "Mac Mini: provisioning already up to date.")
    }

    @Test @MainActor
    func refreshModeNeverOverwritesAConfiguredGatewayURL() async throws {
        let profilesStore = BackendProfilesStore(persistence: makePersistence("refresh"), migrationSeeds: Self.ojamdSeeds)
        let mac = BackendProfile(
            name: "Mac Mini",
            gatewayBaseURL: "https://mac.tailnet.example:9642",
            relayBaseURL: "http://100.79.222.100:8000/v1"
        )
        profilesStore.upsert(mac)
        let service = makeService(profilesStore: profilesStore) { _ in Self.macDescriptor }

        let outcome = try await service.applyProvisioning(profileID: mac.id, mode: .refresh)

        #expect(outcome.filledGatewayBaseURL == false)
        let untouched = try #require(profilesStore.profile(id: mac.id))
        #expect(untouched.gatewayBaseURL == "https://mac.tailnet.example:9642")
    }

    @Test @MainActor
    func shimOnlyDescriptorCountsAsEmptyNow() async throws {
        let profilesStore = BackendProfilesStore(persistence: makePersistence("shimonly"), migrationSeeds: Self.ojamdSeeds)
        let mac = BackendProfile(name: "Mac Mini", gatewayBaseURL: "", relayBaseURL: "http://100.79.222.100:8000/v1")
        profilesStore.upsert(mac)
        // #223 Lane 5: a host reporting ONLY shim provisioning has nothing
        // the app still consumes.
        let service = makeService(profilesStore: profilesStore) { _ in
            RelayProvisioningDescriptor(shimBaseURL: "http://100.79.222.100:8765", shimToken: "tok", gatewayBaseURL: nil)
        }

        let outcome = try await service.applyProvisioning(profileID: mac.id, mode: .fillEmptyOnly)

        #expect(outcome.descriptorWasEmpty)
        #expect(outcome.didFillAnything == false)
        #expect(outcome.summary(profileName: "Mac Mini") == "Mac Mini: host reported no gateway provisioning.")
        let untouched = try #require(profilesStore.profile(id: mac.id))
        #expect(untouched.shimBaseURL == nil)
        #expect(untouched.gatewayBaseURL.isEmpty)
    }

    @Test @MainActor
    func emptyDescriptorFillsNothingAndSaysSo() async throws {
        let profilesStore = BackendProfilesStore(persistence: makePersistence("empty"), migrationSeeds: Self.ojamdSeeds)
        let mac = BackendProfile(name: "Mac Mini", gatewayBaseURL: "", relayBaseURL: "http://100.79.222.100:8000/v1")
        profilesStore.upsert(mac)
        // Whitespace-only values normalize to absent — same as the relay's
        // explicit all-null empty shape.
        let service = makeService(profilesStore: profilesStore) { _ in
            RelayProvisioningDescriptor(shimBaseURL: "  ", shimToken: nil, gatewayBaseURL: "")
        }

        let outcome = try await service.applyProvisioning(profileID: mac.id, mode: .fillEmptyOnly)

        #expect(outcome.descriptorWasEmpty)
        #expect(outcome.didFillAnything == false)
        let untouched = try #require(profilesStore.profile(id: mac.id))
        #expect(untouched.gatewayBaseURL.isEmpty)
    }

    @Test @MainActor
    func fetchFailurePropagatesAndWritesNothing() async throws {
        let profilesStore = BackendProfilesStore(persistence: makePersistence("failure"), migrationSeeds: Self.ojamdSeeds)
        let mac = BackendProfile(name: "Mac Mini", gatewayBaseURL: "", relayBaseURL: "http://100.79.222.100:8000/v1")
        profilesStore.upsert(mac)
        let service = makeService(profilesStore: profilesStore) { _ in
            throw ProvisioningService.ServiceError.notPaired
        }

        await #expect(throws: ProvisioningService.ServiceError.notPaired) {
            try await service.applyProvisioning(profileID: mac.id, mode: .fillEmptyOnly)
        }
        let untouched = try #require(profilesStore.profile(id: mac.id))
        #expect(untouched.gatewayBaseURL.isEmpty)
    }

    // MARK: - Wire payload decode

    @Test @MainActor
    func deviceProvisioningResponseDecodesRelayShape() throws {
        // The relay's data payload — camelCase fields, explicit nulls allowed.
        // Shim fields still decode (old relays send them) but no longer count
        // toward isEmpty.
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
        // #223 Lane 5: shim-only provisioning is "nothing we consume".
        #expect(decoded.provisioning.isEmpty)
        #expect(decoded.updatedAt == Date(timeIntervalSince1970: 1_784_203_200))

        let withGateway = """
        {"provisioning": {"shimBaseURL": null, "shimToken": null, "gatewayBaseURL": "http://ojamd:8642"}, "updatedAt": null}
        """
        let decodedGateway = try RelayCoders.makeDecoder().decode(DeviceProvisioningResponse.self, from: Data(withGateway.utf8))
        #expect(decodedGateway.provisioning.isEmpty == false)
        #expect(decodedGateway.updatedAt == nil)
    }
}
