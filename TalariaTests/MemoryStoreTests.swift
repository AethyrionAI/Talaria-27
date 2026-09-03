import Testing
import Foundation
@testable import Talaria

@Suite("422-A store")
@MainActor
struct MemoryStoreTests {
    private func chunk(session: UUID, message: UUID, index: Int, text: String) -> MemoryTurnIndexRecord {
        MemoryTurnIndexRecord(entryID: UUID(), sessionID: session, messageID: message, chunkIndex: index,
                              text: text, sentAt: Date())
    }

    @Test func upsertIsIdempotentByMessageAndChunkIndex() throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let session = UUID(), message = UUID()
        store.upsertTurnChunks([chunk(session: session, message: message, index: 0, text: "my dentist is Dr. Patel")])
        store.upsertTurnChunks([chunk(session: session, message: message, index: 0, text: "my dentist is Dr. Patel")])
        #expect(store.indexCount() == 1, "the settle seam fires twice for one turn — the second upsert must not duplicate")
    }

    @Test func deletingASessionCascadesItsIndexRows() throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let doomed = UUID(), kept = UUID()
        store.upsertTurnChunks([chunk(session: doomed, message: UUID(), index: 0, text: "a"),
                                chunk(session: kept, message: UUID(), index: 0, text: "b")])
        store.deleteSession(doomed)
        #expect(store.indexCount() == 1, "a memory must not outlive its source session (dangling source line)")
    }

    /// #422 (Task 8b): the retrieval query surface. `candidates()` is what
    /// `LocalChatBackend` hands the scorer, so an excluded row must be invisible
    /// HERE rather than filtered downstream — a row that reaches the scorer at
    /// all can be ranked, chipped and shown, and "excluded" would then mean
    /// "excluded from the UI list" instead of "excluded from memory".
    @Test func candidatesOmitExcludedRows() throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let session = UUID()
        let keptMessage = UUID(), excludedMessage = UUID()
        store.upsertTurnChunks([
            chunk(session: session, message: keptMessage, index: 0, text: "my dentist is Dr. Patel"),
            chunk(session: session, message: excludedMessage, index: 0, text: "the hallway is blue"),
        ])
        let excludedID = try #require(
            store.candidates().first { $0.text == "the hallway is blue" }?.entryID)
        store.setExcluded(entryID: excludedID, true)
        let remaining = store.candidates()
        #expect(remaining.count == 1)
        #expect(remaining.first?.text == "my dentist is Dr. Patel")
        #expect(store.indexCount() == 2, "exclusion hides a row from retrieval; it must not DELETE it")
    }

    /// The round trip. Exclusion is a user-reversible switch, not a tombstone —
    /// Forget everything is the only thing that deletes (Owen, 09-02).
    @Test func anExcludedRowCanBeRestored() throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let session = UUID()
        store.upsertTurnChunks([chunk(session: session, message: UUID(), index: 0, text: "the hallway is blue")])
        let id = try #require(store.candidates().first?.entryID)
        store.setExcluded(entryID: id, true)
        #expect(store.candidates().isEmpty)
        store.setExcluded(entryID: id, false)
        #expect(store.candidates().count == 1)
        #expect(store.candidates().first?.text == "the hallway is blue")
    }
}
