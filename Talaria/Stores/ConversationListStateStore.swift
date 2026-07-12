import Foundation

/// Owns the on-device pin/archive overlay for server-session rows (#97),
/// following the InboxStore local-state pattern: every mutation persists via
/// `didSet`. One instance, wired by AppContainer, shared by the sessions
/// drawer and the conversation search screen.
@MainActor
@Observable
final class ConversationListStateStore {
    private let persistence: any AppPersistenceStoreProtocol
    private(set) var state: ConversationListState {
        didSet { persistence.saveConversationListState(state) }
    }

    init(persistence: any AppPersistenceStoreProtocol) {
        self.persistence = persistence
        self.state = persistence.loadConversationListState()
    }

    func isPinned(_ sessionID: String) -> Bool {
        state.pinnedSessionIDs.contains(sessionID)
    }

    func isArchived(_ sessionID: String) -> Bool {
        state.archivedSessionIDs.contains(sessionID)
    }

    /// Deliberately NO pin cap (ChatGPT caps at 3 — we don't, #97).
    func setPinned(_ pinned: Bool, sessionID: String) {
        guard isPinned(sessionID) != pinned else { return }
        if pinned {
            state.pinnedSessionIDs.insert(sessionID)
        } else {
            state.pinnedSessionIDs.remove(sessionID)
        }
    }

    func setArchived(_ archived: Bool, sessionID: String) {
        guard isArchived(sessionID) != archived else { return }
        if archived {
            state.archivedSessionIDs.insert(sessionID)
        } else {
            state.archivedSessionIDs.remove(sessionID)
        }
    }

    func togglePinned(sessionID: String) {
        setPinned(!isPinned(sessionID), sessionID: sessionID)
    }

    func toggleArchived(sessionID: String) {
        setArchived(!isArchived(sessionID), sessionID: sessionID)
    }
}
