import Foundation

/// P1 offline compose outbox (OPEN_ITEMS #90) + the #306 mid-turn hold: ONE
/// durable store for every composed turn that is not posting right now.
///
/// Two producers, one order (#306 matrix row 5 — two stores would create two
/// competing orders that meet for the first time during a network outage):
/// - **`.unreachable` parks (#90):** turns composed while the Sessions API is
///   unreachable. The send pipeline already minted their transcript row
///   (flipped `.queued`), so they carry a `transcriptRowID` and drain on the
///   next reachability signal.
/// - **`.heldDuringTurn` holds (#306):** the next message, committed while a
///   turn was still streaming. NO transcript row exists until the fire
///   actually posts — the identity ruling: `sendMessage` mints the
///   `clientMessageID` at send time, and the entry id below is a separate,
///   durable identity. These become drain-eligible only when a terminal
///   releases them.
///
/// Text-only by design (v1, re-affirmed by #306 O5): attachments have no
/// durable wire-ready form to park here, so attachment sends still fail
/// honestly when offline — see #314 for the deferred re-examination.
struct ComposeOutboxState: Codable, Hashable, Sendable {

    /// #306 T1: why a turn is parked here — the reason discriminator that
    /// broke the old id fusion (`PendingTurn.id` used to BE the transcript
    /// row's `clientMessageID`, safe only because the row already existed).
    enum ParkReason: String, Codable, Hashable, Sendable {
        /// #90: composed while the Sessions API was unreachable. Has a
        /// transcript row; drain-eligible (`.released`) from birth.
        case unreachable
        /// #306: committed while a turn was in flight. Row-less until the
        /// fire; the #240 drain-time adoption guard must never apply to it
        /// (the text was never posted, so a server match can only be a
        /// coincidence — and would eat the message).
        case heldDuringTurn
    }

    /// #306: where a parked turn is in its life.
    enum Phase: String, Codable, Hashable, Sendable {
        /// Mid-turn hold, waiting on its turn's terminal. Chip: "QUEUED".
        case held
        /// The turn it waited on produced no answer (Stop divergence, a
        /// failed/exhausted/expired terminal, walk-away, process death).
        /// The chip says so and offers Send now / Edit / Discard — the #180
        /// visible-degradation rule. NEVER auto-fires.
        case surfaced
        /// Drain-eligible: an `.unreachable` park (from birth) or a held
        /// turn that a completed terminal released into the drain.
        case released
    }

    struct PendingTurn: Codable, Hashable, Sendable, Identifiable {
        /// Durable ENTRY id (#306 identity ruling): stable from the moment
        /// the user commits the turn, through edits and relaunch. This is
        /// NOT a transcript identity — `sendMessage` mints the row's
        /// `clientMessageID` when it posts. Two ids, two jobs.
        let id: UUID
        var reason: ParkReason
        /// The transcript row's `clientMessageID` — populated only for
        /// `.unreachable` parks, where the row already exists so the drain
        /// can replace the queued bubble with the live re-send. This is the
        /// old fused `id`, demoted to an optional (#306 T1). Nil for
        /// mid-turn holds: no row exists until the fire.
        var transcriptRowID: UUID?
        var text: String
        let composedAt: Date
        /// #306 T2 (tracker correction): the queue is held against the
        /// THREAD, not the app — the server session id where one exists,
        /// else the conversation's local UUID string. Nil = legacy entry
        /// (pre-#306 payload), treated as belonging to the current thread.
        var threadKey: String?
        var phase: Phase

        init(
            id: UUID = UUID(),
            reason: ParkReason,
            transcriptRowID: UUID? = nil,
            text: String,
            composedAt: Date = .now,
            threadKey: String? = nil,
            phase: Phase
        ) {
            self.id = id
            self.reason = reason
            self.transcriptRowID = transcriptRowID
            self.text = text
            self.composedAt = composedAt
            self.threadKey = threadKey
            self.phase = phase
        }

        /// Decode-compat (#306 T1): a pre-#306 payload carries only
        /// `{id, text, composedAt}` — the fused shape. A decode failure here
        /// silently EMPTIES a real user's outbox
        /// (`UserDefaultsAppPersistenceStore.load` returns nil on failure and
        /// the caller substitutes a default), so the legacy shape MUST
        /// decode: the fused id becomes both the entry id and the
        /// `transcriptRowID`, reason `.unreachable`, phase `.released` —
        /// exactly the semantics every pre-#306 entry actually had.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let id = try container.decode(UUID.self, forKey: .id)
            self.id = id
            self.text = try container.decode(String.self, forKey: .text)
            self.composedAt = try container.decode(Date.self, forKey: .composedAt)
            let reason = try container.decodeIfPresent(ParkReason.self, forKey: .reason) ?? .unreachable
            self.reason = reason
            self.transcriptRowID = try container.decodeIfPresent(UUID.self, forKey: .transcriptRowID)
                ?? (reason == .unreachable ? id : nil)
            self.threadKey = try container.decodeIfPresent(String.self, forKey: .threadKey)
            self.phase = try container.decodeIfPresent(Phase.self, forKey: .phase) ?? .released
        }
    }

    /// Every parked turn, oldest-first — array order IS the drain order.
    var pendingTurns: [PendingTurn] = []

    var isEmpty: Bool { pendingTurns.isEmpty }

    /// Drain-eligible entries, oldest-first.
    var releasedTurns: [PendingTurn] { pendingTurns.filter { $0.phase == .released } }

    /// Parks an `.unreachable` turn (#90). Dedupes by transcript row — the
    /// same row re-parking (a drain re-queue) must not double the entry.
    /// Returns the entry id (new or existing) so the drain's front-restore
    /// can address the entry by its own identity.
    @discardableResult
    mutating func enqueueUnreachable(
        transcriptRowID: UUID,
        text: String,
        threadKey: String? = nil,
        composedAt: Date = .now
    ) -> UUID {
        if let existing = pendingTurns.first(where: { $0.transcriptRowID == transcriptRowID }) {
            return existing.id
        }
        let turn = PendingTurn(
            reason: .unreachable,
            transcriptRowID: transcriptRowID,
            text: text,
            composedAt: composedAt,
            threadKey: threadKey,
            phase: .released
        )
        pendingTurns.append(turn)
        return turn.id
    }

    /// Holds a mid-turn composed message (#306 T2). Depth is the CALLER's
    /// rule (ChatStore enforces one per thread — O4); the store just parks.
    @discardableResult
    mutating func hold(text: String, threadKey: String?, composedAt: Date = .now) -> PendingTurn {
        let turn = PendingTurn(
            reason: .heldDuringTurn,
            text: text,
            composedAt: composedAt,
            threadKey: threadKey,
            phase: .held
        )
        pendingTurns.append(turn)
        return turn
    }

    mutating func remove(entryID: UUID) {
        pendingTurns.removeAll { $0.id == entryID }
    }

    /// Removes the entry backing a transcript row (retry's path, #90/#279).
    /// A mid-turn hold has no row, so a retry can never delete one (#306
    /// trap 8).
    mutating func removeEntry(withTranscriptRowID rowID: UUID) {
        pendingTurns.removeAll { $0.transcriptRowID == rowID }
    }

    mutating func update(_ turn: PendingTurn) {
        guard let idx = pendingTurns.firstIndex(where: { $0.id == turn.id }) else { return }
        pendingTurns[idx] = turn
    }

    /// #306 matrix rows 1 and 5: releases a held entry into the drain,
    /// moving it to the TAIL — behind every already-parked turn (for row 5,
    /// behind the turn the `.unreachable` terminal just parked), preserving
    /// oldest-first order across both producers.
    mutating func releaseToTail(entryID: UUID) {
        guard let idx = pendingTurns.firstIndex(where: { $0.id == entryID }) else { return }
        var turn = pendingTurns.remove(at: idx)
        turn.phase = .released
        pendingTurns.append(turn)
    }
}
