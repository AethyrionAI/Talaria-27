import Foundation
import Testing
@testable import Talaria

/// #25 — the CTX meter on resumed sessions. The stored-messages endpoint
/// carries no usage (probe 2026-07-16: per-row `token_count` is always null,
/// and the session list's `input_tokens` is cumulative billing, not context
/// occupancy), so the numerator for a resumed session comes from the
/// app-side `SessionUsageIndex` cache of the last live `run.completed` — or
/// is honestly absent, never 0%.
@Suite(.serialized)
struct ContextMeterTests {

    // MARK: - Fixtures

    private final class MeterStubURLProtocol: URLProtocol, @unchecked Sendable {
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
    }

    @MainActor
    private func makePersistence(_ label: String) -> UserDefaultsAppPersistenceStore {
        let suiteName = "ctx-meter-\(label)-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsAppPersistenceStore(defaults: defaults)
    }

    private static func stubbedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MeterStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func response(for request: URLRequest, body: String, contentType: String = "application/json") -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": contentType]
        )!
        return (response, Data(body.utf8))
    }

    /// Serializes `(event, data)` pairs into an SSE body — same shape the
    /// #60 RunCompletedReasoningTests drive the live parse loop with.
    private static func sse(_ events: [(event: String, data: String)]) -> String {
        events.map { "event: \($0.event)\ndata: \($0.data)\n\n" }.joined()
    }

    /// The wire shape the probe verified: rows carry `token_count` — and it
    /// is null on every one. Fixtures must model that, not a hand-made shape
    /// where decoding `token_count` would appear to work.
    private static let storedMessagesBody = #"""
    {"session_id": "api_old", "data": [
        {"id": "m1", "session_id": "api_old", "role": "user", "content": "Hello",
         "timestamp": 1752600000.0, "token_count": null, "tool_calls": null,
         "finish_reason": null, "reasoning": null, "reasoning_content": null},
        {"id": "m2", "session_id": "api_old", "role": "assistant", "content": "Hi there.",
         "timestamp": 1752600005.0, "token_count": null, "tool_calls": null,
         "finish_reason": "stop", "reasoning": null, "reasoning_content": null}
    ]}
    """#

    @MainActor
    private func makeClient(
        persistence: UserDefaultsAppPersistenceStore,
        journal: ConversationJournalStore,
        usageIndex: SessionUsageIndexStore?
    ) -> SessionsHermesClient {
        SessionsHermesClient(
            baseURLProvider: { "http://ojamd:8642" },
            apiKeyProvider: { "key-test" },
            journal: journal,
            transplanter: ContextTransplanter(intelligence: LocalIntelligenceService()),
            session: Self.stubbedSession(),
            usageIndex: usageIndex
        )
    }

    // MARK: - Index + store persistence

    @Test @MainActor
    func recordedUsageRoundTripsThroughPersistence() {
        let persistence = makePersistence("roundtrip")
        let store = SessionUsageIndexStore(persistence: persistence)
        let usage = TokenUsage(promptTokens: 4200, completionTokens: 130, totalTokens: 4330)

        store.record(sessionID: "api_a", usage: usage)

        // A fresh store instance on the same persistence must read it back —
        // the didSet write-through is what survives relaunch.
        let reloaded = SessionUsageIndexStore(persistence: persistence)
        #expect(reloaded.usage(forSessionID: "api_a") == usage)
        #expect(reloaded.usage(forSessionID: "api_unknown") == nil)
    }

    @Test @MainActor
    func lastWriteWinsPerSession() {
        let persistence = makePersistence("lastwrite")
        let store = SessionUsageIndexStore(persistence: persistence)
        store.record(sessionID: "api_a", usage: TokenUsage(promptTokens: 100, completionTokens: 10, totalTokens: 110))
        store.record(sessionID: "api_a", usage: TokenUsage(promptTokens: 250, completionTokens: 20, totalTokens: 270))

        #expect(store.usage(forSessionID: "api_a")?.promptTokens == 250)
    }

    @Test @MainActor
    func emptySessionIDIsNeverRecorded() {
        let persistence = makePersistence("emptyid")
        let store = SessionUsageIndexStore(persistence: persistence)
        store.record(sessionID: "", usage: TokenUsage(promptTokens: 1, completionTokens: 1, totalTokens: 2))
        #expect(store.index.sessionUsages.isEmpty)
    }

    @Test @MainActor
    func malformedPersistedIndexDegradesToUnknownNotThrow() {
        // A corrupt blob must read as an empty index (gauge hidden), never a
        // wrong number and never a throw — the #58 tolerant-decode posture.
        let suiteName = "ctx-meter-malformed-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(Data("not json".utf8), forKey: "hermes.sessionUsageIndex")
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)

        let store = SessionUsageIndexStore(persistence: persistence)
        #expect(store.usage(forSessionID: "api_a") == nil)
        #expect(store.index.sessionUsages.isEmpty)
    }

    @Test @MainActor
    func pruneDropsOnlyAbsentSessions() {
        let persistence = makePersistence("prune")
        let store = SessionUsageIndexStore(persistence: persistence)
        store.record(sessionID: "api_keep", usage: TokenUsage(promptTokens: 1, completionTokens: 1, totalTokens: 2))
        store.record(sessionID: "api_drop", usage: TokenUsage(promptTokens: 2, completionTokens: 2, totalTokens: 4))

        store.prune(keeping: ["api_keep"])

        #expect(store.usage(forSessionID: "api_keep") != nil)
        #expect(store.usage(forSessionID: "api_drop") == nil)
    }

    // MARK: - Resume path (openSession)

    @Test @MainActor
    func resumedSessionWithCachedUsageReadsIt() async throws {
        let persistence = makePersistence("resume-hit")
        let usageIndex = SessionUsageIndexStore(persistence: persistence)
        let cached = TokenUsage(promptTokens: 8100, completionTokens: 420, totalTokens: 8520)
        usageIndex.record(sessionID: "api_old", usage: cached)

        let client = makeClient(
            persistence: persistence,
            journal: ConversationJournalStore(persistence: persistence),
            usageIndex: usageIndex
        )
        MeterStubURLProtocol.requestHandler = { request in
            Self.response(for: request, body: Self.storedMessagesBody)
        }
        defer { MeterStubURLProtocol.requestHandler = nil }

        let convo = try await client.openSession("api_old")

        #expect(convo.latestUsage == cached)
        #expect(convo.messages.count == 2)
    }

    @Test @MainActor
    func resumedSessionWithoutCacheIsHonestlyAbsentNotZero() async throws {
        let persistence = makePersistence("resume-miss")
        let usageIndex = SessionUsageIndexStore(persistence: persistence)
        let journal = ConversationJournalStore(persistence: persistence)
        let client = makeClient(persistence: persistence, journal: journal, usageIndex: usageIndex)
        MeterStubURLProtocol.requestHandler = { request in
            Self.response(for: request, body: Self.storedMessagesBody)
        }
        defer { MeterStubURLProtocol.requestHandler = nil }

        let chatStore = ChatStore(hermesClient: client, persistence: persistence, journal: journal)
        // The denominator IS known — that alone must no longer render a gauge.
        chatStore.replaceCommandCatalog([], activeModel: "test-model", contextWindow: 128_000)

        await chatStore.openSession("api_old")

        #expect(chatStore.conversation?.messages.count == 2)
        #expect(chatStore.resolvedContextWindow(fallbackModelName: nil) == 128_000)
        // Nil numerator = the gauge's hide condition. The old bug surfaced
        // here as promptTokens 0 → "CTX 0%".
        #expect(chatStore.currentContextTokens == nil)
        #expect(chatStore.conversation?.latestUsage == nil)
    }

    @Test @MainActor
    func switchingToUnknownSessionDropsTheStaleNumerator() async throws {
        // A session with a real gauge value is open; switching to a session
        // with no cached usage must hide the gauge, not keep showing the
        // previous session's number.
        let persistence = makePersistence("resume-switch")
        let usageIndex = SessionUsageIndexStore(persistence: persistence)
        let journal = ConversationJournalStore(persistence: persistence)
        let client = makeClient(persistence: persistence, journal: journal, usageIndex: usageIndex)
        MeterStubURLProtocol.requestHandler = { request in
            Self.response(for: request, body: Self.storedMessagesBody)
        }
        defer { MeterStubURLProtocol.requestHandler = nil }

        let chatStore = ChatStore(hermesClient: client, persistence: persistence, journal: journal)
        chatStore.lastTokenUsage = TokenUsage(promptTokens: 9000, completionTokens: 100, totalTokens: 9100)

        await chatStore.openSession("api_old")

        #expect(chatStore.currentContextTokens == nil)
    }

    // MARK: - Live run.completed → cache → resume

    @Test @MainActor
    func liveRunCompletedUsageIsRecordedAndSurvivesResume() async throws {
        let persistence = makePersistence("live-record")
        let usageIndex = SessionUsageIndexStore(persistence: persistence)
        let client = makeClient(
            persistence: persistence,
            journal: ConversationJournalStore(persistence: persistence),
            usageIndex: usageIndex
        )

        let sseBody = Self.sse([
            (event: "run.started", data: #"{"run_id":"run_1"}"#),
            (event: "assistant.delta", data: #"{"delta":"The answer."}"#),
            (event: "assistant.completed", data: #"{"content":"The answer."}"#),
            (event: "run.completed", data: #"{"usage":{"input_tokens":1234,"output_tokens":56,"total_tokens":1290}}"#),
            (event: "done", data: #"{}"#),
        ])
        MeterStubURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            if path == "/api/sessions" {
                return Self.response(for: request, body: #"{"session": {"id": "api_live"}}"#)
            }
            if path.hasSuffix("/chat/stream") {
                return Self.response(for: request, body: sseBody, contentType: "text/event-stream")
            }
            return Self.response(for: request, body: #"{"session_id": "api_live", "data": []}"#)
        }
        defer { MeterStubURLProtocol.requestHandler = nil }

        var finishedUsage: TokenUsage?
        for await update in client.sendStreaming(message: "Why?", attachments: [], clientMessageID: UUID()) {
            if case .finished(_, let usage, _) = update { finishedUsage = usage }
        }

        // The stream's own usage arrived…
        #expect(finishedUsage?.promptTokens == 1234)
        // …and was recorded for the resume path, durably.
        #expect(usageIndex.usage(forSessionID: "api_live")?.totalTokens == 1290)
        let reloaded = SessionUsageIndexStore(persistence: persistence)
        #expect(reloaded.usage(forSessionID: "api_live")?.promptTokens == 1234)

        // Resuming that session on a fresh client reads the cache.
        let laterClient = makeClient(
            persistence: persistence,
            journal: ConversationJournalStore(persistence: persistence),
            usageIndex: reloaded
        )
        let convo = try await laterClient.openSession("api_live")
        #expect(convo.latestUsage?.promptTokens == 1234)
    }

    // MARK: - Mid-stream numerator suppression (#25 second half / #120 lane)

    /// A scriptable client for the live-stream gauge seams: the stream can
    /// park ahead of `.finished` so the test can land a refresh inside the
    /// window (what the 2s relay-poll tick does), `loadConversation()` serves
    /// a refresh source carrying its own `latestUsage` (the relay's legacy
    /// accounting, another backend's thread), and the finish can stamp a
    /// conversation-level usage the way conversation-maintaining backends do.
    @MainActor
    private final class ParkedStreamUsageClient: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .connected
        var currentConversation: Conversation?

        /// Served by `loadConversation()` — the poll-equivalent refresh source.
        var refreshConversation = Conversation(title: Conversation.defaultTitle)
        /// When set, stamped onto `currentConversation` just before `.finished`
        /// yields — a refresh-source number visible at finish time.
        var finishTimeConversationUsage: TokenUsage?
        /// The authoritative run.completed usage `.finished` carries.
        var finishedUsage: TokenUsage?

        var parksBeforeFinish = false
        private(set) var isParkedBeforeFinish = false
        private var finishGate: CheckedContinuation<Void, Never>?

        func releaseFinish() {
            finishGate?.resume()
            finishGate = nil
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
            AsyncStream { continuation in
                Task { @MainActor in
                    continuation.yield(.textDelta("Working "))
                    if self.parksBeforeFinish {
                        await withCheckedContinuation { (gate: CheckedContinuation<Void, Never>) in
                            self.finishGate = gate
                            self.isParkedBeforeFinish = true
                        }
                    }
                    if let usage = self.finishTimeConversationUsage {
                        var conv = self.currentConversation ?? Conversation(title: Conversation.defaultTitle)
                        conv.latestUsage = usage
                        self.currentConversation = conv
                    }
                    continuation.yield(.finished(
                        Message(sender: .hermes, content: "Done.", status: .delivered),
                        self.finishedUsage,
                        nil
                    ))
                    continuation.finish()
                }
            }
        }

        func loadConversation() async -> Conversation {
            refreshConversation
        }

        func clearConversation() async throws -> Conversation {
            Conversation(title: Conversation.defaultTitle)
        }
    }

    @Test @MainActor
    func liveStreamGaugeIgnoresInterimRefreshNumbers() async throws {
        // While a run streams, a conversation refresh (the poll tick) whose
        // source carries its own latestUsage must NOT move the gauge — the
        // previous turn's number keeps displaying (honest) until the run's
        // own run.completed lands.
        let persistence = makePersistence("live-suppress")
        let client = ParkedStreamUsageClient()
        client.parksBeforeFinish = true
        client.finishedUsage = TokenUsage(promptTokens: 1234, completionTokens: 56, totalTokens: 1290)
        var refresh = Conversation(title: Conversation.defaultTitle)
        refresh.latestUsage = TokenUsage(promptTokens: 999_999, completionTokens: 1, totalTokens: 1_000_000)
        client.refreshConversation = refresh

        let store = ChatStore(hermesClient: client, persistence: persistence)
        store.lastTokenUsage = TokenUsage(promptTokens: 1000, completionTokens: 20, totalTokens: 1020)

        let sendTask = Task { await store.sendMessage("Hi") }
        var spins = 0
        while !client.isParkedBeforeFinish, spins < 10_000 {
            spins += 1
            await Task.yield()
        }
        #expect(client.isParkedBeforeFinish)
        #expect(store.currentContextTokens == 1000)

        await store.loadConversation()
        #expect(store.currentContextTokens == 1000)

        client.releaseFinish()
        await sendTask.value
        #expect(store.currentContextTokens == 1234)
    }

    @Test @MainActor
    func finishedTurnPrefersAuthoritativeRunUsage() async throws {
        // run.completed is the numerator's authority (#25 probe verdict).
        // A merged conversation-level number present at finish time must not
        // outrank it.
        let persistence = makePersistence("finish-precedence")
        let client = ParkedStreamUsageClient()
        client.finishTimeConversationUsage = TokenUsage(promptTokens: 777_777, completionTokens: 1, totalTokens: 777_778)
        client.finishedUsage = TokenUsage(promptTokens: 1234, completionTokens: 56, totalTokens: 1290)

        let store = ChatStore(hermesClient: client, persistence: persistence)
        await store.sendMessage("Hi")

        #expect(store.currentContextTokens == 1234)
    }

    @Test @MainActor
    func malformedWireUsageRecordsNothingAndDoesNotThrow() async throws {
        let persistence = makePersistence("live-malformed")
        let usageIndex = SessionUsageIndexStore(persistence: persistence)
        let client = makeClient(
            persistence: persistence,
            journal: ConversationJournalStore(persistence: persistence),
            usageIndex: usageIndex
        )

        let sseBody = Self.sse([
            (event: "assistant.completed", data: #"{"content":"The answer."}"#),
            (event: "run.completed", data: #"{"usage":{"input_tokens":"not-a-number"}}"#),
            (event: "done", data: #"{}"#),
        ])
        MeterStubURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            if path == "/api/sessions" {
                return Self.response(for: request, body: #"{"session": {"id": "api_bad"}}"#)
            }
            return Self.response(for: request, body: sseBody, contentType: "text/event-stream")
        }
        defer { MeterStubURLProtocol.requestHandler = nil }

        var sawFinished = false
        var finishedUsage: TokenUsage?
        for await update in client.sendStreaming(message: "Why?", attachments: [], clientMessageID: UUID()) {
            if case .finished(_, let usage, _) = update {
                sawFinished = true
                finishedUsage = usage
            }
        }

        // The turn still completes; usage degrades to unknown, never a wrong
        // number and never a throw.
        #expect(sawFinished)
        #expect(finishedUsage == nil)
        #expect(usageIndex.usage(forSessionID: "api_bad") == nil)
    }
}
