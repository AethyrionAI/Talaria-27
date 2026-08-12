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
        _ = await conductor.run(spec: s, trials: 2, cells: ["a"], unattended: true)
        #expect(midRun?.status == .running)          // bar 333-C's schema half
        let final = try latest(in: dir)
        #expect(final.status == .completed)
        #expect(final.endedAt != nil)
        #expect(final.instrument == "t-status" && final.trialsRequested == 2)
        #expect(final.buildSha == "testsha")
        #expect(final.unattended)
        #expect(final.runRecord?.id == recordID)
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

}
#endif
