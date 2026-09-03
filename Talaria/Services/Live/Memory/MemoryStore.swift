import Foundation
import SwiftData
import os

@Model final class MemoryTurnIndexRecord {
    @Attribute(.unique) var entryID: UUID
    var sessionID: UUID
    var messageID: UUID
    var chunkIndex: Int
    var text: String            // verbatim chunk — never paraphrased (ruling 1)
    var sentAt: Date
    var embedderID: String      // rows with a foreign embedderID are never scored (422-C)
    var vector: Data            // 512 × Float32 little-endian
    var isExcluded: Bool = false
    init(entryID: UUID, sessionID: UUID, messageID: UUID, chunkIndex: Int, text: String,
         sentAt: Date, embedderID: String, vector: Data) {
        self.entryID = entryID; self.sessionID = sessionID; self.messageID = messageID
        self.chunkIndex = chunkIndex; self.text = text; self.sentAt = sentAt
        self.embedderID = embedderID; self.vector = vector
    }
}

@Model final class MemoryNoteRecord {
    @Attribute(.unique) var noteID: UUID
    var text: String            // the user's words minus the trigger, verbatim
    var createdAt: Date
    var editedAt: Date?
    var sourceMessageID: UUID?
    var sourceSessionID: UUID?
    var embedderID: String
    var vector: Data
    init(noteID: UUID, text: String, createdAt: Date, sourceMessageID: UUID? = nil,
         sourceSessionID: UUID? = nil, embedderID: String, vector: Data) {
        self.noteID = noteID; self.text = text; self.createdAt = createdAt
        self.sourceMessageID = sourceMessageID; self.sourceSessionID = sourceSessionID
        self.embedderID = embedderID; self.vector = vector
    }
}

@Model final class MemoryUseRecord {
    @Attribute(.unique) var replyMessageID: UUID
    var store: String           // "local" only in the minimal shape; "host" exists for the fuller one
    var entryIDs: [UUID]
    var noteIDs: [UUID]
    var at: Date
    init(replyMessageID: UUID, store: String, entryIDs: [UUID], noteIDs: [UUID], at: Date) {
        self.replyMessageID = replyMessageID; self.store = store
        self.entryIDs = entryIDs; self.noteIDs = noteIDs; self.at = at
    }
}

/// The local memory store — a SEPARATE container from `TalariaLocalSessions`
/// (#422 ruling 3 made structural: no host row can ever live here).
@MainActor
final class MemoryStore {
    private static let logger = Logger(subsystem: "org.aethyrion.talaria", category: "MemoryStore")
    private let container: ModelContainer
    /// The private context — NEVER `mainContext` (iOS 27 SIGTRAP).
    ///
    /// Internal rather than `private` only because Swift's `private` is
    /// FILE-scoped and `MemoryStore+Lookup.swift` is a separate file (kept
    /// separate so the provenance lookup does not sit in the way of this
    /// file's schema edits). Treat it as private: everything outside this
    /// class goes through a named method.
    // lookup-visible
    let context: ModelContext

    private init(container: ModelContainer) {
        self.container = container
        self.context = ModelContext(container)
    }

    static func make(inMemoryOnly: Bool = false) -> MemoryStore? {
        do {
            let schema = Schema([MemoryTurnIndexRecord.self, MemoryNoteRecord.self, MemoryUseRecord.self])
            let configuration = ModelConfiguration(
                "TalariaMemory", schema: schema, isStoredInMemoryOnly: inMemoryOnly,
                allowsSave: true, groupContainer: .none, cloudKitDatabase: .none)
            return MemoryStore(container: try ModelContainer(for: schema, configurations: [configuration]))
        } catch {
            logger.error("TalariaMemory container failed — memory disabled: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Insert-or-update keyed on `messageID × chunkIndex`, in ONE fetch.
    ///
    /// It used to be one predicate fetch PER CHUNK, which put a round trip on
    /// every sentence of every turn — paid on the settle seam the user is
    /// waiting on, and again for every conversation of the launch backfill. One
    /// fetch over the batch's message ids answers the same question.
    ///
    /// The in-memory index also makes the batch dedup itself: two chunks sharing
    /// a key now resolve against each other rather than against whatever a fetch
    /// does or does not see of an unsaved insert.
    func upsertTurnChunks(_ chunks: [MemoryTurnIndexRecord]) {
        guard !chunks.isEmpty else { return }
        let messageIDs = Array(Set(chunks.map(\.messageID)))
        let existing = fetch(FetchDescriptor<MemoryTurnIndexRecord>(
            predicate: #Predicate { messageIDs.contains($0.messageID) }), op: "upsertTurnChunks")

        struct ChunkKey: Hashable { let messageID: UUID; let chunkIndex: Int }
        var byKey = Dictionary(
            existing.map { (ChunkKey(messageID: $0.messageID, chunkIndex: $0.chunkIndex), $0) },
            uniquingKeysWith: { first, _ in first })

        for chunk in chunks {
            let key = ChunkKey(messageID: chunk.messageID, chunkIndex: chunk.chunkIndex)
            if let row = byKey[key] {
                row.text = chunk.text; row.vector = chunk.vector; row.embedderID = chunk.embedderID
            } else {
                context.insert(chunk)
                byKey[key] = chunk
            }
        }
        save()
    }

    /// The per-settle reconcile: ONE fetch and at most one save, answering both
    /// questions the indexer has about a session.
    ///
    /// **Deletes** the rows whose `messageID` is no longer in `liveMessageIDs`.
    /// That is ruling 2 in its negative form — every stored row must have a
    /// resolvable source, and `retryMessage` (removes a user row) and `/undo` /
    /// `regenerateReply` (truncate a range) both make a message disappear. Left
    /// alone, such a row stays retrievable forever with a provenance chip
    /// pointing at nothing.
    ///
    /// **Returns** the message ids that still have rows, so the caller can skip
    /// re-chunking and re-embedding them. A message's content cannot change once
    /// indexed — the only in-place message mutation targets priming rows, which
    /// never enter this store — so "already indexed" means "done", and the
    /// settle seam stops being quadratic over a thread's life.
    func reconcileSession(_ sessionID: UUID, liveMessageIDs: Set<UUID>) -> Set<UUID> {
        let rows = fetch(FetchDescriptor<MemoryTurnIndexRecord>(
            predicate: #Predicate { $0.sessionID == sessionID }), op: "reconcileSession")
        var indexed: Set<UUID> = []
        var deletedAny = false
        for row in rows {
            if liveMessageIDs.contains(row.messageID) {
                indexed.insert(row.messageID)
            } else {
                context.delete(row)
                deletedAny = true
            }
        }
        if deletedAny { save() }
        return indexed
    }

    func deleteSession(_ sessionID: UUID) {
        let rows = fetch(FetchDescriptor<MemoryTurnIndexRecord>(
            predicate: #Predicate { $0.sessionID == sessionID }), op: "deleteSession")
        rows.forEach(context.delete)
        save()
    }

    /// Rows that were stored WITHOUT a vector, oldest first, capped at `limit`.
    ///
    /// This is a repair QUEUE, not a query surface. `MemoryIndexer.index` is
    /// incremental — a message that already has rows is never revisited — so a
    /// turn indexed while the embedder had not yet acquired its asset would keep
    /// an empty vector for the life of the install, permanently lexical-only
    /// because of a condition that lasted seconds.
    ///
    /// **Returns the MODELS, not a snapshot**, and that is deliberate: the
    /// repair writes each row's vector back, and re-fetching every row by
    /// `entryID` to do so is one predicate fetch per row for objects the caller
    /// is already holding. The rows belong to this store's private context and
    /// this class is `@MainActor`, so they never cross an isolation boundary.
    /// Pair every mutation with one `commitVectorRepairs()`.
    ///
    /// The predicate is `vector == empty` rather than a `vector.isEmpty` test:
    /// the comparison is one SwiftData can push down to the store, so a large
    /// index is not faulted row by row (and every blob materialised) on every
    /// launch just to find the handful that need repair. Oldest first so the
    /// repair walks history in the order the user lived it.
    func emptyVectorRows(limit: Int) -> [MemoryTurnIndexRecord] {
        guard limit > 0 else { return [] }
        let empty = Data()
        var descriptor = FetchDescriptor<MemoryTurnIndexRecord>(
            predicate: #Predicate { $0.vector == empty },
            sortBy: [SortDescriptor(\.sentAt, order: .forward)])
        descriptor.fetchLimit = limit
        return fetch(descriptor, op: "emptyVectorRows")
    }

    /// ONE save for a whole repair pass. Saving per row would put up to `limit`
    /// SwiftData commits on the launch path to write a few kilobytes of blobs.
    func commitVectorRepairs() { save() }

    /// The stored blob's size, so a caller can tell a repaired row from a
    /// stranded one without decoding, and by a route independent of the objects
    /// the repair itself mutated. Nil when the row is gone.
    // harness-visible
    func vectorByteCount(entryID: UUID) -> Int? {
        let id = entryID
        return fetch(FetchDescriptor<MemoryTurnIndexRecord>(
            predicate: #Predicate { $0.entryID == id }), op: "vectorByteCount").first?.vector.count
    }

    /// Every stored row's embedder id — `""` on a row that has no vector yet.
    /// Whole-store rather than by id because the claim it exists to check is
    /// about what the writer stamps, which is a property of all of them.
    // harness-visible
    func allEmbedderIDs() -> [String] {
        fetch(FetchDescriptor<MemoryTurnIndexRecord>(
            sortBy: [SortDescriptor(\.sentAt, order: .forward)]), op: "allEmbedderIDs")
            .map(\.embedderID)
    }

    func indexCount() -> Int {
        (try? context.fetchCount(FetchDescriptor<MemoryTurnIndexRecord>())) ?? 0
    }

    /// Fetch with a diagnostic. A swallowed `try?` here is not benign: a failed
    /// fetch in `upsertTurnChunks` silently DUPLICATES a row instead of updating
    /// it, and one in `deleteSession` leaves the doomed session's rows dangling —
    /// the exact invariant bar 422-A protects. Behaviour on failure is unchanged
    /// (empty result); only the silence is.
    private func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>, op: String) -> [T] {
        do {
            return try context.fetch(descriptor)
        } catch {
            Self.logger.error("memory fetch failed (\(op, privacy: .public)): \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func save() {
        do { try context.save() } catch {
            Self.logger.error("memory save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
