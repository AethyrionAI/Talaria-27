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
}
