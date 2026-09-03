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

    func upsertTurnChunks(_ chunks: [MemoryTurnIndexRecord]) {
        for chunk in chunks {
            let messageID = chunk.messageID, index = chunk.chunkIndex
            let existing = fetch(FetchDescriptor<MemoryTurnIndexRecord>(
                predicate: #Predicate { $0.messageID == messageID && $0.chunkIndex == index }),
                op: "upsertTurnChunks")
            if let row = existing.first {
                row.text = chunk.text; row.vector = chunk.vector; row.embedderID = chunk.embedderID
            } else {
                context.insert(chunk)
            }
        }
        save()
    }

    func deleteSession(_ sessionID: UUID) {
        let rows = fetch(FetchDescriptor<MemoryTurnIndexRecord>(
            predicate: #Predicate { $0.sessionID == sessionID }), op: "deleteSession")
        rows.forEach(context.delete)
        save()
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
