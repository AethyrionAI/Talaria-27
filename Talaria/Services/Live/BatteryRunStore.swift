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
    /// #200: the confirmation-gate outcome for THIS invocation —
    /// "accepted" or "declined" when the gate resolved while this call was
    /// the trial's most recent, nil when no confirmation was ever staged
    /// (read tools always; action tools that bailed before the gate).
    /// Optional so pre-#200 run JSONs still decode.
    var confirmation: String? = nil
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
    /// #202A: which router framing produced this row. Optional so #196
    /// records — which had exactly one framing — still decode.
    var variant: String? = nil
    /// #202A: the assistant turn this row was classified against. Two rows
    /// can share a prompt and differ only here, so without it the record
    /// cannot distinguish them. (#201B lesson: if a verdict depends on it,
    /// it belongs in the record.)
    var context: String? = nil
    /// #202A: the band the bars are written against.
    var band: String? = nil
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
    /// #200: "action" for action-path battery runs; nil for the legacy
    /// shape/probe runs (whose export keeps the #196 grammar). Optional so
    /// pre-#200 run JSONs still decode.
    var kind: String? = nil
    /// #200: the teardown's artifact-reap accounting, e.g.
    /// "reminders=20 events=18 alarms=19 failures=1". Nil when the run had
    /// no reap phase. Optional so pre-#200 run JSONs still decode.
    var reapSummary: String? = nil
    /// #201B: thermal state at every cell boundary, as `cell:moment=state`.
    /// A verdict condition that lives only in the console is a condition the
    /// classifier cannot enforce — #201B's thermal comparability check had to be
    /// read by hand, which is the same lesson as the reap seal: if a verdict
    /// depends on it, it belongs in the RECORD. Optional so older run JSONs
    /// still decode.
    var thermal: [String]? = nil
    /// #200 crash diagnostics: false on the per-trial snapshots the
    /// recorder persists mid-run, true once endRun sealed the record. A
    /// crashed run therefore survives on disk carrying every completed
    /// trial AND its own incompleteness. Nil on legacy records (which all
    /// completed — pre-hardening the only persist was endRun's).
    var endedCleanly: Bool? = nil
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
        // #200 action runs carry their own item marker; everything else
        // keeps the #196 grammar byte-for-byte.
        let item = run.kind == "action" ? "#200" : "#196"
        let stamp = ISO8601DateFormatter().string(from: run.startedAt)
        lines.append("battery: RUN \(stamp) build=\(run.appVersion)(\(run.appBuild)) os=\(run.osVersion)")
        if !run.trials.isEmpty {
            let promptCount = Set(run.trials.map(\.prompt)).count
            lines.append("battery: START trials=\(run.trialsPerCell) cells=\(run.cells.count) prompts=\(promptCount) (\(item))")
            for trial in run.trials {
                let tag = "shape=\(trial.shape) p=\(trial.prompt) t=\(trial.trial)"
                if let route = trial.route {
                    lines.append("battery: route=\(route) \(tag)")
                }
                for call in trial.toolCalls {
                    lines.append("battery: tool=\(call.name) \(tag) detail=\(call.detail.replacingOccurrences(of: "\n", with: " / "))")
                    // A CAPTURED outcome renders on any run kind, matching
                    // the live emit sequence (tool line, then its confirm
                    // line). confirm=none is SYNTHESIZED — only for action
                    // runs (which have capture), and only for action-named
                    // tools (read tools have no gate): it means the tool
                    // ran and bailed before ever staging a confirmation.
                    if let confirmation = call.confirmation {
                        lines.append("battery: confirm=\(confirmation) \(tag)")
                    } else if run.kind == "action", DeviceToolBelt.actionToolNames.contains(call.name) {
                        lines.append("battery: confirm=none \(tag)")
                    }
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
            if let reapSummary = run.reapSummary {
                lines.append("battery: REAP \(reapSummary) (\(item))")
            }
            // A crashed run's paste must never read as complete. Nil is
            // legacy (pre-hardening records only persisted at endRun, so
            // they all completed) and keeps DONE.
            if run.endedCleanly == false {
                lines.append("battery: INCOMPLETE — run died before DONE (\(item))")
            } else {
                lines.append("battery: DONE (\(item))")
            }
        }
        if !run.probes.isEmpty {
            lines.append("router: PROBE START trials=\(run.trialsPerCell) probes=\(run.probes.count) (#196)")
            for probe in run.probes {
                // #202A: variant/band render only when present, so a #196
                // record still round-trips to its original line byte for byte.
                let variant = probe.variant.map { " variant=\($0)" } ?? ""
                let band = probe.band.map { " band=\($0)" } ?? ""
                lines.append("router: \(probe.correct)/\(probe.trials) expected=\(probe.expected)\(variant)\(band) probe=\(probe.probe)")
            }
            if run.endedCleanly == false {
                lines.append("router: PROBE INCOMPLETE — run died before DONE (#196)")
            } else {
                lines.append("router: PROBE DONE (#196)")
            }
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

    func beginRun(trialsPerCell: Int, cells: [String], kind: String? = nil) {
        run = BatteryRunRecord(
            id: UUID(),
            startedAt: Date(),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—",
            appBuild: Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "—",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            trialsPerCell: trialsPerCell,
            cells: cells,
            trials: [],
            probes: [],
            kind: kind
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

    /// #200: attaches a confirmation-gate outcome ("accepted"/"declined")
    /// to the trial's MOST RECENT tool call — the tool that staged it
    /// (tools run serially, and a tool's `started` always precedes its
    /// confirmation request). Dropped when no call is pending (defensive;
    /// a gate resolution can't precede its tool's start).
    func recordConfirmation(_ outcome: String) {
        guard run != nil, !pendingToolCalls.isEmpty else { return }
        pendingToolCalls[pendingToolCalls.count - 1].confirmation = outcome
    }

    /// #200: the action battery's teardown accounting, stamped on the run
    /// before `endRun`.
    func recordReapSummary(_ summary: String) {
        guard run != nil else { return }
        run?.reapSummary = summary
    }

    /// #201B: one `cell:moment=state` entry per cell boundary.
    func recordThermal(_ entry: String) {
        guard run != nil else { return }
        // Read, mutate, write back through a local: `run?.thermal = run?.thermal
        // + …` is an overlapping access to `run` and will not compile.
        var entries = run?.thermal ?? []
        entries.append(entry)
        run?.thermal = entries
        persistSnapshot()
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
        persistSnapshot()
    }

    /// #202A adds variant/context/band, defaulted so the #196 call site is
    /// unchanged and its records keep their original shape.
    func recordProbe(probe: String, expected: Bool, correct: Int, trials: Int,
                     variant: String? = nil, context: String? = nil, band: String? = nil) {
        guard run != nil else { return }
        run?.probes.append(RouterProbeRecord(probe: probe, expected: expected,
                                            correct: correct, trials: trials,
                                            variant: variant, context: context, band: band))
        persistSnapshot()
    }

    /// #200 crash diagnostics: persist after EVERY trial/probe, marked
    /// not-yet-clean, overwriting one file (the run id and start stamp fix
    /// the filename) — both 2026-07-28 action-battery crashes lost their
    /// entire runs because the only persist was endRun's. A crashed run
    /// now survives with every completed trial and its own incompleteness.
    private func persistSnapshot() {
        guard var snapshot = run else { return }
        snapshot.endedCleanly = false
        store.persist(snapshot)
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
        guard var run, !(run.trials.isEmpty && run.probes.isEmpty) else { return }
        run.endedCleanly = true
        store.persist(run)
    }
}
#endif
