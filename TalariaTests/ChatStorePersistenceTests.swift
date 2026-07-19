import Foundation
import Testing
@testable import Talaria

/// #56 (Wave 2 Issue E follow-up) — durable optimistic sends: the sent turn is
/// persisted BEFORE streaming starts so a process death mid-run (Siri
/// background launch reaped past the intent budget, app killed mid-stream)
/// can't lose the exchange, and cold load finalizes the stranded `.sending`
/// state instead of leaving it pending forever.
struct ChatStorePersistenceTests {

    @MainActor
    private final class ImmediateReplyClient: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .connected
        var currentConversation: Conversation?
        /// Fired synchronously when sendStreaming is invoked — after the
        /// optimistic save, before any stream event lands.
        var onSendStreaming: (() -> Void)?

        func connect() async {}
        func disconnect() async {}

        func send(message: String, attachments: [PendingAttachment], clientMessageID: UUID) async -> Message {
            Message(sender: .hermes, content: "ok", status: .delivered)
        }

        func sendStreaming(
            message: String,
            attachments: [PendingAttachment],
            clientMessageID: UUID
        ) -> AsyncStream<StreamingUpdate> {
            onSendStreaming?()
            return AsyncStream { continuation in
                continuation.yield(.finished(
                    Message(sender: .hermes, content: "Done.", status: .delivered),
                    nil,
                    nil
                ))
                continuation.finish()
            }
        }

        func loadConversation() async -> Conversation {
            if let currentConversation { return currentConversation }
            let fresh = Conversation(title: "Hermes")
            currentConversation = fresh
            return fresh
        }

        func clearConversation() async throws -> Conversation {
            let fresh = Conversation(title: "Hermes")
            currentConversation = fresh
            return fresh
        }
    }

    @MainActor private func makePersistence() -> UserDefaultsAppPersistenceStore {
        let suiteName = "chat-store-persistence-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsAppPersistenceStore(defaults: defaults)
    }

    // MARK: - Optimistic-send persistence

    @Test @MainActor
    func sendPersistsUserTurnBeforeStreamingStarts() async throws {
        let persistence = makePersistence()
        let client = ImmediateReplyClient()
        let chatStore = ChatStore(hermesClient: client, persistence: persistence)

        // Snapshot the cache at the moment the stream request is made — this
        // is what a process death at any later point would leave behind.
        var cacheAtStreamStart: Conversation?
        client.onSendStreaming = {
            cacheAtStreamStart = persistence.loadConversationCache()
        }

        await chatStore.sendMessage("What's the relay status?")

        let snapshot = try #require(cacheAtStreamStart)
        // The sent turn survived; the transient streaming placeholder is
        // deliberately NOT in the pre-stream save.
        #expect(snapshot.messages.count == 1)
        #expect(snapshot.messages.first?.sender == .user)
        #expect(snapshot.messages.first?.status == .sending)
        #expect(snapshot.messages.first?.content == "What's the relay status?")

        // And the completed exchange still persists as before.
        let final = try #require(persistence.loadConversationCache())
        #expect(final.messages.last?.sender == .hermes)
        #expect(final.messages.last?.content == "Done.")
    }

    // MARK: - Cold-load finalization

    @Test @MainActor
    func coldLoadFinalizesStaleSendingStateFromCache() async throws {
        let persistence = makePersistence()

        // What a mid-stream process death leaves in the cache: the persisted
        // user turn (.sending) — plus, via older mid-stream save paths (relay
        // polling), possibly an empty streaming placeholder row.
        persistence.saveConversationCache(Conversation(
            title: "Hermes",
            messages: [
                Message(sender: .hermes, content: "Earlier reply.", status: .delivered),
                Message(sender: .user, content: "Killed mid-run", status: .sending),
                Message(sender: .hermes, content: "", status: .sending),
            ]
        ))

        let chatStore = ChatStore(hermesClient: ImmediateReplyClient(), persistence: persistence)
        await chatStore.loadConversationIfNeeded()

        let messages = try #require(chatStore.conversation?.messages)
        // Stranded send → .failed (retry affordance), never pending forever.
        let stranded = try #require(messages.first(where: { $0.content == "Killed mid-run" }))
        #expect(stranded.status == .failed)
        // Placeholder scrubbed; delivered history untouched.
        #expect(!messages.contains(where: { $0.sender == .hermes && $0.content.isEmpty }))
        #expect(messages.contains(where: { $0.content == "Earlier reply." && $0.status == .delivered }))

        // The finalized state is written back, so a second launch is clean.
        let repersisted = try #require(persistence.loadConversationCache())
        #expect(repersisted.messages.first(where: { $0.content == "Killed mid-run" })?.status == .failed)
    }

    // MARK: - Composer seed (#48 hermes://ask?q=)

    // Lives here (not a new file) to spare an xcodegen regen: same store,
    // same harness. Seed-only semantics are the security property — an
    // externally fired URL must never auto-send.

    @Test @MainActor
    func composerSeedIsHeldUntilConsumedExactlyOnce() {
        let chatStore = ChatStore(hermesClient: ImmediateReplyClient(), persistence: makePersistence())

        chatStore.seedComposer("  summarize my day  ")
        #expect(chatStore.pendingComposerSeed == "summarize my day")

        #expect(chatStore.consumeComposerSeed() == "summarize my day")
        #expect(chatStore.pendingComposerSeed == nil)
        #expect(chatStore.consumeComposerSeed() == nil)
    }

    @Test @MainActor
    func composerSeedIgnoresEmptyPayloads() {
        let chatStore = ChatStore(hermesClient: ImmediateReplyClient(), persistence: makePersistence())
        chatStore.seedComposer("   ")
        #expect(chatStore.pendingComposerSeed == nil)
        chatStore.seedComposer("")
        #expect(chatStore.pendingComposerSeed == nil)
    }

    // MARK: - Share seed (#123 share extension)

    // A separate slot from the #48 ask-seed on purpose: share seeds carry
    // attachments and APPEND to a queued share (two rapid shares both land),
    // while the ask-seed stays a replace-only String. Same seed-only security
    // property: nothing here may auto-send.

    private func stagedTextAttachment(named fileName: String) -> PendingAttachment {
        PendingAttachment(
            kind: .file,
            fileName: fileName,
            mimeType: "text/markdown",
            data: Data("body".utf8),
            localStoragePath: nil,
            thumbnailData: nil
        )
    }

    @Test @MainActor
    func shareSeedMergesQueuedSharesAndConsumesOnce() throws {
        let chatStore = ChatStore(hermesClient: ImmediateReplyClient(), persistence: makePersistence())

        chatStore.seedComposerFromShare(text: "  first  ", attachments: [stagedTextAttachment(named: "a.md")])
        chatStore.seedComposerFromShare(text: "second", attachments: [stagedTextAttachment(named: "b.md")])

        let seed = try #require(chatStore.consumeShareSeed())
        #expect(seed.text == "first\nsecond")
        #expect(seed.attachments.map(\.fileName) == ["a.md", "b.md"])
        #expect(chatStore.consumeShareSeed() == nil)
    }

    @Test @MainActor
    func shareSeedAcceptsAttachmentOnlyAndRejectsEmpty() {
        let chatStore = ChatStore(hermesClient: ImmediateReplyClient(), persistence: makePersistence())

        chatStore.seedComposerFromShare(text: "   ", attachments: [])
        #expect(chatStore.pendingShareSeed == nil)

        chatStore.seedComposerFromShare(text: "", attachments: [stagedTextAttachment(named: "photo.md")])
        #expect(chatStore.pendingShareSeed != nil)
        #expect(chatStore.consumeShareSeed()?.text == "")
    }

    @Test @MainActor
    func coldLoadLeavesHealthyCacheUntouched() async throws {
        let persistence = makePersistence()
        persistence.saveConversationCache(Conversation(
            title: "Hermes",
            messages: [
                Message(sender: .user, content: "Hi", status: .delivered),
                Message(sender: .hermes, content: "Hello.", status: .delivered),
            ]
        ))

        let chatStore = ChatStore(hermesClient: ImmediateReplyClient(), persistence: persistence)
        await chatStore.loadConversationIfNeeded()

        let messages = try #require(chatStore.conversation?.messages)
        #expect(messages.count == 2)
        #expect(messages.allSatisfy { $0.status == .delivered })
    }

    // MARK: - Per-turn regenerate / edit (#44)

    // Same harness as above (not a new file — spares an xcodegen regen).

    @MainActor
    private func makeStoreWithHistory(_ client: ImmediateReplyClient) -> (ChatStore, [Message]) {
        let history = [
            Message(sender: .user, content: "First question", status: .delivered),
            Message(sender: .hermes, content: "First answer", status: .delivered),
            Message(sender: .user, content: "Second question", status: .delivered),
            Message(sender: .hermes, content: "Second answer", status: .delivered),
        ]
        let persistence = makePersistence()
        persistence.saveConversationCache(Conversation(title: "Hermes", messages: history))
        let chatStore = ChatStore(hermesClient: client, persistence: persistence)
        return (chatStore, history)
    }

    @Test @MainActor
    func regenerateMidHistoryReplyTruncatesFromItsUserTurnAndResends() async throws {
        let client = ImmediateReplyClient()
        let (chatStore, history) = makeStoreWithHistory(client)
        await chatStore.loadConversationIfNeeded()

        // Re-roll the FIRST answer: everything from "First question" onward
        // goes, and that turn re-sends through the full pipeline.
        await chatStore.regenerateReply(history[1])

        let messages = try #require(chatStore.conversation?.messages)
        #expect(messages.count == 2)
        #expect(messages.first?.sender == .user)
        #expect(messages.first?.content == "First question")
        #expect(messages.last?.sender == .hermes)
        #expect(messages.last?.content == "Done.")
        #expect(!messages.contains(where: { $0.content == "Second question" }))
    }

    @Test @MainActor
    func regenerateIgnoresMessagesWithoutAProducingUserTurn() async throws {
        let client = ImmediateReplyClient()
        let persistence = makePersistence()
        let orphanReply = Message(sender: .hermes, content: "Greeting", status: .delivered)
        persistence.saveConversationCache(Conversation(title: "Hermes", messages: [orphanReply]))
        let chatStore = ChatStore(hermesClient: client, persistence: persistence)
        await chatStore.loadConversationIfNeeded()

        await chatStore.regenerateReply(orphanReply)

        // No user turn before it — nothing truncated, nothing sent.
        #expect(chatStore.conversation?.messages.count == 1)
    }

    @Test @MainActor
    func extractTurnForEditingTruncatesAndReturnsComposerPieces() async throws {
        let client = ImmediateReplyClient()
        let (chatStore, history) = makeStoreWithHistory(client)
        await chatStore.loadConversationIfNeeded()

        let turn = try #require(chatStore.extractTurnForEditing(history[2]))

        #expect(turn.text == "Second question")
        let messages = try #require(chatStore.conversation?.messages)
        #expect(messages.count == 2)
        #expect(messages.last?.content == "First answer")

        // The truncation persists — a relaunch must not resurrect the tail.
        let cached = try #require(chatStore.persistence.loadConversationCache())
        #expect(cached.messages.count == 2)
    }

    @Test @MainActor
    func extractTurnForEditingRefusesNonUserMessages() async throws {
        let client = ImmediateReplyClient()
        let (chatStore, history) = makeStoreWithHistory(client)
        await chatStore.loadConversationIfNeeded()

        #expect(chatStore.extractTurnForEditing(history[1]) == nil)
        #expect(chatStore.conversation?.messages.count == 4)
    }
}
