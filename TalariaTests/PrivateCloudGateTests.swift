import Foundation
import Testing
@testable import Talaria

/// **#72 — the Private Cloud Compute build gate.** Bars 72-A and 72-B.
///
/// Apple granted `com.apple.developer.private-cloud-compute` on 2026-08-20
/// and it is verified present in the signed device binary. What these tests
/// guard is the OTHER half: that a **simulator** binary — which has no
/// entitlement, because `CODE_SIGNING_ALLOWED=NO` strips them — never
/// constructs `PrivateCloudComputeLanguageModel`.
///
/// **Why that matters more than it looks.** Constructing the type without the
/// entitlement SIGTRAPs (measured 2026-07-13), and the trap is *uncatchable*
/// — `send()`'s `catch` cannot rescue it. The whole gate suite runs on the
/// simulator. So a hardcoded `pccGrantConfirmed = true` would not fail a
/// test; it would **kill the test process**, producing a run with no failure
/// marker and no verdict. This project already has a rule for that shape:
/// absence of a failure marker is not success.
///
/// **These tests are unusual in that PASSING AT ALL is the evidence.** Every
/// assertion below is reached only if no construction happened on the way to
/// it. If the gate regressed, this file would not report a failure — it would
/// stop existing mid-run. Read a green result as "the process survived
/// asking", not merely as "the value was false".
@MainActor
struct PrivateCloudGateTests {

    private func makeBackend() -> LocalChatBackend {
        let suiteName = "pcc-gate-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return LocalChatBackend(
            persistence: UserDefaultsAppPersistenceStore(defaults: defaults),
            intelligence: LocalIntelligenceService()
        )
    }

    // MARK: - 72-A — the gate is a build fact, and the simulator is excluded

    @Test func gateIsFalseOnSimulatorAndTrueOnDevice() {
        #if targetEnvironment(simulator)
        #expect(
            LocalChatBackend.pccGrantConfirmed == false,
            """
            A simulator binary carries NO entitlement — CODE_SIGNING_ALLOWED=NO \
            strips it — so constructing PrivateCloudComputeLanguageModel here \
            traps uncatchably and takes the suite with it. If this went red, \
            someone hardcoded `true`; restore the simulator exclusion rather \
            than deleting this test.
            """
        )
        #else
        // On device the entitlement is guaranteed by the build system itself:
        // signing fails at GatherProvisioningInputs without it (bar 72-C,
        // demonstrated involuntarily on 2026-08-20).
        #expect(LocalChatBackend.pccGrantConfirmed == true)
        #endif
    }

    // MARK: - 72-B — every surface stays dark, and survival is the proof

    /// Reads every PCC surface. On the simulator the gate must short-circuit
    /// BEFORE the type is touched — so the values come back dark, and the
    /// test returns at all.
    @Test func everyPrivateCloudSurfaceStaysDarkOnSimulator() {
        #if targetEnvironment(simulator)
        let backend = makeBackend()
        #expect(backend.isPrivateCloudAvailable == false)
        #expect(backend.isPrivateCloudUsable == false)
        #expect(backend.privateCloudStatus() == nil)
        // Deliberately exercised even though it returns nothing: a void call
        // can only fail by TRAPPING, which is precisely the failure this bar
        // exists to prevent.
        backend.showPrivateCloudLimitIncreaseOptions()
        #endif
    }

    /// The tier picker must not offer Private Cloud β where it cannot run.
    @Test func availableModelsOmitPrivateCloudOnSimulator() async throws {
        #if targetEnvironment(simulator)
        let models = try await makeBackend().availableModels()
        #expect(!models.contains("private-cloud-beta"))
        #endif
    }
}
