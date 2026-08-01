import Foundation
import Testing
@testable import Talaria

#if DEBUG

/// #198 (`BGTaskScheduler.submit`) — coverage for the continued-processing
/// send path, written BEFORE the migration touches it.
///
/// The path had **zero** tests. That is what made the deprecation look
/// dangerous: `beginLongSend` is wired into `ChatStore.sendMessage`, and the
/// audit could only describe the risk ("the most load-bearing path in the app
/// and it has thin coverage") rather than bound it.
///
/// `BGContinuedProcessingTask` has no public initializer, so no test can make
/// the system hand a handle a real task. That is not a gap here — it is the
/// state the migration actually turns on. A handle whose submission fails
/// never adopts a task either, so "no task adopted" IS the case under test.
struct ContinuedProcessingTests {

    // MARK: - Handle lifecycle with no task adopted

    @MainActor @Test func unadoptedHandleStartsAtTheSubmittedMilestone() {
        let handle = ContinuedProcessingHandle()
        #expect(handle.debugCompletedUnits == ContinuedProcessingHandle.Milestone.submitted.rawValue)
        #expect(!handle.debugFinished)
        #expect(!handle.debugHasTask)
    }

    /// Stream events arrive out of order often enough that a plain assignment
    /// would walk progress BACKWARDS, which the system reads as a stall.
    @MainActor @Test func advanceNeverRegressesToAnEarlierMilestone() {
        let handle = ContinuedProcessingHandle()
        handle.advance(to: .streaming)
        handle.advance(to: .accepted)
        #expect(handle.debugCompletedUnits == ContinuedProcessingHandle.Milestone.streaming.rawValue)
    }

    /// The cap is deliberate (#14): a long tail after 95 can still be culled,
    /// but reaching 100 before `finish` would report completion early.
    @MainActor @Test func tickCapsAtNinetyFive() {
        let handle = ContinuedProcessingHandle()
        for _ in 0..<500 { handle.tick() }
        #expect(handle.debugCompletedUnits == 95)
    }

    /// `sendMessage` finishes the handle at its terminal AND again after the
    /// stream loop as belt-and-braces, so non-idempotent finish would
    /// double-complete a real task — the one crash the system punishes.
    @MainActor @Test func finishSealsTheHandleAndIsIdempotent() {
        let handle = ContinuedProcessingHandle()
        handle.finish(success: false)
        #expect(handle.debugFinished)
        #expect(handle.debugFinishSuccess == false)

        // A second, contradictory terminal must not overwrite the first.
        handle.finish(success: true)
        #expect(handle.debugFinishSuccess == false)

        // And a sealed handle ignores further progress. This one caught a real
        // asymmetry: `advance` used to mutate the counter BEFORE its `finished`
        // guard while `tick` guarded first, so a sealed handle kept climbing.
        // Harmless as the code stood — `finish` nils the box — which is exactly
        // why it survived: nothing observable was wrong, so nothing caught it.
        let sealedAt = handle.debugCompletedUnits
        handle.advance(to: .streaming)
        handle.tick()
        #expect(handle.debugCompletedUnits == sealedAt)
    }

    /// The pin that licenses the migration's failure-semantics change: every
    /// lifecycle call is safe when no task ever arrives. After the migration a
    /// FAILED submission returns a live handle instead of nil, and this is the
    /// object the send path will then drive from start to finish.
    @MainActor @Test func theFullLifecycleIsSafeWhenNoTaskEverArrives() {
        let handle = ContinuedProcessingHandle()
        handle.onExpiration = {}
        handle.advance(to: .accepted)
        handle.tick()
        handle.advance(to: .streaming)
        handle.tick()
        handle.finish(success: true)
        #expect(handle.debugFinished)
        #expect(!handle.debugHasTask)
    }

    // MARK: - The send path drives the handle

    @MainActor private func makePersistence() -> UserDefaultsAppPersistenceStore {
        let suiteName = "continued-processing-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsAppPersistenceStore(defaults: defaults)
    }

    @MainActor private func makeAttachment() -> PendingAttachment {
        PendingAttachment(
            kind: .file,
            fileName: "note.txt",
            mimeType: "text/plain",
            data: Data("hello".utf8),
            localStoragePath: nil,
            thumbnailData: nil
        )
    }

    @MainActor
    private final class ScriptedClient: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .connected
        var currentConversation: Conversation?
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
            let script = self.script
            return AsyncStream { continuation in
                for update in script { continuation.yield(update) }
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

    /// Records what the send path asked for, and hands back a real handle.
    @MainActor private final class HandleRecorder {
        private(set) var subtitles: [String] = []
        private(set) var handles: [ContinuedProcessingHandle] = []
        /// Mirrors a refused registration / (pre-migration) failed submit.
        var returnsNil = false

        func begin(_ subtitle: String) -> ContinuedProcessingHandle? {
            subtitles.append(subtitle)
            guard !returnsNil else { return nil }
            let handle = ContinuedProcessingHandle()
            handles.append(handle)
            return handle
        }
    }

    @MainActor
    private func runSend(
        script: [StreamingUpdate],
        attachments: [PendingAttachment],
        recorder: HandleRecorder,
        text: String = "hi"
    ) async -> ChatStore {
        let client = ScriptedClient()
        client.script = script
        let store = ChatStore(hermesClient: client, persistence: makePersistence())
        store.beginContinuedSend = { [recorder] subtitle in recorder.begin(subtitle) }
        await store.loadConversationIfNeeded()
        await store.sendMessage(text, attachments: attachments)
        return store
    }

    private func finishedReply(_ text: String) -> StreamingUpdate {
        .finished(Message(sender: .hermes, content: text, status: .delivered), nil, nil)
    }

    /// The gate is `attachments.isEmpty` — plain turns stay lightweight. A
    /// widened gate would submit a system-visible progress task for every
    /// one-line message.
    @MainActor @Test func plainTextSendNeverRequestsAContinuedTask() async {
        let recorder = HandleRecorder()
        _ = await runSend(script: [finishedReply("ok")], attachments: [], recorder: recorder)
        #expect(recorder.subtitles.isEmpty)
    }

    @MainActor @Test func attachmentSendRequestsATaskCarryingTheDisplayContent() async {
        let recorder = HandleRecorder()
        _ = await runSend(
            script: [finishedReply("ok")],
            attachments: [makeAttachment()],
            recorder: recorder,
            text: "look at this"
        )
        #expect(recorder.subtitles == ["look at this"])
    }

    @MainActor @Test func acceptanceAdvancesTheHandleToTheAcceptedMilestone() async {
        let recorder = HandleRecorder()
        _ = await runSend(
            script: [.messageSent(jobID: UUID()), finishedReply("ok")],
            attachments: [makeAttachment()],
            recorder: recorder
        )
        let handle = try! #require(recorder.handles.first)
        #expect(handle.debugCompletedUnits == ContinuedProcessingHandle.Milestone.accepted.rawValue)
    }

    /// Past the streaming milestone rather than exactly at it: deltas advance
    /// AND tick, and it is the ticking that keeps the system from culling a
    /// long turn as stalled.
    @MainActor @Test func deltasCarryTheHandlePastTheStreamingMilestone() async {
        let recorder = HandleRecorder()
        _ = await runSend(
            script: [.messageSent(jobID: UUID()), .textDelta("He"), .textDelta("llo"), finishedReply("Hello")],
            attachments: [makeAttachment()],
            recorder: recorder
        )
        let handle = try! #require(recorder.handles.first)
        #expect(handle.debugCompletedUnits > ContinuedProcessingHandle.Milestone.streaming.rawValue)
    }

    @MainActor @Test func theFinishedTerminalCompletesTheHandleSuccessfully() async {
        let recorder = HandleRecorder()
        _ = await runSend(
            script: [.messageSent(jobID: UUID()), finishedReply("done")],
            attachments: [makeAttachment()],
            recorder: recorder
        )
        let handle = try! #require(recorder.handles.first)
        #expect(handle.debugFinished)
        #expect(handle.debugFinishSuccess == true)
    }

    @MainActor @Test func theFailedTerminalCompletesTheHandleUnsuccessfully() async {
        let recorder = HandleRecorder()
        _ = await runSend(
            script: [.failed("nope")],
            attachments: [makeAttachment()],
            recorder: recorder
        )
        let handle = try! #require(recorder.handles.first)
        #expect(handle.debugFinished)
        #expect(handle.debugFinishSuccess == false)
    }

    /// Deliberate (#14): a dropped stream whose run is still alive server-side
    /// is NOT a failure in the system progress UI — the reconcile loop owns
    /// recovery from there. Pinned because it reads like a bug otherwise.
    @MainActor @Test func theInterruptedTerminalCompletesTheHandleSuccessfully() async {
        let recorder = HandleRecorder()
        _ = await runSend(
            script: [.messageSent(jobID: UUID()), .interrupted(sessionId: "s-1", runId: "r-1")],
            attachments: [makeAttachment()],
            recorder: recorder
        )
        let handle = try! #require(recorder.handles.first)
        #expect(handle.debugFinished)
        #expect(handle.debugFinishSuccess == true)
    }

    /// **The pin the migration rests on.** `beginLongSend` currently returns
    /// nil when submission fails; the completion-handler successor reports
    /// that failure AFTER the function has returned, so the nil can no longer
    /// be produced in time and a live-but-never-adopted handle takes its
    /// place. That is only safe if the two are indistinguishable to the turn.
    ///
    /// Runs the same script both ways and compares the resulting conversation.
    @MainActor @Test func anUnadoptedHandleLeavesTheTurnIdenticalToNoHandleAtAll() async {
        func snapshot(returnsNil: Bool) async -> [String] {
            let recorder = HandleRecorder()
            recorder.returnsNil = returnsNil
            let store = await runSend(
                script: [.messageSent(jobID: UUID()), .textDelta("Hi"), finishedReply("Hi there")],
                attachments: [makeAttachment()],
                recorder: recorder
            )
            return (store.conversation?.messages ?? []).map {
                "\($0.sender)|\($0.content)|\($0.status)|\($0.isStreaming)"
            }
        }

        let withoutHandle = await snapshot(returnsNil: true)
        let withUnadoptedHandle = await snapshot(returnsNil: false)

        #expect(!withoutHandle.isEmpty)
        #expect(withUnadoptedHandle == withoutHandle)
    }
}

#endif
