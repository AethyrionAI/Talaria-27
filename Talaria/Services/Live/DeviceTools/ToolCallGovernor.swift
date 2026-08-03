import Foundation

/// OPEN_ITEMS #225 — the bound that did not exist.
///
/// **Production, 2026-08-02:** "what's the weather gonna be in Gulfport tomorrow"
/// produced **64 tool calls in ~90 seconds with no reply text**, and was still
/// calling `searchConversations` when the user killed it. **64 is where Owen
/// intervened, not where it stopped — there was no evidence of any bound at all.**
///
/// The anatomy matters for why this governor is shaped the way it is: call 2 was
/// the *right* call (`currentWeather`), its contract is today-only, "tomorrow" was
/// unmeetable by any tool on the belt, and the unmet demand **displaced** into
/// `searchConversations` — #216's substitution mechanism — then degenerated into a
/// repetition loop mining the memory injection for query terms.
///
/// So two different failures need two different bounds:
/// - a **per-turn budget** catches any spiral regardless of shape;
/// - a **per-tool repeat cap** catches the observed one early, before it has
///   burned the whole budget on one tool.
///
/// **Numbers are pre-registered in #225 with their justification and an explicit
/// falsification condition:** legitimate observed chains are 2–3 calls and the
/// #200-series batteries topped out near 10 same-tool calls per trial, so 12
/// clears every measured legitimate turn with headroom. **If a legitimate turn
/// ever hits either cap, the value is wrong and moves** — that falsifies the
/// number, not the mechanism.
@MainActor
final class ToolCallGovernor {
    enum Admission: Equatable {
        case allowed
        /// Refusal text handed back as the tool's OWN OUTPUT.
        ///
        /// **Never a thrown error.** A throw kills the turn upstream of the model
        /// — that is #197's failure mode — and would trade an unbounded spiral
        /// for a dead turn, which is not an improvement. As tool output the model
        /// can read it and change course, which is the same channel #186's
        /// permission denials already use.
        case refused(String)

        var isRefused: Bool {
            if case .refused = self { return true }
            return false
        }
    }

    private let perTurnBudget: Int
    private let sameToolRepeatCap: Int
    private var callsThisTurn = 0
    private var callsByTool: [String: Int] = [:]

    init(perTurnBudget: Int = 12, sameToolRepeatCap: Int = 4) {
        self.perTurnBudget = perTurnBudget
        self.sameToolRepeatCap = sameToolRepeatCap
    }

    /// Resets both counters. **Called at the start of every turn — a budget that
    /// leaked across turns would silently strangle a long conversation**, leaving
    /// every turn after the twelfth call of the session toolless with no signal.
    /// That is the obvious way this fix becomes worse than the bug it fixes, so
    /// it is pinned by its own test.
    func beginTurn() {
        callsThisTurn = 0
        callsByTool.removeAll()
    }

    /// Consulted by each tool BEFORE it does work. Counts only admitted calls, so
    /// a refused call does not push the turn further toward its ceiling.
    func admit(tool name: String) -> Admission {
        if callsThisTurn >= perTurnBudget {
            return .refused(
                "You have used all the tool calls available for this turn. "
                + "Answer the user now with what you already have, and say plainly "
                + "what you could not find out."
            )
        }
        // Counted across the whole turn, not just consecutively: the observed
        // spiral interleaved before it degenerated, and a consecutive-only cap
        // is defeated by alternating two tools.
        if (callsByTool[name] ?? 0) >= sameToolRepeatCap {
            return .refused(
                "You have already called \(name) several times this turn and it is not "
                + "getting you closer. Do not call it again — answer the user with what "
                + "you have, and say plainly what you could not find out."
            )
        }
        callsThisTurn += 1
        callsByTool[name, default: 0] += 1
        return .allowed
    }
}
