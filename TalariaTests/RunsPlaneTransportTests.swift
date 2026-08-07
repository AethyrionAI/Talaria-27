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
        let body: String
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
        }
        nonisolated(unsafe) static var script: Script?
        /// Ordered request log — the GET-before-POST ordering assertion and
        /// the submit-body assertions both read it. Locked: URLProtocol
        /// callbacks arrive on the loader's queues, not the test's.
        static let recorded = OSAllocatedUnfairLock<[RecordedRequest]>(initialState: [])

        static func reset() {
            script = nil
            recorded.withLock { $0 = [] }
        }

        static func requests() -> [RecordedRequest] {
            recorded.withLock { $0 }
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
                body: Self.bodyString(request)
            )
            Self.recorded.withLock { $0.append(recordedRequest) }

            guard let script = Self.script else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            do {
                let (response, data) = try script.response(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                if let error = script.failAfterBody(request) {
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { [weak self] in
                        guard let self else { return }
                        self.client?.urlProtocol(self, didFailWithError: error)
                    }
                } else {
                    client?.urlProtocolDidFinishLoading(self)
                }
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
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

    /// Routes the four endpoints one runs turn touches. Suffix/exact path
    /// match, mirroring the sessions-plane stubs.
    private static func script(
        sseBody: String,
        messagesBody: String = RunsPlaneTransportTests.messagesFixture
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
                    return try reply(200, messagesBody)
                case "/v1/runs":
                    return try reply(202, #"{"run_id":"run-r1","status":"started"}"#)
                case "/v1/runs/run-r1/events":
                    return try reply(200, sseBody, contentType: "text/event-stream")
                case "/v1/runs/run-r1":
                    // Task 6's business; a live run here means the poll seam
                    // is exercised only as "not terminal yet".
                    return try reply(200, #"{"object":"hermes.run","run_id":"run-r1","status":"running"}"#)
                default:
                    throw URLError(.badURL)
                }
            },
            failAfterBody: { _ in nil }
        )
    }

    @MainActor
    private func makeClient(label: String) -> SessionsHermesClient {
        let suiteName = "runs-plane-\(label)-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RunsStubURLProtocol.self]

        let client = SessionsHermesClient(
            baseURLProvider: { "http://hermes.test" },
            apiKeyProvider: { "test-key" },
            journal: ConversationJournalStore(persistence: persistence),
            transplanter: ContextTransplanter(intelligence: LocalIntelligenceService()),
            session: URLSession(configuration: configuration)
        )
        // Task 5 pins both directions of the dispatch; here it just arms the
        // runs path so the driver is what runs.
        client.useRunsTransportProvider = { true }
        return client
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
}
