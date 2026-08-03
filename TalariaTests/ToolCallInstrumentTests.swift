import Foundation
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

    @Test func executedCallsCountUpWithinATurn() {
        let relay = ToolEventRelay()
        _ = relay.started("currentWeather")
        _ = relay.started("readCalendar")
        _ = relay.started("currentWeather")
        #expect(relay.executedCallsThisTurn == 3)
        #expect(relay.refusalsThisTurn == 0)
    }

    @Test func aRefusedCallCountsAsARefusalNotAnExecution() {
        let relay = ToolEventRelay()
        relay.governor = ToolCallGovernor(perTurnBudget: 1, sameToolRepeatCap: 99)
        _ = relay.started("currentWeather")
        let admission = relay.started("searchConversations")
        #expect(admission.isRefused)
        #expect(relay.executedCallsThisTurn == 1)
        #expect(relay.refusalsThisTurn == 1)
    }

    /// #225's invariant, re-pinned here so the instrument can never regress it:
    /// a refused call gets a LOG line (L0-B) but still no chip — a chip for work
    /// that never happened is the lie #180 is about.
    @Test func aRefusedCallStillEmitsNoChip() {
        let relay = ToolEventRelay()
        relay.governor = ToolCallGovernor(perTurnBudget: 1, sameToolRepeatCap: 99)
        var events: [ToolCallEvent] = []
        relay.emit = { events.append($0) }
        _ = relay.started("currentWeather")
        _ = relay.started("searchConversations")
        #expect(events.map(\.name) == ["currentWeather"])
    }

    /// The relay's `beginTurn()` is now the single turn-boundary call: it must
    /// reset the instrument's counters AND forward to the governor, because
    /// `LocalChatBackend.beginToolTurn()` stops calling the governor directly.
    /// A leaked counter would misnumber every later turn's log; a dropped
    /// governor forward would resurrect #225's silent-strangulation bug.
    @Test func beginTurnResetsTheCountersAndTheGovernor() {
        let relay = ToolEventRelay()
        relay.governor = ToolCallGovernor(perTurnBudget: 1, sameToolRepeatCap: 99)
        _ = relay.started("currentWeather")
        _ = relay.started("searchConversations")  // refused: budget spent

        relay.beginTurn()

        #expect(relay.executedCallsThisTurn == 0)
        #expect(relay.refusalsThisTurn == 0)
        #expect(relay.started("readCalendar") == .allowed, "a new turn must start with a full budget")
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
}
