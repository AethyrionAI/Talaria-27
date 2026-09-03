import Foundation

/// #422 (bar 422-B): turns a settled conversation's USER-AUTHORED rows into
/// verbatim chunks in the local memory store.
///
/// Ruling 1 made structural: nothing here authors text. The chunker splits on
/// sentence boundaries — the words that land in a row are the words the user
/// sent. No model session is constructed anywhere in this module, and the grep
/// that proves it must find nothing, so the forbidden type names are not spelled
/// here either — a comment naming them would trip the very pin it was written to
/// describe.
@MainActor
final class MemoryIndexer {
    private let store: MemoryStore

    /// The memory master switch, read on EVERY call rather than captured at
    /// construction. The indexer is built once on the launch path and lives for
    /// the process, so a construction-time `Bool` would leave a mid-session
    /// flip inert until the next cold start — the user switches memory off,
    /// keeps typing, and every turn is still remembered. Owen's 09-02 ruling
    /// covers indexing as well as retrieval, and this is the indexing half.
    private let isEnabled: () -> Bool

    init(store: MemoryStore, isEnabled: @escaping () -> Bool = { true }) {
        self.store = store
        self.isEnabled = isEnabled
    }

    /// Indexes the user-authored turns of a LOCAL-ORIGIN conversation.
    ///
    /// Local origin is the CALLER's guarantee — ChatStore's store-membership
    /// rule (#190B), which is origin-based and durable. This class never looks
    /// at `brain` stamps: a per-message stamp scan is exactly the rule #190B
    /// replaced, because a paired-mode thread the brain flipped under
    /// mid-conversation would leak host turns into a store ruling 3 says can
    /// never hold one.
    ///
    /// Two exclusions, and they are different questions:
    /// - `isUserAuthored` (#275) — typed AND dictated. Owen's 09-02 rulings:
    ///   assistant turns are out of the corpus, voice turns are in. Going
    ///   through the predicate rather than `== .user || == .voiceUser` is the
    ///   repo's standing rule: a sixth sender case then has to answer this
    ///   question explicitly instead of being silently excluded here.
    /// - `isContextPriming` (#90) — a transplant notice is `.user`-sendered by
    ///   construction and is a wall of RE-PRIMED history, not something the
    ///   user typed at this moment. Indexing it would re-file whole past
    ///   threads as fresh memories, at their transplant timestamp.
    ///
    /// INCREMENTAL, and that is load-bearing rather than an optimisation. The
    /// seam hands the WHOLE conversation over on every settle, so re-chunking
    /// all of it would make a thread's own history cost more on every turn —
    /// quadratic work, synchronous, on the MainActor, on the path the user is
    /// waiting on. One `reconcileSession` fetch names the messages already
    /// stored and only the rest are chunked.
    ///
    /// The same call deletes the rows whose message has LEFT the conversation
    /// (`retryMessage`, `/undo`, `regenerateReply`), which is ruling 2's
    /// requirement that every stored row keep a resolvable source.
    ///
    /// A row is text and nothing else. Memory off returns before ANY of it: no
    /// fetch and no row. The switch is not an eraser, so nothing already stored
    /// is touched; Forget everything is the only thing that deletes (Owen,
    /// 09-02).
    ///
    /// One accepted consequence of returning this early: the RECONCILE does not
    /// run either, so rows whose message the user retried or undid while memory
    /// was off are not reaped at that moment. They are reaped on the first
    /// settle after it goes back ON — the reconcile is per-session and reads the
    /// live message set, so it self-heals rather than needing a catch-up pass.
    func index(_ conversation: Conversation) {
        guard isEnabled() else { return }
        let alreadyIndexed = store.reconcileSession(
            conversation.id, liveMessageIDs: Set(conversation.messages.map(\.id)))
        var rows: [MemoryTurnIndexRecord] = []
        for message in conversation.messages
        where message.sender.isUserAuthored && !message.isContextPriming
            && !alreadyIndexed.contains(message.id) {
            for (i, chunk) in MemoryChunker.chunk(message.content).enumerated() {
                rows.append(MemoryTurnIndexRecord(
                    entryID: UUID(),
                    sessionID: conversation.id,
                    messageID: message.id,
                    chunkIndex: i,
                    text: chunk,
                    sentAt: message.timestamp
                ))
            }
        }
        store.upsertTurnChunks(rows)
    }

    /// The launch backfill: indexes stored sessions the settle seam never saw —
    /// everything the user said before this feature existed.
    ///
    /// **Resumable by construction.** `cursor` is an index into `conversations`
    /// and advances after each one, so a pass the OS cuts short (the user
    /// leaves the app; the process is suspended) resumes at the next
    /// conversation instead of restarting. `budget` caps how many are processed
    /// in one call — the caller's way of keeping a long history off the main
    /// thread in one unbroken block, and the seam a test uses to kill a pass
    /// part-way. Re-running over already-indexed history is a no-op, not a
    /// duplicate (bar 422-A's upsert idempotence), so a stale cursor costs work
    /// and nothing else.
    ///
    /// The caller owns the cursor's PERSISTENCE (`UserSettings
    /// .memoryBackfillCursor`) and the order of `conversations`. Oldest-first is
    /// what makes the cursor meaningful across launches: a session created
    /// since the last pass appends, rather than shifting unread history behind
    /// the cursor.
    func backfill(_ conversations: [Conversation], cursor: inout Int, budget: Int = .max) {
        guard isEnabled() else { return }
        cursor = max(0, cursor)
        var processed = 0
        while cursor < conversations.count, processed < budget {
            index(conversations[cursor])
            cursor += 1
            processed += 1
        }
    }
}
