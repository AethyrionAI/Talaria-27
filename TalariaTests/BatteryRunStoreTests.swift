#if DEBUG
import Foundation
import Testing
@testable import Talaria

/// #196 results-page lane: the structured battery run store. Pins the four
/// dispatch-required behaviors — record round-trip, store bounding, the
/// recorder writing one record per trial through the injectable seam, and
/// the tally math — plus the raw-line export grammar, which the verdict
/// desk's classification tooling parses.
@MainActor
struct BatteryRunStoreTests {

    // MARK: Fixtures

    /// Whole-second dates only: the store encodes ISO8601, which drops
    /// fractional seconds — a fractional fixture would fail round-trip
    /// equality for a reason that has nothing to do with the store.
    private func makeRun(startedAt: Date = Date(timeIntervalSince1970: 1_753_700_000)) -> BatteryRunRecord {
        BatteryRunRecord(
            id: UUID(),
            startedAt: startedAt,
            appVersion: "1.0",
            appBuild: "42",
            osVersion: "Version 27.0",
            trialsPerCell: 2,
            cells: ["armed", "armed-routed"],
            trials: [
                BatteryTrialRecord(
                    shape: "armed", prompt: "canary", trial: 1,
                    text: "2 + 2 = 4.", cant: false, denial: false,
                    toolCalls: [BatteryToolCallRecord(name: "createReminder", detail: "title: 2+2", confirmation: "declined")],
                    route: nil, error: nil, timedOut: false, latencySeconds: 1.25
                ),
                BatteryTrialRecord(
                    shape: "armed-routed", prompt: "haiku", trial: 1,
                    text: "Snow hush on the hill\nrunners carve a silver line\nbreath blooms and is gone",
                    cant: false, denial: false, toolCalls: [],
                    route: "toolless", error: nil, timedOut: false, latencySeconds: 3.5
                ),
                BatteryTrialRecord(
                    shape: "armed-routed", prompt: "norway", trial: 1,
                    text: nil, cant: false, denial: false, toolCalls: [],
                    route: "armed", error: "ToolCallError boom", timedOut: false, latencySeconds: 0.4
                ),
                BatteryTrialRecord(
                    shape: "armed-routed", prompt: "norway", trial: 2,
                    text: nil, cant: false, denial: false, toolCalls: [],
                    route: nil, error: nil, timedOut: true, latencySeconds: 35.0
                ),
            ],
            probes: [
                RouterProbeRecord(probe: "Write a haiku about sledding", expected: false, correct: 20, trials: 20),
            ]
        )
    }

    private func makeTempStore() -> BatteryRunStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("battery-run-tests-\(UUID().uuidString)", isDirectory: true)
        return BatteryRunStore(directory: dir)
    }

    @MainActor
    private final class CapturingStore: BatteryRunPersisting {
        var persisted: [BatteryRunRecord] = []
        func persist(_ run: BatteryRunRecord) { persisted.append(run) }
    }

    // MARK: Round-trip

    @Test func runRecordRoundTripsThroughTheStore() {
        let store = makeTempStore()
        let run = makeRun()
        store.persist(run)
        let loaded = store.loadRuns()
        #expect(loaded == [run])
    }

    // MARK: Bounding

    @Test func storeKeepsOnlyTheMostRecentRuns() {
        let store = makeTempStore()
        let base = Date(timeIntervalSince1970: 1_753_700_000)
        var all: [BatteryRunRecord] = []
        for i in 0 ..< (BatteryRunStore.maxRuns + 2) {
            var run = makeRun(startedAt: base.addingTimeInterval(Double(i) * 60))
            run.id = UUID()
            all.append(run)
            store.persist(run)
        }
        let loaded = store.loadRuns()
        #expect(loaded.count == BatteryRunStore.maxRuns)
        // Newest first, and the two OLDEST runs are the ones dropped.
        #expect(loaded.first?.startedAt == all.last?.startedAt)
        let survivingStarts = Set(loaded.map(\.startedAt))
        #expect(!survivingStarts.contains(all[0].startedAt))
        #expect(!survivingStarts.contains(all[1].startedAt))
    }

    /// A battery run IS the evidence a promotion rests on, and it leaves the
    /// device one file at a time through a share sheet. A multi-cell lane can
    /// therefore evict a run before anyone exported it. Bounding is still
    /// right — this is a phone — but the deletion must be ANNOUNCED, so the
    /// record shows that evidence was destroyed rather than never existing.
    @Test func prunedRunsAreAnnouncedRatherThanVanishingSilently() {
        let store = makeTempStore()
        var pruned: [String] = []
        store.onPrune = { pruned.append($0) }

        let base = Date(timeIntervalSince1970: 1_753_700_000)
        var all: [BatteryRunRecord] = []
        for i in 0 ..< (BatteryRunStore.maxRuns + 2) {
            var run = makeRun(startedAt: base.addingTimeInterval(Double(i) * 60))
            run.id = UUID()
            all.append(run)
            store.persist(run)
        }

        #expect(pruned.count == 2)
        // Named specifically, so the announcement identifies WHICH evidence went.
        #expect(pruned.contains(store.fileURL(for: all[0]).lastPathComponent))
        #expect(pruned.contains(store.fileURL(for: all[1]).lastPathComponent))
    }

    @Test func aStoreUnderItsBoundAnnouncesNothing() {
        let store = makeTempStore()
        var pruned: [String] = []
        store.onPrune = { pruned.append($0) }
        for i in 0 ..< 3 {
            var run = makeRun(startedAt: Date(timeIntervalSince1970: 1_753_700_000 + Double(i) * 60))
            run.id = UUID()
            store.persist(run)
        }
        #expect(pruned.isEmpty)
    }

    // MARK: Recorder — one record per trial, via the injectable seam

    @Test func recorderWritesOneRecordPerTrial() throws {
        let captured = CapturingStore()
        let recorder = BatteryRunRecorder(store: captured)
        recorder.beginRun(trialsPerCell: 3, cells: ["armed", "armed-routed"])

        recorder.beginTrial()
        recorder.recordToolCall(name: "createReminder", detail: "title: 2+2, full untruncated detail")
        recorder.endTrial(shape: "armed", prompt: "canary", trial: 1,
                          text: "4.", cant: false, denial: false)

        recorder.beginTrial()
        recorder.recordRoute("toolless")
        recorder.endTrial(shape: "armed-routed", prompt: "haiku", trial: 1,
                          text: "a haiku", cant: false, denial: false)

        recorder.beginTrial()
        recorder.endTrialError(shape: "armed-routed", prompt: "norway", trial: 1, error: "boom")

        recorder.beginTrial()
        recorder.endTrialTimeout(shape: "armed-routed", prompt: "norway", trial: 2)

        recorder.recordProbe(probe: "What's 2+2?", expected: false, correct: 19, trials: 20)
        recorder.endRun()

        // Snapshots persist along the way (#200 crash diagnostics); the
        // FINAL record carries the whole run.
        let run = try #require(captured.persisted.last)
        #expect(run.trialsPerCell == 3)
        #expect(run.cells == ["armed", "armed-routed"])
        #expect(run.trials.count == 4)
        #expect(run.probes.count == 1)

        // Trial 1 carries its tool call with FULL detail; trial 2 must NOT
        // inherit it (pending state resets between trials) and carries its
        // route instead.
        #expect(run.trials[0].toolCalls == [BatteryToolCallRecord(name: "createReminder", detail: "title: 2+2, full untruncated detail")])
        #expect(run.trials[0].route == nil)
        #expect(run.trials[1].toolCalls.isEmpty)
        #expect(run.trials[1].route == "toolless")
        #expect(run.trials[2].error == "boom")
        #expect(run.trials[2].text == nil)
        #expect(run.trials[3].timedOut)
        #expect(run.trials.allSatisfy { $0.latencySeconds >= 0 })
    }

    // MARK: Recorder — a fail-safe route is not a classification (#215)

    /// `routeNeedsDeviceTool` fails SAFE: any thrown generation returns
    /// `true`, so the turn gets tools. That is right for a live turn and
    /// ruinous for a record — the trial would read `route: "armed"`, which is
    /// indistinguishable from the router having looked at the prompt and
    /// decided. #213 was exactly this bug in the router probe, where the
    /// fail-safe was scored as a CORRECT answer on every `expected: true` row.
    ///
    /// Filed before the instrument could produce a number, not after.
    @Test func recorderDistinguishesAFailSafeRouteFromAClassification() throws {
        let captured = CapturingStore()
        let recorder = BatteryRunRecorder(store: captured)
        recorder.beginRun(trialsPerCell: 2, cells: ["armed-routed"], kind: "action")

        recorder.beginTrial()
        recorder.recordRoute("armed")
        recorder.endTrial(shape: "armed-routed", prompt: "remind", trial: 1,
                          text: "Done.", cant: false, denial: false)

        recorder.beginTrial()
        recorder.recordRoute("armed", failed: true)
        recorder.endTrial(shape: "armed-routed", prompt: "remind", trial: 2,
                          text: "Done.", cant: false, denial: false)

        recorder.endRun()
        let run = try #require(captured.persisted.last)

        // Both say "armed". Only the record can tell them apart.
        #expect(run.trials[0].route == "armed")
        #expect(run.trials[1].route == "armed")
        #expect(run.trials[0].routeFailed == false)
        #expect(run.trials[1].routeFailed == true)
    }

    /// Pending route state resets with every other pending field. Without
    /// this, one thrown router generation would mark every LATER trial in the
    /// run as a fail-safe and destroy the run's denominator.
    @Test func recorderResetsTheFailSafeFlagBetweenTrials() throws {
        let captured = CapturingStore()
        let recorder = BatteryRunRecorder(store: captured)
        recorder.beginRun(trialsPerCell: 2, cells: ["armed-routed"], kind: "action")

        recorder.beginTrial()
        recorder.recordRoute("armed", failed: true)
        recorder.endTrial(shape: "armed-routed", prompt: "remind", trial: 1,
                          text: "Done.", cant: false, denial: false)

        recorder.beginTrial()
        recorder.recordRoute("toolless")
        recorder.endTrial(shape: "armed-routed", prompt: "haiku", trial: 2,
                          text: "a haiku", cant: false, denial: false)

        recorder.endRun()
        let run = try #require(captured.persisted.last)
        #expect(run.trials[0].routeFailed == true)
        #expect(run.trials[1].routeFailed == false)
    }

    /// An unrouted trial never called the router, so it did not fail safe —
    /// it has no route at all. `nil` and `false` are different claims and the
    /// classifier reads them differently.
    @Test func anUnroutedTrialCarriesNoFailSafeVerdict() throws {
        let captured = CapturingStore()
        let recorder = BatteryRunRecorder(store: captured)
        recorder.beginRun(trialsPerCell: 1, cells: ["armed"], kind: "action")

        recorder.beginTrial()
        recorder.endTrial(shape: "armed", prompt: "remind", trial: 1,
                          text: "Done.", cant: false, denial: false)

        recorder.endRun()
        let run = try #require(captured.persisted.last)
        #expect(run.trials[0].route == nil)
        #expect(run.trials[0].routeFailed == nil)
    }

    /// #215 back-compat. The archive is the asset: #209's whole pooled
    /// analysis survived only because 48 older runs were still readable. A new
    /// field that makes them undecodable would destroy more evidence than this
    /// lane can generate.
    @Test func recordsWrittenBeforeTheFailSafeFieldStillDecode() throws {
        let legacy = """
        {
          "shape": "armed-routed", "prompt": "haiku", "trial": 1,
          "text": "a haiku", "cant": false, "denial": false,
          "toolCalls": [], "route": "toolless",
          "timedOut": false, "latencySeconds": 3.5
        }
        """
        let decoded = try JSONDecoder().decode(
            BatteryTrialRecord.self, from: Data(legacy.utf8))
        #expect(decoded.route == "toolless")
        #expect(decoded.routeFailed == nil)
    }

    // MARK: Recorder — confirmation capture (#200)

    @Test func recorderAttachesConfirmationToTheMostRecentToolCall() throws {
        let captured = CapturingStore()
        let recorder = BatteryRunRecorder(store: captured)
        recorder.beginRun(trialsPerCell: 20, cells: ["armed"], kind: "action")

        recorder.beginTrial()
        recorder.recordToolCall(name: "createReminder", detail: "test Talaria")
        recorder.recordConfirmation("accepted")
        recorder.recordToolCall(name: "readReminders", detail: "")
        recorder.endTrial(shape: "armed", prompt: "remind", trial: 1,
                          text: "Created it.", cant: false, denial: false)
        recorder.endRun()

        let run = try #require(captured.persisted.first)
        #expect(run.trials[0].toolCalls == [
            BatteryToolCallRecord(name: "createReminder", detail: "test Talaria", confirmation: "accepted"),
            BatteryToolCallRecord(name: "readReminders", detail: "", confirmation: nil),
        ])
    }

    @Test func recorderIgnoresConfirmationBeforeAnyToolCall() throws {
        let captured = CapturingStore()
        let recorder = BatteryRunRecorder(store: captured)
        recorder.beginRun(trialsPerCell: 20, cells: ["armed"], kind: "action")

        recorder.beginTrial()
        recorder.recordConfirmation("accepted")
        recorder.endTrial(shape: "armed", prompt: "remind", trial: 1,
                          text: "ok", cant: false, denial: false)
        recorder.endRun()

        let run = try #require(captured.persisted.first)
        #expect(run.trials[0].toolCalls.isEmpty)
    }

    @Test func recorderCarriesActionKindAndReapSummary() throws {
        let captured = CapturingStore()
        let recorder = BatteryRunRecorder(store: captured)
        recorder.beginRun(trialsPerCell: 20, cells: ["armed"], kind: "action")

        recorder.beginTrial()
        recorder.endTrial(shape: "armed", prompt: "remind", trial: 1,
                          text: "ok", cant: false, denial: false)
        recorder.recordReapSummary("reminders=1 events=0 alarms=0 failures=0")
        recorder.endRun()

        let run = try #require(captured.persisted.last)
        #expect(run.kind == "action")
        #expect(run.reapSummary == "reminders=1 events=0 alarms=0 failures=0")
    }

    // MARK: Recorder — per-trial snapshots (#200 crash diagnostics)

    /// A run that dies mid-battery must keep everything already measured:
    /// the recorder persists a snapshot after EVERY trial, marked not-yet-
    /// clean; endRun persists the final record marked clean. Same run id
    /// throughout, so the store overwrites one file, never fans out.
    @Test func recorderPersistsASnapshotPerTrialAndMarksTheEndClean() throws {
        let captured = CapturingStore()
        let recorder = BatteryRunRecorder(store: captured)
        recorder.beginRun(trialsPerCell: 20, cells: ["armed"], kind: "action")

        recorder.beginTrial()
        recorder.endTrial(shape: "armed", prompt: "remind", trial: 1,
                          text: "ok", cant: false, denial: false)
        recorder.beginTrial()
        recorder.endTrial(shape: "armed", prompt: "remind", trial: 2,
                          text: "ok", cant: false, denial: false)
        recorder.endRun()

        // Two snapshots + the final persist, all the same run id.
        #expect(captured.persisted.count == 3)
        #expect(Set(captured.persisted.map(\.id)).count == 1)
        #expect(captured.persisted[0].trials.count == 1)
        #expect(captured.persisted[0].endedCleanly == false)
        #expect(captured.persisted[1].trials.count == 2)
        #expect(captured.persisted[1].endedCleanly == false)
        #expect(captured.persisted[2].endedCleanly == true)
    }

    /// Snapshots overwrite ONE file on disk — a crashed run leaves exactly
    /// one record holding every completed trial.
    @Test func snapshotsOverwriteTheSameFileOnDisk() {
        let store = makeTempStore()
        var run = makeRun()
        store.persist(run)
        run.trials.append(BatteryTrialRecord(
            shape: "armed", prompt: "remind", trial: 2,
            text: "later", cant: false, denial: false, toolCalls: [],
            route: nil, error: nil, timedOut: false, latencySeconds: 1.0
        ))
        store.persist(run)
        let loaded = store.loadRuns()
        #expect(loaded.count == 1)
        #expect(loaded.first?.trials.count == run.trials.count)
    }

    /// Export honesty for crashed runs: endedCleanly == false renders an
    /// INCOMPLETE line where DONE would go — a paste can never read as a
    /// completed run. Legacy records (nil, all pre-hardening runs completed)
    /// and clean runs keep DONE.
    @Test func incompleteRunRendersIncompleteInsteadOfDone() {
        var run = makeRun()
        run.probes = []
        run.endedCleanly = false
        let rendered = BatteryRunMath.renderRawLines(for: run)
        #expect(rendered.contains("battery: INCOMPLETE — run died before DONE (#196)"))
        #expect(!rendered.contains("battery: DONE"))

        run.endedCleanly = true
        #expect(BatteryRunMath.renderRawLines(for: run).contains("battery: DONE (#196)"))
        run.endedCleanly = nil
        #expect(BatteryRunMath.renderRawLines(for: run).contains("battery: DONE (#196)"))
    }

    @Test func incompleteProbeRunRendersProbeIncomplete() {
        var run = makeRun()
        run.trials = []
        run.endedCleanly = false
        let rendered = BatteryRunMath.renderRawLines(for: run)
        #expect(rendered.contains("router: PROBE INCOMPLETE — run died before DONE (#196)"))
        #expect(!rendered.contains("router: PROBE DONE"))
    }

    /// Legacy shape-battery runs pass no kind — the record stays nil so the
    /// export keeps the #196 grammar.
    @Test func recorderDefaultsKindNil() throws {
        let captured = CapturingStore()
        let recorder = BatteryRunRecorder(store: captured)
        recorder.beginRun(trialsPerCell: 10, cells: ["armed"])
        recorder.beginTrial()
        recorder.endTrial(shape: "armed", prompt: "canary", trial: 1,
                          text: "4", cant: false, denial: false)
        recorder.endRun()
        let run = try #require(captured.persisted.first)
        #expect(run.kind == nil)
        #expect(run.reapSummary == nil)
    }

    @Test func recorderDropsEmptyRuns() {
        let captured = CapturingStore()
        let recorder = BatteryRunRecorder(store: captured)
        recorder.beginRun(trialsPerCell: 20, cells: ["armed"])
        recorder.endRun()
        #expect(captured.persisted.isEmpty)
    }

    @Test func recorderIgnoresEventsOutsideARun() {
        let captured = CapturingStore()
        let recorder = BatteryRunRecorder(store: captured)
        recorder.beginTrial()
        recorder.recordToolCall(name: "x", detail: "y")
        recorder.endTrial(shape: "armed", prompt: "canary", trial: 1,
                          text: "4", cant: false, denial: false)
        recorder.endRun()
        #expect(captured.persisted.isEmpty)
    }

    // MARK: Tally math

    @Test func talliesCountFlagsPerCellPromptInRunOrder() {
        let run = makeRun()
        let tallies = BatteryRunMath.tallies(for: run.trials)
        #expect(tallies.count == 3)

        #expect(tallies[0] == BatteryCellPromptTally(
            shape: "armed", prompt: "canary", total: 1,
            cantCount: 0, denialCount: 0, toolTrialCount: 1, errorCount: 0, timeoutCount: 0))
        #expect(tallies[1] == BatteryCellPromptTally(
            shape: "armed-routed", prompt: "haiku", total: 1,
            cantCount: 0, denialCount: 0, toolTrialCount: 0, errorCount: 0, timeoutCount: 0))
        #expect(tallies[2] == BatteryCellPromptTally(
            shape: "armed-routed", prompt: "norway", total: 2,
            cantCount: 0, denialCount: 0, toolTrialCount: 0, errorCount: 1, timeoutCount: 1))
    }

    @Test func routeDistributionCountsRoutedTrialsOnly() {
        let run = makeRun()
        let rows = BatteryRunMath.routeDistribution(for: run.trials)
        // armed/canary has no route and must not appear; norway t2 (timeout,
        // no route recorded) doesn't count either.
        #expect(rows.count == 2)
        #expect(rows[0].prompt == "haiku")
        #expect(rows[0].armed == 0)
        #expect(rows[0].toolless == 1)
        #expect(rows[1].prompt == "norway")
        #expect(rows[1].armed == 1)
        #expect(rows[1].toolless == 0)
    }

    // MARK: Export grammar — what classification tooling parses

    @Test func rawLineRenderingMatchesTheEmitGrammar() throws {
        let run = makeRun()
        let lines = BatteryRunMath.renderRawLines(for: run).components(separatedBy: "\n")

        try #require(lines.count == 14)
        #expect(lines[0].hasPrefix("battery: RUN "))
        #expect(lines[0].contains("build=1.0(42)"))
        #expect(lines[1] == "battery: START trials=2 cells=2 prompts=3 (#196)")
        #expect(lines[2] == "battery: tool=createReminder shape=armed p=canary t=1 detail=title: 2+2")
        // A CAPTURED confirmation outcome renders on any run kind (#200);
        // only the confirm=none synthesis is action-run-scoped.
        #expect(lines[3] == "battery: confirm=declined shape=armed p=canary t=1")
        #expect(lines[4] == "battery: shape=armed p=canary t=1 cant=false denial=false chars=10 text=2 + 2 = 4.")
        #expect(lines[5] == "battery: route=toolless shape=armed-routed p=haiku t=1")
        // Reply newlines flatten to " / " exactly as batteryEmit does, and
        // chars counts the ORIGINAL text.
        #expect(lines[6] == "battery: shape=armed-routed p=haiku t=1 cant=false denial=false chars=75 text=Snow hush on the hill / runners carve a silver line / breath blooms and is gone")
        #expect(lines[7] == "battery: route=armed shape=armed-routed p=norway t=1")
        #expect(lines[8] == "battery: shape=armed-routed p=norway t=1 ERROR=ToolCallError boom")
        #expect(lines[9] == "battery: shape=armed-routed p=norway t=2 TIMEOUT — wedged trial guillotined")
        #expect(lines[10] == "battery: DONE (#196)")
        #expect(lines[11] == "router: PROBE START trials=2 probes=1 (#196)")
        #expect(lines[12] == "router: 20/20 expected=false probe=Write a haiku about sledding")
        #expect(lines[13] == "router: PROBE DONE (#196)")
    }

    /// #200 action-battery export: confirm lines per captured outcome,
    /// confirm=none SYNTHESIZED for action-named tools that never staged a
    /// confirmation (pre-gate bail), the REAP teardown line, and the #200
    /// item marker on START/REAP/DONE. Read tools never get a synthesized
    /// none — they have no gate.
    @Test func actionRunRendersConfirmAndReapLinesWithThe200Marker() throws {
        let run = BatteryRunRecord(
            id: UUID(),
            startedAt: Date(timeIntervalSince1970: 1_753_700_000),
            appVersion: "1.0",
            appBuild: "42",
            osVersion: "v27",
            trialsPerCell: 20,
            cells: ["armed"],
            trials: [
                BatteryTrialRecord(
                    shape: "armed", prompt: "remind", trial: 1,
                    text: "Created it.", cant: false, denial: false,
                    toolCalls: [BatteryToolCallRecord(name: "createReminder", detail: "test Talaria", confirmation: "accepted")],
                    route: nil, error: nil, timedOut: false, latencySeconds: 4.0
                ),
                BatteryTrialRecord(
                    shape: "armed", prompt: "alarm", trial: 1,
                    text: "Couldn't read a time.", cant: false, denial: false,
                    toolCalls: [
                        BatteryToolCallRecord(name: "readReminders", detail: ""),
                        BatteryToolCallRecord(name: "scheduleAlarm", detail: "6:30"),
                    ],
                    route: nil, error: nil, timedOut: false, latencySeconds: 6.0
                ),
            ],
            probes: [],
            kind: "action",
            reapSummary: "reminders=1 events=0 alarms=0 failures=0"
        )
        let lines = BatteryRunMath.renderRawLines(for: run).components(separatedBy: "\n")

        try #require(lines.count == 11)
        #expect(lines[0].hasPrefix("battery: RUN "))
        #expect(lines[1] == "battery: START trials=20 cells=1 prompts=2 (#200)")
        #expect(lines[2] == "battery: tool=createReminder shape=armed p=remind t=1 detail=test Talaria")
        #expect(lines[3] == "battery: confirm=accepted shape=armed p=remind t=1")
        #expect(lines[4] == "battery: shape=armed p=remind t=1 cant=false denial=false chars=11 text=Created it.")
        #expect(lines[5] == "battery: tool=readReminders shape=armed p=alarm t=1 detail=")
        #expect(lines[6] == "battery: tool=scheduleAlarm shape=armed p=alarm t=1 detail=6:30")
        #expect(lines[7] == "battery: confirm=none shape=armed p=alarm t=1")
        #expect(lines[8] == "battery: shape=armed p=alarm t=1 cant=false denial=false chars=21 text=Couldn't read a time.")
        #expect(lines[9] == "battery: REAP reminders=1 events=0 alarms=0 failures=0 (#200)")
        #expect(lines[10] == "battery: DONE (#200)")
    }

    // MARK: - #340 bar 340-F5 — the belt-text configuration rides the artifact

    /// **The field survives a round trip, in both states.**
    ///
    /// #398-A's third axis: a rate must carry its configuration. A due-date
    /// number measured WITHOUT the belt text is the fallback measured switched
    /// off — `source=userText 0/N`, reading as a product that does not work —
    /// and nothing in the artifact said which run was which until this field.
    @Test func theRunRecordCarriesTheBeltTextConfiguration() throws {
        for value in [true, false] {
            var run = makeRun()
            run.carriesUserText = value

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode(BatteryRunRecord.self,
                                             from: try encoder.encode(run))

            #expect(decoded.carriesUserText == value)
        }
    }

    /// **The recorder writes what the battery was actually run with**, and
    /// leaves it NOT RECORDED for the instruments that have no belt-text
    /// dimension at all — the default is `nil`, so a probe run never claims a
    /// configuration nobody measured.
    @Test func theRecorderStampsTheConfigurationOnlyWhenItIsGiven() {
        // One trial each: `endRun` DROPS a run with no trials and no probes,
        // so a trial-free fixture would assert against an empty store and pass
        // for the wrong reason on the nil half.
        func run(_ recorder: BatteryRunRecorder) {
            recorder.beginTrial()
            recorder.endTrial(shape: "armed", prompt: "remind", trial: 1,
                              text: "ok", cant: false, denial: false)
            recorder.endRun()
        }

        let armed = CapturingStore()
        let recorderOn = BatteryRunRecorder(store: armed)
        recorderOn.beginRun(trialsPerCell: 1, cells: ["armed"], kind: "action",
                            carriesUserText: true)
        run(recorderOn)
        #expect(armed.persisted.last?.carriesUserText == true)

        let silent = CapturingStore()
        let recorderOff = BatteryRunRecorder(store: silent)
        recorderOff.beginRun(trialsPerCell: 1, cells: ["armed"])
        run(recorderOff)
        #expect(silent.persisted.isEmpty == false, "the fixture recorded nothing — a vacuous nil")
        #expect(silent.persisted.last?.carriesUserText == nil,
                "an instrument with no belt-text dimension must record NOT MEASURED")
    }

    // MARK: Decode compatibility — old run JSONs must still decode (#200)

    /// A pre-#200 run file has no `confirmation`, `kind`, or `reapSummary`
    /// keys anywhere. The store-version bump is optionality: decoding must
    /// succeed with the new fields nil, and every pre-existing field intact.
    @Test func preCaptureRunJSONStillDecodes() throws {
        let json = """
        {
          "appBuild" : "40",
          "appVersion" : "1.0",
          "cells" : ["armed"],
          "id" : "8E2C1D6A-0F6E-4C11-9D2B-3B6F6D7E8A90",
          "osVersion" : "Version 27.0",
          "probes" : [],
          "startedAt" : "2026-07-27T12:00:00Z",
          "trials" : [
            {
              "cant" : false,
              "denial" : false,
              "latencySeconds" : 2.5,
              "prompt" : "haiku",
              "shape" : "armed",
              "text" : "a haiku",
              "timedOut" : false,
              "toolCalls" : [
                { "detail" : "title: sledding", "name" : "createReminder" }
              ],
              "trial" : 1
            }
          ],
          "trialsPerCell" : 20
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let run = try decoder.decode(BatteryRunRecord.self, from: Data(json.utf8))

        #expect(run.kind == nil)
        #expect(run.reapSummary == nil)
        #expect(run.endedCleanly == nil)
        // #340 bar 340-F5: ABSENT decodes to nil, never false. `false` would
        // claim of every pre-2026-09 archive that its belt was measured with
        // the user's text withheld — true of the mechanism, never measured.
        #expect(run.carriesUserText == nil,
                "an absent carriesUserText must read NOT RECORDED, not `false`")
        #expect(run.trials.count == 1)
        #expect(run.trials[0].toolCalls == [
            BatteryToolCallRecord(name: "createReminder", detail: "title: sledding", confirmation: nil),
        ])
        #expect(run.trials[0].text == "a haiku")
        #expect(run.trialsPerCell == 20)
    }

    @Test func probeOnlyRunRendersOnlyRouterLines() {
        var run = makeRun()
        run.trials = []
        let rendered = BatteryRunMath.renderRawLines(for: run)
        #expect(!rendered.contains("battery: START"))
        #expect(!rendered.contains("battery: DONE"))
        #expect(rendered.contains("router: PROBE START"))
        #expect(rendered.contains("router: PROBE DONE (#196)"))
    }
}
#endif
