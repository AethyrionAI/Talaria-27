import Foundation
import Testing
@testable import Talaria

/// OPEN_ITEMS #241 — client-side immunity: no Talaria-created session stores
/// the gateway's own advertised alias as its model.
///
/// Upstream persists `model = body.get("model") or self._model_name`
/// (`api_server.py:3397`), so a bare `POST /api/sessions` makes every session
/// we create store the literal `"hermes-agent"` — a routing sentinel, not a
/// real model id. When the sentinel and the stored value diverge (profile
/// rename, the "API server model name" field, a different host) the stored
/// alias becomes a request for a model no provider has: a non-retryable 404
/// delivered to the client as HTTP 200.
///
/// Bars 241-A..D. 241-E (live, on OJAMD) rides the queued device sitting and
/// is NOT claimed here.
@Suite(.serialized)
struct SessionModelImmunityTests {

    // MARK: - Fixtures

    private final class ImmunityStubURLProtocol: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let handler = Self.requestHandler else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            do {
                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
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

    private struct Captured: Sendable {
        let method: String
        let path: String
        let body: String
    }

    private final class RequestLog: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [Captured] = []

        func record(_ request: URLRequest) {
            lock.lock()
            defer { lock.unlock() }
            entries.append(Captured(
                method: request.httpMethod ?? "",
                path: request.url?.path ?? "",
                body: ImmunityStubURLProtocol.bodyString(request)
            ))
        }

        var all: [Captured] {
            lock.lock()
            defer { lock.unlock() }
            return entries
        }

        /// The `POST /api/sessions` create body, decoded.
        var createBody: [String: Any]? {
            guard let raw = all.first(where: { $0.method == "POST" && $0.path == "/api/sessions" })?.body,
                  let data = raw.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            return object
        }
    }

    private static func stubbedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImmunityStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func response(_ request: URLRequest, _ status: Int, _ body: String) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(body.utf8))
    }

    @MainActor
    private func makeClient(_ label: String) -> SessionsHermesClient {
        let suiteName = "session-model-immunity-\(label)-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        return SessionsHermesClient(
            baseURLProvider: { "http://gateway:8642" },
            apiKeyProvider: { "key-test" },
            journal: ConversationJournalStore(persistence: persistence),
            transplanter: ContextTransplanter(intelligence: LocalIntelligenceService()),
            session: Self.stubbedSession()
        )
    }

    /// Serves the create + chat pair; `/api/model/options` is delegated so
    /// each arm can decide whether the catalog resolves, fails, or is poisoned.
    @MainActor
    private func runOneTurn(
        client: SessionsHermesClient,
        log: RequestLog,
        modelOptions: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) async -> Message {
        ImmunityStubURLProtocol.requestHandler = { request in
            log.record(request)
            let path = request.url?.path ?? ""
            if path == "/api/model/options" {
                return try modelOptions(request)
            }
            if path == "/api/sessions" {
                return Self.response(request, 200, #"{"session": {"id": "api_immunity_1"}}"#)
            }
            return Self.response(request, 200, #"{"message": {"content": "ok"}}"#)
        }
        defer { ImmunityStubURLProtocol.requestHandler = nil }
        return await client.send(message: "hello", attachments: [], clientMessageID: UUID())
    }

    // MARK: - 241-A — an explicit pick rides the create body

    @Test @MainActor
    func createBodyCarriesTheProfilesModelSelection() async throws {
        let client = makeClient("selection")
        client.modelSelection = ModelSelection(provider: "nous", modelID: "anthropic/claude-fable-5")
        let log = RequestLog()

        let reply = await runOneTurn(client: client, log: log) { request in
            Self.response(request, 200, ModelOptionsFixture.json)
        }

        #expect(reply.status == .delivered)
        let body = try #require(log.createBody, "POST /api/sessions must be observed")
        #expect(body["model"] as? String == "anthropic/claude-fable-5")
        // The user's own pick wins outright — the catalog default never applies.
        #expect(body["model"] as? String != "kimi-k3")
        // The lock trio is the PER-TURN contract; create takes a bare model.
        #expect(body["require_model_lock"] == nil)
    }

    // MARK: - 241-B — no pick: the host's real catalog default

    @Test @MainActor
    func createBodyCarriesTheCatalogDefaultWhenNoSelectionIsSet() async throws {
        let client = makeClient("catalog-default")
        client.modelSelection = nil
        let log = RequestLog()

        let reply = await runOneTurn(client: client, log: log) { request in
            Self.response(request, 200, ModelOptionsFixture.json)
        }

        #expect(reply.status == .delivered)
        let body = try #require(log.createBody, "POST /api/sessions must be observed")
        // The real OJAMD v0.20.0 payload's top-level default pair.
        #expect(body["model"] as? String == "kimi-k3")
        #expect(body["require_model_lock"] == nil)
    }

    // MARK: - 241-C — degrade, never block

    @Test @MainActor
    func creationStillSucceedsBareWhenTheCatalogIsUnavailable() async throws {
        let client = makeClient("catalog-down")
        client.modelSelection = nil
        let log = RequestLog()

        let reply = await runOneTurn(client: client, log: log) { request in
            Self.response(request, 500, #"{"error": "boom"}"#)
        }

        // The session is created and the turn answers — an unreachable
        // catalog must never block session creation.
        #expect(reply.status == .delivered)
        let body = try #require(log.createBody, "POST /api/sessions must be observed")
        #expect(body["model"] == nil)
        #expect(body.isEmpty, "the bare body stays byte-compatible with the pre-#241 shape")
    }

    @Test @MainActor
    func creationStillSucceedsWhenTheCatalogFetchThrows() async throws {
        let client = makeClient("catalog-throws")
        client.modelSelection = nil
        let log = RequestLog()

        let reply = await runOneTurn(client: client, log: log) { _ in
            throw URLError(.cannotConnectToHost)
        }

        #expect(reply.status == .delivered)
        let body = try #require(log.createBody, "POST /api/sessions must be observed")
        #expect(body["model"] == nil)
    }

    // MARK: - 241-D — the alias never reaches the wire

    @Test
    func wireSafeModelIDRejectsTheGatewaySelfAlias() {
        // The one choke point every create/pin body's model passes through.
        #expect(SessionsHermesClient.wireSafeModelID("hermes-agent") == nil)
        #expect(SessionsHermesClient.wireSafeModelID("Hermes-Agent") == nil)
        #expect(SessionsHermesClient.wireSafeModelID("  hermes-agent  ") == nil)
        #expect(SessionsHermesClient.wireSafeModelID("") == nil)
        #expect(SessionsHermesClient.wireSafeModelID("   ") == nil)
        #expect(SessionsHermesClient.wireSafeModelID(nil) == nil)
        // Real ids pass through, trimmed.
        #expect(SessionsHermesClient.wireSafeModelID("kimi-k3") == "kimi-k3")
        #expect(SessionsHermesClient.wireSafeModelID(" anthropic/claude-fable-5 ") == "anthropic/claude-fable-5")
        // Not a substring ban — a real id that merely contains the alias survives.
        #expect(SessionsHermesClient.wireSafeModelID("vendor/hermes-agent-v2") == "vendor/hermes-agent-v2")
    }

    @Test @MainActor
    func aliasIsRejectedWhenTheHostAdvertisesItAsItsOwnDefault() async throws {
        // A host whose catalog default IS the sentinel (the "API server model
        // name" hazard). Sending it back would be #241 with extra steps.
        let client = makeClient("poisoned-catalog")
        client.modelSelection = nil
        let log = RequestLog()

        let poisoned = #"{"provider":"kimi-coding","model":"hermes-agent","providers":[]}"#
        let reply = await runOneTurn(client: client, log: log) { request in
            Self.response(request, 200, poisoned)
        }

        #expect(reply.status == .delivered)
        let body = try #require(log.createBody, "POST /api/sessions must be observed")
        #expect(body["model"] == nil, "the alias is rejected — bare beats poisoned")
        for entry in log.all {
            #expect(!entry.body.contains("hermes-agent"), "no request body may carry the alias")
        }
    }

    // MARK: - Path 3 — pin after the first turn

    @Test @MainActor
    func bareCreatedSessionIsPinnedFromTheFirstTurnsRuntimeBlock() async throws {
        // Neither a pick nor a reachable catalog: the session DID inherit the
        // alias at creation, so the first turn's resolved model is pinned to
        // replace it.
        let client = makeClient("pin-after-turn")
        client.modelSelection = nil
        let log = RequestLog()

        ImmunityStubURLProtocol.requestHandler = { request in
            log.record(request)
            let path = request.url?.path ?? ""
            if path == "/api/model/options" {
                return Self.response(request, 503, #"{"error": "unavailable"}"#)
            }
            if path == "/api/sessions" {
                return Self.response(request, 200, #"{"session": {"id": "api_immunity_1"}}"#)
            }
            if path == "/api/sessions/api_immunity_1/model" {
                return Self.response(request, 200, #"{"object": "hermes.session.model_lock"}"#)
            }
            return Self.response(request, 200, """
                {"message": {"content": "ok"},
                 "runtime": {"provider": "kimi-coding", "model": "kimi-k3", "route_source": "global"}}
                """)
        }
        defer { ImmunityStubURLProtocol.requestHandler = nil }

        let reply = await client.send(message: "hello", attachments: [], clientMessageID: UUID())
        #expect(reply.status == .delivered)

        let create = try #require(log.createBody)
        #expect(create["model"] == nil, "creation degraded to bare, as designed")

        let pin = try #require(
            log.all.first { $0.method == "POST" && $0.path == "/api/sessions/api_immunity_1/model" },
            "a bare-created session must be pinned from the first turn's runtime block"
        )
        let pinBody = try #require(
            try JSONSerialization.jsonObject(with: Data(pin.body.utf8)) as? [String: Any]
        )
        #expect(pinBody["model"] as? String == "kimi-k3")
        #expect(pinBody["provider"] as? String == "kimi-coding")
        #expect(!pin.body.contains("hermes-agent"), "no pin body may carry the alias")
    }

    @Test @MainActor
    func aSessionCreatedWithAResolvedModelIsNeverPinned() async throws {
        // The pin exists only to repair the degraded path. A session that
        // already stores a real id must not be pinned — pinning is a
        // CONFIRMED lock and changes turn routing.
        let client = makeClient("no-pin-when-resolved")
        client.modelSelection = nil
        let log = RequestLog()

        ImmunityStubURLProtocol.requestHandler = { request in
            log.record(request)
            let path = request.url?.path ?? ""
            if path == "/api/model/options" {
                return Self.response(request, 200, ModelOptionsFixture.json)
            }
            if path == "/api/sessions" {
                return Self.response(request, 200, #"{"session": {"id": "api_immunity_1"}}"#)
            }
            return Self.response(request, 200, """
                {"message": {"content": "ok"},
                 "runtime": {"provider": "kimi-coding", "model": "kimi-k3", "route_source": "global"}}
                """)
        }
        defer { ImmunityStubURLProtocol.requestHandler = nil }

        let reply = await client.send(message: "hello", attachments: [], clientMessageID: UUID())
        #expect(reply.status == .delivered)
        #expect(log.createBody?["model"] as? String == "kimi-k3")
        #expect(
            !log.all.contains { $0.path.hasSuffix("/model") },
            "no pin may be issued for a session that was created with a real model id"
        )
    }

    @Test @MainActor
    func aFailedPinNeverBreaksTheTurn() async throws {
        // The turn already succeeded when the pin runs; a host that refuses it
        // must cost nothing but a log line.
        let client = makeClient("pin-fails")
        client.modelSelection = nil
        let log = RequestLog()

        ImmunityStubURLProtocol.requestHandler = { request in
            log.record(request)
            let path = request.url?.path ?? ""
            if path == "/api/model/options" {
                return Self.response(request, 503, #"{"error": "unavailable"}"#)
            }
            if path == "/api/sessions" {
                return Self.response(request, 200, #"{"session": {"id": "api_immunity_1"}}"#)
            }
            if path == "/api/sessions/api_immunity_1/model" {
                // A pre-0.20.0 host has no pin route at all.
                return Self.response(request, 404, #"{"error": "not found"}"#)
            }
            return Self.response(request, 200, """
                {"message": {"content": "ok"},
                 "runtime": {"provider": "kimi-coding", "model": "kimi-k3", "route_source": "global"}}
                """)
        }
        defer { ImmunityStubURLProtocol.requestHandler = nil }

        let reply = await client.send(message: "hello", attachments: [], clientMessageID: UUID())
        #expect(reply.status == .delivered, "a refused pin must not fail the turn")
        #expect(reply.content == "ok")
    }

    @Test @MainActor
    func aliasIsRejectedEvenWhenItArrivesAsAPersistedSelection() async throws {
        // Defence in depth: a stored pick can only come from the picker, but
        // the guard must not depend on that.
        let client = makeClient("poisoned-selection")
        client.modelSelection = ModelSelection(provider: "nous", modelID: "hermes-agent")
        let log = RequestLog()

        let reply = await runOneTurn(client: client, log: log) { request in
            Self.response(request, 200, ModelOptionsFixture.json)
        }

        #expect(reply.status == .delivered)
        let body = try #require(log.createBody, "POST /api/sessions must be observed")
        // Falls through the poisoned pick to the host's real catalog default.
        #expect(body["model"] as? String == "kimi-k3")
        let createEntries = log.all.filter { $0.method == "POST" && $0.path == "/api/sessions" }
        for entry in createEntries {
            #expect(!entry.body.contains("hermes-agent"), "no create body may carry the alias")
        }
    }
}
