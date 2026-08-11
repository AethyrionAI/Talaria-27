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

        /// **#279 (bar 279-E): the capability this double did not have.** It
        /// could interrupt a turn but not FAIL one, so the shape #279 lives
        /// in — a turn that dies *after* its user row is already in the
        /// mirror — was not expressible here at all.
        ///
        /// Models `LocalChatBackend`'s GENERATION failure specifically
        /// (`LocalChatBackend.swift:646`, inside the streaming loop's
        /// `catch`): `appendUserMessage` (`:525`) has already run, so the user
        /// row IS mirrored, and the turn then dies before
        /// `appendAssistantMessage` is ever reached, so no reply is. That
        /// asymmetry is the whole defect. It deliberately does NOT model the
        /// availability gate (`:493-497`), which yields `.failed` and returns
        /// BEFORE `appendUserMessage` and therefore mirrors nothing.
        ///
        /// **One-shot: consumed by the turn it fails.** A retry of that turn
        /// has to succeed or there is no second turn to merge against, which
        /// is the entire scenario. (The dispatch proposed the plain name
        /// `failsAfterMirroringTheUserRow`; renamed so the name says
        /// "next turn" out loud rather than reading as a sticky mode.)
        var failsNextTurnAfterMirroringTheUserRow = false

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
            // #279 (279-E): the generation-failure shape. The user row is
            // mirrored — `appendUserMessage` has already run — and then the
            // turn dies, so no reply is. No `.messageSent` first, because
            // `LocalChatBackend` never yields one: that is what makes
            // ChatStore's `acceptedJobID == nil` branch (`:995`) run, which
            // is the branch that renders the failed user row plus a `.system`
            // error row and offers retry.
            if failsNextTurnAfterMirroringTheUserRow {
                failsNextTurnAfterMirroringTheUserRow = false
                mirror(message: message, attachments: attachments, clientMessageID: clientMessageID, reply: nil)
                return AsyncStream { continuation in
                    continuation.yield(.failed("generation failed"))
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
        ///
        /// **#279:** `reply` is optional because the two halves are two
        /// separate calls in production (`appendUserMessage` before the
        /// generation, `appendAssistantMessage` after it) and a failed turn
        /// makes only the first. Passing `nil` mirrors the user row alone.
        private func mirror(
            message: String,
            attachments: [PendingAttachment],
            clientMessageID: UUID,
            reply: Message?
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
            // #279: `appendAssistantMessage`'s half — skipped entirely on a
            // failed turn, exactly as `LocalChatBackend` skips it.
            if let reply {
                currentConversation?.messages.append(reply)
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
    ///
    /// **#279 (2026-08-09): this bar covers the SOURCE SELECTION only, and
    /// said nothing about the removal that precedes it.** At the time this
    /// was written `retryMessage` deleted the failed row with a bare
    /// `conversation.messages.removeAll` that never reached the backend's
    /// mirror, so the retried turn's own post-turn merge resurrected it —
    /// and this test's single `sentPrompts` assertion could not see that.
    /// The removal now exits through `adoptLocalTranscript()`; the bars that
    /// pin it are 279-A..E, below.
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

    // MARK: - tracker #282: scoping the content claim's DEMAND side
    //
    // Tracker #282 is NOT GitHub PR #282. Owen's 2026-08-09 ruling: only a
    // local row where `!status.isSettled` may consume a content claim.

    /// tracker #282's server-transcript builder — what
    /// `SessionsHermesClient.mapStoredMessage` actually produces for a thread
    /// the host has stored: a STABLE server-derived id (#237), **no**
    /// `clientMessageID` (the gateway echoes none), `.delivered`, and the
    /// HOST's own clock, which is a different clock from the phone's. The
    /// clock is the load-bearing detail — `Conversation.dedupingAdoptedEchoes`
    /// keys on the timestamp, so a fixture that reuses the local one hides
    /// every duplicate this seam can produce.
    private func serverTranscript(
        _ rows: [(MessageSender, String)],
        sessionID: String = "tracker-282-session",
        base: Date
    ) -> [Message] {
        rows.enumerated().map { index, row in
            Message(
                id: SessionsHermesClient.stableMessageID(sessionId: sessionID, serverRowID: index + 1),
                sender: row.0,
                content: row.1,
                timestamp: base.addingTimeInterval(Double(index)),
                status: .delivered
            )
        }
    }

    /// A two-turn thread born IN-APP on the Hermes path: client-minted ids,
    /// `clientMessageID` on every user row, both turns settled `.delivered`
    /// (`ChatStore.swift:883` / `:1363` are the two lines that settle them).
    /// None of these rows has ever met the server.
    private func inAppHermesHistory(base: Date) -> [Message] {
        let firstUser = UUID(), secondUser = UUID()
        return [
            Message(id: firstUser, clientMessageID: firstUser, sender: .user,
                    content: "Q1", timestamp: base, status: .delivered),
            Message(sender: .hermes, content: "A1",
                    timestamp: base.addingTimeInterval(1), status: .delivered),
            Message(id: secondUser, clientMessageID: secondUser, sender: .user,
                    content: "Q2", timestamp: base.addingTimeInterval(2), status: .delivered),
            Message(sender: .hermes, content: "A2",
                    timestamp: base.addingTimeInterval(3), status: .delivered),
        ]
    }

    /// **282-B — THE BASELINE, and since 2026-08-10 also bar 299-A.** A
    /// characterization: it records what the Hermes-path reconcile merge
    /// produces, so that every other tracker #282 result is read against a
    /// measured array rather than an assumed one.
    ///
    /// The shape is `attemptReconcile`'s: the WHOLE local transcript merged
    /// onto the WHOLE server transcript. Rows born in-app carry client ids,
    /// so tiers 1 and 2 both miss them and the content claim is the only
    /// confirmation a user row has.
    ///
    /// **HISTORY (superseded 2026-08-10 by tracker #299's fix): as measured
    /// at `12ed25b` this baseline contained ASSISTANT duplicates —
    /// `["Q1", "A1", "Q2", "A2", "A1", "A2"]`.** A `.hermes` row born in-app
    /// had NO confirmation tier at all: it failed tier 1 (client id ≠ the
    /// host's `stableMessageID`), failed tier 2 (the gateway echoes no
    /// `clientMessageID`), was not eligible for tier 3, survived, and was
    /// appended — and `Conversation.dedupingAdoptedEchoes` cannot collapse
    /// the pair because the phone's clock and the host's are different
    /// clocks. That finding was filed as tracker #299, and #299's
    /// adoption-time identity (`ChatStore.serverIdentityAdoptions`) now
    /// confirms those rows by turn structure, so the assertion below pins the
    /// CLEAN array. The claim-tier half of the story is unchanged: the two
    /// user rows are single ONLY because the content claim absorbs them —
    /// precisely the mechanism tracker #282's ruling removes for settled
    /// rows (assistant rows do not depend on it; their turn anchoring is
    /// #299's own and consumes no claims).
    @Test @MainActor
    func theHermesReconcileMergeBaselineBeforeScopingTheClaim() async throws {
        let localBase = Date(timeIntervalSince1970: 1_754_000_000)
        let (store, client, _, _) = makeMirroredStore(
            history: inAppHermesHistory(base: localBase), shape: .hermesFetchCache
        )
        await store.loadConversationIfNeeded()

        client.currentConversation = Conversation(
            title: Conversation.defaultTitle,
            messages: serverTranscript(
                [(.user, "Q1"), (.hermes, "A1"), (.user, "Q2"), (.hermes, "A2")],
                base: localBase.addingTimeInterval(0.5)
            )
        )

        await store.loadConversation()

        let messages = try #require(store.conversation?.messages)
        #expect(messages.map(\.content) == ["Q1", "A1", "Q2", "A2"])
    }

    /// **tracker #299 evidence, then bar 299-B — the merge is IDEMPOTENT
    /// across a second fetch.** As filed this test measured whether the
    /// assistant duplication was BOUNDED (#237's corruption COMPOUNDED,
    /// 32 → 128, so severity turned on it): one extra copy per row, then
    /// stable. **Superseded 2026-08-10 by #299's fix** — the first merge now
    /// adopts the host's identity for the in-app assistant rows too, so
    /// `afterFirst` pins the CLEAN array and this test's remaining job is
    /// the boundedness half: a second reconcile against the same host
    /// transcript changes nothing. `stableMessageID` is deterministic
    /// (#237), so the re-fetch reproduces the same ids, the first merge's
    /// adopted rows confirm at tier 1, and #281's supply gate mints no
    /// claims at all.
    @Test @MainActor
    func theHermesReconcileMergeDoesNotCompoundAcrossASecondFetch() async throws {
        let localBase = Date(timeIntervalSince1970: 1_754_000_000)
        let (store, client, _, _) = makeMirroredStore(
            history: inAppHermesHistory(base: localBase), shape: .hermesFetchCache
        )
        await store.loadConversationIfNeeded()

        let hostView = Conversation(
            title: Conversation.defaultTitle,
            messages: serverTranscript(
                [(.user, "Q1"), (.hermes, "A1"), (.user, "Q2"), (.hermes, "A2")],
                base: localBase.addingTimeInterval(0.5)
            )
        )

        client.currentConversation = hostView
        await store.loadConversation()
        let afterFirst = try #require(store.conversation?.messages).map(\.content)

        // The same rows, re-fetched: same server row ids ⇒ same stable ids.
        client.currentConversation = hostView
        await store.loadConversation()
        let afterSecond = try #require(store.conversation?.messages).map(\.content)

        #expect(afterFirst == ["Q1", "A1", "Q2", "A2"])
        #expect(afterSecond == afterFirst)
    }

    /// **299-C** — a drawer-reopened thread (every row already carrying the
    /// host's `stableMessageID`) merges IDENTICALLY before and after the #299
    /// adoption pass: everything confirms at tier 1, so there is nothing
    /// locally born for the adoption to pair, and the merged rows keep the
    /// exact ids the host minted. Verified green against unmodified
    /// production first, then again with the fix — the pin is "no change on
    /// tier 1's path", not a new behaviour.
    @Test @MainActor
    func aDrawerReopenedThreadMergesIdenticallyWithNothingToAdopt() async throws {
        let localBase = Date(timeIntervalSince1970: 1_754_000_000)
        let hostRows = serverTranscript(
            [(.user, "Q1"), (.hermes, "A1"), (.user, "Q2"), (.hermes, "A2")],
            base: localBase
        )
        let (store, client, _, _) = makeMirroredStore(history: hostRows, shape: .hermesFetchCache)
        await store.loadConversationIfNeeded()

        client.currentConversation = Conversation(
            title: Conversation.defaultTitle, messages: hostRows
        )
        await store.loadConversation()

        let messages = try #require(store.conversation?.messages)
        #expect(messages.map(\.content) == ["Q1", "A1", "Q2", "A2"])
        #expect(messages.map(\.id) == hostRows.map(\.id))
    }

    /// **299-D** — adopted identity survives persistence: save → cold load →
    /// re-reconcile, still no duplicates (the #277/#278 corruption family's
    /// standard round-trip check). The merge's output rows carry the host's
    /// stable ids, so a process death between reconciles must not resurrect
    /// the client ids and re-open the seam — the reborn store's re-reconcile
    /// has to confirm everything at tier 1 with nothing left to adopt.
    @Test @MainActor
    func adoptedIdentitySurvivesAColdLoadAndAReReconcile() async throws {
        let localBase = Date(timeIntervalSince1970: 1_754_000_000)
        let (store, client, _, persistence) = makeMirroredStore(
            history: inAppHermesHistory(base: localBase), shape: .hermesFetchCache
        )
        await store.loadConversationIfNeeded()

        let hostView = Conversation(
            title: Conversation.defaultTitle,
            messages: serverTranscript(
                [(.user, "Q1"), (.hermes, "A1"), (.user, "Q2"), (.hermes, "A2")],
                base: localBase.addingTimeInterval(0.5)
            )
        )
        client.currentConversation = hostView
        await store.loadConversation()   // adopts + persists the merged rows

        // Cold load: a fresh store over the same persistence and client.
        let reborn = ChatStore(hermesClient: client, persistence: persistence)
        await reborn.loadConversationIfNeeded()
        client.currentConversation = hostView
        await reborn.loadConversation()  // re-reconcile after the cold start

        let messages = try #require(reborn.conversation?.messages)
        #expect(messages.map(\.content) == ["Q1", "A1", "Q2", "A2"])
        #expect(messages.map(\.id) == hostView.messages.map(\.id))
    }

    /// **282-D — the settled-historical hole. PREDICTED RED under the
    /// ruling.** A thread whose first turn SETTLED in-app and never met the
    /// server, and whose second turn is mid-recovery. A user row born in-app
    /// carries a client UUID; its server twin carries `stableMessageID` and
    /// no `clientMessageID`, so tiers 1 and 2 both miss and the content claim
    /// is the ONLY confirmation it has. Under the guard a `.delivered` row
    /// can no longer consume, survives, and is appended at the tail — a
    /// second "Q1" bubble below the reply.
    ///
    /// Deliberately scoped to USER rows: assistant rows have no claim tier at
    /// all, so folding them in here would mix the guard's effect with the
    /// separate A2 question 282-B measures.
    @Test @MainActor
    func aSettledInAppUserRowIsNotDuplicatedByTheReconcileMerge() async throws {
        let localBase = Date(timeIntervalSince1970: 1_754_000_000)
        let firstUser = UUID(), recoveringUser = UUID()
        let localRows = [
            Message(id: firstUser, clientMessageID: firstUser, sender: .user,
                    content: "Q1", timestamp: localBase, status: .delivered),
            Message(sender: .hermes, content: "A1",
                    timestamp: localBase.addingTimeInterval(1), status: .delivered),
            Message(id: recoveringUser, clientMessageID: recoveringUser, sender: .user,
                    content: "Q2", timestamp: localBase.addingTimeInterval(2), status: .working),
        ]
        let (store, client, _, _) = makeMirroredStore(history: localRows, shape: .hermesFetchCache)
        await store.loadConversationIfNeeded()

        client.currentConversation = Conversation(
            title: Conversation.defaultTitle,
            messages: serverTranscript(
                [(.user, "Q1"), (.hermes, "A1"), (.user, "Q2")],
                base: localBase.addingTimeInterval(0.5)
            )
        )

        await store.loadConversation()

        let messages = try #require(store.conversation?.messages)
        let userContents = messages.filter { $0.sender == .user }.map(\.content)
        #expect(Set(userContents).count == userContents.count)
    }

    /// tracker #282 case (b): what `mapStoredMessage` produces for a stored
    /// row the host returned with **no `id` and no `timestamp`** —
    /// `SessionsHermesClient.swift:1031` falls back to a fresh `UUID()` and
    /// `:1000` to a fresh `.now`. Both fallbacks are honest; both are
    /// PER-FETCH, which is the whole of case (b). `stampedAt` makes the
    /// per-fetch clock deterministic instead of racing the test runner.
    private func idLessServerTranscript(
        _ rows: [(MessageSender, String)], stampedAt: Date
    ) -> [Message] {
        rows.enumerated().map { index, row in
            Message(id: UUID(), sender: row.0, content: row.1,
                    timestamp: stampedAt.addingTimeInterval(Double(index)), status: .delivered)
        }
    }

    /// **282-E — case (b). PREDICTED RED under the ruling.** A fresh `UUID()`
    /// is never in `localIDs`, so #281's supply gate at the claim's SOURCE can
    /// never bind for an id-less row: it mints a claim on every fetch,
    /// forever. Today the claim tier absorbs that (a silent swallow). Under
    /// the guard the row's previously-adopted local twin is `.delivered`
    /// (`SessionsHermesClient.swift:1035`) and therefore settled, so nothing
    /// consumes the claim and nothing filters the twin — and
    /// `Conversation.dedupingAdoptedEchoes` cannot collapse the pair because
    /// their timestamps differ. **A silent swallow becomes a duplicate per
    /// fetch.**
    @Test @MainActor
    func anIDLessServerRowDoesNotGrowTheUserRowsAcrossTwoFetches() async throws {
        let (store, client, _, _) = makeMirroredStore(history: [], shape: .hermesFetchCache)
        await store.loadConversationIfNeeded()

        let firstFetchAt = Date(timeIntervalSince1970: 1_754_000_000)
        client.currentConversation = Conversation(
            title: Conversation.defaultTitle,
            messages: idLessServerTranscript([(.user, "Q1"), (.hermes, "A1")], stampedAt: firstFetchAt)
        )
        await store.loadConversation()
        let afterFirst = try #require(store.conversation?.messages)
            .filter { $0.sender == .user }.count

        // The SAME two stored rows, re-fetched. The host still sends no id
        // and no timestamp, so the mapper mints both again.
        client.currentConversation = Conversation(
            title: Conversation.defaultTitle,
            messages: idLessServerTranscript(
                [(.user, "Q1"), (.hermes, "A1")], stampedAt: firstFetchAt.addingTimeInterval(10)
            )
        )
        await store.loadConversation()
        let afterSecond = try #require(store.conversation?.messages)
            .filter { $0.sender == .user }.count

        #expect(afterFirst == 1)
        #expect(afterSecond == afterFirst)
    }

    /// **282-F — PLACEMENT, and the lane states its answer rather than
    /// discovering it on device.** The merge APPENDS survivors
    /// (`ChatStore.swift:2741`), so the `.failed` row the ruling saves comes
    /// back at the BOTTOM of the transcript, not above the successful retry.
    ///
    /// **The answer pinned here: tail placement is ACCEPTED and DOCUMENTED
    /// for this change.** Reinserting a survivor in place is a second
    /// production edit the ruling does not authorise and that no bar has
    /// measured. This bar exists so that the placement is a recorded decision
    /// with a test behind it instead of a surprise in a device pass.
    ///
    /// Pre-change this is RED for an instructive reason: the content array is
    /// IDENTICAL either way — what changes is WHICH row is last. Today the
    /// failed row is eaten and the in-flight successor is the tail survivor.
    ///
    /// **WATCHED RED 2026-08-09 against unmodified production, verbatim:**
    /// ```
    /// ✘ ... recorded an issue at ChatStorePersistenceTests.swift:1117:9:
    ///   Expectation failed: tail.id == failedID
    /// ↳ tail.id → A543439B-2ED2-434E-BED9-2E0A1A1941E7
    /// ↳ failedID → E52B1028-E8AE-4BE9-AD8C-14C9DCDFE393
    /// ✘ ... recorded an issue at ChatStorePersistenceTests.swift:1118:9:
    ///   Expectation failed: tail.status == .failed
    /// ↳ tail.status → .working
    /// ```
    /// Note the first `#expect` — the content array — PASSED both times.
    /// `["X", "reply", "X"]` is produced either way; only the identity of the
    /// tail row moves. A content-only bar here would have been green for the
    /// wrong reason.
    ///
    /// **RE-ENABLED 2026-08-11 by the RANKING lane.** The retry here is
    /// `.working` — in flight — so under Owen's ruled ranking it outranks the
    /// settled `.failed` row for the single claim, the failed row survives,
    /// and it lands at the tail. Assertions byte-unchanged from the
    /// 2026-08-09 run quoted above; **re-watched RED against unmodified
    /// production 2026-08-11** before the ranking landed.
    @Test @MainActor
    func theSurvivingFailedRowIsAppendedAtTheTail() async throws {
        let localBase = Date(timeIntervalSince1970: 1_754_000_000)
        let failedID = UUID(), retryID = UUID()
        let localRows = [
            Message(id: failedID, clientMessageID: failedID, sender: .user,
                    content: "X", timestamp: localBase, status: .failed),
            Message(id: retryID, clientMessageID: retryID, sender: .user,
                    content: "X", timestamp: localBase.addingTimeInterval(5), status: .working),
        ]
        let (store, client, _, _) = makeMirroredStore(history: localRows, shape: .hermesFetchCache)
        await store.loadConversationIfNeeded()

        // The host stored only the turn that succeeded, plus its reply.
        client.currentConversation = Conversation(
            title: Conversation.defaultTitle,
            messages: serverTranscript(
                [(.user, "X"), (.hermes, "reply")], base: localBase.addingTimeInterval(6)
            )
        )

        await store.loadConversation()

        let messages = try #require(store.conversation?.messages)
        #expect(messages.map(\.content) == ["X", "reply", "X"])
        let tail = try #require(messages.last)
        #expect(tail.id == failedID)
        #expect(tail.status == .failed)
    }

    // MARK: - #279: a retry's removal has to reach the backend mirror

    /// A thread whose only turn failed *after* its user row was mirrored —
    /// the one #279 shape. Returns the store, the double, and the failed user
    /// row the retry affordance would be attached to.
    ///
    /// `history: []` on purpose: the merged user-row COUNT is what 279-A and
    /// 279-B assert, so the fixture must contribute no user rows of its own.
    @MainActor
    private func makeFailedLocalBrainTurn(
        prompt: String = "A question that fails"
    ) async throws -> (ChatStore, MirroringReplyClient, Message) {
        let (store, client, _, _) = makeMirroredStore(history: [])
        await store.loadConversationIfNeeded()
        client.failsNextTurnAfterMirroringTheUserRow = true

        await store.sendMessage(prompt)

        let failed = try #require(store.conversation?.messages.first)
        #expect(failed.sender == .user)
        #expect(failed.status == .failed)
        return (store, client, failed)
    }

    /// **279-E** — fixture fidelity, pinned FIRST and for the same reason
    /// 281-C is: two doubles in a row have now certified broken behaviour in
    /// this seam by being unable to express the production shape at all.
    ///
    /// **Recorded honestly: this pin was never RED for a defect.** Its "RED"
    /// was that `MirroringReplyClient` could not fail a turn — the capability
    /// did not exist — so the shape #279 lives in was unreachable from this
    /// file. It is green on both sides of the fix by construction; what it
    /// buys is that 279-A/B are measuring `LocalChatBackend`'s real failure
    /// shape rather than an invented one.
    ///
    /// Three claims, each traced to the production line it mirrors:
    /// (i) the user row carries `id == clientMessageID` AND `clientMessageID`,
    ///     `.delivered` — `LocalChatBackend.swift:1318-1338`;
    /// (ii) a failed turn mirrors NO reply — the generation `catch` at `:646`
    ///     returns before `appendAssistantMessage` (`:1340`) is reached;
    /// (iii) every `adoptTruncatedConversation` call is recorded, so 279-B can
    ///     prove the mirror was TOLD rather than that the count merely came
    ///     out right.
    @Test @MainActor
    func theFailingLocalBrainMirrorMatchesTheRealAppendLog() async throws {
        let (store, client, failed) = try await makeFailedLocalBrainTurn()

        // (i)
        let mirrored = try #require(client.currentConversation?.messages)
        #expect(mirrored.count == 1)
        let mirroredRow = try #require(mirrored.first)
        #expect(mirroredRow.sender == .user)
        #expect(mirroredRow.content == "A question that fails")
        #expect(mirroredRow.clientMessageID == mirroredRow.id)
        #expect(mirroredRow.status == .delivered)
        // (ii)
        #expect(!mirrored.contains { $0.sender == .hermes })
        // (iii) — nothing has adopted yet; the removal is what should.
        #expect(client.adoptedMessageCounts.isEmpty)

        // And the rendered shape the retry affordance actually sees: the
        // failed user row followed by the `.system` error row that replaced
        // the streaming placeholder (`ChatStore.swift:995-1000`, `:1012`).
        let local = try #require(store.conversation?.messages)
        #expect(local.map(\.sender) == [.user, .system])
        #expect(local.first?.id == failed.id)
        #expect(local.last?.content == "generation failed")
    }

    /// **279-A** — the characterization baseline. Written and run GREEN
    /// against UNMODIFIED production first, so 279-B's RED means something.
    ///
    /// The number it records is the merged transcript's user-row count after
    /// a failed turn is retried and the retried turn settles. **Pre-fix: 2.**
    /// Post-fix: 1. If the pre-fix number had been anything but 2, the
    /// mechanism in #279 would have been wrong and the lane was to stop.
    ///
    /// (The dispatch proposed the name
    /// `aRetriedFailedTurnLeavesTheMirrorHoldingTheOldRow`; renamed because
    /// the name has to stay true on BOTH sides of a fix that deliberately
    /// moves the number. The assertion below moves 2 → 1 with the fix and
    /// both numbers are quoted, here and in `OPEN_ITEMS.md` #279.)
    @Test @MainActor
    func aRetriedFailedTurnsMergedUserRowCount() async throws {
        let (store, _, failed) = try await makeFailedLocalBrainTurn()

        await store.retryMessage(failed)

        let messages = try #require(store.conversation?.messages)
        let userRows = messages.filter { $0.sender == .user }
        // **2 → 1.** The baseline run against unmodified production asserted
        // `== 2` and was GREEN: the mirror re-served the removed row on the
        // post-turn merge. The fix moves it to 1. Both numbers are recorded
        // in `OPEN_ITEMS.md` #279.
        #expect(userRows.count == 1)
    }

    /// **279-B** — the defect. `retryMessage` removed the failed row from
    /// `conversation.messages` directly and never told the backend's mirror,
    /// so the post-turn merge — which takes that mirror as its BASE ordering
    /// (`ChatStore.swift:886-889`) — put the removed turn straight back,
    /// above the retried copy. Two identical user bubbles.
    ///
    /// The id assertion is the half that matters: the survivor must be the
    /// row the RETRY minted, not the resurrected original wearing the same
    /// text. The adopt assertion is the mechanism — a count that came out
    /// right for some other reason is not this fix.
    ///
    /// **Scope (correction 4 on the entry):** this is total on the LOCAL
    /// BRAIN only. `SessionsHermesClient`'s mirror is a fetch cache
    /// (`SessionsHermesClient.swift:766-768`); on the Hermes path the fix
    /// stops the CACHE re-serving the row and the gateway session still holds
    /// the turn — the documented `/retry` caveat (`ChatStore.swift:1823-1829`).
    @Test @MainActor
    func aRetryLeavesExactlyOneUserRowForTheRetriedText() async throws {
        let (store, client, failed) = try await makeFailedLocalBrainTurn()

        await store.retryMessage(failed)

        let messages = try #require(store.conversation?.messages)
        let retried = messages.filter { $0.sender == .user && $0.content == "A question that fails" }
        #expect(retried.count == 1)
        #expect(retried.first?.id != failed.id)
        // The mirror was TOLD — the removal ran through the adoption tail.
        #expect(!client.adoptedMessageCounts.isEmpty)
        #expect(!(client.currentConversation?.messages.contains { $0.id == failed.id } ?? true))
    }

    /// **279-C** — the second defect in the same eight lines, and the one the
    /// tracker filing did not mention. The removal at `:1739` was
    /// unconditional while the re-send at `:1757` discarded `sendMessage`'s
    /// `Bool`. When the duplicate guard (`:2211`) swallowed the re-send — a
    /// byte-identical turn still `.sending` or `.queued` elsewhere in the
    /// thread — the failed row was deleted and **nothing was sent**.
    ///
    /// This is exactly the residual `regenerateReply` was given
    /// `restoreTruncatedRows(_:at:)` for (`:1858-1864`) and `retryMessage`
    /// never got. Same fixture shape as
    /// `regenerateRestoresHistoryWhenTheResendIsSwallowed`.
    @Test @MainActor
    func aSwallowedRetryPutsTheFailedRowBack() async throws {
        let base = Date(timeIntervalSince1970: 1_754_100_000)
        let rows = [
            // Still in flight — this is what `hasPendingDuplicateMessage`
            // refuses on, and it is byte-identical to the failed row below.
            Message(sender: .user, content: "Same question", timestamp: base, status: .sending),
            Message(sender: .user, content: "Same question",
                    timestamp: base.addingTimeInterval(1), status: .failed),
            Message(sender: .system, content: "generation failed",
                    timestamp: base.addingTimeInterval(2), status: .failed),
        ]
        let (store, client, history, persistence) = makeMirroredStore(history: rows)
        // Adopted directly rather than through `loadConversationIfNeeded`:
        // cold load finalizes a stale `.sending` row to `.failed` (#56), and
        // the guard under test is about a row that IS in flight right now.
        store.conversation = client.currentConversation
        #expect(store.conversation?.messages.first?.status == .sending)

        await store.retryMessage(history[1])

        #expect(client.sentPrompts.isEmpty)
        let messages = try #require(store.conversation?.messages)
        #expect(messages.contains { $0.id == history[1].id })
        #expect(messages.map(\.content) == ["Same question", "Same question", "generation failed"])
        let cached = try #require(persistence.loadConversationCache())
        #expect(cached.messages.count == 3)
    }

    /// **279-D** — no over-reach, and the bar that fails if #279's own filing
    /// is implemented literally. Its "route it through the primitive" reads
    /// as `truncateTranscript(from:)`, which removes `index...` **to the end
    /// of the transcript** — that would delete every turn below the retried
    /// one.
    ///
    /// A mid-transcript `.failed` row is a production shape, not a contrived
    /// one: `finalizeStaleSendsFromCache` (`ChatStore.swift:502-511`, #56)
    /// manufactures exactly this on every cold load after a mid-stream death,
    /// and the retry affordance carries no "is it the last row" condition
    /// (`MessageBubble.swift:211`).
    @Test @MainActor
    func retryingAMidTranscriptFailedRowKeepsEverythingBelowIt() async throws {
        let base = Date(timeIntervalSince1970: 1_754_200_000)
        let rows = [
            Message(sender: .user, content: "Failed question", timestamp: base, status: .failed),
            Message(sender: .user, content: "Second question",
                    timestamp: base.addingTimeInterval(1), status: .delivered),
            Message(sender: .hermes, content: "Second answer",
                    timestamp: base.addingTimeInterval(2), status: .delivered),
            Message(sender: .user, content: "Third question",
                    timestamp: base.addingTimeInterval(3), status: .delivered),
            Message(sender: .hermes, content: "Third answer",
                    timestamp: base.addingTimeInterval(4), status: .delivered),
        ]
        let (store, client, history, _) = makeMirroredStore(history: rows)
        await store.loadConversationIfNeeded()

        await store.retryMessage(history[0])

        #expect(client.sentPrompts == ["Failed question"])
        let messages = try #require(store.conversation?.messages)
        // Everything below the retried row survives, in order, and the
        // retried turn lands at the tail where it was just sent.
        #expect(messages.map(\.content) == [
            "Second question", "Second answer", "Third question", "Third answer",
            "Failed question", "Done.",
        ])
        #expect(messages[0].id == history[1].id)
        #expect(messages[1].id == history[2].id)
        #expect(messages[2].id == history[3].id)
        #expect(messages[3].id == history[4].id)
        // The resurrected original is gone — not merely outnumbered.
        #expect(!messages.contains { $0.id == history[0].id })
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

    // MARK: - #296 bar E — the marker must not cost anyone their history

    /// #296 bar E. `ToolActivity` gained a `failure` field, and `ToolActivity`
    /// has **no hand-written `init(from:)`** — Swift's synthesized one does
    /// NOT apply property defaults, so a non-optional field would make every
    /// blob written before this change throw `keyNotFound`. That throw
    /// propagates all the way out (`Message.init(from:)` uses
    /// `decodeIfPresent` for the ARRAY, which only tolerates a missing key —
    /// a present-but-undecodable element still throws), and
    /// `UserDefaultsAppPersistenceStore.load` catches it and returns nil.
    /// The user's whole transcript would vanish: the #42 silent-wipe shape.
    ///
    /// So the fixture below is **hand-written on purpose** rather than
    /// round-tripped through the encoder. A round-trip would prove nothing:
    /// with `failure` nil, `JSONEncoder` omits the key anyway, so the bytes
    /// would be identical whether the field were optional or not, and the
    /// test would pass against the very declaration it exists to reject.
    /// This blob is the CURRENT (pre-#296) schema, byte-for-byte, and it must
    /// still round-trip to a full conversation.
    ///
    /// **Watched RED before it was trusted:** with `var failure: String = ""`
    /// declared non-optional, this test fails on
    /// `keyNotFound(CodingKeys(stringValue: "failure"...))`.
    @Test @MainActor
    func legacyToolActivityJSONStillDecodes() throws {
        let suiteName = "chat-store-legacy-toolactivity-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        // `UserDefaultsAppPersistenceStore.Keys.conversationCache`, spelled out
        // because it is private — a divergence here presents as an empty
        // conversation, so the assertions below would catch it as a failure
        // rather than a false green.
        let cacheKey = "hermes.conversationCache"
        // Pre-#296 bytes: every key the schema had, and NOT ONE MORE. No
        // `failure` anywhere.
        let legacyJSON = """
        {
          "id": "5F8B4A21-0C3E-4D9A-9F17-2B6E8C1D4A70",
          "title": "Hermes",
          "lastActivity": "2026-08-08T23:59:00Z",
          "messages": [
            {
              "id": "A1C2E3F4-5678-49AB-8CDE-0123456789AB",
              "sender": "user",
              "content": "sleep 30; echo STOPTEST",
              "timestamp": "2026-08-08T23:58:58Z",
              "status": "delivered"
            },
            {
              "id": "B2D3F4A5-6789-4ABC-9DEF-123456789ABC",
              "sender": "hermes",
              "content": "",
              "timestamp": "2026-08-08T23:59:00Z",
              "status": "delivered",
              "toolActivities": [
                {
                  "id": "C3E4A5B6-789A-4BCD-8EF0-23456789ABCD",
                  "label": "terminal",
                  "startedAt": "2026-08-08T23:59:00Z",
                  "isActive": false,
                  "detail": "sleep 30; echo STOPTEST",
                  "anchorOffset": 0
                }
              ]
            }
          ]
        }
        """
        // Decode the same bytes DIRECTLY first. The store's loader catches its
        // decode error and returns nil, so the store path can only ever report
        // "the conversation is gone" — this line is what reports WHY, verbatim,
        // to whoever next breaks it.
        let rawDecoder = JSONDecoder()
        rawDecoder.dateDecodingStrategy = .iso8601
        _ = try rawDecoder.decode(Conversation.self, from: Data(legacyJSON.utf8))

        defaults.set(Data(legacyJSON.utf8), forKey: cacheKey)

        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let restored = try #require(
            persistence.loadConversationCache(),
            "296-E: a conversation cached before the failure field must still decode — a nil here IS the #42 silent wipe"
        )

        #expect(restored.title == "Hermes")
        #expect(restored.messages.count == 2, "296-E: both messages survive, not just the container")
        #expect(restored.messages.first?.content == "sleep 30; echo STOPTEST")

        let reply = try #require(restored.messages.last)
        #expect(reply.sender == .hermes)
        #expect(reply.toolActivities.count == 1, "296-E: the activity itself decodes, not just the message around it")
        let activity = try #require(reply.toolActivities.first)
        #expect(activity.label == "terminal")
        #expect(activity.detail == "sleep 30; echo STOPTEST", "296-E: detail is the INPUT summary and is untouched by #296")
        // The absent key reads as "no failure recorded" — which is the honest
        // answer for a row written before the app could record one.
        #expect(activity.failure == nil)
    }

    // MARK: - #306: the mid-turn hold across a relaunch (bars 306-I / 306-F)

    /// Streams stay open until the test ends them — the state a process
    /// death lands in. Local to this suite because `ImmediateReplyClient`
    /// cannot hold a turn open.
    @MainActor
    private final class HoldOpenStreamClient: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .connected
        var currentConversation: Conversation?
        private(set) var sentMessages: [String] = []
        private(set) var continuations: [AsyncStream<StreamingUpdate>.Continuation] = []

        func connect() async {}
        func disconnect() async {}

        func send(message: String, attachments: [PendingAttachment], clientMessageID: UUID) async -> Message {
            Message(sender: .hermes, content: "unused", status: .delivered)
        }

        func sendStreaming(
            message: String,
            attachments: [PendingAttachment],
            clientMessageID: UUID
        ) -> AsyncStream<StreamingUpdate> {
            sentMessages.append(message)
            return AsyncStream { continuation in
                continuation.yield(.messageSent(jobID: UUID()))
                self.continuations.append(continuation)
            }
        }

        func loadConversation() async -> Conversation {
            currentConversation ?? Conversation(title: Conversation.defaultTitle)
        }

        func clearConversation() async throws -> Conversation {
            Conversation(title: Conversation.defaultTitle)
        }
    }

    @Test @MainActor
    func heldTurnSurvivesRelaunchSurfacedWithoutAutoFiringOrMintingARow() async throws {
        // 306-I: held → process death mid-turn → cold load. The message is
        // present, SURFACED (the turn it waited on died with the process),
        // and NOTHING posts during launch. 306-F's relaunch half rides the
        // same relaunch: the cold-load scrub flips the dead turn's `.sending`
        // row to `.failed` and touches nothing of the held message, because
        // there is no row of it to touch.
        let persistence = makePersistence()
        let client = HoldOpenStreamClient()
        let store = ChatStore(hermesClient: client, persistence: persistence)

        let sendTask = Task { @MainActor in await store.sendMessage("dies mid-stream") }
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline, client.continuations.isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(store.isStreaming)
        #expect(store.holdComposedTurn("survives the relaunch"))

        // Process death: the store is simply never heard from again. The
        // hold was persisted at commit time — the sendMessage precedent.
        sendTask.cancel()

        // The relaunch: a fresh store over the same persistence.
        let relaunchClient = HoldOpenStreamClient()
        let relaunched = ChatStore(hermesClient: relaunchClient, persistence: persistence)
        await relaunched.loadConversationIfNeeded()
        // Let the load-time drain kick (a scheduled Task) run — it must not
        // touch a surfaced hold.
        try? await Task.sleep(for: .milliseconds(150))

        // Present, surfaced, and NOT posted.
        let held = try #require(relaunched.currentThreadHeldTurn)
        #expect(held.text == "survives the relaunch")
        #expect(held.phase == .surfaced, "306-I: the chip SURFACEs — its turn died with the process")
        #expect(relaunchClient.sentMessages.isEmpty, "306-I: nothing may post during launch")

        // 306-F: zero transcript rows for the held text — before and after
        // the cold-load scrub — while the dead turn's own row took the
        // ordinary `.failed` path.
        let rows = relaunched.conversation?.messages ?? []
        #expect(rows.contains { $0.content == "survives the relaunch" } == false)
        #expect(rows.first { $0.sender == .user && $0.content == "dies mid-stream" }?.status == .failed)
    }

}
