import Foundation

/// List hygiene for SERVER-session rows (#97): pin/archive overlays keyed by
/// the Hermes Sessions API session id. The server schema is not ours to
/// change, so this state lives entirely on-device — the sessions drawer
/// applies it on top of whatever the host returns. Ids that don't resolve to
/// a currently-fetched session are harmless (never rendered) and are kept: a
/// session can drop out of one fetch and return in the next.
struct ConversationListState: Codable, Hashable, Sendable {
    var pinnedSessionIDs: Set<String> = []
    var archivedSessionIDs: Set<String> = []
}
