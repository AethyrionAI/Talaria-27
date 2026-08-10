import Foundation

/// #306 constraint C1: the composer names the DOOR a mid-turn commit goes
/// through, from day one. v1 implements `.queued` only; `.steered` and
/// `.interrupted` are slice 3C's doors — present here as cases every switch
/// must handle, so 3C FILLS THEM IN rather than rewriting a Bool into an
/// enum. If a future lane finds itself deleting this enum, constraint C1
/// failed and the #306 routing verdict was wrong — say so in writing.
///
/// Wording rule (bar 306-J): the word "sent" — any form of it — never
/// appears for a message that has not been posted.
enum ComposerDoor: String, CaseIterable, Hashable, Sendable {
    /// #306 v1: the app-held queue — fires exactly once, after a turn that
    /// actually completed.
    case queued
    /// 3C: mid-turn steering on the runs plane. Present, unimplemented —
    /// nothing constructs it in v1.
    case steered
    /// 3C: interrupt-and-resend, honest only where Stop is a real host
    /// interrupt (`POST /v1/runs/{id}/stop`). Present, unimplemented.
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
