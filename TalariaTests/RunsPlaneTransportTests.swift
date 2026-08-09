import Foundation
import os
import Testing
@testable import Talaria

/// #283 Phase 3 slice 3A, Task 4 — the runs-plane turn driver, end to end
/// against a scripted transport.
///
/// The driver replaces `POST /api/sessions/{id}/chat/stream` with
/// `POST /v1/runs` (202 + `run_id`) → `GET /v1/runs/{id}/events` (SSE), and it
/// must reach `ChatStore` through the SAME `AsyncStream<StreamingUpdate>`
/// contract the sessions plane uses — so these tests assert the update
/// SEQUENCE, not the transport's internals.
///
/// Three bars are pinned here:
///  * **3A-A** — a happy turn decodes to the sessions-plane parity sequence
///    (deltas, tool chips, reasoning, one `.finished` carrying real usage);
///  * **3A-D** — a runs `tool.started` carries NO `args` (proven upstream:
///    `api_server.py:6222-6229`), so an artifact chip is unavailable on this
///    plane. Honest absence: zero `.artifactProduced`, never a fabricated
///    chip. The #21 Tier 2 PROSE sweep still runs on the final answer;
///  * **3A-G / 3A-H** — history rides the submit body (runs never READ the
///    session transcript — N4, probed 2026-08-07), fetched BEFORE the run is
///    submitted, and attachment turns ship the single-user-message wrap.
///
/// Serialized: the stub protocol's script and request log are class-global.
@Suite(.serialized)
struct RunsPlaneTransportTests {

    // MARK: - Fixtures

    /// One request the client made, in the order the transport saw it.
    private struct RecordedRequest: Sendable {
        let method: String
        let path: String
        /// #285: the endpoint-pinning test asserts every request in a turn's
        /// family hit the turn's BIRTH host.
        let host: String
        let body: String
        /// Task 7: the `hardStopActiveRun` tests pin the `/stop` POST's auth
        /// header, not just that a request landed.
        let authorization: String?
    }

    /// Scriptable stub with the two-closure shape the loss-classification
    /// suite uses (`StreamLossClassificationTests.DroppingSSEProtocol`):
    /// `response` serves the body, `failAfterBody` optionally tears the
    /// connection down AFTER it — delayed, or the failure supersedes the
    /// response and reads as the pre-response shape.
    private final class RunsStubURLProtocol: URLProtocol, @unchecked Sendable {
        struct Script: Sendable {
            let response: @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
            let failAfterBody: @Sendable (URLRequest) -> Error?
            /// The ZOMBIE shape (#246 parity): body served, then NOTHING —
            /// no finish, no error, the connection just stays open. Distinct
            /// from `failAfterBody`, which at least ends the stream.
            let hangAfterBody: @Sendable (URLRequest) -> Bool
            /// Task 7 finding 2: an artificial delay BEFORE a matching
            /// request's response is delivered. The request log entry is
            /// written the INSTANT `startLoading` begins — before this delay
            /// — so a test can deterministically interleave a synchronous
            /// client-side call (`hardStopActiveRun()`) between "the request
            /// went out" and "the response landed" (which is what starts
            /// frame processing), rather than racing a Task.sleep poll loop
            /// against however fast this stub answers. Zero by default so no
            /// other test's timing changes.
            var responseDelay: @Sendable (URLRequest) -> TimeInterval = { _ in 0 }
        }
        nonisolated(unsafe) static var script: Script?
        /// Ordered request log — the GET-before-POST ordering assertion and
        /// the submit-body assertions both read it. Locked: URLProtocol
        /// callbacks arrive on the loader's queues, not the test's.
        static let recorded = OSAllocatedUnfairLock<[RecordedRequest]>(initialState: [])
        /// Per-path call counter, read INSIDE the script closure so a route
        /// can answer differently on its 1st, 2nd, … call — what the bounded
        /// poll loop needs ("running, running, completed") and what the
        /// stale-hop retry needs ("404, then 200").
        static let callCounts = OSAllocatedUnfairLock<[String: Int]>(initialState: [:])

        static func reset() {
            script = nil
            recorded.withLock { $0 = [] }
            callCounts.withLock { $0 = [:] }
        }

        static func requests() -> [RecordedRequest] {
            recorded.withLock { $0 }
        }

        /// Zero-based index of THIS call on `path`, incrementing the counter.
        static func nextIndex(for path: String) -> Int {
            callCounts.withLock { counts in
                let index = counts[path, default: 0]
                counts[path] = index + 1
                return index
            }
        }

        /// How many times `path` has been requested.
        static func count(_ path: String) -> Int {
            requests().filter { $0.path == path }.count
        }

        /// The first recorded request matching `method` + `path`, or nil.
        static func request(_ method: String, _ path: String) -> RecordedRequest? {
            requests().first { $0.method == method && $0.path == path }
        }

        /// Index of the first `method` + `path` request in the log.
        static func index(_ method: String, _ path: String) -> Int? {
            requests().firstIndex { $0.method == method && $0.path == path }
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let recordedRequest = RecordedRequest(
                method: request.httpMethod ?? "GET",
                path: request.url?.path ?? "",
                host: request.url?.host ?? "?",
                body: Self.bodyString(request),
                authorization: request.value(forHTTPHeaderField: "Authorization")
            )
            Self.recorded.withLock { $0.append(recordedRequest) }

            guard let script = Self.script else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            let delay = script.responseDelay(request)
            guard delay > 0 else {
                Self.deliver(script, for: self)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                Self.deliver(script, for: self)
            }
        }

        private static func deliver(_ script: Script, for protocolTask: RunsStubURLProtocol) {
            do {
                let (response, data) = try script.response(protocolTask.request)
                protocolTask.client?.urlProtocol(protocolTask, didReceive: response, cacheStoragePolicy: .notAllowed)
                protocolTask.client?.urlProtocol(protocolTask, didLoad: data)
                if let error = script.failAfterBody(protocolTask.request) {
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { [weak protocolTask] in
                        guard let protocolTask else { return }
                        protocolTask.client?.urlProtocol(protocolTask, didFailWithError: error)
                    }
                } else if script.hangAfterBody(protocolTask.request) {
                    // Deliberately NOTHING: the connection stays open forever
                    // and only the stall guard can end this turn.
                } else {
                    protocolTask.client?.urlProtocolDidFinishLoading(protocolTask)
                }
            } catch {
                protocolTask.client?.urlProtocol(protocolTask, didFailWithError: error)
            }
        }

        override func stopLoading() {}

        /// URLSession moves `httpBody` into `httpBodyStream` before a protocol
        /// ever sees the request, so reading only `httpBody` returns nothing.
        static func bodyString(_ request: URLRequest) -> String {
            if let body = request.httpBody { return String(decoding: body, as: UTF8.self) }
            guard let stream = request.httpBodyStream else { return "" }
            stream.open()
            defer { stream.close() }
            var data = Data()
            let capacity = 4096
            var buffer = [UInt8](repeating: 0, count: capacity)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: capacity)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            return String(decoding: data, as: UTF8.self)
        }
    }

    /// The runs dialect has NO `event:` lines — every frame is one `data:`
    /// line carrying the event name inside the JSON (`parseRunsFrame`'s
    /// dialect note). The leading comment pads past URLSession's
    /// custom-protocol flush threshold (~512B); below it the body sits
    /// unflushed and never reaches the task. The trailing comment mirrors the
    /// real stream's close.
    private static func runsSSE(_ frames: [String]) -> String {
        let padding = ": " + String(repeating: "-", count: 600) + "\n\n"
        return padding + frames.map { "data: \($0)\n\n" }.joined() + ": stream closed\n\n"
    }

    /// The stored-messages fixture: the two-row server transcript the history
    /// pre-fetch reads. `KUMQUAT-N4A` is the N4 probe's continuity marker.
    private static let messagesFixture = #"""
    {"session_id":"sess-r","data":[
      {"id":1,"role":"user","content":"KUMQUAT-N4A","timestamp":1754000000.0},
      {"id":2,"role":"assistant","content":"noted","timestamp":1754000005.0}
    ]}
    """#

    /// The default status-poll body: a run still going. With this, the poll
    /// seam is exercised as "not terminal yet" and the caller falls through
    /// to `.interrupted`.
    private static let runningStatus = #"{"object":"hermes.run","run_id":"run-r1","status":"running"}"#

    /// Picks the entry for call number `index` on a route, with the LAST
    /// entry repeating forever — so `[a]` is "always a" and `[a, b]` is
    /// "a once, then b from then on".
    private static func atCall<T>(_ values: [T], _ index: Int) -> T {
        values[min(index, values.count - 1)]
    }

    /// Routes the four endpoints one runs turn touches. Suffix/exact path
    /// match, mirroring the sessions-plane stubs.
    ///
    /// `eventsStatus` + `failEventsAfterBody` + `hangEventsAfterBody` are what
    /// let the loss tests script the three ways an events subscription dies:
    /// refused outright (non-2xx), opened then torn down mid-stream, or opened
    /// and left hanging (the zombie).
    ///
    /// The three `status*` parameters are per-call SEQUENCES (see `atCall`):
    /// a run that is still going on the first read and finished on the
    /// second is the whole point of the bounded poll loop, and a single read
    /// cannot express it.
    private static func script(
        sseBody: String,
        messagesBody: String = RunsPlaneTransportTests.messagesFixture,
        messagesStatuses: [Int] = [200],
        statusBodies: [String] = [RunsPlaneTransportTests.runningStatus],
        statusCodes: [Int] = [200],
        statusTransportFailures: Set<Int> = [],
        eventsStatus: Int = 200,
        failEventsAfterBody: URLError.Code? = nil,
        hangEventsAfterBody: Bool = false,
        eventsResponseDelay: TimeInterval = 0,
        /// Review of #279, Task 7 fix: makes `/v1/runs/run-r1/stop` die at the
        /// TRANSPORT level (never an HTTP response at all) — the same shape
        /// `statusTransportFailures` gives the status GET — so a test can pin
        /// `hardStopActiveRun()`'s behavior when its own POST never reaches
        /// the host.
        stopTransportFails: Bool = false
    ) -> RunsStubURLProtocol.Script {
        RunsStubURLProtocol.Script(
            response: { request in
                guard let url = request.url else { throw URLError(.badURL) }
                func reply(_ status: Int, _ body: String, contentType: String = "application/json") throws -> (HTTPURLResponse, Data) {
                    guard let response = HTTPURLResponse(
                        url: url,
                        statusCode: status,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": contentType]
                    ) else { throw URLError(.badServerResponse) }
                    return (response, Data(body.utf8))
                }
                switch url.path {
                case "/api/sessions":
                    return try reply(200, #"{"session":{"id":"sess-r"}}"#)
                case "/api/sessions/sess-r/messages":
                    let call = RunsStubURLProtocol.nextIndex(for: url.path)
                    let status = atCall(messagesStatuses, call)
                    guard status == 200 else {
                        // The stale-hop shape: the persisted hop's server
                        // session is gone, so its transcript 404s.
                        return try reply(status, #"{"error":"Session not found"}"#)
                    }
                    return try reply(200, messagesBody)
                case "/v1/runs":
                    return try reply(202, #"{"run_id":"run-r1","status":"started"}"#)
                case "/v1/runs/run-r1/events":
                    return try reply(eventsStatus, sseBody, contentType: "text/event-stream")
                case "/v1/runs/run-r1/stop":
                    // Task 7: the real server-side interrupt. The response
                    // body is never decoded by `hardStopActiveRun` — it fires
                    // and forgets — so an empty object is enough.
                    if stopTransportFails { throw URLError(.networkConnectionLost) }
                    return try reply(200, "{}")
                case "/v1/runs/run-r1":
                    let call = RunsStubURLProtocol.nextIndex(for: url.path)
                    // A flaky GET: the connection dies before any response.
                    // Recovery must survive one of these, not end on it.
                    if statusTransportFailures.contains(call) { throw URLError(.networkConnectionLost) }
                    return try reply(atCall(statusCodes, call), atCall(statusBodies, call))
                default:
                    throw URLError(.badURL)
                }
            },
            failAfterBody: { request in
                guard let code = failEventsAfterBody,
                      request.url?.path == "/v1/runs/run-r1/events" else { return nil }
                return URLError(code)
            },
            hangAfterBody: { request in
                hangEventsAfterBody && request.url?.path == "/v1/runs/run-r1/events"
            },
            responseDelay: { request in
                request.url?.path == "/v1/runs/run-r1/events" ? eventsResponseDelay : 0
            }
        )
    }

    /// #285: lets the endpoint-pinning test flip the "active profile's" base
    /// URL mid-turn, the way a real profile switch moves the live providers.
    @MainActor
    private final class MutableBaseURLBox {
        var value: String
        init(_ value: String) { self.value = value }
    }

    @MainActor
    private func makeClient(
        label: String,
        persistedHop: String? = nil,
        baseURLBox: MutableBaseURLBox? = nil
    ) -> SessionsHermesClient {
        let suiteName = "runs-plane-\(label)-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RunsStubURLProtocol.self]

        let journal = ConversationJournalStore(persistence: persistence)
        // A hop persisted from a previous launch — the only state under which
        // the stale-hop retry is allowed to fire (`PreparedHop.wasReused`).
        // The journal stays EMPTY on purpose: the re-hop then has nothing to
        // transplant, which keeps `ContextTransplanter` (and the on-device
        // model behind it) out of a unit test.
        if let persistedHop {
            journal.beginHop(apiSessionId: persistedHop, primingUsage: nil, profileID: nil)
        }

        let client = SessionsHermesClient(
            baseURLProvider: { baseURLBox?.value ?? "http://hermes.test" },
            apiKeyProvider: { "test-key" },
            journal: journal,
            transplanter: ContextTransplanter(intelligence: LocalIntelligenceService()),
            session: URLSession(configuration: configuration)
        )
        // Task 5 pins both directions of the dispatch; here it just arms the
        // runs path so the driver is what runs.
        client.useRunsTransportProvider = { true }
        // Task 6: the recovery poll's knobs, shortened suite-wide. Production
        // is 2s/120s — a still-running run would park every loss test on the
        // 10s belt and report a hang instead of an outcome.
        client.runsPollInterval = .milliseconds(40)
        client.runsPollBudget = .milliseconds(800)
        return client
    }

    /// #283 review re-review: a real `ChatStore` wired to a real (test-stub)
    /// `SessionsHermesClient` — needed for the `cancelStreaming(hardStopHost:)`
    /// residual pins, which have to exercise `ChatStore`'s own gating logic,
    /// not just the client's.
    @MainActor
    private func makeChatStore(hermesClient: SessionsHermesClient) -> ChatStore {
        let suiteName = "runs-plane-chatstore-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return ChatStore(hermesClient: hermesClient, persistence: UserDefaultsAppPersistenceStore(defaults: defaults))
    }

    /// One turn, collected with the 10s hang belt every test in this suite
    /// uses: the belt CANCELS the collector, and cancellation genuinely ends
    /// `AsyncStream` iteration, so awaiting `.value` cannot strand.
    @MainActor
    private func collect(
        from client: SessionsHermesClient,
        message: String = "hi",
        attachments: [PendingAttachment] = []
    ) async -> [StreamingUpdate] {
        let collector = Task { @MainActor in
            var updates: [StreamingUpdate] = []
            for await update in client.sendStreaming(
                message: message,
                attachments: attachments,
                clientMessageID: UUID()
            ) {
                updates.append(update)
            }
            return updates
        }
        let belt = Task {
            try? await Task.sleep(for: .seconds(10))
            collector.cancel()
        }
        let updates = await collector.value
        belt.cancel()
        return updates
    }

    /// Compact, order-preserving labels for sequence assertions.
    private func labels(_ updates: [StreamingUpdate]) -> [String] {
        updates.map { update in
            switch update {
            case .messageSent: return "messageSent"
            case .textDelta(let text): return "textDelta(\(text))"
            case .reasoningDelta(let text): return "reasoningDelta(\(text))"
            case .toolActivity(let event):
                return "toolActivity(\(event.name):\(event.phase == .started ? "started" : "completed"))"
            case .artifactProduced: return "artifactProduced"
            case .contextPrimed: return "contextPrimed"
            case .modelResolved: return "modelResolved"
            case .finished: return "finished"
            case .failed(let text): return "failed(\(text))"
            case .unreachable(let text): return "unreachable(\(text))"
            case .interrupted: return "interrupted"
            }
        }
    }

    private func finishedPayload(_ updates: [StreamingUpdate]) -> (message: Message, usage: TokenUsage?)? {
        for update in updates {
            if case let .finished(message, usage, _) = update { return (message, usage) }
        }
        return nil
    }

    // MARK: - 3A-A: happy-path parity

    @Test @MainActor
    func happyTurnDecodesToParitySequence() async throws {
        RunsStubURLProtocol.reset()
        RunsStubURLProtocol.script = Self.script(sseBody: Self.runsSSE([
            #"{"event":"message.delta","run_id":"run-r1","timestamp":1.0,"delta":"Hel"}"#,
            #"{"event":"message.delta","run_id":"run-r1","timestamp":1.1,"delta":"lo"}"#,
            #"{"event":"tool.started","run_id":"run-r1","timestamp":1.2,"tool":"shell","preview":"ls -la"}"#,
            #"{"event":"tool.completed","run_id":"run-r1","timestamp":1.3,"tool":"shell"}"#,
            #"{"event":"reasoning.available","run_id":"run-r1","timestamp":1.4,"text":"thinking…"}"#,
            #"{"event":"run.completed","run_id":"run-r1","timestamp":1.5,"output":"Hello answer","usage":{"input_tokens":10,"output_tokens":2,"total_tokens":12}}"#,
        ]))
        defer { RunsStubURLProtocol.reset() }

        let client = makeClient(label: "happy")
        let updates = await collect(from: client)

        #expect(labels(updates) == [
            "textDelta(Hel)",
            "textDelta(lo)",
            "toolActivity(shell:started)",
            "toolActivity(shell:completed)",
            "reasoningDelta(thinking…)",
            "finished",
        ])

        let finished = try #require(finishedPayload(updates))
        #expect(finished.message.content == "Hello answer")
        #expect(finished.message.reasoning == "thinking…")
        #expect(finished.usage?.totalTokens == 12)
        #expect(finished.usage?.promptTokens == 10)

        // Exactly ONE terminal yield: a second `.finished` (or a `.finished`
        // plus an `.interrupted` chaser from the clean close) is the
        // duplicate-bubble shape #240/#235 exist to prevent.
        #expect(updates.filter { if case .finished = $0 { return true } else { return false } }.count == 1)
        #expect(!updates.contains { if case .interrupted = $0 { return true } else { return false } })
        // No transplant happened (fresh journal), so no priming receipt may
        // be fabricated — and `.modelResolved` has no source on this plane at
        // all (runs `run.completed` carries no runtime block).
        #expect(!updates.contains { if case .contextPrimed = $0 { return true } else { return false } })
        #expect(!updates.contains { if case .modelResolved = $0 { return true } else { return false } })
    }

    // MARK: - 3A-G: history rides the submit body, fetched first

    @Test @MainActor
    func historyRidesTheSubmitBody() async throws {
        RunsStubURLProtocol.reset()
        RunsStubURLProtocol.script = Self.script(sseBody: Self.runsSSE([
            #"{"event":"run.completed","run_id":"run-r1","timestamp":1.5,"output":"ok","usage":{"input_tokens":1,"output_tokens":1,"total_tokens":2}}"#,
        ]))
        defer { RunsStubURLProtocol.reset() }

        let client = makeClient(label: "history")
        _ = await collect(from: client)

        let submit = try #require(RunsStubURLProtocol.request("POST", "/v1/runs"))
        let body = try #require(
            JSONSerialization.jsonObject(with: Data(submit.body.utf8)) as? [String: Any]
        )
        #expect(body["session_id"] as? String == "sess-r")
        #expect(body["input"] as? String == "hi")
        let history = try #require(body["conversation_history"] as? [[String: Any]])
        #expect(history.count == 2)
        #expect(history[0]["role"] as? String == "user")
        #expect(history[0]["content"] as? String == "KUMQUAT-N4A")
        #expect(history[1]["role"] as? String == "assistant")
        #expect(history[1]["content"] as? String == "noted")

        // Ordering is the load-bearing half: runs never READ the session
        // transcript (N4), so the pre-fetch has to complete BEFORE the run is
        // submitted or the turn ships contextless.
        let messagesIndex = try #require(RunsStubURLProtocol.index("GET", "/api/sessions/sess-r/messages"))
        let submitIndex = try #require(RunsStubURLProtocol.index("POST", "/v1/runs"))
        #expect(messagesIndex < submitIndex)
    }

    // MARK: - 3A-D: honest artifact absence

    @Test @MainActor
    func writeFileToolStartedProducesNoArtifact() async throws {
        RunsStubURLProtocol.reset()
        RunsStubURLProtocol.script = Self.script(sseBody: Self.runsSSE([
            #"{"event":"tool.started","run_id":"run-r1","timestamp":1.0,"tool":"write_file","preview":"O:\\Hermes\\MobileDL\\a.txt"}"#,
            #"{"event":"tool.completed","run_id":"run-r1","timestamp":1.1,"tool":"write_file"}"#,
            #"{"event":"run.completed","run_id":"run-r1","timestamp":1.2,"output":"Saved it to MobileDL/report.txt for you.","usage":{"input_tokens":3,"output_tokens":3,"total_tokens":6}}"#,
        ]))
        defer { RunsStubURLProtocol.reset() }

        let client = makeClient(label: "artifact")
        let updates = await collect(from: client)

        // The tool chip still arrives — the pill is real activity.
        #expect(updates.contains {
            if case let .toolActivity(event) = $0 { return event.name == "write_file" && event.phase == .started }
            return false
        })
        // …but the runs `tool.started` has no `args`, so nothing can be
        // reconstructed from it. Zero artifact chips, and the preview's
        // MobileDL path must NOT be laundered into an attachment either: a
        // tool-payload path is not an announced-file claim on this plane.
        #expect(!updates.contains { if case .artifactProduced = $0 { return true } else { return false } })

        let finished = try #require(finishedPayload(updates))
        // The #21 Tier 2 PROSE sweep survives — it reads the assistant's own
        // answer, not tool args, so it is legitimate here and still runs.
        #expect(finished.message.attachments.count == 1)
        #expect(finished.message.attachments.first?.remotePath == "report.txt")
        // A fetchable pointer, not staged bytes — nothing was reconstructed.
        #expect(finished.message.attachments.allSatisfy { $0.localStoragePath == nil })
    }

    // MARK: - 3A-H: the attachment wrap

    @Test @MainActor
    func attachmentTurnSubmitsMessageArrayWrap() async throws {
        RunsStubURLProtocol.reset()
        RunsStubURLProtocol.script = Self.script(sseBody: Self.runsSSE([
            #"{"event":"run.completed","run_id":"run-r1","timestamp":1.0,"output":"red","usage":{"input_tokens":1,"output_tokens":1,"total_tokens":2}}"#,
        ]))
        defer { RunsStubURLProtocol.reset() }

        let client = makeClient(label: "attachment")
        _ = await collect(
            from: client,
            message: "what color?",
            attachments: [PendingAttachment.stubTransmittableImage()]
        )

        let submit = try #require(RunsStubURLProtocol.request("POST", "/v1/runs"))
        let body = try #require(
            JSONSerialization.jsonObject(with: Data(submit.body.utf8)) as? [String: Any]
        )
        // The 3A-0 probe proved a bare parts array 400s on /v1/runs; the
        // single-user-message wrap is the shape that reaches the agent.
        let input = try #require(body["input"] as? [[String: Any]], "attachment input must be a MESSAGE array")
        #expect(input.count == 1)
        #expect(input[0]["role"] as? String == "user")
        let parts = try #require(input[0]["content"] as? [[String: Any]])
        #expect(parts.contains { $0["type"] as? String == "text" })
        #expect(parts.contains { $0["type"] as? String == "image_url" })
    }

    // MARK: - Loss and recovery (the poll seam)

    /// The mid-stream drop: partial deltas arrive, then the connection dies
    /// with no terminal frame, and the run is STILL RUNNING when polled. The
    /// run is committed server-side, so this must arm recovery
    /// (`.interrupted`) — never `.failed` (a dead end the user must retry) and
    /// never `.unreachable` (which parks the turn in the compose outbox and
    /// re-sends it, making Hermes answer twice, #240).
    @Test @MainActor
    func droppedStreamOnALiveRunArmsRecovery() async throws {
        RunsStubURLProtocol.reset()
        RunsStubURLProtocol.script = Self.script(
            sseBody: Self.runsSSE([
                #"{"event":"message.delta","run_id":"run-r1","timestamp":1.0,"delta":"Par"}"#,
                #"{"event":"message.delta","run_id":"run-r1","timestamp":1.1,"delta":"tial"}"#,
            ]),
            // The poll finds the run still going — nothing terminal to deliver.
            statusBodies: [Self.runningStatus],
            failEventsAfterBody: .networkConnectionLost
        )
        defer { RunsStubURLProtocol.reset() }

        let client = makeClient(label: "drop")
        let updates = await collect(from: client)

        // The deltas that DID arrive are still delivered — a drop loses the
        // rest of the stream, not what already landed.
        #expect(labels(updates).prefix(2) == ["textDelta(Par)", "textDelta(tial)"])

        let interruptions = updates.compactMap { update -> (String, String?)? in
            if case let .interrupted(sessionId, runId) = update { return (sessionId, runId) }
            return nil
        }
        #expect(interruptions.count == 1, "exactly one terminal yield, and it must be the recovery one")
        #expect(interruptions.first?.0 == "sess-r")
        #expect(interruptions.first?.1 == "run-r1")
        #expect(!updates.contains { if case .finished = $0 { return true } else { return false } })
        #expect(!updates.contains { if case .failed = $0 { return true } else { return false } })
        #expect(!updates.contains { if case .unreachable = $0 { return true } else { return false } })
        // Deliberately NOT asserting whether the poll ran here: a THROWN
        // stream takes the catch classification, which in Task 4 yields
        // recovery directly. Task 6 is what puts the bounded poll in front of
        // it; pinning today's absence would just book a failure for that task.
    }

    /// The clean close: the stream ENDS without a terminal frame (no error to
    /// classify). This is the branch that enters the poll seam, and with the
    /// run still live the poll has nothing terminal to deliver — so it falls
    /// through to the same recovery yield.
    @Test @MainActor
    func cleanCloseWithNoTerminalFramePollsThenArmsRecovery() async throws {
        RunsStubURLProtocol.reset()
        RunsStubURLProtocol.script = Self.script(
            sseBody: Self.runsSSE([
                #"{"event":"message.delta","run_id":"run-r1","timestamp":1.0,"delta":"Half "}"#,
                #"{"event":"tool.started","run_id":"run-r1","timestamp":1.1,"tool":"shell","preview":"ls"}"#,
            ]),
            statusBodies: [Self.runningStatus]
        )
        defer { RunsStubURLProtocol.reset() }

        let client = makeClient(label: "clean-close")
        let updates = await collect(from: client)

        // The poll seam was actually entered — without this assertion the
        // test would also pass on a driver that never polls at all.
        #expect(RunsStubURLProtocol.index("GET", "/v1/runs/run-r1") != nil)

        let interruptions = updates.compactMap { update -> (String, String?)? in
            if case let .interrupted(sessionId, runId) = update { return (sessionId, runId) }
            return nil
        }
        #expect(interruptions.count == 1)
        #expect(interruptions.first?.0 == "sess-r")
        #expect(interruptions.first?.1 == "run-r1")
        #expect(!updates.contains { if case .finished = $0 { return true } else { return false } })
        #expect(!updates.contains { if case .failed = $0 { return true } else { return false } })
    }

    /// The subscribe miss: `GET /events` 404s (the run finished before we
    /// attached, or the registration race was lost). The stream carries no
    /// answer, but the status object does — for an hour — so the turn still
    /// finishes with the real output and usage rather than degrading.
    @Test @MainActor
    func eventsSubscribeMissRecoversTheAnswerFromTheStatusPoll() async throws {
        RunsStubURLProtocol.reset()
        RunsStubURLProtocol.script = Self.script(
            sseBody: #"{"error":{"message":"Run not found: run-r1","code":"run_not_found"}}"#,
            statusBodies: [#"""
            {"object":"hermes.run","run_id":"run-r1","status":"completed",
             "output":"Polled answer","usage":{"input_tokens":7,"output_tokens":4,"total_tokens":11}}
            """#],
            eventsStatus: 404
        )
        defer { RunsStubURLProtocol.reset() }

        let client = makeClient(label: "subscribe-miss")
        let updates = await collect(from: client)

        let finishes = updates.filter { if case .finished = $0 { return true } else { return false } }
        #expect(finishes.count == 1)
        let finished = try #require(finishedPayload(updates))
        #expect(finished.message.content == "Polled answer")
        #expect(finished.usage?.totalTokens == 11)
        #expect(finished.usage?.promptTokens == 7)
        #expect(!updates.contains { if case .interrupted = $0 { return true } else { return false } })
        #expect(!updates.contains { if case .failed = $0 { return true } else { return false } })
    }

    /// #285 (the #283 adjacency): a runs turn is MANY requests over wall
    /// clock — history GET, submit, events subscribe, then status polls.
    /// Before the fix each request re-resolved the ACTIVE endpoint at build
    /// time, so a profile switch landing mid-turn redirected the turn's later
    /// polls to the NEW host. Now the turn resolves a `ResolvedEndpoint` once
    /// at birth and every request in its family carries it.
    ///
    /// Determinism: the events response is DELAYED (`eventsResponseDelay`),
    /// and the request log is written the instant `startLoading` begins — so
    /// the flip lands after the subscribe request is recorded and before its
    /// (404) response starts the poll loop. Every status poll is post-flip.
    @Test @MainActor
    func aMidTurnBaseURLChangeCannotRedirectALiveTurnsRequests() async throws {
        RunsStubURLProtocol.reset()
        RunsStubURLProtocol.script = Self.script(
            sseBody: #"{"error":{"message":"Run not found: run-r1","code":"run_not_found"}}"#,
            statusBodies: [
                Self.runningStatus,
                #"{"object":"hermes.run","run_id":"run-r1","status":"completed","output":"pinned","usage":{"input_tokens":3,"output_tokens":2,"total_tokens":5}}"#,
            ],
            eventsStatus: 404,
            eventsResponseDelay: 0.3
        )
        defer { RunsStubURLProtocol.reset() }

        let baseURL = MutableBaseURLBox("http://hermes.test")
        let client = makeClient(label: "endpoint-pin", baseURLBox: baseURL)

        let collector = Task { @MainActor in await collect(from: client) }
        // The switch, mid-turn: as soon as the events subscribe is RECORDED,
        // flip the live base URL — the moved-scope half of a profile switch.
        while RunsStubURLProtocol.count("/v1/runs/run-r1/events") == 0 {
            try await Task.sleep(for: .milliseconds(5))
        }
        baseURL.value = "http://hermes-b.test"
        let updates = await collector.value

        // The turn finished with the polled answer…
        let finished = try #require(finishedPayload(updates))
        #expect(finished.message.content == "pinned")
        // …polling really happened, all of it post-flip…
        #expect(RunsStubURLProtocol.count("/v1/runs/run-r1") >= 1)
        // …and EVERY request the turn made hit the birth host. The flipped
        // host saw nothing.
        let hosts = Set(RunsStubURLProtocol.requests().map(\.host))
        #expect(hosts == ["hermes.test"])
    }

    /// #235 F1 on the poll path: a run the host calls `completed` while
    /// carrying NO answer text anywhere (empty `output`, no streamed deltas).
    /// Delivering that as `.finished` paints an empty bubble AND suppresses
    /// recovery — the exact shape the sessions plane converts to
    /// `.interrupted` via `cleanCloseArmsRecovery`. The runs plane reuses that
    /// same guard.
    @Test @MainActor
    func completedStatusWithNoAnswerTextArmsRecoveryInsteadOfAnEmptyBubble() async throws {
        RunsStubURLProtocol.reset()
        RunsStubURLProtocol.script = Self.script(
            sseBody: #"{"error":{"message":"Run not found: run-r1","code":"run_not_found"}}"#,
            statusBodies: [#"{"object":"hermes.run","run_id":"run-r1","status":"completed","output":"","usage":{"input_tokens":7,"output_tokens":0,"total_tokens":7}}"#],
            eventsStatus: 404
        )
        defer { RunsStubURLProtocol.reset() }

        let client = makeClient(label: "empty-completed")
        let updates = await collect(from: client)

        #expect(!updates.contains { if case .finished = $0 { return true } else { return false } },
                "an empty answer must never be delivered as a finished message")
        let interruptions = updates.filter { if case .interrupted = $0 { return true } else { return false } }
        #expect(interruptions.count == 1)
        // Task 6 interaction, stated rather than assumed: `completed` is
        // TERMINAL, so the bounded loop must stop on the first read even
        // though the guard then converts it to recovery. A loop that kept
        // polling for an answer that will never appear would burn the whole
        // budget on every empty run.
        #expect(RunsStubURLProtocol.count("/v1/runs/run-r1") == 1)
    }

    // MARK: - Task 6: the bounded poll loop

    /// 3A-B + the #237 pin: the stream is KILLED mid-turn while the run is
    /// still going, and the answer arrives on a LATER status read. The loop is
    /// what makes this recoverable — a single read (Task 4's seam) would have
    /// seen `running` and degraded to `.interrupted`, losing an answer the
    /// host was about to have.
    @Test @MainActor
    func killedStreamRecoversFinalAnswerViaStatusPollExactlyOnce() async throws {
        RunsStubURLProtocol.reset()
        RunsStubURLProtocol.script = Self.script(
            sseBody: Self.runsSSE([
                #"{"event":"message.delta","run_id":"run-r1","timestamp":1.0,"delta":"FUL"}"#,
            ]),
            // Still going on the first read, finished on every read after it.
            statusBodies: [
                Self.runningStatus,
                #"{"object":"hermes.run","run_id":"run-r1","status":"completed","output":"FULL ANSWER","usage":{"input_tokens":9,"output_tokens":3,"total_tokens":12}}"#,
            ],
            failEventsAfterBody: .networkConnectionLost
        )
        defer { RunsStubURLProtocol.reset() }

        let client = makeClient(label: "poll-recovers")
        let updates = await collect(from: client)

        let finishes = updates.filter { if case .finished = $0 { return true } else { return false } }
        #expect(finishes.count == 1, "exactly one terminal yield — a second is the #237 double-bubble")
        let finished = try #require(finishedPayload(updates))
        // The authoritative answer is the status object's `output`, NOT the
        // partial delta that arrived before the stream died.
        #expect(finished.message.content == "FULL ANSWER")
        #expect(finished.usage?.totalTokens == 12)
        #expect(finished.usage?.promptTokens == 9)
        #expect(!updates.contains { if case .failed = $0 { return true } else { return false } })
        #expect(!updates.contains { if case .unreachable = $0 { return true } else { return false } })
        #expect(!updates.contains { if case .interrupted = $0 { return true } else { return false } })
        // The LOOP is the thing under test: one read would have found only
        // `running`. Without this the test would pass on a lucky single read.
        #expect(RunsStubURLProtocol.count("/v1/runs/run-r1") >= 2)
    }

    /// The #237 shape pinned from the other side: a turn that finished on the
    /// STREAM must never also poll. Polling after a delivered answer is how a
    /// second terminal yield gets minted.
    @Test @MainActor
    func streamCompletionSuppressesThePollPath() async throws {
        RunsStubURLProtocol.reset()
        RunsStubURLProtocol.script = Self.script(
            sseBody: Self.runsSSE([
                #"{"event":"message.delta","run_id":"run-r1","timestamp":1.0,"delta":"Done"}"#,
                #"{"event":"run.completed","run_id":"run-r1","timestamp":1.1,"output":"Done","usage":{"input_tokens":4,"output_tokens":1,"total_tokens":5}}"#,
            ]),
            // If the driver polled anyway it would find a DIFFERENT answer
            // here — so a stray poll cannot hide behind a matching fixture.
            statusBodies: [#"{"object":"hermes.run","run_id":"run-r1","status":"completed","output":"POLLED (must not appear)"}"#]
        )
        defer { RunsStubURLProtocol.reset() }

        let client = makeClient(label: "no-poll-after-finish")
        let updates = await collect(from: client)

        let finishes = updates.filter { if case .finished = $0 { return true } else { return false } }
        #expect(finishes.count == 1)
        let finished = try #require(finishedPayload(updates))
        #expect(finished.message.content == "Done")
        #expect(RunsStubURLProtocol.count("/v1/runs/run-r1") == 0,
                "a completed stream must not touch the status endpoint at all")
        #expect(!updates.contains { if case .interrupted = $0 { return true } else { return false } })
    }

    /// The budget is a real bound, not decoration: a run that never finishes
    /// must hand off to the existing `.interrupted` machinery (ChatStore's
    /// pendingRun reconcile — unchanged in 3A) rather than spin, and it must
    /// never be reported as a FAILURE, which is a dead end the user has to
    /// retry by hand.
    @Test @MainActor
    func pollBudgetExpiryYieldsInterruptedNotFailed() async throws {
        RunsStubURLProtocol.reset()
        RunsStubURLProtocol.script = Self.script(
            sseBody: Self.runsSSE([
                #"{"event":"message.delta","run_id":"run-r1","timestamp":1.0,"delta":"Still"}"#,
            ]),
            statusBodies: [Self.runningStatus],
            failEventsAfterBody: .networkConnectionLost
        )
        defer { RunsStubURLProtocol.reset() }

        let client = makeClient(label: "budget-expiry")
        let updates = await collect(from: client)

        let interruptions = updates.compactMap { update -> (String, String?)? in
            if case let .interrupted(sessionId, runId) = update { return (sessionId, runId) }
            return nil
        }
        #expect(interruptions.count == 1)
        #expect(interruptions.first?.0 == "sess-r")
        #expect(interruptions.first?.1 == "run-r1")
        #expect(!updates.contains { if case .finished = $0 { return true } else { return false } })
        #expect(!updates.contains { if case .failed = $0 { return true } else { return false } })
        // It kept polling across the budget rather than giving up on the
        // first `running` — and it did stop, or the 10s belt would have
        // ended this test instead of the budget.
        #expect(RunsStubURLProtocol.count("/v1/runs/run-r1") >= 2)
    }

    /// TTL expiry / wrong host: `GET /v1/runs/{id}` 404s `run_not_found`.
    /// Polling harder cannot conjure a run the gateway has forgotten, so the
    /// loop must bail on the FIRST 404 — the budget is for runs that might
    /// still finish.
    @Test @MainActor
    func runNotFoundStatusBailsPromptlyToRecovery() async throws {
        RunsStubURLProtocol.reset()
        RunsStubURLProtocol.script = Self.script(
            sseBody: Self.runsSSE([
                #"{"event":"message.delta","run_id":"run-r1","timestamp":1.0,"delta":"Orphan"}"#,
            ]),
            statusBodies: [#"{"error":{"message":"Run not found: run-r1","code":"run_not_found"}}"#],
            statusCodes: [404]
        )
        defer { RunsStubURLProtocol.reset() }

        let client = makeClient(label: "run-not-found")
        let updates = await collect(from: client)

        #expect(RunsStubURLProtocol.count("/v1/runs/run-r1") == 1,
                "a 404 is terminal news about the run — re-reading it is pure delay")
        let interruptions = updates.filter { if case .interrupted = $0 { return true } else { return false } }
        #expect(interruptions.count == 1)
        #expect(!updates.contains { if case .finished = $0 { return true } else { return false } })
        #expect(!updates.contains { if case .failed = $0 { return true } else { return false } })
    }

    /// One flaky GET must not end a recovery. The status read dies in
    /// transport on its first attempt; the retry finds the finished run and
    /// the answer still lands.
    @Test @MainActor
    func aFlakyStatusGetDoesNotKillRecovery() async throws {
        RunsStubURLProtocol.reset()
        RunsStubURLProtocol.script = Self.script(
            sseBody: Self.runsSSE([
                #"{"event":"message.delta","run_id":"run-r1","timestamp":1.0,"delta":"Half"}"#,
            ]),
            statusBodies: [#"{"object":"hermes.run","run_id":"run-r1","status":"completed","output":"Recovered anyway","usage":{"input_tokens":2,"output_tokens":2,"total_tokens":4}}"#],
            // The first status GET never gets a response at all.
            statusTransportFailures: [0]
        )
        defer { RunsStubURLProtocol.reset() }

        let client = makeClient(label: "flaky-status")
        let updates = await collect(from: client)

        let finished = try #require(finishedPayload(updates))
        #expect(finished.message.content == "Recovered anyway")
        #expect(finished.usage?.totalTokens == 4)
        #expect(updates.filter { if case .finished = $0 { return true } else { return false } }.count == 1)
        #expect(!updates.contains { if case .interrupted = $0 { return true } else { return false } })
        #expect(RunsStubURLProtocol.count("/v1/runs/run-r1") >= 2)
    }

    /// #246 parity through the runs loop: 2xx, a partial body, then the
    /// connection just HANGS. Nothing throws on its own, so only the stall
    /// guard can end this turn — and it must, before the belt does.
    @Test @MainActor
    func zombieRunsStreamTripsTheStallGuard() async throws {
        RunsStubURLProtocol.reset()
        RunsStubURLProtocol.script = Self.script(
            sseBody: Self.runsSSE([
                #"{"event":"message.delta","run_id":"run-r1","timestamp":1.0,"delta":"Zomb"}"#,
            ]),
            statusBodies: [Self.runningStatus],
            hangEventsAfterBody: true
        )
        defer { RunsStubURLProtocol.reset() }

        let client = makeClient(label: "zombie")
        client.streamStallThreshold = .milliseconds(400)
        let updates = await collect(from: client)

        // The delta that landed before the silence is still delivered.
        #expect(labels(updates).first == "textDelta(Zomb)")
        let interruptions = updates.compactMap { update -> (String, String?)? in
            if case let .interrupted(sessionId, runId) = update { return (sessionId, runId) }
            return nil
        }
        #expect(interruptions.count == 1, "the zombie must interrupt, not hang past the belt")
        #expect(interruptions.first?.0 == "sess-r")
        #expect(interruptions.first?.1 == "run-r1")
        #expect(!updates.contains { if case .failed = $0 { return true } else { return false } })
    }

    /// `deliverPolledTerminal`'s `failed` arm: a run the host declares FAILED
    /// is a real failure, not a recovery case — the run is over and no later
    /// reconcile will produce an answer, so `.interrupted` would leave the
    /// turn spinning forever.
    @Test @MainActor
    func failedStatusFromThePollYieldsExactlyOneFailure() async throws {
        RunsStubURLProtocol.reset()
        RunsStubURLProtocol.script = Self.script(
            sseBody: #"{"error":{"message":"Run not found: run-r1","code":"run_not_found"}}"#,
            statusBodies: [#"{"object":"hermes.run","run_id":"run-r1","status":"failed","error":"tool budget exhausted"}"#],
            eventsStatus: 404
        )
        defer { RunsStubURLProtocol.reset() }

        let client = makeClient(label: "failed-status")
        let updates = await collect(from: client)

        let failures = updates.compactMap { update -> String? in
            if case let .failed(text) = update { return text }
            return nil
        }
        #expect(failures.count == 1)
        // The host's OWN reason, never an invented one.
        #expect(failures.first == "tool budget exhausted")
        #expect(!updates.contains { if case .finished = $0 { return true } else { return false } })
        #expect(!updates.contains { if case .interrupted = $0 { return true } else { return false } })
    }

    /// Stale-hop parity with the sessions plane. A hop persisted from a
    /// previous launch whose server session has since expired 404s on the
    /// HISTORY read — the one session-scoped request a runs turn still makes
    /// (N4). Before this, that surfaced as `.failed` where the sessions plane
    /// recovers. It re-hops ONCE and the turn completes, and — the assertion
    /// that matters most — the run is submitted exactly ONCE (#240: a re-sent
    /// accepted turn makes Hermes answer twice).
    @Test @MainActor
    func staleHopOnTheHistoryReadRehopsOnceAndCompletes() async throws {
        RunsStubURLProtocol.reset()
        RunsStubURLProtocol.script = Self.script(
            sseBody: Self.runsSSE([
                #"{"event":"run.completed","run_id":"run-r1","timestamp":1.0,"output":"after re-hop","usage":{"input_tokens":1,"output_tokens":1,"total_tokens":2}}"#,
            ]),
            // First transcript read 404s (the expired session), the next
            // one — on the freshly created hop — succeeds.
            messagesStatuses: [404, 200]
        )
        defer { RunsStubURLProtocol.reset() }

        let client = makeClient(label: "stale-hop", persistedHop: "sess-r")
        let updates = await collect(from: client)

        let finishes = updates.filter { if case .finished = $0 { return true } else { return false } }
        #expect(finishes.count == 1)
        let finished = try #require(finishedPayload(updates))
        #expect(finished.message.content == "after re-hop")
        #expect(!updates.contains { if case .failed = $0 { return true } else { return false } })
        #expect(!updates.contains { if case .interrupted = $0 { return true } else { return false } })

        // Two turn-setup sequences: the persisted hop (which created no
        // session) then the fresh one, each with its own transcript read.
        #expect(RunsStubURLProtocol.count("/api/sessions/sess-r/messages") == 2)
        #expect(RunsStubURLProtocol.count("/api/sessions") == 1)
        // …and exactly ONE submit. The retry re-runs the SETUP, never the run.
        #expect(RunsStubURLProtocol.count("/v1/runs") == 1)
    }

    // MARK: - Task 6: the sync send path

    /// `send(...)` — the non-streaming turn (Ask-Hermes intents, widgets) —
    /// rides the runs plane too when the switch is on: submit, then poll to
    /// terminal. There is no sync runs endpoint, so the poll IS the answer
    /// path; a driver that quietly left `send` on `/chat` would ship a turn on
    /// the plane the A/B is trying to retire.
    @Test @MainActor
    func syncSendRidesRunsWhenSwitchOn() async throws {
        RunsStubURLProtocol.reset()
        RunsStubURLProtocol.script = Self.script(
            sseBody: "",
            statusBodies: [
                Self.runningStatus,
                #"{"object":"hermes.run","run_id":"run-r1","status":"completed","output":"Sync answer","usage":{"input_tokens":5,"output_tokens":2,"total_tokens":7}}"#,
            ]
        )
        defer { RunsStubURLProtocol.reset() }

        let client = makeClient(label: "sync-on")
        let message = await client.send(message: "hi", attachments: [], clientMessageID: UUID())

        #expect(message.sender == .hermes)
        #expect(message.content == "Sync answer")
        #expect(message.status == .delivered)

        let paths = RunsStubURLProtocol.requests().map(\.path)
        #expect(paths.contains { $0 == "/v1/runs" })
        #expect(!paths.contains { $0.hasSuffix("/chat") },
                "the sync sessions endpoint must not be touched while the switch is on")
        // No SSE either: the sync path polls, it does not subscribe.
        #expect(!paths.contains { $0.hasSuffix("/events") })
    }

    /// The sync path is bounded by its OWN budget (`runsSyncBudget`, 20s in
    /// production), not by the streamed path's `runsPollBudget` (120s).
    /// `send(...)` has a user waiting on one answer and no `.interrupted`
    /// machinery to degrade to, so it lives under #145 Part A's non-stream
    /// ceiling — the same 20s the sessions `/chat` turn it replaces already
    /// carried via `requestTimeout(forAccept:)`.
    ///
    /// The two knobs are set FAR apart here on purpose: a sync path that read
    /// the wrong one would poll for 30 seconds, so the elapsed-time bound is
    /// what distinguishes them. A per-request timeout could not have caught
    /// this — each individual GET is correctly stamped; it is the LOOP that
    /// needs the ceiling.
    @Test @MainActor
    func syncSendStopsAtItsOwnBudgetNotTheStreamedPollBudget() async throws {
        RunsStubURLProtocol.reset()
        RunsStubURLProtocol.script = Self.script(
            sseBody: "",
            // The run never finishes — the only thing that can end this call
            // is the budget.
            statusBodies: [Self.runningStatus]
        )
        defer { RunsStubURLProtocol.reset() }

        let client = makeClient(label: "sync-budget")
        client.runsPollBudget = .seconds(30)
        client.runsSyncBudget = .milliseconds(300)

        let started = ContinuousClock.now
        let message = await client.send(message: "hi", attachments: [], clientMessageID: UUID())
        let elapsed = ContinuousClock.now - started

        // Bounded, and bounded by the SYNC knob: reading `runsPollBudget`
        // would have parked this call for 30s.
        #expect(elapsed < .seconds(5), "the sync turn must stop at runsSyncBudget, not runsPollBudget")

        // `SessionsClientError.requestFailed`'s message passes through
        // `errorDescription` verbatim, so this pins BOTH the error case and
        // its user-facing text.
        #expect(message.sender == .system)
        #expect(message.status == .failed)
        #expect(message.content == "The Hermes run did not answer in time. It may still finish on the host — check the conversation shortly.")
        // The run was ACCEPTED, so the honest words matter: giving up watching
        // is not the turn being lost, and the status object stays readable for
        // the TTL (1h).
        #expect(message.content.contains("may still finish"))

        // It really polled — and really stopped. 300ms at a 40ms interval is
        // ~8 reads; an unbounded loop would run to the belt instead.
        let statusReads = RunsStubURLProtocol.count("/v1/runs/run-r1")
        #expect(statusReads >= 2, "a single read would not have exercised the loop at all")
        #expect(statusReads <= 20, "polling must stop at the budget, not run unbounded")
    }

    /// The sync path's failure half: a run the host declares FAILED must
    /// surface as a failed message carrying the host's own reason, never as
    /// an empty successful answer.
    @Test @MainActor
    func syncSendSurfacesAFailedRunAsAFailure() async throws {
        RunsStubURLProtocol.reset()
        RunsStubURLProtocol.script = Self.script(
            sseBody: "",
            statusBodies: [#"{"object":"hermes.run","run_id":"run-r1","status":"failed","error":"model refused"}"#]
        )
        defer { RunsStubURLProtocol.reset() }

        let client = makeClient(label: "sync-failed")
        let message = await client.send(message: "hi", attachments: [], clientMessageID: UUID())

        #expect(message.sender == .system)
        #expect(message.status == .failed)
        #expect(message.content.contains("model refused"))
    }

    // MARK: - Task 7: the real server-side stop (#283 S23)

    /// Before this, "Stop" only stopped the app LISTENING (S24: the host
    /// kept generating unattended). This pins the real interrupt:
    /// `hardStopActiveRun()` — the explicit Stop tap's entry point, split
    /// from the network-free `abandonActiveRun()` walk-away teardown by the
    /// #283 review ruling — must actually POST `/v1/runs/{id}/stop` with the
    /// client's auth, and the self-initiated cancel that follows must
    /// resolve SILENTLY — ChatStore already tore its own UI state down the
    /// moment the user tapped Stop, so a second `.interrupted` would be an
    /// unwanted, redundant teardown.
    ///
    /// The stream is parked (`hangEventsAfterBody`, the same zombie shape
    /// `zombieRunsStreamTripsTheStallGuard` uses) so the run is still
    /// "active" from the client's point of view when `hardStopActiveRun()`
    /// fires. `streamStallThreshold` is shortened so the stall guard trips
    /// promptly afterward, entering the recovery poll — scripted to report
    /// the run `cancelled`, the shape the host takes after honoring a real
    /// `/stop`.
    @Test @MainActor
    func hardStopActiveRunPostsStopWithAuth() async throws {
        RunsStubURLProtocol.reset()
        RunsStubURLProtocol.script = Self.script(
            sseBody: Self.runsSSE([
                #"{"event":"message.delta","run_id":"run-r1","timestamp":1.0,"delta":"Wait"}"#,
            ]),
            statusBodies: [#"{"object":"hermes.run","run_id":"run-r1","status":"cancelled"}"#],
            hangEventsAfterBody: true
        )
        defer { RunsStubURLProtocol.reset() }

        let client = makeClient(label: "abandon")
        client.streamStallThreshold = .milliseconds(300)

        let collector = Task { @MainActor in
            var updates: [StreamingUpdate] = []
            for await update in client.sendStreaming(message: "hi", attachments: [], clientMessageID: UUID()) {
                updates.append(update)
            }
            return updates
        }
        // Same hang belt every test in this suite uses — a safety net, not
        // the thing under test (see the assertions below).
        let belt = Task {
            try? await Task.sleep(for: .seconds(10))
            collector.cancel()
        }

        // Pump until the events subscribe has actually gone out — abandoning
        // before the run is even submitted would find nothing to stop.
        var pumps = 0
        while RunsStubURLProtocol.index("GET", "/v1/runs/run-r1/events") == nil, pumps < 200 {
            pumps += 1
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(
            RunsStubURLProtocol.index("GET", "/v1/runs/run-r1/events") != nil,
            "the events subscribe must land before the turn can be stopped"
        )

        client.hardStopActiveRun()

        let updates = await collector.value
        belt.cancel()

        // Pump for the stop request — it is fire-and-forget, so it may land
        // slightly after `hardStopActiveRun()` returns.
        pumps = 0
        while RunsStubURLProtocol.request("POST", "/v1/runs/run-r1/stop") == nil, pumps < 200 {
            pumps += 1
            try? await Task.sleep(for: .milliseconds(10))
        }
        let stop = try #require(RunsStubURLProtocol.request("POST", "/v1/runs/run-r1/stop"))
        #expect(stop.authorization == "Bearer test-key")

        // Silent teardown: no `.interrupted` for the run WE stopped.
        #expect(!updates.contains { if case .interrupted = $0 { return true } else { return false } })
        // The collector drained the WHOLE stream via `continuation.finish()`
        // — proven by content, not elapsed time: the only thing collected is
        // the delta that arrived before the stop, with nothing appended by a
        // belt-cancellation cutting the loop off early.
        #expect(labels(updates) == ["textDelta(Wait)"])
    }

    /// Review of #279, Task 7 fix: a Stop whose POST never reaches the host
    /// must NOT read as success. Same fixture and shape as
    /// `hardStopActiveRunPostsStopWithAuth` above (parked stream, shortened
    /// stall guard, status poll scripted `cancelled`) but with
    /// `stopTransportFails: true` — the stop request is attempted (recorded
    /// by the stub the instant `startLoading` begins) and then dies at the
    /// transport level, so `hardStopActiveRun()`'s `session.data(for:)` never
    /// returns success. Before the fix, `markSelfStopped` fired BEFORE the
    /// POST outcome was known, so this run would still have ended silently —
    /// a Stop that reads as having worked when the host never heard it. The
    /// fix makes this run surface as ordinary recovery instead: the polled
    /// `cancelled` status still yields `.interrupted`, not silence.
    @Test @MainActor
    func hardStopWhoseStopPostFailsIsNotMarkedSelfStopped() async throws {
        RunsStubURLProtocol.reset()
        RunsStubURLProtocol.script = Self.script(
            sseBody: Self.runsSSE([
                #"{"event":"message.delta","run_id":"run-r1","timestamp":1.0,"delta":"Wait"}"#,
            ]),
            statusBodies: [#"{"object":"hermes.run","run_id":"run-r1","status":"cancelled"}"#],
            hangEventsAfterBody: true,
            stopTransportFails: true
        )
        defer { RunsStubURLProtocol.reset() }

        let client = makeClient(label: "hardstop-transport-fail")
        client.streamStallThreshold = .milliseconds(300)

        let collector = Task { @MainActor in
            var updates: [StreamingUpdate] = []
            for await update in client.sendStreaming(message: "hi", attachments: [], clientMessageID: UUID()) {
                updates.append(update)
            }
            return updates
        }
        let belt = Task {
            try? await Task.sleep(for: .seconds(10))
            collector.cancel()
        }

        var pumps = 0
        while RunsStubURLProtocol.index("GET", "/v1/runs/run-r1/events") == nil, pumps < 200 {
            pumps += 1
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(
            RunsStubURLProtocol.index("GET", "/v1/runs/run-r1/events") != nil,
            "the events subscribe must land before the turn can be stopped"
        )

        client.hardStopActiveRun()

        let updates = await collector.value
        belt.cancel()

        // The attempt landed (the stub records the request BEFORE failing
        // it) even though it never succeeded.
        pumps = 0
        while RunsStubURLProtocol.request("POST", "/v1/runs/run-r1/stop") == nil, pumps < 200 {
            pumps += 1
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(RunsStubURLProtocol.request("POST", "/v1/runs/run-r1/stop") != nil)

        // NOT silenced: a failed stop POST must not read as a self-stop, so
        // the polled `cancelled` status still arms ordinary `.interrupted`
        // recovery — the whole point of this fix.
        #expect(updates.contains { if case .interrupted = $0 { return true } else { return false } })
    }

    /// A Stop tapped with nothing running — the turn already finished, or
    /// this backend never had one (the local brain, reached through the same
    /// protocol default) — must send no request at all.
    @Test @MainActor
    func hardStopWithNoActiveRunIsANoOp() async throws {
        RunsStubURLProtocol.reset()
        RunsStubURLProtocol.script = Self.script(sseBody: Self.runsSSE([]))
        defer { RunsStubURLProtocol.reset() }

        // Fresh client, runs provider on (`makeClient`'s default), no turn
        // ever started — nothing for `activeRunContext` to hold.
        let client = makeClient(label: "hardstop-noop")
        client.hardStopActiveRun()

        // Give an errant fire-and-forget a moment to (not) fire.
        try? await Task.sleep(for: .milliseconds(50))

        #expect(RunsStubURLProtocol.requests().isEmpty, "no active run means no request of any kind, not just no /stop")
    }

    /// #283 review ruling: `abandonActiveRun` — the WALK-AWAY teardown
    /// (`abandonPendingRun`, a thread switch, clearing the conversation, a
    /// continued-send expiring) — must never touch the network, even while a
    /// run is genuinely active. Sessions-plane parity: switching threads or
    /// clearing mid-turn must not throw away an answer the write-half would
    /// otherwise have preserved. This is the inverse of
    /// `hardStopActiveRunPostsStopWithAuth` above — same parked-stream setup,
    /// but `abandonActiveRun()` instead of `hardStopActiveRun()`, and the
    /// run is left un-silenced (still reachable) since nobody told the host
    /// to stop.
    @Test @MainActor
    func walkAwayAbandonNeverTouchesTheNetwork() async throws {
        RunsStubURLProtocol.reset()
        RunsStubURLProtocol.script = Self.script(
            sseBody: Self.runsSSE([
                #"{"event":"message.delta","run_id":"run-r1","timestamp":1.0,"delta":"Wait"}"#,
            ]),
            statusBodies: [Self.runningStatus],
            hangEventsAfterBody: true
        )
        defer { RunsStubURLProtocol.reset() }

        let client = makeClient(label: "walk-away")
        client.streamStallThreshold = .milliseconds(300)

        let collector = Task { @MainActor in
            var updates: [StreamingUpdate] = []
            for await update in client.sendStreaming(message: "hi", attachments: [], clientMessageID: UUID()) {
                updates.append(update)
            }
            return updates
        }
        let belt = Task {
            try? await Task.sleep(for: .seconds(10))
            collector.cancel()
        }

        var pumps = 0
        while RunsStubURLProtocol.index("GET", "/v1/runs/run-r1/events") == nil, pumps < 200 {
            pumps += 1
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(RunsStubURLProtocol.index("GET", "/v1/runs/run-r1/events") != nil)

        // Walk-away, NOT Stop.
        client.abandonActiveRun()

        let updates = await collector.value
        belt.cancel()

        #expect(
            RunsStubURLProtocol.requests().filter { $0.path.hasSuffix("/stop") }.isEmpty,
            "abandonActiveRun (walk-away) must never POST /stop"
        )
        // Not silenced either: the host was never told to stop, so its
        // eventual recovery is the ordinary "still going" shape, not the
        // self-stopped silence `hardStopActiveRun` produces. Proves
        // `abandonActiveRun` leaves `selfStoppedRunIDs` untouched, not just
        // that it skips the network call.
        #expect(updates.contains { if case .interrupted = $0 { return true } else { return false } })
    }

    /// #293(c): `selfStoppedRunIDs`' doc promised a bound that its own code
    /// stopped enforcing when the #279 review fix moved the insert to AFTER
    /// the `/stop` POST returns — an insert landing past the driver's last
    /// drain has nothing left to remove it, and would sit there for the
    /// process's life. The bound is now the code's, not the comment's.
    /// Behaviour that must NOT change: an id still in the list is still
    /// consumed exactly once, and consuming an unknown id is still false.
    @Test @MainActor
    func selfStoppedRunIDsStayBoundedWhenNothingEverDrainsThem() async throws {
        let client = makeClient(label: "self-stopped-bound")

        for index in 0 ..< (SessionsHermesClient.selfStoppedRunIDLimit * 3) {
            client.markSelfStopped(runID: "run-\(index)")
        }
        #expect(
            client.selfStoppedRunIDs.count == SessionsHermesClient.selfStoppedRunIDLimit,
            "an undrained mark must never grow the list past its stated handful"
        )
        #expect(
            client.selfStoppedRunIDs.contains("run-0") == false,
            "eviction is oldest-first — the newest stops are the ones still owed a terminal"
        )

        let newest = "run-\(SessionsHermesClient.selfStoppedRunIDLimit * 3 - 1)"
        #expect(client.consumeSelfStopped(runID: newest), "a live id is still consumed")
        #expect(client.consumeSelfStopped(runID: newest) == false, "and consumed exactly once")
        #expect(client.consumeSelfStopped(runID: "never-stopped") == false)

        // Re-marking the same run must not double-count against the bound.
        client.markSelfStopped(runID: "run-repeat")
        client.markSelfStopped(runID: "run-repeat")
        #expect(client.selfStoppedRunIDs.filter { $0 == "run-repeat" }.count == 1)
    }

    // MARK: - Task 7 residual: ChatStore.cancelStreaming's hardStopHost gate

    /// #283 review re-review — the residual the whole-branch pass caught:
    /// `ChatStore.cancelStreaming()` had exactly ONE caller that is not the
    /// explicit Stop tap — the continued-send expiration handler set up in
    /// `ChatStore.sendMessage(_:attachments:)` (`continuedSend?.onExpiration`),
    /// fired when the SYSTEM revokes a background task's budget with NO user
    /// action. Because `cancelStreaming` unconditionally called
    /// `hardStopActiveRun()`, a lapsed background budget on an attachment
    /// turn silently hard-killed the host run. Fix: `cancelStreaming(hardStopHost:)`,
    /// defaulting to `true` (every explicit-stop caller unchanged), with the
    /// expiration handler alone passing `false`.
    ///
    /// #295 close-out (SHIPPED): the fix above stands, and skipping
    /// `hardStopActiveRun()` now preserves an answer for real — not via
    /// `restartPendingPollingIfNeeded` (that loop only ever re-merges
    /// `hermesClient.loadConversation()`'s CACHED conversation, no network
    /// call), but via the genuine recovery route: `cancelStreaming`
    /// (`hardStopHost: false`) now arms `pendingRun` + `reconcileFromServer()`
    /// on this expiration path too, gated on `currentRunIsServerRecoverable`.
    /// The real `SessionsHermesClient` these two tests wire up always answers
    /// `true` for that gate — but `makeChatStore` constructs its `ChatStore`
    /// with NO `journal:`, a separate `ConversationJournalStore` from the one
    /// `makeClient` gave the `SessionsHermesClient`, so `activeSessionID`
    /// (`journal?.activeHop?.apiSessionId`) and therefore `activeStreamRun`
    /// never resolve on THIS `ChatStore` — the arm's session-id guard fails
    /// regardless of the recoverability flag, and both turns land in the
    /// residual defensive tail (`.delivered`, no `pendingRun`) same as
    /// before. That's why this pair asserts only on the `/stop` POST, not on
    /// `pendingRun`/reconcile state — the arm doesn't fire in this fixture
    /// either way, so it's orthogonal to what's pinned below. See
    /// `ChatStore.cancelStreaming(hardStopHost:)`'s doc for the full account
    /// of the arm itself.
    ///
    /// This pair of tests exercises a REAL `ChatStore` wired to a REAL
    /// `SessionsHermesClient` against this file's HTTP stub — not a
    /// call-counting double — so what's pinned is the actual network
    /// effect (a `/stop` POST landing or not), matching
    /// `walkAwayAbandonNeverTouchesTheNetwork`'s fixture and shape.
    ///
    /// **SCOPE NOTE:** both tests call `cancelStreaming(hardStopHost:)`
    /// directly rather than through the real expiration callback
    /// (`continuedSend?.onExpiration`). `BGContinuedProcessingTask` has no
    /// public initializer (`ContinuedProcessingTests`'s own header comment
    /// states this), so no test can make the system hand a handle a real
    /// task or simulate the system revoking one. What IS pinned here: the
    /// `hardStopHost` parameter's gating logic on `cancelStreaming` itself.
    /// What is NOT pinned: that `ChatStore.sendMessage`'s expiration closure
    /// actually calls `cancelStreaming(hardStopHost: false)` — that one line
    /// is read-verified only, not exercised by a test.
    @Test @MainActor
    func cancelStreamingHardStopHostFalseNeverPostsStop() async throws {
        RunsStubURLProtocol.reset()
        RunsStubURLProtocol.script = Self.script(
            sseBody: Self.runsSSE([
                #"{"event":"message.delta","run_id":"run-r1","timestamp":1.0,"delta":"Wait"}"#,
            ]),
            statusBodies: [Self.runningStatus],
            hangEventsAfterBody: true
        )
        defer { RunsStubURLProtocol.reset() }

        let client = makeClient(label: "chatstore-no-hardstop")
        client.streamStallThreshold = .milliseconds(300)
        let chatStore = makeChatStore(hermesClient: client)

        let sendTask = Task { @MainActor in
            _ = await chatStore.sendMessage("hi")
        }
        let belt = Task {
            try? await Task.sleep(for: .seconds(10))
            sendTask.cancel()
        }

        var pumps = 0
        while RunsStubURLProtocol.index("GET", "/v1/runs/run-r1/events") == nil, pumps < 200 {
            pumps += 1
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(RunsStubURLProtocol.index("GET", "/v1/runs/run-r1/events") != nil)

        // The expiration-handler shape: NOT the explicit Stop tap.
        chatStore.cancelStreaming(hardStopHost: false)

        await sendTask.value
        belt.cancel()

        // Give an errant fire-and-forget a moment to (not) fire.
        try? await Task.sleep(for: .milliseconds(50))
        #expect(
            RunsStubURLProtocol.requests().filter { $0.path.hasSuffix("/stop") }.isEmpty,
            "cancelStreaming(hardStopHost: false) must never POST /stop"
        )
    }

    /// The other half of the pair: the SAME fixture, but the default
    /// `hardStopHost: true` — the explicit-Stop-tap shape — must still POST
    /// `/stop` exactly as `hardStopActiveRunPostsStopWithAuth` already pins
    /// at the client level. Failing this direction would mean the gate got
    /// inverted rather than added.
    @Test @MainActor
    func cancelStreamingDefaultPostsStop() async throws {
        RunsStubURLProtocol.reset()
        RunsStubURLProtocol.script = Self.script(
            sseBody: Self.runsSSE([
                #"{"event":"message.delta","run_id":"run-r1","timestamp":1.0,"delta":"Wait"}"#,
            ]),
            statusBodies: [#"{"object":"hermes.run","run_id":"run-r1","status":"cancelled"}"#],
            hangEventsAfterBody: true
        )
        defer { RunsStubURLProtocol.reset() }

        let client = makeClient(label: "chatstore-hardstop")
        client.streamStallThreshold = .milliseconds(300)
        let chatStore = makeChatStore(hermesClient: client)

        let sendTask = Task { @MainActor in
            _ = await chatStore.sendMessage("hi")
        }
        let belt = Task {
            try? await Task.sleep(for: .seconds(10))
            sendTask.cancel()
        }

        var pumps = 0
        while RunsStubURLProtocol.index("GET", "/v1/runs/run-r1/events") == nil, pumps < 200 {
            pumps += 1
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(RunsStubURLProtocol.index("GET", "/v1/runs/run-r1/events") != nil)

        // The explicit-Stop-tap shape: default `hardStopHost: true`.
        chatStore.cancelStreaming()

        await sendTask.value
        belt.cancel()

        pumps = 0
        while RunsStubURLProtocol.request("POST", "/v1/runs/run-r1/stop") == nil, pumps < 200 {
            pumps += 1
            try? await Task.sleep(for: .milliseconds(10))
        }
        let stop = try #require(RunsStubURLProtocol.request("POST", "/v1/runs/run-r1/stop"))
        #expect(stop.authorization == "Bearer test-key")
    }

    // MARK: - Task 7 review finding 1: the poll's nil-terminal door

    /// Review finding 1: `deliverPolledTerminal`'s terminal-SNAPSHOT arm
    /// silences a self-stopped `cancelled` status, but every caller ALSO
    /// falls back to `.interrupted` when the poll never reaches a terminal
    /// snapshot at all (budget exhausted, `.gone`, or the unreadable-reads
    /// limit) — a real gap: the host can honor `/stop` by closing the SSE
    /// with no `run.cancelled` frame and then reap the run before any poll
    /// catches it `cancelled`, leaving nothing but a `.gone` 404. That must
    /// end silently too. Uses the `.gone` door specifically (`statusCodes:
    /// [404]`) — it is the FASTEST of the three nil-exits (returns on the
    /// very first read, no budget to burn), so this stays quick without
    /// needing to shorten anything beyond what `makeClient` already does.
    @Test @MainActor
    func selfStoppedRunEndsSilentlyWhenTheRecoveryPollNeverResolves() async throws {
        RunsStubURLProtocol.reset()
        RunsStubURLProtocol.script = Self.script(
            sseBody: Self.runsSSE([
                #"{"event":"message.delta","run_id":"run-r1","timestamp":1.0,"delta":"Wait"}"#,
            ]),
            statusBodies: [#"{"error":{"message":"Run not found: run-r1","code":"run_not_found"}}"#],
            statusCodes: [404],
            hangEventsAfterBody: true
        )
        defer { RunsStubURLProtocol.reset() }

        let client = makeClient(label: "self-stop-poll-gone")
        client.streamStallThreshold = .milliseconds(300)

        let collector = Task { @MainActor in
            var updates: [StreamingUpdate] = []
            for await update in client.sendStreaming(message: "hi", attachments: [], clientMessageID: UUID()) {
                updates.append(update)
            }
            return updates
        }
        let belt = Task {
            try? await Task.sleep(for: .seconds(10))
            collector.cancel()
        }

        var pumps = 0
        while RunsStubURLProtocol.index("GET", "/v1/runs/run-r1/events") == nil, pumps < 200 {
            pumps += 1
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(RunsStubURLProtocol.index("GET", "/v1/runs/run-r1/events") != nil)

        client.hardStopActiveRun()

        let updates = await collector.value
        belt.cancel()

        // The `.gone` door, not the `cancelled`-snapshot door the earlier
        // test pins — no `.interrupted` for the run WE stopped either way,
        // and the collector finished on its own (the stall-guard → poll →
        // `.gone` chain), never the 10s belt.
        #expect(!updates.contains { if case .interrupted = $0 { return true } else { return false } })
        #expect(labels(updates) == ["textDelta(Wait)"])
    }

    // MARK: - Task 7 review finding 2: the direct `run.cancelled` frame

    /// Review finding 2a: pins the OTHER silencing branch — a `run.cancelled`
    /// frame arriving directly on the SSE stream (`:461-468`), never
    /// exercised by any prior test. `eventsResponseDelay` holds the events
    /// response back until well after `hardStopActiveRun()` has run:
    /// the request log entry is written the instant the request goes out
    /// (before the delay), so pumping for it and then calling
    /// `hardStopActiveRun()` is guaranteed to land before the frame is even
    /// delivered, let alone processed — no race against however fast the
    /// stub would otherwise answer.
    @Test @MainActor
    func selfStoppedRunReceivingCancelledFrameEndsSilently() async throws {
        RunsStubURLProtocol.reset()
        RunsStubURLProtocol.script = Self.script(
            sseBody: Self.runsSSE([
                #"{"event":"run.cancelled","run_id":"run-r1","timestamp":1.0}"#,
            ]),
            eventsResponseDelay: 0.2
        )
        defer { RunsStubURLProtocol.reset() }

        let client = makeClient(label: "self-stop-frame")

        let collector = Task { @MainActor in
            var updates: [StreamingUpdate] = []
            for await update in client.sendStreaming(message: "hi", attachments: [], clientMessageID: UUID()) {
                updates.append(update)
            }
            return updates
        }
        let belt = Task {
            try? await Task.sleep(for: .seconds(10))
            collector.cancel()
        }

        var pumps = 0
        while RunsStubURLProtocol.index("GET", "/v1/runs/run-r1/events") == nil, pumps < 200 {
            pumps += 1
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(RunsStubURLProtocol.index("GET", "/v1/runs/run-r1/events") != nil)

        client.hardStopActiveRun()

        let updates = await collector.value
        belt.cancel()

        // Silent all the way: no `.interrupted`, no `.failed`, no `.finished`
        // — the frame carried no answer, and the turn ends without
        // announcing anything.
        #expect(updates.isEmpty)
    }

    /// Review finding 2b, the control: a `run.cancelled` frame WITHOUT a
    /// self-stop (a host-side or another-client cancel) must still yield
    /// exactly one `.interrupted` — proving the flag actually discriminates
    /// rather than the branch having quietly gone unconditional.
    @Test @MainActor
    func hostCancelledRunWithoutSelfStopYieldsInterrupted() async throws {
        RunsStubURLProtocol.reset()
        RunsStubURLProtocol.script = Self.script(sseBody: Self.runsSSE([
            #"{"event":"run.cancelled","run_id":"run-r1","timestamp":1.0}"#,
        ]))
        defer { RunsStubURLProtocol.reset() }

        let client = makeClient(label: "host-cancel")
        let updates = await collect(from: client)

        let interruptions = updates.compactMap { update -> (String, String?)? in
            if case let .interrupted(sessionId, runId) = update { return (sessionId, runId) }
            return nil
        }
        #expect(interruptions.count == 1)
        #expect(interruptions.first?.0 == "sess-r")
        #expect(interruptions.first?.1 == "run-r1")
        #expect(!updates.contains { if case .finished = $0 { return true } else { return false } })
        #expect(!updates.contains { if case .failed = $0 { return true } else { return false } })
    }

    // MARK: - Task 5: dual-path dispatch pin (#218 guard)
    //
    // The switch reads ONCE per turn (`sendStreaming`'s `useRunsTransportProvider()`
    // check) and routes the WHOLE turn to one plane or the other — never a mix.
    // These two tests pin both directions of that dispatch so a future edit that
    // blurs the branches (e.g. a stray runs-plane probe firing while OFF, or a
    // sessions-plane fallback firing while ON) fails loudly instead of shipping
    // silently, the #218 shape (an untested branch going stale in production).

    /// The sessions-plane SSE dialect (`event:` + `data:` lines), reusing the
    /// shape `ArtifactStreamingTests.sse(_:)` pins — NOT the runs dialect's
    /// single `data:` JSON envelope this file's other fixtures build.
    private static func sessionsSSE(_ events: [(event: String, data: String)]) -> String {
        let padding = ": " + String(repeating: "-", count: 600) + "\n\n"
        return padding + events.map { "event: \($0.event)\ndata: \($0.data)\n\n" }.joined()
    }

    /// Routes the sessions-plane endpoints a streamed turn touches when the
    /// switch is OFF: session creation, the sessions `chat/stream`, and the
    /// history read `/messages` (served defensively — a fresh journal with no
    /// entries never calls it, but the stub shouldn't 400 if that changes).
    /// Deliberately has NO `/v1/runs` route: if the OFF path ever touched it,
    /// the request would still land in the log (recorded before routing) and
    /// this test's negative assertion would catch it.
    private static func sessionsScript(sseBody: String) -> RunsStubURLProtocol.Script {
        RunsStubURLProtocol.Script(
            response: { request in
                guard let url = request.url else { throw URLError(.badURL) }
                func reply(_ status: Int, _ body: String, contentType: String = "application/json") throws -> (HTTPURLResponse, Data) {
                    guard let response = HTTPURLResponse(
                        url: url,
                        statusCode: status,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": contentType]
                    ) else { throw URLError(.badServerResponse) }
                    return (response, Data(body.utf8))
                }
                switch url.path {
                case "/api/sessions":
                    return try reply(200, #"{"session":{"id":"sess-off"}}"#)
                case "/api/sessions/sess-off/messages":
                    return try reply(200, #"{"session_id":"sess-off","data":[]}"#)
                case "/api/sessions/sess-off/chat/stream":
                    return try reply(200, sseBody, contentType: "text/event-stream")
                default:
                    throw URLError(.badURL)
                }
            },
            failAfterBody: { _ in nil },
            hangAfterBody: { _ in false }
        )
    }

    @Test @MainActor
    func switchOffUsesSessionsPlaneExclusively() async throws {
        RunsStubURLProtocol.reset()
        RunsStubURLProtocol.script = Self.sessionsScript(sseBody: Self.sessionsSSE([
            (event: "run.started", data: #"{"run_id":"run_off1"}"#),
            (event: "assistant.delta", data: #"{"delta":"Hi"}"#),
            (event: "assistant.completed", data: #"{"content":"Hi"}"#),
            (event: "run.completed", data: #"{"usage":{"input_tokens":1,"output_tokens":1,"total_tokens":2}}"#),
            (event: "done", data: #"{}"#),
        ]))
        defer { RunsStubURLProtocol.reset() }

        let client = makeClient(label: "switch-off")
        client.useRunsTransportProvider = { false }
        let updates = await collect(from: client)

        // The fixture must actually drive the sessions parser to a real
        // terminal frame — a pin built on a coincidental early exit (e.g. a
        // 400 that never reached /v1/runs) would prove nothing.
        #expect(updates.contains { if case .finished = $0 { return true } else { return false } })

        let paths = RunsStubURLProtocol.requests().map(\.path)
        #expect(paths.contains { $0.contains("/chat/stream") })
        #expect(!paths.contains { $0.contains("/v1/runs") })
    }

    @Test @MainActor
    func switchOnNeverTouchesChatStream() async throws {
        RunsStubURLProtocol.reset()
        RunsStubURLProtocol.script = Self.script(sseBody: Self.runsSSE([
            #"{"event":"run.completed","run_id":"run-r1","timestamp":1.0,"output":"ok","usage":{"input_tokens":1,"output_tokens":1,"total_tokens":2}}"#,
        ]))
        defer { RunsStubURLProtocol.reset() }

        // makeClient(label:) already arms the runs provider (`{ true }`) —
        // the ON direction is the file's default, per its own comment.
        let client = makeClient(label: "switch-on")
        let updates = await collect(from: client)

        #expect(updates.contains { if case .finished = $0 { return true } else { return false } })

        let paths = RunsStubURLProtocol.requests().map(\.path)
        #expect(paths.contains { $0 == "/v1/runs" })
        #expect(!paths.contains { $0.contains("/chat/stream") })
    }
}

// MARK: - History mapping (the pre-fetch's pure half)

/// Direct unit coverage for the three drop/mapping rules `runsHistory`
/// implements. Pure and `nonisolated` — no network, no client.
struct RunsHistoryMappingTests {

    private func message(_ sender: MessageSender, _ content: String) -> Message {
        Message(sender: sender, content: content, status: .delivered)
    }

    @Test func mapsUserAndHermesRolesAndDropsEveryoneElse() {
        let history = SessionsHermesClient.runsHistory(
            from: [
                message(.user, "ping"),
                message(.hermes, "pong"),
                // System notices are the APP's own text (priming receipts,
                // outage banners) — never part of the thread the agent is
                // being handed.
                message(.system, "Context transplanted."),
            ],
            excludingTrailing: ""
        )
        #expect(history.map(\.role) == ["user", "assistant"])
        #expect(history.map(\.content) == ["ping", "pong"])
    }

    @Test func dropsEmptyAndWhitespaceOnlyRows() {
        let history = SessionsHermesClient.runsHistory(
            from: [
                message(.user, "real"),
                message(.hermes, ""),
                message(.hermes, "   \n\t "),
                message(.hermes, "  also real  "),
            ],
            excludingTrailing: ""
        )
        // Blank rows carry nothing for the agent and cost tokens; survivors
        // are trimmed.
        #expect(history.map(\.content) == ["real", "also real"])
    }

    @Test func dropsATrailingRowEqualToTheOutgoingTurn() {
        let history = SessionsHermesClient.runsHistory(
            from: [
                message(.user, "what is the weather"),
                message(.hermes, "sunny"),
                message(.user, "what is the weather"),
            ],
            excludingTrailing: "what is the weather"
        )
        // Only the TRAILING duplicate goes: it is the turn about to be sent,
        // which the body already carries as `input`. The identical EARLIER
        // row is a genuine thing the user said before and must survive — a
        // blanket de-dupe would silently rewrite the conversation.
        #expect(history.map(\.content) == ["what is the weather", "sunny"])
        #expect(history.map(\.role) == ["user", "assistant"])
    }

    @Test func keepsATrailingRowThatIsNotTheOutgoingTurn() {
        let assistantTail = SessionsHermesClient.runsHistory(
            from: [message(.user, "hi"), message(.hermes, "hello")],
            excludingTrailing: "hello"
        )
        // Same text, but it is the ASSISTANT's — never the outgoing turn.
        #expect(assistantTail.map(\.content) == ["hi", "hello"])

        let differentTail = SessionsHermesClient.runsHistory(
            from: [message(.user, "hi"), message(.hermes, "hello")],
            excludingTrailing: "something else"
        )
        #expect(differentTail.count == 2)

        // Whitespace-only outgoing text never drops anything.
        let blankOutgoing = SessionsHermesClient.runsHistory(
            from: [message(.user, "hi")],
            excludingTrailing: "   "
        )
        #expect(blankOutgoing.count == 1)
    }
}
