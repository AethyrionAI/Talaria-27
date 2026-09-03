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

    // MARK: - Note CRUD (#422 Task 11 — the explicit "Remember that…" path)
    //
    // Every note that reaches here already arrived VERBATIM — captured by
    // `ExplicitMemoryIntent.parse`, never re-worded here or anywhere else
    // (ruling 1). This store's job is only to keep, resolve, edit and forget
    // rows; it never authors or corrects their text.

    /// Saves a new explicit note. Returns the new row's id so the caller can
    /// stamp `Message.memoryProvenance` and, on Undo, remove the same row.
    @discardableResult
    func insertNote(_ text: String, sourceMessageID: UUID?, sourceSessionID: UUID?) -> UUID {
        let id = UUID()
        context.insert(MemoryNoteRecord(
            noteID: id, text: text, createdAt: Date(),
            sourceMessageID: sourceMessageID, sourceSessionID: sourceSessionID))
        save()
        return id
    }

    /// Removes a note — the explicit-note path's own undo (a `/undo` on the
    /// turn that saved it) and the Memory screen's delete row alike. A no-op
    /// when the row is already gone.
    func deleteNote(_ noteID: UUID) {
        let id = noteID
        guard let row = fetch(FetchDescriptor<MemoryNoteRecord>(
            predicate: #Predicate { $0.noteID == id }), op: "deleteNote").first else { return }
        context.delete(row)
        save()
    }

    /// Edits a note's text in place. `createdAt` is untouched; `editedAt` is
    /// stamped so the Memory screen can show it was edited. The caller
    /// supplies the user's own new words verbatim — this is a store write,
    /// never a rewording (ruling 1). A no-op when the row is gone.
    func updateNote(_ noteID: UUID, text: String) {
        let id = noteID
        guard let row = fetch(FetchDescriptor<MemoryNoteRecord>(
            predicate: #Predicate { $0.noteID == id }), op: "updateNote").first else { return }
        row.text = text
        row.editedAt = Date()
        save()
    }

    /// Every explicit note, newest first — the Memory screen's list and the
    /// notes-block composer's source (`MemoryBudget.composeNotesBlock`, which
    /// owns the newest-first ordering the caller must supply).
    func allNotes() -> [(noteID: UUID, text: String, createdAt: Date, editedAt: Date?)] {
        fetch(FetchDescriptor<MemoryNoteRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]), op: "allNotes")
            .map { (noteID: $0.noteID, text: $0.text, createdAt: $0.createdAt, editedAt: $0.editedAt) }
    }

    /// The explicit note behind a provenance `noteID`, or `nil` when the row
    /// no longer exists (#422 ruling 2 — a resolvable source, or an honest
    /// absence; never a placeholder invented here). Same shape independently
    /// added by lane M4's provenance chip (task 15's `note(id:)`, read-only,
    /// through the same `fetch(_:op:)`) — the two are expected to unify into
    /// one definition when the lanes merge.
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
