import Foundation

/// A tool-call lifecycle event surfaced while a turn streams (#10/#11).
/// `tool.started` carries the name plus whatever input summary the server
/// provides; `tool.completed` is usually an empty payload on the wire, so a
/// completion event only arrives when the server names the finished tool.
struct ToolCallEvent: Sendable {
    enum Phase: Sendable {
        case started
        case completed
    }

    let name: String
    let phase: Phase
    /// Compact key-input summary (server `preview`, else condensed args).
    let detail: String?

    init(name: String, phase: Phase = .started, detail: String? = nil) {
        self.name = name
        self.phase = phase
        self.detail = detail
    }
}

enum StreamingUpdate: Sendable {
    case messageSent(jobID: UUID)
    case textDelta(String)
    /// Reasoning-channel delta (#4.15): the model's thinking, streamed over
    /// `tool.progress` events with `tool_name:"_thinking"`. A separate channel
    /// from the answer — never folded into `textDelta`.
    case reasoningDelta(String)
    case toolActivity(ToolCallEvent)
    /// P1 (#90): this turn started a fresh server session and transplanted
    /// condensed journal context into it as turn zero, BEFORE the user's turn
    /// was posted. Carries the priming turn's real token usage from its
    /// `run.completed` (nil when the server reported none) so the cost
    /// surfaces in the receipts — priming is not free.
    case contextPrimed(TokenUsage?)
    case finished(Message, TokenUsage?, CodeDiff?)
    case failed(String)
    /// P1 (#90): the turn never reached the Sessions API at all (transport
    /// failure — host down, no route, offline). Distinct from `failed` so the
    /// offline compose outbox can queue the turn durably and drain it when
    /// the API is reachable again, instead of dead-ending it.
    case unreachable(String)
    /// The stream dropped (e.g. the app was backgrounded on lock) AFTER the run
    /// was committed server-side. Not a failure: the run keeps running on the
    /// host and is reconciled via the Sessions messages endpoint.
    case interrupted(sessionId: String, runId: String?)
}
