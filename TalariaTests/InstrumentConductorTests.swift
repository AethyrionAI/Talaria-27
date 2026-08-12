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
