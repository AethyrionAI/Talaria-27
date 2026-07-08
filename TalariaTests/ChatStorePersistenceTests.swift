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
}
