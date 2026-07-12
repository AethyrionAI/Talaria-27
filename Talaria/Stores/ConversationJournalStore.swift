import Foundation
import os

/// Owns the durable `ConversationJournal` (P1 continuity fabric, OPEN_ITEMS
/// #90): loads it at launch, persists every mutation, and keeps it in sync
/// with the settled transcript. Shared by ChatStore (which records settled
/// exchanges) and `SessionsHermesClient` (which reads/updates the hop handle
/// at send time) — one instance, wired by AppContainer.
///
/// The journal's entries are DERIVED from the settled conversation at each
/// sync point rather than appended independently, so every transcript
/// mutation path (streamed finish, interrupted-run reconcile, polling
/// fallback, per-turn regenerate/edit truncation (#44), voice transcripts)
/// self-heals into the same record — no second source of truth to drift.
@MainActor
@Observable
final class ConversationJournalStore {
    private static let logger = Logger(subsystem: "org.aethyrion.talaria", category: "ConversationJournal")

    private(set) var journal: ConversationJournal
    private let persistence: any AppPersistenceStoreProtocol

    init(persistence: any AppPersistenceStoreProtocol) {
        self.persistence = persistence
        self.journal = persistence.loadConversationJournal() ?? ConversationJournal()
    }

    var entries: [ConversationJournal.Entry] { journal.entries }
    var hasEntries: Bool { !journal.entries.isEmpty }
    var activeHop: ConversationJournal.ServerHop? { journal.activeHop }
    var activeHopIsCurrent: Bool { journal.activeHopIsCurrent }
    var isPinned: Bool { journal.isPinned }
    var isArchived: Bool { journal.isArchived }

    /// Re-derives the journal from the settled transcript. Call at the points
    /// where ChatStore persists the conversation cache.
    ///
    /// - A different `conversation.id` means a new/foreign thread (fresh chat,
    ///   pre-journal cache migration): the journal resets to that identity
    ///   with no hop, so the next Hermes turn hops fresh and transplants.
    /// - `lastExchangeViaActiveHop` bumps the hop waterline to cover the
    ///   just-settled exchange when it actually rode the active hop (a
    ///   Hermes-brain turn). Local-brain and voice turns leave the waterline
    ///   behind, which is exactly what marks the hop stale for the next
    ///   Hermes turn.
    /// - Entries can also SHRINK (#44 client-side truncation on regenerate /
    ///   edit-and-resend); the waterline clamps so the hop still reads
    ///   current — the server session keeps its history either way, matching
    ///   the documented /retry caveat.
    func sync(with conversation: Conversation, lastExchangeViaActiveHop: Bool = false) {
        let derived = Self.entries(from: conversation)

        guard journal.conversationID == conversation.id else {
            journal = ConversationJournal(conversationID: conversation.id, entries: derived)
            save()
            Self.logger.notice("journal reset to conversation \(conversation.id.uuidString.prefix(8), privacy: .public) (\(derived.count) entries, no hop)")
            return
        }

        var updated = journal
        updated.entries = derived
        if var hop = updated.activeHop {
            hop.seenEntryCount = lastExchangeViaActiveHop
                ? derived.count
                : min(hop.seenEntryCount, derived.count)
            updated.activeHop = hop
        }
        guard updated != journal else { return }
        journal = updated
        save()
    }

    /// Records a freshly created server session as the active hop.
    /// `primingUsage` carries the transplant turn's real token usage (nil when
    /// the journal was empty and no priming was sent).
    func beginHop(apiSessionId: String, primingUsage: TokenUsage?) {
        journal.activeHop = ConversationJournal.ServerHop(
            apiSessionId: apiSessionId,
            seenEntryCount: journal.entries.count,
            primingUsage: primingUsage
        )
        save()
    }

    /// Discards the active hop WITHOUT touching the journal — the handle is
    /// ephemeral by design. The next Hermes turn creates a fresh session and
    /// transplants. Used on stale-session 404s, after a model switch, and on
    /// clear.
    func endHop() {
        guard journal.activeHop != nil else { return }
        journal.activeHop = nil
        save()
    }

    /// Adopts an existing server session opened from the sessions drawer: the
    /// journal rebuilds from its history under the given conversation's
    /// identity, with the session as an already-current hop (its history IS
    /// its context — nothing to transplant).
    func adoptServerSession(id: String, conversation: Conversation) {
        let derived = Self.entries(from: conversation)
        journal = ConversationJournal(
            conversationID: conversation.id,
            entries: derived,
            activeHop: ConversationJournal.ServerHop(
                apiSessionId: id,
                seenEntryCount: derived.count,
                primingUsage: nil
            )
        )
        save()
        Self.logger.notice("journal adopted server session (\(derived.count) entries)")
    }

    /// List hygiene (#97): pin/unpin the local conversation. Persists with
    /// the journal, so the flag survives relaunches AND hop swaps (server
    /// session ids are ephemeral per #93 — this is the durable copy).
    func setPinned(_ pinned: Bool) {
        guard journal.isPinned != pinned else { return }
        journal.isPinned = pinned
        save()
    }

    /// List hygiene (#97): archive/unarchive the local conversation. Same
    /// durability contract as `setPinned`.
    func setArchived(_ archived: Bool) {
        guard journal.isArchived != archived else { return }
        journal.isArchived = archived
        save()
    }

    /// Full reset (sign-out / ChatStore.reset()).
    func reset() {
        journal = ConversationJournal()
        persistence.clearConversationJournal()
    }

    /// Maps the settled transcript onto journal entries, reusing the local
    /// brain's turn extraction (#26) so both surfaces agree on what counts as
    /// conversation content: delivered user/Hermes messages including voice
    /// turns; system banners (incl. context-priming notices), failed and
    /// in-flight sends, and streaming placeholders are skipped.
    nonisolated static func entries(from conversation: Conversation) -> [ConversationJournal.Entry] {
        LocalChatBackend.transcriptTurns(from: conversation.messages).map { turn in
            ConversationJournal.Entry(
                role: turn.role == .user ? .user : .assistant,
                text: turn.text
            )
        }
    }

    private func save() {
        persistence.saveConversationJournal(journal)
    }
}
