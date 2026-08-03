import Foundation
import FoundationModels
import Testing
@testable import Talaria

/// OPEN_ITEMS #228 — Lane 0 of the local-brain device run: the production
/// tool-call instrument.
///
/// On the night #225's cap was falsified on device, tool chips were counted BY
/// EYE and the log could not corroborate them — the relay's per-call logging is
/// `#if DEBUG` + battery-tag gated, so a Release build logs nothing. These tests
/// pin the instrument's data source (the relay's per-turn counters) and the
/// exact log-line shapes, which are the grep keys the device run will read.
///
/// The os_log emission itself is a two-line verbose-gated shim over these pure
/// pieces; L0-A/L0-C's "readable on a verbose Release build" halves are device
/// bars in #228, not claimed here.
///
/// `@MainActor` for the same reason `ToolCallGovernorTests` is: the relay is
/// MainActor-isolated, and every tool already hops to it.
@MainActor
struct ToolCallInstrumentTests {

    // MARK: - Per-turn counters (the instrument's data source)

    @Test func executedCallsCountUpWithinATurn() throws {
        let relay = ToolEventRelay()
        _ = try relay.started("currentWeather")
        _ = try relay.started("readCalendar")
        _ = try relay.started("currentWeather")
        #expect(relay.executedCallsThisTurn == 3)
        #expect(relay.refusalsThisTurn == 0)
    }

    @Test func aRefusedCallCountsAsARefusalNotAnExecution() throws {
        let relay = ToolEventRelay()
        relay.governor = ToolCallGovernor(perTurnBudget: 1, sameToolRepeatCap: 99)
        _ = try relay.started("currentWeather")
        let admission = try relay.started("searchConversations")
        #expect(admission.isRefused)
        #expect(relay.executedCallsThisTurn == 1)
        #expect(relay.refusalsThisTurn == 1)
    }

    /// #225's invariant, re-pinned here so the instrument can never regress it:
    /// a refused call gets a LOG line (L0-B) but still no chip — a chip for work
    /// that never happened is the lie #180 is about.
    @Test func aRefusedCallStillEmitsNoChip() throws {
        let relay = ToolEventRelay()
        relay.governor = ToolCallGovernor(perTurnBudget: 1, sameToolRepeatCap: 99)
        var events: [ToolCallEvent] = []
        relay.emit = { events.append($0) }
        _ = try relay.started("currentWeather")
        _ = try relay.started("searchConversations")
        #expect(events.map(\.name) == ["currentWeather"])
    }

    /// The relay's `beginTurn()` is now the single turn-boundary call: it must
    /// reset the instrument's counters AND forward to the governor, because
    /// `LocalChatBackend.beginToolTurn()` stops calling the governor directly.
    /// A leaked counter would misnumber every later turn's log; a dropped
    /// governor forward would resurrect #225's silent-strangulation bug.
    @Test func beginTurnResetsTheCountersAndTheGovernor() throws {
        let relay = ToolEventRelay()
        relay.governor = ToolCallGovernor(perTurnBudget: 1, sameToolRepeatCap: 99)
        _ = try relay.started("currentWeather")
        _ = try relay.started("searchConversations")  // refused: budget spent

        relay.beginTurn()

        #expect(relay.executedCallsThisTurn == 0)
        #expect(relay.refusalsThisTurn == 0)
        #expect(try relay.started("readCalendar") == .allowed, "a new turn must start with a full budget")
    }

    // MARK: - Log-line shapes (pure; pinned so the grep keys stay stable)

    @Test func callLogLineCarriesSequenceNameAndDetail() {
        let line = ToolEventRelay.callLogLine(sequence: 3, name: "currentWeather", detail: "Gulfport")
        #expect(line == "tool-call #3 currentWeather — Gulfport (#228)")
    }

    @Test func callLogLineOmitsAnAbsentDetail() {
        #expect(ToolEventRelay.callLogLine(sequence: 1, name: "readCalendar", detail: nil)
            == "tool-call #1 readCalendar (#228)")
        #expect(ToolEventRelay.callLogLine(sequence: 2, name: "readCalendar", detail: "")
            == "tool-call #2 readCalendar (#228)")
    }

    /// Console-line width, same 80-char budget the battery line uses. The
    /// ellipsis marks the cut so a truncated detail can't read as complete.
    @Test func callLogLineTruncatesALongDetail() {
        let long = String(repeating: "x", count: 200)
        let line = ToolEventRelay.callLogLine(sequence: 1, name: "searchConversations", detail: long)
        #expect(line == "tool-call #1 searchConversations — \(String(repeating: "x", count: 80))… (#228)")
    }

    @Test func refusalLogLineNamesTheToolAndBothCounts() {
        let line = ToolEventRelay.refusalLogLine(
            name: "searchConversations", executedThisTurn: 12, refusalsThisTurn: 3)
        #expect(line == "tool-call REFUSED searchConversations — 12 executed, 3 refusal(s) this turn (#225/#228)")
    }

    // MARK: - Session budget line (Lane 0.2 — the number nobody has seen)

    @Test func sessionBudgetLineReportsAllFourNumbersAndTheHeadroom() {
        let line = LocalChatBackend.sessionBudgetLogLine(
            toolCount: 13, toolTokens: 2500, transcriptTokens: 900, window: 8192)
        #expect(line == "session budget: 13 tool(s) ~2500 tok + transcript ~900 tok of window 8192 — ~4792 free (#228)")
    }

    /// Real-data-only: where the tokenizer is unavailable (the sim has no
    /// model) the line shows "—" and never invents a number.
    @Test func sessionBudgetLineShowsDashesWhenTheTokenizerIsUnavailable() {
        let line = LocalChatBackend.sessionBudgetLogLine(
            toolCount: 13, toolTokens: nil, transcriptTokens: nil, window: 8192)
        #expect(line == "session budget: 13 tool(s) ~— tok + transcript ~— tok of window 8192 — free — (#228)")
    }

    @Test func sessionBudgetLineWithOneMeasurementMissingStillShowsTheOther() {
        let line = LocalChatBackend.sessionBudgetLogLine(
            toolCount: 13, toolTokens: 2500, transcriptTokens: nil, window: 8192)
        #expect(line == "session budget: 13 tool(s) ~2500 tok + transcript ~— tok of window 8192 — free — (#228)")
    }

    // MARK: - #233 conversation latch

    @Test func earlyMorningAskClaimsExactlyOncePerConversation() {
        let relay = ToolEventRelay()
        #expect(relay.claimEarlyMorningAsk())
        #expect(!relay.claimEarlyMorningAsk())
    }

    /// The ask/answer round-trip spans two turns — a turn boundary must not
    /// re-arm the bounce, or the model asks again after the user answers.
    @Test func beginTurnDoesNotClearTheEarlyMorningLatch() {
        let relay = ToolEventRelay()
        _ = relay.claimEarlyMorningAsk()
        relay.beginTurn()
        #expect(!relay.claimEarlyMorningAsk())
    }

    @Test func clearConversationResetsTheEarlyMorningLatch() async throws {
        let backend = makeBackend()
        let relay = ToolEventRelay()
        backend.installTools([], relay: relay)
        #expect(relay.claimEarlyMorningAsk())
        _ = try await backend.clearConversation()
        #expect(relay.claimEarlyMorningAsk())
    }

    // MARK: - Deferred measurement (#228, revised after the device falsified L0-D)
    //
    // The first shipped shape measured DURING the turn: its tokenizer round
    // trips shared the FM client plumbing with the live stream, and their
    // teardown invalidated the turn's provider connection (ModelManagerError
    // 1001 → the UI's "LanguageModelError -1", device, 2026-08-02, trial 1).
    // The revision captures values at session build and measures only at the
    // post-turn flush. These tests pin the queue discipline; the measurement
    // itself needs the model and stays a thin async tail.

    private func makeBackend() -> LocalChatBackend {
        LocalChatBackend(
            persistence: UserDefaultsAppPersistenceStore(
                defaults: UserDefaults(suiteName: "tool-call-instrument-tests")!
            ),
            intelligence: LocalIntelligenceService()
        )
    }

    @Test func budgetRecordingQueuesNothingWhenVerboseIsOff() {
        TalariaLog.setVerbose(false)
        let backend = makeBackend()
        backend.recordSessionBudgetIfVerbose(offered: [], transcript: Transcript())
        #expect(backend.pendingSessionBudgets.isEmpty)
    }

    /// Two records per turn is the real shape: a #26 overflow rebuilds the
    /// session mid-turn, and BOTH builds' budgets must survive to the flush.
    @Test func budgetRecordingQueuesOnePerSessionBuildWhenVerboseIsOn() {
        TalariaLog.setVerbose(true)
        defer { TalariaLog.setVerbose(false) }
        let backend = makeBackend()
        backend.recordSessionBudgetIfVerbose(offered: [], transcript: Transcript())
        backend.recordSessionBudgetIfVerbose(offered: [], transcript: Transcript())
        #expect(backend.pendingSessionBudgets.count == 2)
    }

    @Test func flushDrainsTheQueue() {
        TalariaLog.setVerbose(true)
        defer { TalariaLog.setVerbose(false) }
        let backend = makeBackend()
        backend.recordSessionBudgetIfVerbose(offered: [], transcript: Transcript())
        backend.flushSessionBudgetMeasurements()
        #expect(backend.pendingSessionBudgets.isEmpty)
    }

    // MARK: - #232: the refusal cut (bars 232-A/B, pre-registered in the entry)
    //
    // Trial 1, instrumented: after the 12-call cap the model burned 57
    // refusal→re-infer cycles at ~2.4s each — refusals as tool output keep it
    // in tool-calling mode, and NOTHING bounded the loop. The cut ends the
    // tool phase STRUCTURALLY: the fourth attempted call in one turn throws
    // `ToolPhaseCutError` (the Tool protocol is already `throws`), which the
    // send loops catch like #26/#197 and retry once as a routed-toolless turn.

    @Test func refusalsOneThroughThreeAreStringsTheFourthAttemptThrows() throws {
        let relay = ToolEventRelay()
        relay.governor = ToolCallGovernor(perTurnBudget: 1, sameToolRepeatCap: 99)
        _ = try relay.started("currentWeather")                       // executed
        for attempt in 1...3 {
            let admission = try relay.started("searchConversations")  // refusals 1–3
            #expect(admission.isRefused, "refusal \(attempt) must still be a string the model can react to")
        }
        #expect(relay.refusalsThisTurn == 3)
        #expect(throws: ToolPhaseCutError.self) {
            _ = try relay.started("searchConversations")              // attempt 4 → cut
        }
    }

    @Test func beginTurnRearmsTheCut() throws {
        let relay = ToolEventRelay()
        relay.governor = ToolCallGovernor(perTurnBudget: 0, sameToolRepeatCap: 99)
        for _ in 1...3 { _ = try relay.started("a") }
        #expect(throws: ToolPhaseCutError.self) { _ = try relay.started("a") }

        relay.beginTurn()

        // A fresh turn gets refusal STRINGS again, not an instant throw.
        #expect(try relay.started("a").isRefused)
    }

    /// A turn with no refusals can never reach the throw — the cut must be
    /// unobservable on every healthy path (bar 232-D's sim half).
    @Test func aHealthyTurnNeverThrows() throws {
        let relay = ToolEventRelay()
        relay.governor = ToolCallGovernor(perTurnBudget: 12, sameToolRepeatCap: 4)
        for i in 1...12 {
            #expect(try relay.started("tool\(i)") == .allowed)
        }
    }

    /// The send loops see the cut either bare or wrapped in the SDK's
    /// `ToolCallError` — both must route to the toolless retry (bar 232-B).
    @Test func theCutIsDetectedBareAndWrappedInToolCallError() {
        #expect(LocalChatBackend.isToolPhaseCut(ToolPhaseCutError()))
        let wrapped = LanguageModelSession.ToolCallError(
            tool: DeviceStatusTool(relay: ToolEventRelay()),
            underlyingError: ToolPhaseCutError()
        )
        #expect(LocalChatBackend.isToolPhaseCut(wrapped))
        #expect(!LocalChatBackend.isToolPhaseCut(CocoaError(.fileNoSuchFile)))
    }
}
