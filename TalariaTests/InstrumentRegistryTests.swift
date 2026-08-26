#if DEBUG
import Foundation
import Testing
@testable import Talaria

/// #373's discriminator for the structural tripwire below. COMPILE-TIME on
/// purpose — the test bundle is built per destination, so this is decided by
/// the build rather than sniffed at runtime (the idiom is
/// `Phase0ActionCautionTests`'s, and the reasoning is identical).
///
/// A simulator process shares the Mac's filesystem, so `#filePath` resolves to
/// the real repo and a test may read the project's own Swift sources. On a
/// device it cannot — the sources were never copied into the bundle — and the
/// read fails with `NSCocoaErrorDomain 260`. That is a property of the sandbox,
/// not of the code under test, so the bar it guards is UNSCORABLE on a device
/// rather than failed.
private let repoSourcesAreReadableAtRuntime: Bool = {
    #if targetEnvironment(simulator)
    return true
    #else
    return false
    #endif
}()

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
        // 50 since #373 registered `cold-calfix` (2026-08-26).
        #expect(InstrumentRegistry.all.count >= 50)
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
            // #335: the read-only FM measurement instruments.
            "tokencount-preflight", "fm-asymmetries", "condensation-fit",
            // #388: the beta5 surface sweep.
            "pcc-surface",
            // 🔴 #373: THESE THREE WERE MISSING, and their absence is the
            // finding rather than the fix. `due-date`, `card-clause` and
            // `refusal-words` have been tapped from the Developer screen since
            // #340, #337-F and #337-D respectively — three separate lanes each
            // added a button and left this list alone, and nothing complained,
            // because **a hand-maintained list cannot detect its own
            // omissions.** The tripwire above only checks the names it was
            // told about; a button it was never told about is exactly the case
            // it was built to catch and the one case it is blind to.
            //
            // Fixed by listing them. ⟵ AND FIXED STRUCTURALLY 2026-08-26
            // (#373): `everyInstrumentButtonInTheViewSourceResolves` below now
            // reads the VIEW's source at test time and derives the names, which
            // is the only thing that can catch an omission. **That test, not
            // this list, is the completeness authority from here on.** This one
            // keeps a narrower job worth having: it is framework-only, so it
            // scores on a DEVICE too, where the source-reading test cannot run
            // at all. A name missing here is now a coverage gap in the device
            // arm rather than a blind spot in the project.
            "due-date", "card-clause", "refusal-words",
            // #373: registered with this lane, and it is the RED that proved
            // the structural test works — the button landed first and the
            // derived scan caught it while this list stayed happily green.
            "cold-calfix",
        ]
        for name in namesTheViewPasses {
            #expect(InstrumentRegistry.spec(named: name) != nil,
                    "the Developer screen taps \"\(name)\" and the registry has no entry")
        }
    }

    /// 🔧 #373's STRUCTURAL FIX for the tripwire above, and the reason it was
    /// owed. `everyConvertedButtonNameResolves` is a hand-maintained list, and
    /// on 2026-08-21 a diff against the view found **three** names it had never
    /// been told about — `due-date`, `card-clause` and `refusal-words`, each
    /// tapped from the Developer screen for days. Three lanes added a button
    /// and left the list alone, and nothing complained, **because a
    /// hand-maintained list cannot detect its own omissions**: it checks the
    /// names it knows, and a button it was never told about is precisely the
    /// case it exists for.
    ///
    /// So this one does not ask the list. It reads the VIEW'S SOURCE and asks
    /// the registry about every name the view actually passes. Deriving from
    /// `InstrumentRegistry.all` instead would only make the test agree with
    /// itself — that is why the list above is literals in the first place, and
    /// it is why the third source of truth (the view) is the one to read.
    ///
    /// **The POSITIVE CONTROL is not ceremony.** A scan that CANNOT fire is
    /// indistinguishable from a scan that found nothing wrong — the same
    /// false-green shape as a success marker a no-op satisfies. If the regex,
    /// the path or the factory's name ever drifts, this finds zero names and
    /// says so LOUDLY rather than passing an empty loop.
    @Test(.enabled(if: repoSourcesAreReadableAtRuntime,
                   """
                   #373: this bar reads the repo's own Swift sources at runtime, so it \
                   can only be scored where the test process shares the Mac's filesystem \
                   — a simulator. Off-simulator the sources do not exist and the read \
                   fails with NSCocoaErrorDomain 260, which measures the sandbox and not \
                   the registry. Skipped rather than failed; the literal-list pin above \
                   runs everywhere and is unaffected.
                   """))
    func everyInstrumentButtonInTheViewSourceResolves() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TalariaTests/
            .deletingLastPathComponent()   // repo root
        let viewPath = repoRoot.appendingPathComponent(
            "Talaria/Features/Settings/DeveloperSettingsScreen.swift")
        let source = try String(contentsOf: viewPath, encoding: .utf8)

        // `instrumentButton("name"` — the factory every converted button goes
        // through. The DECLARATION (`private func instrumentButton(_ name:`)
        // does not match, because it is followed by an underscore rather than
        // a quote.
        let pattern = try NSRegularExpression(pattern: #"instrumentButton\(\s*"([a-z0-9-]+)""#)
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        var names: Set<String> = []
        for m in pattern.matches(in: source, range: range) {
            if let r = Range(m.range(at: 1), in: source) { names.insert(String(source[r])) }
        }

        // POSITIVE CONTROL — see the doc comment. Both halves matter: the scan
        // must find MANY names (a drifted regex finds none) and it must find a
        // name we know by hand is there (a regex that matched the wrong token
        // could still be numerous).
        #expect(names.count >= 45,
                "the scan found only \(names.count) button names — it has gone blind; repoint it rather than believing the loop below")
        #expect(names.contains("shape"), "the scan cannot see a name known to be in the view")

        for name in names.sorted() {
            #expect(InstrumentRegistry.spec(named: name) != nil,
                    "the Developer screen taps \"\(name)\" and the registry has no entry — that button is INERT when tapped, which no compiler can catch")
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
