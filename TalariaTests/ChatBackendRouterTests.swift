import Foundation
import Testing
@testable import Talaria

/// #27 — routing rules, per-conversation preference persistence, and
/// producing-brain tagging. Backends are stubs; the real clients' behavior is
/// covered by their own tests and device verification.
@MainActor
struct ChatBackendRouterTests {

    /// Minimal controllable backend: records sends, emits one scripted
    /// finished message.
    @MainActor
    final class StubBackend: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .disconnected
        var currentConversation: Conversation?
        var sentMessages: [String] = []
        var replyContent: String

        init(replyContent: String) {
            self.replyContent = replyContent
        }

        func connect() async { connectionStatus = .connected }
        func disconnect() async { connectionStatus = .disconnected }

        func send(message: String, attachments: [PendingAttachment], clientMessageID: UUID) async -> Message {
            sentMessages.append(message)
            return Message(sender: .hermes, content: replyContent, status: .delivered)
        }

        func sendStreaming(message: String, attachments: [PendingAttachment], clientMessageID: UUID) -> AsyncStream<StreamingUpdate> {
            sentMessages.append(message)
            let content = replyContent
            return AsyncStream { continuation in
                continuation.yield(.textDelta(content))
                continuation.yield(.finished(
                    Message(sender: .hermes, content: content, status: .delivered),
                    TokenUsage(promptTokens: 10, completionTokens: 5, totalTokens: 15),
                    nil
                ))
                continuation.finish()
            }
        }

        func loadConversation() async -> Conversation {
            currentConversation ?? Conversation(title: Conversation.defaultTitle)
        }

        func clearConversation() async throws -> Conversation {
            Conversation(title: Conversation.defaultTitle)
        }
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "ChatBackendRouterTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeRouter(
        hermesConfigured: Bool,
        hermes: StubBackend,
        local: StubBackend,
        defaults: UserDefaults? = nil
    ) -> ChatBackendRouter {
        ChatBackendRouter(
            hermes: hermes,
            local: local,
            isHermesConfigured: { hermesConfigured },
            hasHermesHost: { hermesConfigured },
            defaults: defaults ?? makeDefaults()
        )
    }

    // MARK: Routing rules

    @Test func neverConfiguredDeviceRoutesLocalUnconditionally() {
        let hermes = StubBackend(replyContent: "hermes")
        let local = StubBackend(replyContent: "local")
        hermes.connectionStatus = .connected // even a healthy hermes is ignored
        let router = makeRouter(hermesConfigured: false, hermes: hermes, local: local)
        #expect(router.resolvedBrainForNextTurn() == .onDevice)
        #expect(router.activeBrain == .onDevice)
        #expect(!router.showsBrainPicker)
    }

    @Test func configuredDeviceDefaultsToHermes() {
        let hermes = StubBackend(replyContent: "hermes")
        let local = StubBackend(replyContent: "local")
        let router = makeRouter(hermesConfigured: true, hermes: hermes, local: local)
        #expect(router.resolvedBrainForNextTurn() == .hermes)
        #expect(router.showsBrainPicker)
    }

    @Test func unreachableHermesRoutesNewTurnsLocal() {
        let hermes = StubBackend(replyContent: "hermes")
        let local = StubBackend(replyContent: "local")
        hermes.connectionStatus = .error
        let router = makeRouter(hermesConfigured: true, hermes: hermes, local: local)
        #expect(router.resolvedBrainForNextTurn() == .onDevice)
    }

    @Test func explicitHermesPreferenceFailsHonestlyInsteadOfSwapping() {
        // The user pinned Hermes; a dead gateway must NOT silently reroute —
        // the turn goes to Hermes and fails visibly.
        let hermes = StubBackend(replyContent: "hermes")
        let local = StubBackend(replyContent: "local")
        hermes.connectionStatus = .error
        let router = makeRouter(hermesConfigured: true, hermes: hermes, local: local)
        router.setPreferredBrain(.hermes, forConversation: nil)
        #expect(router.resolvedBrainForNextTurn() == .hermes)
    }

    // MARK: Preference persistence + migration

    @Test func nextConversationPreferenceMigratesOntoFirstConversation() {
        let defaults = makeDefaults()
        let hermes = StubBackend(replyContent: "hermes")
        let local = StubBackend(replyContent: "local")
        let router = makeRouter(hermesConfigured: true, hermes: hermes, local: local, defaults: defaults)

        // Picked before any conversation exists → stored under "next".
        router.setPreferredBrain(.onDevice, forConversation: nil)
        #expect(router.preferredBrain(forConversation: nil) == .onDevice)

        // A conversation appears; resolution migrates "next" onto its id.
        let conversationID = UUID()
        router.conversationIDProvider = { conversationID }
        #expect(router.resolvedBrainForNextTurn() == .onDevice)
        #expect(router.preferredBrain(forConversation: conversationID) == .onDevice)
        #expect(router.preferredBrain(forConversation: nil) == nil)

        // A DIFFERENT conversation is unaffected — per-conversation, not global.
        router.conversationIDProvider = { UUID() }
        #expect(router.resolvedBrainForNextTurn() == .hermes)
    }

    @Test func clearingPreferenceReturnsToAutomaticRouting() {
        let hermes = StubBackend(replyContent: "hermes")
        let local = StubBackend(replyContent: "local")
        let router = makeRouter(hermesConfigured: true, hermes: hermes, local: local)
        let conversationID = UUID()
        router.conversationIDProvider = { conversationID }

        router.setPreferredBrain(.onDevice, forConversation: conversationID)
        #expect(router.resolvedBrainForNextTurn() == .onDevice)

        router.setPreferredBrain(nil, forConversation: conversationID)
        #expect(router.resolvedBrainForNextTurn() == .hermes)
    }

    // MARK: Delegation + tagging

    @Test func streamRunsOnResolvedBackendAndTagsFinishedMessage() async {
        let hermes = StubBackend(replyContent: "from hermes")
        let local = StubBackend(replyContent: "from local")
        let router = makeRouter(hermesConfigured: false, hermes: hermes, local: local)

        var finished: Message?
        var usage: TokenUsage?
        for await update in router.sendStreaming(message: "hi", attachments: [], clientMessageID: UUID()) {
            if case .finished(let message, let tokenUsage, _) = update {
                finished = message
                usage = tokenUsage
            }
        }

        #expect(local.sentMessages == ["hi"])
        #expect(hermes.sentMessages.isEmpty)
        #expect(finished?.content == "from local")
        #expect(finished?.brain == "on-device")
        #expect(usage?.totalTokens == 15) // pass-through, untouched
    }

    @Test func syncSendTagsReplyWithProducingBrain() async {
        let hermes = StubBackend(replyContent: "from hermes")
        let local = StubBackend(replyContent: "from local")
        let router = makeRouter(hermesConfigured: true, hermes: hermes, local: local)

        let reply = await router.send(message: "hello", attachments: [], clientMessageID: UUID())
        #expect(hermes.sentMessages == ["hello"])
        #expect(reply.brain == "hermes")
    }

    // MARK: Transcript tags

    @Test func transcriptTagMarksNonHermesBrainsOnly() {
        #expect(ChatBackendRouter.transcriptTag(forMessageBrain: nil) == nil)
        #expect(ChatBackendRouter.transcriptTag(forMessageBrain: "hermes") == nil)
        #expect(ChatBackendRouter.transcriptTag(forMessageBrain: "on-device") == "ON-DEVICE")
        #expect(ChatBackendRouter.transcriptTag(forMessageBrain: "private-cloud-beta") == "PCC β")
        #expect(ChatBackendRouter.transcriptTag(forMessageBrain: "not-a-brain") == nil)
    }

    @Test func brainRawValuesAreStablePersistedIdentifiers() {
        // Persisted in message caches and preference dictionaries — renaming
        // them would orphan stored data (same rule as the accent slots).
        #expect(ChatBackendRouter.Brain.hermes.rawValue == "hermes")
        #expect(ChatBackendRouter.Brain.onDevice.rawValue == "on-device")
        #expect(ChatBackendRouter.Brain.privateCloud.rawValue == "private-cloud-beta")
    }

    // MARK: Message.brain cache round-trip

    @Test func messageBrainSurvivesCodableRoundTrip() throws {
        let message = Message(sender: .hermes, content: "hi", status: .delivered, brain: "on-device")
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        #expect(decoded.brain == "on-device")

        // Pre-#27 cache rows (no brain key) decode with brain == nil.
        let legacy = Message(sender: .hermes, content: "old", status: .delivered)
        let legacyData = try JSONEncoder().encode(legacy)
        let legacyDecoded = try JSONDecoder().decode(Message.self, from: legacyData)
        #expect(legacyDecoded.brain == nil)
    }

    // MARK: Header pill width anchor (#42)

    @Test func widestMonoLabelAnchorsThePillToTheLongestBrainLabel() {
        // The chat header pill sizes itself to this label so it never wraps;
        // a new brain with a longer label must widen the anchor with it.
        let longest = ChatBackendRouter.Brain.allCases
            .map(\.monoLabel)
            .max { $0.count < $1.count }
        #expect(ChatBackendRouter.Brain.widestMonoLabel == longest)
        #expect(ChatBackendRouter.Brain.widestMonoLabel == "ON-DEVICE")
    }
}
