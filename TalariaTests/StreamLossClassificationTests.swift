import Foundation
import Testing
@testable import Talaria

/// #240: classification of a stream that dies in the accepted-but-pre-
/// `run.started` window. A 2xx on the chat/stream POST proves the turn
/// reached the API; the teardown error that follows (fast backgrounding
/// kills the SSE with an unreachable-family URLError) must arm RECOVERY
/// (`.interrupted`), never the offline compose outbox (`.unreachable`) —
/// parking a delivered turn is a visible dupe plus an armed auto-resend.
@Suite(.serialized)
struct StreamLossClassificationTests {

    /// SSE stub that can fail BEFORE the response (`response` throws) or
    /// AFTER delivering the response + a partial body (`failAfterBody`
    /// returns an error for the request).
    private final class DroppingSSEProtocol: URLProtocol, @unchecked Sendable {
        struct Script {
            let response: @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
            let failAfterBody: @Sendable (URLRequest) -> Error?
        }
        nonisolated(unsafe) static var script: Script?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let script = Self.script else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            do {
                let (response, data) = try script.response(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                if let error = script.failAfterBody(request) {
                    // Delayed so the response continuation resumes (and the
                    // partial body is consumable) BEFORE the teardown lands —
                    // a synchronous fail can reach the task first, which is
                    // the pre-response shape, not the mid-stream one.
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
    }

    /// Runs one streamed turn against the scripted transport and returns the
    /// classification-relevant updates.
    @MainActor
    private func collectUpdates() async -> (
        interrupted: [(sessionId: String, runId: String?)],
        sawUnreachable: Bool,
        sawFailed: Bool
    ) {
        let suiteName = "stream-loss-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DroppingSSEProtocol.self]
        let session = URLSession(configuration: configuration)

        let client = SessionsHermesClient(
            baseURLProvider: { "http://hermes.test" },
            apiKeyProvider: { "test-key" },
            journal: ConversationJournalStore(persistence: persistence),
            transplanter: ContextTransplanter(intelligence: LocalIntelligenceService()),
            session: session
        )

        var interrupted: [(sessionId: String, runId: String?)] = []
        var sawUnreachable = false
        var sawFailed = false
        for await update in client.sendStreaming(message: "Q", attachments: [], clientMessageID: UUID()) {
            switch update {
            case let .interrupted(sessionId, runId):
                interrupted.append((sessionId: sessionId, runId: runId))
            case .unreachable:
                sawUnreachable = true
            case .failed:
                sawFailed = true
            default:
                break
            }
        }
        return (interrupted, sawUnreachable, sawFailed)
    }

    /// 240-A, the hole: 2xx received, stream dies before `run.started` with
    /// an unreachable-family teardown error. Must arm recovery, not park.
    @Test @MainActor
    func acceptedButPreRunStartedDropArmsRecoveryNotParking() async {
        DroppingSSEProtocol.script = .init(
            response: { request in
                guard let url = request.url else { throw URLError(.badURL) }
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                switch url.path {
                case "/api/sessions":
                    return (response, Data(#"{"session":{"id":"sess-1"}}"#.utf8))
                case "/api/sessions/sess-1/chat/stream":
                    // Partial body: the server spoke, but run.started never
                    // arrived. The SSE comment padding (ignored by the parse
                    // loop) pushes past URLSession's custom-protocol buffer
                    // threshold (~512B) — below it, the response + body sit
                    // unflushed and the delayed error supersedes them, which
                    // reads as the PRE-response shape instead (probed
                    // 2026-08-03, scratchpad bytes-probe series).
                    let padding = ": " + String(repeating: "x", count: 700) + "\n"
                    return (response, Data((padding + "event: message.started\ndata: {}\n\n").utf8))
                default:
                    throw URLError(.badURL)
                }
            },
            failAfterBody: { request in
                request.url?.path == "/api/sessions/sess-1/chat/stream"
                    ? URLError(.notConnectedToInternet) : nil
            }
        )
        defer { DroppingSSEProtocol.script = nil }

        let outcome = await collectUpdates()

        #expect(outcome.interrupted.count == 1)
        #expect(outcome.interrupted.first?.sessionId == "sess-1")
        #expect(outcome.interrupted.first?.runId == nil)
        #expect(!outcome.sawUnreachable)
    }

    /// The honest case keeps working: the SAME error before any response on
    /// the chat request means the turn never reached the API — still parks.
    @Test @MainActor
    func preResponseDropStillParksAsUnreachable() async {
        DroppingSSEProtocol.script = .init(
            response: { request in
                guard let url = request.url else { throw URLError(.badURL) }
                if url.path == "/api/sessions" {
                    let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    return (response, Data(#"{"session":{"id":"sess-1"}}"#.utf8))
                }
                throw URLError(.notConnectedToInternet)
            },
            failAfterBody: { _ in nil }
        )
        defer { DroppingSSEProtocol.script = nil }

        let outcome = await collectUpdates()

        #expect(outcome.interrupted.isEmpty)
        #expect(outcome.sawUnreachable)
        #expect(!outcome.sawFailed)
    }
}

// MARK: - #246: the zombie stream — silence past the stall threshold

/// Filed from Owen's build-1978 backgrounding test (the first 235-E run):
/// a stream that goes zombie — socket open, bytes never coming, no terminal
/// event — never ended, so recovery never armed and the spinner sat until a
/// manual leave/re-enter. The guard makes prolonged silence THROW, and the
/// existing post-2xx catch converts the throw into `.interrupted` with all
/// of #235/#237's machinery downstream.
@Suite(.serialized)
struct StreamStallGuardTests {

    /// A scriptable line source: yields the given lines, then either goes
    /// silent forever (`thenSilent`) or completes.
    private struct ScriptedLines: AsyncSequence, Sendable {
        let lines: [String]
        let thenSilent: Bool

        struct AsyncIterator: AsyncIteratorProtocol {
            var remaining: [String]
            let thenSilent: Bool
            mutating func next() async throws -> String? {
                if remaining.isEmpty {
                    if thenSilent {
                        // Silence, not termination: park until cancelled.
                        while !Task.isCancelled {
                            try await Task.sleep(for: .milliseconds(20))
                        }
                        return nil
                    }
                    return nil
                }
                return remaining.removeFirst()
            }
        }

        func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(remaining: lines, thenSilent: thenSilent)
        }
    }

    /// 246-A: one line, then silence past the threshold — the line is
    /// delivered, then the guard THROWS `StreamStallError` instead of
    /// blocking forever.
    @Test
    func silencePastTheThresholdThrowsAfterDeliveringWhatArrived() async {
        let guarded = SessionsHermesClient.stallGuardedLines(
            ScriptedLines(lines: ["data: hello"], thenSilent: true),
            threshold: .milliseconds(200)
        )
        var received: [String] = []
        do {
            for try await line in guarded { received.append(line) }
            Issue.record("a silent stream must throw, not finish cleanly")
        } catch {
            #expect(error is SessionsHermesClient.StreamStallError)
        }
        #expect(received == ["data: hello"])
    }

    /// 246-B: lines flowing within the threshold pass through untouched and
    /// the sequence completes normally — a healthy stream never trips it.
    @Test
    func flowingLinesPassThroughAndCompleteWithoutTripping() async throws {
        let lines = (0 ..< 20).map { "data: line-\($0)" }
        let guarded = SessionsHermesClient.stallGuardedLines(
            ScriptedLines(lines: lines, thenSilent: false),
            threshold: .milliseconds(500)
        )
        var received: [String] = []
        for try await line in guarded { received.append(line) }
        #expect(received == lines)
    }

    /// SSE stub that delivers a response + body and then HOLDS THE
    /// CONNECTION OPEN — no finish, no error. The zombie, scripted.
    private final class ZombieSSEProtocol: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var streamBody: Data?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let url = request.url else { return }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if url.path == "/api/sessions" {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data(#"{"session":{"id":"sess-z"}}"#.utf8))
                client?.urlProtocolDidFinishLoading(self)
                return
            }
            if url.path == "/api/model/options" {
                // #241: the create path probes the catalog before POSTing the
                // session. This fixture is about stream loss, not model
                // resolution — 404 it and FINISH, so the client takes its
                // designed degrade-to-bare path instead of inheriting the
                // zombie stream's never-closing socket (which stalls the
                // create and cancels the turn before the zombie is ever met).
                let notFound = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
                client?.urlProtocol(self, didReceive: notFound, cacheStoragePolicy: .notAllowed)
                client?.urlProtocolDidFinishLoading(self)
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.streamBody ?? Data())
            // Deliberately NOTHING else: the connection stays open forever.
        }

        override func stopLoading() {}
    }

    /// 246-C: end to end — `run.started` arrives, then silence. The client
    /// yields `.interrupted` with the runId (recovery arms), never `.failed`
    /// and never a hang.
    @Test @MainActor
    func zombieStreamAfterRunStartedYieldsInterrupted() async {
        // The same sub-512B buffering trap as #240's fixture: pad past the
        // custom-protocol flush threshold or the body never reaches the task.
        // The trailing message.started matters: `bytes.lines` swallows blank
        // lines, so an event only dispatches when the NEXT `event:` line
        // arrives — a lone run.started with nothing after it parks
        // undispatched (runId nil, reconcile resolves positionally). Real
        // zombies stream events before going quiet, so the fixture does too.
        let padding = ": " + String(repeating: "x", count: 700) + "\n"
        ZombieSSEProtocol.streamBody = Data(
            (padding + "event: run.started\ndata: {\"run_id\":\"run-z1\"}\n\nevent: message.started\ndata: {}\n\n").utf8
        )
        defer { ZombieSSEProtocol.streamBody = nil }

        let suiteName = "stall-guard-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ZombieSSEProtocol.self]
        let client = SessionsHermesClient(
            baseURLProvider: { "http://hermes.test" },
            apiKeyProvider: { "test-key" },
            journal: ConversationJournalStore(persistence: persistence),
            transplanter: ContextTransplanter(intelligence: LocalIntelligenceService()),
            session: URLSession(configuration: configuration)
        )
        client.streamStallThreshold = .milliseconds(400)

        // Belt against a hang if the guard ever regresses: a deadline task
        // CANCELS the collector, and cancellation genuinely ends AsyncStream
        // iteration — the loop exits with a partial outcome, so awaiting
        // `.value` cannot strand (the Task.value trap needs an operation
        // that ignores cancellation; this one doesn't).
        let collector = Task { @MainActor in
            var interrupted: [(String, String?)] = []
            var sawFailed = false
            for await update in client.sendStreaming(message: "Q", attachments: [], clientMessageID: UUID()) {
                switch update {
                case let .interrupted(sessionId, runId): interrupted.append((sessionId, runId))
                case .failed: sawFailed = true
                default: break
                }
            }
            return (interrupted: interrupted, sawFailed: sawFailed)
        }
        let belt = Task {
            try? await Task.sleep(for: .seconds(10))
            collector.cancel()
        }
        let outcome = await collector.value
        belt.cancel()

        #expect(outcome.interrupted.count == 1, "the zombie stream must interrupt, not hang past the belt")
        #expect(outcome.interrupted.first?.0 == "sess-z")
        #expect(outcome.interrupted.first?.1 == "run-z1")
        #expect(!outcome.sawFailed)
    }
}
