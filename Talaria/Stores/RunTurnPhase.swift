import Foundation

// Phase 3 slice 3C (#357 bars 357-E/F/I): the turn-phase state the composer's
// three doors key on, and the door resolver for a plain mid-turn send.
// Design of record: PHASE3-RUNS-MIGRATION-PLAN §2.5/§2.6 as modified by
// #357's wire facts (the ACK is submit-only; `run.steered` is the applied
// signal; `pending_steer` makes a missed steer land honestly as the next
// message — which is what makes a steer-preference send safe in ANY phase).

/// #357-F: derived purely from the stream events ChatStore already decodes.
/// Tools run serially (the `.toolActivity` handler's own rule), so
/// tool-in-flight is a bool, not a count; a prose delta ends it (matching
/// `.textDelta`'s deactivate-tools semantics); reasoning is a SEPARATE
/// channel and must not — `_thinking` flows during tool execution.
struct RunTurnPhaseTracker: Equatable {
    enum Phase: Equatable {
        /// Between send and the first stream signal.
        case awaitingFirstSignal
        /// A `tool.started` with no matching `tool.completed` — the steer
        /// window is open (§2.5).
        case toolInFlight
        /// Prose is flowing (or the last tool completed) — a steer fired
        /// here degrades to `pending_steer` (357-G).
        case prose
    }

    private(set) var phase: Phase = .awaitingFirstSignal

    mutating func noteToolStarted() { phase = .toolInFlight }
    mutating func noteToolCompleted() { phase = .prose }
    mutating func noteProseDelta() { phase = .prose }
    mutating func noteReasoningDelta() {}
}

/// #357-E: Owen's setting — what a plain mid-turn send does. Raw values are
/// persisted in the `hermes.userSettings` blob; never rename.
enum MidTurnSendAction: String, Codable, CaseIterable, Sendable {
    case queue
    case steer
}

extension ComposerDoor {
    /// #357-E/I: the plain mid-turn send's door, the whole policy in one
    /// pure function. Resolves only between `.queued` and `.steered` —
    /// `.interrupted` is always an explicit user choice, never a plain
    /// send's resolution.
    /// - Row 3 (stream lost, run live) is QUEUE only — the run is
    ///   unreachable for steering and firing is #307's corruption.
    /// - The steer preference needs a live run id and takes depth-1: while
    ///   one steer attempt is unresolved, the next send queues.
    static func resolvePlainSend(
        setting: MidTurnSendAction,
        streamLostRunLive: Bool,
        runIDAvailable: Bool,
        steerAttemptOutstanding: Bool
    ) -> ComposerDoor {
        if streamLostRunLive { return .queued }
        switch setting {
        case .queue:
            return .queued
        case .steer:
            guard runIDAvailable, !steerAttemptOutstanding else { return .queued }
            return .steered
        }
    }
}
