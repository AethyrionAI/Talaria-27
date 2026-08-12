# #333 Unattended Instrument Runner — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the ~25 Developer-screen instruments triggerable headlessly (launch env → same code path as the button → JSON artifact with a positive completion flag → `devicectl` fetch), so device batteries run with nobody watching.

**Architecture:** A DEBUG-only `InstrumentRegistry` (name → capability flags + the exact backend call each button makes today) is the single dispatch table. An `InstrumentConductor` owns the flag discipline (auto-accept/decline, `alarmWritesAttended`, idle timer), the refusal rules (alarm-flagged refuses unattended; EventKit-flagged refuses on iPad), and writes an `InstrumentResultEnvelope` artifact (status `running` at start, `completed`/`refused`/`failed` at end, atomic writes) to `Documents/InstrumentRuns/`. Buttons and the launch-env trigger both resolve through the registry to the conductor — one code path (bar 333-B). A Mac-side `scripts/mac/run-instrument.sh` launches via `DEVICECTL_CHILD_*` env (proven mechanism, `planning/HANDOFF-2026-07-28-OVERNIGHT.md`), polls with a hard timeout, fetches, and verifies the completion flag.

**Tech Stack:** Swift 6 / SwiftUI, Swift Testing (`@Test`/`#expect`), XcodeGen, `xcrun devicectl`, bash + python3 (harness). Everything app-side is `#if DEBUG`.

## Global Constraints

- **Tracker:** this is #333; bars 333-A..H are pre-registered in `OPEN_ITEMS.md` — read them before starting. A missed bar is a falsification, not a redefinition.
- `export DEVELOPER_DIR=/Applications/Xcode-beta5.app/Contents/Developer` in every shell.
- **All new app code inside `#if DEBUG`** (bar 333-F; Release build proves it — #218).
- **New Swift files ⇒ `xcodegen generate` is mandatory IN THE TASK THAT CREATES THEM, immediately after creating them and before running tests** (an explicit-listing project cannot see a file it wasn't regenerated with); commit the regenerated `project.pbxproj` with the files (idempotent since #319). Task 7's regen is then a no-op verification.
- The trigger **never** sets `BatteryTestContainer.alarmWritesAttended = true` (that flag means "a human tapped" — #331). Alarm-flagged instruments are refused when `unattended`. EventKit-flagged instruments are refused on any iPad (`userInterfaceIdiom == .pad`).
- Do not touch `beginBatteryRun`/`endBatteryRun`, the reap, or `BatteryRunRecorder` internals — containment is inherited by calling the existing `run*` methods (#331 composition).
- Do not run anything on a physical device except in Task 9. Never run EventKit/AlarmKit anything on Shelley's iPad.
- Tests: Swift Testing, `@MainActor`, fixtures follow `TalariaTests/BatteryRunStoreTests.swift` idioms (whole-second dates — the store's ISO8601 drops fractional seconds).
- Commit per task; commit messages end with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Work happens on branch `t27-333-instrument-runner` off `main` (currently `a7a3008`).

---

### Task 1: `InstrumentResultEnvelope` + atomic artifact writer

**Files:**
- Create: `Talaria/Services/Live/InstrumentArtifact.swift`
- Test: `TalariaTests/InstrumentArtifactTests.swift`

**Interfaces:**
- Consumes: `BatteryRunRecord` (exists, `Talaria/Services/Live/BatteryRunStore.swift:148` — `Codable, Equatable`).
- Produces: `InstrumentRunStatus` (enum `running|completed|refused|failed`), `InstrumentResultEnvelope` (Codable struct below), `InstrumentArtifactWriter` with `init(directory: URL)`, `func write(_ envelope: InstrumentResultEnvelope) throws`, `static var defaultDirectory: URL` (Documents/InstrumentRuns). Task 4 depends on these exact names.

- [ ] **Step 1: Write the failing tests**

```swift
#if DEBUG
import Foundation
import Testing
@testable import Talaria

/// #333: the artifact is the run's ONLY machine-readable output. `latest.json`
/// must be atomic (a partial file is never mistaken for a finished one) and the
/// status field is the positive completion signal — bar 333-C's schema half.
@MainActor
struct InstrumentArtifactTests {

    private func makeWriter() -> (InstrumentArtifactWriter, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("instrument-artifact-tests-\(UUID().uuidString)", isDirectory: true)
        return (InstrumentArtifactWriter(directory: dir), dir)
    }

    private func makeEnvelope(status: InstrumentRunStatus) -> InstrumentResultEnvelope {
        InstrumentResultEnvelope(
            instrument: "router-probe", trialsRequested: 2, cells: nil,
            unattended: true,
            startedAt: Date(timeIntervalSince1970: 1_755_000_000),
            endedAt: status == .running ? nil : Date(timeIntervalSince1970: 1_755_000_120),
            deviceModel: "iPad15,3", osVersion: "Version 27.0",
            appVersion: "1.0", appBuild: "42", buildSha: "a7a3008",
            status: status, refusalReason: nil, runRecord: nil
        )
    }

    @Test func envelopeRoundTripsThroughLatestJSON() throws {
        let (writer, dir) = makeWriter()
        let envelope = makeEnvelope(status: .completed)
        try writer.write(envelope)
        let data = try Data(contentsOf: dir.appendingPathComponent("latest.json"))
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(InstrumentResultEnvelope.self, from: data) == envelope)
    }

    @Test func rewriteReplacesLatestInPlace() throws {
        let (writer, dir) = makeWriter()
        try writer.write(makeEnvelope(status: .running))
        try writer.write(makeEnvelope(status: .completed))
        let data = try Data(contentsOf: dir.appendingPathComponent("latest.json"))
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(InstrumentResultEnvelope.self, from: data).status == .completed)
    }

    @Test func terminalWriteAlsoLandsATimestampedResultFile() throws {
        let (writer, dir) = makeWriter()
        try writer.write(makeEnvelope(status: .running))
        try writer.write(makeEnvelope(status: .refused))
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        // running writes ONLY latest.json; the terminal status adds result-*.json.
        #expect(names.filter { $0.hasPrefix("result-") }.count == 1)
    }

    @Test func statusRawValuesAreTheHarnessContract() {
        // scripts/mac/run-instrument.sh string-matches these — renaming them
        // breaks the harness silently. Pin them.
        #expect(InstrumentRunStatus.running.rawValue == "running")
        #expect(InstrumentRunStatus.completed.rawValue == "completed")
        #expect(InstrumentRunStatus.refused.rawValue == "refused")
        #expect(InstrumentRunStatus.failed.rawValue == "failed")
    }
}
#endif
```

- [ ] **Step 2: Run to verify they fail** — build fails: types not defined. Run (background it; poll the log):
`DEVELOPER_DIR=/Applications/Xcode-beta5.app/Contents/Developer xcodebuild -project Talaria.xcodeproj -scheme Talaria -destination 'platform=iOS Simulator,name=CC-333-iPhone-Air' test -only-testing:'TalariaTests/InstrumentArtifactTests'` (create the sim first per Task 7's command; note Swift Testing `-only-testing` needs the struct name, no `()` — a wrong name prints TEST SUCCEEDED over zero tests, so confirm the run reports 4 tests).

- [ ] **Step 3: Implement**

```swift
#if DEBUG
import Foundation

/// #333: the four terminal truths a harness can read. `running` is written at
/// conductor start so a killed run's `latest.json` never claims completion —
/// the positive-signal rule (bar 333-C).
enum InstrumentRunStatus: String, Codable {
    case running, completed, refused, failed
}

/// #333: one run's machine-readable artifact. Embeds the full
/// `BatteryRunRecord` (whose own `endedCleanly` is the store-side completion
/// flag) so the harness fetches exactly one file.
struct InstrumentResultEnvelope: Codable, Equatable {
    var schemaVersion: Int = 1
    var instrument: String
    var trialsRequested: Int
    var cells: [String]?
    var unattended: Bool
    var startedAt: Date
    var endedAt: Date?
    var deviceModel: String
    var osVersion: String
    var appVersion: String
    var appBuild: String
    /// Pass-through of TALARIA_BUILD_SHA from launch env — the harness stamps
    /// what it deployed; the app cannot know its own git sha.
    var buildSha: String?
    var status: InstrumentRunStatus
    var refusalReason: String?
    var runRecord: BatteryRunRecord?
}

/// Writes `latest.json` on every transition and a timestamped `result-*.json`
/// on terminal statuses. `.atomic` throughout — a partial file cannot exist.
struct InstrumentArtifactWriter {
    let directory: URL

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("InstrumentRuns", isDirectory: true)
    }

    func write(_ envelope: InstrumentResultEnvelope) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(envelope)
        try data.write(to: directory.appendingPathComponent("latest.json"), options: .atomic)
        if envelope.status != .running {
            let stamp = Int(envelope.startedAt.timeIntervalSince1970)
            let name = "result-\(envelope.instrument)-\(stamp).json"
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        }
    }
}
#endif
```

- [ ] **Step 4: Run tests to verify they pass** (same command; expect 4/4).
- [ ] **Step 5: Commit** — `feat(#333): instrument result envelope + atomic artifact writer`

---

### Task 2: `InstrumentLaunchIntent` — the env parser (incl. #196 legacy mapping)

**Files:**
- Create: `Talaria/Services/Live/InstrumentLaunchIntent.swift`
- Test: `TalariaTests/InstrumentLaunchIntentTests.swift`

**Interfaces:**
- Produces: `struct InstrumentLaunchIntent: Equatable { var name: String; var trials: Int; var cells: [String]? }` and `static func parse(_ env: [String: String]) -> [InstrumentLaunchIntent]`. Task 5 depends on exactly this.

- [ ] **Step 1: Write the failing tests**

```swift
#if DEBUG
import Foundation
import Testing
@testable import Talaria

/// #333: pure parse of the launch environment. Legacy #196 vars map onto
/// registry names so the old contract keeps working with no second mechanism.
struct InstrumentLaunchIntentTests {

    @Test func newVarsParseNameTrialsAndCells() {
        let intents = InstrumentLaunchIntent.parse([
            "TALARIA_RUN_INSTRUMENT": "action",
            "TALARIA_TRIALS": "5",
            "TALARIA_CELLS": "armed,armed-routed",
        ])
        #expect(intents == [InstrumentLaunchIntent(name: "action", trials: 5, cells: ["armed", "armed-routed"])])
    }

    @Test func trialsDefaultsToTenAndCellsToNil() {
        let intents = InstrumentLaunchIntent.parse(["TALARIA_RUN_INSTRUMENT": "shape"])
        #expect(intents == [InstrumentLaunchIntent(name: "shape", trials: 10, cells: nil)])
    }

    @Test func legacyVarsMapToRegistryNamesInLegacyOrder() {
        // #196's contract: battery first, then probe, both runnable in one launch.
        let intents = InstrumentLaunchIntent.parse([
            "TALARIA_AUTO_BATTERY": "3",
            "TALARIA_AUTO_ROUTER_PROBE": "4",
        ])
        #expect(intents == [
            InstrumentLaunchIntent(name: "shape", trials: 3, cells: nil),
            InstrumentLaunchIntent(name: "router-probe", trials: 4, cells: nil),
        ])
    }

    @Test func emptyOrGarbageEnvironmentParsesToNothing() {
        #expect(InstrumentLaunchIntent.parse([:]).isEmpty)
        #expect(InstrumentLaunchIntent.parse(["TALARIA_TRIALS": "5"]).isEmpty)
        #expect(InstrumentLaunchIntent.parse(["TALARIA_AUTO_BATTERY": "many"]).isEmpty)
    }
}
#endif
```

- [ ] **Step 2: Run to verify failure** (build error: type not defined; confirm 4 tests once compiling).
- [ ] **Step 3: Implement**

```swift
#if DEBUG
import Foundation

/// #333: one requested instrument run, parsed from launch environment.
/// Pure function of the env dictionary — trivially testable, no ProcessInfo.
struct InstrumentLaunchIntent: Equatable {
    var name: String
    var trials: Int
    var cells: [String]?

    static func parse(_ env: [String: String]) -> [InstrumentLaunchIntent] {
        var intents: [InstrumentLaunchIntent] = []
        // #196 legacy vars first, in their original order (battery, then probe).
        if let trials = env["TALARIA_AUTO_BATTERY"].flatMap(Int.init) {
            intents.append(.init(name: "shape", trials: trials, cells: nil))
        }
        if let trials = env["TALARIA_AUTO_ROUTER_PROBE"].flatMap(Int.init) {
            intents.append(.init(name: "router-probe", trials: trials, cells: nil))
        }
        if let name = env["TALARIA_RUN_INSTRUMENT"], !name.isEmpty {
            let trials = env["TALARIA_TRIALS"].flatMap(Int.init) ?? 10
            let cells = env["TALARIA_CELLS"].map { $0.split(separator: ",").map(String.init) }
            intents.append(.init(name: name, trials: trials, cells: cells))
        }
        return intents
    }
}
#endif
```

- [ ] **Step 4: Run tests to verify pass** (4/4).
- [ ] **Step 5: Commit** — `feat(#333): launch-env intent parser with #196 legacy mapping`

---

### Task 3: `InstrumentRegistry` — three canonical entries

**Files:**
- Create: `Talaria/Services/Live/InstrumentRegistry.swift`
- Test: `TalariaTests/InstrumentRegistryTests.swift`

**Interfaces:**
- Consumes: `LocalChatBackend.runShapeBattery(trials:)`, `.runActionBattery(trials:)` (its extra params have defaults — call exactly as `DeveloperSettingsScreen.swift:681` does), `.runReadToolBattery(trials:)`, `.runRouterProbe(trials:)`.
- Produces (Task 4/5/6 depend on these exact shapes):

```swift
struct InstrumentSpec {
    enum ConfirmationMode { case autoAccept, autoDecline, none }
    let name: String
    let confirmationMode: ConfirmationMode
    let writesEventKit: Bool
    let writesAlarms: Bool
    // Backend is optional so conductor tests can exercise flag discipline with
    // no LocalChatBackend; every registry entry guard-lets it first thing.
    let run: @MainActor (LocalChatBackend?, _ trials: Int, _ cells: [String]?) async -> Void
}
enum InstrumentRegistry {
    static let all: [InstrumentSpec]
    static func spec(named: String) -> InstrumentSpec?
}
```

- [ ] **Step 1: Write the failing tests**

```swift
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
}
#endif
```

- [ ] **Step 2: Run to verify failure.**
- [ ] **Step 3: Implement** — four entries now; the sweep in Task 6 adds the rest:

```swift
#if DEBUG
import Foundation

/// #333: one reachable instrument. `run` binds the EXACT call the
/// Developer-screen button makes — the button and the trigger share this
/// closure, which is the whole of bar 333-B. Capability flags feed the
/// conductor's refusal rules (alarms never unattended — Owen 2026-08-11;
/// EventKit never on an iPad — Shelley's-device rule made structural).
struct InstrumentSpec {
    enum ConfirmationMode { case autoAccept, autoDecline, none }
    let name: String
    let confirmationMode: ConfirmationMode
    let writesEventKit: Bool
    let writesAlarms: Bool
    let run: @MainActor (LocalChatBackend, _ trials: Int, _ cells: [String]?) async -> Void
}

enum InstrumentRegistry {
    static let all: [InstrumentSpec] = [
        // #196: composition/decline battery. Headless sessions can never answer
        // a confirmation card, so grabs auto-decline — which also measures
        // post-denial recovery.
        InstrumentSpec(name: "shape", confirmationMode: .autoDecline,
                       writesEventKit: false, writesAlarms: false,
                       run: { backend, trials, _ in
                           guard let backend else { return }
                           await backend.runShapeBattery(trials: trials)
                       }),
        // #200: the action-SUCCESS path — real EventKit/AlarmKit writes,
        // marker-tagged, reaped (#331 container).
        InstrumentSpec(name: "action", confirmationMode: .autoAccept,
                       writesEventKit: true, writesAlarms: true,
                       run: { backend, trials, cells in
                           guard let backend else { return }
                           if let cells { await backend.runActionBattery(trials: trials, cells: cells) }
                           else { await backend.runActionBattery(trials: trials) }
                       }),
        // Read-only tools; nothing to accept or decline.
        InstrumentSpec(name: "read-tool", confirmationMode: .none,
                       writesEventKit: false, writesAlarms: false,
                       run: { backend, trials, _ in
                           guard let backend else { return }
                           await backend.runReadToolBattery(trials: trials)
                       }),
        // #196: router classification probe — FM-only, no tool execution.
        InstrumentSpec(name: "router-probe", confirmationMode: .none,
                       writesEventKit: false, writesAlarms: false,
                       run: { backend, trials, _ in
                           guard let backend else { return }
                           await backend.runRouterProbe(trials: trials)
                       }),
    ]

    static func spec(named name: String) -> InstrumentSpec? {
        all.first { $0.name == name }
    }
}
#endif
```

(Check `runActionBattery`'s real signature at `LocalChatBackend+Battery.swift:734` before writing the `cells` arm — if the `cells:` label differs, bind it exactly as the button does and adjust the closure; the registry must never invent an argument the button doesn't pass.)

- [ ] **Step 4: Run tests to verify pass** (3/3).
- [ ] **Step 5: Commit** — `feat(#333): instrument registry — the one dispatch table (4 canonical entries)`

---

### Task 4: `InstrumentConductor` — flag discipline, refusals, artifact

**Files:**
- Create: `Talaria/Services/Live/InstrumentConductor.swift`
- Test: `TalariaTests/InstrumentConductorTests.swift`

**Interfaces:**
- Consumes: Task 1's writer/envelope, Task 3's `InstrumentSpec`, `ToolConfirmationCenter.autoAcceptForBattery`/`.autoDeclineForBattery`, `BatteryTestContainer.alarmWritesAttended`, `LocalChatBackend.batteryRunStore.loadRuns()` (static store; newest-first), `LocalChatBackend.batteryEmit(_:)`.
- Produces: `@MainActor final class InstrumentConductor` with `init(confirmationCenter:backend:artifactWriter:idiom:env:)` (trailing three defaulted) and `func run(spec: InstrumentSpec, trials: Int, cells: [String]?, unattended: Bool) async -> InstrumentRunStatus`. Tasks 5/6 call exactly this.

- [ ] **Step 1: Write the failing tests**

```swift
#if DEBUG
import Foundation
import UIKit
import Testing
@testable import Talaria

/// #333 bars D and E, as unit tests: flags explicit on every path, cleared on
/// every exit; alarm-flagged refuses unattended; EventKit-flagged refuses on
/// iPad; a refusal writes an artifact and never invokes the instrument.
@MainActor
struct InstrumentConductorTests {

    private func makeConductor(idiom: UIUserInterfaceIdiom = .phone,
                               center: ToolConfirmationCenter = ToolConfirmationCenter())
        -> (InstrumentConductor, ToolConfirmationCenter, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("conductor-tests-\(UUID().uuidString)", isDirectory: true)
        let conductor = InstrumentConductor(
            confirmationCenter: center, backend: nil,
            artifactWriter: InstrumentArtifactWriter(directory: dir),
            idiom: idiom, env: ["TALARIA_BUILD_SHA": "testsha"])
        return (conductor, center, dir)
    }

    private func spec(_ name: String, mode: InstrumentSpec.ConfirmationMode,
                      eventKit: Bool = false, alarms: Bool = false,
                      run: @escaping @MainActor (LocalChatBackend?, Int, [String]?) async -> Void = { _, _, _ in })
        -> InstrumentSpec {
        InstrumentSpec(name: name, confirmationMode: mode,
                       writesEventKit: eventKit, writesAlarms: alarms,
                       run: { b, t, c in await run(b, t, c) })
    }

    private func latest(in dir: URL) throws -> InstrumentResultEnvelope {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(InstrumentResultEnvelope.self,
                                  from: Data(contentsOf: dir.appendingPathComponent("latest.json")))
    }

    @Test func acceptModeAttendedArmsAcceptAndAlarmsThenClearsEverything() async throws {
        var seen: (accept: Bool, decline: Bool, alarms: Bool)?
        let (conductor, center, _) = makeConductor()
        let s = spec("t-accept", mode: .autoAccept, eventKit: true, alarms: true) { _, _, _ in
            seen = (center.autoAcceptForBattery, center.autoDeclineForBattery,
                    BatteryTestContainer.alarmWritesAttended)
        }
        let status = await conductor.run(spec: s, trials: 1, cells: nil, unattended: false)
        #expect(status == .completed)
        #expect(seen! == (accept: true, decline: false, alarms: true))
        #expect(!center.autoAcceptForBattery && !center.autoDeclineForBattery)
        #expect(!BatteryTestContainer.alarmWritesAttended)
    }

    @Test func declineModeUnattendedArmsDeclineAndNeverAlarms() async throws {
        var seen: (accept: Bool, decline: Bool, alarms: Bool)?
        let (conductor, center, _) = makeConductor()
        let s = spec("t-decline", mode: .autoDecline) { _, _, _ in
            seen = (center.autoAcceptForBattery, center.autoDeclineForBattery,
                    BatteryTestContainer.alarmWritesAttended)
        }
        _ = await conductor.run(spec: s, trials: 1, cells: nil, unattended: true)
        #expect(seen! == (accept: false, decline: true, alarms: false))
        #expect(!center.autoDeclineForBattery)
    }

    @Test func alarmFlaggedRefusesUnattendedWithoutInvoking() async throws {
        var invoked = false
        let (conductor, _, dir) = makeConductor()
        let s = spec("t-alarm", mode: .autoAccept, alarms: true) { _, _, _ in invoked = true }
        let status = await conductor.run(spec: s, trials: 1, cells: nil, unattended: true)
        #expect(status == .refused)
        #expect(!invoked)
        let envelope = try latest(in: dir)
        #expect(envelope.status == .refused)
        #expect(envelope.refusalReason?.contains("alarm") == true)
        #expect(!BatteryTestContainer.alarmWritesAttended)
    }

    @Test func eventKitFlaggedRefusesOnPadEvenAttended() async throws {
        var invoked = false
        let (conductor, _, dir) = makeConductor(idiom: .pad)
        let s = spec("t-ek", mode: .autoAccept, eventKit: true) { _, _, _ in invoked = true }
        let status = await conductor.run(spec: s, trials: 1, cells: nil, unattended: false)
        #expect(status == .refused)
        #expect(!invoked)
        #expect(try latest(in: dir).refusalReason?.contains("iPad") == true)
    }

    @Test func envelopeIsRunningDuringExecutionAndCompletedAfter() async throws {
        let (conductor, _, dir) = makeConductor()
        var midRun: InstrumentResultEnvelope?
        let s = spec("t-status", mode: .none) { _, _, _ in
            midRun = try? self.latest(in: dir)
        }
        _ = await conductor.run(spec: s, trials: 2, cells: ["a"], unattended: true)
        #expect(midRun?.status == .running)          // bar 333-C's schema half
        let final = try latest(in: dir)
        #expect(final.status == .completed)
        #expect(final.endedAt != nil)
        #expect(final.instrument == "t-status" && final.trialsRequested == 2)
        #expect(final.buildSha == "testsha")
        #expect(final.unattended)
    }

}
#endif
```

- [ ] **Step 2: Run to verify failure.**
- [ ] **Step 3: Implement**

```swift
#if DEBUG
import Foundation
import UIKit

/// #333: the ONE code path from "run instrument X" to "artifact on disk" —
/// buttons pass `unattended: false`, the launch-env trigger `unattended: true`.
/// Owns the #196/#200/#331 flag discipline the buttons used to hand-copy:
/// modes are mutually exclusive, set explicitly on every path (never
/// inherited), and cleared on every exit — `defer`, so an early return or a
/// cancelled Task cannot leave a flag armed (bar 333-D). Refusals (bar 333-E):
/// alarm-flagged instruments never run unattended (Owen's 2026-08-11 ruling;
/// `alarmWritesAttended` means "a human tapped" and this class never sets it
/// for an unattended run), and EventKit-flagged instruments never run on an
/// iPad (Shelley's-device rule, enforced by hardware class rather than by
/// trusting the caller). A refusal still writes an artifact naming the reason,
/// so the harness reads REFUSED rather than timing out.
@MainActor
final class InstrumentConductor {
    private let confirmationCenter: ToolConfirmationCenter
    private let backend: LocalChatBackend?
    private let artifactWriter: InstrumentArtifactWriter
    private let idiom: UIUserInterfaceIdiom
    private let env: [String: String]

    init(confirmationCenter: ToolConfirmationCenter,
         backend: LocalChatBackend?,
         artifactWriter: InstrumentArtifactWriter = InstrumentArtifactWriter(directory: InstrumentArtifactWriter.defaultDirectory),
         idiom: UIUserInterfaceIdiom = UIDevice.current.userInterfaceIdiom,
         env: [String: String] = ProcessInfo.processInfo.environment) {
        self.confirmationCenter = confirmationCenter
        self.backend = backend
        self.artifactWriter = artifactWriter
        self.idiom = idiom
        self.env = env
    }

    @discardableResult
    func run(spec: InstrumentSpec, trials: Int, cells: [String]?,
             unattended: Bool) async -> InstrumentRunStatus {
        var envelope = InstrumentResultEnvelope(
            instrument: spec.name, trialsRequested: trials, cells: cells,
            unattended: unattended, startedAt: Date(), endedAt: nil,
            deviceModel: UIDevice.current.model,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?",
            buildSha: env["TALARIA_BUILD_SHA"],
            status: .running, refusalReason: nil, runRecord: nil)

        func finish(_ status: InstrumentRunStatus, reason: String? = nil) -> InstrumentRunStatus {
            envelope.status = status
            envelope.refusalReason = reason
            envelope.endedAt = Date()
            try? artifactWriter.write(envelope)
            LocalChatBackend.batteryEmit("instrument: \(status.rawValue.uppercased()) \(spec.name) (#333)")
            return status
        }

        if spec.writesAlarms && unattended {
            return finish(.refused, reason: "alarm-writing instruments never run unattended (Owen 2026-08-11; #331)")
        }
        if spec.writesEventKit && idiom == .pad {
            return finish(.refused, reason: "EventKit-writing instruments never run on an iPad (Shelley's-device rule)")
        }

        try? artifactWriter.write(envelope) // status: running — bar 333-C

        // Explicit on EVERY path; mutually exclusive; never inherited.
        confirmationCenter.autoAcceptForBattery = (spec.confirmationMode == .autoAccept)
        confirmationCenter.autoDeclineForBattery = (spec.confirmationMode == .autoDecline)
        BatteryTestContainer.alarmWritesAttended =
            (spec.confirmationMode == .autoAccept && spec.writesAlarms && !unattended)
        UIApplication.shared.isIdleTimerDisabled = true
        defer {
            confirmationCenter.autoAcceptForBattery = false
            confirmationCenter.autoDeclineForBattery = false
            BatteryTestContainer.alarmWritesAttended = false
            UIApplication.shared.isIdleTimerDisabled = false
        }

        let priorNewestID = LocalChatBackend.batteryRunStore.loadRuns().first?.id
        await spec.run(backend, trials, cells)
        if let newest = LocalChatBackend.batteryRunStore.loadRuns().first, newest.id != priorNewestID {
            envelope.runRecord = newest
        }
        return finish(.completed)
    }
}
#endif
```

(If `ToolConfirmationCenter()` needs arguments in its initializer, construct it however `AppContainer` does — read its definition first; the tests only need a real instance whose two `Bool`s can be read. If `LocalChatBackend.batteryRunStore` is not reachable as written, use the exact static spelling from `LocalChatBackend+Battery.swift:76-77`. The conductor's `backend` is optional purely as the test seam — production callers guard it non-nil before constructing the conductor, and every registry closure guard-lets it.)

- [ ] **Step 4: Run tests to verify pass** (5/5). Also re-run Tasks 1–3 tests.
- [ ] **Step 5: Commit** — `feat(#333): instrument conductor — one code path, refusals, artifact`

---

### Task 5: Wire the launch trigger (supersede #196's narrow one)

**Files:**
- Modify: `Talaria/Stores/AppContainer.swift:2487-2521` (replace `runAutoBatteryIfArmed`)
- Modify: `Talaria/AppEntry.swift:132-137` (call site)
- Test: extend `TalariaTests/InstrumentLaunchIntentTests.swift`

**Interfaces:**
- Consumes: Tasks 2/3/4.
- Produces: `AppContainer.runAutoInstrumentsIfArmed()` — the only launch-side entry.

- [ ] **Step 1: Replace the #196 body** (keep the `#if DEBUG` fence and MARK; update the comment):

```swift
#if DEBUG
// MARK: - #333 instrument trigger (DEBUG builds only; supersedes #196's pair)

extension AppContainer {
    /// Autonomous runs: `TALARIA_RUN_INSTRUMENT=<name>` (+ `TALARIA_TRIALS`,
    /// `TALARIA_CELLS`) runs any registry instrument on launch; the #196 pair
    /// (`TALARIA_AUTO_BATTERY`, `TALARIA_AUTO_ROUTER_PROBE`) still works,
    /// mapped onto the same registry — one mechanism, no drift. Armed only by
    /// launch environment (devicectl passes `DEVICECTL_CHILD_`-prefixed vars;
    /// simctl passes `SIMCTL_CHILD_`-prefixed), inert in every normal run.
    /// Every run is `unattended: true` by definition here — the conductor
    /// refuses alarm-flagged instruments and never arms `alarmWritesAttended`.
    @MainActor
    func runAutoInstrumentsIfArmed() async {
        let env = ProcessInfo.processInfo.environment
        let intents = InstrumentLaunchIntent.parse(env)
        guard !intents.isEmpty, let backend = localChatBackend else { return }
        let conductor = InstrumentConductor(confirmationCenter: toolConfirmationCenter, backend: backend)
        for intent in intents {
            guard let spec = InstrumentRegistry.spec(named: intent.name) else {
                LocalChatBackend.batteryEmit("instrument: UNKNOWN \(intent.name) (#333)")
                continue
            }
            await conductor.run(spec: spec, trials: intent.trials, cells: intent.cells, unattended: true)
        }
        LocalChatBackend.batteryEmit("instrument: AUTO COMPLETE (#333)")
    }
}
#endif
```

- [ ] **Step 2: Update the call site** in `AppEntry.swift` — replace `await container.runAutoBatteryIfArmed()` with `await container.runAutoInstrumentsIfArmed()` (keep the surrounding `#if DEBUG` and the "#196 battery 4" comment, updating its text to name #333 and note the #196 vars still work).
- [ ] **Step 3: Grep for stragglers** — `grep -rn "runAutoBatteryIfArmed" Talaria/ TalariaTests/ TalariaUITests/` must return nothing.
- [ ] **Step 4: Add one parser test asserting all three vars can coexist** (legacy pair + new var → 3 intents, legacy order first) and run the full `TalariaTests/Instrument*` set — all green.
- [ ] **Step 5: Sim smoke of the mechanics** (the sim cannot generate — trials will error; the point is dispatch + artifact, not data):

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta5.app/Contents/Developer
UDID=$(xcrun simctl list devices | grep "CC-333-iPhone-Air" | grep -oE '[0-9A-F-]{36}')
xcrun simctl boot "$UDID" 2>/dev/null; xcrun simctl privacy "$UDID" grant calendar org.aethyrion.talaria27; xcrun simctl privacy "$UDID" grant reminders org.aethyrion.talaria27
# build + install the Debug app, then:
SIMCTL_CHILD_TALARIA_RUN_INSTRUMENT=router-probe SIMCTL_CHILD_TALARIA_TRIALS=1 xcrun simctl launch "$UDID" org.aethyrion.talaria27
sleep 90 && APP_DATA=$(xcrun simctl get_app_container "$UDID" org.aethyrion.talaria27 data)
python3 -c "import json,sys; d=json.load(open('$APP_DATA/Documents/InstrumentRuns/latest.json')); print(d['status'], d['instrument'])"
```

Expected: a `latest.json` exists with `instrument == "router-probe"` and a terminal status (`completed` even if trials errored — errors live in the record; `failed` only if the backend was absent). If no file appears, the trigger never fired — check the env prefix before suspecting the code.
- [ ] **Step 6: Commit** — `feat(#333): launch trigger dispatches the registry; #196 vars mapped, not duplicated`

---

### Task 6: Button sweep — every Developer-screen instrument through the conductor

**Files:**
- Modify: `Talaria/Features/Settings/DeveloperSettingsScreen.swift` (the ~25 `@ViewBuilder` battery button factories, lines ~626-2280)
- Modify: `Talaria/Services/Live/InstrumentRegistry.swift` (add the remaining entries)
- Test: extend `TalariaTests/InstrumentRegistryTests.swift`

**Interfaces:**
- Consumes: Task 4's `InstrumentConductor.run(spec:trials:cells:unattended:)`.
- Produces: one generic factory `instrumentButton(_ name: String, trials: Int, label: String)`; every battery button uses it; registry covers every button.

- [ ] **Step 1 (6a): Convert the three canonical buttons** (`batteryButton` → "shape", `actionBatteryButton` → "action", `readToolBatteryButton` → "read-tool") to a single generic factory:

```swift
// #333: ONE factory for every instrument button. The action is the same
// conductor call the launch-env trigger makes — bar 333-B's "one code path"
// is this line. `batteryRunning` stays a UI-only double-fire guard; the real
// mutex is backend-owned (beginBatteryRun).
@ViewBuilder
private func instrumentButton(_ name: String, trials: Int, label: String) -> some View {
    Button {
        guard !batteryRunning,
              let backend = container.localChatBackend,
              let spec = InstrumentRegistry.spec(named: name) else { return }
        batteryRunning = true
        Task {
            let conductor = InstrumentConductor(
                confirmationCenter: container.toolConfirmationCenter, backend: backend)
            await conductor.run(spec: spec, trials: trials, cells: nil, unattended: false)
            batteryRunning = false
        }
    } label: {
        MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                  size: 10, tracking: Design.Tracking.mono,
                  color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
    }
    .disabled(batteryRunning)
}
```

Replace each converted factory's call sites (e.g. `batteryButton(trials: 10, label: …)` → `instrumentButton("shape", trials: 10, label: …)`), delete the converted factory bodies, and MOVE each deleted factory's measurement-rationale comment onto its registry entry (the comments are load-bearing history — they must not be lost). Run the Task 3/4 tests + a full sim build. Commit: `refactor(#333): three canonical buttons through the conductor`.

- [ ] **Step 2 (6b): Sweep the remaining factories.** For EACH remaining `*BatteryButton`/`*ProbeButton` factory (enumerate them — the known list: `destallBatteryButton`, `instrfixBatteryButton`, `toolmodeBatteryButton`, `communityBatteryButton`, `findfixBatteryButton`, `spiralBatteryButton`, `spiralfixBatteryButton`, `scopedV2BatteryButton`, `routedBatteryButton`, `routedScopedBatteryButton`, `intentRouterProbeButton`, `vectorRouterProbeButton`, `toollessIndexBatteryButton`, `capabilityDetectionProbeButton`, `crossChatRecallProbeButton`, `motionRedirectBatteryButton`, `motionScopeBatteryButton`, `honestyV2BatteryButton`, `longContextProbeButton`, plus any this list missed — grep `private func.*[Bb]attery.*Button|ProbeButton` to be exhaustive):
  1. Read the factory body. Note (a) the exact backend call with ALL its arguments, (b) which flags it sets (accept / decline / neither, `alarmWritesAttended`), and (c) its rationale comment.
  2. Add a registry entry: kebab-case name derived from the factory (e.g. `destallBatteryButton` → `"destall"`), `confirmationMode` from (b), `writesEventKit`/`writesAlarms` from (b)+(a) (accept-mode batteries that create reminders/events set `writesEventKit: true`; ones that also schedule alarms set `writesAlarms: true` — the #200-family accept batteries do both; read the method if unsure), `run` closure = the exact call from (a) with extra parameters (e.g. `ticTrials`) bound to the values the button passes today. Comment = (c).
  3. Replace the factory's call sites with `instrumentButton(...)` and delete the factory.
  4. **If a factory does anything besides the standard pattern** (extra UI, extra state, a second backend call), do NOT force it — leave it custom but route its backend call through the conductor, and note it in the commit message.
- [ ] **Step 3: Extend the registry test** with a completeness pin:

```swift
@Test func registryCoversEveryDeveloperScreenInstrument() {
    // Grep-derived pin: if a button is added without a registry entry, this
    // count is the tripwire. Update it WITH the new entry, in the same commit.
    #expect(InstrumentRegistry.all.count >= 20)
}
```

(Set the literal to the actual final count, `>=` so future additions don't red it.)
- [ ] **Step 4: Full local suite + sim build green; confirm the reported test count MOVED vs 2145** (stale-binary check). Spot-check two converted buttons in the sim by tapping them (Developer screen) and confirming a `latest.json` appears with `unattended: false`.
- [ ] **Step 5: Commit** — `refactor(#333): every instrument button through the registry + conductor`

---

### Task 7: xcodegen, gate, Release proof

- [ ] **Step 1:** `xcodegen generate` (new files were added in Tasks 1–4) — commit the regenerated `project.pbxproj` (idempotent since #319).
- [ ] **Step 2:** Dedicated sim + TCC (a fresh sim HANGS the suite otherwise — re-grant before EVERY run; it does not survive reinstall):

```bash
xcrun simctl create "CC-333-iPhone-Air" com.apple.CoreSimulator.SimDeviceType.iPhone-Air com.apple.CoreSimulator.SimRuntime.iOS-27-0 2>/dev/null || true
UDID=$(xcrun simctl list devices | grep "CC-333-iPhone-Air" | grep -oE '[0-9A-F-]{36}')
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl privacy "$UDID" grant calendar org.aethyrion.talaria27
xcrun simctl privacy "$UDID" grant reminders org.aethyrion.talaria27
```

- [ ] **Step 3:** `TALARIA_SIM_NAME=CC-333-iPhone-Air scripts/mac/lane-gate.sh` — background it, poll the log, require the POSITIVE success marker (`GATE: PASS`) and a moved test count (bar 333-H). Check `pgrep -fl xcodebuild` for concurrent builds before believing any failure.
- [ ] **Step 4:** The gate includes a Release build; confirm its success marker explicitly — that is bar 333-F's evidence. If the gate's Release leg is ever skipped, run the CLAUDE.md Release command manually.
- [ ] **Step 5:** Commit anything the gate surfaced; record `GATE: PASS` + counts in the eventual tracker note.

---

### Task 8: The Mac-side harness — `scripts/mac/run-instrument.sh`

**Files:**
- Create: `scripts/mac/run-instrument.sh` (`chmod +x`)

**Interfaces:**
- Consumes: the installed Debug app on a physical device; Task 1's status strings (`running|completed|refused|failed`); `Documents/InstrumentRuns/latest.json`.
- Produces: exit 0 + artifact path on `completed`/`refused`; exit 1 on `failed`; exit 2 on TIMEOUT; exit 3 on precondition failure. Artifacts land in `~/.talaria-instrument-runs/<UTC-stamp>-<instrument>/`.

- [ ] **Step 1: Write the script**

```bash
#!/bin/bash
# #333: launch an instrument on a device via launch env, poll the artifact
# with a HARD timeout (a TCC hang parks a run silently — the harness detects
# it, not a human), fetch, and verify the POSITIVE completion flag.
# Usage: run-instrument.sh --device <name|udid> --instrument <name> [--trials N]
#        [--cells a,b] [--timeout SECONDS] [--out DIR]
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta5.app/Contents/Developer}"
BUNDLE_ID="org.aethyrion.talaria27"
DEVICE="" INSTRUMENT="" TRIALS=10 CELLS="" TIMEOUT=1800 OUT_ROOT="$HOME/.talaria-instrument-runs"
while [[ $# -gt 0 ]]; do case "$1" in
  --device) DEVICE="$2"; shift 2;; --instrument) INSTRUMENT="$2"; shift 2;;
  --trials) TRIALS="$2"; shift 2;; --cells) CELLS="$2"; shift 2;;
  --timeout) TIMEOUT="$2"; shift 2;; --out) OUT_ROOT="$2"; shift 2;;
  *) echo "unknown arg: $1" >&2; exit 3;;
esac; done
[[ -n "$DEVICE" && -n "$INSTRUMENT" ]] || { echo "need --device and --instrument" >&2; exit 3; }

# Resolve to a PHYSICAL device udid (the Reality column — a sim match here
# once produced a phantom-hardware recommendation).
UDID=$(xcrun devicectl list devices 2>/dev/null | awk -v d="$DEVICE" \
  '$0 ~ d && /physical/ {for(i=1;i<=NF;i++) if ($i ~ /^[0-9A-F-]{36}$/) print $i}' | head -1)
[[ -n "$UDID" ]] || { echo "PRECONDITION: no connected physical device matching '$DEVICE'" >&2; exit 3; }

STAMP=$(date -u +%Y%m%dT%H%M%SZ); OUT_DIR="$OUT_ROOT/$STAMP-$INSTRUMENT"; mkdir -p "$OUT_DIR"
SHA=$(git -C "$(dirname "$0")/../.." rev-parse --short HEAD 2>/dev/null || echo unknown)
echo "device=$UDID instrument=$INSTRUMENT trials=$TRIALS cells=$CELLS timeout=${TIMEOUT}s sha=$SHA" | tee "$OUT_DIR/run.log"

# Launch. DEVICECTL_CHILD_* is the proven env bridge (HANDOFF-2026-07-28).
# --console streams app stdout; background it — it blocks for the app's life.
DEVICECTL_CHILD_TALARIA_RUN_INSTRUMENT="$INSTRUMENT" \
DEVICECTL_CHILD_TALARIA_TRIALS="$TRIALS" \
DEVICECTL_CHILD_TALARIA_CELLS="$CELLS" \
DEVICECTL_CHILD_TALARIA_BUILD_SHA="$SHA" \
xcrun devicectl device process launch --terminate-existing --console \
  --device "$UDID" "$BUNDLE_ID" >> "$OUT_DIR/console.log" 2>&1 &
LAUNCH_PID=$!
echo "launched (console pid $LAUNCH_PID); polling every 20s" | tee -a "$OUT_DIR/run.log"

fetch_latest() {
  rm -f "$OUT_DIR/latest.json"
  xcrun devicectl device copy from --device "$UDID" \
    --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" \
    --source "Documents/InstrumentRuns/latest.json" \
    --destination "$OUT_DIR/latest.json" >/dev/null 2>&1 || return 1
}
status_of() { python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('status',''))" "$1" 2>/dev/null || echo ""; }
started_of() { python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('startedAt',''))" "$1" 2>/dev/null || echo ""; }

ELAPSED=0; STATUS=""; FIRST_STARTED=""
while (( ELAPSED < TIMEOUT )); do
  sleep 20; ELAPSED=$((ELAPSED+20))
  fetch_latest || continue
  S=$(status_of "$OUT_DIR/latest.json"); STARTED=$(started_of "$OUT_DIR/latest.json")
  # Guard against reading a PREVIOUS run's terminal artifact: only trust a
  # terminal status once we've seen THIS run's file (startedAt changes).
  if [[ -z "$FIRST_STARTED" && -n "$STARTED" ]]; then
    if [[ "$S" == "running" ]]; then FIRST_STARTED="$STARTED";
    elif (( ELAPSED >= 60 )); then FIRST_STARTED="$STARTED"; fi   # fast refusal never shows running
  fi
  [[ -n "$FIRST_STARTED" ]] || continue
  if [[ "$S" != "running" && -n "$S" ]]; then STATUS="$S"; break; fi
  echo "t+${ELAPSED}s status=$S" | tee -a "$OUT_DIR/run.log"
done
kill "$LAUNCH_PID" 2>/dev/null || true

if [[ -z "$STATUS" ]]; then
  echo "TIMEOUT after ${TIMEOUT}s — run NOT complete. Fetching store snapshots for post-mortem." | tee -a "$OUT_DIR/run.log"
  xcrun devicectl device copy from --device "$UDID" \
    --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" \
    --source "Library/Application Support/BatteryRuns" \
    --destination "$OUT_DIR/BatteryRuns" >/dev/null 2>&1 || true
  exit 2
fi
echo "RESULT: $STATUS — artifact at $OUT_DIR/latest.json" | tee -a "$OUT_DIR/run.log"
case "$STATUS" in completed|refused) exit 0;; *) exit 1;; esac
```

- [ ] **Step 2: Dry-check the option parsing and awk filter** without a device: `bash -n scripts/mac/run-instrument.sh` and `scripts/mac/run-instrument.sh --instrument x --device no-such-device` → expect exit 3 with the PRECONDITION line.
- [ ] **Step 3: Commit** — `feat(#333): run-instrument.sh — launch, poll with hard timeout, fetch, verify`

---

### Task 9: Device witnesses — bars A, C, E (and G)

Nothing here runs EventKit/AlarmKit on the iPad; the chosen instrument (`router-probe`) executes no tools at all.

- [ ] **Step 1 (bar A):** Build + install Debug to the iPad (`4822A154-722B-53EB-81A2-84357FD03719`), then `scripts/mac/run-instrument.sh --device 4822A154 --instrument router-probe --trials 2 --timeout 900`. Expect exit 0, `status=completed`, and a `runRecord` whose probe rows carry real classifications (the iPad generates — verified §9a). Hands off the device throughout: the witness is that nobody touched it.
- [ ] **Step 2 (bar C):** Start `--instrument router-probe --trials 20`, and ~60 s in (after `status=running` is observed in run.log), kill the app: `xcrun devicectl device process launch --terminate-existing` of a benign second launch, or `devicectl device process terminate` if available — whatever kills the process; record which. The harness must exit 2 (TIMEOUT) or read a non-terminal artifact; the fetched `latest.json` must still say `running` and the fetched `BatteryRuns` snapshot must show `endedCleanly: false` — the partial is distinguishable (bar C witnessed by killing, not reasoning).
- [ ] **Step 3 (bar E, both arms):** (a) iPad: `--instrument action --trials 1` → exit 0 with `status=refused`, reason naming the iPad, zero writes anywhere; (b) sim (alarm arm, distinct from the pad arm): `SIMCTL_CHILD_TALARIA_RUN_INSTRUMENT=action` launch on CC-333 → `latest.json` `status=refused`, reason naming alarms/unattended. Keep both artifacts.
- [ ] **Step 4 (bar G):** already witnessed by Step 2's timeout path; note the exit code + fetched snapshot in the tracker evidence.
- [ ] **Step 5:** Copy the three artifacts into the tracker note (quoted, not summarized) at #333.

---

### Task 10: Close-out + merge

- [ ] **Step 1:** `OPEN_ITEMS.md` #333 — dated note scoring every bar A–H with the evidence (artifact excerpts, gate line, kill procedure used). Any missed bar is reported as missed, not redefined.
- [ ] **Step 2:** `OPEN_ITEMS-ARCHIVE.md` #196 — append-only dated pointer block (never edit the original bytes): the auto-battery trigger is superseded by #333's registry; the two env vars still work, mapped.
- [ ] **Step 3:** `planning/UNATTENDED-RUNS-HANDOFF.md` §3 — replace the hand-run procedure with `run-instrument.sh` usage (dated note; the §1 device rules and §4 scoring rules stand).
- [ ] **Step 4:** Confirm nothing else this build falsifies: grep `TALARIA_AUTO_BATTERY` and `runAutoBatteryIfArmed` across `*.md` — historical handoffs stay as-is (dated records of their day), live docs get the supersession note.
- [ ] **Step 5:** Merge `t27-333-instrument-runner` to `main` (merge authority granted this thread), push, verify `git log --oneline -3` shows the merge.
