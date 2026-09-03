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
    var isExcluded: Bool = false
    init(entryID: UUID, sessionID: UUID, messageID: UUID, chunkIndex: Int, text: String,
         sentAt: Date) {
        self.entryID = entryID; self.sessionID = sessionID; self.messageID = messageID
        self.chunkIndex = chunkIndex; self.text = text; self.sentAt = sentAt
    }
}

@Model final class MemoryNoteRecord {
    @Attribute(.unique) var noteID: UUID
    var text: String            // the user's words minus the trigger, verbatim
    var createdAt: Date
    var editedAt: Date?
    var sourceMessageID: UUID?
    var sourceSessionID: UUID?
    init(noteID: UUID, text: String, createdAt: Date, sourceMessageID: UUID? = nil,
         sourceSessionID: UUID? = nil) {
        self.noteID = noteID; self.text = text; self.createdAt = createdAt
        self.sourceMessageID = sourceMessageID; self.sourceSessionID = sourceSessionID
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
    private let context: ModelContext   // private context — NEVER mainContext (iOS 27 SIGTRAP)

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
                row.text = chunk.text
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
    /// re-chunking them. A message's content cannot change once
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

    /// The retrieval query surface: every row memory is allowed to draw on.
    ///
    /// Excluded rows are filtered HERE rather than downstream, and that placement is the
    /// point. A row that reaches the scorer at all can be ranked, injected and chipped, so
    /// filtering later would quietly redefine "excluded" as "hidden from the memory list"
    /// while the reply still drew on it. Exclusion is also not a delete — the row stays,
    /// because Forget everything is the only thing that erases (Owen, 09-02).
    ///
    /// Returns VALUES, not models. The scorer runs over the whole set and has no business
    /// holding live SwiftData objects: a candidate is read once, ranked, and may outlive
    /// the fetch that produced it.
    func candidates() -> [MemoryCandidate] {
        fetch(FetchDescriptor<MemoryTurnIndexRecord>(
            predicate: #Predicate { $0.isExcluded == false },
            sortBy: [SortDescriptor(\.sentAt, order: .forward)]), op: "candidates")
            .map { MemoryCandidate(entryID: $0.entryID, sessionID: $0.sessionID,
                                   chunkIndex: $0.chunkIndex, text: $0.text, sentAt: $0.sentAt) }
    }

    /// Hide a single row from retrieval, or bring it back. A no-op when the row is gone.
    func setExcluded(entryID: UUID, _ excluded: Bool) {
        let id = entryID
        guard let row = fetch(FetchDescriptor<MemoryTurnIndexRecord>(
            predicate: #Predicate { $0.entryID == id }), op: "setExcluded").first else { return }
        row.isExcluded = excluded
        save()
    }

    func indexCount() -> Int {
        (try? context.fetchCount(FetchDescriptor<MemoryTurnIndexRecord>())) ?? 0
    }

    // MARK: - Provenance lookup (#422 ruling 2)
    //
    // Resolving the ids a `MemoryProvenance` value carries back into the words
    // the user actually wrote, so the provenance sheet shows a source rather
    // than an identifier.
    //
    // Both read ONLY `text` / `sentAt` / `createdAt`. A source line quotes the
    // user's own words and says when they were said; the scoring columns are no
    // part of that question, and reading them here would tie the one surface the
    // user sees to a retrieval implementation that is still moving.
    //
    // Both return `nil` rather than a placeholder for a row that is gone.
    // Missing is a real answer — `reconcileSession` deletes the rows of a
    // message the user retried, undid or regenerated away — and the caller
    // renders it as `source deleted`. Manufacturing a stand-in row here would
    // put that decision in the store, where the view could no longer tell a
    // real memory from a hole.
    //
    // They go through `fetch(_:op:)` like every other read. A bare
    // `try? context.fetch` would make a FAILED fetch indistinguishable from a
    // deleted row, and the user-visible consequence is worse here than
    // anywhere else in this class: the sheet would say "source deleted" about
    // a memory that still exists, in the one surface ruling 2 built to be
    // trustworthy — silently, and only for the user whose store is unhappy.

    /// The indexed turn chunk behind a provenance `entryID`, or `nil` when the
    /// row no longer exists.
    func turnEntry(id: UUID) -> (text: String, sentAt: Date)? {
        let entryID = id
        var descriptor = FetchDescriptor<MemoryTurnIndexRecord>(
            predicate: #Predicate { $0.entryID == entryID })
        descriptor.fetchLimit = 1
        guard let row = fetch(descriptor, op: "turnEntry").first else { return nil }
        return (row.text, row.sentAt)
    }

    /// The explicit note behind a provenance `noteID`, or `nil` when the row no
    /// longer exists.
    func note(id: UUID) -> (text: String, createdAt: Date)? {
        let noteID = id
        var descriptor = FetchDescriptor<MemoryNoteRecord>(
            predicate: #Predicate { $0.noteID == noteID })
        descriptor.fetchLimit = 1
        guard let row = fetch(descriptor, op: "note").first else { return nil }
        return (row.text, row.createdAt)
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
