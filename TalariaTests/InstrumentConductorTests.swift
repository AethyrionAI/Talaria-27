#if DEBUG
import Foundation
import UIKit
import Testing
@testable import Talaria

/// #333 bars D and E, as unit tests: flags explicit on every path, cleared on
/// every exit; alarm-flagged refuses unattended; EventKit-flagged refuses on
/// iPad; a refusal writes an artifact and never invokes the instrument.
///
/// Review fix (post-Task-4): `completed` means "a new `BatteryRunRecord`
/// exists and is embedded" — `spec.run` can return having done nothing (the
/// `beginBatteryRun()` mutex refusing a concurrent battery, or a recorder
/// bypass), and reporting `.completed` on the strength of "the closure
/// returned" would be a false positive on the one signal the runner exists
/// to make trustworthy. Every test below constructs its conductor with a
/// hermetic, per-test `RunsBox` rather than the real on-device
/// `LocalChatBackend.batteryRunStore` — tests that need `.completed` append
/// a minimal record to the box from inside the spec's `run` closure (mirrors
/// what a real instrument does by calling into the battery recorder); tests
/// that don't touch the box observe `.failed`, which is the correct,
/// non-lying terminal state for "nothing was recorded."
@MainActor
struct InstrumentConductorTests {

    /// Reference-type backing store for an injected `loadRuns` closure — a
    /// test's `spec.run` closure can append to it mid-run and the
    /// conductor's post-run read sees the mutation.
    private final class RunsBox {
        var records: [BatteryRunRecord] = []
    }

    private func minimalRunRecord() -> BatteryRunRecord {
        BatteryRunRecord(id: UUID(), startedAt: Date(), appVersion: "1.0", appBuild: "1",
                         osVersion: "test", trialsPerCell: 1, cells: [], trials: [], probes: [])
    }

    private func makeConductor(idiom: UIUserInterfaceIdiom = .phone,
                               center: ToolConfirmationCenter = ToolConfirmationCenter())
        -> (InstrumentConductor, ToolConfirmationCenter, URL, RunsBox) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("conductor-tests-\(UUID().uuidString)", isDirectory: true)
        let box = RunsBox()
        let conductor = InstrumentConductor(
            confirmationCenter: center, backend: nil,
            artifactWriter: InstrumentArtifactWriter(directory: dir),
            idiom: idiom, env: ["TALARIA_BUILD_SHA": "testsha"],
            loadRuns: { box.records })
        return (conductor, center, dir, box)
    }

    private func spec(_ name: String, mode: InstrumentSpec.ConfirmationMode,
                      eventKit: Bool = false, alarms: Bool = false,
                      defaultCells: [LocalChatBackend.ActionBatteryCell]? = nil,
                      run: @escaping @MainActor (LocalChatBackend?, Int,
                                                 [LocalChatBackend.ActionBatteryCell]?) async -> Void
                        = { _, _, _ in })
        -> InstrumentSpec {
        InstrumentSpec(name: name, confirmationMode: mode,
                       writesEventKit: eventKit, writesAlarms: alarms,
                       defaultCells: defaultCells,
                       run: { b, t, c in await run(b, t, c) })
    }

    private func latest(in dir: URL) throws -> InstrumentResultEnvelope {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(InstrumentResultEnvelope.self,
                                  from: Data(contentsOf: dir.appendingPathComponent("latest.json")))
    }

    @Test func acceptModeAttendedArmsAcceptAndAlarmsThenClearsEverything() async throws {
        var seen: (accept: Bool, decline: Bool, alarms: Bool)?
        let (conductor, center, _, box) = makeConductor()
        let s = spec("t-accept", mode: .autoAccept, eventKit: true, alarms: true) { _, _, _ in
            seen = (center.autoAcceptForBattery, center.autoDeclineForBattery,
                    BatteryTestContainer.alarmWritesAttended)
            // A real accept-mode instrument writes through the battery
            // recorder; simulate that so this run earns a genuine .completed.
            box.records = [self.minimalRunRecord()]
        }
        let status = await conductor.run(spec: s, trials: 1, cells: nil, unattended: false)
        #expect(status == .completed)
        #expect(seen! == (accept: true, decline: false, alarms: true))
        #expect(!center.autoAcceptForBattery && !center.autoDeclineForBattery)
        #expect(!BatteryTestContainer.alarmWritesAttended)
    }

    @Test func declineModeUnattendedArmsDeclineAndNeverAlarms() async throws {
        var seen: (accept: Bool, decline: Bool, alarms: Bool)?
        let (conductor, center, _, _) = makeConductor()
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
        let (conductor, _, dir, _) = makeConductor()
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
        let (conductor, _, dir, _) = makeConductor(idiom: .pad)
        let s = spec("t-ek", mode: .autoAccept, eventKit: true) { _, _, _ in invoked = true }
        let status = await conductor.run(spec: s, trials: 1, cells: nil, unattended: false)
        #expect(status == .refused)
        #expect(!invoked)
        #expect(try latest(in: dir).refusalReason?.contains("iPad") == true)
    }

    @Test func envelopeIsRunningDuringExecutionAndCompletedAfter() async throws {
        let (conductor, _, dir, box) = makeConductor()
        var midRun: InstrumentResultEnvelope?
        var recordID: UUID?
        let s = spec("t-status", mode: .none) { _, _, _ in
            midRun = try? self.latest(in: dir)
            let record = self.minimalRunRecord()
            recordID = record.id
            box.records = [record]
        }
        _ = await conductor.run(spec: s, trials: 2, cells: nil, unattended: true)
        #expect(midRun?.status == .running)          // bar 333-C's schema half
        let final = try latest(in: dir)
        #expect(final.status == .completed)
        #expect(final.endedAt != nil)
        #expect(final.instrument == "t-status" && final.trialsRequested == 2)
        #expect(final.buildSha == "testsha")
        #expect(final.unattended)
        #expect(final.runRecord?.id == recordID)
    }

    /// 🔒 #373, pinning #335's hazard SHUT. The conductor claims its run by SET
    /// DIFFERENCE against the ids present before it started, and until now
    /// nothing tested that: every other case here begins with an EMPTY store,
    /// where a set difference and `loadRuns().first` are indistinguishable. The
    /// fix landed 2026-08-21 and the reversion that undoes it would have been
    /// silent.
    ///
    /// The case that separates them is the one #335 described: `BatteryRunStore`
    /// sorts newest-first on `startedAt`, which persists as ISO8601 at SECOND
    /// granularity, so two records written inside one second decode to equal
    /// keys and the sort gives NO order between them. This test constructs that
    /// state directly — a foreign record still sitting at index 0 after the run
    /// — which is what an injected store lets us do and a real clock does not.
    ///
    /// **What it forecloses is not a crash.** It is the conductor embedding
    /// SOMEBODY ELSE'S run record in this run's artifact and sealing it
    /// `.completed`: a wrong measurement wearing a positive marker, which is the
    /// single shape this whole file exists to prevent.
    @Test func theRunRecordIsClaimedByIdentityRatherThanByStoreOrder() async throws {
        let (conductor, _, dir, box) = makeConductor()
        let foreign = minimalRunRecord()
        box.records = [foreign]
        var mineID: UUID?
        let s = spec("t-claim", mode: .none) { _, _, _ in
            let mine = self.minimalRunRecord()
            mineID = mine.id
            // Deliberately NOT newest-first. A real store would usually sort
            // `mine` to the front; the equal-second case is exactly when it
            // does not, and that is the case being pinned.
            box.records = [foreign, mine]
        }
        let status = await conductor.run(spec: s, trials: 1, cells: nil, unattended: true)
        #expect(status == .completed)
        let envelope = try latest(in: dir)
        #expect(envelope.runRecord?.id == mineID,
                "the conductor embedded a record this run did not produce")
        #expect(envelope.runRecord?.id != foreign.id)
    }

    /// Review fix: the mutex-refusal / recorder-bypass case. The instrument
    /// closure runs (it is not refused up front — no alarm/EventKit flags
    /// here) but never appends to the run store, exactly as
    /// `LocalChatBackend.beginBatteryRun()` returning `false` would look from
    /// the conductor's vantage point: `spec.run` returns having done
    /// nothing. `.completed` would be a false positive here; `.failed` is
    /// the honest terminal state, and it must name the mutex so the harness
    /// (and a human reading the artifact) knows this isn't a crash.
    @Test func noNewRunRecordFailsRatherThanFalselyCompletes() async throws {
        let (conductor, _, dir, _) = makeConductor()
        let s = spec("t-mutex", mode: .none) // default run closure is a no-op — no record appended
        let status = await conductor.run(spec: s, trials: 1, cells: nil, unattended: true)
        #expect(status == .failed)
        let envelope = try latest(in: dir)
        #expect(envelope.status == .failed)
        #expect(envelope.refusalReason?.contains("mutex") == true)
        #expect(envelope.runRecord == nil)
    }

    // MARK: - #341 cell selection

    /// THE bar this lane exists for. A mistyped cell name must not produce a
    /// run: the instrument is never invoked, so no `BatteryRunRecord` appears
    /// and the artifact seals `failed` — and the reason names the typo rather
    /// than blaming the battery mutex, which is what a downstream conversion
    /// would have left in the file.
    @Test func anUnknownCellNameFailsWithoutRunningTheInstrument() async throws {
        var invoked = false
        let (conductor, _, dir, box) = makeConductor()
        let s = spec("t-cells", mode: .none, defaultCells: [.armed, .armedCardrollback]) { _, _, _ in
            invoked = true
            box.records = [self.minimalRunRecord()]
        }
        let status = await conductor.run(spec: s, trials: 1,
                                         cells: ["armed-nosuchcell"], unattended: true)
        #expect(status == .failed)
        #expect(!invoked)
        #expect(box.records.isEmpty)
        let envelope = try latest(in: dir)
        #expect(envelope.status == .failed)
        #expect(envelope.refusalReason?.contains("armed-nosuchcell") == true)
        #expect(envelope.refusalReason?.contains("mutex") == false)
        #expect(envelope.runRecord == nil)
        // The request itself survives into the artifact, so a reader can see
        // what was asked for as well as why it was refused.
        #expect(envelope.cells == ["armed-nosuchcell"])
    }

    /// A one-cell launch runs exactly that cell, and the embedded run record
    /// says so — the whole point of #337's two-launch A/B is that a reader
    /// can never mistake one arm for the full three-cell instrument.
    @Test func aSingleCellRequestReachesTheInstrumentAndTheArtifact() async throws {
        var seen: [LocalChatBackend.ActionBatteryCell]?
        let (conductor, _, dir, box) = makeConductor()
        let s = spec("t-cells", mode: .none,
                     defaultCells: [.armed, .armedCardrollback, .armedSpiralfix]) { _, _, cells in
            seen = cells
            var record = self.minimalRunRecord()
            // Mirrors what `runActionBattery` does: the recorder's run header
            // carries the raw values of the cells it was handed.
            record.cells = (cells ?? []).map(\.rawValue)
            box.records = [record]
        }
        let status = await conductor.run(spec: s, trials: 10,
                                         cells: ["armed"], unattended: true)
        #expect(status == .completed)
        #expect(seen == [.armed])
        #expect(try latest(in: dir).runRecord?.cells == ["armed"])
    }

    /// The default path: nothing requested means the instrument's OWN pinned
    /// list arrives at the closure, byte for byte.
    @Test func noRequestHandsTheInstrumentItsDeclaredDefaultCells() async throws {
        var seen: [LocalChatBackend.ActionBatteryCell]?
        let (conductor, _, _, box) = makeConductor()
        let pinned: [LocalChatBackend.ActionBatteryCell] = [.armed, .armedCardrollback, .armedSpiralfix]
        let s = spec("t-cells", mode: .none, defaultCells: pinned) { _, _, cells in
            seen = cells
            box.records = [self.minimalRunRecord()]
        }
        _ = await conductor.run(spec: s, trials: 10, cells: nil, unattended: true)
        #expect(seen == pinned)
    }

    /// An instrument with no cell dimension is refused a cell request rather
    /// than running its default and ignoring the argument.
    @Test func cellsRequestedOfACelllessInstrumentFailWithoutRunning() async throws {
        var invoked = false
        let (conductor, _, dir, _) = makeConductor()
        let s = spec("t-nocells", mode: .none) { _, _, _ in invoked = true }
        let status = await conductor.run(spec: s, trials: 1, cells: ["armed"], unattended: true)
        #expect(status == .failed)
        #expect(!invoked)
        #expect(try latest(in: dir).refusalReason?.contains("t-nocells") == true)
    }

    /// The empty wire state (`TALARIA_CELLS` exported but unset by the runner)
    /// is not a request, so a cell-less instrument still runs normally.
    @Test func theEmptyWireStateIsNotARequest() async throws {
        var invoked = false
        let (conductor, _, _, box) = makeConductor()
        let s = spec("t-nocells", mode: .none) { _, _, _ in
            invoked = true
            box.records = [self.minimalRunRecord()]
        }
        let status = await conductor.run(spec: s, trials: 1, cells: [], unattended: true)
        #expect(status == .completed)
        #expect(invoked)
    }
}
#endif
