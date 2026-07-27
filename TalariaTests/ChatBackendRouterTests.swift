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
        hermes: any HermesClientProtocol,
        local: any HermesClientProtocol,
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

    // MARK: Sticky mode (#192, decided 2026-07-27)

    @Test func explicitPickIsAStickyModeNewChatsInherit() {
        let hermes = StubBackend(replyContent: "hermes")
        let local = StubBackend(replyContent: "local")
        let router = makeRouter(hermesConfigured: true, hermes: hermes, local: local)

        // Picked before any conversation exists → the sticky default.
        router.setPreferredBrain(.onDevice, forConversation: nil)
        #expect(router.preferredBrain(forConversation: nil) == .onDevice)

        // A conversation appears; it inherits the sticky default.
        let conversationID = UUID()
        router.conversationIDProvider = { conversationID }
        #expect(router.resolvedBrainForNextTurn() == .onDevice)

        // #192: an id rotation (New chat / clear / openSession) must NOT
        // revert the brain — this exact fall-through to "Hermes wins on a
        // paired device" was the silent self-switch.
        router.conversationIDProvider = { UUID() }
        #expect(router.resolvedBrainForNextTurn() == .onDevice)
        router.refreshActiveBrain()
        #expect(router.activeBrain == .onDevice)
    }

    @Test func perConversationOverrideLayersOnTopOfStickyDefault() {
        let hermes = StubBackend(replyContent: "hermes")
        let local = StubBackend(replyContent: "local")
        let router = makeRouter(hermesConfigured: true, hermes: hermes, local: local)
        let conversationA = UUID()
        let conversationB = UUID()
        var current = conversationA
        router.conversationIDProvider = { current }

        // Pick on-device in A, then Hermes in B: B's pick is the new
        // app-wide default, but A keeps its own override on top.
        router.setPreferredBrain(.onDevice, forConversation: conversationA)
        current = conversationB
        router.setPreferredBrain(.hermes, forConversation: conversationB)
        #expect(router.resolvedBrainForNextTurn() == .hermes)

        current = conversationA
        #expect(router.resolvedBrainForNextTurn() == .onDevice)

        // A NEW chat inherits the LAST explicit pick.
        current = UUID()
        #expect(router.resolvedBrainForNextTurn() == .hermes)
    }

    @Test func pickOnlyOverrideLeavesTheStickyDefaultAlone() {
        // The #30 escalation offer and the #134 debug harness pin a single
        // conversation — the app-wide mode must not move with them.
        let hermes = StubBackend(replyContent: "hermes")
        let local = StubBackend(replyContent: "local")
        let router = makeRouter(hermesConfigured: true, hermes: hermes, local: local)
        let conversationID = UUID()
        router.conversationIDProvider = { conversationID }

        router.setPreferredBrain(.hermes, forConversation: nil)
        router.setPreferredBrain(.onDevice, forConversation: conversationID, updatesDefault: false)
        #expect(router.resolvedBrainForNextTurn() == .onDevice)

        router.conversationIDProvider = { UUID() }
        #expect(router.resolvedBrainForNextTurn() == .hermes)
    }

    @Test func legacyNextSlotStillMigratesOntoFirstConversation() {
        // A pre-#192 pick stored under "next" is never stranded: it migrates
        // onto the first conversation that resolves, exactly as before.
        let defaults = makeDefaults()
        defaults.set(
            [ChatBackendRouter.nextConversationKey: ChatBackendRouter.Brain.onDevice.rawValue],
            forKey: ChatBackendRouter.preferencesDefaultsKey
        )
        let hermes = StubBackend(replyContent: "hermes")
        let local = StubBackend(replyContent: "local")
        let router = makeRouter(hermesConfigured: true, hermes: hermes, local: local, defaults: defaults)

        let conversationID = UUID()
        router.conversationIDProvider = { conversationID }
        #expect(router.resolvedBrainForNextTurn() == .onDevice)
        #expect(router.preferredBrain(forConversation: conversationID) == .onDevice)

        let stored = defaults.dictionary(forKey: ChatBackendRouter.preferencesDefaultsKey) as? [String: String]
        #expect(stored?[ChatBackendRouter.nextConversationKey] == nil)
    }

    @Test func legacyPerConversationPicksSurviveAsOverrides() {
        // Pre-#192 per-conversation rows keep working as overrides; with no
        // sticky default stored, other conversations stay automatic.
        let defaults = makeDefaults()
        let conversationID = UUID()
        defaults.set(
            [conversationID.uuidString: ChatBackendRouter.Brain.onDevice.rawValue],
            forKey: ChatBackendRouter.preferencesDefaultsKey
        )
        let hermes = StubBackend(replyContent: "hermes")
        let local = StubBackend(replyContent: "local")
        let router = makeRouter(hermesConfigured: true, hermes: hermes, local: local, defaults: defaults)

        router.conversationIDProvider = { conversationID }
        #expect(router.resolvedBrainForNextTurn() == .onDevice)

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

        // "Automatic" cleared the sticky default too — new chats route
        // automatically again.
        router.conversationIDProvider = { UUID() }
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

    // MARK: #192 — the wedge, synthetically

    /// A backend whose stream yields one delta and then NEVER finishes —
    /// the #145/#184 dropped-run shape that left `runningBrain` set for the
    /// life of the process and wedged the brain toggle until force quit.
    @MainActor
    final class NeverFinishingBackend: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .connected
        var currentConversation: Conversation?

        func connect() async {}
        func disconnect() async {}

        func send(message: String, attachments: [PendingAttachment], clientMessageID: UUID) async -> Message {
            Message(sender: .hermes, content: "never", status: .delivered)
        }

        func sendStreaming(message: String, attachments: [PendingAttachment], clientMessageID: UUID) -> AsyncStream<StreamingUpdate> {
            AsyncStream { continuation in
                continuation.yield(.textDelta("stuck"))
                // Deliberately never finished — the dropped-run shape.
            }
        }

        func loadConversation() async -> Conversation {
            Conversation(title: Conversation.defaultTitle)
        }

        func clearConversation() async throws -> Conversation {
            Conversation(title: Conversation.defaultTitle)
        }
    }

    @Test func wedgedRunRefusesSwitchUntilAbandonedThenRecovers() async {
        let hermes = NeverFinishingBackend()
        let local = StubBackend(replyContent: "local")
        let router = makeRouter(hermesConfigured: true, hermes: hermes, local: local)
        #expect(router.resolvedBrainForNextTurn() == .hermes)

        // A run starts and its stream never finishes.
        let stream = router.sendStreaming(message: "hi", attachments: [], clientMessageID: UUID())
        let consumer = Task { @MainActor in
            for await _ in stream {}
        }
        #expect(router.activeBrain == .hermes)

        // The user picks on-device. The pick PERSISTS, but re-derivation is
        // refused while the wedged run holds the routing lock — the observed
        // "switch doesn't take" residue, created on demand.
        router.setPreferredBrain(.onDevice, forConversation: nil)
        #expect(router.preferredBrain(forConversation: nil) == .onDevice)
        #expect(router.activeBrain == .hermes)
        router.refreshActiveBrain()
        #expect(router.activeBrain == .hermes)

        // #184's teardown primitive abandons the run → routing re-derives
        // immediately. No force quit.
        router.abandonActiveRun()
        #expect(router.activeBrain == .onDevice)
        #expect(router.resolvedBrainForNextTurn() == .onDevice)

        consumer.cancel()
        _ = await consumer.value
    }

    @Test func consumerWalkAwayAloneReleasesTheRoutingLock() async {
        // Defense in depth: even WITHOUT the explicit `abandonActiveRun`
        // call, the consumer cancelling its iteration (what ChatStore's
        // `streamingTask.cancel()` does) terminates the stream and must
        // release the routing lock.
        let hermes = NeverFinishingBackend()
        let local = StubBackend(replyContent: "local")
        let router = makeRouter(hermesConfigured: true, hermes: hermes, local: local)

        let stream = router.sendStreaming(message: "hi", attachments: [], clientMessageID: UUID())
        let consumer = Task { @MainActor in
            for await _ in stream {}
        }
        router.setPreferredBrain(.onDevice, forConversation: nil)
        #expect(router.activeBrain == .hermes) // wedged while the run holds the lock

        consumer.cancel()
        _ = await consumer.value

        // The release hops through onTermination → the pump's MainActor
        // exit; give it a bounded number of scheduler turns, not wall-clock.
        for _ in 0..<200 where router.activeBrain != .onDevice {
            await Task.yield()
        }
        #expect(router.activeBrain == .onDevice)
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
