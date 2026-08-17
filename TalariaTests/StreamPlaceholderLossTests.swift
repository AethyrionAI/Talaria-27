import Foundation
import Testing
@testable import Talaria

/// #358 — the silent-drop defect #356's morning stage exposed: every stream
/// update handler and the `.finished` landing block key on the streaming
/// placeholder row by id and SKIP SILENTLY when it is absent, after which the
/// turn still settles as a clean success. A fully delivered reply renders as
/// nothing, with no failure surfaced anywhere.
///
/// These tests assert the DESIRED behavior (bar 358-A/B: the reply must land
/// even when the placeholder slot is gone; bar 358-C: the turn ledger must
/// witness the drops), so they are RED on the pre-fix code by design.
struct StreamPlaceholderLossTests {

    @MainActor private static func makePersistence() -> UserDefaultsAppPersistenceStore {
        let suiteName = "placeholder-loss-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsAppPersistenceStore(defaults: defaults)
    }

    /// Same manual-drive shape as MessageQueueTerminalsTests' client: the
    /// test owns the continuation, so the terminal is the test's own event.
    @MainActor
    private final class ManualStreamClient: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .connected
        var currentConversation: Conversation?
        var currentRunIsServerRecoverable = true
        private(set) var sentMessages: [String] = []
        private(set) var continuations: [AsyncStream<StreamingUpdate>.Continuation] = []
        var hostStopIsIssuable = false

        @discardableResult
        func hardStopActiveRun() -> Bool { hostStopIsIssuable }

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

        func reconcileFromServer() async -> Conversation? { nil }
    }

    @MainActor
    private func pollUntil(
        timeout: Duration = .seconds(5),
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    /// Starts a turn and holds until its stream is live.
    @MainActor
    private func startTurn(
        _ text: String, store: ChatStore, client: ManualStreamClient
    ) async -> Task<Bool, Never> {
        let priorStreams = client.continuations.count
        let task = Task { @MainActor in await store.sendMessage(text) }
        let live = await pollUntil { store.isStreaming && client.continuations.count > priorStreams }
        #expect(live, "the turn must be streaming before the test proceeds")
        return task
    }

    /// Removes the streaming placeholder row the way every real remover
    /// leaves the transcript: the hermes `.sending` row is simply gone.
    @MainActor
    private func removePlaceholder(from store: ChatStore) {
        var conv = store.conversation
        conv?.messages.removeAll { $0.sender == .hermes && $0.status == .sending }
        store.conversation = conv
    }

    // MARK: - 358-A/B: the reply must land even when the slot is gone

    @Test @MainActor
    func finishedWithLostPlaceholderStillLandsTheReply() async throws {
        let persistence = Self.makePersistence()
        let client = ManualStreamClient()
        let store = ChatStore(hermesClient: client, persistence: persistence)

        let sendTask = await startTurn("tell me a story", store: store, client: client)
        let stream = try #require(client.continuations.last)

        stream.yield(.textDelta("Once"))
        // Give the delta a beat to apply before the loss.
        _ = await pollUntil { store.conversation?.messages.contains { $0.content.hasPrefix("Once") } ?? false }

        removePlaceholder(from: store)

        let finalContent = "Once upon a time, a fully delivered reply."
        stream.yield(.finished(
            Message(sender: .hermes, content: finalContent, status: .delivered),
            TokenUsage(promptTokens: 10, completionTokens: 20, totalTokens: 30),
            nil
        ))
        stream.finish()
        _ = await sendTask.value

        // The turn settles either way — that part was never the defect.
        #expect(store.isTranscriptBusy == false)
        let userRow = try #require(store.conversation?.messages.first { $0.sender == .user })
        #expect(userRow.status == .delivered)

        // THE BAR (358-B): the fully delivered reply is in the transcript.
        // Pre-fix this is the silent-success shape: no assistant row at all.
        let assistantRows = store.conversation?.messages.filter { $0.sender == .hermes } ?? []
        #expect(
            assistantRows.contains { $0.content == finalContent },
            "a fully delivered reply must land in the transcript even when the placeholder slot is gone (#358)"
        )
    }

    // MARK: - 358-B guard: a pre-merged copy must not double-append

    @Test @MainActor
    func finishedWithLostPlaceholderAndPreMergedCopyDoesNotDuplicate() async throws {
        let persistence = Self.makePersistence()
        let client = ManualStreamClient()
        let store = ChatStore(hermesClient: client, persistence: persistence)

        let sendTask = await startTurn("tell me a story", store: store, client: client)
        let stream = try #require(client.continuations.last)

        removePlaceholder(from: store)

        // #120 shape: a mid-stream merge already adopted the reply row.
        let finalID = UUID()
        let finalContent = "The adopted reply."
        var conv = store.conversation
        conv?.messages.append(Message(id: finalID, sender: .hermes, content: finalContent, status: .delivered))
        store.conversation = conv

        stream.yield(.finished(
            Message(id: finalID, sender: .hermes, content: finalContent, status: .delivered),
            nil, nil
        ))
        stream.finish()
        _ = await sendTask.value

        let copies = store.conversation?.messages.filter { $0.id == finalID } ?? []
        #expect(copies.count == 1, "the landed reply must not duplicate a pre-merged copy (#120 guard)")
    }

    // MARK: - 358-C: the ledger witnesses the drops

    @Test @MainActor
    func turnLedgerRecordsDroppedUpdatesAndOutcome() async throws {
        let persistence = Self.makePersistence()
        let client = ManualStreamClient()
        let store = ChatStore(hermesClient: client, persistence: persistence)

        let sendTask = await startTurn("tell me a story", store: store, client: client)
        let stream = try #require(client.continuations.last)

        stream.yield(.textDelta("Once"))
        _ = await pollUntil { store.conversation?.messages.contains { $0.content.hasPrefix("Once") } ?? false }

        removePlaceholder(from: store)

        stream.yield(.textDelta(" upon"))
        stream.yield(.reasoningDelta("thinking"))
        stream.yield(.finished(
            Message(sender: .hermes, content: "Once upon a time.", status: .delivered),
            nil, nil
        ))
        stream.finish()
        _ = await sendTask.value

        let ledger = try #require(store.lastTurnStreamLedger, "every streamed turn must end with a ledger (#358-C)")
        #expect(ledger.updatesApplied >= 1, "the pre-loss delta applied")
        #expect(ledger.updatesDropped >= 2, "the post-loss delta and reasoning delta must be counted, not silently skipped")
        #expect(ledger.finalDelivery == .appendedWithoutPlaceholder)
    }

    // MARK: - no-regression: the intact path is unchanged

    @Test @MainActor
    func intactPlaceholderPathUnchanged() async throws {
        let persistence = Self.makePersistence()
        let client = ManualStreamClient()
        let store = ChatStore(hermesClient: client, persistence: persistence)

        let sendTask = await startTurn("tell me a story", store: store, client: client)
        let stream = try #require(client.continuations.last)

        stream.yield(.textDelta("Once"))
        stream.yield(.textDelta(" upon a time."))
        let finalContent = "Once upon a time."
        stream.yield(.finished(
            Message(sender: .hermes, content: finalContent, status: .delivered),
            nil, nil
        ))
        stream.finish()
        _ = await sendTask.value

        let assistantRows = store.conversation?.messages.filter { $0.sender == .hermes } ?? []
        #expect(assistantRows.count == 1)
        #expect(assistantRows.first?.content == finalContent)

        let ledger = try #require(store.lastTurnStreamLedger)
        #expect(ledger.updatesDropped == 0)
        #expect(ledger.finalDelivery == .replacedPlaceholder)
    }
}
