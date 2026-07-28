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
                    toolCalls: [BatteryToolCallRecord(name: "createReminder", detail: "title: 2+2")],
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

        #expect(captured.persisted.count == 1)
        let run = try #require(captured.persisted.first)
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

    @Test func rawLineRenderingMatchesTheEmitGrammar() {
        let run = makeRun()
        let lines = BatteryRunMath.renderRawLines(for: run).components(separatedBy: "\n")

        #expect(lines[0].hasPrefix("battery: RUN "))
        #expect(lines[0].contains("build=1.0(42)"))
        #expect(lines[1] == "battery: START trials=2 cells=2 prompts=3 (#196)")
        #expect(lines[2] == "battery: tool=createReminder shape=armed p=canary t=1 detail=title: 2+2")
        #expect(lines[3] == "battery: shape=armed p=canary t=1 cant=false denial=false chars=10 text=2 + 2 = 4.")
        #expect(lines[4] == "battery: route=toolless shape=armed-routed p=haiku t=1")
        // Reply newlines flatten to " / " exactly as batteryEmit does, and
        // chars counts the ORIGINAL text.
        #expect(lines[5] == "battery: shape=armed-routed p=haiku t=1 cant=false denial=false chars=75 text=Snow hush on the hill / runners carve a silver line / breath blooms and is gone")
        #expect(lines[6] == "battery: route=armed shape=armed-routed p=norway t=1")
        #expect(lines[7] == "battery: shape=armed-routed p=norway t=1 ERROR=ToolCallError boom")
        #expect(lines[8] == "battery: shape=armed-routed p=norway t=2 TIMEOUT — wedged trial guillotined")
        #expect(lines[9] == "battery: DONE (#196)")
        #expect(lines[10] == "router: PROBE START trials=2 probes=1 (#196)")
        #expect(lines[11] == "router: 20/20 expected=false probe=Write a haiku about sledding")
        #expect(lines[12] == "router: PROBE DONE (#196)")
        #expect(lines.count == 13)
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
