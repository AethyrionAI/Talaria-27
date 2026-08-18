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

        /// 357-H's ordering witness: every stop and send in arrival order.
        private(set) var orderedEvents: [String] = []

        @discardableResult
        func hardStopActiveRun() -> Bool {
            orderedEvents.append("stop")
            return hostStopIsIssuable
        }

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
            orderedEvents.append("send:\(message)")
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

    // MARK: - 357-H: the interrupt door — stop first, then ONE fresh turn

    @Test @MainActor
    func interruptStopsThenPostsExactlyOneFreshTurn() async throws {
        let client = SteeringManualClient()
        client.hostStopIsIssuable = true
        let store = ChatStore(hermesClient: client, persistence: Self.makePersistence())
        let sendTask = await startTurn("write a story", store: store, client: client)

        client.autoFinishSends = true
        #expect(await store.interruptActiveTurnAndResend("new question"))
        _ = await sendTask.value

        // The ordering is the bar: the host stop goes out BEFORE the fresh
        // turn posts, and the text posts exactly once — no double-send.
        let stopIndex = try #require(client.orderedEvents.firstIndex(of: "stop"))
        let resendIndex = try #require(client.orderedEvents.firstIndex(of: "send:new question"))
        #expect(stopIndex < resendIndex, "stop settles before the fresh turn posts")
        #expect(client.sentMessages.filter { $0 == "new question" }.count == 1)
        #expect(store.doorStatusChip == nil, "the interrupt chip does not outlive the orchestration")
        #expect(store.isTranscriptBusy == false)
    }

    @Test @MainActor
    func interruptRefusedWhenNothingIsRunning() async {
        let client = SteeringManualClient()
        let store = ChatStore(hermesClient: client, persistence: Self.makePersistence())

        #expect(await store.interruptActiveTurnAndResend("nothing to interrupt") == false)
        #expect(client.orderedEvents.isEmpty, "an idle composer neither stops nor posts")
    }

    @Test @MainActor
    func interruptNeverAutoFiresAHeldTurn() async throws {
        // #306 row 2: a stopped turn never auto-fires the held message. The
        // interrupt door's fresh turn is the INTERRUPT text alone — the held
        // turn parks (restores), it does not ride along.
        let client = SteeringManualClient()
        client.hostStopIsIssuable = true
        let store = ChatStore(hermesClient: client, persistence: Self.makePersistence())
        store.composerLiveText = { "" }
        let sendTask = await startTurn("write a story", store: store, client: client)

        #expect(store.holdComposedTurn("held follow"))
        client.autoFinishSends = true
        #expect(await store.interruptActiveTurnAndResend("urgent question"))
        _ = await sendTask.value

        #expect(client.sentMessages.filter { $0 == "urgent question" }.count == 1)
        #expect(!client.sentMessages.contains("held follow"), "row 2: stop must not fire the hold")
    }
}
