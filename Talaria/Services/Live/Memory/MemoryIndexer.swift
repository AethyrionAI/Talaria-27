import Foundation

/// #422 (bar 422-B): turns a settled conversation's USER-AUTHORED rows into
/// verbatim chunks in the local memory store.
///
/// Ruling 1 made structural: nothing here authors text. The chunker splits on
/// sentence boundaries and the embedder only scores — the words that land in a
/// row are the words the user sent. No model session is constructed anywhere in
/// this module, and the grep that proves it must find nothing, so the forbidden
/// type names are not spelled here either — a comment naming them would trip the
/// very pin it was written to describe.
@MainActor
final class MemoryIndexer {
    private let store: MemoryStore
    private let makeEmbedder: () -> EmbeddingService

    /// LAZY on purpose. `EmbeddingService.init` makes up to two
    /// `NLEmbedding.sentenceEmbedding(for:)` lookups, and the indexer is
    /// constructed on the LAUNCH path (AppContainer) while it is first used on
    /// a settle — so an eager embedder charges every launch for work no launch
    /// needs. The factory is injected so a test can hand over a pre-made
    /// instance and then read its counters.
    private lazy var embedder: EmbeddingService = makeEmbedder()

    /// The memory master switch, read on EVERY call rather than captured at
    /// construction. The indexer is built once on the launch path and lives for
    /// the process, so a construction-time `Bool` would leave a mid-session
    /// flip inert until the next cold start — the user switches memory off,
    /// keeps typing, and every turn is still remembered. Owen's 09-02 ruling
    /// covers indexing as well as retrieval, and this is the indexing half.
    private let isEnabled: () -> Bool

    init(store: MemoryStore,
         makeEmbedder: @escaping () -> EmbeddingService = { EmbeddingService() },
         isEnabled: @escaping () -> Bool = { true }) {
        self.store = store
        self.makeEmbedder = makeEmbedder
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
    /// seam hands the WHOLE conversation over on every settle, so re-chunking and
    /// re-embedding all of it would make a thread's own history cost more on
    /// every turn — quadratic work, synchronous, on the MainActor, on the path
    /// the user is waiting on. One `reconcileSession` fetch names the messages
    /// already stored and only the rest are embedded.
    ///
    /// The same call deletes the rows whose message has LEFT the conversation
    /// (`retryMessage`, `/undo`, `regenerateReply`), which is ruling 2's
    /// requirement that every stored row keep a resolvable source.
    ///
    /// A turn whose embedding is not available yet keeps its row with an EMPTY
    /// vector — the verbatim text IS the memory, and retrieval scores such a row
    /// lexically. Blocking or retrying here would stall the settle seam.
    /// Memory off returns before ANY of that: no fetch, no row, and — because
    /// the embedder is lazy — no `NLEmbedding` asset lookup either. The switch
    /// is not an eraser, so nothing already stored is touched; Forget
    /// everything is the only thing that deletes (Owen, 09-02).
    func index(_ conversation: Conversation) {
        guard isEnabled() else { return }
        let alreadyIndexed = store.reconcileSession(
            conversation.id, liveMessageIDs: Set(conversation.messages.map(\.id)))
        var rows: [MemoryTurnIndexRecord] = []
        for message in conversation.messages
        where message.sender.isUserAuthored && !message.isContextPriming
            && !alreadyIndexed.contains(message.id) {
            for (i, chunk) in MemoryChunker.chunk(message.content).enumerated() {
                let vector = embedder.embed(chunk).map(EmbeddingService.encode) ?? Data()
                rows.append(MemoryTurnIndexRecord(
                    entryID: UUID(),
                    sessionID: conversation.id,
                    messageID: message.id,
                    chunkIndex: i,
                    text: chunk,
                    sentAt: message.timestamp,
                    embedderID: EmbeddingService.embedderID,
                    vector: vector
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
        // Only once the pass has reached the end, so a windowed caller does not
        // re-scan the store for stranded rows on every window.
        if cursor >= conversations.count { reEmbedStrandedRows() }
    }

    /// Repairs rows that were stored WITHOUT a vector.
    ///
    /// `index` is incremental — an already-indexed message is never revisited —
    /// so a turn taken while the embedder had not yet acquired its asset keeps
    /// an empty vector forever, scored lexically for the life of the install
    /// because of a condition that lasted seconds. This is the only path that
    /// looks at such a row again.
    ///
    /// Bounded on purpose: it runs on the launch path, so it takes a slice and
    /// leaves the rest to the next pass. A row whose text the embedder simply
    /// cannot vectorise is skipped and retried later — cheap, and self-limiting
    /// at this cap — but a MISSING embedder stops the pass outright, because
    /// every remaining row would fail the same way.
    private func reEmbedStrandedRows(limit: Int = 200) {
        let stranded = store.entriesWithEmptyVector(limit: limit)
        guard !stranded.isEmpty else { return }   // …so no embedder is built for an empty queue
        for row in stranded {
            guard let vector = embedder.embed(row.text) else {
                if !embedder.isAvailable { return }
                continue
            }
            store.updateVector(entryID: row.entryID,
                               vector: EmbeddingService.encode(vector),
                               embedderID: EmbeddingService.embedderID)
        }
    }
}
