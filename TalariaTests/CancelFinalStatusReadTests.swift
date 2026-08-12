import Foundation
import os
import Testing
@testable import Talaria

/// #322 — cancellation takes ONE final status read.
///
/// **Read the first bar before the others: this item exists downstream of a
/// fix it must not undo.** #292 killed a runs producer that fired ~60 requests
/// over 2 minutes; bar 322-A is a regression pin against that loop coming back
/// wearing a new name, not a feature. Everything here is built so a retry, a
/// poll, or a resurrected producer Task fails a test rather than passing
/// unnoticed.
///
/// The other half is instrument honesty (#215 / #180): a Stop must never leave
/// the CTX gauge showing the PRIOR run's numbers. The honest-unknown state is
/// **not new** — #25 already hides the gauge on an unknown numerator rather
/// than printing "CTX 0%" — so nothing here invents an error-looking state for
/// an ordinary cancel. (That was #322's kill clause; it was considered against
/// `ChatScreen.agentIdentityStrip`'s existing `currentContextTokens != nil`
/// gate and did not trigger.)
struct CancelFinalStatusReadTests {

    @MainActor private static func makePersistence() -> UserDefaultsAppPersistenceStore {
        let suiteName = "cancel-final-read-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsAppPersistenceStore(defaults: defaults)
    }

    /// A client that drives the #278 reconcile window by hand and COUNTS every
    /// `finalRunUsage` call. Counting at this seam is what makes 322-A
    /// falsifiable at the store level: a retry loop in `ChatStore` shows up as
    /// a call count, whatever the transport does.
    @MainActor
    private final class CancelProbeClient: HermesClientProtocol {
        /// What the final status read answers, and when.
        enum FinalRead {
            /// A status object carrying usage — the happy arm.
            case usage(TokenUsage)
            /// Every failure collapses here: transport error, 404 for a reaped
            /// run, or a 200 whose body has no `usage` block. The transport
            /// distinguishes them (see the URLProtocol tests below); the store
            /// has exactly one honest thing to say about all three.
            case empty
            /// Parks until `releasePark()`, then answers with the payload.
            /// This is bar 322-C's instrument: a read that CANNOT resolve, so
            /// a hung read can never be mistaken for a fast one.
            case parked(TokenUsage?)
        }

        var connectionStatus: ConnectionStatus = .connected
        var currentConversation: Conversation?
        var currentRunIsServerRecoverable = true
        var liveRunID: String?
        var activeRunID: String? { liveRunID }
        /// Models `SessionsHermesClient.hardStopActiveRun()`, whose FIRST
        /// statement is `clearActiveRunContext(...)`. Without this the
        /// read-before-clear ordering in `cancelStreaming` is untestable —
        /// a stub that keeps answering after the stop would pass whether the
        /// capture happened before or after.
        var clearsRunIDOnHardStop = false
        private(set) var hardStopCalls = 0

        @discardableResult
        func hardStopActiveRun() -> Bool {
            hardStopCalls += 1
            if clearsRunIDOnHardStop { liveRunID = nil }
            return hostStopIsIssuable
        }
        /// #328 route 2: default false — nothing was issued.
        var hostStopIsIssuable = false

        var finalRead: FinalRead = .empty
        private(set) var finalUsageCalls: [String] = []
        private(set) var continuations: [AsyncStream<StreamingUpdate>.Continuation] = []
        private(set) var sentMessages: [String] = []
        private var parkGate: CheckedContinuation<Void, Never>?

        func releasePark() {
            parkGate?.resume()
            parkGate = nil
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

        func finalRunUsage(runID: String) async -> TokenUsage? {
            finalUsageCalls.append(runID)
            switch finalRead {
            case .usage(let usage):
                return usage
            case .empty:
                return nil
            case .parked(let payload):
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    parkGate = continuation
                }
                return payload
            }
        }
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

    /// Drives the store into the real #278 window — a turn goes out, its
    /// stream reports `.interrupted` (committed server-side, connection lost)
    /// — and leaves the reconcile budget patient so nothing closes underneath
    /// the assertions. This is #321's abandon path, which is the path bar
    /// 322-A names.
    @MainActor
    private func enterReconcileWindow(
        store: ChatStore, client: CancelProbeClient, runID: String? = "R322"
    ) async {
        store.reconcileWallClockBudget = .seconds(30)
        store.reconcilePollInterval = .seconds(30)
        let task = Task { @MainActor in await store.sendMessage("dropped turn") }
        let live = await pollUntil { store.isStreaming && !client.continuations.isEmpty }
        #expect(live, "fixture: the turn must be streaming before it is interrupted")
        client.continuations.last?.yield(.interrupted(sessionId: "S322", runId: runID))
        client.continuations.last?.finish()
        _ = await task.value
        #expect(store.isTranscriptBusy, "fixture: the window's live half — a pendingRun")
        #expect(store.isStreaming == false, "fixture: the window's other half — no stream")
    }

    @MainActor
    private func makeStore(_ client: CancelProbeClient) -> ChatStore {
        ChatStore(hermesClient: client, persistence: Self.makePersistence())
    }

    private static let priorRun = TokenUsage(promptTokens: 91_000, completionTokens: 400, totalTokens: 91_400)
    private static let stoppedRun = TokenUsage(promptTokens: 4_200, completionTokens: 130, totalTokens: 4_330)

    // MARK: - 322-A: exactly one request, and #292 stays fixed

    /// **322-A.** The abandon path takes ONE read — not two, not a loop, and
    /// nothing that keeps going afterwards.
    ///
    /// The 300 ms tail is the pin that matters: #292's producer took ~2
    /// minutes to show its shape, but its FIRST repeat came fast. A retry, a
    /// poll interval, or a re-armed producer would move this counter.
    @Test @MainActor
    func theAbandonPathTakesExactlyOneStatusReadAndNeverPollsAgain() async throws {
        let client = CancelProbeClient()
        client.finalRead = .usage(Self.stoppedRun)
        let store = makeStore(client)
        await enterReconcileWindow(store: store, client: client)
        #expect(client.finalUsageCalls.isEmpty, "no read may be taken before the user cancels")

        store.cancelStreaming()

        let read = await pollUntil { client.finalUsageCalls.count == 1 }
        #expect(read, "322-A: the abandon path takes its one read")
        #expect(client.finalUsageCalls == ["R322"],
                "322-A: the read addresses the ABANDONED run, by the id the pendingRun carried")

        try? await Task.sleep(for: .milliseconds(300))
        #expect(client.finalUsageCalls.count == 1,
                "322-A: exactly one request — zero retries, zero follow-up polls (#292's loop must not return)")
        #expect(store.hasActiveReconcileLoop == false,
                "322-A: no producer Task resurrected — the abandon ended the loop and nothing re-armed it")
        #expect(store.pendingRunSessionId == nil)
    }

    /// **322-A, the other failure shape.** A read that comes back EMPTY must
    /// not tempt a second attempt. Failure is exactly as terminal as success.
    @Test @MainActor
    func aFailedReadIsNotRetried() async throws {
        let client = CancelProbeClient()
        client.finalRead = .empty
        let store = makeStore(client)
        await enterReconcileWindow(store: store, client: client)

        store.cancelStreaming()

        _ = await pollUntil { client.finalUsageCalls.count == 1 }
        try? await Task.sleep(for: .milliseconds(300))
        #expect(client.finalUsageCalls.count == 1,
                "322-A: a failed read is not retried — 'one bounded read' means one, on every arm")
        #expect(store.hasActiveReconcileLoop == false)
    }

    /// **322-A, the no-address arm.** A cancelled turn with no run id at all
    /// (the sessions plane before a run id exists, the on-device brain, any
    /// client whose plane has none) issues ZERO requests. Nothing is invented
    /// to have something to call.
    @Test @MainActor
    func aCancelWithNoRunIDIssuesNoRequestAtAll() async throws {
        let client = CancelProbeClient()
        client.finalRead = .usage(Self.stoppedRun)
        let store = makeStore(client)
        store.lastTokenUsage = Self.priorRun
        await enterReconcileWindow(store: store, client: client, runID: nil)

        store.cancelStreaming()

        try? await Task.sleep(for: .milliseconds(200))
        #expect(client.finalUsageCalls.isEmpty,
                "322-A: no run id, no request — there is nothing to address")
        #expect(store.lastTokenUsage == nil,
                "322-B: and the gauge still goes honestly unknown rather than keeping the prior run's numbers")
    }

    /// **322, the LIVE-STREAM Stop — and the one ordering only this arm can
    /// pin.** The clear-and-read is not window-only: an ordinary Stop leaves
    /// the gauge exactly as stale as the abandon does, and this item's shape
    /// section says "an explicit user cancel".
    ///
    /// The load-bearing assertion is the run id. `cancelStreaming` must
    /// capture `activeRunID` at the TOP of the function, before
    /// `hardStopActiveRun()` — whose first statement clears the client's
    /// slot — and before `abandonActiveRun()` releases the router's lock.
    /// Read it one line later and the id is nil on every Stop, no request is
    /// ever made, and the gauge goes permanently unknown while every other
    /// test here still passes. The window arm cannot catch that: it takes its
    /// id from `pendingRun`, not from the client.
    @Test @MainActor
    func aLiveStreamStopReadsTheRunItHasJustStopped() async throws {
        let client = CancelProbeClient()
        client.liveRunID = "R-live"
        client.clearsRunIDOnHardStop = true
        client.finalRead = .usage(Self.stoppedRun)
        let store = makeStore(client)
        store.lastTokenUsage = Self.priorRun

        let task = Task { @MainActor in await store.sendMessage("stop me live") }
        let live = await pollUntil { store.isStreaming && !client.continuations.isEmpty }
        #expect(live, "fixture: the turn must be streaming before the Stop")

        store.cancelStreaming()
        _ = await task.value

        #expect(client.hardStopCalls == 1)
        #expect(client.liveRunID == nil,
                "fixture: the stop cleared the client's slot, exactly as the real one does")
        let read = await pollUntil { client.finalUsageCalls.count == 1 }
        #expect(read, "322: a live-stream Stop takes the final read too, not only the window abandon")
        #expect(client.finalUsageCalls == ["R-live"],
                "the run id must be captured BEFORE hardStopActiveRun() clears it — read-before-clear")
        #expect(store.lastTokenUsage == Self.stoppedRun,
                "322-B: and the stopped run's own numbers replace the prior run's")
    }

    // MARK: - 322-B: the gauge stops lying

    /// **322-B arm 1.** A successful read carrying usage puts THAT run's
    /// numbers on the gauge — replacing, not merely clearing, the prior run's.
    @Test @MainActor
    func aSuccessfulReadPutsTheStoppedRunsOwnNumbersOnTheGauge() async throws {
        let client = CancelProbeClient()
        client.finalRead = .usage(Self.stoppedRun)
        let store = makeStore(client)
        store.lastTokenUsage = Self.priorRun
        await enterReconcileWindow(store: store, client: client)
        #expect(store.currentContextTokens == 91_000, "fixture: the stale numerator #292 accepted")

        store.cancelStreaming()

        let adopted = await pollUntil { store.currentContextTokens == 4_200 }
        #expect(adopted, "322-B: the gauge shows the STOPPED run's numbers once the read lands")
        #expect(store.lastTokenUsage == Self.stoppedRun)
    }

    /// **322-B arms 2 and 3.** Failure, a 404/expired run, and a read with no
    /// usage are one answer at this layer: honestly unknown. The bar's real
    /// clause is the second one — **never the prior run's numbers** — so the
    /// store is seeded with them first and must not be holding them at any
    /// point after the Stop.
    @Test @MainActor
    func anUnreadableRunLeavesTheGaugeUnknownAndNeverStale() async throws {
        let client = CancelProbeClient()
        client.finalRead = .empty
        let store = makeStore(client)
        store.lastTokenUsage = Self.priorRun
        await enterReconcileWindow(store: store, client: client)

        store.cancelStreaming()

        // Synchronously true the instant the Stop returns — the clear happens
        // BEFORE the read, so there is no window in which the gauge is
        // labelled for one run and showing another's tokens.
        #expect(store.lastTokenUsage == nil,
                "322-B: the prior run's numbers are gone the moment the user cancels, not when the read fails")
        #expect(store.currentContextTokens == nil,
                "322-B: an unknown numerator is the gauge's HIDE condition (#25) — not 'CTX 0%'")

        _ = await pollUntil { client.finalUsageCalls.count == 1 }
        try? await Task.sleep(for: .milliseconds(200))
        #expect(store.lastTokenUsage == nil,
                "322-B: an empty read leaves it unknown — it never falls back to the prior run")
    }

    // MARK: - 322-C: the UI never waits

    /// **322-C.** Asserted with a transport that NEVER completes, so a hung
    /// read cannot be mistaken for a fast one. #321's immediate abandon is the
    /// contract this rides behind, and these assertions run on the very next
    /// line after `cancelStreaming()` returns — before the parked read could
    /// possibly have resolved, because it cannot resolve at all.
    @Test @MainActor
    func theComposerFreesWhileTheStatusReadIsStillHung() async throws {
        let client = CancelProbeClient()
        client.finalRead = .parked(Self.stoppedRun)
        let store = makeStore(client)
        defer { client.releasePark() }
        await enterReconcileWindow(store: store, client: client)

        store.cancelStreaming()

        #expect(store.pendingRunSessionId == nil, "322-C: the run is abandoned without awaiting the read")
        #expect(store.isTranscriptBusy == false, "322-C: the composer is free while the read is still hung")
        #expect(store.hasActiveReconcileLoop == false)

        let started = await pollUntil { client.finalUsageCalls.count == 1 }
        #expect(started, "322-C: the read really is in flight — the freedom above is not a skipped read")
        try? await Task.sleep(for: .milliseconds(200))
        #expect(store.isTranscriptBusy == false, "322-C: and it stays free — nothing joins on the hung read")
        #expect(store.lastTokenUsage == nil, "322-C: the gauge reads unknown while the answer is outstanding")
    }

    // MARK: - 322-D: cancellation-safe

    /// **322-D arm 1.** A second Stop while the read is in flight neither
    /// crashes nor starts a second read: the run is already abandoned, so the
    /// second call finds nothing to cancel and issues nothing.
    @Test @MainActor
    func aSecondStopDuringTheReadNeitherCrashesNorTakesASecondRead() async throws {
        let client = CancelProbeClient()
        client.finalRead = .parked(nil)
        let store = makeStore(client)
        defer { client.releasePark() }
        await enterReconcileWindow(store: store, client: client)

        store.cancelStreaming()
        _ = await pollUntil { client.finalUsageCalls.count == 1 }
        store.cancelStreaming()
        store.cancelStreaming()

        try? await Task.sleep(for: .milliseconds(200))
        #expect(client.finalUsageCalls.count == 1,
                "322-D: a defensive re-Stop must not fire another read at a run already abandoned")
        #expect(store.pendingRunSessionId == nil)
        #expect(store.lastTokenUsage == nil)
    }

    /// **322-D arm 2 — the one that needs the generation token.** A thread
    /// switch (here: New Chat) while the read is in flight must leave the
    /// ARRIVING thread's gauge alone. Without the late-write guard the
    /// straggler would stamp the departed run's tokens onto a fresh
    /// conversation — a number that is not wrong so much as about a different
    /// thread entirely.
    @Test @MainActor
    func aWalkAwayDuringTheReadLeavesTheArrivingThreadsGaugeAlone() async throws {
        let client = CancelProbeClient()
        client.finalRead = .parked(Self.stoppedRun)
        let store = makeStore(client)
        await enterReconcileWindow(store: store, client: client)

        store.cancelStreaming()
        _ = await pollUntil { client.finalUsageCalls.count == 1 }

        try await store.clearConversation()
        #expect(store.lastTokenUsage == nil, "the fresh thread starts with no numerator")

        // The straggler now resolves, carrying the DEPARTED run's usage.
        client.releasePark()
        try? await Task.sleep(for: .milliseconds(200))

        #expect(store.lastTokenUsage == nil,
                "322-D: a read that lands after a walk-away writes NOTHING — no double-write, no cross-thread number")
        #expect(client.finalUsageCalls.count == 1)
    }

    // MARK: - 322-A/B at the TRANSPORT: one HTTP request, three failure arms

    /// Counts real `GET /v1/runs/{id}` requests. Bar 322-A says "a stubbed
    /// transport counts requests" — a client-seam counter proves `ChatStore`
    /// calls once, and this proves `SessionsHermesClient` does not turn that
    /// one call into several.
    private final class FinalReadStubURLProtocol: URLProtocol, @unchecked Sendable {
        struct Script: Sendable {
            let status: Int
            let body: String
            var failsInTransport = false
        }
        nonisolated(unsafe) static var script: Script?
        static let recorded = OSAllocatedUnfairLock<[String]>(initialState: [])

        static func reset() {
            script = nil
            recorded.withLock { $0 = [] }
        }
        static func count(_ path: String) -> Int {
            recorded.withLock { $0 }.filter { $0 == path }.count
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            Self.recorded.withLock { $0.append(request.url?.path ?? "") }
            guard let script = Self.script, !script.failsInTransport else {
                client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
                return
            }
            guard let url = request.url,
                  let response = HTTPURLResponse(
                      url: url, statusCode: script.status, httpVersion: "HTTP/1.1",
                      headerFields: ["Content-Type": "application/json"]
                  ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(script.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    @MainActor
    private func makeSessionsClient() -> SessionsHermesClient {
        let persistence = Self.makePersistence()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FinalReadStubURLProtocol.self]
        return SessionsHermesClient(
            baseURLProvider: { "http://hermes.test" },
            apiKeyProvider: { "test-key" },
            journal: ConversationJournalStore(persistence: persistence),
            transplanter: ContextTransplanter(intelligence: LocalIntelligenceService()),
            session: URLSession(configuration: configuration)
        )
    }

    /// **322-A at the wire.** One call in, exactly one `GET /v1/runs/{id}`
    /// out, and the usage decoded from the status object's own top-level
    /// `usage` block (the same Anthropic-style keys `run.completed` carries —
    /// decoded by the same `decodeRunUsage`, so the two cannot drift).
    @Test @MainActor
    func theTransportIssuesExactlyOneGetAndDecodesTheStatusUsage() async throws {
        FinalReadStubURLProtocol.reset()
        FinalReadStubURLProtocol.script = .init(
            status: 200,
            body: #"{"object":"hermes.run","run_id":"run-z1","status":"cancelled","usage":{"input_tokens":4200,"output_tokens":130,"total_tokens":4330}}"#
        )
        defer { FinalReadStubURLProtocol.reset() }

        let usage = await makeSessionsClient().finalRunUsage(runID: "run-z1")

        #expect(usage == Self.stoppedRun, "322-B: a status object carrying usage is read as that run's numbers")
        #expect(FinalReadStubURLProtocol.count("/v1/runs/run-z1") == 1,
                "322-A: exactly one HTTP request — the transport adds no retry of its own")
    }

    /// **322-B's three failure arms, distinguished where they actually
    /// differ.** The store collapses them to one honest answer; here they are
    /// separated so a future change that starts inventing a zero for one of
    /// them fails loudly. Each is also pinned at ONE request: a 404 or a
    /// transport error must not become an excuse to try again.
    @Test @MainActor
    func everyUnreadableArmReturnsNilInExactlyOneRequest() async throws {
        // Arm 1: the run was already reaped (404 — past the 1h status TTL).
        FinalReadStubURLProtocol.reset()
        FinalReadStubURLProtocol.script = .init(status: 404, body: #"{"error":"run_not_found"}"#)
        #expect(await makeSessionsClient().finalRunUsage(runID: "run-gone") == nil,
                "322-B: a 404/expired run reads as unknown")
        #expect(FinalReadStubURLProtocol.count("/v1/runs/run-gone") == 1,
                "322-A: a 404 is a verdict, not a reason to retry")

        // Arm 2: the read failed in transport.
        FinalReadStubURLProtocol.reset()
        FinalReadStubURLProtocol.script = .init(status: 200, body: "", failsInTransport: true)
        #expect(await makeSessionsClient().finalRunUsage(runID: "run-dead") == nil,
                "322-B: a transport failure reads as unknown")
        #expect(FinalReadStubURLProtocol.count("/v1/runs/run-dead") == 1,
                "322-A: a transport failure is not retried — this is #292's regression pin")

        // Arm 3: a healthy 200 whose body simply carries no usage block.
        FinalReadStubURLProtocol.reset()
        FinalReadStubURLProtocol.script = .init(
            status: 200,
            body: #"{"object":"hermes.run","run_id":"run-bare","status":"cancelled"}"#
        )
        #expect(await makeSessionsClient().finalRunUsage(runID: "run-bare") == nil,
                "322-B: no usage block is unknown — never a fabricated zero")
        #expect(FinalReadStubURLProtocol.count("/v1/runs/run-bare") == 1)

        FinalReadStubURLProtocol.reset()
    }
}
