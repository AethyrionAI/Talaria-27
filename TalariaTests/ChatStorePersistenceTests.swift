import Foundation
import Testing
@testable import Talaria

/// #56 (Wave 2 Issue E follow-up) — durable optimistic sends: the sent turn is
/// persisted BEFORE streaming starts so a process death mid-run (Siri
/// background launch reaped past the intent budget, app killed mid-stream)
/// can't lose the exchange, and cold load finalizes the stranded `.sending`
/// state instead of leaving it pending forever.
struct ChatStorePersistenceTests {

    /// ⚠️ **This double does NOT mirror the transcript** — it never appends a
    /// turn to `currentConversation`, so ChatStore's post-turn / poll-tick
    /// merge against a client's mirror is a structural no-op here. That is
    /// exactly why the #44 pins below were green while #78's resurrection
    /// shipped. Fine for send/persistence/stream-event pins; **never use it
    /// for a truncation-durability pin** — use `MirroringReplyClient`.
    @MainActor
    private final class ImmediateReplyClient: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .connected
        var currentConversation: Conversation?
        /// Fired synchronously when sendStreaming is invoked — after the
        /// optimistic save, before any stream event lands.
        var onSendStreaming: (() -> Void)?
        /// #203 (1A): when non-empty, these are emitted in order instead of
        /// the single `.finished` — so a test can drive real stream EVENTS.
        var script: [StreamingUpdate] = []

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
            let script = self.script
            if !script.isEmpty {
                return AsyncStream { continuation in
                    for update in script { continuation.yield(update) }
                    continuation.finish()
                }
            }
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

    // MARK: - #78: truncation durability (regenerate / edit-and-resend)

    /// The double the #44 pins should always have had.
    ///
    /// Every real backend keeps its OWN copy of the thread —
    /// `LocalChatBackend` restores it from this same conversation cache and
    /// appends both halves of every turn; `SessionsHermesClient` caches the
    /// last server fetch — and ChatStore merges that copy back over its
    /// transcript at the end of every turn, on every ~2s poll tick, and on
    /// the streaming fallback path, taking the mirror as the BASE ordering.
    /// `ImmediateReplyClient` never populates `currentConversation`, so that
    /// merge is a structural no-op there: the resurrection path is ABSENT
    /// from the fixture, which is why a correct test passed against broken
    /// behaviour for a month (#78, the #258/#259 green-certifies-broken
    /// family). This one mirrors, so the merge is real.
    ///
    /// **#281 — and it mirrored only ONE of the two production shapes.** As
    /// first written this double always stamped a `clientMessageID` on the
    /// user row it mirrored, which is `LocalChatBackend`'s shape and NOT the
    /// Hermes one: `SessionsHermesClient.currentConversation` is a FETCH
    /// CACHE built by `mapStoredMessage`, which never sets that field and is
    /// not appended to by a send at all. The merge's confirmation tiers read
    /// exactly that field, so the Hermes-path defect (#281) was structurally
    /// unreachable from this fixture — the same failure as
    /// `ImmediateReplyClient`, one heuristic further in. `mirrorShape` makes
    /// both shapes expressible; pinned by 281-C.
    @MainActor
    private final class MirroringReplyClient: HermesClientProtocol {
        /// Which production mirror this double is imitating. They differ in
        /// precisely the fields `ChatStore.unconfirmedLocalMessages` reads,
        /// so a test that does not name one is testing an invented backend.
        enum MirrorShape {
            /// `LocalChatBackend` — an APPEND LOG. Both halves of every turn
            /// land in `currentConversation` as the turn runs, and the user
            /// row carries the client's own id AND its `clientMessageID`, so
            /// the merge pairs it by identity.
            case localBrain
            /// `SessionsHermesClient` — a FETCH CACHE. A sent turn never
            /// enters it (only `openSession`, `reconcileFromServer`,
            /// `adoptTruncatedConversation` and `clearConversation` write
            /// it), and every row it holds came from `mapStoredMessage`,
            /// which stamps a server-derived stable id and NEVER a
            /// `clientMessageID`.
            case hermesFetchCache
        }

        var connectionStatus: ConnectionStatus = .connected
        var currentConversation: Conversation?
        var replyText = "Done."
        var mirrorShape: MirrorShape = .localBrain
        /// Prompts handed to `sendStreaming` — #275 reads which turn re-sent.
        private(set) var sentPrompts: [String] = []
        /// 78-E: a mirror-less-session client's stand-in for
        /// `LocalChatBackend.session = nil`. The real half of that bar is
        /// pinned against `LocalChatBackend` itself in `LocalChatBackendTests`.
        private(set) var didInvalidateSession = false
        private(set) var adoptedMessageCounts: [Int] = []

        /// #278: when true, `sendStreaming` yields `.interrupted` instead of
        /// `.finished` — the shape a stream takes when the user leaves the
        /// chat screen mid-run. The run stays live server-side.
        var interruptsInsteadOfFinishing = false

        init(mirroring conversation: Conversation? = nil) {
            currentConversation = conversation
        }

        func connect() async {}
        func disconnect() async {}

        func send(message: String, attachments: [PendingAttachment], clientMessageID: UUID) async -> Message {
            sentPrompts.append(message)
            let reply = Message(sender: .hermes, content: replyText, status: .delivered)
            mirror(message: message, attachments: attachments, clientMessageID: clientMessageID, reply: reply)
            return reply
        }

        func sendStreaming(
            message: String,
            attachments: [PendingAttachment],
            clientMessageID: UUID
        ) -> AsyncStream<StreamingUpdate> {
            sentPrompts.append(message)
            if interruptsInsteadOfFinishing {
                return AsyncStream { continuation in
                    continuation.yield(.messageSent(jobID: UUID()))
                    continuation.yield(.interrupted(sessionId: "live-session", runId: "live-run"))
                    continuation.finish()
                }
            }
            let reply = Message(sender: .hermes, content: replyText, status: .delivered)
            // Mirrored BEFORE `.finished` is yielded — exactly the order
            // `LocalChatBackend` uses, which is what lets a mid-stream poll
            // adopt the reply early (#120).
            mirror(message: message, attachments: attachments, clientMessageID: clientMessageID, reply: reply)
            return AsyncStream { continuation in
                continuation.yield(.finished(reply, nil, nil))
                continuation.finish()
            }
        }

        /// `LocalChatBackend.appendUserMessage` / `appendAssistantMessage`,
        /// reduced to their mirroring effect: the user row carries the
        /// client's own id so ChatStore's merge pairs it by identity.
        ///
        /// **#281:** on `.hermesFetchCache` this is a NO-OP, because the real
        /// `SessionsHermesClient` does not append the turn it just sent —
        /// `currentConversation` there only changes on a fetch or an adopt.
        private func mirror(
            message: String,
            attachments: [PendingAttachment],
            clientMessageID: UUID,
            reply: Message
        ) {
            guard mirrorShape == .localBrain else { return }
            if currentConversation == nil {
                currentConversation = Conversation(title: Conversation.defaultTitle)
            }
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayContent = trimmed.isEmpty && !attachments.isEmpty
                ? "[\(attachments.count) attachment\(attachments.count == 1 ? "" : "s")]"
                : trimmed
            currentConversation?.messages.append(Message(
                id: clientMessageID,
                clientMessageID: clientMessageID,
                sender: .user,
                content: displayContent,
                status: .delivered,
                attachments: attachments.map { MessageAttachment(from: $0) }
            ))
            currentConversation?.messages.append(reply)
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

        func adoptTruncatedConversation(_ conversation: Conversation) {
            currentConversation = conversation
            didInvalidateSession = true
            adoptedMessageCounts.append(conversation.messages.count)
        }
    }

    /// A four-turn thread that the store AND the backend both hold — the
    /// production shape, where the backend restored the very same cache.
    @MainActor
    private func makeMirroredStore(
        history: [Message]? = nil,
        shape: MirroringReplyClient.MirrorShape = .localBrain
    ) -> (ChatStore, MirroringReplyClient, [Message], UserDefaultsAppPersistenceStore) {
        let rows = history ?? [
            Message(sender: .user, content: "First question", status: .delivered),
            Message(sender: .hermes, content: "First answer", status: .delivered),
            Message(sender: .user, content: "Second question", status: .delivered),
            Message(sender: .hermes, content: "Second answer", status: .delivered),
        ]
        let persistence = makePersistence()
        let cached = Conversation(title: "Hermes", messages: rows)
        persistence.saveConversationCache(cached)
        let client = MirroringReplyClient(mirroring: cached)
        client.mirrorShape = shape
        return (ChatStore(hermesClient: client, persistence: persistence), client, rows, persistence)
    }

    /// #281's fixture: a thread reopened from the drawer on the Hermes path.
    /// Every row came off the server transcript, so none carries a
    /// `clientMessageID` — and the SAME prompt text appears TWICE, which is
    /// what arms the content-claim tier. The four-distinct-strings fixture
    /// above cannot fire a claim at all, which is the other half of why the
    /// suite never saw this.
    @MainActor
    private func repeatedPromptServerHistory() -> [Message] {
        let base = Date(timeIntervalSince1970: 1_754_000_000)
        return [
            Message(sender: .user, content: "How many are left",
                    timestamp: base, status: .delivered),
            Message(sender: .hermes, content: "Five.",
                    timestamp: base.addingTimeInterval(1), status: .delivered),
            Message(sender: .user, content: "How many are left",
                    timestamp: base.addingTimeInterval(2), status: .delivered),
            Message(sender: .hermes, content: "Four.",
                    timestamp: base.addingTimeInterval(3), status: .delivered),
        ]
    }

    /// **78-A** — the count. A mid-history re-roll truncates from the turn
    /// that produced the reply and the truncation STAYS truncated through
    /// the post-turn merge.
    @Test @MainActor
    func regenerateSurvivesTheBackendMirrorMerge() async throws {
        let (store, _, history, _) = makeMirroredStore()
        await store.loadConversationIfNeeded()

        await store.regenerateReply(history[1])

        let messages = try #require(store.conversation?.messages)
        #expect(messages.count == 2)
    }

    /// **78-B** — the identity. The original reply row is GONE (not merely
    /// outnumbered) and the regenerated one is the tail.
    @Test @MainActor
    func regenerateLeavesNoResurrectedRowsAndEndsOnTheNewReply() async throws {
        let (store, _, history, persistence) = makeMirroredStore()
        await store.loadConversationIfNeeded()

        await store.regenerateReply(history[1])

        let messages = try #require(store.conversation?.messages)
        #expect(!messages.contains { $0.id == history[1].id })
        #expect(!messages.contains { $0.content == "First answer" })
        #expect(!messages.contains { $0.content == "Second question" })
        #expect(!messages.contains { $0.content == "Second answer" })
        #expect(messages.last?.sender == .hermes)
        #expect(messages.last?.content == "Done.")
        // #78's missing save: a re-roll that isn't persisted is undone by a
        // relaunch even when the merge behaves.
        let cached = try #require(persistence.loadConversationCache())
        #expect(!cached.messages.contains { $0.content == "Second answer" })
    }

    /// **78-C** — the poll tick. One merge against the backend's mirror is
    /// all it took to put the removed rows back; it must now be inert.
    @Test @MainActor
    func oneRefreshMergeAfterATruncationDoesNotResurrectRows() async throws {
        let (store, _, history, _) = makeMirroredStore()
        await store.loadConversationIfNeeded()

        // Truncate without sending — this isolates the MERGE as the only
        // thing that runs between the truncation and the assertion.
        _ = store.extractTurnForEditing(history[2])
        #expect(store.conversation?.messages.count == 2)

        await store.loadConversation()

        let messages = try #require(store.conversation?.messages)
        #expect(messages.count == 2)
        #expect(!messages.contains { $0.content == "Second question" })
        #expect(!messages.contains { $0.content == "Second answer" })
    }

    /// **78-D** — edit-and-resend durability. The cruel shape: the
    /// truncation looks right (nothing sends at that moment, so no merge
    /// runs) and is wiped the instant the user taps send.
    @Test @MainActor
    func editAndResendTruncationSurvivesTheFollowUpSend() async throws {
        let (store, _, history, persistence) = makeMirroredStore()
        await store.loadConversationIfNeeded()

        let turn = try #require(store.extractTurnForEditing(history[2]))
        #expect(turn.text == "Second question")

        await store.sendMessage("Second question, rephrased")

        let messages = try #require(store.conversation?.messages)
        #expect(!messages.contains { $0.content == "Second question" })
        #expect(!messages.contains { $0.content == "Second answer" })
        #expect(messages.map(\.content) == [
            "First question", "First answer", "Second question, rephrased", "Done.",
        ])
        let cached = try #require(persistence.loadConversationCache())
        #expect(!cached.messages.contains { $0.content == "Second answer" })
    }

    /// **78-E (client half)** — the mechanism. After a truncation the
    /// backend's mirror IS the truncated thread, and the client was told to
    /// drop the session state that holds its own copy of the transcript.
    @Test @MainActor
    func truncationIsHandedToTheBackendMirror() async throws {
        let (store, client, history, _) = makeMirroredStore()
        await store.loadConversationIfNeeded()

        _ = store.extractTurnForEditing(history[2])

        let local = try #require(store.conversation?.messages)
        let mirrored = try #require(client.currentConversation?.messages)
        #expect(mirrored.map(\.id) == local.map(\.id))
        #expect(client.didInvalidateSession)
        #expect(client.adoptedMessageCounts == [2])
    }

    /// The residual #78 named: `regenerateReply` truncated and then returned
    /// without sending whenever `sendMessage`'s duplicate guard swallowed the
    /// byte-identical re-send — history destroyed in memory, nothing sent,
    /// nothing persisted. A swallowed re-send must leave the transcript as
    /// it found it.
    @Test @MainActor
    func regenerateRestoresHistoryWhenTheResendIsSwallowed() async throws {
        // An earlier turn identical to the one being re-rolled, still
        // pending — exactly what `hasPendingDuplicateMessage` refuses on.
        let rows = [
            Message(sender: .user, content: "Same question", status: .sending),
            Message(sender: .user, content: "Same question", status: .delivered),
            Message(sender: .hermes, content: "An answer", status: .delivered),
        ]
        let (store, client, history, persistence) = makeMirroredStore(history: rows)
        // Adopted directly rather than through `loadConversationIfNeeded`:
        // cold load finalizes a stale `.sending` row to `.failed` (#56), and
        // the guard under test is about a row that IS in flight right now.
        store.conversation = client.currentConversation
        #expect(store.conversation?.messages.first?.status == .sending)

        await store.regenerateReply(history[2])

        let messages = try #require(store.conversation?.messages)
        #expect(client.sentPrompts.isEmpty)
        #expect(messages.map(\.content) == ["Same question", "Same question", "An answer"])
        let cached = try #require(persistence.loadConversationCache())
        #expect(cached.messages.count == 3)
    }

    // MARK: - #275: a dictated turn is a producing turn

    /// **275-A** — the mixed thread. The reply was produced by a DICTATED
    /// turn; matching `.user` alone skips it, finds the earlier typed turn,
    /// and truncates far more history than the user asked for while
    /// re-sending the wrong prompt.
    @Test @MainActor
    func regenerateTruncatesFromADictatedProducingTurn() async throws {
        let rows = [
            Message(sender: .user, content: "First question", status: .delivered),
            Message(sender: .hermes, content: "First answer", status: .delivered),
            Message(sender: .voiceUser, content: "Dictated second question", status: .delivered),
            Message(sender: .hermes, content: "Second answer", status: .delivered),
        ]
        let (store, client, history, _) = makeMirroredStore(history: rows)
        await store.loadConversationIfNeeded()

        await store.regenerateReply(history[3])

        #expect(client.sentPrompts == ["Dictated second question"])
        let messages = try #require(store.conversation?.messages)
        #expect(messages.map(\.content) == [
            "First question", "First answer", "Dictated second question", "Done.",
        ])
        // The dictated row is re-sent as a normal composed turn, so the
        // earlier exchange is untouched — that is the whole point.
        #expect(messages[0].id == history[0].id)
        #expect(messages[1].id == history[1].id)
    }

    /// **275-B** — the dead menu item. With no typed turn anywhere above it,
    /// the backwards scan found nothing at all and `regenerateReply` returned
    /// silently: nothing truncated, nothing sent, no log line.
    @Test @MainActor
    func regenerateWorksOnAThreadWhoseOnlyUserTurnWasDictated() async throws {
        let rows = [
            Message(sender: .voiceUser, content: "Only dictated turn", status: .delivered),
            Message(sender: .hermes, content: "An answer", status: .delivered),
        ]
        let (store, client, history, _) = makeMirroredStore(history: rows)
        await store.loadConversationIfNeeded()

        await store.regenerateReply(history[1])

        #expect(client.sentPrompts == ["Only dictated turn"])
        let messages = try #require(store.conversation?.messages)
        #expect(messages.map(\.content) == ["Only dictated turn", "Done."])
    }

    /// **275-C** — `retryMessage` shares the assumption: a failed reply whose
    /// producing turn was dictated re-sent the last TYPED turn instead.
    @Test @MainActor
    func retryUsesADictatedProducingTurnAsItsSource() async throws {
        let rows = [
            Message(sender: .user, content: "Typed question", status: .delivered),
            Message(sender: .hermes, content: "Typed answer", status: .delivered),
            Message(sender: .voiceUser, content: "Dictated question", status: .delivered),
            Message(sender: .hermes, content: "Reply that failed", status: .failed),
        ]
        let (store, client, history, _) = makeMirroredStore(history: rows)
        await store.loadConversationIfNeeded()

        await store.retryMessage(history[3])

        #expect(client.sentPrompts == ["Dictated question"])
    }

    /// **275-D** — the regression half: widening the set to user-AUTHORED
    /// must not let an assistant, spoken-assistant, or system row be mistaken
    /// for a producing turn. Only "Q" is user-authored here, so a re-roll of
    /// the final reply must truncate from index 0 and re-send "Q" — picking
    /// the `.voiceHermes` row would re-send "Spoken reply" instead.
    @Test @MainActor
    func onlyUserAuthoredRowsCanBeProducingTurns() async throws {
        let rows = [
            Message(sender: .user, content: "Q", status: .delivered),
            Message(sender: .system, content: "[Voice session ended]", status: .delivered),
            Message(sender: .voiceHermes, content: "Spoken reply", status: .delivered),
            Message(sender: .hermes, content: "A", status: .delivered),
        ]
        let (store, client, history, _) = makeMirroredStore(history: rows)
        await store.loadConversationIfNeeded()

        await store.regenerateReply(history[3])

        #expect(client.sentPrompts == ["Q"])
        #expect(store.conversation?.messages.map(\.content) == ["Q", "Done."])
    }

    /// **275-E** — the predicate every producing-turn search now shares. A
    /// sixth sender case has to answer this question explicitly rather than
    /// be silently excluded by four separate `== .user` comparisons.
    @Test func userAuthoredCoversTypedAndDictatedTurnsOnly() {
        #expect(MessageSender.user.isUserAuthored)
        #expect(MessageSender.voiceUser.isUserAuthored)
        #expect(!MessageSender.hermes.isUserAuthored)
        #expect(!MessageSender.voiceHermes.isUserAuthored)
        #expect(!MessageSender.system.isUserAuthored)
    }

    // MARK: - #278: the in-flight gate

    /// **278-A** — a dropped stream leaves a LIVE run behind, and Edit &
    /// Resend was both offered and honored on it: it truncated under the run,
    /// and the resend posted a second run to the same server session.
    @Test @MainActor
    func editAndResendIsRefusedWhileADroppedStreamsRunIsStillLive() async throws {
        let (store, client, _, _) = makeMirroredStore(history: [])
        await store.loadConversationIfNeeded()
        client.interruptsInsteadOfFinishing = true

        await store.sendMessage("A question mid-flight")

        // The state the bug lives in: no stream, a live run, a `.working` row.
        #expect(!store.isStreaming)
        #expect(store.pendingRunSessionId == "live-session")
        let userRow = try #require(store.conversation?.messages.first)
        #expect(userRow.status == .working)

        let countBefore = store.conversation?.messages.count
        #expect(store.extractTurnForEditing(userRow) == nil)
        #expect(store.conversation?.messages.count == countBefore)
        #expect(store.conversation?.messages.contains { $0.id == userRow.id } == true)
    }

    /// **278-B** — the menu reads the same predicate, so the item is not even
    /// offered. `isStreaming` (what the menu used to read) is false here,
    /// which is the entire bug.
    @Test @MainActor
    func theBusyPredicateStaysTrueAcrossAnInterruptedRun() async throws {
        let (store, client, _, _) = makeMirroredStore(history: [])
        await store.loadConversationIfNeeded()
        client.interruptsInsteadOfFinishing = true

        await store.sendMessage("A question mid-flight")

        #expect(!store.isStreaming)
        #expect(store.isTranscriptBusy)
        // And the row's own status agrees — the belt has two independent
        // strands on purpose.
        #expect(store.conversation?.messages.first?.status.isSettled == false)
    }

    /// **278-C** — no over-tightening. A settled turn on an idle thread must
    /// still be editable; a gate that refuses everything is not a fix.
    @Test @MainActor
    func editAndResendStillWorksOnASettledTurnWithNoRunInFlight() async throws {
        let (store, _, history, _) = makeMirroredStore()
        await store.loadConversationIfNeeded()

        #expect(!store.isTranscriptBusy)
        let turn = try #require(store.extractTurnForEditing(history[2]))
        #expect(turn.text == "Second question")
        #expect(store.conversation?.messages.count == 2)
    }

    // MARK: - #281: the surplus content claim

    /// **281-C** — fixture fidelity, and it is pinned as a bar because two
    /// doubles in a row have now certified broken behaviour in this exact
    /// function. The Hermes-shaped mirror must produce what
    /// `SessionsHermesClient.mapStoredMessage` produces — **no**
    /// `clientMessageID` on any row — and must NOT append the turn it just
    /// sent, because a fetch cache is not an append log. The fixture must
    /// also be able to FIRE a content claim at all: the four-distinct-strings
    /// history the #78 pins use cannot, whatever else it proves.
    @Test @MainActor
    func theHermesShapedMirrorMatchesTheRealFetchCache() async throws {
        let rows = repeatedPromptServerHistory()
        let userContents = rows.filter { $0.sender == .user }.map(\.content)
        #expect(Set(userContents).count < userContents.count)   // a claim CAN fire
        #expect(rows.allSatisfy { $0.clientMessageID == nil })   // server-transcript shape

        let (store, client, _, _) = makeMirroredStore(history: rows, shape: .hermesFetchCache)
        await store.loadConversationIfNeeded()
        await store.sendMessage("How many are left")

        #expect(client.sentPrompts == ["How many are left"])
        let mirrored = try #require(client.currentConversation?.messages)
        #expect(mirrored.allSatisfy { $0.clientMessageID == nil })
        // Not an append log: the sent turn is absent until the next fetch.
        #expect(mirrored.count == rows.count)
    }

    /// **281-B** — the case that failed 78-F on Owen's device. A thread
    /// reopened from the drawer (every row `clientMessageID == nil`) in which
    /// the SAME prompt was sent twice. Regenerating the second reply re-sends
    /// that prompt — and the fresh user row was eaten by a content claim the
    /// already-id-confirmed historical row had minted, so there was no new
    /// row at all. *"It didn't show the current time for when I actually
    /// regenerated it."*
    @Test @MainActor
    func aRepeatedPromptsRegenerateKeepsItsFreshUserRow() async throws {
        let rows = repeatedPromptServerHistory()
        let (store, client, history, _) = makeMirroredStore(history: rows, shape: .hermesFetchCache)
        await store.loadConversationIfNeeded()

        await store.regenerateReply(history[3])

        #expect(client.sentPrompts == ["How many are left"])
        let messages = try #require(store.conversation?.messages)
        #expect(messages.map(\.content) == [
            "How many are left", "Five.", "How many are left", "Done.",
        ])
        // And it is a NEW row, not the surviving historical twin — which is
        // the half the screen showed Owen: same text, stale timestamp.
        let userRows = messages.filter { $0.sender == .user }
        #expect(userRows.count == 2)
        let fresh = try #require(userRows.last)
        #expect(!history.contains { $0.id == fresh.id })
        #expect(fresh.timestamp > history[2].timestamp)
    }

    // MARK: - #276: mergeAttachments drops nothing

    private func anchoredAttachment(id: UUID, anchor: Int?) -> MessageAttachment {
        MessageAttachment(
            id: id,
            kind: "file",
            fileName: "notes.md",
            mimeType: "text/markdown",
            thumbnailBase64: "THUMB",
            localStoragePath: "/staged/notes.md",
            voiceMemoAudioPath: "/staged/memo.m4a",
            remotePath: "O:/Hermes/notes.md",
            remoteProfileID: UUID(),
            anchorOffset: anchor
        )
    }

    /// **276-A** — the field the #262 lane added and this merge forgot. Any
    /// refresh merge demoted an anchored chip back to the trailing grid.
    @Test @MainActor
    func mergeAttachmentsPreservesTheInlineAnchor() throws {
        let id = UUID()
        let local = anchoredAttachment(id: id, anchor: 42)
        let remote = MessageAttachment(id: id, kind: "file", fileName: "notes.md", mimeType: "text/markdown")

        let merged = try #require(ChatStore.mergeAttachments([local], onto: [remote]).first)

        #expect(merged.anchorOffset == 42)
    }

    /// **276-B** — the whole preserved shape, not just the new field. A
    /// field-by-field rebuild is exactly how the anchor was lost, so every
    /// client-side field this merge is supposed to carry is pinned here.
    @Test @MainActor
    func mergeAttachmentsPreservesEveryClientSideField() throws {
        let id = UUID()
        let local = anchoredAttachment(id: id, anchor: 7)
        let remote = MessageAttachment(id: id, kind: "file", fileName: "notes.md", mimeType: "text/markdown")

        let merged = try #require(ChatStore.mergeAttachments([local], onto: [remote]).first)

        #expect(merged.id == id)
        #expect(merged.kind == "file")
        #expect(merged.fileName == "notes.md")
        #expect(merged.mimeType == "text/markdown")
        #expect(merged.thumbnailBase64 == "THUMB")
        #expect(merged.localStoragePath == "/staged/notes.md")
        #expect(merged.voiceMemoAudioPath == "/staged/memo.m4a")
        #expect(merged.remotePath == "O:/Hermes/notes.md")
        #expect(merged.remoteProfileID == local.remoteProfileID)
        #expect(merged.anchorOffset == 7)
    }

    // MARK: - #203 (1A) the stall hint's WIRING

    /// The predicate is pinned in `DeviceToolBeltTests`; this pins the half
    /// that actually made 1A ship broken — whether the store's activity stamp
    /// is refreshed by real stream events.
    ///
    /// **The simulator cannot verify this feature end to end:**
    /// FoundationModels ships no assets there, so an on-device turn fails
    /// instantly instead of entering the sustained streaming state the hint
    /// watches for (confirmed on the 27.0 sim, 2026-07-31). A scripted stream
    /// is not a shortcut here — it is the only deterministic way to drive the
    /// state machine.
    @MainActor @Test func streamActivityStampIsRefreshedByRealStreamEvents() async {
        let client = ImmediateReplyClient()
        client.script = [
            .textDelta("Hello"),
            .finished(Message(sender: .hermes, content: "Hello", status: .delivered), nil, nil),
        ]
        let store = ChatStore(hermesClient: client, persistence: makePersistence())
        await store.loadConversationIfNeeded()

        let before = Date()
        await store.sendMessage("hi")
        let stamp = try! #require(store.lastStreamActivityAt)
        // The delta advanced it, so the stamp tracks ACTIVITY rather than
        // merely being set once at send time.
        #expect(stamp >= before)
        // Fresh stamp → not stalled; past the threshold → stalled. That
        // transition is exactly what the UI renders.
        #expect(!ChatStore.isStalled(isStreaming: true, lastActivityAt: stamp, now: stamp))
        #expect(ChatStore.isStalled(
            isStreaming: true, lastActivityAt: stamp,
            now: stamp.addingTimeInterval(ChatStore.stallHintAfter + 1)))
    }

}
