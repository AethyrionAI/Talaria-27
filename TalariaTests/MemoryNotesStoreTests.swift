import Foundation
import Testing
@testable import Talaria

/// #422 Task 11 — the explicit-note store CRUD. `MemoryStoreTests.swift`
/// (suite "422-A store") owns the indexed-TURN pins from bar 422-A; this
/// suite owns the separate `MemoryNoteRecord` surface a saved
/// "Remember that…" writes to, read through, edits in place, and forgets.
///
/// Every insert here stands in for `ExplicitMemoryIntent.parse`'s output —
/// this suite does not re-test the parser (see `ExplicitMemoryIntentTests`);
/// it tests that the store keeps, resolves, edits and forgets whatever text
/// it is handed, unchanged.
@Suite("422-E note store")
@MainActor
struct MemoryNotesStoreTests {

    // MARK: - Insert + resolve (the note-by-id positive pin Task 15 dropped)

    /// **Re-adds the positive pin Task 15's fix round dropped.** Lane M4's
    /// provenance-chip task added a read-only `note(id:)` but no writer, so
    /// its own positive-path test (`theStoreResolvesAnExplicitNoteByItsNoteID`)
    /// had no production route to seed a row and was deleted — recorded as
    /// "OWED" in that task's report. `insertNote` is that writer.
    @Test func insertedNoteResolvesByID() throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let id = store.insertNote("my sister lives in Austin", sourceMessageID: nil, sourceSessionID: nil)

        let resolved = try #require(store.note(id: id))
        #expect(resolved.text == "my sister lives in Austin")
        #expect(abs(resolved.createdAt.timeIntervalSinceNow) < 5, "createdAt is stamped at insert time")
    }

    @Test func anIDTheStoreHasNeverSeenResolvesToNil() throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        #expect(store.note(id: UUID()) == nil)
    }

    /// `allNotes()`/`note(id:)` don't surface `sourceMessageID`/
    /// `sourceSessionID` (no reader was asked for — the schema keeps them for
    /// a future provenance resolver), so this can only prove the explicit
    /// source arguments are accepted and the row is created — not read the
    /// values back. Named accordingly rather than claiming more than it pins.
    @Test func insertNoteAcceptsAnExplicitSourceWithoutLosingTheRow() throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let messageID = UUID(), sessionID = UUID()
        let id = store.insertNote("call the dentist", sourceMessageID: messageID, sourceSessionID: sessionID)

        let all = store.allNotes()
        #expect(all.count == 1)
        #expect(all.first?.noteID == id)
    }

    // MARK: - Delete (Undo's primitive)

    @Test func deleteNoteRemovesIt() throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let id = store.insertNote("call the dentist", sourceMessageID: nil, sourceSessionID: nil)
        #expect(store.note(id: id) != nil)

        store.deleteNote(id)

        #expect(store.note(id: id) == nil)
        #expect(store.allNotes().isEmpty)
    }

    @Test func deletingAnUnknownNoteIsANoOp() throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let kept = store.insertNote("keep me", sourceMessageID: nil, sourceSessionID: nil)

        store.deleteNote(UUID())

        #expect(store.note(id: kept) != nil, "a delete of an unrelated id must not touch a real row")
        #expect(store.allNotes().count == 1)
    }

    @Test func deleteOnlyRemovesTheNamedRow() throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let doomed = store.insertNote("forget this", sourceMessageID: nil, sourceSessionID: nil)
        let kept = store.insertNote("keep this", sourceMessageID: nil, sourceSessionID: nil)

        store.deleteNote(doomed)

        #expect(store.note(id: doomed) == nil)
        #expect(store.note(id: kept)?.text == "keep this")
    }

    // MARK: - Update (edit in place — keeps createdAt, stamps editedAt)

    @Test func updateNoteChangesTextAndStampsEditedAtKeepingCreatedAt() throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let id = store.insertNote("my sister lives in Austin", sourceMessageID: nil, sourceSessionID: nil)
        let originalCreatedAt = try #require(store.note(id: id)).createdAt
        let originalRow = try #require(store.allNotes().first { $0.noteID == id })
        #expect(originalRow.editedAt == nil, "an unedited note has no editedAt")

        store.updateNote(id, text: "my sister lives in Denver now")

        let updated = try #require(store.note(id: id))
        #expect(updated.text == "my sister lives in Denver now")
        #expect(updated.createdAt == originalCreatedAt, "editing must not restamp when the note was FIRST saved")
        let updatedRow = try #require(store.allNotes().first { $0.noteID == id })
        #expect(updatedRow.editedAt != nil, "an edit stamps editedAt")
    }

    @Test func updatingAnUnknownNoteIsANoOp() throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let id = store.insertNote("real note", sourceMessageID: nil, sourceSessionID: nil)

        store.updateNote(UUID(), text: "does not exist")

        #expect(store.note(id: id)?.text == "real note", "an update of an unrelated id must not touch a real row")
        #expect(store.allNotes().count == 1)
    }

    // MARK: - allNotes() — newest first

    @Test func allNotesOnAnEmptyStoreIsEmpty() throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        #expect(store.allNotes().isEmpty)
    }

    @Test func allNotesOrdersNewestFirst() throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let first = store.insertNote("said first", sourceMessageID: nil, sourceSessionID: nil)
        // SwiftData timestamps at insert time — force a real gap so the
        // ordering assertion cannot pass by clock-resolution luck.
        Thread.sleep(forTimeInterval: 0.01)
        let second = store.insertNote("said second", sourceMessageID: nil, sourceSessionID: nil)

        let all = store.allNotes()
        #expect(all.map(\.noteID) == [second, first], "newest first — the notes-block composer relies on this order")
    }
}
