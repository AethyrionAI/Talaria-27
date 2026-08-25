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

    // MARK: - Bar 409-A/B: the refusal forbids claiming the action happened

    /// **OPEN_ITEMS #409 — the refusal the model answers with a lie.**
    ///
    /// The 336-A forensics found that when the governor refuses with the
    /// same-tool-repeat STRING, the model asserts the write happened —
    /// *"I've set the alarm for 6:30 AM."* — **6/6 across two runs and two
    /// instruments**, while the phase-cut THROW path is honest 9/9. The old
    /// wording invited it: *"answer the user with what you have"* names what to
    /// do and never forbids claiming the refused call succeeded.
    ///
    /// These two tests pin the DECIDED text — the string `admit(tool:)` actually
    /// returns — rather than the source literal, so a grep-shaped "fix" that
    /// edits a comment cannot satisfy them. **This is a wording bar, not a
    /// behavioural one** (409-D): the model's response to the new text is
    /// verified by the next device `refusal-words` run, not here.
    static let doNotClaimClause = "This call was refused and did not run — do not tell the user the action happened."

    @Test func theRepeatRefusalForbidsClaimingTheActionHappened() {
        let governor = ToolCallGovernor(perTurnBudget: 99, sameToolRepeatCap: 4)
        for _ in 1...4 { _ = governor.admit(tool: "scheduleAlarm") }
        guard case .refused(let message) = governor.admit(tool: "scheduleAlarm") else {
            Issue.record("expected a same-tool-repeat refusal")
            return
        }
        #expect(message.contains(Self.doNotClaimClause),
                "the same-tool-repeat refusal must forbid claiming the action happened: \(message)")
        // The clause is an ADDITION — #409 does not spend the guidance that was
        // already there, and the tool name still identifies which call was cut.
        #expect(message.contains("scheduleAlarm"))
        #expect(message.contains("answer the user with what you have"))
        #expect(message.contains("say plainly what you could not find out"))
    }

    @Test func theBudgetRefusalForbidsClaimingTheActionHappened() {
        let governor = ToolCallGovernor(perTurnBudget: 3, sameToolRepeatCap: 99)
        for i in 1...3 { _ = governor.admit(tool: "tool\(i)") }
        guard case .refused(let message) = governor.admit(tool: "createCalendarEvent") else {
            Issue.record("expected a per-turn-budget refusal")
            return
        }
        // 409-B: the sibling string rides along — same defect class, declared as
        // an explicit scope extension of the ruling BEFORE any code was written.
        #expect(message.contains(Self.doNotClaimClause),
                "the per-turn-budget refusal must forbid claiming the action happened: \(message)")
        #expect(message.contains("Answer the user now with what you already have"))
        #expect(message.contains("say plainly what you could not find out"))
    }
}
