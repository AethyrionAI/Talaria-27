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
