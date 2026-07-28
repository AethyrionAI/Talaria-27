#if DEBUG
import Foundation

// MARK: - #196 battery run store (results-page lane)
//
// Structured capture for the shape-battery instrument, ADDITIVE to the three
// `batteryEmit` sinks (Console / stdout / container log — the home workflow
// is untouched). The point is the work desk: OTA-installed builds have no
// Console and no `devicectl`, so runs were write-only from anywhere but the
// home LAN. Records persist as one JSON file per run in Application Support
// (NOT UserDefaults — runs are 100KB+ of reply text, #104's churn lesson),
// bounded to the most recent runs, and export back OUT through the
// established `battery:` line grammar so a paste into chat is immediately
// classifiable. Raw reply text is stored IN FULL — the 500-char emit prefix
// is a Console-line constraint, not a classification budget.

/// One tool invocation observed inside a battery trial, via the same
/// `ToolEventRelay.batteryTrialTag` path the relay logging uses. `detail`
/// is unbounded here (the emit line truncates to 80 for Console width).
struct BatteryToolCallRecord: Codable, Equatable {
    var name: String
    var detail: String
}

/// One battery trial: the full reply (or its ERROR/TIMEOUT marker), the
/// heuristic flags exactly as emitted, tool invocations, the router's route
/// for armed-routed trials, and wall-clock latency for the whole turn
/// (routing included for routed trials — that is the real turn cost).
struct BatteryTrialRecord: Codable, Equatable {
    var shape: String
    var prompt: String
    var trial: Int
    /// Full reply text. Nil when the trial ended in ERROR or TIMEOUT.
    var text: String?
    var cant: Bool
    var denial: Bool
    var toolCalls: [BatteryToolCallRecord]
    /// armed-routed only: "armed" or "toolless".
    var route: String?
    var error: String?
    var timedOut: Bool
    var latencySeconds: Double
}

/// One router-probe aggregate — mirrors the `router:` emit line.
struct RouterProbeRecord: Codable, Equatable {
    var probe: String
    var expected: Bool
    var correct: Int
    var trials: Int
}

/// One battery or probe run. A probe-only run has empty `trials`; a battery
/// run has empty `probes`; the headless auto-run produces one of each.
struct BatteryRunRecord: Codable, Equatable, Identifiable {
    var id: UUID
    var startedAt: Date
    var appVersion: String
    var appBuild: String
    var osVersion: String
    var trialsPerCell: Int
    var cells: [String]
    var trials: [BatteryTrialRecord]
    var probes: [RouterProbeRecord]
}

// MARK: - Tally math (pure, testable)

/// Flag tallies for one cell × prompt. These are HEURISTIC aids only — the
/// `cant`/`denial` flags are the emit line's hints, and the results UI must
/// label them as such; raw text remains the classification ground truth.
struct BatteryCellPromptTally: Hashable {
    var shape: String
    var prompt: String
    var total: Int
    var cantCount: Int
    var denialCount: Int
    var toolTrialCount: Int
    var errorCount: Int
    var timeoutCount: Int
}

enum BatteryRunMath {

    /// Tallies in first-appearance order of (shape, prompt) — which is the
    /// battery's own execution order, so the table reads like the run.
    static func tallies(for trials: [BatteryTrialRecord]) -> [BatteryCellPromptTally] {
        var order: [String] = []
        var byKey: [String: BatteryCellPromptTally] = [:]
        for trial in trials {
            let key = "\(trial.shape)\u{1F}\(trial.prompt)"
            if byKey[key] == nil {
                order.append(key)
                byKey[key] = BatteryCellPromptTally(
                    shape: trial.shape, prompt: trial.prompt,
                    total: 0, cantCount: 0, denialCount: 0,
                    toolTrialCount: 0, errorCount: 0, timeoutCount: 0
                )
            }
            byKey[key]!.total += 1
            if trial.cant { byKey[key]!.cantCount += 1 }
            if trial.denial { byKey[key]!.denialCount += 1 }
            if !trial.toolCalls.isEmpty { byKey[key]!.toolTrialCount += 1 }
            if trial.error != nil { byKey[key]!.errorCount += 1 }
            if trial.timedOut { byKey[key]!.timeoutCount += 1 }
        }
        return order.compactMap { byKey[$0] }
    }

    /// Router decision distribution per prompt, for runs containing routed
    /// trials: (prompt, armed count, toolless count).
    static func routeDistribution(for trials: [BatteryTrialRecord]) -> [(prompt: String, armed: Int, toolless: Int)] {
        var order: [String] = []
        var armed: [String: Int] = [:]
        var toolless: [String: Int] = [:]
        for trial in trials {
            guard let route = trial.route else { continue }
            if armed[trial.prompt] == nil {
                order.append(trial.prompt)
                armed[trial.prompt] = 0
                toolless[trial.prompt] = 0
            }
            if route == "armed" { armed[trial.prompt]! += 1 } else { toolless[trial.prompt]! += 1 }
        }
        return order.map { ($0, armed[$0] ?? 0, toolless[$0] ?? 0) }
    }

    /// The complete run in the established emit-line grammar, with FULL
    /// reply texts — what "Copy raw run" places on the clipboard. Newlines
    /// inside replies flatten to " / " exactly as `batteryEmit` does, so the
    /// paste is line-per-trial and classifiable by the same tooling.
    static func renderRawLines(for run: BatteryRunRecord) -> String {
        var lines: [String] = []
        let stamp = ISO8601DateFormatter().string(from: run.startedAt)
        lines.append("battery: RUN \(stamp) build=\(run.appVersion)(\(run.appBuild)) os=\(run.osVersion)")
        if !run.trials.isEmpty {
            lines.append("battery: START trials=\(run.trialsPerCell) cells=\(run.cells.count) prompts=3 (#196)")
            for trial in run.trials {
                let tag = "shape=\(trial.shape) p=\(trial.prompt) t=\(trial.trial)"
                if let route = trial.route {
                    lines.append("battery: route=\(route) \(tag)")
                }
                for call in trial.toolCalls {
                    lines.append("battery: tool=\(call.name) \(tag) detail=\(call.detail.replacingOccurrences(of: "\n", with: " / "))")
                }
                if let error = trial.error {
                    lines.append("battery: \(tag) ERROR=\(error)")
                } else if trial.timedOut {
                    lines.append("battery: \(tag) TIMEOUT — wedged trial guillotined")
                } else if let text = trial.text {
                    let flat = text.replacingOccurrences(of: "\n", with: " / ")
                    lines.append("battery: \(tag) cant=\(trial.cant) denial=\(trial.denial) chars=\(text.count) text=\(flat)")
                }
            }
            lines.append("battery: DONE (#196)")
        }
        if !run.probes.isEmpty {
            lines.append("router: PROBE START trials=\(run.trialsPerCell) probes=\(run.probes.count) (#196)")
            for probe in run.probes {
                lines.append("router: \(probe.correct)/\(probe.trials) expected=\(probe.expected) probe=\(probe.probe)")
            }
            lines.append("router: PROBE DONE (#196)")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Persistence

/// Seam between the recorder and disk, so tests can capture persisted runs
/// without touching the filesystem.
@MainActor
protocol BatteryRunPersisting: AnyObject {
    func persist(_ run: BatteryRunRecord)
}

/// One JSON file per run under Application Support/BatteryRuns, newest-first
/// on load, bounded to `maxRuns` (oldest files deleted on persist). All
/// failures are silent by design — this is an instrument sink, and the three
/// emit sinks still carry every line.
@MainActor
final class BatteryRunStore: BatteryRunPersisting {
    static let maxRuns = 10

    private let directory: URL

    /// Default: Application Support/BatteryRuns. Tests pass a temp directory.
    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.directory = base.appendingPathComponent("BatteryRuns", isDirectory: true)
        }
    }

    private static let filenameStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    func fileURL(for run: BatteryRunRecord) -> URL {
        let stamp = Self.filenameStamp.string(from: run.startedAt)
        let suffix = run.id.uuidString.prefix(8)
        return directory.appendingPathComponent("run-\(stamp)-\(suffix).json")
    }

    func persist(_ run: BatteryRunRecord) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(run) else { return }
        try? data.write(to: fileURL(for: run), options: .atomic)
        enforceBound()
    }

    /// Filenames embed a UTC timestamp, so lexicographic order IS age order;
    /// decode-free bounding stays cheap however large the replies get.
    private func enforceBound() {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        let runs = names.filter { $0.hasPrefix("run-") && $0.hasSuffix(".json") }.sorted()
        guard runs.count > Self.maxRuns else { return }
        for stale in runs.prefix(runs.count - Self.maxRuns) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(stale))
        }
    }

    func loadRuns() -> [BatteryRunRecord] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return names
            .filter { $0.hasPrefix("run-") && $0.hasSuffix(".json") }
            .compactMap { name -> BatteryRunRecord? in
                guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
                return try? decoder.decode(BatteryRunRecord.self, from: data)
            }
            .sorted { $0.startedAt > $1.startedAt }
    }

    func delete(_ run: BatteryRunRecord) {
        try? FileManager.default.removeItem(at: fileURL(for: run))
    }
}

// MARK: - Recorder

/// Assembles one run from the battery's event stream and persists it at
/// `endRun`. Every method is a no-op unless a run is open, so the wiring in
/// the battery loop stays unconditional. MainActor like everything else in
/// the instrument (the battery loop, the relay, the emit path).
@MainActor
final class BatteryRunRecorder {
    private let store: BatteryRunPersisting
    private var run: BatteryRunRecord?
    private var trialStart: ContinuousClock.Instant?
    private var pendingToolCalls: [BatteryToolCallRecord] = []
    private var pendingRoute: String?
    private let clock = ContinuousClock()

    init(store: BatteryRunPersisting) {
        self.store = store
    }

    func beginRun(trialsPerCell: Int, cells: [String]) {
        run = BatteryRunRecord(
            id: UUID(),
            startedAt: Date(),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—",
            appBuild: Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "—",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            trialsPerCell: trialsPerCell,
            cells: cells,
            trials: [],
            probes: []
        )
    }

    func beginTrial() {
        guard run != nil else { return }
        trialStart = clock.now
        pendingToolCalls = []
        pendingRoute = nil
    }

    func recordRoute(_ route: String) {
        guard run != nil else { return }
        pendingRoute = route
    }

    func recordToolCall(name: String, detail: String) {
        guard run != nil else { return }
        pendingToolCalls.append(BatteryToolCallRecord(name: name, detail: detail))
    }

    func endTrial(shape: String, prompt: String, trial: Int, text: String, cant: Bool, denial: Bool) {
        appendTrial(shape: shape, prompt: prompt, trial: trial,
                    text: text, cant: cant, denial: denial, error: nil, timedOut: false)
    }

    func endTrialTimeout(shape: String, prompt: String, trial: Int) {
        appendTrial(shape: shape, prompt: prompt, trial: trial,
                    text: nil, cant: false, denial: false, error: nil, timedOut: true)
    }

    func endTrialError(shape: String, prompt: String, trial: Int, error: String) {
        appendTrial(shape: shape, prompt: prompt, trial: trial,
                    text: nil, cant: false, denial: false, error: error, timedOut: false)
    }

    private func appendTrial(shape: String, prompt: String, trial: Int,
                             text: String?, cant: Bool, denial: Bool,
                             error: String?, timedOut: Bool) {
        guard run != nil else { return }
        let latency = trialStart.map { Double((clock.now - $0).components.seconds)
            + Double((clock.now - $0).components.attoseconds) * 1e-18 } ?? 0
        run?.trials.append(BatteryTrialRecord(
            shape: shape, prompt: prompt, trial: trial,
            text: text, cant: cant, denial: denial,
            toolCalls: pendingToolCalls, route: pendingRoute,
            error: error, timedOut: timedOut,
            latencySeconds: latency
        ))
        trialStart = nil
        pendingToolCalls = []
        pendingRoute = nil
    }

    func recordProbe(probe: String, expected: Bool, correct: Int, trials: Int) {
        guard run != nil else { return }
        run?.probes.append(RouterProbeRecord(probe: probe, expected: expected, correct: correct, trials: trials))
    }

    /// Persists and closes the run. Empty runs (begin/end with no trials and
    /// no probes — e.g. a battery aborted before its first trial) are
    /// dropped, not persisted: an empty record on the results page would
    /// read as data.
    func endRun() {
        defer {
            run = nil
            trialStart = nil
            pendingToolCalls = []
            pendingRoute = nil
        }
        guard let run, !(run.trials.isEmpty && run.probes.isEmpty) else { return }
        store.persist(run)
    }
}
#endif
