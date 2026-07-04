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
    case toolActivity(ToolCallEvent)
    case finished(Message, TokenUsage?, CodeDiff?)
    case failed(String)
    /// The stream dropped (e.g. the app was backgrounded on lock) AFTER the run
    /// was committed server-side. Not a failure: the run keeps running on the
    /// host and is reconciled via the Sessions messages endpoint.
    case interrupted(sessionId: String, runId: String?)
}
