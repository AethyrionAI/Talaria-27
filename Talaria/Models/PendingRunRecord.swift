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
    /// #430: the backend profile this run was SENT under — the host that
    /// actually has it. **Identity only: a profile UUID, never a base URL and
    /// never a key**, so a record read off disk cannot widen the credential
    /// surface even by accident.
    ///
    /// Without it, recovery asked `readRunStatus(runID:profileID: nil)`, and
    /// nil resolves to whichever profile is ACTIVE at relaunch. On a
    /// multi-profile phone that is routinely a host which has never heard of
    /// this run: it answers 404, and a 404 is classified `.gone` — a real
    /// answer destroyed as "the host forgot it".
    ///
    /// Optional because every record written before this build carries no
    /// such key. Those decode `nil` and recovery falls back to the session's
    /// BIRTH profile (`SessionProfileIndexStore`), then to the active one.
    /// A non-optional field would fail the whole decode instead, and a failed
    /// decode of this record presents downstream as "there was no pending run
    /// at all" — the #42 shape.
    let profileID: UUID?
}
