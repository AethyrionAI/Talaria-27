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
