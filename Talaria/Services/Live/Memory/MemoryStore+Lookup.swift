import Foundation
import SwiftData

/// #422 ruling 2, the read half: resolving the ids a `MemoryProvenance` value
/// carries back into the words the user actually wrote, so the provenance
/// sheet can show a source rather than an identifier.
///
/// Two things this deliberately does NOT do.
///
/// It reads only `text` / `sentAt` / `createdAt`. A source line quotes the
/// user's own words and says when they were said; the scoring columns are no
/// part of that question, and reading them here would tie the one surface the
/// user sees to a retrieval implementation that is still moving.
///
/// It returns `nil` rather than a placeholder for a row that is gone. Missing
/// is a real answer — `reconcileSession` deletes a row whose message the user
/// retried, undid or regenerated away — and the caller renders it as
/// `source deleted`. Manufacturing a stand-in row here would put that decision
/// in the store, where the view could no longer tell a real memory from a
/// hole.
///
/// A separate file from `MemoryStore.swift` on purpose: the schema and its
/// writers are under concurrent edit, and a read-only lookup has no business
/// sitting in the middle of that.
extension MemoryStore {

    /// The indexed turn chunk behind a provenance `entryID`, or `nil` when the
    /// row no longer exists.
    func turnEntry(id: UUID) -> (text: String, sentAt: Date)? {
        let entryID = id
        var descriptor = FetchDescriptor<MemoryTurnIndexRecord>(
            predicate: #Predicate { $0.entryID == entryID })
        descriptor.fetchLimit = 1
        guard let row = try? context.fetch(descriptor).first else { return nil }
        return (row.text, row.sentAt)
    }

    /// The explicit note behind a provenance `noteID`, or `nil` when the row no
    /// longer exists.
    func note(id: UUID) -> (text: String, createdAt: Date)? {
        let noteID = id
        var descriptor = FetchDescriptor<MemoryNoteRecord>(
            predicate: #Predicate { $0.noteID == noteID })
        descriptor.fetchLimit = 1
        guard let row = try? context.fetch(descriptor).first else { return nil }
        return (row.text, row.createdAt)
    }
}
