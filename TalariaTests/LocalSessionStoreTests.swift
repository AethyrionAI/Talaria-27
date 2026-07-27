import Foundation
import Testing
@testable import Talaria

/// #190 Phase 1 — the SwiftData-backed local session store: keyed upsert,
/// recency-ordered listing, transcript round-trip, and the remote-stub
/// snapshot. All against an in-memory container.
struct LocalSessionStoreTests {

    @MainActor private func makeStore() throws -> SwiftDataLocalSessionStore {
        try #require(SwiftDataLocalSessionStore.make(inMemoryOnly: true))
    }

    private func conversation(
        id: UUID = UUID(),
        title: String = "Hermes",
        messages: [Message],
        lastActivity: Date
    ) -> Conversation {
        Conversation(id: id, title: title, messages: messages, lastActivity: lastActivity)
    }

    private func exchange(_ prompt: String, _ reply: String) -> [Message] {
        [
            Message(sender: .user, content: prompt, status: .delivered),
            Message(sender: .hermes, content: reply, status: .delivered, brain: "on-device"),
        ]
    }

    // MARK: - Sessions

    @Test @MainActor
    func summariesListMostRecentFirst() throws {
        let store = try makeStore()
        let older = conversation(messages: exchange("first", "one"), lastActivity: Date(timeIntervalSince1970: 1_000))
        let newer = conversation(messages: exchange("second", "two"), lastActivity: Date(timeIntervalSince1970: 2_000))
        store.upsertSession(older)
        store.upsertSession(newer)

        let summaries = store.sessionSummaries()
        #expect(summaries.map(\.id) == [newer.id, older.id])
        #expect(summaries.first?.messageCount == 2)
    }

    @Test @MainActor
    func upsertingSameIDUpdatesInsteadOfDuplicating() throws {
        let store = try makeStore()
        let id = UUID()
        let first = conversation(id: id, messages: exchange("hello", "hi"), lastActivity: Date(timeIntervalSince1970: 1_000))
        store.upsertSession(first)

        var grown = first
        grown.messages.append(Message(sender: .user, content: "more", status: .delivered))
        grown.lastActivity = Date(timeIntervalSince1970: 3_000)
        store.upsertSession(grown)

        let summaries = store.sessionSummaries()
        #expect(summaries.count == 1)
        #expect(summaries.first?.messageCount == 3)
        #expect(summaries.first?.lastActivity == Date(timeIntervalSince1970: 3_000))
    }

    @Test @MainActor
    func conversationRoundTripsTranscriptExactly() throws {
        let store = try makeStore()
        var original = conversation(
            title: "Round trip",
            messages: exchange("keep my words", "kept"),
            lastActivity: Date(timeIntervalSince1970: 5_000)
        )
        original.latestUsage = TokenUsage(promptTokens: 12, completionTokens: 34, totalTokens: 46)
        original.generatedPreview = "A preview line"
        store.upsertSession(original)

        let restored = store.conversation(withID: original.id)
        #expect(restored == original)
    }

    @Test @MainActor
    func unknownIDReadsAsAbsent() throws {
        let store = try makeStore()
        #expect(store.conversation(withID: UUID()) == nil)
        #expect(store.hasSession(withID: UUID()) == false)
        #expect(store.sessionSummaries().isEmpty)
    }

    @Test @MainActor
    func hasSessionReflectsStoredIDs() throws {
        let store = try makeStore()
        let stored = conversation(messages: exchange("a", "b"), lastActivity: .now)
        store.upsertSession(stored)
        #expect(store.hasSession(withID: stored.id))
    }

    // MARK: - Remote stubs (#190 Phase 4)

    @Test @MainActor
    func remoteStubSnapshotReplacesWholesale() throws {
        let store = try makeStore()
        let first = HermesSessionInfo(
            id: "s-1", title: "Server one", preview: "p1", model: "opus",
            source: "chat", messageCount: 4,
            lastActive: Date(timeIntervalSince1970: 1_000), isActive: false
        )
        let second = HermesSessionInfo(
            id: "s-2", title: "Server two", preview: "p2", model: "opus",
            source: "cron", messageCount: 9,
            lastActive: Date(timeIntervalSince1970: 2_000), isActive: false
        )
        store.recordRemoteSessionStubs([first, second])

        // The host stopped listing s-1 — the snapshot must not resurrect it.
        store.recordRemoteSessionStubs([second])

        let stubs = store.remoteSessionStubs()
        #expect(stubs.map(\.id) == ["s-2"])
        #expect(stubs.first?.title == "Server two")
        #expect(stubs.first?.source == "cron")
        #expect(stubs.first?.messageCount == 9)
    }

    @Test @MainActor
    func remoteStubsListMostRecentFirst() throws {
        let store = try makeStore()
        let older = HermesSessionInfo(
            id: "s-old", title: nil, preview: nil, model: nil,
            source: "chat", messageCount: 1,
            lastActive: Date(timeIntervalSince1970: 1_000), isActive: false
        )
        let newer = HermesSessionInfo(
            id: "s-new", title: nil, preview: nil, model: nil,
            source: "chat", messageCount: 2,
            lastActive: Date(timeIntervalSince1970: 9_000), isActive: false
        )
        store.recordRemoteSessionStubs([older, newer])
        #expect(store.remoteSessionStubs().map(\.id) == ["s-new", "s-old"])
    }
}
