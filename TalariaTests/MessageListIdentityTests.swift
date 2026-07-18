import Foundation
import Testing
@testable import Talaria

/// #120: the transcript ForEach renders `conversation.messages` keyed by the
/// message UUID — the rendered collection must never hold the same id twice
/// (SwiftUI declares the result undefined; device logs 2026-07-16, two runs:
/// `ForEach<Array<Message>, UUID, …>: the ID … occurs multiple times`).
///
/// The duplication mechanism: backends that maintain their own conversation
/// (LocalChatBackend, the mock) append the final reply to it BEFORE yielding
/// `.finished` with that same Message. Any conversation merge that runs in
/// that window — the 2s relay-poll tick, a refresh — adopts the reply into
/// the store while the streaming placeholder is still in the array. The
/// `.finished` handler then replaced the placeholder by index without
/// checking whether the final message's id was already present: same UUID,
/// twice. The post-finish metadata merge only healed it when
/// `hermesClient.currentConversation` happened to contain the reply — nil on
/// the warm-launch path (`loadConversationIfNeeded` returns early from
/// cache, so no one primes the client), and the wrong backend entirely when
/// an overlapping turn moves the router's resolution mid-flight.
struct MessageListIdentityTests {

    @MainActor private static func makePersistence() -> UserDefaultsAppPersistenceStore {
        let suiteName = "message-list-identity-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsAppPersistenceStore(defaults: defaults)
    }

    /// A backend shaped like LocalChatBackend's streaming path: it maintains
    /// its own conversation, appending the user row (id == clientMessageID)
    /// and then the reply BEFORE `.finished` yields — then parks so the test
    /// can land a conversation merge inside the real race window (the poll
    /// tick). `currentConversation` stays nil, the warm-launch resilient
    /// shape (primary never primed), so the post-finish metadata merge
    /// cannot mask the duplication.
    @MainActor
    private final class MidTurnMergeClient: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .connected
        /// Nil by design — see the type comment. The poll-equivalent merge
        /// reads `loadConversation()` instead, which serves the backend's
        /// own thread (the resilient-fallback shape).
        var currentConversation: Conversation?

        /// The backend's own thread — what LocalChatBackend keeps in its
        /// `currentConversation` and what a relay fallback would serve.
        private(set) var backendConversation = Conversation(title: Conversation.defaultTitle)

        /// The reply's identity: appended to the backend thread AND yielded
        /// via `.finished`, exactly like LocalChatBackend.streamTurn.
        let finalMessageID = UUID()

        /// True once the reply is appended backend-side and the stream is
        /// parked ahead of the `.finished` yield.
        private(set) var isParkedBeforeFinish = false
        private var finishGate: CheckedContinuation<Void, Never>?

        func releaseFinish() {
            finishGate?.resume()
            finishGate = nil
        }

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
            AsyncStream { continuation in
                Task { @MainActor in
                    self.backendConversation.messages.append(Message(
                        id: clientMessageID,
                        clientMessageID: clientMessageID,
                        sender: .user,
                        content: message,
                        status: .delivered
                    ))
                    continuation.yield(.textDelta("Hello "))
                    let reply = Message(
                        id: self.finalMessageID,
                        sender: .hermes,
                        content: "Hello there.",
                        status: .delivered
                    )
                    self.backendConversation.messages.append(reply)
                    await withCheckedContinuation { (gate: CheckedContinuation<Void, Never>) in
                        self.finishGate = gate
                        self.isParkedBeforeFinish = true
                    }
                    continuation.yield(.finished(reply, nil, nil))
                    continuation.finish()
                }
            }
        }

        func loadConversation() async -> Conversation {
            backendConversation
        }

        func clearConversation() async throws -> Conversation {
            Conversation(title: Conversation.defaultTitle)
        }
    }

    @Test @MainActor
    func streamFinalizeNeverDuplicatesMessageIDsAfterMidStreamMerge() async throws {
        let persistence = Self.makePersistence()
        let client = MidTurnMergeClient()
        let store = ChatStore(hermesClient: client, persistence: persistence)

        let sendTask = Task { await store.sendMessage("Hi") }

        // Let the scripted backend reach the parked point: reply appended
        // backend-side, `.finished` not yet yielded.
        var spins = 0
        while !client.isParkedBeforeFinish, spins < 10_000 {
            spins += 1
            await Task.yield()
        }
        #expect(client.isParkedBeforeFinish)

        // The mid-stream merge — what the 2s relay-poll tick does in
        // production (same mergeConversationMetadata path). It adopts the
        // backend's copy of the reply while the placeholder is still live.
        await store.loadConversation()
        let midStreamIDs = store.conversation?.messages.map(\.id) ?? []
        #expect(midStreamIDs.contains(client.finalMessageID))
        let placeholderID = try #require(store.streamingMessageID)
        #expect(midStreamIDs.contains(placeholderID))

        client.releaseFinish()
        await sendTask.value

        let ids = store.conversation?.messages.map(\.id) ?? []
        #expect(Set(ids).count == ids.count, "transcript ids must be unique — got \(ids)")
        #expect(ids.filter { $0 == client.finalMessageID }.count == 1)
        #expect(store.streamingMessageID == nil)
        // The settled reply carries the finished content in exactly one row.
        let replies = store.conversation?.messages.filter { $0.id == client.finalMessageID } ?? []
        #expect(replies.first?.content == "Hello there.")
    }

    /// A refresh source that serves the same message id twice — a foreign
    /// transcript (relay, backend cache) must not be able to import an
    /// internal duplicate into the rendered collection wholesale.
    @MainActor
    private final class DuplicateRefreshClient: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .connected
        var currentConversation: Conversation?

        let duplicatedID = UUID()

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
            AsyncStream { continuation in
                continuation.finish()
            }
        }

        func loadConversation() async -> Conversation {
            let echoed = Message(
                id: duplicatedID,
                sender: .hermes,
                content: "echoed twice",
                status: .delivered
            )
            return Conversation(
                title: Conversation.defaultTitle,
                messages: [echoed, echoed]
            )
        }

        func clearConversation() async throws -> Conversation {
            Conversation(title: Conversation.defaultTitle)
        }
    }

    @Test @MainActor
    func refreshMergeNeverImportsInternalDuplicateIDs() async throws {
        let persistence = Self.makePersistence()
        let client = DuplicateRefreshClient()
        let store = ChatStore(hermesClient: client, persistence: persistence)

        await store.loadConversation()

        let ids = store.conversation?.messages.map(\.id) ?? []
        #expect(ids.filter { $0 == client.duplicatedID }.count == 1)
        #expect(Set(ids).count == ids.count)
    }
}
