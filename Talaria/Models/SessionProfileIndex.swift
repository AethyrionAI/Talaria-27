import Foundation

/// Birth-host record for server sessions (Lane M / M-1): which backend
/// profile each Hermes Sessions API session id was created on. Session ids
/// are SERVER-scoped — a session minted on OJAMD does not exist on the Mac
/// Mini — so the id→profile binding is immutable for the life of the session
/// and every later fetch/stream/reconcile must resolve the host from it, not
/// from whichever profile happens to be active.
///
/// Kept on-device (the server schema is not ours to change), following the
/// `ConversationListState` overlay pattern. Ids that no longer resolve to a
/// fetched session are harmless and cheap; `prune(keeping:)` lets callers
/// drop them opportunistically after a full list fetch.
struct SessionProfileIndex: Codable, Hashable, Sendable {
    var sessionProfileIDs: [String: UUID] = [:]

    func profileID(forSessionID sessionID: String) -> UUID? {
        sessionProfileIDs[sessionID]
    }

    mutating func record(sessionID: String, profileID: UUID) {
        sessionProfileIDs[sessionID] = profileID
    }

    /// Drops entries for sessions not in `keeping` — call only with a set
    /// assembled from ALL profiles' fetches; a single-host fetch would prune
    /// the other host's sessions.
    mutating func prune(keeping sessionIDs: Set<String>) {
        sessionProfileIDs = sessionProfileIDs.filter { sessionIDs.contains($0.key) }
    }
}
