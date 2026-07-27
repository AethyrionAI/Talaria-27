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

    /// #190B change (4): the 26 pre-existing tests round-trip synthetic
    /// minimal conversations; the device pass showed that "probably fine" is
    /// not a decode guarantee. This drives a REAL-shaped conversation — every
    /// field the cache coders persist, populated the way live turns populate
    /// them — through encode → SwiftData → decode on the actual store.
    /// (`toolActivity` and `codeDiff` are transient stream state the coders
    /// deliberately drop; they are exactly as absent here as in a persisted
    /// live thread.)
    @Test @MainActor
    func maximalRealShapedConversationRoundTripsThroughStore() throws {
        let store = try makeStore()
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        let voiceBanner = Message(
            sender: .system,
            content: "[Voice session ended]",
            timestamp: base,
            status: .delivered,
            voiceSessionDuration: 154.5
        )
        let voiceUser = Message(sender: .voiceUser, content: "spoken question", timestamp: base + 1, status: .delivered)
        let voiceHermes = Message(sender: .voiceHermes, content: "spoken answer", timestamp: base + 2, status: .delivered)

        let userClientID = UUID()
        let userTurn = Message(
            id: userClientID,
            clientMessageID: userClientID,
            sender: .user,
            content: "run the analysis on these",
            timestamp: base + 10,
            status: .delivered,
            attachments: [
                MessageAttachment(
                    kind: "image", fileName: "chart.png", mimeType: "image/png",
                    thumbnailBase64: "aGVsbG8=", localStoragePath: "/tmp/chart.png"
                ),
                MessageAttachment(
                    kind: "file", fileName: "memo.m4a", mimeType: "audio/mp4",
                    voiceMemoAudioPath: "/tmp/memo.m4a"
                ),
                MessageAttachment(
                    kind: "file", fileName: "report.pdf", mimeType: "application/pdf",
                    remotePath: "reports/report.pdf", remoteProfileID: UUID()
                ),
            ]
        )

        let hermesTurn = Message(
            sender: .hermes,
            content: "Here's the analysis.",
            timestamp: base + 20,
            jobID: UUID(),
            status: .delivered,
            toolActivities: [
                ToolActivity(label: "write_file", startedAt: base + 12, isActive: false,
                             detail: "reports/report.pdf", anchorOffset: 6),
                ToolActivity(label: "terminal", startedAt: base + 14, isActive: false,
                             detail: "python analyze.py", anchorOffset: 12),
            ],
            reasoning: "First I should read the attachments…",
            reasoningSummary: "Read attachments, then analyzed.",
            brain: "hermes",
            usage: TokenUsage(promptTokens: 1_200, completionTokens: 340, totalTokens: 1_540),
            turnDuration: 42.7,
            servingModel: "claude-opus-4.8"
        )

        let primingNotice = Message(
            sender: .system,
            content: "[Context transplanted into a fresh session — 2.1K tokens]",
            timestamp: base + 30,
            status: .delivered,
            usage: TokenUsage(promptTokens: 2_100, completionTokens: 0, totalTokens: 2_100),
            servingModel: "claude-opus-4.8",
            isContextPriming: true
        )

        let failedUser = Message(sender: .user, content: "lost turn", timestamp: base + 40, status: .failed)
        let localTurn = Message(
            sender: .hermes,
            content: "Continuing on-device.",
            timestamp: base + 50,
            status: .delivered,
            reasoning: "Short local reasoning.",
            brain: "on-device",
            usage: TokenUsage(promptTokens: 800, completionTokens: 120, totalTokens: 920),
            turnDuration: 3.4,
            servingModel: "apple-on-device"
        )

        var original = Conversation(
            title: "Analysis session",
            messages: [voiceBanner, voiceUser, voiceHermes, userTurn, hermesTurn, primingNotice, failedUser, localTurn],
            lastActivity: base + 50
        )
        original.latestUsage = TokenUsage(promptTokens: 800, completionTokens: 120, totalTokens: 920)
        original.generatedPreview = "Attachment analysis across both brains"

        store.upsertSession(original)
        let restored = try #require(store.conversation(withID: original.id))
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
