import Foundation

/// #306 constraint C1: the composer names the DOOR a mid-turn commit goes
/// through, from day one. v1 implemented `.queued` only; #357's 3C app half
/// (2026-08-17) filled in `.steered` and `.interrupted` exactly as C1
/// intended — no Bool was rewritten into an enum. If a future lane finds
/// itself deleting this enum, constraint C1 failed and the #306 routing
/// verdict was wrong — say so in writing.
///
/// Wording rule (bar 306-J): the word "sent" — any form of it — never
/// appears for a message that has not been posted.
enum ComposerDoor: String, CaseIterable, Hashable, Sendable {
    /// #306 v1: the app-held queue — fires exactly once, after a turn that
    /// actually completed.
    case queued
    /// #357 (3C): mid-turn steering on the runs plane — submit is
    /// `ChatStore.steerActiveTurn`; `run.steered` alone renders applied.
    case steered
    /// #357 (3C): interrupt-and-resend — honest because Stop is a real host
    /// interrupt (`POST /v1/runs/{id}/stop`, #304);
    /// `ChatStore.interruptActiveTurnAndResend` owns the ordering.
    case interrupted

    /// The chip's door name.
    var displayName: String {
        switch self {
        case .queued: "QUEUED"
        case .steered: "STEERED"
        case .interrupted: "INTERRUPTED"
        }
    }

    /// One-line status while the committed message waits on the running turn.
    var waitingStatusLine: String {
        switch self {
        case .queued: "Waiting for this turn to finish"
        case .steered: "Steering the running turn"
        case .interrupted: "Interrupting the running turn"
        }
    }

    /// The chip's status once the turn it waited on produced no answer —
    /// the #180 visible-degradation rule. The chip then offers
    /// Send now / Edit / Discard, and NOTHING auto-fires.
    static let surfacedStatusLine = "The turn this was waiting on didn't produce an answer"

    /// #357-E/I: which doors the EXPLICIT affordance (the commit control's
    /// menu) offers for the running turn — feasibility only; the plain
    /// send's default lives in `resolvePlainSend`.
    /// - Row 3 (stream lost, run live) offers QUEUE only: the run is
    ///   unreachable for steering, and an interrupt's resend would fire
    ///   into a live `pendingRun` (#306/#307).
    /// - Steer needs a live run id and is depth-1; queue is depth-1 via the
    ///   #306 hold slot.
    static func explicitDoors(
        streamLostRunLive: Bool,
        runIDAvailable: Bool,
        steerAttemptOutstanding: Bool,
        holdSlotFree: Bool
    ) -> [ComposerDoor] {
        if streamLostRunLive { return holdSlotFree ? [.queued] : [] }
        var doors: [ComposerDoor] = []
        if holdSlotFree { doors.append(.queued) }
        if runIDAvailable && !steerAttemptOutstanding { doors.append(.steered) }
        doors.append(.interrupted)
        return doors
    }
}

/// #357-E/G/H: the control-free status strip for a live steer or interrupt
/// attempt — the door name and the honesty state, nothing else. No Edit, no
/// Cancel: a steer that has reached the host can be neither reworked nor
/// recalled, so the chip only reports. A chip, never a transcript row
/// (#282/identity ruling). Renders alongside the queued-turn chip when both
/// exist (steer outstanding + a second send held).
struct DoorStatusChipModel: Equatable {
    enum State: Equatable {
        /// Submitted — the HTTP ACK. Must never read as applied (357-G).
        case steering
        /// `run.steered` seen on the events stream — THE applied signal.
        case steered
        /// The interrupt door: stop issued, the text about to post as a
        /// fresh turn (357-H).
        case interrupting
    }

    let text: String
    let state: State

    var doorName: String {
        switch state {
        case .steering, .steered: ComposerDoor.steered.displayName
        case .interrupting: ComposerDoor.interrupted.displayName
        }
    }

    var statusLine: String {
        switch state {
        case .steering: ComposerDoor.steered.waitingStatusLine
        case .steered: "Applied to the running turn"
        case .interrupting: "Stopped — sending as a new message"
        }
    }
}

/// What the composer renders for a held message: the chip's view model,
/// derived from `ChatStore.currentThreadHeldTurn` (#306 — chip, not a
/// transcript bubble; the identity ruling and #282 both forbid a row).
struct QueuedTurnChipModel: Equatable {
    let text: String
    let door: ComposerDoor
    let isSurfaced: Bool

    var statusLine: String {
        isSurfaced ? ComposerDoor.surfacedStatusLine : door.waitingStatusLine
    }
}
