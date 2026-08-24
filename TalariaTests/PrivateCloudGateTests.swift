import Foundation
import Testing
@testable import Talaria

/// **#72 — the Private Cloud Compute build gate, as amended by #403's
/// metadata carve-out.** Bars 72-A/72-B and 403-A/403-B.
///
/// Apple granted `com.apple.developer.private-cloud-compute` on 2026-08-20
/// and it is verified present in the signed device binary. **The dated
/// record of the simulator hazard, because this header used to overstate
/// it:** constructing the type on a sim SIGTRAPped when measured 2026-07-13;
/// that trap did NOT reproduce on 2026-08-20 (beta5, construction + quota
/// reads ran clean on an unentitled binary); and #402 (2026-08-24, runtime
/// 24A5423a) established that a sim binary in fact CARRIES the entitlement —
/// in the simulated-entitlements section `codesign` cannot see — and that
/// modelmanagerd honors it. So construction is measured-safe, and #403
/// carved the METADATA plane in for DEBUG simulator builds.
///
/// **What still must never light on a simulator is the TURN plane** —
/// `isAvailable` reads true there while generation fails instantly on an
/// unresolvable asset (#402), so a turn-plane surface gone light offers a
/// tier that cannot run. That is what these tests pin now: the two planes
/// SPLIT. Survival remains part of the evidence on the metadata tests: they
/// construct the type for real on every suite run.
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

    // MARK: - 72-B (amended by #403) — the TURN plane stays dark

    /// On the simulator every turn-plane surface must stay dark, because the
    /// SDK's own `isAvailable` is TRUE there (#402) — only the gate keeps
    /// these false. **That is exactly what makes these pins mutation-red for
    /// 403-A:** repoint `isPrivateCloudAvailable` to the metadata gate and
    /// the `setPreferredTier` pin goes red (the tier would take); repoint
    /// `isPrivateCloudUsable` and its pin goes red (sim quota reads
    /// belowLimit, so nothing but the gate returns false).
    @Test func turnPlaneStaysDarkOnSimulator() {
        #if targetEnvironment(simulator)
        let backend = makeBackend()
        #expect(backend.isPrivateCloudAvailable == false)
        #expect(backend.isPrivateCloudUsable == false)
        backend.setPreferredTier(privateCloud: true)
        #expect(
            backend.activeTier == .onDevice,
            "A sim build asked for the PCC tier and GOT it — a turn-plane surface is reading the #403 metadata gate."
        )
        #endif
    }

    // MARK: - 403-B — the METADATA plane lights on a DEBUG simulator

    /// This suite always builds Debug, so on a simulator the #403 carve-out
    /// is active: the settings surface exists and the quota status maps from
    /// LIVE SDK reads. Survival is still part of the evidence — every call
    /// here constructs `PrivateCloudComputeLanguageModel` for real.
    /// (Assumes the runtime's `isAvailable == true` on sim — measured on
    /// 24A5390f-era beta5 2026-08-20 and on 24A5423a in #402. If a future
    /// runtime returns false, this test names the assumption to revisit.)
    @Test func metadataPlaneLightsOnDebugSimulator() {
        #if targetEnvironment(simulator)
        let backend = makeBackend()
        #expect(LocalChatBackend.pccMetadataObservable == true)
        #expect(backend.isPrivateCloudObservable == true)
        #expect(backend.privateCloudStatus() != nil)
        // Void call — it can only fail by trapping, which is the survival
        // half of the bar.
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
