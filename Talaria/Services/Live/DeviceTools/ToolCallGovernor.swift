import Foundation

/// OPEN_ITEMS #232 — the refusal grind's structural end.
///
/// Refusal STRINGS keep the model in tool-calling mode: instrumented on
/// device 2026-08-02, one turn burned 57 refusal→re-infer cycles (~2.4s
/// each) after the #225 cap correctly stopped execution. Refusals 1–3 stay
/// strings (the model gets real chances to course-correct); the FOURTH
/// attempted call in a turn throws this instead. The Tool protocol is
/// already `throws`, the error surfaces as `ToolCallError.underlyingError`,
/// and both send loops catch it and retry ONCE as a routed-toolless turn —
/// the 486-token shape measured clean 10/10 the same night. **This is the
/// one sanctioned tool-path throw; #197's never-throw rule still governs
/// refusals themselves.**
struct ToolPhaseCutError: Error {
    /// Refusals that stay strings before the cut. Pre-registered in #232
    /// with tonight's evidence: healthy turns showed zero refusals, and no
    /// observed case exists where refusal ≥4 led anywhere but the grind.
    /// A legitimate turn hitting the cut falsifies the NUMBER, not the
    /// mechanism.
    static let refusalThreshold = 3
}

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

    #if DEBUG
    /// #337 bar 337-D: ONE refusal, verbatim, with the state that produced it.
    ///
    /// #232 filed the grind — 57 refusal→re-infer cycles — and #337 measured
    /// its rate at scale (~80% of action turns cut). **Nobody has ever read
    /// what a refusal actually SAYS in a run that got cut**, so every filed
    /// number about the grind describes a text nobody has looked at. This is
    /// that text, plus the two counters that decide which branch produced it:
    /// a refusal whose `callsThisTurn` is 12 and whose `callsOfThisTool` is 0
    /// is a BUDGET refusal that this turn did not earn, and that is a
    /// different finding from a tool called four times.
    struct RefusalObservation: Equatable {
        enum Reason: String, Equatable {
            /// The per-turn budget was already spent when this call arrived.
            case perTurnBudget = "per-turn-budget"
            /// This tool had already been admitted `sameToolRepeatCap` times.
            case sameToolRepeat = "same-tool-repeat"
        }
        var tool: String
        var reason: Reason
        /// The refusal string EXACTLY as the model receives it.
        var text: String
        /// Admitted calls this turn at the moment of the refusal.
        var callsThisTurn: Int
        /// Admitted calls of THIS tool this turn at the moment of the refusal.
        var callsOfThisTool: Int
    }

    /// The 337-D capture sink. `nil` in every normal run — including every
    /// DEBUG run that is not an instrument — so the governor's hot path costs
    /// one optional load and nothing else.
    ///
    /// A shared static rather than an injected dependency because the governor
    /// is constructed inside `installTools` (#225's "a property of HAVING a
    /// belt" design) and an instrument has no handle on it. Same shape, and
    /// the same justification, as `ToolEventRelay.batteryTrialTag`.
    @MainActor
    final class RefusalCapture {
        static var current: RefusalCapture?
        private(set) var observations: [RefusalObservation] = []
        func record(_ observation: RefusalObservation) { observations.append(observation) }
        /// Returns everything captured since the last drain and clears the
        /// buffer — the per-trial boundary an instrument needs.
        @discardableResult
        func drain() -> [RefusalObservation] {
            defer { observations = [] }
            return observations
        }
    }
    #endif
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

    /// OPEN_ITEMS #409 — **the sentence that stops the model answering a refusal
    /// with a lie.**
    ///
    /// The 336-A forensics (2026-08-25) determined the trigger for #336's
    /// false-completion claims: when a refusal arrives as the same-tool-repeat
    /// STRING, the model asserts the write happened — *"I've set the alarm for
    /// 6:30 AM."* — **6/6 across two runs and two instruments**, while the
    /// phase-cut THROW path is honest **9/9**. The refusal wording is the
    /// discriminating variable.
    ///
    /// The old text named what to do (*"answer the user with what you have"*)
    /// and never forbade the one thing that hurts: reporting a call that never
    /// ran as a completed action. **Both refusal branches carry this clause** —
    /// the budget sibling was never the observed trigger, but it is the same
    /// defect class (a refusal inviting an answer without forbidding a claim),
    /// and letting one branch keep the invitation is how the defect survives a
    /// change in turn shape.
    ///
    /// One constant rather than two literals so the siblings cannot drift apart;
    /// each is nonetheless pinned independently, on the string `admit(tool:)`
    /// returns, by `ToolCallGovernorTests`.
    private static let doNotClaimClause =
        "This call was refused and did not run — do not tell the user the action happened."

    /// Consulted by each tool BEFORE it does work. Counts only admitted calls, so
    /// a refused call does not push the turn further toward its ceiling.
    func admit(tool name: String) -> Admission {
        if callsThisTurn >= perTurnBudget {
            let text = "You have used all the tool calls available for this turn. "
                + Self.doNotClaimClause + " "
                + "Answer the user now with what you already have, and say plainly "
                + "what you could not find out."
            #if DEBUG
            // #337-D: captured at the point the refusal is DECIDED, so the
            // text recorded is the one the model was handed rather than a
            // reconstruction of it.
            RefusalCapture.current?.record(RefusalObservation(
                tool: name, reason: .perTurnBudget, text: text,
                callsThisTurn: callsThisTurn, callsOfThisTool: callsByTool[name] ?? 0))
            #endif
            return .refused(text)
        }
        // Counted across the whole turn, not just consecutively: the observed
        // spiral interleaved before it degenerated, and a consecutive-only cap
        // is defeated by alternating two tools.
        if (callsByTool[name] ?? 0) >= sameToolRepeatCap {
            let text = "You have already called \(name) several times this turn and it is not "
                + "getting you closer. " + Self.doNotClaimClause + " "
                + "Do not call it again — answer the user with what "
                + "you have, and say plainly what you could not find out."
            #if DEBUG
            RefusalCapture.current?.record(RefusalObservation(
                tool: name, reason: .sameToolRepeat, text: text,
                callsThisTurn: callsThisTurn, callsOfThisTool: callsByTool[name] ?? 0))
            #endif
            return .refused(text)
        }
        callsThisTurn += 1
        callsByTool[name, default: 0] += 1
        return .allowed
    }
}
