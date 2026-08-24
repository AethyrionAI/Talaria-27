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
    /// #285: the link reads the gateway API key from the secure store itself
    /// (no injected closure), so the fixture seeds this slot instead.
    private static let apiKeyKey = BackendProfileScopedKeys.gatewayAPIKey(scope)

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
        handler: @escaping @Sendable (URLRequest) -> (Int, Data)?
    ) async -> TalariaPlatformLink {
        StubURLProtocol.handler = handler
        await secureStore.store(key: Self.apiKeyKey, value: "test-key")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return TalariaPlatformLink(
            gatewayBaseURL: { "http://stub.local:8642" },
            installID: { "install-abc" },
            deviceName: { "TestPhone" },
            credentialScopeID: { Self.scope },
            secureStore: secureStore,
            responder: responder,
            onItemsReceived: onItems,
            session: URLSession(configuration: configuration)
        )
    }

    // MARK: - #396: the sensitivity pick rides the mint

    /// **396-P-B — `talk_session_create` carries the user's tuning.** Always
    /// — `.normal` included — so host logs show the choice, and an old host
    /// simply ignores the unknown field (the payload is `payload.get()`
    /// host-side; #383's graceful-degrade shape). Written RED against a
    /// create body that carries no `tuning` key.
    @Test func talkSessionCreateCarriesTheTuningField() async {
        defer { StubURLProtocol.handler = nil }
        let secure = MockSecureStore()
        await secure.store(key: Self.tokenKey, value: "tok-1")
        await secure.store(key: Self.deviceIDKey, value: "dev12")
        let recorder = Recorder()
        let link = await makeLink(secureStore: secure) { request in
            let body = StubURLProtocol.bodyString(request)
            if body.contains(#""talk_session_create""#) {
                recorder.record(body)
                return (200, Data(#"{"voice_session":{"id":"vs-1"}}"#.utf8))
            }
            return (200, Data("{}".utf8))
        }

        _ = await link.talkSessionCreate(tuning: "noisy")

        #expect(recorder.all.count == 1, "the mint must have been observed")
        #expect(recorder.all.first?.contains(#""tuning":"noisy""#) == true,
                "the mint body must carry the pick — got: \(recorder.all.first ?? "nil")")
    }

    // MARK: - Pairing

    @Test func pairStoresTokenInProfileScopedKeychainSlot() async {
        defer { StubURLProtocol.handler = nil }
        let secure = MockSecureStore()
        let link = await makeLink(secureStore: secure) { _ in
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
        let link = await makeLink(secureStore: secure) { request in
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
        let link = await makeLink(secureStore: secure, onItems: { received.items = $0 }) { request in
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
        let link = await makeLink(secureStore: secure) { request in
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
        let link = await makeLink(secureStore: secure) { request in
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

    /// Bar 286-F, pinned together with the pure ladder math: the ladder
    /// isn't hypothetical, and a real settlement failure actually feeds it.
    /// `nextDelay` is the cadence `start()`'s loop consults on any `.failed`
    /// outcome (see its `switch outcome` above); a drain whose ack 500s
    /// classifies exactly that `.failed` (Task 1), so the two assertions
    /// together are "no hot loop by construction" — the loop cannot spin
    /// freely on a broken settlement because the outcome it gets back is the
    /// one the ladder is keyed on.
    @Test func backoffLadderIsBoundedAndDeterministic() async {
        defer { StubURLProtocol.handler = nil }
        let secure = MockSecureStore()
        await secure.store(key: Self.tokenKey, value: "tok-1")
        await secure.store(key: Self.deviceIDKey, value: "dev12")
        let link = await makeLink(secureStore: secure) { request in
            let body = StubURLProtocol.bodyString(request)
            if body.contains("\"drain\"") {
                return (200, Data(#"""
                {"items":[{"id":"i1","kind":"message","text":"hi","created_at":"2026-08-05T21:00:00+00:00","meta":{"session_id":"s1"}}],"queries":[]}
                """#.utf8))
            }
            return (500, Data())
        }
        #expect(link.nextDelay(afterFailureCount: 1) == 1)
        #expect(link.nextDelay(afterFailureCount: 2) == 2)
        #expect(link.nextDelay(afterFailureCount: 3) == 4)
        #expect(link.nextDelay(afterFailureCount: 6) == 30)
        #expect(link.nextDelay(afterFailureCount: 99) == 30)
        #expect(await link.drainOnce(wait: false) == .failed)
    }

    @Test func stopCancelsTheLoop() async throws {
        defer { StubURLProtocol.handler = nil }
        let secure = MockSecureStore()
        await secure.store(key: Self.tokenKey, value: "tok")
        await secure.store(key: Self.deviceIDKey, value: "dev")
        let link = await makeLink(secureStore: secure) { _ in
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
        let link = await makeLink(secureStore: secure) { _ in
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
        let link = await makeLink(secureStore: secure, responder: responder) { request in
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

    // MARK: - #286: honest settlement classification

    /// Bars 286-A + 286-D's dedupe half: a drain that delivers an item but
    /// whose ack POST 500s must still hand the item to the app (rows are
    /// delivered before ack — redelivery on the next drain is deduped
    /// upstream by `platformID`), but the TURN classifies `.failed` so the
    /// backoff ladder engages instead of resetting on a false `.delivered`.
    @Test func ackServerErrorClassifiesTheDrainFailed() async {
        defer { StubURLProtocol.handler = nil }
        let secure = MockSecureStore()
        await secure.store(key: Self.tokenKey, value: "tok-1")
        await secure.store(key: Self.deviceIDKey, value: "dev12")
        let received = ItemsBox()
        let link = await makeLink(secureStore: secure, onItems: { received.items = $0 }) { request in
            let body = StubURLProtocol.bodyString(request)
            if body.contains("\"drain\"") {
                return (200, Data(#"""
                {"items":[{"id":"i1","kind":"message","text":"hi","created_at":"2026-08-05T21:00:00+00:00","meta":{"session_id":"s1"}}],"queries":[]}
                """#.utf8))
            }
            return (500, Data())
        }

        let outcome = await link.drainOnce(wait: false)

        #expect(outcome == .failed)
        #expect(received.items.count == 1)
    }

    /// Bar 286-B: the ack request fails at transport — the stub's handler
    /// signals "no response" (nil) rather than any status, which drives a
    /// real `didFailWithError` through the URLProtocol client, exercising
    /// `post`'s `guard let ... else` branch rather than a non-200 status.
    @Test func ackTransportFailureClassifiesTheDrainFailed() async {
        defer { StubURLProtocol.handler = nil }
        let secure = MockSecureStore()
        await secure.store(key: Self.tokenKey, value: "tok-1")
        await secure.store(key: Self.deviceIDKey, value: "dev12")
        let link = await makeLink(secureStore: secure) { request in
            let body = StubURLProtocol.bodyString(request)
            if body.contains("\"drain\"") {
                return (200, Data(#"""
                {"items":[{"id":"i1","kind":"message","text":"hi","created_at":"2026-08-05T21:00:00+00:00","meta":{"session_id":"s1"}}],"queries":[]}
                """#.utf8))
            }
            return nil  // transport failure, not a server response
        }

        let outcome = await link.drainOnce(wait: false)

        #expect(outcome == .failed)
    }

    /// Bar 286-C: both `query_result` attempts 500 (Task 2 adds a retry —
    /// answering 500 to every `query_result` POST keeps this valid before
    /// and after that retry lands).
    @Test func queryResultServerErrorClassifiesTheDrainFailed() async {
        defer { StubURLProtocol.handler = nil }
        let secure = MockSecureStore()
        await secure.store(key: Self.tokenKey, value: "tok-1")
        await secure.store(key: Self.deviceIDKey, value: "dev12")
        let link = await makeLink(secureStore: secure) { request in
            let body = StubURLProtocol.bodyString(request)
            if body.contains("\"drain\"") {
                return (200, Data(#"{"items":[],"queries":[{"id":"q1","kind":"health","params":{"metric":"steps"}}]}"#.utf8))
            }
            return (500, Data())
        }

        let outcome = await link.drainOnce(wait: false)

        #expect(outcome == .failed)
    }

    // MARK: - #286 Task 2: one bounded in-turn retry for query answers

    /// A `@Sendable`-safe box so the network stub (which runs off the
    /// MainActor — see `WireRecorder` in `ProfileSwitchAtomicityTests`) can
    /// reach back into the link to drive a mid-drain `stop()`. That file's
    /// idiom parks on a gated secure store and calls `stop()` from the test
    /// body between the park and the release; the retry's own gate is a
    /// plain `Task.sleep(for: .seconds(2))`, which has no park to hook, so
    /// this box instead lets the handler that answers the FIRST failed
    /// `query_result` POST schedule the `stop()` itself — landing well
    /// inside the 2s pause that follows.
    private final class LinkBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _link: TalariaPlatformLink?
        var link: TalariaPlatformLink? {
            get { lock.lock(); defer { lock.unlock() }; return _link }
            set { lock.lock(); defer { lock.unlock() }; _link = newValue }
        }
    }

    /// Bar 286-C follow-up: the first `query_result` 500s, the retry 200s.
    /// Recomputation is fine — the server is exactly-once by `query_id`
    /// (protocol read, #286 filing) — so the two bodies need not match.
    @Test func queryAnswerRetriesOnceAndRecovers() async {
        defer { StubURLProtocol.handler = nil }
        let secure = MockSecureStore()
        await secure.store(key: Self.tokenKey, value: "tok-1")
        await secure.store(key: Self.deviceIDKey, value: "dev12")
        let recorder = Recorder()
        let link = await makeLink(secureStore: secure) { request in
            let body = StubURLProtocol.bodyString(request)
            if body.contains("\"drain\"") {
                return (200, Data(#"{"items":[],"queries":[{"id":"q1","kind":"health","params":{"metric":"steps"}}]}"#.utf8))
            }
            if body.contains("\"query_result\"") {
                recorder.record(body)
                return recorder.count(containing: "\"query_result\"") == 1
                    ? (500, Data())
                    : (200, Data(#"{"ok":true}"#.utf8))
            }
            return (200, Data())
        }

        let outcome = await link.drainOnce(wait: false)

        #expect(outcome == .delivered)
        #expect(recorder.count(containing: "\"query_result\"") == 2)
    }

    /// A `stop()` landing in the 2s gap between the failed first attempt and
    /// the retry must abandon the retry: `.superseded`, exactly one
    /// `query_result` request on the wire (the retry never goes out).
    @Test func queryAnswerRetryIsEpochChecked() async {
        defer { StubURLProtocol.handler = nil }
        let secure = MockSecureStore()
        await secure.store(key: Self.tokenKey, value: "tok-1")
        await secure.store(key: Self.deviceIDKey, value: "dev12")
        let recorder = Recorder()
        let box = LinkBox()
        let link = await makeLink(secureStore: secure) { request in
            let body = StubURLProtocol.bodyString(request)
            if body.contains("\"drain\"") {
                return (200, Data(#"{"items":[],"queries":[{"id":"q1","kind":"health","params":{"metric":"steps"}}]}"#.utf8))
            }
            if body.contains("\"query_result\"") {
                recorder.record(body)
                // Drives the mid-turn stop() from the handler itself — see
                // `LinkBox`'s doc comment above for why this test can't
                // reuse ProfileSwitchAtomicityTests' gated-secure-store
                // park/release idiom directly.
                Task { @MainActor in box.link?.stop() }
                return (500, Data())
            }
            return (200, Data())
        }
        box.link = link

        let outcome = await link.drainOnce(wait: false)

        #expect(outcome == .superseded)
        #expect(recorder.count(containing: "\"query_result\"") == 1)
    }

    /// Bar 286-D: a fully successful settlement (ack 200, query_result 200)
    /// still classifies `.delivered` — pins current behavior against
    /// regression from the new failure-folding logic.
    @Test func happyPathSettlementStaysDelivered() async {
        defer { StubURLProtocol.handler = nil }
        let secure = MockSecureStore()
        await secure.store(key: Self.tokenKey, value: "tok-1")
        await secure.store(key: Self.deviceIDKey, value: "dev12")
        let received = ItemsBox()
        let link = await makeLink(secureStore: secure, onItems: { received.items = $0 }) { request in
            let body = StubURLProtocol.bodyString(request)
            if body.contains("\"drain\"") {
                return (200, Data(#"""
                {"items":[{"id":"i1","kind":"message","text":"hi","created_at":"2026-08-05T21:00:00+00:00","meta":{"session_id":"s1"}}],"queries":[{"id":"q1","kind":"health","params":{"metric":"steps"}}]}
                """#.utf8))
            }
            return (200, Data(#"{"ok":true}"#.utf8))
        }

        let outcome = await link.drainOnce(wait: false)

        #expect(outcome == .delivered)
        #expect(received.items.count == 1)
    }

    /// Bar 286-E: a 401 on the ACK POST (not the drain POST) folds into the
    /// same `false`/`.failed` path as any other non-200 — the drain-owned
    /// 401-repair machinery (the re-pair-once-then-give-up dance in `drain`,
    /// pinned by `unauthorizedDrainRepairsExactlyOnce` above) belongs to the
    /// DRAIN request alone and must never fire off a settlement 401. A
    /// settlement 401 on a token that just drained 200 is transient skew; a
    /// truly stale pair fails the NEXT drain, which owns the repair.
    @Test func settlementUnauthorizedClassifiesFailedWithoutTouchingThePair() async {
        defer { StubURLProtocol.handler = nil }
        let secure = MockSecureStore()
        await secure.store(key: Self.tokenKey, value: "tok-1")
        await secure.store(key: Self.deviceIDKey, value: "dev12")
        let recorder = Recorder()
        let received = ItemsBox()
        let link = await makeLink(secureStore: secure, onItems: { received.items = $0 }) { request in
            let body = StubURLProtocol.bodyString(request)
            recorder.record(body)
            if body.contains("\"drain\"") {
                return (200, Data(#"""
                {"items":[{"id":"i1","kind":"message","text":"hi","created_at":"2026-08-05T21:00:00+00:00","meta":{"session_id":"s1"}}],"queries":[]}
                """#.utf8))
            }
            return (401, Data(#"{"error":"bad token","code":"invalid_talaria_auth"}"#.utf8))
        }

        let outcome = await link.drainOnce(wait: false)

        #expect(outcome == .failed)
        #expect(received.items.count == 1)
        // The pair is untouched — no drop, no re-mint.
        #expect(await secure.retrieve(key: Self.tokenKey) == "tok-1")
        #expect(await secure.retrieve(key: Self.deviceIDKey) == "dev12")
        #expect(recorder.count(containing: "\"pair\"") == 0)
    }

    // MARK: - Link probe (#269-A)

    @Test func probeClassifies401AsAdapterLiveAndSendsNoBearer() async {
        defer { StubURLProtocol.handler = nil }
        let recorder = Recorder()
        let link = await makeLink(secureStore: MockSecureStore()) { request in
            recorder.record(request.value(forHTTPHeaderField: "Authorization") ?? "NONE")
            return (401, Data(#"{"error":"missing_bearer"}"#.utf8))
        }
        #expect(await link.probeLinkState() == .adapterLive(status: 401))
        #expect(recorder.all == ["NONE"])  // unauthenticated by design
    }

    @Test func probeClassifies503AsAdapterAbsent() async {
        defer { StubURLProtocol.handler = nil }
        let link = await makeLink(secureStore: MockSecureStore()) { _ in
            (503, Data(#"{"error":"platform_unavailable"}"#.utf8))
        }
        #expect(await link.probeLinkState() == .adapterAbsent(status: 503))
    }

    @Test func probeClassifiesUnexpectedStatusAsIndeterminate() async {
        defer { StubURLProtocol.handler = nil }
        let link = await makeLink(secureStore: MockSecureStore()) { _ in
            (418, Data())
        }
        #expect(await link.probeLinkState() == .indeterminate(status: 418))
    }

    @Test func probeClassifiesTransportFailureAsHostUnreachable() async {
        defer { StubURLProtocol.handler = nil }
        // A nil handler result is the stub's transport-failure convention.
        let link = await makeLink(secureStore: MockSecureStore()) { _ in nil }
        #expect(await link.probeLinkState() == .hostUnreachable)
    }

    @Test func probeWithNoGatewayURLIsNotConfigured() async {
        defer { StubURLProtocol.handler = nil }
        StubURLProtocol.handler = { _ in (401, Data()) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let link = TalariaPlatformLink(
            gatewayBaseURL: { nil },
            installID: { "install-abc" },
            deviceName: { "TestPhone" },
            credentialScopeID: { Self.scope },
            secureStore: MockSecureStore(),
            responder: nil,
            onItemsReceived: { _ in },
            session: URLSession(configuration: configuration)
        )
        #expect(await link.probeLinkState() == .notConfigured)
    }
}

/// Minimal request/response stub: hands every request to a static handler and
/// replays its `(status, body)` verbatim.
private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    /// A handler returning `nil` (rather than any status) simulates a
    /// transport failure — the stub delivers a real `didFailWithError`
    /// instead of any response, exercising `post`'s transport-nil branch.
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, Data)?)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        guard let (status, data) = handler(request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            return
        }
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
