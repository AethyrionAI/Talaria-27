import Foundation

/// Owns the on-device session→last-run-usage index (#25), following the
/// `SessionProfileIndexStore` pattern: every mutation persists via `didSet`.
/// One instance, wired by AppContainer; written by the Sessions client
/// whenever a `run.completed` delivers usage (live turns and priming turns
/// alike) and read back when a stored session is resumed — the CTX gauge's
/// only honest numerator for resumed sessions.
@MainActor
@Observable
final class SessionUsageIndexStore {
    private let persistence: any AppPersistenceStoreProtocol
    private(set) var index: SessionUsageIndex {
        didSet { persistence.saveSessionUsageIndex(index) }
    }

    init(persistence: any AppPersistenceStoreProtocol) {
        self.persistence = persistence
        self.index = persistence.loadSessionUsageIndex()
    }

    /// The session's last recorded run usage, when any live run's
    /// `run.completed` has been observed for it. Nil = honestly unknown —
    /// callers must surface absence, never substitute 0.
    func usage(forSessionID sessionID: String) -> TokenUsage? {
        index.usage(forSessionID: sessionID)
    }

    /// Records a run's usage. Last write wins — unlike the birth-profile
    /// binding, a session's latest run usage legitimately changes every turn.
    func record(sessionID: String, usage: TokenUsage) {
        guard !sessionID.isEmpty else { return }
        var updated = index
        updated.record(sessionID: sessionID, usage: usage)
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
        index = SessionUsageIndex()
        persistence.clearSessionUsageIndex()
    }
}
