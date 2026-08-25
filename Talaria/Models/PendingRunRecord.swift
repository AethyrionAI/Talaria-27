import Foundation

/// #329: the pending run's durable half. `ChatStore.pendingRun` is in-memory
/// and dies with the process, which used to force the cold-load scrubber to
/// classify every restored `.sending` row as failed without asking anyone.
/// This record survives, so a relaunch can consult `GET /v1/runs/{id}`
/// (`resolveDroppedRun`) and classify from the host's own verdict instead.
///
/// Only run-id-carrying pending runs are recorded — a record without a run id
/// has no status read to consult, and the legacy positional re-read is too
/// blunt an instrument to point at a cache from a dead process.
struct PendingRunRecord: Codable, Equatable, Sendable {
    let sessionId: String
    let runId: String
    /// The `.sending`/`.working` user row this run answers — the row the
    /// scrubber must NOT flip and the reconcile settles.
    let userMessageID: UUID
    /// The thread the row lives on. A record must never arm recovery against
    /// a different conversation — adoption into the wrong thread is #307's
    /// corruption arriving through a new door.
    let conversationID: UUID
    let sentAt: Date
    /// Reasoning streamed before the process died (#4.15) — the server
    /// transcript filters `_thinking`, so this copy is the only survivor.
    let partialReasoning: String?
}
