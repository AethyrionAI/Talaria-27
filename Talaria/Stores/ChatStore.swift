import Foundation
import UIKit
import os

private let chatLog = Logger(subsystem: "org.aethyrion.talaria", category: "ChatStore")

/// #21 Tier 2: transient per-attachment download state for fetchable agent
/// files. Absence from the map means idle (tap to download); staged-ness
/// itself is derived from the attachment's `localStoragePath`, never tracked
/// here.
enum AgentFileDownloadState: Equatable {
    case downloading
    case failed(String)
}

@MainActor
@Observable
final class ChatStore {
    var conversation: Conversation?
    var isLoading = false
    var pendingMessageSentAt: Date?
    var lastTokenUsage: TokenUsage?

    /// #48: payload from a `hermes://ask?q=…` deep link, held until ChatScreen
    /// pulls it into the composer. Seed-only by design — a custom-scheme URL
    /// can be fired by any app or web page, so it must never auto-send.
    private(set) var pendingComposerSeed: String?

    func seedComposer(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingComposerSeed = trimmed
    }

    func consumeComposerSeed() -> String? {
        defer { pendingComposerSeed = nil }
        return pendingComposerSeed
    }

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

    /// #46: session running totals over every metered Hermes turn. Input
    /// tokens sum across turns on purpose — each turn re-reads the context,
    /// so the sum is the billed amount, not the context size. Nil until at
    /// least one turn carries a receipt.
    /// P1 (#90): context-transplant priming accumulates SEPARATELY from
    /// metered chat turns — priming is real spend the user should see, but it
    /// isn't a conversation turn.
    struct SessionUsageTotals: Hashable {
        var promptTokens = 0
        var completionTokens = 0
        var totalTokens = 0
        var meteredTurns = 0
        var totalDuration: TimeInterval = 0
        var primingTokens = 0
        var primingHops = 0
    }

    var sessionUsageTotals: SessionUsageTotals? {
        guard let messages = conversation?.messages else { return nil }
        var totals = SessionUsageTotals()
        for message in messages {
            if message.isContextPriming {
                // A hop demonstrably happened even when its run reported no
                // usage — the count stays honest independent of the tokens.
                totals.primingHops += 1
                totals.primingTokens += message.usage?.totalTokens ?? 0
                continue
            }
            guard message.sender == .hermes, let usage = message.usage else { continue }
            totals.promptTokens += usage.promptTokens
            totals.completionTokens += usage.completionTokens
            totals.totalTokens += usage.totalTokens
            totals.meteredTurns += 1
            totals.totalDuration += message.turnDuration ?? 0
        }
        return (totals.meteredTurns > 0 || totals.primingHops > 0) ? totals : nil
    }

    private let hermesClient: any HermesClientProtocol
    private let chatLiveActivity = LiveActivityService()
    private let notifications = LocalNotificationService()
    let persistence: any AppPersistenceStoreProtocol

    /// P1 (#90): the durable journal — the conversation's primary on-device
    /// record, shared with `SessionsHermesClient` (which reads the hop handle
    /// at send time). ChatStore re-syncs it at every point the settled
    /// transcript changes. Nil in tests that don't exercise continuity.
    let journal: ConversationJournalStore?

    /// Lane J (J-8): the store-level conversation selection — the API session
    /// handle of the journal's active hop. Rows write selection via
    /// `openSession(_:)` and the detail renders `conversation`, so no
    /// view-local selection exists to desync the split-view columns. NOTE:
    /// the sidebar's row highlight deliberately stays server-sourced
    /// (`HermesSessionInfo.isActive`, refreshed after each switch) for Lane F
    /// parity — this observable surface is the local truth for anything that
    /// needs selection without a fetch.
    var activeSessionID: String? { journal?.activeHop?.apiSessionId }

    /// P1 offline compose outbox (#90): turns composed while the Sessions API
    /// is unreachable park here (the SensorUploadService pattern) and drain
    /// oldest-first once it's reachable again.
    private var composeOutbox: ComposeOutboxState
    private var isDrainingComposeOutbox = false
    /// Set when the in-flight send just re-queued its turn (still
    /// unreachable) — tells the drain loop to stop instead of spinning.
    private var didQueueComposeTurnDuringSend = false
    /// The outbox id the in-flight send just queued under — lets the drain
    /// restore a re-queued turn to the FRONT by identity, not by text match.
    private var lastQueuedComposeTurnID: UUID?

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

    /// #21 Tier 2: downloads a fetchable agent file — (birth profile id,
    /// route-form remote path) → a local temp URL. Wired by AppContainer to
    /// the per-profile relay factory (Lane M: the file lives on the
    /// announcing session's birth-profile relay, never a global base URL).
    /// Nil in tests and unwired constructions — the tap then fails honestly.
    var agentFileDownloader: (@MainActor (UUID?, String) async throws -> URL)?

    /// #21 Tier 2: in-flight/failed download state per attachment id, driving
    /// the fetchable bubble's spinner and honest-failure row.
    private(set) var agentFileDownloads: [UUID: AgentFileDownloadState] = [:]

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

    /// Session id of the run awaiting reconcile, if any — what the relay's
    /// completion watcher needs to be told about (#38).
    var pendingRunSessionId: String? { pendingRun?.sessionId }

    /// Called when conversation content changes (new message, streaming complete).
    /// Used by AppContainer to push widget data updates.
    var onConversationChanged: (@MainActor () -> Void)?

    /// #17: fired with the fresh session list whenever it's fetched — wired by
    /// AppContainer to Spotlight donation (gated there). Stays nil in tests.
    var onSessionsLoaded: (@MainActor ([HermesSessionInfo]) -> Void)?
    /// A run detached while the app was leaving the foreground — the in-app
    /// reconcile loop can't tick once suspended, so AppContainer hands the
    /// completion notify to the relay's APNs watcher (#38).
    var onRunDetached: (@MainActor (String) -> Void)?

    /// A previously detached run was reconciled in-app; AppContainer
    /// withdraws the relay watch so no stale push arrives.
    var onRunResolved: (@MainActor (String) -> Void)?

    /// A send reached a terminal failure the user will see (stream error
    /// before job acceptance, or polling exhaustion). Wired by AppContainer
    /// to the error haptic. Deliberately NOT fired by the cold-load cache
    /// finalization (#56) — that's bookkeeping for an old failure, and a
    /// buzz at launch would have no visible cause.
    var onSendFailed: (@MainActor () -> Void)?

    init(
        hermesClient: any HermesClientProtocol,
        persistence: any AppPersistenceStoreProtocol,
        journal: ConversationJournalStore? = nil
    ) {
        self.hermesClient = hermesClient
        self.persistence = persistence
        self.journal = journal
        self.composeOutbox = persistence.loadComposeOutboxState()
    }

    func loadConversationIfNeeded() async {
        if conversation == nil {
            conversation = persistence.loadConversationCache()
            if let cachedUsage = conversation?.latestUsage {
                lastTokenUsage = cachedUsage
            }
            finalizeStaleSendsFromCache()
        }
        if conversation != nil {
            // P1 (#90): align the journal with the restored thread. A cache
            // that predates the journal (id mismatch) rebuilds it with no hop
            // — the next Hermes turn hops fresh and transplants.
            if let conversation {
                journal?.sync(with: conversation)
            }
            // Queued offline turns drain as soon as there's a thread to
            // drain into; still-unreachable sends just re-queue.
            Task { [weak self] in await self?.drainComposeOutboxIfPossible() }
            return
        }
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

        // #90: a `.queued` row whose compose-outbox entry vanished (cleared
        // state, decode failure) can never drain — flip it to .failed so it
        // gets the retry affordance instead of pending forever. Rows WITH an
        // entry stay queued by design: they survive relaunch and drain on
        // reachability.
        let queuedTurnIDs = Set(composeOutbox.pendingTurns.map(\.id))
        for i in conv.messages.indices
        where conv.messages[i].sender == .user
            && conv.messages[i].status == .queued
            && !queuedTurnIDs.contains(conv.messages[i].clientMessageID ?? conv.messages[i].id) {
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
            journal?.sync(with: conversation)
        }
        restartPendingPollingIfNeeded()
    }

    /// Returns whether the turn actually dispatched — false when a guard
    /// swallowed it (empty content, duplicate of a pending row). The compose
    /// outbox drain needs the distinction: a swallowed turn produced no
    /// stream, so neither success nor a re-queue happened (#90).
    @discardableResult
    func sendMessage(_ content: String, attachments: [PendingAttachment] = []) async -> Bool {
        // Reset FIRST, before any guard: the drain reads this after every
        // send, and a stale true from the previous send would corrupt its
        // stop/continue decision.
        didQueueComposeTurnDuringSend = false
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty || !attachments.isEmpty else { return false }
        guard hasPendingDuplicateMessage(trimmedContent, attachments: attachments) == false else { return false }

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

        // #14: attachment sends are the deliberately-backgroundable long path —
        // wrap them in a continued-processing task (submitted here, in the
        // foreground, from the user's explicit send). Plain text turns stay
        // lightweight. On system revocation the stream would die on suspension
        // anyway, so expiration finalizes partial content via cancelStreaming.
        let continuedSend = attachments.isEmpty ? nil : beginContinuedSend?(displayContent)
        continuedSend?.onExpiration = { [weak self] in self?.cancelStreaming() }

        // #31 contextual priming: the notification prompt rides the first
        // LONG-RUN — a send that can outlive the foreground and want a
        // completion notify — not the first message ever sent.
        if continuedSend != nil {
            Task { await self.notifications.requestAuthorizationIfNeeded() }
        }

        let stream = hermesClient.sendStreaming(message: trimmedContent, attachments: attachments, clientMessageID: clientMessageID)
        var acceptedJobID: UUID?
        var needsPollingFallback = false
        // P1 (#90): whether the settled exchange rode the active Hermes hop —
        // drives the journal's hop-waterline bump after the stream ends.
        var finishedViaHermesHop = false

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

                case .contextPrimed(let usage):
                    // P1 (#90): a fresh server session was just primed with
                    // condensed journal context, before this turn was posted.
                    // Surface the hop honestly in the transcript; the notice
                    // carries the priming turn's real cost so the session
                    // totals add up (priming is not free).
                    let notice = self.makePrimingNotice(usage: usage)
                    if var conv = self.conversation,
                       let idx = conv.messages.firstIndex(where: { $0.id == placeholderID }) {
                        conv.messages.insert(notice, at: idx)
                        self.conversation = conv
                    } else {
                        self.conversation?.messages.append(notice)
                    }
                    continuedSend?.tick()

                case .finished(let finalMessage, let usage, let diff):
                    finishedViaHermesHop = finalMessage.sender == .hermes
                        && (finalMessage.brain == nil || finalMessage.brain == ChatBackendRouter.Brain.hermes.rawValue)
                    if let idx = self.conversation?.messages.firstIndex(where: { $0.id == placeholderID }) {
                        let activities = self.conversation?.messages[idx].toolActivities ?? []
                        let streamedReasoning = self.conversation?.messages[idx].reasoning
                        var resolved = finalMessage
                        resolved.toolActivities = activities
                        resolved.codeDiff = diff
                        // #4.15: keep the accumulated reasoning when the final
                        // message doesn't carry its own (relay/mock clients) —
                        // unless it just mirrors the answer (#60: the defective
                        // `_thinking` channel echoes the answer verbatim; the
                        // client refused to attach it, so the placeholder's
                        // copy must not resurrect it here).
                        if resolved.reasoning == nil,
                           let streamed = streamedReasoning, !streamed.isEmpty,
                           !SessionsHermesClient.reasoningMirrorsAnswer(streamed, content: resolved.content) {
                            resolved.reasoning = streamed
                        }
                        // #46: the turn receipt. Usage rode this run's
                        // `run.completed` (or the local brain's session
                        // stats); duration is wall-clock from the optimistic
                        // send; the serving model keys cost estimates.
                        // Previously each turn overwrote the last in
                        // lastTokenUsage and rendered nowhere.
                        if resolved.usage == nil { resolved.usage = usage }
                        if resolved.turnDuration == nil {
                            resolved.turnDuration = self.pendingMessageSentAt.map {
                                Date.now.timeIntervalSince($0)
                            }
                        }
                        // Hermes-brain turns only: `activeModelName` is the
                        // gateway's model, and stamping it on an on-device /
                        // PCC turn (#27 brain tags) would price a free local
                        // turn at the Hermes model's rate.
                        if resolved.servingModel == nil,
                           resolved.brain == nil || resolved.brain == ChatBackendRouter.Brain.hermes.rawValue {
                            resolved.servingModel = self.activeModelName
                        }
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
                    // #110: the finished content lets the service retract the
                    // pending queue when a #102 breaker trip shortened the
                    // reply below what already streamed to the synthesizer.
                    self.speechOutput?.finishStream(
                        messageID: placeholderID,
                        finishedContent: finalMessage.content
                    )
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
                    // #31: this run just went long (finishing server-side
                    // while we may background) — the completion notify needs
                    // authorization. Best-effort: the prompt can only present
                    // while foregrounded; idempotent on the next long run.
                    Task { await self.notifications.requestAuthorizationIfNeeded() }
                    // #14: the continued task's job — keeping the stream alive —
                    // is over; the reconcile loop owns recovery from here. Not a
                    // failure in the system progress UI.
                    continuedSend?.finish(success: true)
                    // Streams overwhelmingly detach because the app left the
                    // foreground (lock/background) — that's the case where only
                    // a remote push can announce completion. A rare in-app
                    // network blip also lands here; the watch is still harmless
                    // (the reconcile loop resolves first and cancels it).
                    if UIApplication.shared.applicationState != .active {
                        self.onRunDetached?(sessionId)
                    }

                case .unreachable(let errorMessage):
                    // P1 offline compose outbox (#90): the turn never reached
                    // the Sessions API at all. Text-only turns park durably
                    // (`.queued`) and auto-send when the API is reachable
                    // again; attachment turns keep the honest .failed
                    // dead-end — they have no durable wire form to park.
                    if let idx = self.conversation?.messages.firstIndex(where: { $0.id == placeholderID }) {
                        self.conversation?.messages.remove(at: idx)
                    }
                    if attachments.isEmpty, !trimmedContent.isEmpty {
                        if let idx = self.conversation?.messages.firstIndex(where: { $0.id == clientMessageID }) {
                            self.conversation?.messages[idx].status = .queued
                        }
                        self.composeOutbox.enqueue(id: clientMessageID, text: trimmedContent)
                        self.persistComposeOutbox()
                        self.didQueueComposeTurnDuringSend = true
                        self.lastQueuedComposeTurnID = clientMessageID
                        chatLog.notice("compose outbox: turn queued while Sessions API unreachable (#90)")
                    } else {
                        if let idx = self.conversation?.messages.firstIndex(where: { $0.id == clientMessageID }) {
                            self.conversation?.messages[idx].status = .failed
                        }
                        self.conversation?.messages.append(
                            Message(sender: .system, content: errorMessage, status: .failed)
                        )
                    }
                    self.streamingMessageID = nil
                    self.pendingMessageSentAt = nil
                    self.chatLiveActivity.endActivity()
                    self.speechOutput?.cancelStream(messageID: placeholderID)
                    continuedSend?.finish(success: false)

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
                        self.onSendFailed?()
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
            // P1 (#90): re-sync the durable journal with the settled
            // transcript. A Hermes-brain finish bumps the hop waterline over
            // the new exchange; local-brain turns leave it behind on purpose
            // — that's what marks the hop stale, so the next Hermes turn
            // starts a fresh, re-transplanted session.
            journal?.sync(with: conversation, lastExchangeViaActiveHop: finishedViaHermesHop)
        }

        finalizeOnDeviceIntelligence()
        return true
    }

    func clearConversation() async throws {
        reconcileTask?.cancel()
        reconcileTask = nil
        if let abandoned = pendingRun {
            onRunResolved?(abandoned.sessionId)
        }
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
        // P1 (#90): the journal resets to the fresh thread's identity (the
        // client already ended its hop). Queued offline turns belonged to the
        // cleared thread — they die with it.
        journal?.sync(with: fresh)
        composeOutbox = ComposeOutboxState()
        persistence.clearComposeOutboxState()
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

    // MARK: - Fetchable agent files (#21 Tier 2)

    /// Tap→download→stage for a fetchable agent-file bubble: pulls the bytes
    /// from the announcing session's birth-profile relay, stages them into
    /// the Attachments dir, and flips the attachment to its staged form —
    /// from then on the bubble behaves exactly like a Tier 1 bubble
    /// (preview sheet + ShareLink). Failures land in `agentFileDownloads`
    /// with an honest message; tapping again retries.
    func fetchAgentFile(_ attachment: MessageAttachment, in message: Message) async {
        guard attachment.localStoragePath == nil,
              let remotePath = attachment.remotePath,
              agentFileDownloads[attachment.id] != .downloading
        else { return }
        guard let downloader = agentFileDownloader else {
            agentFileDownloads[attachment.id] = .failed("Downloads aren't available in this session.")
            return
        }
        agentFileDownloads[attachment.id] = .downloading
        do {
            let temporaryURL = try await downloader(attachment.remoteProfileID, remotePath)
            guard let stagedPath = MessageAttachment.stageFetchedAgentFile(
                from: temporaryURL,
                preferredFileName: attachment.fileName
            ) else {
                agentFileDownloads[attachment.id] = .failed("Couldn't save the downloaded file.")
                return
            }
            if var conv = conversation,
               let messageIdx = conv.messages.firstIndex(where: { $0.id == message.id }),
               let attachmentIdx = conv.messages[messageIdx].attachments.firstIndex(where: { $0.id == attachment.id }) {
                conv.messages[messageIdx].attachments[attachmentIdx] =
                    conv.messages[messageIdx].attachments[attachmentIdx].staged(atLocalPath: stagedPath)
                conversation = conv
                persistence.saveConversationCache(conv)
                onConversationChanged?()
            } else {
                // The transcript moved on mid-download (cleared, switched
                // session) — nothing to attach the bytes to.
                try? FileManager.default.removeItem(atPath: stagedPath)
            }
            agentFileDownloads[attachment.id] = nil
        } catch {
            agentFileDownloads[attachment.id] = .failed(Self.agentFileFailureMessage(for: error))
            chatLog.notice("agent file fetch failed (#21): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Honest, user-facing failure text for a fetch: auth, not-found, and
    /// offline each get a specific line (the acceptance triad); everything
    /// else surfaces its own description.
    nonisolated static func agentFileFailureMessage(for error: Error) -> String {
        if let downloadError = error as? RelayAPIClient.FileDownloadError {
            switch downloadError {
            case .unauthorized:
                return "The relay refused this device's authorization. Re-pair with the host and try again."
            case .notFound:
                return "The file isn't available from the relay — it may have been moved or removed on the host."
            case .failed(let message):
                return message
            }
        }
        if SessionsHermesClient.isUnreachableError(error) {
            return "The relay is unreachable. Check the connection and tap to retry."
        }
        let described = error.localizedDescription
        return described.isEmpty ? "The download failed. Tap to retry." : described
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
            // P1 (#90): voice turns are conversation content — journaled so a
            // transplant carries them. They didn't ride the Hermes hop, so
            // the waterline stays behind and the next Hermes turn re-hops
            // with the voice context transplanted. The explicit context POST
            // below is then mostly redundant on the Sessions path, but it
            // stays: non-hop backends (mock/legacy relay) have no transplant,
            // and double context is harmless where hops exist.
            journal?.sync(with: conversation)
        }

        guard postToHermes else { return }
        let contextTurn = Self.voiceTranscriptTurnText(from: session)
        guard !contextTurn.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            // P1 (#90): the journal sync above just left the hop waterline
            // behind, so this sync send will usually hop — a transplant paid
            // for on a path that yields no stream. Capture the hop identity
            // before/after so the priming still surfaces in the transcript
            // and totals (priming is not free, even here).
            let hopBefore = self.journal?.activeHop?.apiSessionId
            let reply = await self.hermesClient.send(
                message: contextTurn,
                attachments: [],
                clientMessageID: UUID()
            )
            if reply.status == .failed {
                chatLog.notice("voice transcript context turn failed — transcript stays local-only this session")
                return
            }
            if let journal = self.journal,
               let hop = journal.activeHop,
               hop.apiSessionId != hopBefore,
               journal.hasEntries {
                self.appendPrimingNotice(usage: hop.primingUsage)
            }
        }
    }

    /// The context-transplant notice row (#90): honest label + the priming
    /// turn's real usage, marked so the session totals separate priming from
    /// metered chat turns.
    private func makePrimingNotice(usage: TokenUsage?) -> Message {
        let label = usage.map {
            "[Context transplanted into a fresh session — \(TurnReceiptFormat.fullTokenLabel($0.totalTokens)) tokens]"
        } ?? "[Context transplanted into a fresh session]"
        return Message(
            sender: .system,
            content: label,
            status: .delivered,
            usage: usage,
            servingModel: activeModelName,
            isContextPriming: true
        )
    }

    /// Appends the context-transplant notice for a priming that happened on a
    /// non-streaming path (the voice context POST) — the streamed path gets
    /// its notice from `.contextPrimed` instead (#90).
    private func appendPrimingNotice(usage: TokenUsage?) {
        conversation?.messages.append(makePrimingNotice(usage: usage))
        if let conversation {
            persistence.saveConversationCache(conversation)
            onConversationChanged?()
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

    /// Why `/save` can refuse before it even tries to write.
    enum ExportError: LocalizedError {
        case nothingToSave
        case documentsUnavailable

        var errorDescription: String? {
            switch self {
            case .nothingToSave:
                "There's no conversation to save yet."
            case .documentsUnavailable:
                "The Documents folder isn't available on this device."
            }
        }
    }

    /// Writes the current conversation to Documents as JSON and returns the
    /// file URL, throwing on any failure so `/save` reports honestly instead
    /// of claiming success unconditionally.
    @discardableResult
    func exportConversationToFile() throws -> URL {
        guard let conversation else { throw ExportError.nothingToSave }

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

        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw ExportError.documentsUnavailable
        }
        let fileURL = dir.appendingPathComponent(filename)

        let data = try JSONSerialization.data(withJSONObject: exportData, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    func setConversationTitle(_ title: String) {
        conversation?.title = title
        if let conversation {
            persistence.saveConversationCache(conversation)
            onConversationChanged?()
        }
    }

    func retryMessage(_ message: Message) async {
        // A retried turn must not ALSO drain from the compose outbox later —
        // drop any queued copy before re-sending (#90).
        composeOutbox.remove(id: message.clientMessageID ?? message.id)
        persistComposeOutbox()

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

    // MARK: - Per-turn regenerate / edit (#44)

    /// Re-rolls a successful Hermes reply from its context menu: truncates the
    /// transcript from the user turn that produced the reply, then re-sends
    /// that turn through the full pipeline (attachments restored). Like
    /// `/retry` and `/undo`, the truncation is client-side only — the server
    /// session keeps its history and the re-sent turn continues that session.
    /// No-op while a run is streaming (the menu also hides the item).
    func regenerateReply(_ message: Message) async {
        guard !isStreaming,
              let conv = conversation,
              let replyIdx = conv.messages.firstIndex(where: { $0.id == message.id }),
              let userIdx = conv.messages[..<replyIdx].lastIndex(where: { $0.sender == .user })
        else { return }

        let userMessage = conv.messages[userIdx]
        let attachments = userMessage.attachments.compactMap(PendingAttachment.restore)
        let content = normalizedRetryContent(for: userMessage)
        guard !content.isEmpty || !attachments.isEmpty else { return }

        conversation?.messages.removeSubrange(userIdx...)
        // P1 (#90): the journal follows the truncation (waterline clamps; the
        // server session keeps its history — the documented /retry caveat).
        if let conversation { journal?.sync(with: conversation) }
        await sendMessage(content, attachments: attachments)
    }

    /// The pieces a truncated user turn hands back to the composer.
    struct EditableTurn {
        let text: String
        let attachments: [PendingAttachment]
    }

    /// The truncation half of edit-and-resend (#44) — same semantics as
    /// `/undo`, but returning the removed turn's restorable content so the
    /// caller can seed the composer. Nothing is sent here; the user edits and
    /// taps send. Returns nil (and leaves the transcript untouched) while a
    /// run is streaming or for non-user messages.
    func extractTurnForEditing(_ message: Message) -> EditableTurn? {
        guard !isStreaming,
              message.sender == .user,
              let conv = conversation,
              let idx = conv.messages.firstIndex(where: { $0.id == message.id })
        else { return nil }

        let attachments = message.attachments.compactMap(PendingAttachment.restore)
        let text = normalizedRetryContent(for: message)
        conversation?.messages.removeSubrange(idx...)
        if let conversation {
            persistence.saveConversationCache(conversation)
            onConversationChanged?()
            journal?.sync(with: conversation)
        }
        return EditableTurn(text: text, attachments: attachments)
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
        // P1 (#90): reachability is the compose outbox's drain trigger — the
        // chat screen runs this probe on appear and every ~10s.
        if directConnectionStatus == .connected {
            await drainComposeOutboxIfPossible()
        }
    }

    // MARK: - Offline compose outbox (P1 / #90)

    /// Whether any composed turns are parked waiting for reachability.
    var hasQueuedComposeTurns: Bool { !composeOutbox.isEmpty }

    /// Drains queued turns oldest-first through the normal send pipeline
    /// (each drained turn hops/transplants exactly like a live send). The
    /// queued transcript row is replaced by the re-send's fresh optimistic
    /// row. Stops as soon as a send re-queues — still unreachable; the next
    /// reachability signal retries.
    func drainComposeOutboxIfPossible() async {
        guard !isDrainingComposeOutbox, !isStreaming, !composeOutbox.isEmpty else { return }
        isDrainingComposeOutbox = true
        defer { isDrainingComposeOutbox = false }

        while let turn = composeOutbox.pendingTurns.first {
            composeOutbox.remove(id: turn.id)
            persistComposeOutbox()
            if var conv = conversation {
                conv.messages.removeAll { $0.id == turn.id || $0.clientMessageID == turn.id }
                conversation = conv
            }
            let dispatched = await sendMessage(turn.text)
            if !dispatched {
                // Swallowed by a sendMessage guard — in practice the
                // duplicate check, meaning an identical row is already
                // pending in the transcript. Dropping the outbox copy IS the
                // dedupe; the pending row still represents the message.
                chatLog.notice("compose outbox: drained turn duplicated a pending row — dropped (#90)")
                continue
            }
            if didQueueComposeTurnDuringSend {
                // The re-queue appended the turn behind any still-waiting
                // ones — restore it to the front (by identity) so the queue
                // stays FIFO.
                if let requeuedID = lastQueuedComposeTurnID,
                   let idx = composeOutbox.pendingTurns.firstIndex(where: { $0.id == requeuedID }),
                   idx > 0 {
                    let requeued = composeOutbox.pendingTurns.remove(at: idx)
                    composeOutbox.pendingTurns.insert(requeued, at: 0)
                    persistComposeOutbox()
                }
                chatLog.notice("compose outbox: still unreachable — \(self.composeOutbox.pendingTurns.count) turn(s) remain queued (#90)")
                break
            }
        }
    }

    private func persistComposeOutbox() {
        persistence.saveComposeOutboxState(composeOutbox)
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

    /// The most recent successfully fetched session list (#96): the server
    /// half of the in-app conversation search corpus. Search never fetches
    /// per keystroke — it reads this snapshot, which refreshes whenever the
    /// drawer (or any other caller) loads sessions. Kept across a failed
    /// refresh: a stale-but-real list beats an empty one.
    private(set) var lastLoadedSessions: [HermesSessionInfo] = []

    /// Recent sessions from the host. Returns [] when unreachable.
    func loadSessions() async -> [HermesSessionInfo] {
        do {
            let sessions = try await hermesClient.listSessions()
            chatLog.verbose("loadSessions: got \(sessions.count) sessions")
            lastLoadedSessions = sessions
            onSessionsLoaded?(sessions)
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
            // P1 (#90): the Sessions client already adopted the thread into
            // the journal (identity + current hop); this sync is the no-op
            // alignment for non-hop backends (local brain, mocks).
            journal?.sync(with: convo)
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
        lastLoadedSessions = []
        persistence.clearConversationCache()
        journal?.reset()
        composeOutbox = ComposeOutboxState()
        persistence.clearComposeOutboxState()
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
                && ($0.status == .sending || $0.status == .queued)
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
                self.onSendFailed?()
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
        // #46: receipt for the reconciled turn. Duration comes from two real
        // timestamps (send → reply landing). Usage is adopted only when the
        // reply is the session's last Hermes message — the conversation-level
        // `latestUsage` then belongs to this run; anything else would be a
        // guess.
        if var conv = conversation,
           let idx = conv.messages.firstIndex(where: { $0.id == reply.id }) {
            if conv.messages[idx].turnDuration == nil {
                conv.messages[idx].turnDuration = reply.timestamp.timeIntervalSince(pending.sentAt)
            }
            if conv.messages[idx].usage == nil,
               serverConvo.messages.last(where: { $0.sender == .hermes })?.id == reply.id {
                conv.messages[idx].usage = serverConvo.latestUsage
            }
            if conv.messages[idx].servingModel == nil {
                conv.messages[idx].servingModel = activeModelName
            }
            conversation = conv
        }
        if let latestUsage = conversation?.latestUsage {
            lastTokenUsage = latestUsage
        }
        pendingRun = nil
        pendingMessageSentAt = nil
        onRunResolved?(pending.sessionId)
        if let conversation {
            persistence.saveConversationCache(conversation)
            onConversationChanged?()
            // P1 (#90): the reconciled exchange ran on the active hop's
            // server session — journal it and bump the waterline.
            journal?.sync(with: conversation, lastExchangeViaActiveHop: true)
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

            // Turn receipts are client-only too (#46) — the server transcript
            // carries no per-message usage, duration, or serving model.
            if refreshedConversation.messages[index].usage == nil, let usage = local.usage {
                refreshedConversation.messages[index].usage = usage
            }
            if refreshedConversation.messages[index].turnDuration == nil, let duration = local.turnDuration {
                refreshedConversation.messages[index].turnDuration = duration
            }
            if refreshedConversation.messages[index].servingModel == nil, let model = local.servingModel {
                refreshedConversation.messages[index].servingModel = model
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

        // P1 (#90): conversation identity is LOCAL and durable. Refresh
        // sources mint a new Conversation UUID on every fetch; adopting it
        // would churn the thread's identity on each reconcile/poll —
        // resetting the journal (dropping the hop and forcing a spurious
        // re-transplant) and orphaning per-conversation brain pins (#27).
        // The merged thread keeps the local id.
        if refreshedConversation.id != localConversation.id {
            refreshedConversation = Conversation(
                id: localConversation.id,
                title: refreshedConversation.title,
                messages: refreshedConversation.messages,
                lastActivity: refreshedConversation.lastActivity,
                latestUsage: refreshedConversation.latestUsage,
                generatedPreview: refreshedConversation.generatedPreview
            )
        }

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
                voiceMemoAudioPath: match.voiceMemoAudioPath,
                // Client-only (#21 Tier 2): the fetch pointer and its birth
                // profile never round-trip through the server either.
                remotePath: match.remotePath,
                remoteProfileID: match.remoteProfileID
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
