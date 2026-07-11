import Foundation

/// P1 continuity fabric (OPEN_ITEMS #90): the on-device journal is the DURABLE
/// PRIMARY record of a conversation. It owns the conversation's identity — a
/// local UUID that never changes for the life of the thread — while the Hermes
/// Sessions API session id is demoted to an ephemeral, swappable per-hop
/// handle (`ServerHop`). A "brain hop" (relaunch after the server session
/// expired, a model switch, local-brain turns in between) starts a FRESH
/// server session and transplants condensed context from this journal as its
/// first turn, instead of leaning on one long-lived server session. The
/// transplant mechanism was validated by the #89 three-arm probe.
struct ConversationJournal: Codable, Hashable, Sendable {
    /// One settled conversation turn, durable and brain-agnostic: entries are
    /// recorded whether the exchange ran on Hermes, on-device, or PCC, so a
    /// transplant always carries the WHOLE conversation across a hop.
    /// Deliberately timestamp-free: entries are re-derived from the settled
    /// transcript at each sync, so any stamped time would be derivation time,
    /// not turn time — a lie the condenser doesn't need anyway.
    struct Entry: Codable, Hashable, Sendable {
        enum Role: String, Codable, Sendable {
            case user
            case assistant
        }

        let role: Role
        let text: String
    }

    /// The ephemeral server-session handle for the current hop. NOT the
    /// conversation's identity: it is created, swapped, and discarded freely;
    /// the journal (and its `conversationID`) is what persists.
    struct ServerHop: Codable, Hashable, Sendable {
        /// The Hermes Sessions API session id (e.g. "api_…") carrying turns
        /// right now.
        let apiSessionId: String
        /// Waterline: how many journal entries this hop's server session has
        /// context for — transplanted at hop creation, or exchanged through
        /// the hop since. When `entries.count` outgrows this (e.g. local-brain
        /// turns landed in between), the hop is stale and the next Hermes turn
        /// starts a fresh, re-transplanted session.
        var seenEntryCount: Int
        /// Real usage from the priming turn's `run.completed` (#46 receipts —
        /// priming is not free). Nil when the hop started on an empty journal
        /// (nothing to transplant) or the server reported no usage.
        var primingUsage: TokenUsage?
    }

    /// The conversation's identity. Local, durable, and independent of any
    /// server session id.
    let conversationID: UUID
    var entries: [Entry]
    var activeHop: ServerHop?

    init(
        conversationID: UUID = UUID(),
        entries: [Entry] = [],
        activeHop: ServerHop? = nil
    ) {
        self.conversationID = conversationID
        self.entries = entries
        self.activeHop = activeHop
    }

    /// Whether the active hop's server session already has context for every
    /// journal entry. False when there is no hop at all — the next Hermes
    /// turn must create one (and transplant if the journal has history).
    var activeHopIsCurrent: Bool {
        guard let activeHop else { return false }
        return activeHop.seenEntryCount >= entries.count
    }
}
