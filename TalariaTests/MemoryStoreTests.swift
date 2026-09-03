import Testing
import Foundation
@testable import Talaria

@Suite("422-A store")
@MainActor
struct MemoryStoreTests {
    private func chunk(session: UUID, message: UUID, index: Int, text: String) -> MemoryTurnIndexRecord {
        MemoryTurnIndexRecord(entryID: UUID(), sessionID: session, messageID: message, chunkIndex: index,
                              text: text, sentAt: Date(), embedderID: "test", vector: Data())
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
}
