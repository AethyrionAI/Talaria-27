import Foundation
import Network
import Testing
@testable import Talaria

// MARK: - A loopback HTTP server whose live connections can be poisoned

/// One-shot latch for a continuation resumed from a callback that can fire
/// more than once — `NWListener`'s state handler reports `.ready` and can then
/// report `.failed`, and resuming a continuation twice is a crash.
private final class ResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false
    func claim() -> Bool {
        lock.withLock {
            guard !claimed else { return false }
            claimed = true
            return true
        }
    }
}

/// A real HTTP/1.1 server on `127.0.0.1`, used to reproduce #394 against an
/// actual socket and an actual `URLSession` connection pool.
///
/// **Why not a `URLProtocol` stub, which this target has a dozen of.**
/// `URLProtocol` intercepts *above* the connection pool: a stub can fake the
/// failure's SHAPE but can never exercise the mechanism #394 alleges, because
/// no socket is ever opened and no connection is ever reused. A fixture that
/// cannot execute the code path under test is the trap this project already
/// paid for once (the SSE stub whose sub-512B body never flushed, so the
/// fixture silently tested a different path). For a pooled-connection bug the
/// pool has to be real.
///
/// **What "poisoned" means, and why it models airplane mode.** When an
/// interface disappears, the peer never sends FIN or RST — the socket simply
/// stops carrying anything. The client's kernel still holds a connection it
/// believes is fine, writes into it succeed locally, and no answer ever comes
/// back. Cancelling a connection server-side would send RST, which
/// `URLSession` handles correctly by evicting and retrying, so cancelling
/// would model the wrong outage. A poisoned connection here therefore
/// **accepts bytes, never answers, and is never closed** — while brand-new
/// connections to the same listener are served normally.
final class PoisonableLoopbackServer: @unchecked Sendable {

    private let listener: NWListener
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var openConnections: [ObjectIdentifier: NWConnection] = [:]
    private var poisonedConnections: Set<ObjectIdentifier> = []
    private var accepted = 0
    private var served = 0

    /// The port the listener actually bound. Ephemeral, so parallel tests
    /// cannot collide on it. Assigned by `start()`.
    private(set) var port: UInt16 = 0

    /// How many distinct TCP connections the listener has accepted. **This is
    /// the load-bearing measurement**: it is what separates "the request
    /// failed" from "the request failed *because the pooled connection was
    /// reused*".
    var acceptedConnectionCount: Int { lock.withLock { accepted } }

    /// How many HTTP responses were actually written.
    var servedRequestCount: Int { lock.withLock { served } }

    /// Two-phase on purpose: `NWListener` must have its connection handler
    /// installed **before** `start()`, and a handler that captures `self`
    /// cannot be installed from inside an `async` init (the continuation would
    /// capture `self` before all members were initialised). Splitting the
    /// construction from the start is what lets both rules hold at once —
    /// starting without a handler is what the runtime rejects with EINVAL.
    static func started() async throws -> PoisonableLoopbackServer {
        let server = try PoisonableLoopbackServer()
        try await server.start()
        return server
    }

    private init() throws {
        let queue = DispatchQueue(label: "org.aethyrion.talaria.poisonable-loopback")
        self.queue = queue
        self.listener = try NWListener(using: .tcp, on: .any)
        // Installed here, before start(). Every stored property is initialised
        // at this point, so capturing self is legal.
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
    }

    private func start() async throws {
        let listener = self.listener
        let queue = self.queue
        port = try await withCheckedThrowingContinuation { continuation in
            let resumed = ResumeGuard()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard let bound = listener.port?.rawValue, resumed.claim() else { return }
                    continuation.resume(returning: bound)
                case let .failed(error):
                    guard resumed.claim() else { return }
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
        lock.withLock {
            for connection in openConnections.values { connection.cancel() }
            openConnections.removeAll()
        }
    }

    /// Poison every connection currently open — the transition. Connections
    /// opened *after* this call are served normally, which is exactly the
    /// asymmetry #394 describes: the host is fine, one particular socket is
    /// not.
    func poisonOpenConnections() {
        lock.withLock {
            for id in openConnections.keys { poisonedConnections.insert(id) }
        }
    }

    func url(path: String) -> URL {
        URL(string: "http://127.0.0.1:\(port)\(path)")!
    }

    // MARK: Connection handling

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        lock.withLock {
            openConnections[id] = connection
            accepted += 1
        }
        connection.start(queue: queue)
        receive(on: connection, id: id)
    }

    private func receive(on connection: NWConnection, id: ObjectIdentifier) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if error != nil || isComplete {
                self.lock.withLock { self.openConnections[id] = nil }
                return
            }
            guard let data, !data.isEmpty else {
                self.receive(on: connection, id: id)
                return
            }

            let isPoisoned = self.lock.withLock { self.poisonedConnections.contains(id) }
            if isPoisoned {
                // The whole point: swallow the bytes, answer nothing, close
                // nothing. The client's request rides this socket into its
                // timeout.
                self.receive(on: connection, id: id)
                return
            }

            // Only answer once a full request head has arrived.
            guard String(decoding: data, as: UTF8.self).contains("\r\n\r\n") else {
                self.receive(on: connection, id: id)
                return
            }
            self.respond(on: connection, id: id)
        }
    }

    private func respond(on connection: NWConnection, id: ObjectIdentifier) {
        let body = #"{"data":[{"id":"hermes-agent","object":"model"}],"object":"list"}"#
        let head = [
            "HTTP/1.1 200 OK",
            "Content-Type: application/json",
            "Content-Length: \(body.utf8.count)",
            "Connection: keep-alive",
            "", "",
        ].joined(separator: "\r\n")
        let payload = Data((head + body).utf8)
        lock.withLock { served += 1 }
        connection.send(content: payload, completion: .contentProcessed { [weak self] _ in
            // Keep-alive: stay open for the next request on this connection,
            // which is what makes the pool reuse it.
            self?.receive(on: connection, id: id)
        })
    }

}

// MARK: - #394 bar 394-A

/// **#394 bar 394-A — reproduce the wedge deterministically, before any fix.**
///
/// Owen's device observation: back from airplane mode, the chat stayed OFFLINE
/// against a host that was up, while Settings → Uplink → **Test Connection on
/// that same host PASSED**. Two `URLSession`s disagreeing about one host.
///
/// **This bar exists because the first hypothesis was wrong.** An ATS/MagicDNS
/// story was built and discarded — it rested on misreading which host an IP
/// belonged to. A transport bug fixed without a reproduction is a guess, so
/// the reproduction comes first and it has to fail for the alleged reason
/// rather than merely fail.
///
/// **The assertion that makes this a mechanism test rather than a symptom
/// test** is `acceptedConnectionCount`. Any wedged request can be made to
/// fail; what #394 claims is specifically that the failing request **reused a
/// pooled connection** instead of opening a fresh one. If the session opened a
/// second connection and still failed, the filed mechanism would be wrong —
/// so the connection count is checked, not just the error.
@Suite(.serialized)
struct PooledConnectionWedgeTests {

    /// The shipping chat-plane session's shape, with the request timeout cut
    /// from 20s to 3s so the wedge resolves inside a test run.
    ///
    /// **The timeout is the ONLY difference, and it is stated rather than
    /// hidden**: keep-alive, connection reuse and the resource ceiling are the
    /// production values, because those are the properties under test. A
    /// harness that quietly changed the pooling behaviour would be measuring a
    /// configuration the app never enters (#215's rule, one layer down).
    private static func wedgeableChatPlaneSession(timeout: TimeInterval = 3) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = 3600
        return URLSession(configuration: configuration)
    }

    private static func get(_ url: URL, on session: URLSession) async -> Result<Int, Error> {
        do {
            let (_, response) = try await session.data(from: url)
            return .success((response as? HTTPURLResponse)?.statusCode ?? -1)
        } catch {
            return .failure(error)
        }
    }

    /// **394-A.** One host, one transition, two sessions — and they disagree.
    @Test func aPoisonedPooledConnectionWedgesItsOwnSessionWhileTheHostStaysReachable() async throws {
        let server: PoisonableLoopbackServer
        do {
            server = try await PoisonableLoopbackServer.started()
        } catch {
            Issue.record("HARNESS could not start the loopback listener (\(error)) — not a #394 result either way.")
            return
        }
        defer { server.stop() }
        let url = server.url(path: "/v1/models")

        let chatSession = Self.wedgeableChatPlaneSession()
        defer { chatSession.invalidateAndCancel() }

        // 1 — healthy. This is what establishes the pooled connection.
        let first = await Self.get(url, on: chatSession)
        #expect(first.statusCode == 200, "baseline request should succeed: \(first)")
        #expect(server.acceptedConnectionCount == 1,
                "expected exactly one TCP connection so far, saw \(server.acceptedConnectionCount)")

        // 2 — the transition. The host stays up; the established socket dies.
        server.poisonOpenConnections()

        // 3 — the same session probes the same host again. #394 says this
        //     wedges, and says WHY: the pool hands back the dead socket.
        let second = await Self.get(url, on: chatSession)
        #expect(second.isFailure, """
            the wedge did not reproduce — the poisoned pooled connection answered \
            with \(second). If this passes, #394's filed mechanism is wrong and the \
            entry must be corrected before any fix.
            """)
        #expect(server.acceptedConnectionCount == 1, """
            #394's mechanism requires the failing request to have REUSED the pooled \
            connection. The listener accepted \(server.acceptedConnectionCount) \
            connection(s), so the request opened a fresh one and failed for some other \
            reason — the filed mechanism would then be wrong.
            """)

        // 4 — a fresh session reaches the identical host. This is Owen's
        //     Test Connection passing while the chat stayed offline.
        let probeSession = Self.wedgeableChatPlaneSession()
        defer { probeSession.invalidateAndCancel() }
        let third = await Self.get(url, on: probeSession)
        #expect(third.statusCode == 200, """
            the control failed: a FRESH session could not reach the host either \
            (\(third)), so the server — not the pool — is what broke. The \
            disagreement between two sessions IS #394; without this leg the test \
            proves only that a poisoned socket times out.
            """)
        #expect(server.acceptedConnectionCount == 2,
                "the fresh session should have opened a second connection, saw \(server.acceptedConnectionCount)")
    }

    /// **394-A, second half: is the wedge DURABLE?** This is the leg that
    /// decides whether the filed mechanism explains what Owen actually saw.
    ///
    /// The four-leg test above proves ONE request fails on a reused dead
    /// socket. Owen's device stayed OFFLINE across repeated probes — the chat
    /// re-probes on appear and every ~10s — so if `URLSession` evicts the dead
    /// connection after its first timeout, the very next probe would open a
    /// fresh connection and recover, and **the pooled-socket story would not
    /// explain the durability**.
    ///
    /// This test asserts nothing about which way it goes. It MEASURES, and
    /// prints the answer, because that answer decides the shape of the fix:
    /// self-healing-after-one-failure needs no invalidation at all, while a
    /// durable wedge does.
    @Test func measureWhetherTheWedgeSurvivesASecondProbeOnTheSameSession() async throws {
        let server: PoisonableLoopbackServer
        do {
            server = try await PoisonableLoopbackServer.started()
        } catch {
            Issue.record("HARNESS could not start the loopback listener (\(error)) — not a #394 result either way.")
            return
        }
        defer { server.stop() }
        let url = server.url(path: "/v1/models")

        let chatSession = Self.wedgeableChatPlaneSession()
        defer { chatSession.invalidateAndCancel() }

        _ = await Self.get(url, on: chatSession)
        server.poisonOpenConnections()

        var outcomes: [String] = []
        for probe in 1...3 {
            let result = await Self.get(url, on: chatSession)
            let connections = server.acceptedConnectionCount
            switch result {
            case let .success(code):
                outcomes.append("probe \(probe): RECOVERED (HTTP \(code)), connections=\(connections)")
            case let .failure(error):
                let code = (error as? URLError)?.code
                let described = code.map { String(describing: $0) } ?? "?"
                outcomes.append("probe \(probe): still wedged (\(described)), connections=\(connections)")
            }
        }
        print("=== #394 durability measurement — does the wedge survive repeated probes? ===")
        for line in outcomes { print(line) }
        print("(connections=1 means the pool kept handing back the dead socket; a rise means URLSession evicted it and opened a fresh one.)")
        #expect(!outcomes.isEmpty)
    }

    /// The shipping constant this harness deliberately overrides, pinned so
    /// the 3s used above cannot quietly drift away from what ships.
    @Test func theShippingChatPlaneRequestTimeoutIsUnchanged() {
        #expect(SessionsHermesClient.interactiveRequestTimeout == 20)
        #expect(SessionsHermesClient.streamingRequestTimeout == 300)
    }

    /// **The pin #394's fix never had, added by the 2026-08-23 Opus-week
    /// audit.** The fix is a view modifier (`.task(id: scenePhase)`) plus a
    /// guard-at-top — SwiftUI bodies are unreachable from a unit test, and
    /// reverting either line passed the whole suite. Entry #394 retired its
    /// automated bar with reasoning and closed on device evidence; this
    /// structural pin (the #399 pattern) is the cheap floor under that
    /// decision: the two load-bearing lines must exist in the source.
    @Test func theScenePhaseRestartWiringIsStillSpelled() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TalariaTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Talaria/Features/Chat/ChatScreen.swift")
        let source = try #require(
            try? String(contentsOf: url, encoding: .utf8),
            "cannot read ChatScreen.swift — this check did not run"
        )
        #expect(source.contains(".task(id: scenePhase) { await monitorConnectionStatus() }"),
                "the health-poll task is no longer scenePhase-keyed — #394's frozen-phase bug can return")
        #expect(source.contains("ChatHealthPollPolicy.shouldProbe(scenePhase: pollScenePhase)"),
                "the per-tick live-phase guard is gone from the poll loop (#394)")
    }
}

private extension Result where Success == Int, Failure == Error {
    var statusCode: Int? { try? get() }
    var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }
}
