import Foundation
import Testing
@testable import Talaria

/// OPEN_ITEMS #225 — the unbounded tool-call spiral.
///
/// **Production, 2026-08-02:** "what's the weather gonna be in Gulfport tomorrow"
/// produced **64 tool calls in ~90 seconds, no reply text, and was still calling
/// `searchConversations` when Owen killed it.** There was no evidence of any
/// bound — 64 is where the user intervened, not where it stopped.
///
/// The shape: call 2 was the RIGHT call (`currentWeather`), its contract is
/// today-only, "tomorrow" was unmeetable, and the unmet demand displaced into
/// `searchConversations` (#216's substitution mechanism) then degenerated into a
/// repetition loop mining the memory injection for query terms.
///
/// These tests cover the MECHANICAL bars pre-registered in #225. The four
/// behavioural bars (does the turn speak, does it stay honest) need a device run
/// and are recorded in the entry, not claimed here.
///
/// `@MainActor` because the governor is: it lives on `ToolEventRelay`, which is
/// MainActor-isolated and is what every tool already hops to. Isolating the test
/// rather than loosening the type is deliberate — the governor's state is
/// mutable and per-turn, so a `nonisolated` version would need its own locking
/// to protect nothing that ever runs off the main actor.
@MainActor
struct ToolCallGovernorTests {

    // MARK: - Bar 1: the per-turn budget

    @Test func callsUpToTheBudgetAreAdmitted() {
        let governor = ToolCallGovernor(perTurnBudget: 12, sameToolRepeatCap: 4)
        for i in 1...12 {
            #expect(governor.admit(tool: "tool\(i)") == .allowed, "call \(i) should be admitted")
        }
    }

    @Test func theCallPastTheBudgetIsRefused() {
        let governor = ToolCallGovernor(perTurnBudget: 12, sameToolRepeatCap: 4)
        for i in 1...12 { _ = governor.admit(tool: "tool\(i)") }
        #expect(governor.admit(tool: "tool13").isRefused)
    }

    /// #225's own number: 64 calls. With the budget in place the spiral cannot
    /// get past 12 no matter how many distinct tools it reaches for.
    @Test func aSixtyFourCallSpiralIsCutAtTheBudget() {
        let governor = ToolCallGovernor(perTurnBudget: 12, sameToolRepeatCap: 4)
        var admitted = 0
        for i in 1...64 where governor.admit(tool: "tool\(i)") == .allowed { admitted += 1 }
        #expect(admitted == 12)
    }

    // MARK: - Bar 2: the same-tool repeat cap

    @Test func theFifthConsecutiveCallToOneToolIsRefused() {
        let governor = ToolCallGovernor(perTurnBudget: 12, sameToolRepeatCap: 4)
        for i in 1...4 {
            #expect(governor.admit(tool: "searchConversations") == .allowed, "repeat \(i)")
        }
        #expect(governor.admit(tool: "searchConversations").isRefused)
    }

    /// The cap is PER TOOL, not a disguised global counter — a different tool
    /// must still be reachable after one tool has exhausted its repeats. The
    /// observed spiral hammered a single tool; strangling the whole belt would
    /// break legitimate chains (#225 bar B4).
    @Test func adifferentToolStillProceedsAfterAnotherIsCapped() {
        let governor = ToolCallGovernor(perTurnBudget: 12, sameToolRepeatCap: 4)
        for _ in 1...4 { _ = governor.admit(tool: "searchConversations") }
        #expect(governor.admit(tool: "searchConversations").isRefused)
        #expect(governor.admit(tool: "currentWeather") == .allowed)
    }

    /// The real spiral interleaved a little before degenerating. The cap counts
    /// calls to a tool across the whole turn, not just consecutive ones —
    /// otherwise alternating two tools defeats it entirely.
    @Test func interleavingTwoToolsDoesNotDefeatTheRepeatCap() {
        let governor = ToolCallGovernor(perTurnBudget: 12, sameToolRepeatCap: 4)
        for _ in 1...4 {
            _ = governor.admit(tool: "searchConversations")
            _ = governor.admit(tool: "readCalendar")
        }
        #expect(governor.admit(tool: "searchConversations").isRefused)
        #expect(governor.admit(tool: "readCalendar").isRefused)
    }

    // MARK: - Bar 3: counters reset per turn

    /// **The obvious way for this fix to become a worse bug than the one it
    /// fixes.** A budget that leaked across turns would silently strangle a long
    /// conversation — every turn after the twelfth call of the session would be
    /// toolless, with no signal.
    @Test func theBudgetResetsForEachTurn() {
        let governor = ToolCallGovernor(perTurnBudget: 12, sameToolRepeatCap: 4)
        for i in 1...12 { _ = governor.admit(tool: "tool\(i)") }
        #expect(governor.admit(tool: "tool13").isRefused)

        governor.beginTurn()

        #expect(governor.admit(tool: "tool1") == .allowed, "a new turn must start with a full budget")
    }

    @Test func theRepeatCapAlsoResetsForEachTurn() {
        let governor = ToolCallGovernor(perTurnBudget: 12, sameToolRepeatCap: 4)
        for _ in 1...4 { _ = governor.admit(tool: "searchConversations") }
        #expect(governor.admit(tool: "searchConversations").isRefused)

        governor.beginTurn()

        #expect(governor.admit(tool: "searchConversations") == .allowed)
    }

    // MARK: - Bar 4: the refusal is TEXT, and it is usable

    /// A refusal must arrive as the tool's own output string so the model can
    /// react to it. **Throwing would kill the turn upstream — #197's failure
    /// mode — trading a spiral for a dead turn.**
    @Test func aRefusalCarriesGuidanceTheModelCanActon() {
        let governor = ToolCallGovernor(perTurnBudget: 1, sameToolRepeatCap: 1)
        _ = governor.admit(tool: "searchConversations")
        guard case .refused(let message) = governor.admit(tool: "searchConversations") else {
            Issue.record("expected a refusal")
            return
        }
        // Tells the model to stop calling tools and answer — the #197/#201B
        // shape: name what happened, name what to do instead.
        #expect(message.lowercased().contains("answer"))
        #expect(!message.isEmpty)
        // No internals: this string is user-adjacent via the model.
        for leak in ["Talaria.", "0x", "Optional(", "Error"] {
            #expect(!message.contains(leak), "refusal leaked \(leak): \(message)")
        }
    }

    /// The budget refusal and the repeat refusal say DIFFERENT things — a model
    /// that can distinguish "you have used your tools" from "stop calling that
    /// one" has a chance of doing the right thing with each.
    @Test func budgetAndRepeatRefusalsAreDistinguishable() {
        let budgeted = ToolCallGovernor(perTurnBudget: 1, sameToolRepeatCap: 99)
        _ = budgeted.admit(tool: "a")
        let repeated = ToolCallGovernor(perTurnBudget: 99, sameToolRepeatCap: 1)
        _ = repeated.admit(tool: "a")

        guard case .refused(let budgetMessage) = budgeted.admit(tool: "b"),
              case .refused(let repeatMessage) = repeated.admit(tool: "a") else {
            Issue.record("expected both to refuse")
            return
        }
        #expect(budgetMessage != repeatMessage)
    }
}
