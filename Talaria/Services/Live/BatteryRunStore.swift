#if DEBUG
import Foundation
import os

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
    /// #212: what the tool actually RETURNED.
    ///
    /// The record has always carried that a tool ran and what it was asked;
    /// never what it answered. That blindness is what stalled #212: 40 of 40
    /// `currentWeather` trials failed, the tool's own catch had WeatherKit's
    /// `localizedDescription` in hand, and the record kept only the model's
    /// paraphrase of it. Signing turned out to be correct at every layer —
    /// entitlements file, signed binary AND provisioning profile — so the real
    /// error text is the only thing left that can name the cause.
    ///
    /// **nil means NOT CAPTURED, not "empty".** Capture is currently wired on
    /// the READ tools only (weather, health, motion); the rest still record
    /// nil and are owed.
    var result: String? = nil
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
    /// #215: true when that route was a FAIL-SAFE rather than a
    /// classification. `routeNeedsDeviceTool` returns `armed` on any thrown
    /// generation — right for a live turn, ruinous for a record, because
    /// `route: "armed"` then reads exactly like the router having looked at
    /// the prompt and decided. #213 was this same bug in the router probe,
    /// where the fallback was scored as a CORRECT answer.
    ///
    /// `nil` on trials that never routed — a claim distinct from `false`, and
    /// the reason this is optional rather than defaulted at the decoder: the
    /// 48 archived runs predate the field and must keep decoding.
    var routeFailed: Bool? = nil
    var error: String?
    var timedOut: Bool
    var latencySeconds: Double
    /// #208: the turn's real token cost, read from `response.usage`.
    /// Optional because ERROR and TIMEOUT trials never produce a response —
    /// the asymmetry the dispatch states in advance: this measures turns
    /// that SUCCEEDED and is structurally blind to the ones that broke.
    var inputTokens: Int? = nil
    var outputTokens: Int? = nil
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
    /// #217: the intent this row should have produced, and the FULL tally of
    /// what it actually answered — every value, not just the matches.
    ///
    /// `correct/trials` cannot answer this lane's safety question. A row that
    /// scores 7/10 is harmless if the other three said `other` (full belt,
    /// today's behaviour) and dangerous if they said `health` on a calendar
    /// turn. Those are the same number and opposite verdicts, so the
    /// distribution is the record and the ratio is a summary of it.
    var expectedIntent: String? = nil
    var intentTally: [String: Int]? = nil
    /// #202C: mean seconds per classification. The long-context probe exists
    /// to answer a LATENCY question — the router runs on every production
    /// turn — and the first run emitted the timing to the console only, so
    /// the one number the probe was built for could not be read from the
    /// record. Same lesson #201B's thermal readings taught.
    var seconds: Double? = nil
    /// #213: how many of `trials` had the router generation THROW.
    ///
    /// This record could not represent a failure at all. `routeNeedsDeviceTool`
    /// catches everything and fails safe to `armed` — correct for production,
    /// but it means that on a row with `expected: true` a CRASHED generation
    /// matched the expectation and was counted CORRECT. **Five of the ten
    /// baseline rows are `expected: true`, so half the 200/200 series could not
    /// distinguish "the router judged right" from "the router died and fell
    /// back."**
    ///
    /// The other five rows are an accidental control: on `expected: false` a
    /// failure scores as a MISS, and they sit at 100/100 — which bounds the
    /// real error rate near zero and is why no filed verdict is believed wrong.
    /// Nobody chose that safeguard; recording the count replaces luck with
    /// evidence.
    ///
    /// nil = the run predates #213 **or the call site forgot to sample**, NOT
    /// zero errors.
    ///
    /// **INVARIANT for anyone adding a probe runner:** every `recordProbe`
    /// call that follows a GENERATION must pass `errors:`. The first cut of
    /// #213 wired only `runRouterContextProbe` and the commit message claimed
    /// "each probe row" — an external audit found three runners still blind,
    /// including the legacy #196 probe whose 200/200 series the program quotes
    /// as its baseline gate. This is a source-level invariant that no test
    /// reaches; the honest defence is this comment and the classifier's
    /// "NOT RECORDED" line, which reports unsampled rows rather than counting
    /// them clean. A deterministic row that cannot throw passes `errors: 0`.
    var errors: Int? = nil
    /// #335: named NUMERIC measurements for the read-only FM instruments —
    /// token counts, the cap a count must fit under, computed headroom,
    /// ratios, `contextSize`.
    ///
    /// A new field rather than a reuse of `correct`/`trials`, because those
    /// two already mean something in this file's grammar: `renderRawLines`
    /// prints them as `router: 312/128 expected=true`, and a reader who knows
    /// that line would read a token count as an accuracy. #201B's rule (if a
    /// verdict depends on it, it belongs in the record) with #213's corollary
    /// attached: **nil means NOT MEASURED, never zero.**
    var metrics: [String: Double]? = nil
    /// #335: named STRING measurements — the model variant's `displayName`,
    /// the class of a thrown error, which of two behaviours a band observed.
    /// Same nil-means-not-measured rule as `metrics`.
    var notes: [String: String]? = nil
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
    /// #340 bar 340-F5 — **whether the belt was handed each trial's own prompt
    /// text**, for every cell in this run.
    ///
    /// **This is #398-A's third axis applied to a reminder-due rate.** That
    /// rule says a rate carries its configuration — #215 asks whether the row
    /// was ROUTED, #343 whether the run predates the governor, #398-A which OS
    /// build it ran on. #340 Task 3 added a fourth, and it is the sharpest of
    /// them: the user-words fallback reads
    /// `ToolEventRelay.currentTurnUserText`, the bare per-trial `beginTurn()`
    /// every instrument makes CLEARS it, so a due-date run WITHOUT
    /// `carriesUserText` measures the fallback **switched off** and reports
    /// `source=userText 0/N` as if the product did not work. Task 2's review
    /// caught exactly that before the device run. A number whose artifact does
    /// not say which of those two configurations produced it is ambiguous, and
    /// the ambiguity is invisible.
    ///
    /// **Run-level, applying to every cell — the same sense `trialsPerCell` is
    /// per-cell.** `runActionBattery` takes one `carriesUserText` for the whole
    /// run and every cell in it runs with that value; a map keyed by cell would
    /// imply a variance the instrument cannot express.
    ///
    /// **Absent decodes to `nil`, never `false`** — `nil` means NOT RECORDED
    /// (every run written before this field, and every instrument that has no
    /// belt-text dimension), `false` means the belt was measured with the text
    /// withheld. `metrics`/`notes` carry the same rule for the same reason
    /// (#213): a default of `false` would silently claim of a 2026-08 archive
    /// that its fallback was off, which is true but was never measured.
    var carriesUserText: Bool? = nil
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
                    // #212: the tool's own answer, when captured. Absent for
                    // tools not yet wired — nil is "not captured", not "empty".
                    if let result = call.result {
                        lines.append("battery: toolresult=\(call.name) \(tag) \(result.replacingOccurrences(of: "\n", with: " / "))")
                    }
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
    /// Raised from 10 to 50 on 2026-08-01. A run leaves the device ONE FILE AT
    /// A TIME through a share sheet, and the #200-series routinely ran
    /// multi-cell lanes, so a bound of 10 could evict a cell before anyone had
    /// exported it. These are JSON files on a phone with tens of gigabytes; the
    /// bound exists to stop unbounded growth, not to be tight.
    static let maxRuns = 50

    /// `nonisolated` so `enforceBound` can log without hopping actors, and
    /// `.notice` because Console.app's default view suppresses `.info` — a
    /// diagnostic nobody can see is not a diagnostic.
    private nonisolated static let logger = Logger(subsystem: "org.aethyrion.talaria", category: "BatteryRunStore")

    /// Called with the filename of every run this store deletes.
    ///
    /// **A battery run IS the evidence a promotion argument rests on**, so a
    /// deletion is not the same class of event as this file's other silent
    /// failures. Failing to WRITE a run loses a record that was never used;
    /// deleting one destroys a record that may already have been cited. The
    /// announcement means the trail shows evidence was destroyed rather than
    /// never existing — the same reason `RouterProbeRecord.errors` distinguishes
    /// "not sampled" from "zero".
    var onPrune: ((String) -> Void)?

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
            // Announced, never silent — see `onPrune`. The log line is the
            // production channel; the closure is how tests see it.
            Self.logger.notice("battery run pruned at the \(Self.maxRuns, privacy: .public)-run bound: \(stale, privacy: .public)")
            onPrune?(stale)
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
    /// #215: nil until a route is recorded, so an unrouted trial's record says
    /// nil rather than claiming the router succeeded.
    private var pendingRouteFailed: Bool?
    private let clock = ContinuousClock()

    init(store: BatteryRunPersisting) {
        self.store = store
    }

    /// #340 bar 340-F5: `carriesUserText` defaults to `nil` so every instrument
    /// that has no belt-text dimension records NOT MEASURED rather than a
    /// `false` it never established. Only `runActionBattery` passes a value.
    func beginRun(trialsPerCell: Int, cells: [String], kind: String? = nil,
                  carriesUserText: Bool? = nil) {
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
            kind: kind,
            carriesUserText: carriesUserText
        )
    }

    func beginTrial() {
        guard run != nil else { return }
        trialStart = clock.now
        pendingToolCalls = []
        pendingRoute = nil
        pendingRouteFailed = nil
    }

    /// #215: `failed` says the route was the fail-safe, not a classification.
    /// Defaulted so the existing call sites are unchanged; every caller that
    /// CAN observe a router throw is expected to pass it.
    func recordRoute(_ route: String, failed: Bool = false) {
        guard run != nil else { return }
        pendingRoute = route
        pendingRouteFailed = failed
    }

    func recordToolCall(name: String, detail: String) {
        guard run != nil else { return }
        pendingToolCalls.append(BatteryToolCallRecord(name: name, detail: detail))
    }

    /// #212: attaches what a tool RETURNED to the trial's most recent call of
    /// that name. Matched by name rather than blindly to the last call, because
    /// a tool completing can interleave with a later tool's start.
    func recordToolResult(name: String, result: String) {
        guard run != nil else { return }
        guard let i = pendingToolCalls.lastIndex(where: { $0.name == name && $0.result == nil })
        else { return }
        pendingToolCalls[i].result = result
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

    func endTrial(shape: String, prompt: String, trial: Int, text: String, cant: Bool, denial: Bool,
                  inputTokens: Int? = nil, outputTokens: Int? = nil) {
        appendTrial(shape: shape, prompt: prompt, trial: trial,
                    text: text, cant: cant, denial: denial, error: nil, timedOut: false,
                    inputTokens: inputTokens, outputTokens: outputTokens)
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
                             error: String?, timedOut: Bool,
                             inputTokens: Int? = nil, outputTokens: Int? = nil) {
        guard run != nil else { return }
        let latency = trialStart.map { Double((clock.now - $0).components.seconds)
            + Double((clock.now - $0).components.attoseconds) * 1e-18 } ?? 0
        run?.trials.append(BatteryTrialRecord(
            shape: shape, prompt: prompt, trial: trial,
            text: text, cant: cant, denial: denial,
            toolCalls: pendingToolCalls, route: pendingRoute,
            routeFailed: pendingRouteFailed,
            error: error, timedOut: timedOut,
            latencySeconds: latency,
            inputTokens: inputTokens, outputTokens: outputTokens
        ))
        trialStart = nil
        pendingToolCalls = []
        pendingRoute = nil
        pendingRouteFailed = nil
        persistSnapshot()
    }

    /// #202A adds variant/context/band, defaulted so the #196 call site is
    /// unchanged and its records keep their original shape.
    func recordProbe(probe: String, expected: Bool, correct: Int, trials: Int,
                     variant: String? = nil, context: String? = nil, band: String? = nil,
                     seconds: Double? = nil, errors: Int? = nil,
                     expectedIntent: String? = nil, intentTally: [String: Int]? = nil,
                     metrics: [String: Double]? = nil, notes: [String: String]? = nil) {
        guard run != nil else { return }
        run?.probes.append(RouterProbeRecord(probe: probe, expected: expected,
                                            correct: correct, trials: trials,
                                            variant: variant, context: context, band: band,
                                            expectedIntent: expectedIntent,
                                            intentTally: intentTally,
                                            seconds: seconds, errors: errors,
                                            metrics: metrics, notes: notes))
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
