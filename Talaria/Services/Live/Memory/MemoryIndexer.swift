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

    init(store: MemoryStore, makeEmbedder: @escaping () -> EmbeddingService = { EmbeddingService() }) {
        self.store = store
        self.makeEmbedder = makeEmbedder
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
    func index(_ conversation: Conversation) {
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
}
