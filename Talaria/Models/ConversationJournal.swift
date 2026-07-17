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
        /// Birth host (Lane M / #114): the backend profile this hop's server
        /// session was created on — immutable, since session ids are
        /// server-scoped. Every send/fetch on the hop must resolve the base
        /// URL from it, not from the active profile. Nil on hops recorded
        /// before profiles existed (all of which belong to the migrated
        /// profile) and in profile-less test constructions.
        var profileID: UUID?

        init(
            apiSessionId: String,
            seenEntryCount: Int,
            primingUsage: TokenUsage? = nil,
            profileID: UUID? = nil
        ) {
            self.apiSessionId = apiSessionId
            self.seenEntryCount = seenEntryCount
            self.primingUsage = primingUsage
            self.profileID = profileID
        }

        private enum CodingKeys: String, CodingKey {
            case apiSessionId
            case seenEntryCount
            case primingUsage
            case profileID
        }

        /// Hand-written so pre-Lane-M persisted hops (no profileID key)
        /// decode to nil instead of failing — a decode failure here would
        /// silently drop the journal at launch.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            apiSessionId = try container.decode(String.self, forKey: .apiSessionId)
            seenEntryCount = try container.decodeIfPresent(Int.self, forKey: .seenEntryCount) ?? 0
            primingUsage = try container.decodeIfPresent(TokenUsage.self, forKey: .primingUsage)
            profileID = try container.decodeIfPresent(UUID.self, forKey: .profileID)
        }
    }

    /// The conversation's identity. Local, durable, and independent of any
    /// server session id.
    let conversationID: UUID
    var entries: [Entry]
    var activeHop: ServerHop?
    /// List hygiene (#97): pinned/archived state for THIS conversation. Rides
    /// the journal because the journal owns the conversation's durable
    /// identity — a flag keyed to the ephemeral per-hop server-session id
    /// would silently die on the next hop. Server-session ROWS carry their
    /// own overlay (`ConversationListState`); these flags are the
    /// conversation-identity copy.
    var isPinned: Bool
    var isArchived: Bool

    init(
        conversationID: UUID = UUID(),
        entries: [Entry] = [],
        activeHop: ServerHop? = nil,
        isPinned: Bool = false,
        isArchived: Bool = false
    ) {
        self.conversationID = conversationID
        self.entries = entries
        self.activeHop = activeHop
        self.isPinned = isPinned
        self.isArchived = isArchived
    }

    private enum CodingKeys: String, CodingKey {
        case conversationID
        case entries
        case activeHop
        case isPinned
        case isArchived
    }

    /// Hand-written so pre-#97 persisted journals (no pin/archive keys)
    /// migrate to `false`/`false` instead of failing to decode — a decode
    /// failure here reads as a missing journal at launch and would silently
    /// drop the conversation's durable record.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        conversationID = try container.decode(UUID.self, forKey: .conversationID)
        entries = try container.decodeIfPresent([Entry].self, forKey: .entries) ?? []
        activeHop = try container.decodeIfPresent(ServerHop.self, forKey: .activeHop)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }

    /// Whether the active hop's server session already has context for every
    /// journal entry. False when there is no hop at all — the next Hermes
    /// turn must create one (and transplant if the journal has history).
    var activeHopIsCurrent: Bool {
        guard let activeHop else { return false }
        return activeHop.seenEntryCount >= entries.count
    }
}
