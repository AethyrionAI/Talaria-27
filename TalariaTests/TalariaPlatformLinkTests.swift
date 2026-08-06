import Foundation
import Testing
@testable import Talaria

/// #251-2A Task 7 — the phone side of the talaria platform transport:
/// auto-pair into the profile-scoped Keychain slot, drain + ack the durable
/// outbox, and re-pair exactly once on a 401.
///
/// Every case below runs through a real `URLProtocol` stub, a real
/// `URLSession`, and the real `JSONDecoder` — the fixtures are raw wire bytes
/// with the gateway's snake_case keys, so what is pinned is the CONTRACT, not
/// a stubbed decoder. Serialized because the stub's handler is a static.
@Suite(.serialized)
@MainActor
struct TalariaPlatformLinkTests {

    // MARK: - Fixtures

    private static let scope = UUID(uuidString: "3A1B7C9D-0E2F-4A5B-8C6D-7E8F9A0B1C2D")!
    private static let tokenKey = BackendProfileScopedKeys.talariaDeviceToken(scope)
    private static let deviceIDKey = tokenKey + ".deviceID"

    /// Records request bodies off the URLSession thread the stub runs on —
    /// a captured `var` would be a data race under strict concurrency.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var bodies: [String] = []

        func record(_ body: String) {
            lock.lock()
            defer { lock.unlock() }
            bodies.append(body)
        }

        var all: [String] {
            lock.lock()
            defer { lock.unlock() }
            return bodies
        }

        func count(containing needle: String) -> Int {
            all.filter { $0.contains(needle) }.count
        }
    }

    @MainActor
    private final class ItemsBox {
        var items: [TalariaPlatformItem] = []
    }

    private func makeLink(
        secureStore: MockSecureStore,
        responder: PhoneQueryResponding? = nil,
        onItems: @escaping @MainActor ([TalariaPlatformItem]) -> Void = { _ in },
        handler: @escaping @Sendable (URLRequest) -> (Int, Data)
    ) -> TalariaPlatformLink {
        StubURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return TalariaPlatformLink(
            gatewayBaseURL: { "http://stub.local:8642" },
            apiKey: { "test-key" },
            installID: { "install-abc" },
            deviceName: { "TestPhone" },
            credentialScopeID: { Self.scope },
            secureStore: secureStore,
            responder: responder,
            onItemsReceived: onItems,
            session: URLSession(configuration: configuration)
        )
    }

    // MARK: - Pairing

    @Test func pairStoresTokenInProfileScopedKeychainSlot() async {
        defer { StubURLProtocol.handler = nil }
        let secure = MockSecureStore()
        let link = makeLink(secureStore: secure) { _ in
            (200, Data(#"{"device_id":"dev12","device_token":"tok-1"}"#.utf8))
        }
        #expect(await link.ensurePaired() == true)
        #expect(await secure.retrieve(key: Self.tokenKey) == "tok-1")
        #expect(await secure.retrieve(key: Self.deviceIDKey) == "dev12")
        // The slot is profile-scoped, not global: a different profile's key
        // is a different string and holds nothing.
        #expect(await secure.retrieve(key: BackendProfileScopedKeys.talariaDeviceToken(UUID())) == nil)
    }

    @Test func pairSkippedWhenAlreadyPaired() async {
        defer { StubURLProtocol.handler = nil }
        let secure = MockSecureStore()
        await secure.store(key: Self.tokenKey, value: "existing")
        await secure.store(key: Self.deviceIDKey, value: "dev-existing")
        let recorder = Recorder()
        let link = makeLink(secureStore: secure) { request in
            recorder.record(StubURLProtocol.bodyString(request))
            return (200, Data(#"{"device_id":"dev99","device_token":"tok-99"}"#.utf8))
        }
        #expect(await link.ensurePaired() == true)
        #expect(recorder.all.isEmpty)          // no network call at all
        #expect(await secure.retrieve(key: Self.tokenKey) == "existing")
    }

    // MARK: - Drain

    @Test func drainParsesItemsAndAcksThem() async {
        defer { StubURLProtocol.handler = nil }
        let secure = MockSecureStore()
        await secure.store(key: Self.tokenKey, value: "tok-1")
        await secure.store(key: Self.deviceIDKey, value: "dev12")
        let recorder = Recorder()
        let received = ItemsBox()
        let link = makeLink(secureStore: secure, onItems: { received.items = $0 }) { request in
            let body = StubURLProtocol.bodyString(request)
            recorder.record(body)
            if body.contains("\"drain\"") {
                return (200, Data(#"""
                {"items":[{"id":"i1","kind":"message","text":"hi","created_at":"2026-08-05T21:00:00+00:00","meta":{"session_id":"s1"}}],"queries":[]}
                """#.utf8))
            }
            return (200, Data(#"{"acked":["i1"]}"#.utf8))
        }

        let outcome = await link.drainOnce(wait: false)

        #expect(outcome == .delivered)
        #expect(received.items.map(\.id) == ["i1"])
        #expect(received.items.first?.kind == "message")
        #expect(received.items.first?.text == "hi")
        // snake_case decoding is real, not asserted against a mock.
        #expect(received.items.first?.createdAt == "2026-08-05T21:00:00+00:00")
        #expect(received.items.first?.meta?["session_id"] == "s1")
        #expect(recorder.all.contains { $0.contains("\"ack\"") && $0.contains("i1") })
        #expect(recorder.count(containing: "\"drain\"") == 1)
    }

    @Test func emptyDrainIsIdleAndAcksNothing() async {
        defer { StubURLProtocol.handler = nil }
        let secure = MockSecureStore()
        await secure.store(key: Self.tokenKey, value: "tok-1")
        await secure.store(key: Self.deviceIDKey, value: "dev12")
        let recorder = Recorder()
        let link = makeLink(secureStore: secure) { request in
            recorder.record(StubURLProtocol.bodyString(request))
            return (200, Data(#"{"items":[],"queries":[]}"#.utf8))
        }

        #expect(await link.drainOnce(wait: false) == .idle)
        #expect(recorder.count(containing: "\"ack\"") == 0)
    }

    @Test func unauthorizedDrainRepairsExactlyOnce() async {
        defer { StubURLProtocol.handler = nil }
        let secure = MockSecureStore()
        await secure.store(key: Self.tokenKey, value: "stale")
        await secure.store(key: Self.deviceIDKey, value: "dev-stale")
        let recorder = Recorder()
        let link = makeLink(secureStore: secure) { request in
            let body = StubURLProtocol.bodyString(request)
            recorder.record(body)
            if body.contains("\"pair\"") {
                return (200, Data(#"{"device_id":"dev13","device_token":"tok-2"}"#.utf8))
            }
            return (401, Data(#"{"error":"bad token","code":"invalid_talaria_auth"}"#.utf8))
        }

        let outcome = await link.drainOnce(wait: false)

        // One re-pair, then the second 401 is taken at face value.
        #expect(outcome == .unauthorized)
        #expect(recorder.count(containing: "\"pair\"") == 1)
        #expect(await secure.retrieve(key: Self.tokenKey) == "tok-2")
        #expect(await secure.retrieve(key: Self.deviceIDKey) == "dev13")
        // The retry actually presented the freshly minted token.
        #expect(recorder.all.last?.contains("tok-2") == true)
    }

    @Test func drainWithoutGatewayURLIsNotConfigured() async {
        defer { StubURLProtocol.handler = nil }
        let secure = MockSecureStore()
        let recorder = Recorder()
        StubURLProtocol.handler = { request in
            recorder.record(StubURLProtocol.bodyString(request))
            return (200, Data())
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let link = TalariaPlatformLink(
            gatewayBaseURL: { nil },
            apiKey: { "test-key" },
            installID: { "install-abc" },
            deviceName: { "TestPhone" },
            credentialScopeID: { Self.scope },
            secureStore: secure,
            responder: nil,
            onItemsReceived: { _ in },
            session: URLSession(configuration: configuration)
        )

        #expect(await link.drainOnce(wait: false) == .notConfigured)
        #expect(recorder.all.isEmpty)
    }

    // MARK: - Loop

    @Test func backoffLadderIsBoundedAndDeterministic() {
        let link = makeLink(secureStore: MockSecureStore()) { _ in (200, Data()) }
        defer { StubURLProtocol.handler = nil }
        #expect(link.nextDelay(afterFailureCount: 1) == 1)
        #expect(link.nextDelay(afterFailureCount: 2) == 2)
        #expect(link.nextDelay(afterFailureCount: 3) == 4)
        #expect(link.nextDelay(afterFailureCount: 6) == 30)
        #expect(link.nextDelay(afterFailureCount: 99) == 30)
    }

    @Test func stopCancelsTheLoop() async throws {
        defer { StubURLProtocol.handler = nil }
        let secure = MockSecureStore()
        await secure.store(key: Self.tokenKey, value: "tok")
        await secure.store(key: Self.deviceIDKey, value: "dev")
        let link = makeLink(secureStore: secure) { _ in
            (200, Data(#"{"items":[],"queries":[]}"#.utf8))
        }
        link.start()
        #expect(link.isRunning == true)
        link.stop()
        #expect(link.isRunning == false)
    }

    @Test func startIsIdempotentWhileAlreadyRunning() async {
        defer { StubURLProtocol.handler = nil }
        let secure = MockSecureStore()
        await secure.store(key: Self.tokenKey, value: "tok")
        await secure.store(key: Self.deviceIDKey, value: "dev")
        let link = makeLink(secureStore: secure) { _ in
            (200, Data(#"{"items":[],"queries":[]}"#.utf8))
        }
        link.start()
        link.start()  // second call must not spawn a competing loop
        #expect(link.isRunning == true)
        link.stop()
        #expect(link.isRunning == false)
    }

    // MARK: - #260(B): the query_result wire payloads

    /// A responder with full #260(B) vocabulary: scripted answer + gate.
    @MainActor
    private final class StubResponder: PhoneQueryResponding {
        var answerValue: PhoneQueryAnswer
        var gateValue: PhoneQueryDeniedGate?

        init(answer: PhoneQueryAnswer, gate: PhoneQueryDeniedGate? = nil) {
            self.answerValue = answer
            self.gateValue = gate
        }

        func answer(kind: String, params: [String: String]) async -> PhoneQueryAnswer { answerValue }
        func deniedGate(kind: String) -> PhoneQueryDeniedGate? { gateValue }
    }

    /// A conformer written before #260(B) existed: `answer` only, so
    /// `deniedGate` resolves through the protocol default. Pins the compat
    /// shape — old conformers keep producing exactly the pre-#260 body.
    @MainActor
    private final class LegacyResponder: PhoneQueryResponding {
        func answer(kind: String, params: [String: String]) async -> PhoneQueryAnswer { .denied }
    }

    /// One drain returning one health query; returns the decoded
    /// `query_result` body the link posted back.
    private func queryResultBody(responder: PhoneQueryResponding) async -> [String: Any]? {
        defer { StubURLProtocol.handler = nil }
        let secure = MockSecureStore()
        await secure.store(key: Self.tokenKey, value: "tok-1")
        await secure.store(key: Self.deviceIDKey, value: "dev12")
        let recorder = Recorder()
        let link = makeLink(secureStore: secure, responder: responder) { request in
            let body = StubURLProtocol.bodyString(request)
            recorder.record(body)
            if body.contains("\"drain\"") {
                return (200, Data(#"{"items":[],"queries":[{"id":"q1","kind":"health","params":{"metric":"steps"}}]}"#.utf8))
            }
            return (200, Data(#"{"ok":true}"#.utf8))
        }
        let outcome = await link.drainOnce(wait: false)
        #expect(outcome == .delivered)
        // Key order in a serialized dictionary is not stable — decode the
        // recorded body instead of substring-matching adjacent keys.
        guard let raw = recorder.all.first(where: { $0.contains("\"query_result\"") }),
              let object = try? JSONSerialization.jsonObject(with: Data(raw.utf8))
        else { return nil }
        return object as? [String: Any]
    }

    @Test func masterDenialNamesTheMasterOnTheWire() async {
        let body = await queryResultBody(responder: StubResponder(answer: .denied, gate: .master))
        #expect(body?["error"] as? String == "permission_denied")
        #expect(body?["denied_gate"] as? String == "master")
        #expect(body?["denied_stream"] == nil)
        #expect(body?["result"] == nil)
    }

    @Test func streamDenialNamesTheStreamOnTheWire() async {
        let body = await queryResultBody(responder: StubResponder(answer: .denied, gate: .stream(sensor: "health")))
        #expect(body?["error"] as? String == "permission_denied")
        #expect(body?["denied_gate"] as? String == "stream")
        #expect(body?["denied_stream"] as? String == "health")
    }

    /// Old conformers (and any future responder that never classifies) keep
    /// the exact pre-#260 body: bare `permission_denied`, no gate keys — the
    /// plugin's generic prose path.
    @Test func legacyResponderDenialStaysBareOnTheWire() async {
        let body = await queryResultBody(responder: LegacyResponder())
        #expect(body?["error"] as? String == "permission_denied")
        #expect(body?["denied_gate"] == nil)
        #expect(body?["denied_stream"] == nil)
    }

    /// #260-B's third payload: iOS-ungranted travels as SUCCESS prose — the
    /// wire carries `result.text` and no error/gate keys at all.
    @Test func successProseCarriesResultAndNoGateKeys() async {
        let body = await queryResultBody(
            responder: StubResponder(answer: .success(text: "Health data permission hasn't been granted."))
        )
        let result = body?["result"] as? [String: Any]
        #expect(result?["text"] as? String == "Health data permission hasn't been granted.")
        #expect(body?["error"] == nil)
        #expect(body?["denied_gate"] == nil)
    }
}

/// Minimal request/response stub: hands every request to a static handler and
/// replays its `(status, body)` verbatim.
private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, data) = handler(request)
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
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
