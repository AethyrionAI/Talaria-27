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

        @Test func aggregatesReasoningAcrossAssistantEntries() async throws {
            // Wire truth (captured 2026-07-13, terminal-tool turn): on
            // tool-using turns the genuine plan CoT rides the INTERMEDIATE
            // assistant entries; the final entry's reasoning is typically a
            // draft-the-answer compile step. Every segment survives, in
            // transcript order — last-assistant-wins discarded the plan.
            let body = Self.sse(Self.turnPrefix(thinkingMirror: false) + [
                (event: "run.completed",
                 data: #"{"messages":[{"role":"assistant","content":"","reasoning_content":"Plan: check the host clock with the terminal."},{"role":"tool","content":"{\"output\":\"Tue, Jul 14\"}"},{"role":"assistant","content":"The answer.","finish_reason":"stop","reasoning_content":"Compile the final answer."}]}"#),
                (event: "done", data: #"{}"#),
            ])
            let finished = try #require(await streamTurn(sseBody: body))
            #expect(finished.message.reasoning == "Plan: check the host clock with the terminal.\n\nCompile the final answer.")
        }

        @Test func blankEntriesAndNonAssistantRowsNeverContribute() async throws {
            // Blank per-entry reasoning stays absent-equivalent inside the
            // aggregate — no empty segments, no doubled separators — and a
            // reasoning key on a non-assistant row is ignored outright.
            let body = Self.sse(Self.turnPrefix(thinkingMirror: false) + [
                (event: "run.completed",
                 data: #"{"messages":[{"role":"assistant","reasoning_content":"First thought."},{"role":"assistant","reasoning_content":"  \n ","reasoning":""},{"role":"tool","reasoning_content":"tool noise"},{"role":"assistant","reasoning_content":"Second thought."}]}"#),
                (event: "done", data: #"{}"#),
            ])
            let finished = try #require(await streamTurn(sseBody: body))
            #expect(finished.message.reasoning == "First thought.\n\nSecond thought.")
        }

        @Test func perEntryKeyPreferenceHoldsInsideAggregate() async throws {
            // `reasoning_content` over `reasoning` is decided PER ENTRY, not
            // across the transcript: an entry carrying only the fallback key
            // still contributes its text to the aggregate.
            let body = Self.sse(Self.turnPrefix(thinkingMirror: false) + [
                (event: "run.completed",
                 data: #"{"messages":[{"role":"assistant","reasoning":"fallback plan"},{"role":"assistant","reasoning":"stale duplicate","reasoning_content":"canonical compile"}]}"#),
                (event: "done", data: #"{}"#),
            ])
            let finished = try #require(await streamTurn(sseBody: body))
            #expect(finished.message.reasoning == "fallback plan\n\ncanonical compile")
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

        @Test func mirroringAggregateFallsThroughToAssembledDeltas() async throws {
            // 60B: a single-entry transcript whose reasoning just restates
            // the answer (whitespace-folded) counts as absent — the attach
            // falls through to the assembled `_thinking` branch, adopting
            // genuinely distinct deltas...
            let distinct = Self.sse([
                (event: "run.started", data: #"{"run_id":"r1"}"#),
                (event: "tool.progress", data: #"{"tool_name":"_thinking","delta":"Genuine thought."}"#),
                (event: "assistant.delta", data: #"{"delta":"The answer."}"#),
                (event: "assistant.completed", data: #"{"content":"The answer."}"#),
                (event: "run.completed",
                 data: #"{"messages":[{"role":"assistant","content":"The answer.","reasoning_content":"The  answer."}]}"#),
                (event: "done", data: #"{}"#),
            ])
            let distinctFinished = try #require(await streamTurn(sseBody: distinct))
            #expect(distinctFinished.message.reasoning == "Genuine thought.")

            // ...and when the `_thinking` fixture is the mirror too, nothing
            // attaches — no chevron, same as every other mirror path.
            let mirror = Self.sse(Self.turnPrefix(thinkingMirror: true) + [
                (event: "run.completed",
                 data: #"{"messages":[{"role":"assistant","content":"The answer.","reasoning_content":"The answer."}]}"#),
                (event: "done", data: #"{}"#),
            ])
            let mirrorFinished = try #require(await streamTurn(sseBody: mirror))
            #expect(mirrorFinished.message.reasoning == nil)
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

    // MARK: Resume path — reasoning restored from GET /messages (#121)

    /// End-to-end fixtures against the REAL `openSession` decode + map path:
    /// a stubbed URLSession serves the stored-messages endpoint and the mapped
    /// `Conversation.messages` are inspected. `GET .../messages` carries the
    /// same per-row reasoning the live `run.completed` path adopts (#60,
    /// probed 2026-07-16); resume restores the panes without ever reshowing an
    /// answer-mirror. Serialized — the stub protocol's body is class-global.
    @Suite(.serialized)
    struct ResumeReasoningTests {

        private final class MessagesStubProtocol: URLProtocol, @unchecked Sendable {
            nonisolated(unsafe) static var body = ""

            override class func canInit(with request: URLRequest) -> Bool { true }
            override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

            override func startLoading() {
                let url = request.url ?? URL(string: "http://hermes.test")!
                let response = HTTPURLResponse(
                    url: url, statusCode: 200, httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
                client?.urlProtocolDidFinishLoading(self)
            }

            override func stopLoading() {}
        }

        /// Wraps `data` rows in the probed stored-messages envelope.
        private static func messagesBody(_ rows: String) -> String {
            #"{"session_id": "api_sess", "data": [\#(rows)]}"#
        }

        /// Runs one resume (fresh journal — nothing to transplant) against the
        /// scripted stored-messages body and returns the mapped messages.
        @MainActor
        private func resume(rows: String) async throws -> [Message] {
            let suiteName = "resume-reasoning-\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            defaults.removePersistentDomain(forName: suiteName)
            let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)

            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [MessagesStubProtocol.self]
            let session = URLSession(configuration: configuration)
            MessagesStubProtocol.body = Self.messagesBody(rows)
            defer { MessagesStubProtocol.body = "" }

            let client = SessionsHermesClient(
                baseURLProvider: { "http://hermes.test" },
                apiKeyProvider: { "test-key" },
                journal: ConversationJournalStore(persistence: persistence),
                transplanter: ContextTransplanter(intelligence: LocalIntelligenceService()),
                session: session
            )
            return try await client.openSession("api_sess").messages
        }

        @Test @MainActor
        func restoresReasoningContentOnAssistantRow() async throws {
            let messages = try await resume(rows: #"""
            {"role":"user","content":"Ping","timestamp":1752600000.0,"reasoning":null,"reasoning_content":null},
            {"role":"assistant","content":"Pong.","timestamp":1752600005.0,"reasoning":null,"reasoning_content":"Weigh the options, then answer."}
            """#)
            #expect(messages.count == 2)
            let assistant = try #require(messages.last)
            #expect(assistant.content == "Pong.")
            #expect(assistant.reasoning == "Weigh the options, then answer.")
            // The user row never carries reasoning.
            #expect(messages.first?.reasoning == nil)
        }

        @Test @MainActor
        func dropsAnswerMirrorRow() async throws {
            // Both keys restate the answer verbatim — the defective upstream
            // `_thinking` mirror that #60 closed. A restored pane parroting its
            // own answer is the exact regression; nothing attaches.
            let messages = try await resume(rows: #"""
            {"role":"assistant","content":"The answer is 42.","timestamp":1752600005.0,"reasoning":"The answer is 42.","reasoning_content":"The answer is 42."}
            """#)
            let assistant = try #require(messages.first)
            #expect(assistant.content == "The answer is 42.")
            #expect(assistant.reasoning == nil)
        }

        @Test @MainActor
        func dropsWhitespaceFoldedMirror() async throws {
            // The stored reasoning and answer differ only in whitespace runs —
            // the #60 fold treats them as the same text and drops it.
            let messages = try await resume(rows: #"""
            {"role":"assistant","content":"The answer, spread across lines.","timestamp":1752600005.0,"reasoning_content":"The\n\nanswer,  spread\tacross lines."}
            """#)
            #expect(messages.first?.reasoning == nil)
        }

        @Test @MainActor
        func reasoningContentWinsOverReasoning() async throws {
            // Per-row preference: `reasoning_content` matches the live channel.
            let messages = try await resume(rows: #"""
            {"role":"assistant","content":"Answer.","timestamp":1752600005.0,"reasoning":"stale duplicate","reasoning_content":"canonical chain"}
            """#)
            #expect(messages.first?.reasoning == "canonical chain")
        }

        @Test @MainActor
        func fallsBackToReasoningKeyWhenContentBlankAndTrims() async throws {
            // `reasoning_content` null (row 1) or present-but-blank (row 2)
            // falls back to `reasoning`; the chosen value is trimmed.
            let messages = try await resume(rows: #"""
            {"role":"assistant","content":"First.","timestamp":1752600005.0,"reasoning":"  Real chain of thought.\n","reasoning_content":null},
            {"role":"assistant","content":"Second.","timestamp":1752600006.0,"reasoning":"blanked fallback","reasoning_content":"   "}
            """#)
            #expect(messages.count == 2)
            #expect(messages.first?.reasoning == "Real chain of thought.")
            #expect(messages.last?.reasoning == "blanked fallback")
        }

        @Test @MainActor
        func nullAbsentAndTypeMismatchedReasoningNeverThrow() async throws {
            // Real wire: keys present-but-null (row 1), absent entirely
            // (row 2), and a non-string type where a string is expected
            // (row 3 — the tolerant decode must swallow it). None throws; none
            // attaches reasoning; every row still maps.
            let messages = try await resume(rows: #"""
            {"role":"assistant","content":"Null keys.","timestamp":1752600001.0,"reasoning":null,"reasoning_content":null},
            {"role":"assistant","content":"Absent keys.","timestamp":1752600002.0},
            {"role":"assistant","content":"Wrong type.","timestamp":1752600003.0,"reasoning":42,"reasoning_content":{"nested":"object"}}
            """#)
            #expect(messages.count == 3)
            #expect(messages.allSatisfy { $0.reasoning == nil })
            #expect(messages.map(\.content) == ["Null keys.", "Absent keys.", "Wrong type."])
        }

        @Test @MainActor
        func mixedConversationOnlyWithRowsCarryReasoning() async throws {
            let messages = try await resume(rows: #"""
            {"role":"user","content":"Q1","timestamp":1752600000.0},
            {"role":"assistant","content":"A1.","timestamp":1752600001.0,"reasoning_content":"Think about A1."},
            {"role":"user","content":"Q2","timestamp":1752600002.0},
            {"role":"assistant","content":"A2.","timestamp":1752600003.0,"reasoning":null,"reasoning_content":null},
            {"role":"assistant","content":"A3.","timestamp":1752600004.0,"reasoning_content":"Think about A3."}
            """#)
            let assistants = messages.filter { $0.sender == .hermes }
            #expect(assistants.count == 3)
            #expect(assistants[0].reasoning == "Think about A1.")
            #expect(assistants[1].reasoning == nil)
            #expect(assistants[2].reasoning == "Think about A3.")
            #expect(messages.filter { $0.sender == .user }.allSatisfy { $0.reasoning == nil })
        }

        @Test @MainActor
        func userRowReasoningNeverAttaches() async throws {
            // Defensive: even if the API ever stamped reasoning on a user row,
            // the sender gate drops it — reasoning is assistant-only.
            let messages = try await resume(rows: #"""
            {"role":"user","content":"Ping","timestamp":1752600000.0,"reasoning_content":"user rows never reason"}
            """#)
            #expect(messages.first?.sender == .user)
            #expect(messages.first?.reasoning == nil)
        }

        @Test @MainActor
        func toolCallPlannerRowKeepsPlanReasoning() async throws {
            // 60B wire truth: on a tool-using turn the genuine plan CoT rides
            // the tool-call planner row, whose content is empty — distinct from
            // that empty content, so it survives on the chip's message. The
            // final answer row's reasoning near-copies the answer → dropped.
            let messages = try await resume(rows: #"""
            {"role":"assistant","content":"","timestamp":1752600001.0,"tool_calls":[{"name":"terminal"}],"reasoning_content":"Plan: check the host clock with the terminal."},
            {"role":"assistant","content":"The current UTC time is 03:02:46.","timestamp":1752600003.0,"reasoning_content":"The current UTC time is 03:02:46."}
            """#)
            #expect(messages.count == 2)
            let planner = try #require(messages.first)
            #expect(planner.content == "")
            #expect(planner.toolActivities.map(\.label) == ["terminal"])
            #expect(planner.reasoning == "Plan: check the host clock with the terminal.")
            #expect(messages.last?.reasoning == nil)
        }
    }
}
