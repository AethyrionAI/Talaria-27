import Foundation
import UIKit
import os

private let chatLog = Logger(subsystem: "org.aethyrion.talaria", category: "ChatStore")

@MainActor
@Observable
final class ChatStore {
    var conversation: Conversation?
    var isLoading = false
    var pendingMessageSentAt: Date?
    var lastTokenUsage: TokenUsage?

    /// Reachability of the Hermes Sessions API itself — the direct connection
    /// (localhost:8642) that actually carries chat, independent of the relay.
    /// The relay is offline by design, so the Chat screen drives its connectivity
    /// UI from this rather than relay-sourced host status (which would otherwise
    /// paint a false "offline" banner). Updated by `refreshDirectHealth()`.
    private(set) var directConnectionStatus: ConnectionStatus = .disconnected
    private var isPollingEnabled = false
    private var pollingTask: Task<Void, Never>?
    private var streamingTask: Task<Void, Never>?
    private(set) var streamingMessageID: UUID?

    var isStreaming: Bool { streamingMessageID != nil }

    /// Dynamic slash command catalog fetched from the connected Hermes host.
    /// Includes gateway commands, installed skills, custom personalities,
    /// and hidden quick-command metadata for manual slash dispatch.
    private(set) var commandCatalog: [SlashCommand] = SlashCommand.allBuiltIn

    /// Active model name from the Hermes agent config (e.g., "gpt-5.4-mini").
    private(set) var activeModelName: String?
    /// Context window size for the active model (e.g., 400000).
    private(set) var contextWindow: Int?

    var currentContextTokens: Int? {
        lastTokenUsage?.promptTokens
    }

    private let hermesClient: any HermesClientProtocol
    private let chatLiveActivity = LiveActivityService()
    private let notifications = LocalNotificationService()
    let persistence: any AppPersistenceStoreProtocol

    /// Read-aloud (#2), wired by AppContainer. When `autoReadAloudEnabled`
    /// returns true, streamed `assistant.delta` chunks are fed to the TTS
    /// sentence buffer as they arrive. Both stay nil in tests.
    var speechOutput: SpeechOutputService?
    var autoReadAloudEnabled: (@MainActor () -> Bool)?

    /// On-device FoundationModels intelligence (#4.8 × #4.15), wired by
    /// AppContainer: conversation title + preview after the first completed
    /// exchange, one-line reasoning condensation. Stays nil in tests.
    var localIntelligence: LocalIntelligenceService?

    /// #14: wraps a deliberately-backgroundable long send (attachments — the
    /// #38 long-send path) in a BGContinuedProcessingTask so iOS shows system
    /// progress and keeps the run alive past app exit. Wired by AppContainer;
    /// stays nil in tests (no BGTaskScheduler in the test host).
    var beginContinuedSend: (@MainActor (String) -> ContinuedProcessingHandle?)?
    private var isGeneratingConversationCard = false

    /// A run whose stream dropped (e.g. backgrounded on lock) but which is still
    /// running server-side. Reconciled via the Sessions messages endpoint when it
    /// completes. `sentAt` is captured here so reconcile is insulated from the
    /// relay-poll machinery that owns `pendingMessageSentAt`.
    private struct PendingRun {
        let sessionId: String
        let runId: String?
        let userMessageID: UUID
        let sentAt: Date
        /// Reasoning streamed before the drop (#4.15). The server transcript
        /// filters `_thinking`, so this local copy is the only survivor —
        /// re-attached to the reply when reconcile adopts it.
        let partialReasoning: String?
    }
    private var pendingRun: PendingRun?
    private var reconcileTask: Task<Void, Never>?

    /// Called when conversation content changes (new message, streaming complete).
    /// Used by AppContainer to push widget data updates.
    var onConversationChanged: (@MainActor () -> Void)?

    init(hermesClient: any HermesClientProtocol, persistence: any AppPersistenceStoreProtocol) {
        self.hermesClient = hermesClient
        self.persistence = persistence
    }

    func loadConversationIfNeeded() async {
        if conversation == nil {
            conversation = persistence.loadConversationCache()
            if let cachedUsage = conversation?.latestUsage {
                lastTokenUsage = cachedUsage
            }
            finalizeStaleSendsFromCache()
        }
        guard conversation == nil else { return }
        await loadConversation()
    }

    /// Cache hygiene on cold load (#56). A user message still `.sending` in a
    /// freshly loaded cache belongs to a process that died mid-stream — no
    /// stream survives a relaunch, so that state can never resolve; flip it to
    /// `.failed` (the same terminal the polling-exhaustion path uses) so it
    /// renders with the retry affordance instead of pending forever. Honest
    /// caveat: the run may in fact have completed server-side (the in-memory
    /// pendingRun/session id don't survive process death), so the sessions
    /// drawer remains the authoritative view and retry is user-mediated, not
    /// automatic. Also scrubs any cached streaming placeholder (empty Hermes
    /// `.sending` row) that a mid-stream save (e.g. relay polling) let slip in.
    private func finalizeStaleSendsFromCache() {
        guard var conv = conversation else { return }
        var didChange = false

        for i in conv.messages.indices
        where conv.messages[i].sender == .user && conv.messages[i].status == .sending {
            conv.messages[i].status = .failed
            didChange = true
        }

        let placeholderCount = conv.messages.count
        conv.messages.removeAll {
            $0.sender == .hermes
                && $0.status == .sending
                && $0.content.isEmpty
                && $0.toolActivities.isEmpty
        }
        didChange = didChange || conv.messages.count != placeholderCount

        guard didChange else { return }
        chatLog.notice("cold load: finalized stale in-flight send state from cache (#56)")
        conversation = conv
        persistence.saveConversationCache(conv)
    }

    func loadConversation() async {
        isLoading = true
        defer { isLoading = false }
        let cachedConversation = conversation ?? persistence.loadConversationCache()
        conversation = mergeConversationMetadata(
            from: cachedConversation,
            into: await hermesClient.loadConversation()
        )
        if let latestUsage = conversation?.latestUsage {
            lastTokenUsage = latestUsage
        }
        if let conversation {
            persistence.saveConversationCache(conversation)
            onConversationChanged?()
        }
        restartPendingPollingIfNeeded()
    }

    func sendMessage(_ content: String, attachments: [PendingAttachment] = []) async {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty || !attachments.isEmpty else { return }
        guard hasPendingDuplicateMessage(trimmedContent, attachments: attachments) == false else { return }

        let clientMessageID = UUID()
        let displayContent = trimmedContent.isEmpty && !attachments.isEmpty
            ? "[\(attachments.count) attachment\(attachments.count == 1 ? "" : "s")]"
            : trimmedContent
        let optimistic = Message(
            id: clientMessageID,
            clientMessageID: clientMessageID,
            sender: .user,
            content: displayContent,
            status: .sending,
            attachments: attachments.map { MessageAttachment(from: $0) }
        )
        if conversation == nil {
            conversation = Conversation(title: Conversation.defaultTitle)
        }
        conversation?.messages.append(optimistic)
        conversation?.lastActivity = optimistic.timestamp
        pendingMessageSentAt = optimistic.timestamp

        // Persist the optimistic turn NOW, before streaming starts — the next
        // save otherwise only happens after the stream ends, so a process
        // death mid-run (Siri background launch reaped past the intent budget
        // (#56), app killed mid-stream) used to lose the sent exchange from
        // the cache entirely. Deliberately saved BEFORE the placeholder below
        // is appended: the placeholder is transient stream UI, and cold load
        // treats a cached one as garbage (see loadConversationIfNeeded).
        if let conversation {
            persistence.saveConversationCache(conversation)
            onConversationChanged?()
        }

        // Append a placeholder Hermes message for streaming content
        let placeholderID = UUID()
        let placeholder = Message(
            id: placeholderID,
            sender: .hermes,
            content: "",
            status: .sending,
            isStreaming: true
        )
        conversation?.messages.append(placeholder)
        streamingMessageID = placeholderID
        restartPendingPollingIfNeeded()

        Task { await self.notifications.requestAuthorizationIfNeeded() }

        // #14: attachment sends are the deliberately-backgroundable long path —
        // wrap them in a continued-processing task (submitted here, in the
        // foreground, from the user's explicit send). Plain text turns stay
        // lightweight. On system revocation the stream would die on suspension
        // anyway, so expiration finalizes partial content via cancelStreaming.
        let continuedSend = attachments.isEmpty ? nil : beginContinuedSend?(displayContent)
        continuedSend?.onExpiration = { [weak self] in self?.cancelStreaming() }

        let stream = hermesClient.sendStreaming(message: trimmedContent, attachments: attachments, clientMessageID: clientMessageID)
        var acceptedJobID: UUID?
        var needsPollingFallback = false

        streamingTask = Task { [weak self] in
            guard let self else { return }
            for await update in stream {
                if Task.isCancelled { break }
                switch update {
                case .messageSent(let jobID):
                    acceptedJobID = jobID
                    continuedSend?.advance(to: .accepted)

                case .textDelta(let delta):
                    if var conv = self.conversation,
                       let idx = conv.messages.firstIndex(where: { $0.id == placeholderID }) {
                        conv.messages[idx].content += delta
                        conv.messages[idx].toolActivity = nil
                        for i in conv.messages[idx].toolActivities.indices {
                            conv.messages[idx].toolActivities[i].isActive = false
                        }
                        self.conversation = conv
                    }
                    if self.autoReadAloudEnabled?() == true {
                        self.speechOutput?.enqueueStreamChunk(delta, messageID: placeholderID)
                    }
                    continuedSend?.advance(to: .streaming)
                    continuedSend?.tick()

                case .reasoningDelta(let delta):
                    continuedSend?.tick()
                    // #4.15: accumulate the `_thinking` channel on the streaming
                    // placeholder — the bubble shows the newest line verbatim
                    // while the model reasons, ahead of any answer text.
                    if var conv = self.conversation,
                       let idx = conv.messages.firstIndex(where: { $0.id == placeholderID }) {
                        conv.messages[idx].reasoning = (conv.messages[idx].reasoning ?? "") + delta
                        self.conversation = conv
                    }

                case .toolActivity(let event):
                    if var conv = self.conversation,
                       let idx = conv.messages.firstIndex(where: { $0.id == placeholderID }) {
                        switch event.phase {
                        case .started:
                            // Tools run serially, so a new start resolves any
                            // still-active predecessor.
                            for i in conv.messages[idx].toolActivities.indices {
                                conv.messages[idx].toolActivities[i].isActive = false
                            }
                            // Anchor at the content streamed so far — this is
                            // what places the chip inline in the transcript (#10).
                            let activity = ToolActivity(
                                label: event.name,
                                detail: event.detail,
                                anchorOffset: conv.messages[idx].content.count
                            )
                            conv.messages[idx].toolActivities.append(activity)
                            conv.messages[idx].toolActivity = event.name
                        case .completed:
                            // tool.completed is usually empty on the wire; when
                            // it does name the tool, resolve its newest chip.
                            if let last = conv.messages[idx].toolActivities.lastIndex(where: {
                                $0.isActive && $0.label == event.name
                            }) {
                                conv.messages[idx].toolActivities[last].isActive = false
                            }
                        }
                        self.conversation = conv
                    }
                    if event.phase == .started {
                        // Show tool progress on Lock Screen / Dynamic Island
                        self.chatLiveActivity.startToolCall(toolName: event.name)
                        self.chatLiveActivity.updateToolProgress(event.name)
                    }
                    continuedSend?.tick()

                case .finished(let finalMessage, let usage, let diff):
                    if let idx = self.conversation?.messages.firstIndex(where: { $0.id == placeholderID }) {
                        let activities = self.conversation?.messages[idx].toolActivities ?? []
                        let streamedReasoning = self.conversation?.messages[idx].reasoning
                        var resolved = finalMessage
                        resolved.toolActivities = activities
                        resolved.codeDiff = diff
                        // #4.15: keep the accumulated reasoning when the final
                        // message doesn't carry its own (relay/mock clients).
                        if resolved.reasoning == nil { resolved.reasoning = streamedReasoning }
                        self.conversation?.messages[idx] = resolved
                    }
                    // The direct stream completed, so this message definitively
                    // succeeded — mark it delivered, recovering even if the relay
                    // polling fallback had already flipped it to .failed.
                    if let idx = self.conversation?.messages.firstIndex(where: { $0.id == clientMessageID }) {
                        if self.conversation?.messages[idx].status != .delivered {
                            self.conversation?.messages[idx].status = .delivered
                        }
                    }
                    self.conversation = self.mergeConversationMetadata(
                        from: self.conversation,
                        into: self.hermesClient.currentConversation
                    )
                    if let latestUsage = self.conversation?.latestUsage {
                        self.lastTokenUsage = latestUsage
                    } else if let usage {
                        self.lastTokenUsage = usage
                    }
                    self.detectModelSwitch(from: finalMessage.content)
                    self.streamingMessageID = nil
                    self.pendingMessageSentAt = nil
                    self.chatLiveActivity.endActivity()
                    self.speechOutput?.finishStream(messageID: placeholderID)
                    continuedSend?.finish(success: true)

                case .interrupted(let sessionId, let runId):
                    // Run committed server-side but the stream dropped (lock /
                    // background). Not a failure: mark the turn working and let the
                    // reconcile loop pick up the reply when it lands.
                    var partialReasoning: String?
                    if let idx = self.conversation?.messages.firstIndex(where: { $0.id == placeholderID }) {
                        partialReasoning = self.conversation?.messages[idx].reasoning
                        self.conversation?.messages.remove(at: idx)
                    }
                    if let idx = self.conversation?.messages.firstIndex(where: { $0.id == clientMessageID }) {
                        self.conversation?.messages[idx].status = .working
                    }
                    self.streamingMessageID = nil
                    self.chatLiveActivity.endActivity()
                    self.speechOutput?.cancelStream(messageID: placeholderID)
                    self.pendingRun = PendingRun(
                        sessionId: sessionId,
                        runId: runId,
                        userMessageID: clientMessageID,
                        sentAt: self.pendingMessageSentAt ?? .now,
                        partialReasoning: partialReasoning
                    )
                    self.startReconcileLoopIfNeeded()
                    // #14: the continued task's job — keeping the stream alive —
                    // is over; the reconcile loop owns recovery from here. Not a
                    // failure in the system progress UI.
                    continuedSend?.finish(success: true)

                case .failed(let errorMessage):
                    if let idx = self.conversation?.messages.firstIndex(where: { $0.id == placeholderID }) {
                        if acceptedJobID == nil {
                            self.conversation?.messages[idx] = Message(
                                sender: .system,
                                content: errorMessage,
                                status: .failed
                            )
                        } else {
                            self.conversation?.messages.remove(at: idx)
                        }
                    }
                    self.streamingMessageID = nil
                    self.chatLiveActivity.endActivity()
                    self.speechOutput?.cancelStream(messageID: placeholderID)
                    if let idx = self.conversation?.messages.firstIndex(where: { $0.id == clientMessageID }) {
                        self.conversation?.messages[idx].status = acceptedJobID == nil ? .failed : .sending
                    }
                    if acceptedJobID != nil {
                        needsPollingFallback = true
                    } else {
                        self.pendingMessageSentAt = nil
                    }
                    continuedSend?.finish(success: false)
                }
            }
        }
        await streamingTask?.value
        streamingTask = nil

        // #14: belt-and-braces — a stream that ended without a terminal case
        // must still complete its continued-processing task (idempotent).
        continuedSend?.finish(success: true)

        // If streaming failed after the job was accepted, immediately refresh once
        // and then fall back to polling only if the server still hasn't delivered.
        if needsPollingFallback {
            let refreshed = await hermesClient.loadConversation()
            conversation = mergeConversationMetadata(from: conversation, into: refreshed)
            if let latestUsage = conversation?.latestUsage {
                lastTokenUsage = latestUsage
            }
            streamingMessageID = nil
            restartPendingPollingIfNeeded()
        }

        if !hasPendingMessages {
            pendingMessageSentAt = nil
        }

        if let conversation {
            persistence.saveConversationCache(conversation)
            onConversationChanged?()
        }

        finalizeOnDeviceIntelligence()
    }

    func clearConversation() async throws {
        reconcileTask?.cancel()
        reconcileTask = nil
        pendingRun = nil
        streamingTask?.cancel()
        streamingTask = nil
        streamingMessageID = nil
        chatLiveActivity.endActivity()
        speechOutput?.stop()
        let fresh = try await hermesClient.clearConversation()
        conversation = fresh
        lastTokenUsage = fresh.latestUsage
        pendingMessageSentAt = nil
        persistence.saveConversationCache(fresh)
        onConversationChanged?()
        pollingTask?.cancel()
        pollingTask = nil
    }

    func cancelStreaming() {
        streamingTask?.cancel()
        streamingTask = nil
        chatLiveActivity.endActivity()
        // User asked for silence along with the stop — cut read-aloud too.
        speechOutput?.stop()

        // Finalize current streaming message with content received so far
        if let sid = streamingMessageID,
           var conv = conversation,
           let idx = conv.messages.firstIndex(where: { $0.id == sid }) {
            conv.messages[idx].isStreaming = false
            conv.messages[idx].status = .delivered
            for i in conv.messages[idx].toolActivities.indices {
                conv.messages[idx].toolActivities[i].isActive = false
            }
            conversation = conv
        }
        streamingMessageID = nil
        pendingMessageSentAt = nil

        if let conversation {
            persistence.saveConversationCache(conversation)
            onConversationChanged?()
        }
    }

    // MARK: - Voice transcript hand-off (#1)

    /// Appends a completed voice session to the conversation, composed entirely
    /// on-device from the TalkStore snapshot: the "[Voice session ended]" banner
    /// plus the finalized transcript turns. The old relay inject endpoint is out
    /// of the path — the transcript renders and persists (UserDefaults cache)
    /// even when the relay/host is unreachable.
    ///
    /// When `postToHermes` is true, the transcript is also POSTed to the Sessions
    /// API as a normal text turn so the agent has the voice context for the next
    /// exchange. Best-effort and fire-and-forget: the reply is discarded and a
    /// failure never touches the locally composed messages.
    func appendVoiceTranscript(_ session: CompletedVoiceSession, postToHermes: Bool) {
        let transcriptMessages = Self.voiceTranscriptMessages(from: session)
        guard !transcriptMessages.isEmpty else { return }

        if conversation == nil {
            conversation = Conversation(title: Conversation.defaultTitle)
        }
        conversation?.messages.append(contentsOf: transcriptMessages)
        conversation?.lastActivity = transcriptMessages.last?.timestamp ?? .now
        if let conversation {
            persistence.saveConversationCache(conversation)
            onConversationChanged?()
        }

        guard postToHermes else { return }
        let contextTurn = Self.voiceTranscriptTurnText(from: session)
        guard !contextTurn.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            let reply = await self.hermesClient.send(
                message: contextTurn,
                attachments: [],
                clientMessageID: UUID()
            )
            if reply.status == .failed {
                chatLog.notice("voice transcript context turn failed — transcript stays local-only this session")
            }
        }
    }

    /// Builds the chat messages for a completed voice session: a system banner
    /// (carrying the duration for `VoiceSessionBanner`) followed by one message
    /// per finalized spoken turn (`.voiceUser` / `.voiceHermes`). Partial turns,
    /// empty turns (e.g. image-only frames), and system notices are dropped.
    /// Returns [] when nothing was actually spoken.
    nonisolated static func voiceTranscriptMessages(from session: CompletedVoiceSession) -> [Message] {
        var messages: [Message] = []
        for item in session.transcript where !item.isPartial {
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let sender: MessageSender
            switch item.speaker {
            case .user: sender = .voiceUser
            case .hermes: sender = .voiceHermes
            case .system: continue
            }
            messages.append(Message(sender: sender, content: text, status: .delivered))
        }
        guard !messages.isEmpty else { return [] }
        let banner = Message(
            sender: .system,
            content: "[Voice session ended]",
            status: .delivered,
            voiceSessionDuration: session.duration
        )
        return [banner] + messages
    }

    /// The plain-text turn POSTed to the Sessions API so the agent sees the
    /// voice exchange as context. Empty when the session had no spoken turns.
    nonisolated static func voiceTranscriptTurnText(from session: CompletedVoiceSession) -> String {
        let lines: [String] = session.transcript.compactMap { item in
            guard !item.isPartial, item.speaker != .system else { return nil }
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return "\(item.speaker == .user ? "User" : "Hermes"): \(text)"
        }
        guard !lines.isEmpty else { return "" }
        return """
        [Voice session transcript — shared for context. No reply needed.]
        \(lines.joined(separator: "\n"))
        """
    }

    func exportConversationToFile() {
        guard let conversation else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let filename = "hermes_conversation_\(timestamp).json"

        let exportData: [String: Any] = [
            "title": conversation.title,
            "sessionId": conversation.id.uuidString,
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "messageCount": conversation.messages.count,
            "messages": conversation.messages.map { msg in
                [
                    "role": msg.sender.rawValue,
                    "content": msg.content,
                    "timestamp": ISO8601DateFormatter().string(from: msg.timestamp),
                ] as [String: String]
            },
        ]

        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let fileURL = dir.appendingPathComponent(filename)

        do {
            let data = try JSONSerialization.data(withJSONObject: exportData, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: fileURL)
            // Append a system message confirming the save (caller handles this)
        } catch {
            // Export failed silently — caller can check
        }
    }

    func setConversationTitle(_ title: String) {
        conversation?.title = title
        if let conversation {
            persistence.saveConversationCache(conversation)
            onConversationChanged?()
        }
    }

    func retryMessage(_ message: Message) async {
        // Remove the failed message
        conversation?.messages.removeAll { $0.id == message.id }

        // Determine the user content to retry (attachments can't be recovered from metadata)
        let sourceMessage: Message?
        if message.sender == .user {
            sourceMessage = message
        } else {
            sourceMessage = conversation?.messages.last(where: { $0.sender == .user })
        }

        guard let sourceMessage else { return }
        let attachments = sourceMessage.attachments.compactMap(PendingAttachment.restore)
        let content = normalizedRetryContent(for: sourceMessage)
        guard !content.isEmpty || !attachments.isEmpty else { return }

        await sendMessage(content, attachments: attachments)
    }

    func setPollingEnabled(_ isEnabled: Bool) {
        isPollingEnabled = isEnabled
        if isEnabled {
            restartPendingPollingIfNeeded()
        } else {
            pollingTask?.cancel()
            pollingTask = nil
        }
    }

    // MARK: - Direct Sessions API health

    /// Probes the direct Sessions API (`/v1/models`, via the client's `connect()`)
    /// and records the outcome in `directConnectionStatus`. The probe creates no
    /// chat session and has no side effect beyond the status. While a response is
    /// actively streaming the connection is, by definition, live, so we skip the
    /// probe and report `.connected`.
    func refreshDirectHealth() async {
        guard !isStreaming else {
            directConnectionStatus = .connected
            return
        }
        await hermesClient.connect()
        directConnectionStatus = hermesClient.connectionStatus
    }

    // MARK: - Model controls

    /// Model identifiers exposed by the connected host. Returns [] when the host
    /// is unreachable so callers can fall back to placeholder options.
    func availableModels() async -> [String] {
        (try? await hermesClient.availableModels()) ?? []
    }

    /// Switches the active model. Applies to the NEXT session (the Hermes agent
    /// dispatches `/model` as a command turn), so start a new chat for it to take
    /// effect. Updates the displayed model immediately for toolbar feedback.
    ///
    /// The CTX denominator reconciles against the host's `/model` response
    /// ("Context: N tokens") — Hermes's own number for the switched model. It is
    /// NEVER seeded from the client-side nominal table here; that table stays a
    /// read-time display fallback only (resolvedContextWindow), because its
    /// nominal windows run ~1.4x above Hermes's effective ones (#4).
    @discardableResult
    func selectModel(_ identifier: String) async -> Bool {
        do {
            let responseText = try await hermesClient.switchModel(identifier)
            activeModelName = identifier
            updateContextWindow(
                responseText.flatMap(Self.reportedContextWindow(in:)),
                source: "model-switch response"
            )
            return true
        } catch {
            return false
        }
    }

    // MARK: - Sessions

    /// Recent sessions from the host. Returns [] when unreachable.
    func loadSessions() async -> [HermesSessionInfo] {
        do {
            let sessions = try await hermesClient.listSessions()
            chatLog.verbose("loadSessions: got \(sessions.count) sessions")
            return sessions
        } catch {
            chatLog.error("loadSessions: FAILED — \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Opens an existing session: loads its history and continues that thread.
    func openSession(_ id: String) async {
        chatLog.verbose("openSession: opening '\(id)'")
        streamingTask?.cancel()
        streamingTask = nil
        streamingMessageID = nil
        chatLiveActivity.endActivity()
        pollingTask?.cancel()
        pollingTask = nil
        do {
            let convo = try await hermesClient.openSession(id)
            conversation = convo
            lastTokenUsage = convo.latestUsage
            pendingMessageSentAt = nil
            persistence.saveConversationCache(convo)
            onConversationChanged?()
            chatLog.verbose("openSession: loaded \(convo.messages.count) messages for '\(id)'")
        } catch {
            chatLog.error("openSession: FAILED for '\(id, privacy: .public)' — \(error.localizedDescription, privacy: .public)")
        }
    }

    func replaceCommandCatalog(_ catalog: [SlashCommand], activeModel: String? = nil, contextWindow: Int? = nil) {
        commandCatalog = catalog.isEmpty ? SlashCommand.allBuiltIn : catalog
        if let activeModel { activeModelName = activeModel }
        if let contextWindow { updateContextWindow(contextWindow, source: "command catalog") }
    }

    func resetCommandCatalog() {
        commandCatalog = SlashCommand.allBuiltIn
        activeModelName = nil
        updateContextWindow(nil, source: "catalog reset")
    }

    /// Drops back to the built-in command list WITHOUT discarding the active
    /// model or its Hermes-reported context window. Used when a catalog refresh
    /// merely failed (the relay is offline by design much of the time) — a
    /// transient fetch failure must not demote the CTX denominator from a
    /// Hermes-reported value to the nominal client-side table (#4).
    func restoreBuiltInCatalog() {
        commandCatalog = SlashCommand.allBuiltIn
    }

    func reset() {
        pollingTask?.cancel()
        pollingTask = nil
        isPollingEnabled = false
        resetCommandCatalog()
        conversation = nil
        isLoading = false
        pendingMessageSentAt = nil
        lastTokenUsage = nil
        persistence.clearConversationCache()
    }

    func resolvedContextWindow(fallbackModelName: String?) -> Int? {
        contextWindow ?? Self.inferredContextWindow(for: fallbackModelName)
    }

    private var hasPendingMessages: Bool {
        conversation?.messages.contains(where: { $0.sender == .user && $0.status == .sending }) == true
    }

    private func hasPendingDuplicateMessage(_ content: String, attachments: [PendingAttachment]) -> Bool {
        conversation?.messages.contains(where: {
            $0.sender == .user
                && $0.status == .sending
                && normalizedRetryContent(for: $0) == content
                && attachmentSignature(for: $0.attachments) == attachmentSignature(for: attachments.map { MessageAttachment(from: $0) })
        }) == true
    }

    private static let maxPollAttempts = 30 // 30 × 2s = 60 seconds max

    private func restartPendingPollingIfNeeded() {
        guard isPollingEnabled, hasPendingMessages else {
            pollingTask?.cancel()
            pollingTask = nil
            return
        }

        guard pollingTask == nil else { return }

        pollingTask = Task { [weak self] in
            guard let self else { return }
            var attempts = 0

            while !Task.isCancelled, attempts < Self.maxPollAttempts {
                attempts += 1
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                let fresh = await self.hermesClient.loadConversation()
                self.conversation = self.mergeConversationMetadata(from: self.conversation, into: fresh)
                if let latestUsage = self.conversation?.latestUsage {
                    self.lastTokenUsage = latestUsage
                }
                if let conversation = self.conversation {
                    self.persistence.saveConversationCache(conversation)
                    self.onConversationChanged?()
                }
                if self.hasPendingMessages == false {
                    self.pendingMessageSentAt = nil
                    break
                }
            }

            // If we exhausted attempts, mark stuck messages as failed — but only
            // when no direct stream is still in flight. A tool-heavy turn can run
            // past the 60s poll window, and the stream (not the relay) is the
            // authority on delivery, so we must not preempt it with a false failure.
            if attempts >= Self.maxPollAttempts, self.hasPendingMessages, self.streamingMessageID == nil {
                if var conv = self.conversation {
                    for i in conv.messages.indices where conv.messages[i].sender == .user && conv.messages[i].status == .sending {
                        conv.messages[i].status = .failed
                    }
                    self.conversation = conv
                    self.persistence.saveConversationCache(conv)
                }
                self.pendingMessageSentAt = nil
            }

            if self.pollingTask?.isCancelled == false {
                self.pollingTask = nil
            }
        }
    }

    /// Re-attaches transient streaming artifacts (tool timeline, code diff) onto the
    /// canonical conversation that the relay returned, since the relay knows nothing
    /// about those client-only fields.
    // MARK: - Interrupted-run reconcile (Phase 1)

    /// Called on app foreground to catch a run that finished while the app was
    /// suspended and the in-app loop couldn't tick.
    func reconcilePendingRuns() async {
        guard let pending = pendingRun else { return }
        if await attemptReconcile(pending) == false {
            startReconcileLoopIfNeeded()
        }
    }

    private func startReconcileLoopIfNeeded() {
        guard reconcileTask == nil, pendingRun != nil else { return }
        reconcileTask = Task { [weak self] in
            guard let self else { return }
            var attempts = 0
            let maxAttempts = 60 // 60 x 2s = ~2 min, the background-run ceiling
            while !Task.isCancelled, attempts < maxAttempts {
                attempts += 1
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let pending = self.pendingRun else { break }
                if await self.attemptReconcile(pending) { break }
            }
            self.reconcileTask = nil
        }
    }

    /// One reconcile pass: fetch the server's view of the session; if the
    /// assistant reply landed after the run started, adopt it, notify, and clear
    /// the pending run. Returns true when resolved.
    @discardableResult
    private func attemptReconcile(_ pending: PendingRun) async -> Bool {
        guard let serverConvo = await hermesClient.reconcileFromServer() else { return false }
        let reply = serverConvo.messages.last(where: {
            $0.sender == .hermes
                && $0.timestamp > pending.sentAt
                && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })
        guard let reply else { return false }

        conversation = mergeConversationMetadata(from: conversation, into: serverConvo)
        // #4.15: the server transcript filters `_thinking`, so the reasoning
        // that streamed before the drop survives only in the pending run —
        // re-attach it (partial by definition: the stream died mid-think).
        if let partial = pending.partialReasoning, !partial.isEmpty,
           var conv = conversation,
           let idx = conv.messages.firstIndex(where: { $0.id == reply.id }),
           conv.messages[idx].reasoning == nil {
            conv.messages[idx].reasoning = partial
            conversation = conv
        }
        if let latestUsage = conversation?.latestUsage {
            lastTokenUsage = latestUsage
        }
        pendingRun = nil
        pendingMessageSentAt = nil
        if let conversation {
            persistence.saveConversationCache(conversation)
            onConversationChanged?()
        }
        if UIApplication.shared.applicationState != .active {
            notifications.notifyRunCompleted(preview: reply.content)
        }
        finalizeOnDeviceIntelligence()
        return true
    }

    // MARK: - On-device intelligence (#4.8 × #4.15)

    /// Post-turn on-device work: a real title + preview once the first
    /// exchange completes, and a one-line condensation of any reasoning the
    /// turn streamed. Fire-and-forget; every path is guarded so it can run
    /// after every turn without redoing work. No-op when AppContainer hasn't
    /// wired `localIntelligence` (tests).
    private func finalizeOnDeviceIntelligence() {
        generateConversationCardIfNeeded()
        Task { [weak self] in await self?.condensePendingReasoning() }
    }

    /// Generates the conversation's `{title, preview}` after the first
    /// completed exchange (#4.8). Runs only while the title is still the
    /// placeholder, so a manual `/title` (or an earlier generation) is never
    /// overwritten. When the on-device model is unavailable the service
    /// falls back to truncation internally — the conversation still gets a
    /// real label.
    private func generateConversationCardIfNeeded() {
        guard let intelligence = localIntelligence,
              let conversation,
              conversation.title == Conversation.defaultTitle,
              !isGeneratingConversationCard,
              let firstReply = conversation.messages.first(where: {
                  $0.sender == .hermes
                      && $0.status == .delivered
                      && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              })
        else { return }

        // The user side of the exchange. normalizedRetryContent maps the
        // synthetic "[N attachment(s)]" display placeholder to "" — it's not
        // user words and must never become the title; with it empty, the card
        // (and the truncation fallback) derives everything from the reply.
        let firstUserText = conversation.messages
            .first(where: { $0.sender == .user })
            .map { normalizedRetryContent(for: $0) } ?? ""

        let conversationID = conversation.id
        isGeneratingConversationCard = true
        Task { [weak self] in
            let card = await intelligence.conversationCard(
                userText: firstUserText,
                assistantText: firstReply.content
            )
            guard let self else { return }
            self.isGeneratingConversationCard = false
            // Re-check before writing: the chat may have been cleared or
            // retitled by hand while the model ran.
            guard var conv = self.conversation,
                  conv.id == conversationID,
                  conv.title == Conversation.defaultTitle
            else { return }
            if !card.preview.isEmpty { conv.generatedPreview = card.preview }
            self.conversation = conv
            if !card.title.isEmpty {
                chatLog.notice("on-device conversation card generated (#4.8)")
                self.setConversationTitle(card.title)   // persists + notifies
            } else {
                self.persistence.saveConversationCache(conv)
                self.onConversationChanged?()
            }
        }
    }

    /// Condenses un-summarized reasoning into one line each (#4.15) via the
    /// on-device model — only while foregrounded (background scheduling isn't
    /// worth fighting for; the collapsed row already falls back to the last
    /// raw reasoning line). Newest first, a few per pass: a foreground return
    /// can owe more than one (several turns settled while backgrounded), and
    /// a nil summary ends the pass — model unavailable or a guardrail veto
    /// would otherwise hammer the same input. Also invoked from AppContainer
    /// on foreground so backgrounded turns get their summaries on return.
    func condensePendingReasoning() async {
        for _ in 0 ..< 3 {
            guard let intelligence = localIntelligence,
                  UIApplication.shared.applicationState == .active,
                  let conv = conversation,
                  let index = conv.messages.lastIndex(where: {
                      $0.sender == .hermes
                          && ($0.reasoning?.isEmpty == false)
                          && $0.reasoningSummary == nil
                          && !$0.isStreaming
                  }),
                  let reasoning = conv.messages[index].reasoning
            else { return }

            let messageID = conv.messages[index].id
            guard let summary = await intelligence.condensedReasoning(reasoning) else { return }
            // The conversation may have changed while the model ran — re-find.
            guard var current = conversation,
                  let idx = current.messages.firstIndex(where: { $0.id == messageID })
            else { return }
            current.messages[idx].reasoningSummary = summary
            conversation = current
            persistence.saveConversationCache(current)
            onConversationChanged?()
        }
    }

    private func mergeConversationMetadata(
        from localConversation: Conversation?,
        into refreshedConversation: Conversation?
    ) -> Conversation? {
        guard var refreshedConversation else { return localConversation }
        guard let localConversation else { return refreshedConversation }

        if refreshedConversation.latestUsage == nil {
            refreshedConversation.latestUsage = localConversation.latestUsage
        }

        // Conversation-level metadata is client-local (#4.8): the Sessions
        // client's base conversation only ever carries the placeholder title
        // and no preview, so a merge must not demote the local ones. (Also
        // fixes the long-standing quirk of a manual /title reverting on the
        // next exchange — and without this, the title-generation gate would
        // re-trip and re-run the on-device model every single turn.)
        if refreshedConversation.title == Conversation.defaultTitle,
           localConversation.title != Conversation.defaultTitle {
            refreshedConversation.title = localConversation.title
        }
        if refreshedConversation.generatedPreview == nil {
            refreshedConversation.generatedPreview = localConversation.generatedPreview
        }

        for index in refreshedConversation.messages.indices {
            let remote = refreshedConversation.messages[index]

            // Prefer exact UUID match (works when the relay echoes back the same ID).
            let local: Message?
            if let byID = localConversation.messages.first(where: { $0.id == remote.id }) {
                local = byID
            } else if let remoteClientMessageID = remote.clientMessageID {
                local = localConversation.messages.first(where: {
                    $0.id == remoteClientMessageID || $0.clientMessageID == remoteClientMessageID
                })
            } else if let remoteJobID = remote.jobID {
                // Fallback: the streaming placeholder had a client-generated UUID that
                // differs from the server-assigned message ID.  Match on jobID + sender
                // instead, but only for Hermes messages that actually carry artifacts.
                local = localConversation.messages.first(where: {
                    $0.jobID == remoteJobID
                        && $0.sender == remote.sender
                        && $0.sender == .hermes
                        && (!$0.toolActivities.isEmpty || $0.codeDiff != nil)
                })
            } else {
                local = nil
            }

            guard let local else { continue }

            if !local.toolActivities.isEmpty {
                refreshedConversation.messages[index].toolActivities = local.toolActivities
                refreshedConversation.messages[index].toolActivity = local.toolActivity
            }

            if let diff = local.codeDiff, refreshedConversation.messages[index].codeDiff == nil {
                refreshedConversation.messages[index].codeDiff = diff
            }

            // Reasoning is client-only (#4.15) — the server transcript filters
            // the `_thinking` channel out, so a refresh would otherwise drop it.
            if refreshedConversation.messages[index].reasoning == nil, let reasoning = local.reasoning {
                refreshedConversation.messages[index].reasoning = reasoning
            }
            if refreshedConversation.messages[index].reasoningSummary == nil, let summary = local.reasoningSummary {
                refreshedConversation.messages[index].reasoningSummary = summary
            }

            if !local.attachments.isEmpty {
                refreshedConversation.messages[index].attachments = mergeAttachments(
                    local.attachments,
                    onto: refreshedConversation.messages[index].attachments
                )
            }
        }

        // Preserve any local message the relay hasn't echoed back yet — not just
        // streaming placeholders, but also just-sent user messages still in flight.
        // The relay assigns its own message IDs, so a local message is "confirmed"
        // only if the refreshed conversation contains it by id OR by clientMessageID.
        // Anything unconfirmed must survive the merge, otherwise a sent message
        // vanishes the instant the first poll/refresh returns without it.
        let refreshedIDs = Set(refreshedConversation.messages.map(\.id))
        let refreshedClientIDs = Set(refreshedConversation.messages.compactMap(\.clientMessageID))
        let unconfirmedLocals = localConversation.messages.filter { local in
            if refreshedIDs.contains(local.id) { return false }
            if let clientID = local.clientMessageID, refreshedClientIDs.contains(clientID) { return false }
            return true
        }
        refreshedConversation.messages.append(contentsOf: unconfirmedLocals)

        return refreshedConversation
    }

    private func mergeAttachments(_ localAttachments: [MessageAttachment], onto remoteAttachments: [MessageAttachment]) -> [MessageAttachment] {
        guard !remoteAttachments.isEmpty else { return localAttachments }

        return remoteAttachments.enumerated().map { index, remote in
            let match = localAttachments.first(where: {
                $0.fileName == remote.fileName && $0.mimeType == remote.mimeType
            }) ?? localAttachments[safe: index]
            guard let match else { return remote }
            return MessageAttachment(
                id: remote.id,
                kind: remote.kind,
                fileName: remote.fileName,
                mimeType: remote.mimeType,
                thumbnailBase64: remote.thumbnailBase64 ?? match.thumbnailBase64,
                localStoragePath: match.localStoragePath,
                // Client-only (#9): the server never echoes the audio path;
                // the local copy is the source of truth for playback.
                voiceMemoAudioPath: match.voiceMemoAudioPath
            )
        }
    }

    private func normalizedRetryContent(for message: Message) -> String {
        if !message.attachments.isEmpty,
           message.content.range(of: #"^\[\d+ attachment"#, options: .regularExpression) != nil {
            return ""
        }
        return message.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func attachmentSignature(for attachments: [MessageAttachment]) -> String {
        attachments
            .map { "\($0.kind)|\($0.fileName)|\($0.mimeType)" }
            .sorted()
            .joined(separator: "||")
    }

    // MARK: - Model Switch Detection

    /// Detect a model switch from the agent's response text.
    /// Updates activeModelName and contextWindow immediately so the
    /// toolbar chip reflects the change in the same render frame.
    // Regex for context window in /model response: "Context: 1,000,000 tokens"
    nonisolated(unsafe) private static let contextWindowPattern = /Context:\s*([\d,]+)\s*tokens/

    /// Extracts the Hermes-reported context window from a `/model` response
    /// ("Context: 262,144 tokens"). This is the authoritative denominator
    /// source for the CTX meter (#4). Nil when the response carries none.
    nonisolated static func reportedContextWindow(in text: String) -> Int? {
        guard let match = text.firstMatch(of: contextWindowPattern) else { return nil }
        let raw = String(match.1).replacingOccurrences(of: ",", with: "")
        guard let value = Int(raw), value > 0 else { return nil }
        return value
    }

    /// Single write path for the CTX denominator, logging every change with its
    /// source so a wrong meter reading is a one-line log read (#4 acceptance).
    private func updateContextWindow(_ value: Int?, source: String) {
        guard value != contextWindow else { return }
        contextWindow = value
        if let value {
            chatLog.notice("contextWindow ← \(value) [\(source, privacy: .public)]")
        } else {
            chatLog.notice("contextWindow ← nil [\(source, privacy: .public)] — display falls back to inferred table")
        }
    }

    private func detectModelSwitch(from text: String) {
        // Match: "Model switched to `claude-sonnet-4-6`" or "Model switched: gpt-4-turbo"
        // Model ids can be slashed (e.g. "anthropic/claude-opus-4.8" from the nous
        // portal), so the capture class must include `/`. Inside a `/.../` regex
        // literal the slash is escaped as `\/`. Keep `-` last so it stays literal.
        let patterns: [Regex<(Substring, Substring)>] = [
            /[Mm]odel\s+switched\s+to\s+`?([A-Za-z0-9._\/-]+)`?/,
            /[Mm]odel\s+switched:\s+`?([A-Za-z0-9._\/-]+)`?/,
        ]
        for pattern in patterns {
            if let match = text.firstMatch(of: pattern) {
                let newModel = String(match.1)
                activeModelName = newModel

                // v0.8.0: the /model response includes "Context: N tokens"
                // — parse it directly instead of relying on a heuristic table.
                // If absent, clear and let the next catalog refresh resolve it.
                updateContextWindow(
                    Self.reportedContextWindow(in: text),
                    source: "chat /model response"
                )
                return
            }
        }
    }

    /// Fallback-only lookup for cases where the connector has not yet provided
    /// an explicit context window. This should never overwrite a known value.
    static func inferredContextWindow(for modelName: String?) -> Int? {
        guard let modelName, !modelName.isEmpty else { return nil }
        let n = modelName.lowercased()

        if n.contains("claude-opus-4-6") || n.contains("claude-opus-4.6")
            || n.contains("claude-sonnet-4-6") || n.contains("claude-sonnet-4.6") {
            return 1_000_000
        }
        if n.contains("claude") { return 200_000 }
        if n.contains("gpt-4.1") { return 1_047_576 }
        if n.contains("gpt-5") { return 128_000 }
        if n.contains("gpt-4") { return 128_000 }
        if n.contains("gemini") { return 1_048_576 }
        if n.contains("gemma-4-31b") || n.contains("gemma-4-26b") { return 256_000 }
        if n.contains("gemma-3") { return 131_072 }
        if n.contains("gemma") { return 8_192 }
        if n.contains("deepseek") { return 128_000 }
        if n.contains("llama") { return 131_072 }
        if n.contains("qwen") { return 131_072 }
        if n.contains("minimax") { return 204_800 }
        if n.contains("glm") { return 202_752 }
        if n.contains("kimi") { return 262_144 }
        if n.contains("mimo-v2-pro") || n.contains("mimo-v2-omni") { return 1_048_576 }
        return 128_000
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
