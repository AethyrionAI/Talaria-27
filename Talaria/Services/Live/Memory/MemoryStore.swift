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
    /// #422 Task 11 fix round 1 (minor): whether `ExplicitMemoryIntent`'s
    /// 500-char cap actually cut this note. Stored at capture time — from
    /// `parseResult(_:).truncated` — rather than re-derived downstream from
    /// `text.count == 500`, per the controller's ruling: a note that
    /// happens to be exactly 500 characters long on its own is not the same
    /// fact as one the cap truncated, and Task 16's notice must be honest
    /// about which happened. `false` for every note written before this
    /// column existed (a legacy row was, by definition, never marked cut).
    ///
    /// **The `= false` is the migration, not a style choice** (Task 11's
    /// review finding, landed with Task 10). SwiftData's lightweight
    /// migration can add a new NON-OPTIONAL column only when the property
    /// carries a default; without one, opening an existing `TalariaMemory`
    /// file whose rows predate the column fails container creation — and
    /// `MemoryStore.make` turns that into "memory disabled", silently, for
    /// exactly the users who had already saved notes.
    var wasTruncated: Bool = false
    init(noteID: UUID, text: String, createdAt: Date, sourceMessageID: UUID? = nil,
         sourceSessionID: UUID? = nil, wasTruncated: Bool = false) {
        self.noteID = noteID; self.text = text; self.createdAt = createdAt
        self.sourceMessageID = sourceMessageID; self.sourceSessionID = sourceSessionID
        self.wasTruncated = wasTruncated
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
    /// `wasTruncated` should be `ExplicitMemoryIntent.parseResult(_:)`'s own
    /// `truncated` flag, captured at insert time (fix round 1 minor) — never
    /// re-derived downstream from `text.count == 500`.
    @discardableResult
    func insertNote(_ text: String, sourceMessageID: UUID?, sourceSessionID: UUID?, wasTruncated: Bool = false) -> UUID {
        let id = UUID()
        context.insert(MemoryNoteRecord(
            noteID: id, text: text, createdAt: Date(),
            sourceMessageID: sourceMessageID, sourceSessionID: sourceSessionID,
            wasTruncated: wasTruncated))
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

    /// **#422 Task 11 fix round 1 (Important, item 3).** Removes every note
    /// whose `sourceMessageID` is in `ids` — the "the row's source is gone"
    /// rule `reconcileSession` already applies to indexed turn chunks
    /// (ruling 2), extended to explicit notes. Called from BOTH
    /// `ChatStore.truncateTranscript` (Undo/regenerate's range removal) and
    /// `ChatStore.retryMessage` (which removes its single row OUTSIDE
    /// `truncateTranscript`, #279, and then re-sends the same text — without
    /// this call the re-send's fresh capture would leave the ORIGINAL note
    /// orphaned instead of replaced). Passing an id that owns no note is a
    /// harmless no-op — callers pass every removed row's id, not just the
    /// ones known in advance to have one.
    ///
    /// A full-table scan-then-filter, not a `#Predicate` membership test:
    /// `sourceMessageID` is `UUID?`, and `Set<UUID>.contains` on an optional
    /// column is the kind of predicate shape worth not gambling on. Note
    /// counts are a person's own "remember that…" list — never large enough
    /// for this to be a real cost.
    func deleteNotes(withSourceMessageIDs ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let doomed = fetch(FetchDescriptor<MemoryNoteRecord>(), op: "deleteNotes")
            .filter { row in row.sourceMessageID.map(ids.contains) ?? false }
        guard !doomed.isEmpty else { return }
        doomed.forEach(context.delete)
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
    ///
    /// Secondary sort by `noteID` (fix round 1 minor): `createdAt` alone is
    /// not a TOTAL order — two notes saved within the same storage-precision
    /// tick sort arbitrarily against each other on repeat calls otherwise.
    /// The tiebreak is applied in Swift, after the fetch, because
    /// `SortDescriptor` needs `Comparable` and `UUID` isn't; sorting by its
    /// string form is a stable, if not semantically meaningful, second key —
    /// its only job is making repeat calls agree with themselves.
    func allNotes() -> [(noteID: UUID, text: String, createdAt: Date, editedAt: Date?, wasTruncated: Bool)] {
        fetch(FetchDescriptor<MemoryNoteRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]), op: "allNotes")
            .sorted {
                $0.createdAt != $1.createdAt
                    ? $0.createdAt > $1.createdAt
                    : $0.noteID.uuidString < $1.noteID.uuidString
            }
            .map { (noteID: $0.noteID, text: $0.text, createdAt: $0.createdAt,
                    editedAt: $0.editedAt, wasTruncated: $0.wasTruncated) }
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

    /// **#422 Task 11 fix round 1 (CRITICAL, item 1).** The note whose
    /// `sourceMessageID` matches — what
    /// `LocalChatBackend.savedNoteThisTurn(clientMessageID:)` reads to
    /// answer "did THIS turn's message really write a memory" from the
    /// STORE, never by re-parsing the message text (the defect: a re-parse
    /// says yes on three paths where nothing was actually saved — the
    /// toggle off, a nil store, and the voice pipeline, which calls
    /// `sendStreaming` directly and never reaches ChatStore's capture at
    /// all). `sourceMessageID` is unique per turn by construction (one
    /// explicit note per send), so the first row a fetch returns is the
    /// only one that could exist; nil is the honest "nothing was saved"
    /// answer, never a placeholder.
    func note(forSourceMessageID sourceMessageID: UUID) -> (noteID: UUID, text: String)? {
        let id = sourceMessageID
        var descriptor = FetchDescriptor<MemoryNoteRecord>(
            predicate: #Predicate { $0.sourceMessageID == id })
        descriptor.fetchLimit = 1
        guard let row = fetch(descriptor, op: "noteForSourceMessageID").first else { return nil }
        return (row.noteID, row.text)
    }

    // MARK: - Use records (#422 Task 10 — what a reply actually drew on)

    /// Records that the reply `replyMessageID` was generated with these
    /// memories in its context. One row per reply, keyed on the reply's id.
    ///
    /// **Why the store and not just the message.** Ruling 2 wants a chip on
    /// every reply that drew on memory, and the chip's ids have to survive a
    /// relaunch, a cache reload and the `.finished` slot swap. Lane M4 adds
    /// `Message.memoryProvenance` (its type, not this branch's) and will stamp
    /// the same fact onto the message; until then this row IS the record, and
    /// it is the RECENTLY USED list's source either way.
    ///
    /// Fetch-then-update rather than a bare insert: `replyMessageID` is
    /// `@Attribute(.unique)`, and a retried turn can settle twice on one id.
    /// Writing nothing when the ids are empty is deliberate — "this reply drew
    /// on nothing" is the absence of a row, never a row full of empty arrays
    /// that the RECENTLY USED list would then have to filter back out.
    func recordUse(replyMessageID: UUID, entryIDs: [UUID], noteIDs: [UUID], at: Date = Date()) {
        guard !entryIDs.isEmpty || !noteIDs.isEmpty else { return }
        let id = replyMessageID
        var descriptor = FetchDescriptor<MemoryUseRecord>(
            predicate: #Predicate { $0.replyMessageID == id })
        descriptor.fetchLimit = 1
        if let row = fetch(descriptor, op: "recordUse").first {
            row.entryIDs = entryIDs
            row.noteIDs = noteIDs
            row.at = at
        } else {
            context.insert(MemoryUseRecord(
                replyMessageID: replyMessageID, store: "local",
                entryIDs: entryIDs, noteIDs: noteIDs, at: at))
        }
        save()
    }

    /// The most recent use records, newest first — Task 16's RECENTLY USED
    /// list reads these, and a test reads them to prove a turn recorded what
    /// it drew on.
    func recentUses(limit: Int = 20) -> [(replyMessageID: UUID, store: String,
                                          entryIDs: [UUID], noteIDs: [UUID], at: Date)] {
        var descriptor = FetchDescriptor<MemoryUseRecord>(
            sortBy: [SortDescriptor(\.at, order: .reverse)])
        descriptor.fetchLimit = max(0, limit)
        return fetch(descriptor, op: "recentUses").map {
            (replyMessageID: $0.replyMessageID, store: $0.store,
             entryIDs: $0.entryIDs, noteIDs: $0.noteIDs, at: $0.at)
        }
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
