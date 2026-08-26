import Foundation
import Testing
@testable import Talaria

/// **#384 — no personal host ships in the binary, and an empty host is a
/// first-class state rather than a broken one.**
///
/// Every fresh install used to mint a profile pointed at `http://ojamd:8642`,
/// Owen's personal Windows box — hardcoded, not debug-gated, and *named*
/// `"OJAMD"` besides. Three consequences, only the first of which was filed:
/// a stranger's install aimed at a host they cannot resolve, a personal
/// hostname in every shipping copy, and **#348's 85 × 401** — the gate's own
/// simulator runs authenticating against a production box and failing.
///
/// Owen's route (2026-08-22): ship no default at all. Not the debug-gate,
/// which would have left #348 untouched because the gate builds Debug.
struct NoDefaultHostTests {

    /// **384-A.** The shipping defaults carry no host at all.
    ///
    /// Asserted on the CONSTANTS rather than by grepping the source, because a
    /// grep passes the moment someone spells the same host differently — an
    /// IP, a MagicDNS name, a `String(...)` built at runtime. What matters is
    /// that a fresh install resolves to nothing.
    @Test func noDefaultHostShipsAtAll() {
        #expect(UserSettings.defaultHermesAPIBaseURL.isEmpty)
        #expect(UserSettings.defaultModelsShimBaseURL.isEmpty)
    }

    /// **384-A, the seed name.** A stranger's install must not be *called*
    /// OJAMD either — the third literal, which #384's entry never named and
    /// only tracing the seed path found.
    @Test func theMintedProfileIsNotNamedAfterAPersonalHost() {
        let seeds = BackendProfilesStore.MigrationSeeds(gatewayBaseURL: "")
        #expect(!seeds.name.localizedCaseInsensitiveContains("ojamd"))
        #expect(!seeds.name.isEmpty, "a nameless profile is its own defect")
    }

    /// **384-C — one spelling of the gateway gate.**
    ///
    /// #310 added `hasRelay` because *"a gate with two spellings is a gate with
    /// a hole"*, and the gateway plane had no equivalent while three call
    /// sites tested `.isEmpty == false` by hand. That was survivable while the
    /// empty case was an edge; **#384 makes it every fresh install's first
    /// state**, so it needed the same treatment.
    @Test func hasGatewayIsTheOneSpellingAndAgreesWithItsResolvedForm() {
        let none = BackendProfile(name: "Fresh", gatewayBaseURL: "")
        #expect(none.hasGateway == false)
        #expect(none.resolvedGatewayBaseURL == nil)

        let some = BackendProfile(name: "Mine", gatewayBaseURL: "http://example.test:8642")
        #expect(some.hasGateway)
        #expect(some.resolvedGatewayBaseURL == "http://example.test:8642")
    }

    /// **384-B — an empty host is HONEST, not broken.**
    ///
    /// The risk this bar exists for: shipping an empty default without a route
    /// to fill it would be worse than the hardcoded host. A profile with no
    /// gateway must be a *coherent* state — it has an identity, it persists,
    /// and it reports its own lack rather than pretending.
    ///
    /// What this test does NOT cover, stated rather than implied: whether the
    /// onboarding UI actually presents the "add your host" path. That is a
    /// device/UI question, and claiming it here from a model-layer assertion
    /// would be the green-that-proves-nothing shape.
    @Test func aProfileWithNoGatewayIsCoherentRatherThanBroken() throws {
        let fresh = BackendProfile(name: "My Hermes", gatewayBaseURL: "")
        #expect(fresh.hasGateway == false)
        // #309 Lane B: the `hasRelay == false` line that stood here is gone
        // with the property. It said the same thing twice on a gateway-only
        // build — every profile is relay-less now, by construction.

        // It survives a persistence round trip unchanged — an empty host must
        // not decode into something else on the next launch.
        let data = try JSONEncoder().encode(fresh)
        let back = try JSONDecoder().decode(BackendProfile.self, from: data)
        #expect(back.gatewayBaseURL.isEmpty)
        #expect(back.hasGateway == false)
        #expect(back.name == "My Hermes")
    }

    /// **384-D — Owen's own install is untouched.**
    ///
    /// M-2 is one-shot and already ran on his device, so his profile keeps the
    /// name and URL it was minted with. **A change that silently renamed or
    /// cleared an existing profile would have broken a working install to fix
    /// a fresh-install problem** — which is the failure mode this bar exists
    /// to forbid, not a hypothetical.
    ///
    /// Pinned over a persisted blob rather than a constructed value, because
    /// the decoder is where a "helpful" default would actually get applied.
    @Test func anExistingProfileKeepsItsNameAndHostAcrossTheChange() throws {
        let blob = Data("""
        {"id":"6E5B0F62-0000-4000-8000-00000000384D",
         "name":"OJAMD",
         "gatewayBaseURL":"http://ojamd:8642",
         "usesLegacyCredentialKeys":true}
        """.utf8)

        let decoded = try JSONDecoder().decode(BackendProfile.self, from: blob)

        #expect(decoded.name == "OJAMD", "an existing profile was renamed by #384")
        #expect(decoded.gatewayBaseURL == "http://ojamd:8642",
                "an existing profile's host was cleared by #384")
        #expect(decoded.hasGateway)
    }
}
