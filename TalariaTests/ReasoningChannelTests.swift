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
}
