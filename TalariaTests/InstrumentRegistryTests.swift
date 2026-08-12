#if DEBUG
import Foundation
import Testing
@testable import Talaria

/// #333 bar B's substrate: the registry is the ONE dispatch table both the
/// Developer-screen buttons and the launch-env trigger resolve through.
struct InstrumentRegistryTests {

    @Test func namesAreUniqueAndKebabCase() {
        let names = InstrumentRegistry.all.map(\.name)
        #expect(Set(names).count == names.count)
        for name in names {
            #expect(name == name.lowercased() && !name.contains(" "), "bad name: \(name)")
        }
    }

    @Test func canonicalEntriesResolveWithTheirCapabilityFlags() throws {
        let shape = try #require(InstrumentRegistry.spec(named: "shape"))
        #expect(shape.confirmationMode == .autoDecline)
        #expect(!shape.writesEventKit && !shape.writesAlarms)

        let action = try #require(InstrumentRegistry.spec(named: "action"))
        #expect(action.confirmationMode == .autoAccept)
        #expect(action.writesEventKit && action.writesAlarms)

        let readTool = try #require(InstrumentRegistry.spec(named: "read-tool"))
        #expect(readTool.confirmationMode == .none)
        #expect(!readTool.writesEventKit && !readTool.writesAlarms)

        #expect(InstrumentRegistry.spec(named: "router-probe") != nil)
        #expect(InstrumentRegistry.spec(named: "no-such-instrument") == nil)
    }

    @Test func alarmWritersAreAlwaysEventKitOrAcceptMode() {
        // An instrument that writes alarms but never confirms is a spec bug:
        // alarm writes only happen on the accept path.
        for spec in InstrumentRegistry.all where spec.writesAlarms {
            #expect(spec.confirmationMode == .autoAccept, "\(spec.name) writes alarms without accept mode")
        }
    }

    /// #333 Task 6: the grep-derived completeness pin. Every Developer-screen
    /// instrument button now resolves through `instrumentButton(_:trials:label:)`,
    /// so a button added WITHOUT a registry entry is a `spec(named:)` miss that
    /// no compiler can catch — the button just silently does nothing when
    /// tapped. This count is the tripwire; update it WITH the new entry, in the
    /// same commit. `>=` so a future addition does not red the suite for the
    /// lane that made it.
    @Test func registryCoversEveryDeveloperScreenInstrument() {
        #expect(InstrumentRegistry.all.count >= 48)
    }

    /// The pin above counts; this one checks the count is of the right things.
    /// A `spec(named:)` that returns nil is the exact failure mode a converted
    /// button has — `instrumentButton` guard-lets the lookup and returns, so a
    /// typo'd or missing name is an inert button rather than a crash.
    @Test func everyConvertedButtonNameResolves() throws {
        // The names the Developer screen passes to `instrumentButton`, as of
        // the #333 sweep. Kept as literals on purpose: a test that derived
        // them from `InstrumentRegistry.all` would agree with itself no matter
        // what the view file says.
        let namesTheViewPasses = [
            "shape", "action", "read-tool", "router-probe", "destall", "instrfix",
            "toolmode", "community", "findfix", "spiral", "scoped-v2", "routed",
            "routed-scoped", "spiralfix", "cardfix", "datefix", "calendar",
            "deadend", "deadend-verify", "grabfix", "stallfix", "schemafix",
            "schema-reverify", "calfix", "deadend2", "deadend-confirm",
            "calfix-warm", "cal-rollback-verify", "deadend-reconsider",
            "deadend-reversed", "two-turn", "clause-reverify", "decline",
            "motion-scope", "motion-redirect", "intent-router-probe",
            "vector-router-probe", "toolless-index", "capability-detection-probe",
            "cross-chat-recall-probe", "router-context-probe", "image-routing-probe",
            "long-context-probe", "honesty", "honesty-v2",
            // #334: the read-only FM measurement instruments.
            "tokencount-preflight", "fm-asymmetries", "condensation-fit",
        ]
        for name in namesTheViewPasses {
            #expect(InstrumentRegistry.spec(named: name) != nil,
                    "the Developer screen taps \"\(name)\" and the registry has no entry")
        }
    }

    /// #333 Task 6: alarm-writing instruments are the ones Owen's 2026-08-11
    /// ruling keeps off an unattended device, so an accept-mode battery that
    /// forgot its flags would quietly become unattended-eligible. Every
    /// accept-mode entry in the sweep delegates to `runActionBattery`'s default
    /// prompt set (remind / alarm / calendar) or, for `two-turn`, reaps alarms
    /// itself — so accept implies BOTH write flags, with no exceptions.
    @Test func acceptModeInstrumentsAllDeclareTheirWrites() {
        for spec in InstrumentRegistry.all where spec.confirmationMode == .autoAccept {
            #expect(spec.writesEventKit, "\(spec.name) auto-accepts but claims no EventKit writes")
            #expect(spec.writesAlarms, "\(spec.name) auto-accepts but claims no alarm writes")
        }
    }

    /// The converse guard: a non-accept instrument cannot write, because
    /// `ToolConfirmationCenter.requestConfirmation` checks auto-decline FIRST
    /// and a `.none` instrument stages no confirmation at all. A `true` here
    /// would mean a capability flag was copied rather than derived.
    @Test func nonAcceptInstrumentsWriteNothing() {
        for spec in InstrumentRegistry.all where spec.confirmationMode != .autoAccept {
            #expect(!spec.writesEventKit && !spec.writesAlarms,
                    "\(spec.name) is \(spec.confirmationMode) yet claims writes")
        }
    }
}
#endif
