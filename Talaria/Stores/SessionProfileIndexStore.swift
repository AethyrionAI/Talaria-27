import Foundation

/// Owns the on-device session→birth-profile index (Lane M / M-1), following
/// the `ConversationListStateStore` pattern: every mutation persists via
/// `didSet`. One instance, wired by AppContainer, written by the Sessions
/// client (hop creation / session adoption / list fetches) and read by the
/// routing layer to resolve which host a session id lives on.
@MainActor
@Observable
final class SessionProfileIndexStore {
    private let persistence: any AppPersistenceStoreProtocol
    private(set) var index: SessionProfileIndex {
        didSet { persistence.saveSessionProfileIndex(index) }
    }

    init(persistence: any AppPersistenceStoreProtocol) {
        self.persistence = persistence
        self.index = persistence.loadSessionProfileIndex()
    }

    /// The profile a session was born on, when recorded. Unrecorded ids are
    /// pre-Lane-M sessions — callers fall back to the migrated/active profile.
    func profileID(forSessionID sessionID: String) -> UUID? {
        index.profileID(forSessionID: sessionID)
    }

    /// Records a session's birth profile. First write wins — the binding is
    /// immutable (session ids are server-scoped), so a later record for a
    /// known id is ignored rather than allowed to rebind the session.
    func record(sessionID: String, profileID: UUID) {
        guard !sessionID.isEmpty, index.profileID(forSessionID: sessionID) == nil else { return }
        var updated = index
        updated.record(sessionID: sessionID, profileID: profileID)
        index = updated
    }

    /// Drops entries for sessions absent from `sessionIDs` — only safe with a
    /// set assembled from ALL profiles' list fetches.
    func prune(keeping sessionIDs: Set<String>) {
        var updated = index
        updated.prune(keeping: sessionIDs)
        guard updated != index else { return }
        index = updated
    }

    func reset() {
        index = SessionProfileIndex()
        persistence.clearSessionProfileIndex()
    }
}
