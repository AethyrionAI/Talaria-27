import Foundation
import Testing
@testable import Talaria

/// #357 bars 357-E/G — the store half of the steer door: submit vs applied,
/// the queue fallback when the door is closed, and the pending-steer
/// conversion (hold-first, seed when occupied, always at the terminal).
struct SteeringOrchestrationTests {

    @MainActor private static func makePersistence() -> UserDefaultsAppPersistenceStore {
        let suiteName = "steering-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsAppPersistenceStore(defaults: defaults)
    }

    /// The MessageQueueTerminalsTests manual-drive shape plus a scriptable
    /// steer outcome.
    @MainActor
    private final class SteeringManualClient: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .connected
        var currentConversation: Conversation?
        var currentRunIsServerRecoverable = true
        private(set) var sentMessages: [String] = []
        private(set) var continuations: [AsyncStream<StreamingUpdate>.Continuation] = []
        var autoFinishSends = false
        var hostStopIsIssuable = false

        var steerOutcome: SteerSubmitOutcome = .submitted
        private(set) var steeredTexts: [String] = []

        @discardableResult
        func hardStopActiveRun() -> Bool { hostStopIsIssuable }

        func steerActiveRun(text: String) async -> SteerSubmitOutcome {
            steeredTexts.append(text)
            return steerOutcome
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
            sentMessages.append(message)
            let autoFinish = autoFinishSends
            return AsyncStream { continuation in
                continuation.yield(.messageSent(jobID: UUID()))
                if autoFinish {
                    continuation.yield(.finished(
                        Message(sender: .hermes, content: "auto-reply: \(message)", status: .delivered),
                        nil, nil
                    ))
                    continuation.finish()
                } else {
                    self.continuations.append(continuation)
                }
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

    @MainActor
    private func startTurn(
        _ text: String, store: ChatStore, client: SteeringManualClient
    ) async -> Task<Bool, Never> {
        let priorStreams = client.continuations.count
        let task = Task { @MainActor in await store.sendMessage(text) }
        let live = await pollUntil { store.isStreaming && client.continuations.count > priorStreams }
        #expect(live, "the turn must be streaming before the test proceeds")
        return task
    }

    // MARK: - 357-G: submit is not applied; the frame is

    @Test @MainActor
    func steerSubmitsAndLandsOnlyOnTheFrame() async throws {
        let client = SteeringManualClient()
        let store = ChatStore(hermesClient: client, persistence: Self.makePersistence())
        let sendTask = await startTurn("write a story", store: store, client: client)
        let stream = try #require(client.continuations.last)

        #expect(await store.steerActiveTurn("actually, reply PLUM"))
        #expect(client.steeredTexts == ["actually, reply PLUM"])
        #expect(store.steerAttemptOutstanding, "submitted ≠ applied — the attempt is outstanding until the frame")
        #expect(store.steerAttempt?.landed == false)

        stream.yield(.steerLanded)
        let landed = await pollUntil { store.steerAttempt?.landed == true }
        #expect(landed, "run.steered is THE applied signal")
        #expect(!store.steerAttemptOutstanding)

        stream.yield(.finished(Message(sender: .hermes, content: "PLUM", status: .delivered), nil, nil))
        stream.finish()
        _ = await sendTask.value
        #expect(store.steerAttempt == nil, "the attempt does not outlive its turn")
    }

    // MARK: - 357-E: depth-1

    @Test @MainActor
    func secondSteerWhileOutstandingIsRefused() async throws {
        let client = SteeringManualClient()
        let store = ChatStore(hermesClient: client, persistence: Self.makePersistence())
        let sendTask = await startTurn("write a story", store: store, client: client)
        let stream = try #require(client.continuations.last)

        #expect(await store.steerActiveTurn("first"))
        #expect(await store.steerActiveTurn("second") == false)
        #expect(client.steeredTexts == ["first"])

        stream.finish()
        _ = await sendTask.value
    }

    // MARK: - 357-E: the closed door falls back to the queue, named

    @Test @MainActor
    func closedWindowFallsBackToTheHold() async throws {
        let client = SteeringManualClient()
        let store = ChatStore(hermesClient: client, persistence: Self.makePersistence())
        let sendTask = await startTurn("write a story", store: store, client: client)
        let stream = try #require(client.continuations.last)

        client.steerOutcome = .windowClosed
        #expect(await store.steerActiveTurn("too late"))
        #expect(store.steerAttempt == nil, "a refused submit is not an attempt")
        let held = try #require(store.currentThreadHeldTurn)
        #expect(held.text == "too late")

        stream.finish()
        _ = await sendTask.value
    }

    // MARK: - 357-G: the pending-steer conversion fires as the next message

    @Test @MainActor
    func unconsumedSteerConvertsToHeldAndFiresAtTheTerminal() async throws {
        let client = SteeringManualClient()
        let store = ChatStore(hermesClient: client, persistence: Self.makePersistence())
        let sendTask = await startTurn("write a story", store: store, client: client)
        let stream = try #require(client.continuations.last)

        #expect(await store.steerActiveTurn("reply MANGO"))

        client.autoFinishSends = true
        stream.yield(.steerUnconsumed("reply MANGO"))
        stream.yield(.finished(Message(sender: .hermes, content: "the story", status: .delivered), nil, nil))
        stream.finish()
        _ = await sendTask.value

        let fired = await pollUntil { client.sentMessages.contains("reply MANGO") }
        #expect(fired, "the drained steer is the next user turn (#306 fire at the completed terminal)")
        #expect(store.steerAttempt == nil)
    }

    // MARK: - 357-G: an occupied hold falls to the seed, never silent loss

    @Test @MainActor
    func unconsumedSteerSeedsComposerWhenHoldIsOccupied() async throws {
        let client = SteeringManualClient()
        let store = ChatStore(hermesClient: client, persistence: Self.makePersistence())
        store.composerLiveText = { "" }
        let sendTask = await startTurn("write a story", store: store, client: client)
        let stream = try #require(client.continuations.last)

        #expect(store.holdComposedTurn("the user's own queued message"))
        client.autoFinishSends = true
        stream.yield(.steerUnconsumed("reply MANGO"))
        stream.yield(.finished(Message(sender: .hermes, content: "the story", status: .delivered), nil, nil))
        stream.finish()
        _ = await sendTask.value

        #expect(store.pendingComposerSeed == "reply MANGO", "the steer text restores via the #48 seed when the hold is taken")
        let userHoldFired = await pollUntil { client.sentMessages.contains("the user's own queued message") }
        #expect(userHoldFired, "the user's explicit hold keeps its slot and fires")
    }
}
