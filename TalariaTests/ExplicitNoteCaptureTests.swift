import Foundation
import Testing
@testable import Talaria

/// #422 Task 11 — the wiring around `ExplicitMemoryIntent`: ChatStore's
/// `sendMessage` captures a note BEFORE dispatching the turn to any backend
/// (bar 422-E's ordering pin), the toggle gates the write (not the parse),
/// and Undo removes the row through the same public primitive `/undo` uses
/// (`truncateTranscript`). Fixture shape follows `LocalSessionHistoryTests`
/// (`makePersistence`, a minimal `HermesClientProtocol` fake).
@MainActor
struct ExplicitNoteCaptureTests {

    @MainActor private func makePersistence() -> UserDefaultsAppPersistenceStore {
        let suiteName = "explicit-note-capture-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsAppPersistenceStore(defaults: defaults)
    }

    /// Yields one `.finished` reply, exactly like `LocalSessionHistoryTests`'
    /// `SettlingClient` — the minimal client for driving ChatStore's settle
    /// path. `sendStreaming` is also the ordering pin's SPY: it records how
    /// many notes the store already holds at the instant a backend (any
    /// backend — this fake stands in for either) is asked to prepare the
    /// turn, which is bar 422-E's "before the turn is dispatched" made
    /// measurable.
    @MainActor
    private final class NoteOrderingSpyClient: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .connected
        var currentConversation: Conversation?
        private let memoryStore: MemoryStore
        private(set) var noteCountsAtPrepareTime: [Int] = []

        init(memoryStore: MemoryStore) { self.memoryStore = memoryStore }

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
            // The spy: read BEFORE the stream does anything else. If
            // ChatStore captured the note earlier in `sendMessage` (as bar
            // 422-E requires), it is already in the store by the time this
            // closure runs.
            noteCountsAtPrepareTime.append(memoryStore.allNotes().count)
            let reply = Message(sender: .hermes, content: "Got it.", status: .delivered)
            return AsyncStream { continuation in
                continuation.yield(.finished(reply, nil, nil))
                continuation.finish()
            }
        }

        func loadConversation() async -> Conversation {
            currentConversation ?? Conversation(title: "Hermes")
        }

        func clearConversation() async throws -> Conversation {
            Conversation(title: "Hermes")
        }
    }

    private func makeChatStore(memoryStore: MemoryStore) -> (ChatStore, NoteOrderingSpyClient) {
        let client = NoteOrderingSpyClient(memoryStore: memoryStore)
        let chatStore = ChatStore(hermesClient: client, persistence: makePersistence())
        chatStore.memoryStore = memoryStore
        return (chatStore, client)
    }

    // MARK: - The ordering pin (bar 422-E)

    @Test func theNoteExistsBeforeTheBackendsTurnIsPrepared() async throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let (chatStore, client) = makeChatStore(memoryStore: store)

        _ = await chatStore.sendMessage("Remember that my sister lives in Austin")

        #expect(client.noteCountsAtPrepareTime == [1],
                "the store must already hold the note by the time the backend prepares the turn")
        #expect(store.allNotes().map(\.text) == ["my sister lives in Austin"])
    }

    @Test func anOrdinaryMessageCapturesNoNoteAndTheSpySeesZero() async throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let (chatStore, client) = makeChatStore(memoryStore: store)

        _ = await chatStore.sendMessage("What's the weather like?")

        #expect(client.noteCountsAtPrepareTime == [0])
        #expect(store.allNotes().isEmpty)
    }

    @Test func aReminderShapeCapturesNoNote() async throws {
        // The same discriminator as ExplicitMemoryIntentTests, re-asserted
        // at the wiring level: "remember to…" must never write a row.
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let (chatStore, _) = makeChatStore(memoryStore: store)

        _ = await chatStore.sendMessage("Remember to call mom")

        #expect(store.allNotes().isEmpty)
    }

    // MARK: - The toggle (Owen's ruling: OFF stores nothing)

    @Test func toggleOffParsesButStoresNothing() async throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let (chatStore, client) = makeChatStore(memoryStore: store)
        chatStore.isMemoryEnabled = { false }

        let sent = await chatStore.sendMessage("Remember that my sister lives in Austin")

        #expect(sent, "the toggle must not block the turn itself, only the write")
        #expect(store.allNotes().isEmpty, "OFF must store nothing even though the trigger matched")
        #expect(client.noteCountsAtPrepareTime == [0])
    }

    @Test func toggleOnAfterAnOffTurnResumesCapture() async throws {
        // The closure must be read live, not captured once — a mid-session
        // flip takes effect on the very next send (same discipline as
        // `MemoryIndexer.isEnabled`).
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let (chatStore, _) = makeChatStore(memoryStore: store)
        chatStore.isMemoryEnabled = { false }

        _ = await chatStore.sendMessage("Remember that the router password is on the fridge")
        #expect(store.allNotes().isEmpty)

        // Reassigning the SAME chatStore's closure (rather than mutating a
        // captured var — Swift 6 flags that as a sendable-closure hazard) is
        // still the discriminating case: `sendMessage` calls
        // `isMemoryEnabled?()` fresh on every send, so this still proves the
        // toggle is read live rather than cached at construction.
        chatStore.isMemoryEnabled = { true }
        _ = await chatStore.sendMessage("Remember that my sister lives in Austin")
        #expect(store.allNotes().map(\.text) == ["my sister lives in Austin"])
    }

    @Test func aNilMemoryStoreNeverCrashesTheSend() async throws {
        let client = NoteOrderingSpyClient(memoryStore: try #require(MemoryStore.make(inMemoryOnly: true)))
        let chatStore = ChatStore(hermesClient: client, persistence: makePersistence())
        // memoryStore left nil — container-creation failure's shape.

        let sent = await chatStore.sendMessage("Remember that my sister lives in Austin")

        #expect(sent)
    }

    // MARK: - Undo removes the note (through the public `truncateTranscript` primitive `/undo` uses)

    @Test func undoingTheTurnThatSavedANoteRemovesIt() async throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let (chatStore, _) = makeChatStore(memoryStore: store)

        _ = await chatStore.sendMessage("Remember that my sister lives in Austin")
        #expect(store.allNotes().count == 1)

        let messages = try #require(chatStore.conversation?.messages)
        let lastUserIdx = try #require(messages.lastIndex { $0.sender.isUserAuthored })
        chatStore.truncateTranscript(from: lastUserIdx, reason: "/undo")

        #expect(store.allNotes().isEmpty, "Undo of the note-saving turn must remove the row with it")
    }

    @Test func undoingAnUnrelatedLaterTurnDoesNotRemoveAnEarlierNote() async throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let (chatStore, _) = makeChatStore(memoryStore: store)

        _ = await chatStore.sendMessage("Remember that my sister lives in Austin")
        #expect(store.allNotes().count == 1)

        _ = await chatStore.sendMessage("What's the weather like?")
        let messages = try #require(chatStore.conversation?.messages)
        let lastUserIdx = try #require(messages.lastIndex { $0.sender.isUserAuthored })
        chatStore.truncateTranscript(from: lastUserIdx, reason: "/undo")

        #expect(store.allNotes().count == 1, "undoing a later, unrelated turn must not touch the earlier note")
    }

    @Test func undoingATurnThatSavedNoNoteIsANoOpOnTheStore() async throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let (chatStore, _) = makeChatStore(memoryStore: store)

        _ = await chatStore.sendMessage("What's the weather like?")
        let messages = try #require(chatStore.conversation?.messages)
        let lastUserIdx = try #require(messages.lastIndex { $0.sender.isUserAuthored })
        chatStore.truncateTranscript(from: lastUserIdx, reason: "/undo")

        #expect(store.allNotes().isEmpty)
    }

    // MARK: - Regenerate restores the note when the re-send is swallowed
    //         (FINAL REVIEW item 2 — silent data loss)

    /// **The defect.** `regenerateReply` truncates the transcript in order to
    /// re-send, and `truncateTranscript` deletes the notes those turns saved.
    /// When a send guard swallows the re-send — in practice the duplicate
    /// check, when an identical turn is still pending elsewhere in the thread
    /// — `restoreTruncatedRows` puts the MESSAGES back but used to leave the
    /// note deleted. The user re-rolled a reply and silently lost a memory
    /// they had explicitly asked to keep: no error, nothing on screen, and
    /// the transcript looks untouched because the rows came back.
    ///
    /// The transcript is built directly rather than driven through two sends,
    /// because the swallow needs a `.sending` row that OUTLIVES the
    /// truncation — an earlier identical turn, above `userIdx`. That is the
    /// real shape (#78's residual) and it is not reachable by settling sends.
    @Test func regeneratingWithASwallowedResendKeepsTheNote() async throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let (chatStore, _) = makeChatStore(memoryStore: store)
        let text = "Remember that my sister lives in Austin"

        let producingID = UUID()
        let noteID = store.insertNote(
            "my sister lives in Austin", sourceMessageID: producingID, sourceSessionID: nil)
        #expect(store.allNotes().count == 1)

        // An earlier, still-pending copy of the same turn: this is what makes
        // `sendMessage` return false, and it survives the truncation because
        // it sits ABOVE the producing turn.
        let stuck = Message(
            id: UUID(), clientMessageID: UUID(), sender: .user, content: text, status: .sending)
        let producing = Message(
            id: producingID, clientMessageID: producingID, sender: .user,
            content: text, status: .delivered)
        let reply = Message(sender: .hermes, content: "Got it.", status: .delivered)
        chatStore.conversation = Conversation(
            title: "Hermes", messages: [stuck, producing, reply])

        await chatStore.regenerateReply(reply)

        #expect(store.allNotes().count == 1, """
            the re-send was swallowed and the rows were restored, but the note was not — \
            the user re-rolled a reply and silently lost a memory they asked to keep
            """)
        #expect(store.note(id: noteID) != nil, """
            the note came back under a DIFFERENT id — every memoryProvenance and \
            MemoryUseRecord naming the old one now resolves to nothing (ruling 2)
            """)
        #expect(store.allNotes().first?.text == "my sister lives in Austin",
                "restored verbatim")
    }

    /// The restore must not resurrect a note the user really did undo: a
    /// truncation that is NOT followed by a restore leaves the row deleted,
    /// and a later restore of a DIFFERENT truncation must not bring it back.
    @Test func aPlainUndoStillRemovesTheNoteForGood() async throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let (chatStore, _) = makeChatStore(memoryStore: store)

        _ = await chatStore.sendMessage("Remember that my sister lives in Austin")
        #expect(store.allNotes().count == 1)
        let messages = try #require(chatStore.conversation?.messages)
        let lastUserIdx = try #require(messages.lastIndex { $0.sender.isUserAuthored })
        chatStore.truncateTranscript(from: lastUserIdx, reason: "/undo")
        #expect(store.allNotes().isEmpty)

        // A later regenerate whose re-send IS swallowed must restore only its
        // OWN truncation's notes — the stash is per-truncation, not a
        // graveyard.
        let stuck = Message(
            id: UUID(), clientMessageID: UUID(), sender: .user,
            content: "something else", status: .sending)
        let producing = Message(sender: .user, content: "something else", status: .delivered)
        let reply = Message(sender: .hermes, content: "ok", status: .delivered)
        chatStore.conversation = Conversation(
            title: "Hermes", messages: [stuck, producing, reply])
        await chatStore.regenerateReply(reply)

        #expect(store.allNotes().isEmpty,
                "an undone note must stay undone — the stash belongs to one truncation")
    }

    // MARK: - Retry does not duplicate the note (fix round 1, Important item 3)
    //
    // `ChatStore.retryMessage` removes its single row with a bare
    // `messages.remove(at:)` — deliberately NOT `truncateTranscript` (#279,
    // the function's own doc) — so `truncateTranscript`'s cleanup never ran
    // for it. The re-send that follows captures a SECOND identical note
    // under a fresh `clientMessageID`, orphaning the first. The fix keys
    // cleanup on `sourceMessageID` directly (`MemoryStore.deleteNotes(
    // withSourceMessageIDs:)`), called from `retryMessage` itself right
    // where the re-send actually lands.

    @Test func retryingTheTurnThatSavedANoteLeavesExactlyOne() async throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let (chatStore, _) = makeChatStore(memoryStore: store)

        _ = await chatStore.sendMessage("Remember that my sister lives in Austin")
        #expect(store.allNotes().count == 1)

        let userMessage = try #require(chatStore.conversation?.messages.first { $0.sender.isUserAuthored })
        await chatStore.retryMessage(userMessage)

        #expect(store.allNotes().count == 1, "a retry must not leave a duplicate note behind")
        #expect(store.allNotes().first?.text == "my sister lives in Austin")
    }

    @Test func retryingATurnThatSavedNoNoteStaysEmpty() async throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let (chatStore, _) = makeChatStore(memoryStore: store)

        _ = await chatStore.sendMessage("What's the weather like?")
        let userMessage = try #require(chatStore.conversation?.messages.first { $0.sender.isUserAuthored })
        await chatStore.retryMessage(userMessage)

        #expect(store.allNotes().isEmpty)
    }

    /// Retrying a DIFFERENT turn than the one that saved a note must not
    /// touch the unrelated note — the cleanup is keyed on the retried row's
    /// OWN id, not a blanket sweep.
    @Test func retryingAnUnrelatedTurnDoesNotTouchAnEarlierNote() async throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let (chatStore, _) = makeChatStore(memoryStore: store)

        _ = await chatStore.sendMessage("Remember that my sister lives in Austin")
        #expect(store.allNotes().count == 1)

        _ = await chatStore.sendMessage("What's the weather like?")
        let secondUserMessage = try #require(chatStore.conversation?.messages.last { $0.sender.isUserAuthored })
        await chatStore.retryMessage(secondUserMessage)

        #expect(store.allNotes().count == 1, "retrying the unrelated later turn must not touch the earlier note")
        #expect(store.allNotes().first?.text == "my sister lives in Austin")
    }
}
