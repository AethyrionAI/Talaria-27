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
