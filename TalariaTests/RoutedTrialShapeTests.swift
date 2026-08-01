#if DEBUG
import Foundation
import FoundationModels
import Testing
@testable import Talaria

/// #215 — what routing DOES to a turn, pinned in one place.
///
/// The action battery has never routed: every trial is armed by construction,
/// which is why #214's 8/10 grab rate measured a configuration production does
/// not ship. Giving it a routed variant means the battery must apply exactly
/// the transformation the live path applies — and the live path's two gates
/// (`effectiveOfferedTools`, `effectiveInstructionsText`) are private, so the
/// only way a battery can agree with them is to share a seam.
///
/// **The drift this file exists to prevent is not hypothetical.** The #196
/// rate battery's routed cell built its toolless turn from
/// `instructionsText(for: .toollessLic2, …)`. On 2026-07-30 the #202D
/// promotion added clause v2 to production's toolless branch and created
/// `productionToollessInstructions` — whose own doc comment says it exists
/// "in ONE place so the live path and the measured arm cannot drift apart."
/// The battery was never re-pointed at it. From that promotion until this
/// lane, a routed-toolless trial spoke a text production had stopped
/// speaking.
struct RoutedTrialShapeTests {

    /// A fixed device line, so an assertion can never depend on which machine
    /// or simulator ran it. `deviceContextLine()` is private to the backend and
    /// reads `UIDevice.current`; the seam takes the context as a parameter
    /// precisely so the tests do not have to.
    private static let context = "Device: iPhone running iOS 27.0."

    /// A fixed date. `instructionsText` formats the day into its text, so
    /// `.now` would make two calls in the same test disagree across midnight.
    private static let date = Date(timeIntervalSince1970: 1_753_700_000)

    private static func belt() -> [any Tool] {
        [RoutedProbeToolA(), RoutedProbeToolB()]
    }

    // MARK: The armed half — routing must not touch it

    /// A turn the router says needs a tool is production's armed turn,
    /// unchanged. If this ever fails, the routed battery is measuring the
    /// routing seam rather than the model.
    @Test func armedRouteIsIdentityOnBothBeltAndInstructions() {
        let armed = Self.belt()
        let instructions = "ARMED INSTRUCTIONS — pinned marker."
        let shaped = LocalChatBackend.routedTrialShape(
            needsTool: true, armedBelt: armed, armedInstructions: instructions,
            deviceContext: Self.context, date: Self.date
        )
        #expect(shaped.belt.map(\.name) == ["routedProbeA", "routedProbeB"])
        #expect(shaped.instructions == instructions)
    }

    // MARK: The toolless half — the belt goes away entirely

    /// #196's promoted cure is structural: a routed-toolless turn registers NO
    /// belt. `armed-nocall` proved that leaving schemas in context while
    /// gating the call sustains the disclaimer tic on its own, so an empty
    /// belt — not a call gate — is what the battery must reproduce.
    @Test func toollessRouteRegistersNoBelt() {
        let shaped = LocalChatBackend.routedTrialShape(
            needsTool: false, armedBelt: Self.belt(), armedInstructions: "ignored",
            deviceContext: Self.context, date: Self.date
        )
        #expect(shaped.belt.isEmpty)
    }

    /// The load-bearing assertion: the toolless text is PRODUCTION's, byte for
    /// byte. Everything else in this lane is arithmetic on top of this being
    /// true.
    @Test func toollessRouteSpeaksProductionsToollessText() {
        let shaped = LocalChatBackend.routedTrialShape(
            needsTool: false, armedBelt: Self.belt(), armedInstructions: "ignored",
            deviceContext: Self.context, date: Self.date
        )
        let production = LocalChatBackend.productionToollessInstructions(
            deviceContext: Self.context, date: Self.date, hasImageTools: false
        )
        #expect(shaped.instructions == production)
    }

    /// The drift pin. `.toollessLic2` is the PRE-#202D text — the
    /// `honesty-control` cell, measured at 9/10 broken turns. It is still a
    /// legitimate rollback cell, so it must keep existing; what it must never
    /// again be is what a routed trial speaks.
    ///
    /// Without this test the previous one could be satisfied by re-pointing
    /// BOTH sides at the stale text. This is the assertion that says the two
    /// texts are genuinely different, so agreeing with production means
    /// something.
    @Test func productionToollessTextIsNotTheStaleLic2Text() {
        let production = LocalChatBackend.productionToollessInstructions(
            deviceContext: Self.context, date: Self.date, hasImageTools: false
        )
        let staleLic2 = LocalChatBackend.instructionsText(
            for: .toollessLic2, deviceContext: Self.context, date: Self.date,
            hasTools: false, hasImageTools: false
        )
        #expect(production != staleLic2)
        // Directional, not just unequal: production is the lic2 payload PLUS
        // clause v2, so the stale text must be a strict prefix of it. An
        // assertion of mere inequality would also pass if the two had diverged
        // in some other direction entirely.
        #expect(production.hasPrefix(staleLic2))
        #expect(production.count > staleLic2.count)
    }

    /// The seam takes `hasImageTools` because production threads it, and this
    /// pins that threading it changes NOTHING — deliberately.
    ///
    /// I wrote this test the other way round first, asserting the flag varied
    /// the text, and it failed. The flag has been inert since #176/#148 moved
    /// the vision gate structurally into `DeviceToolBelt.offeredTools`: the
    /// registered belt is the only capability enumeration, so the instructions
    /// cannot claim a tool the session was not given, and there is nothing
    /// left for this flag to say. `instructionsText`'s own doc comment records
    /// it as "kept for call-site stability."
    ///
    /// Pinned rather than deleted, because the inertness is the load-bearing
    /// fact: it is why a routed battery passing `false` loses nothing, and why
    /// a future image lane must change the BELT, not this parameter.
    @Test func theImageToolsFlagIsThreadedButInert() {
        let withImages = LocalChatBackend.routedTrialShape(
            needsTool: false, armedBelt: [], armedInstructions: "ignored",
            deviceContext: Self.context, date: Self.date, hasImageTools: true
        )
        let withoutImages = LocalChatBackend.routedTrialShape(
            needsTool: false, armedBelt: [], armedInstructions: "ignored",
            deviceContext: Self.context, date: Self.date, hasImageTools: false
        )
        #expect(withImages.instructions == withoutImages.instructions)
        // And both are production's text, so the invariance is production's,
        // not something this seam introduces.
        #expect(withImages.instructions == LocalChatBackend.productionToollessInstructions(
            deviceContext: Self.context, date: Self.date, hasImageTools: true
        ))
        #expect(withoutImages.instructions == LocalChatBackend.productionToollessInstructions(
            deviceContext: Self.context, date: Self.date, hasImageTools: false
        ))
    }
}

// MARK: - Probe tools

/// File scope: the `@Generable` macro expansion needs a non-nested,
/// non-private type. Never called — only their names are read.
fileprivate struct RoutedProbeToolA: Tool {
    let name = "routedProbeA"
    let description = "Probe tool. Never called."

    @Generable
    struct Arguments {
        @Guide(description: "Unused.")
        var probe: String
    }

    func call(arguments: Arguments) async throws -> String { "unused" }
}

fileprivate struct RoutedProbeToolB: Tool {
    let name = "routedProbeB"
    let description = "Probe tool. Never called."

    @Generable
    struct Arguments {
        @Guide(description: "Unused.")
        var probe: String
    }

    func call(arguments: Arguments) async throws -> String { "unused" }
}
#endif
