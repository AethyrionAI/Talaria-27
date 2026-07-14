import Foundation
import Testing
@testable import Talaria

/// #4.15 — the `_thinking` reasoning channel: SSE payload parsing, streaming
/// accumulation onto the placeholder, preservation through `.finished`, and
/// cache round-tripping of the new Message fields.
struct ReasoningChannelTests {

    // MARK: SSE payload parsing

    @Test func parsesCanonicalThinkingDelta() {
        let payload = #"{"tool_name":"_thinking","delta":"Considering the request"}"#
        #expect(SessionsHermesClient.thinkingDelta(fromToolProgress: payload) == "Considering the request")
    }

    @Test func parsesDriftedDeltaKeys() {
        // The exact key is unverified against the live host — the parser must
        // survive the plausible spellings.
        #expect(SessionsHermesClient.thinkingDelta(
            fromToolProgress: #"{"tool_name":"_thinking","content":"step 1"}"#
        ) == "step 1")
        #expect(SessionsHermesClient.thinkingDelta(
            fromToolProgress: #"{"tool_name":"_thinking","text":"step 2"}"#
        ) == "step 2")
        #expect(SessionsHermesClient.thinkingDelta(
            fromToolProgress: #"{"name":"_thinking","message":"step 3"}"#
        ) == "step 3")
        #expect(SessionsHermesClient.thinkingDelta(
            fromToolProgress: #"{"tool_name":"_thinking","args":{"content":"nested"}}"#
        ) == "nested")
    }

    @Test func ignoresRealToolProgressAndGarbage() {
        // A real tool's progress event must never leak into the reasoning UI.
        #expect(SessionsHermesClient.thinkingDelta(
            fromToolProgress: #"{"tool_name":"web_search","delta":"50%"}"#
        ) == nil)
        #expect(SessionsHermesClient.thinkingDelta(
            fromToolProgress: #"{"tool_name":"_thinking"}"#
        ) == nil)
        #expect(SessionsHermesClient.thinkingDelta(
            fromToolProgress: #"{"tool_name":"_thinking","delta":""}"#
        ) == nil)
        #expect(SessionsHermesClient.thinkingDelta(fromToolProgress: "not json") == nil)
    }

    // MARK: Wire-mode hedge (increments vs cumulative snapshots)

    @Test func incrementalDeltaPassesThroughIncrementMode() {
        #expect(SessionsHermesClient.incrementalReasoningDelta(from: "Step two.", assembled: "Step one.") == "Step two.")
        #expect(SessionsHermesClient.incrementalReasoningDelta(from: "Step one.", assembled: "") == "Step one.")
        #expect(SessionsHermesClient.incrementalReasoningDelta(from: "", assembled: "anything") == nil)
    }

    @Test func incrementalDeltaUnwrapsCumulativeSnapshots() {
        // A chunk that starts with everything assembled so far is a snapshot —
        // only the new suffix may be forwarded, or the text duplicates.
        #expect(SessionsHermesClient.incrementalReasoningDelta(
            from: "Step one. Step two.",
            assembled: "Step one. "
        ) == "Step two.")
        // An identical re-send adds nothing.
        #expect(SessionsHermesClient.incrementalReasoningDelta(
            from: "Step one.",
            assembled: "Step one."
        ) == nil)
    }

    // MARK: Mirror guard (#60)

    @Test func mirrorGuardDetectsIdenticalText() {
        #expect(SessionsHermesClient.reasoningMirrorsAnswer("The answer.", content: "The answer."))
    }

    @Test func mirrorGuardFoldsWhitespaceRuns() {
        // The defective `_thinking` event and the answer can differ in
        // chunk-join artifacts only — folded, they are the same text.
        #expect(SessionsHermesClient.reasoningMirrorsAnswer(
            "The\n\nanswer,  spread\tacross lines.",
            content: " The answer, spread across lines. "
        ))
    }

    @Test func mirrorGuardPassesGenuinelyDistinctReasoning() {
        #expect(!SessionsHermesClient.reasoningMirrorsAnswer("Step one: think.", content: "The answer."))
        // A superset is NOT a mirror — reasoning that contains the answer
        // plus real thought must survive.
        #expect(!SessionsHermesClient.reasoningMirrorsAnswer("The answer. Because reasons.", content: "The answer."))
    }

    // MARK: Last-line extraction (streaming placeholder + collapsed fallback)

    @Test func lastReasoningLineSkipsTrailingBlanks() {
        #expect(MessageBubble.lastReasoningLine("First step.\nSecond step.\n  \n") == "Second step.")
        #expect(MessageBubble.lastReasoningLine("single") == "single")
        #expect(MessageBubble.lastReasoningLine("   \n\n") == nil)
        #expect(MessageBubble.lastReasoningLine("") == nil)
    }

    // MARK: Message cache round-trip

    @Test func reasoningFieldsSurviveCacheRoundTrip() throws {
        let original = Message(
            sender: .hermes,
            content: "Answer",
            status: .delivered,
            reasoning: "Step one.\nStep two.",
            reasoningSummary: "Worked out the two steps"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        #expect(decoded.reasoning == "Step one.\nStep two.")
        #expect(decoded.reasoningSummary == "Worked out the two steps")
    }

    @Test func preReasoningCachesDecodeWithNilFields() throws {
        // A cache written before #4.15 has no reasoning keys — it must decode.
        let legacy = Message(sender: .hermes, content: "Old reply", status: .delivered)
        let data = try JSONEncoder().encode(legacy)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("reasoning"))
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        #expect(decoded.reasoning == nil)
        #expect(decoded.reasoningSummary == nil)
    }

    // MARK: Streaming accumulation (ChatStore)

    @MainActor
    private final class ReasoningStreamClient: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .connected
        var currentConversation: Conversation?

        func connect() async {}
        func disconnect() async {}

        func send(message: String, attachments: [PendingAttachment], clientMessageID: UUID) async -> Message {
            Message(sender: .hermes, content: "unused", status: .delivered)
        }

        func sendStreaming(message: String, attachments: [PendingAttachment], clientMessageID: UUID) -> AsyncStream<StreamingUpdate> {
            AsyncStream { continuation in
                Task { @MainActor in
                    continuation.yield(.messageSent(jobID: UUID()))
                    continuation.yield(.reasoningDelta("Step one."))
                    continuation.yield(.reasoningDelta("\nStep two."))
                    continuation.yield(.textDelta("The answer."))
                    // The final message carries no reasoning of its own — the
                    // store must keep what the placeholder accumulated.
                    continuation.yield(.finished(
                        Message(sender: .hermes, content: "The answer.", status: .delivered),
                        nil,
                        nil
                    ))
                    continuation.finish()
                }
            }
        }

        func loadConversation() async -> Conversation {
            currentConversation ?? Conversation(title: "Hermes")
        }

        func clearConversation() async throws -> Conversation {
            Conversation(title: "Hermes")
        }
    }

    @Test @MainActor
    func chatStoreAccumulatesReasoningAndKeepsItOnFinish() async throws {
        let suiteName = "reasoning-stream-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let chatStore = ChatStore(hermesClient: ReasoningStreamClient(), persistence: persistence)

        await chatStore.sendMessage("Why?")

        let reply = try #require(chatStore.conversation?.messages.last(where: { $0.sender == .hermes }))
        #expect(reply.content == "The answer.")
        #expect(reply.reasoning == "Step one.\nStep two.")
        #expect(reply.reasoningSummary == nil)
        #expect(reply.status == .delivered)

        // And the accumulated reasoning must survive the end-of-send cache write.
        let cached = try #require(persistence.loadConversationCache())
        let cachedReply = try #require(cached.messages.last(where: { $0.sender == .hermes }))
        #expect(cachedReply.reasoning == "Step one.\nStep two.")
    }

    @Test @MainActor
    func mergeKeepsLocalTitleAndPreviewOverPlaceholderBase() async throws {
        // The Sessions client's base conversation only ever carries the
        // placeholder title and no preview; the post-turn merge must not
        // demote a generated (or manual) title back to it — otherwise the
        // #4.8 gate re-trips and regenerates the card every turn.
        let suiteName = "title-merge-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let client = ReasoningStreamClient()
        client.currentConversation = Conversation(title: Conversation.defaultTitle)
        let chatStore = ChatStore(hermesClient: client, persistence: persistence)
        chatStore.conversation = Conversation(
            title: "Reverse proxy setup",
            generatedPreview: "Caddy for the home lab"
        )

        await chatStore.sendMessage("More detail?")

        #expect(chatStore.conversation?.title == "Reverse proxy setup")
        #expect(chatStore.conversation?.generatedPreview == "Caddy for the home lab")
    }

    // MARK: ChatStore resurrection side door (#60)

    /// Like `ReasoningStreamClient`, but the streamed updates are scripted
    /// per-test so the placeholder can accumulate a mirror or genuine text.
    @MainActor
    private final class ScriptedReasoningClient: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .connected
        var currentConversation: Conversation?
        var script: [StreamingUpdate] = []

        func connect() async {}
        func disconnect() async {}

        func send(message: String, attachments: [PendingAttachment], clientMessageID: UUID) async -> Message {
            Message(sender: .hermes, content: "unused", status: .delivered)
        }

        func sendStreaming(message: String, attachments: [PendingAttachment], clientMessageID: UUID) -> AsyncStream<StreamingUpdate> {
            let updates = script
            return AsyncStream { continuation in
                Task { @MainActor in
                    continuation.yield(.messageSent(jobID: UUID()))
                    for update in updates { continuation.yield(update) }
                    continuation.finish()
                }
            }
        }

        func loadConversation() async -> Conversation {
            currentConversation ?? Conversation(title: "Hermes")
        }

        func clearConversation() async throws -> Conversation {
            Conversation(title: "Hermes")
        }
    }

    @MainActor
    private func makeScriptedStore(script: [StreamingUpdate]) -> ChatStore {
        let suiteName = "reasoning-side-door-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let client = ScriptedReasoningClient()
        client.script = script
        return ChatStore(hermesClient: client, persistence: persistence)
    }

    @Test @MainActor
    func chatStoreDoesNotResurrectAnswerMirrorReasoning() async throws {
        // The placeholder accumulated exactly the answer text (the defective
        // upstream `_thinking` mirror) and the client — having refused it —
        // attached nothing to the final message. The fallback keep must not
        // resurrect it.
        let chatStore = makeScriptedStore(script: [
            .reasoningDelta("The answer."),
            .textDelta("The answer."),
            .finished(Message(sender: .hermes, content: "The answer.", status: .delivered), nil, nil),
        ])

        await chatStore.sendMessage("Why?")

        let reply = try #require(chatStore.conversation?.messages.last(where: { $0.sender == .hermes }))
        #expect(reply.content == "The answer.")
        #expect(reply.reasoning == nil)
    }

    @Test @MainActor
    func chatStoreKeepsDistinctPlaceholderReasoning() async throws {
        // Genuine accumulated reasoning (distinct from the answer) still
        // survives a final message that carries none of its own —
        // the relay/mock-client keep that #4.15 introduced.
        let chatStore = makeScriptedStore(script: [
            .reasoningDelta("Weigh both options first."),
            .textDelta("The answer."),
            .finished(Message(sender: .hermes, content: "The answer.", status: .delivered), nil, nil),
        ])

        await chatStore.sendMessage("Why?")

        let reply = try #require(chatStore.conversation?.messages.last(where: { $0.sender == .hermes }))
        #expect(reply.reasoning == "Weigh both options first.")
    }

    // MARK: run.completed reasoning adoption + attach precedence (#60)

    /// End-to-end fixtures against the REAL `SessionsHermesClient` SSE parse
    /// loop: a stubbed URLSession serves a scripted event stream, and the
    /// `.finished` message is inspected. Serialized — the stub protocol's
    /// request handler is class-global state.
    @Suite(.serialized)
    struct RunCompletedReasoningTests {

        private final class SSEStubProtocol: URLProtocol, @unchecked Sendable {
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

        /// Serializes `(event, data)` pairs into an SSE body. Every `data`
        /// value must be single-line JSON — real newlines belong JSON-escaped
        /// (`\n`) inside it, exactly as on the wire.
        private static func sse(_ events: [(event: String, data: String)]) -> String {
            events.map { "event: \($0.event)\ndata: \($0.data)\n\n" }.joined()
        }

        /// Runs one streamed turn through a real client (fresh journal — no
        /// transplant) against the scripted SSE body and returns the
        /// `.finished` payload, nil when the stream never finished.
        @MainActor
        private func streamTurn(sseBody: String) async -> (message: Message, usage: TokenUsage?)? {
            let suiteName = "run-reasoning-\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            defaults.removePersistentDomain(forName: suiteName)
            let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)

            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [SSEStubProtocol.self]
            let session = URLSession(configuration: configuration)

            SSEStubProtocol.requestHandler = { request in
                guard let url = request.url else { throw URLError(.badURL) }
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                switch url.path {
                case "/api/sessions":
                    return (response, Data(#"{"session":{"id":"sess-1"}}"#.utf8))
                case "/api/sessions/sess-1/chat/stream":
                    return (response, Data(sseBody.utf8))
                default:
                    throw URLError(.badURL)
                }
            }
            defer { SSEStubProtocol.requestHandler = nil }

            let client = SessionsHermesClient(
                baseURLProvider: { "http://hermes.test" },
                apiKeyProvider: { "test-key" },
                journal: ConversationJournalStore(persistence: persistence),
                transplanter: ContextTransplanter(intelligence: LocalIntelligenceService()),
                session: session
            )

            var finished: (message: Message, usage: TokenUsage?)?
            for await update in client.sendStreaming(message: "Q", attachments: [], clientMessageID: UUID()) {
                if case .finished(let message, let usage, _) = update {
                    finished = (message: message, usage: usage)
                }
            }
            return finished
        }

        /// The probed wire shape's common prefix: answer deltas plus, when
        /// `thinkingMirror` is set, the defective cumulative `_thinking`
        /// event that carries the answer verbatim.
        private static func turnPrefix(thinkingMirror: Bool) -> [(event: String, data: String)] {
            var events: [(event: String, data: String)] = [
                (event: "run.started", data: #"{"run_id":"r1"}"#),
                (event: "assistant.delta", data: #"{"delta":"The answer."}"#),
            ]
            if thinkingMirror {
                events.append((event: "tool.progress", data: #"{"tool_name":"_thinking","delta":"The answer."}"#))
            }
            events.append((event: "assistant.completed", data: #"{"content":"The answer."}"#))
            return events
        }

        // MARK: decodeRunReasoning (exercised through the live parse)

        @Test func adoptsReasoningContentVerbatim() async throws {
            let body = Self.sse(Self.turnPrefix(thinkingMirror: false) + [
                (event: "run.completed",
                 data: #"{"completed":true,"messages":[{"role":"assistant","content":"The answer.","finish_reason":"stop","reasoning_content":"Step one.\nStep two."}]}"#),
                (event: "done", data: #"{}"#),
            ])
            let finished = try #require(await streamTurn(sseBody: body))
            #expect(finished.message.content == "The answer.")
            #expect(finished.message.reasoning == "Step one.\nStep two.")
        }

        @Test func fallsBackToReasoningKeyAndTrims() async throws {
            let body = Self.sse(Self.turnPrefix(thinkingMirror: false) + [
                (event: "run.completed",
                 data: #"{"messages":[{"role":"assistant","reasoning":"  Real chain of thought.\n"}]}"#),
                (event: "done", data: #"{}"#),
            ])
            let finished = try #require(await streamTurn(sseBody: body))
            #expect(finished.message.reasoning == "Real chain of thought.")
        }

        @Test func reasoningContentWinsOverReasoning() async throws {
            let body = Self.sse(Self.turnPrefix(thinkingMirror: false) + [
                (event: "run.completed",
                 data: #"{"messages":[{"role":"assistant","reasoning":"stale duplicate","reasoning_content":"canonical"}]}"#),
                (event: "done", data: #"{}"#),
            ])
            let finished = try #require(await streamTurn(sseBody: body))
            #expect(finished.message.reasoning == "canonical")
        }

        @Test func lastAssistantEntryWins() async throws {
            let body = Self.sse(Self.turnPrefix(thinkingMirror: false) + [
                (event: "run.completed",
                 data: #"{"messages":[{"role":"assistant","reasoning_content":"first round"},{"role":"user","content":"Q"},{"role":"assistant","reasoning_content":"final round"}]}"#),
                (event: "done", data: #"{}"#),
            ])
            let finished = try #require(await streamTurn(sseBody: body))
            #expect(finished.message.reasoning == "final round")
        }

        @Test func blankOrAbsentStructuredReasoningYieldsNil() async throws {
            // Blank reasoning keys are absent-equivalent — with no `_thinking`
            // text either, nothing attaches.
            let blank = Self.sse(Self.turnPrefix(thinkingMirror: false) + [
                (event: "run.completed",
                 data: #"{"messages":[{"role":"assistant","reasoning_content":"  \n ","reasoning":""}]}"#),
                (event: "done", data: #"{}"#),
            ])
            let blankFinished = try #require(await streamTurn(sseBody: blank))
            #expect(blankFinished.message.reasoning == nil)

            let absent = Self.sse(Self.turnPrefix(thinkingMirror: false) + [
                (event: "run.completed", data: #"{"completed":true}"#),
                (event: "done", data: #"{}"#),
            ])
            let absentFinished = try #require(await streamTurn(sseBody: absent))
            #expect(absentFinished.message.reasoning == nil)
        }

        @Test func malformedRunCompletedNeverThrows() async throws {
            let body = Self.sse(Self.turnPrefix(thinkingMirror: false) + [
                (event: "run.completed", data: #"not-json{{{"#),
                (event: "done", data: #"{}"#),
            ])
            // The turn still finishes cleanly off assistant.completed —
            // reasoning and usage are simply absent.
            let finished = try #require(await streamTurn(sseBody: body))
            #expect(finished.message.content == "The answer.")
            #expect(finished.message.reasoning == nil)
            #expect(finished.usage == nil)
        }

        // MARK: Attach precedence

        @Test func structuredReasoningWinsOverThinkingMirror() async throws {
            // The wire truth (probed 2026-07-13): `_thinking` mirrors the
            // answer, the real CoT rides run.completed. Structured wins —
            // and usage still decodes off the same payload.
            let body = Self.sse(Self.turnPrefix(thinkingMirror: true) + [
                (event: "run.completed",
                 data: #"{"messages":[{"role":"assistant","content":"The answer.","reasoning_content":"Real chain of thought.","reasoning":"Real chain of thought."}],"usage":{"input_tokens":10,"output_tokens":5,"total_tokens":15}}"#),
                (event: "done", data: #"{}"#),
            ])
            let finished = try #require(await streamTurn(sseBody: body))
            #expect(finished.message.content == "The answer.")
            #expect(finished.message.reasoning == "Real chain of thought.")
            #expect(finished.usage?.totalTokens == 15)
        }

        @Test func thinkingMirrorAloneNeverAttaches() async throws {
            let body = Self.sse(Self.turnPrefix(thinkingMirror: true) + [
                (event: "run.completed",
                 data: #"{"messages":[{"role":"assistant","content":"The answer.","finish_reason":"stop"}],"usage":{"input_tokens":10,"output_tokens":5,"total_tokens":15}}"#),
                (event: "done", data: #"{}"#),
            ])
            let finished = try #require(await streamTurn(sseBody: body))
            #expect(finished.message.reasoning == nil)
        }

        @Test func distinctThinkingDeltasKeptWithoutStructured() async throws {
            // Forward-compat, pinned as a test: the day upstream streams REAL
            // reasoning deltas, they differ from the answer and are adopted
            // with zero further app changes.
            let body = Self.sse([
                (event: "run.started", data: #"{"run_id":"r1"}"#),
                (event: "tool.progress", data: #"{"tool_name":"_thinking","delta":"Check the docs first."}"#),
                (event: "tool.progress", data: #"{"tool_name":"_thinking","delta":" Then compare versions."}"#),
                (event: "assistant.delta", data: #"{"delta":"The answer."}"#),
                (event: "assistant.completed", data: #"{"content":"The answer."}"#),
                (event: "run.completed", data: #"{"completed":true}"#),
                (event: "done", data: #"{}"#),
            ])
            let finished = try #require(await streamTurn(sseBody: body))
            #expect(finished.message.reasoning == "Check the docs first. Then compare versions.")
        }

        @Test func streamEndFallbackDropsMirrorKeepsDistinct() async throws {
            // No run.completed at all — the fallback message applies the same
            // mirror guard (step 1 is skipped by construction).
            let mirror = Self.sse(Self.turnPrefix(thinkingMirror: true))
            let mirrorFinished = try #require(await streamTurn(sseBody: mirror))
            #expect(mirrorFinished.message.reasoning == nil)

            let distinct = Self.sse([
                (event: "run.started", data: #"{"run_id":"r1"}"#),
                (event: "tool.progress", data: #"{"tool_name":"_thinking","delta":"Genuine thought."}"#),
                (event: "assistant.delta", data: #"{"delta":"The answer."}"#),
                (event: "assistant.completed", data: #"{"content":"The answer."}"#),
            ])
            let distinctFinished = try #require(await streamTurn(sseBody: distinct))
            #expect(distinctFinished.message.reasoning == "Genuine thought.")
        }
    }
}
