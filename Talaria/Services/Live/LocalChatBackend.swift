import Foundation
import FoundationModels
import UIKit
import os

/// On-device chat brain (#26): Apple's FoundationModels framework behind the
/// same `HermesClientProtocol` seam as `SessionsHermesClient`, so ChatStore's
/// streaming consumer, read-aloud, persistence, and the sessions drawer work
/// unmodified — with zero desktop setup.
///
/// One `LanguageModelSession` per conversation, created lazily with the
/// assistant persona + current date + device context as instructions and the
/// conversation history replayed as a `Transcript` on restore. The context
/// window is read from the model at RUNTIME (`model.contextSize` — 8192 on
/// iPhone 17 Pro Max / iOS 27, 4096 on 26.0; never hardcoded). When a
/// conversation approaches that budget, older turns are condensed through
/// `LocalIntelligenceService`'s deterministic trimming helpers and the session
/// is recreated as [condensed memory] + recent verbatim turns — overflow
/// degrades to summarized memory, never errors.
///
/// Real-data-only: the backend never fabricates. Model unavailable → honest
/// explanation state; `GenerationError` → plain-language `.failed` reasons;
/// token usage is reported only where the OS actually provides it
/// (`LanguageModelSession.usage`, iOS 27) — never estimated client-side.
@MainActor
@Observable
final class LocalChatBackend: HermesClientProtocol {

    /// Model identifiers exposed by `availableModels()` and accepted by
    /// `switchModel`. PCC appears only when the entitlement + availability
    /// check actually passes (#30) — never assumed.
    static let onDeviceModelID = "on-device"
    static let privateCloudModelID = "private-cloud-beta"

    /// The two tiers the local brain can run (#30). PCC is a MODE of this
    /// backend — one seam, never a third client. On-device is the permanent
    /// free floor; PCC is opportunistic and visibly labeled beta.
    enum LocalModelTier: String, Sendable {
        case onDevice = "on-device"
        case privateCloud = "private-cloud-beta"
    }

    /// `HermesSessionInfo.source` tag for locally-produced conversations, so
    /// the sessions drawer can distinguish the standalone thread from server
    /// history once both exist (#27 transcript honesty).
    static let localSessionSource = "local"

    private static let logger = Logger(subsystem: "org.aethyrion.talaria", category: "LocalChatBackend")

    /// Tokens reserved out of the context window for the model's reply (the
    /// window is shared between input and output).
    static let responseHeadroomTokens = 1024
    /// Per-turn cap when older turns are condensed into memory: enough for the
    /// gist of a turn, small enough that memory never crowds out live context.
    static let condensedPerTurnTokens = 120
    /// Cap on the whole condensed-memory block appended to the instructions.
    static let condensedMemoryTokens = 1024

    var connectionStatus: ConnectionStatus = .disconnected
    var currentConversation: Conversation?

    private var model: SystemLanguageModel { SystemLanguageModel.default }
    private var session: LanguageModelSession?
    /// The tier the NEXT session runs on (#30). Switching invalidates the
    /// live session; the replayed (condensed) transcript is the handover.
    private(set) var activeTier: LocalModelTier = .onDevice
    /// One-shot escalation offer (#30): set when on-device condensation first
    /// kicks in while PCC is available — the user decides, never silent.
    private(set) var shouldOfferPrivateCloudEscalation = false
    private var escalationOfferDismissed = false
    /// Device tool belt (#28), installed by AppContainer after construction.
    /// Empty = the tool-less #26 configuration (tests, early boot).
    private(set) var tools: [any Tool] = []
    /// Bridges the belt's invocations onto `StreamingUpdate.toolActivity` —
    /// pointed at the live stream's continuation for the duration of a turn.
    private(set) var toolRelay: ToolEventRelay?
    /// The memory block synthesized by the last condensation, kept for
    /// diagnostics. Session-lifetime only: rebuilds re-derive it from the full
    /// message history, which the Conversation always retains.
    private(set) var condensedMemory: String?
    private var didAttemptCacheRestore = false

    /// Shared trimming/token-measuring helpers (#4.8) — reused so the
    /// tokenizer-facing surface (and its iOS 26.4 gate) lives in one place.
    private let intelligence: LocalIntelligenceService
    /// Standalone history is local-only by design (#26): the UserDefaults
    /// conversation cache — written by ChatStore — is the restore source for
    /// kill/relaunch continuity and the backing for listSessions/openSession.
    private let persistence: any AppPersistenceStoreProtocol

    init(
        persistence: any AppPersistenceStoreProtocol,
        intelligence: LocalIntelligenceService
    ) {
        self.persistence = persistence
        self.intelligence = intelligence
    }

    /// Installs the device tool belt (#28). Invalidates the live session so
    /// the next turn is created with the tools (and tool-aware instructions).
    func installTools(_ tools: [any Tool], relay: ToolEventRelay) {
        self.tools = tools
        self.toolRelay = relay
        session = nil
    }

    /// Honest explanation for the CURRENT unavailability, nil when the model
    /// is available (#31). Drives the standalone chat's explanation state —
    /// re-read live each render, so enabling Apple Intelligence in Settings
    /// clears it on return without a relaunch.
    var availabilityExplanation: String? {
        if case .unavailable(let reason) = model.availability {
            return Self.unavailabilityMessage(for: reason)
        }
        return nil
    }

    // MARK: - Private Cloud Compute tier (#30)

    /// Whether PCC exists for this install at all: iOS 27+, entitlement
    /// granted, device/region eligible. Denied/pending Apple approval reads
    /// as unavailable — the on-device path is unaffected.
    var isPrivateCloudAvailable: Bool {
        guard #available(iOS 27.0, *) else { return false }
        return PrivateCloudComputeLanguageModel().isAvailable
    }

    /// Whether PCC can take a turn RIGHT NOW: available and not over the
    /// daily quota. The router consults this per new message, so a
    /// rate-limited tier degrades to on-device with a visible indicator
    /// change instead of failing turns.
    var isPrivateCloudUsable: Bool {
        guard #available(iOS 27.0, *) else { return false }
        let pcc = PrivateCloudComputeLanguageModel()
        return pcc.isAvailable && !pcc.quotaUsage.isLimitReached
    }

    /// Version-agnostic quota snapshot for persistent UI (Settings → Models)
    /// — status, not alerts, per the PCC design guidance. Nil pre-iOS 27 or
    /// while PCC is unavailable.
    struct PrivateCloudStatus: Equatable, Sendable {
        enum Quota: Equatable, Sendable {
            case belowLimit(approaching: Bool)
            case limitReached(resetDate: Date?)
        }

        let quota: Quota
        let hasLimitIncreaseSuggestion: Bool
    }

    func privateCloudStatus() -> PrivateCloudStatus? {
        guard #available(iOS 27.0, *) else { return nil }
        let pcc = PrivateCloudComputeLanguageModel()
        guard pcc.isAvailable else { return nil }
        let usage = pcc.quotaUsage
        let quota: PrivateCloudStatus.Quota
        if usage.isLimitReached {
            quota = .limitReached(resetDate: usage.resetDate)
        } else if case .belowLimit(let info) = usage.status {
            quota = .belowLimit(approaching: info.isApproachingLimit)
        } else {
            quota = .belowLimit(approaching: false)
        }
        return PrivateCloudStatus(
            quota: quota,
            hasLimitIncreaseSuggestion: usage.limitIncreaseSuggestion != nil
        )
    }

    /// Presents the system's iCloud+ upgrade path for more PCC access.
    func showPrivateCloudLimitIncreaseOptions() {
        guard #available(iOS 27.0, *) else { return }
        PrivateCloudComputeLanguageModel().quotaUsage.limitIncreaseSuggestion?.show()
    }

    /// Applies the tier for the NEXT turn (called by the router per message).
    /// PCC requested while unavailable degrades to on-device — the router
    /// already made that visible via its own resolution.
    func setPreferredTier(privateCloud: Bool) {
        let tier: LocalModelTier = (privateCloud && isPrivateCloudAvailable) ? .privateCloud : .onDevice
        guard tier != activeTier else { return }
        activeTier = tier
        // Recreate on next send: the replayed (condensed where needed)
        // transcript IS the escalation handover context.
        session = nil
        Self.logger.notice("local tier → \(tier.rawValue, privacy: .public)")
    }

    /// User answered the escalation offer (either way) — one offer per
    /// conversation; cleared by clearConversation.
    func dismissPrivateCloudEscalationOffer() {
        shouldOfferPrivateCloudEscalation = false
        escalationOfferDismissed = true
    }

    /// The context budget follows the ACTIVE tier's model, read at runtime —
    /// 32K on PCC vs the on-device window; neither is ever hardcoded.
    private var activeContextSize: Int {
        if #available(iOS 27.0, *), activeTier == .privateCloud {
            return PrivateCloudComputeLanguageModel().contextSize
        }
        return model.contextSize
    }

    // MARK: - HermesClientProtocol

    func connect() async {
        switch model.availability {
        case .available:
            connectionStatus = .connected
        case .unavailable(let reason):
            Self.logger.notice("connect: on-device model unavailable — \(Self.unavailabilityMessage(for: reason), privacy: .public)")
            connectionStatus = .error
        }
    }

    func disconnect() async {
        session = nil
        connectionStatus = .disconnected
    }

    func send(
        message: String,
        attachments: [PendingAttachment] = [],
        clientMessageID: UUID
    ) async -> Message {
        if case .unavailable(let reason) = model.availability {
            connectionStatus = .error
            return Message(sender: .system, content: Self.unavailabilityMessage(for: reason), status: .failed)
        }
        let prompt = Self.composePrompt(message: message, attachments: attachments)
        var liveSession = await preparedSession(nextPrompt: prompt, excludingClientMessageID: clientMessageID)
        appendUserMessage(message: message, attachments: attachments, clientMessageID: clientMessageID)

        var didCondenseRetry = false
        while true {
            do {
                let response = try await liveSession.respond(to: Prompt(prompt))
                connectionStatus = .connected
                let reply = Message(sender: .hermes, content: response.content, status: .delivered)
                appendAssistantMessage(reply, usage: currentTokenUsage())
                return reply
            } catch {
                if !didCondenseRetry, Self.isContextOverflow(error) {
                    // Overflow degrades to summarized memory, never errors:
                    // rebuild with condensation forced and retry exactly once.
                    didCondenseRetry = true
                    liveSession = await rebuildSession(excludingClientMessageID: clientMessageID, forceCondense: true)
                    continue
                }
                connectionStatus = .error
                return Message(sender: .system, content: failureMessageForActiveTier(error), status: .failed)
            }
        }
    }

    func sendStreaming(
        message content: String,
        attachments: [PendingAttachment] = [],
        clientMessageID: UUID
    ) -> AsyncStream<StreamingUpdate> {
        AsyncStream { continuation in
            Task { @MainActor [weak self] in
                guard let self else {
                    continuation.yield(.failed("The on-device brain was deallocated before the send started."))
                    continuation.finish()
                    return
                }
                await self.streamTurn(
                    message: content,
                    attachments: attachments,
                    clientMessageID: clientMessageID,
                    into: continuation
                )
                continuation.finish()
            }
        }
    }

    private func streamTurn(
        message: String,
        attachments: [PendingAttachment],
        clientMessageID: UUID,
        into continuation: AsyncStream<StreamingUpdate>.Continuation
    ) async {
        if case .unavailable(let reason) = model.availability {
            connectionStatus = .error
            continuation.yield(.failed(Self.unavailabilityMessage(for: reason)))
            return
        }

        let prompt = Self.composePrompt(message: message, attachments: attachments)
        var liveSession = await preparedSession(nextPrompt: prompt, excludingClientMessageID: clientMessageID)
        appendUserMessage(message: message, attachments: attachments, clientMessageID: clientMessageID)

        // #28: tool invocations surface on the existing toolActivity channel
        // for the duration of this turn — the tool-chip UI renders them free.
        toolRelay?.emit = { event in continuation.yield(.toolActivity(event)) }
        defer { toolRelay?.emit = nil }

        var didCondenseRetry = false
        while true {
            do {
                // FM snapshots are cumulative — diff against what has already
                // been emitted so ChatStore's `.textDelta`-appending consumer
                // works unmodified.
                var emitted = ""
                var latestFull = ""
                // #30: PCC reasoning is a SEPARATE channel (the #4.15 rule) —
                // reasoning transcript entries diff onto reasoningDelta,
                // never folded into the answer text.
                var emittedReasoning = ""
                let stream = liveSession.streamResponse(to: Prompt(prompt))
                for try await snapshot in stream {
                    if Task.isCancelled { break }
                    latestFull = snapshot.content
                    if let delta = Self.streamDelta(from: emitted, to: latestFull) {
                        emitted += delta
                        continuation.yield(.textDelta(delta))
                    }
                    if #available(iOS 27.0, *), activeTier == .privateCloud {
                        let reasoningFull = Self.reasoningText(from: snapshot.transcriptEntries)
                        if let delta = Self.streamDelta(from: emittedReasoning, to: reasoningFull) {
                            emittedReasoning += delta
                            continuation.yield(.reasoningDelta(delta))
                        }
                    }
                }
                connectionStatus = .connected
                // `latestFull` is authoritative: if a snapshot ever rewrote
                // earlier text (no incremental delta exists for that), the
                // finished message still carries the model's real final text.
                var reply = Message(sender: .hermes, content: latestFull, status: .delivered)
                if !emittedReasoning.isEmpty { reply.reasoning = emittedReasoning }
                let usage = currentTokenUsage()
                appendAssistantMessage(reply, usage: usage)
                continuation.yield(.finished(reply, usage, nil))
                return
            } catch {
                if !didCondenseRetry, Self.isContextOverflow(error) {
                    didCondenseRetry = true
                    Self.logger.notice("streamTurn: context window exceeded — condensing older turns and retrying once (#26)")
                    liveSession = await rebuildSession(excludingClientMessageID: clientMessageID, forceCondense: true)
                    continue
                }
                connectionStatus = .error
                continuation.yield(.failed(failureMessageForActiveTier(error)))
                return
            }
        }
    }

    /// #30: a failed PCC turn names its tier and what happens next — the
    /// router's per-message resolution moves the NEXT turn on-device when the
    /// tier stays rate-limited/unavailable (visible indicator change).
    private func failureMessageForActiveTier(_ error: Error) -> String {
        let base = Self.failureMessage(for: error)
        guard activeTier == .privateCloud else { return base }
        return "Private Cloud β: \(base) The next message continues on-device if the tier stays unavailable."
    }

    /// Concatenated reasoning text from a snapshot's transcript entries (#30).
    /// Reasoning segments never appear in the response content — this is the
    /// only place they surface.
    @available(iOS 27.0, *)
    nonisolated static func reasoningText(from entries: [Transcript.Entry]) -> String {
        entries.compactMap { entry -> String? in
            guard case .reasoning(let reasoning) = entry else { return nil }
            let text = reasoning.segments.compactMap { segment -> String? in
                if case .text(let textSegment) = segment { return textSegment.content }
                return nil
            }.joined(separator: "\n")
            return text.isEmpty ? nil : text
        }.joined(separator: "\n")
    }

    func loadConversation() async -> Conversation {
        restoreFromCacheIfNeeded()
        if let currentConversation { return currentConversation }
        let fresh = Conversation(title: Conversation.defaultTitle)
        currentConversation = fresh
        return fresh
    }

    func clearConversation() async throws -> Conversation {
        session = nil
        condensedMemory = nil
        // #30: the escalation offer is per-conversation.
        shouldOfferPrivateCloudEscalation = false
        escalationOfferDismissed = false
        let fresh = Conversation(title: Conversation.defaultTitle)
        currentConversation = fresh
        return fresh
    }

    // MARK: - Model controls

    func availableModels() async throws -> [String] {
        // PCC appears ONLY when the entitlement + availability check passes
        // (#30) — a denied/pending Apple application never fakes a tier.
        var models = [Self.onDeviceModelID]
        if isPrivateCloudAvailable {
            models.append(Self.privateCloudModelID)
        }
        return models
    }

    /// Matches Sessions API semantics the UI already knows: the switch applies
    /// to the NEXT session. The response text carries the authoritative
    /// "Context: N tokens" for the CTX meter's denominator (#4) — read from
    /// the model at runtime, never hardcoded.
    @discardableResult
    func switchModel(_ identifier: String) async throws -> String? {
        switch identifier {
        case Self.onDeviceModelID:
            setPreferredTier(privateCloud: false)
        case Self.privateCloudModelID where isPrivateCloudAvailable:
            setPreferredTier(privateCloud: true)
        default:
            throw LocalChatBackendError.unknownModel(identifier)
        }
        return Self.modelSwitchResponseText(modelID: identifier, contextSize: activeContextSize)
    }

    // MARK: - Sessions (local-only by design)

    func listSessions() async throws -> [HermesSessionInfo] {
        restoreFromCacheIfNeeded()
        guard let conversation = currentConversation, !conversation.messages.isEmpty else { return [] }
        return [Self.sessionInfo(for: conversation)]
    }

    func openSession(_ id: String) async throws -> Conversation {
        restoreFromCacheIfNeeded()
        guard let conversation = currentConversation, conversation.id.uuidString == id else {
            throw LocalChatBackendError.sessionNotFound(id)
        }
        // Recreate the LanguageModelSession on next send so the reopened
        // history is replayed into the transcript.
        session = nil
        return conversation
    }

    func reconcileFromServer() async -> Conversation? {
        // No server: a local run either finishes in-process or fails honestly.
        nil
    }

    // MARK: - Session lifecycle

    /// Returns the live session when the next turn still fits its context;
    /// otherwise rebuilds (condensing as needed). Also the lazy-creation path.
    private func preparedSession(nextPrompt: String, excludingClientMessageID: UUID?) async -> LanguageModelSession {
        restoreFromCacheIfNeeded()
        if currentConversation == nil {
            currentConversation = Conversation(title: Conversation.defaultTitle)
        }
        if let session {
            let turns = Self.transcriptTurns(
                from: currentConversation?.messages ?? [],
                excludingClientMessageID: excludingClientMessageID
            )
            if await fitsContext(turns: turns, nextPrompt: nextPrompt) {
                return session
            }
            Self.logger.notice("preparedSession: context budget approached — condensing older turns (#26)")
        }
        return await rebuildSession(excludingClientMessageID: excludingClientMessageID, forceCondense: false)
    }

    @discardableResult
    private func rebuildSession(excludingClientMessageID: UUID?, forceCondense: Bool) async -> LanguageModelSession {
        let turns = Self.transcriptTurns(
            from: currentConversation?.messages ?? [],
            excludingClientMessageID: excludingClientMessageID
        )
        let blueprint = await sessionBlueprint(for: turns, forceCondense: forceCondense)
        condensedMemory = blueprint.condensedMemory
        let fresh = makeSession(from: blueprint)
        session = fresh
        return fresh
    }

    /// What a recreated session should contain: instructions (base persona,
    /// plus condensed memory of dropped turns when the history no longer fits)
    /// and the verbatim turn suffix to replay.
    struct SessionBlueprint {
        let instructions: String
        let verbatimTurns: [TranscriptTurn]
        let condensedMemory: String?
    }

    private func sessionBlueprint(for turns: [TranscriptTurn], forceCondense: Bool) async -> SessionBlueprint {
        let baseInstructions = Self.instructionsText(deviceContext: Self.deviceContextLine(), hasTools: !tools.isEmpty)
        // Budget from the model at RUNTIME — never hardcoded (#26 ground rule).
        let contextBudget = max(1024, activeContextSize - Self.responseHeadroomTokens)

        // Cheap upper bound first: every token is at least one UTF-8 byte, so
        // a byte total inside the budget can never overflow it — skip the
        // tokenizer round trip for the common short-history case.
        let byteTotal = baseInstructions.utf8.count + turns.reduce(0) { $0 + $1.text.utf8.count }
        if !forceCondense, byteTotal <= contextBudget {
            return SessionBlueprint(instructions: baseInstructions, verbatimTurns: turns, condensedMemory: nil)
        }

        var counts: [Int] = []
        counts.reserveCapacity(turns.count)
        for turn in turns {
            counts.append(await intelligence.measuredTokenCount(of: turn.text))
        }
        let instructionTokens = await intelligence.measuredTokenCount(of: baseInstructions)
        let available = max(512, contextBudget - instructionTokens)

        var split = Self.verbatimSplitIndex(turnTokenCounts: counts, availableBudget: available)
        if forceCondense, split == 0, turns.count > 1 {
            // The live session overflowed even though our estimate said the
            // history fits (tokenizer estimates are approximate) — drop at
            // least the older half so the retry actually has room.
            split = turns.count / 2
        }
        guard split > 0 else {
            return SessionBlueprint(instructions: baseInstructions, verbatimTurns: turns, condensedMemory: nil)
        }

        // #30: the conversation just outgrew the on-device window — offer the
        // 32K PCC tier ONCE per conversation, only when it's actually
        // available. The user decides; nothing escalates silently.
        if activeTier == .onDevice, !escalationOfferDismissed, isPrivateCloudAvailable {
            shouldOfferPrivateCloudEscalation = true
        }

        var memoryLines: [String] = []
        for turn in turns[..<split] {
            let head = await intelligence.trimmed(turn.text, toTokenBudget: Self.condensedPerTurnTokens)
            memoryLines.append("\(turn.role == .user ? "User" : "Hermes"): \(head)")
        }
        let memory = await intelligence.trimmed(
            memoryLines.joined(separator: "\n"),
            toTokenBudget: Self.condensedMemoryTokens
        )
        let instructions = baseInstructions + "\n\n" + Self.condensedMemoryPreamble + "\n" + memory
        Self.logger.notice("sessionBlueprint: condensed \(split) older turn(s) into memory; \(turns.count - split) replayed verbatim (#26)")
        return SessionBlueprint(
            instructions: instructions,
            verbatimTurns: Array(turns[split...]),
            condensedMemory: memory
        )
    }

    /// Whether instructions + full history + the next prompt fit the runtime
    /// context budget. Byte count is a safe upper bound for token count, so
    /// the tokenizer only runs once histories actually get long.
    private func fitsContext(turns: [TranscriptTurn], nextPrompt: String) async -> Bool {
        let baseInstructions = Self.instructionsText(deviceContext: Self.deviceContextLine(), hasTools: !tools.isEmpty)
        let contextBudget = max(1024, activeContextSize - Self.responseHeadroomTokens)
        let byteTotal = baseInstructions.utf8.count
            + nextPrompt.utf8.count
            + turns.reduce(0) { $0 + $1.text.utf8.count }
        if byteTotal <= contextBudget { return true }
        var tokens = await intelligence.measuredTokenCount(of: baseInstructions)
        tokens += await intelligence.measuredTokenCount(of: nextPrompt)
        for turn in turns {
            tokens += await intelligence.measuredTokenCount(of: turn.text)
            if tokens > contextBudget { return false }
        }
        return tokens <= contextBudget
    }

    private func makeSession(from blueprint: SessionBlueprint) -> LanguageModelSession {
        var entries: [Transcript.Entry] = []
        entries.append(.instructions(Transcript.Instructions(
            id: UUID().uuidString,
            segments: [.text(Transcript.TextSegment(id: UUID().uuidString, content: blueprint.instructions))],
            toolDefinitions: []
        )))
        for turn in blueprint.verbatimTurns {
            let segment = Transcript.Segment.text(
                Transcript.TextSegment(id: UUID().uuidString, content: turn.text)
            )
            switch turn.role {
            case .user:
                entries.append(.prompt(Transcript.Prompt(
                    id: UUID().uuidString,
                    segments: [segment],
                    options: GenerationOptions(),
                    responseFormat: nil
                )))
            case .assistant:
                entries.append(.response(Transcript.Response(
                    id: UUID().uuidString,
                    assetIDs: [],
                    segments: [segment]
                )))
            }
        }
        // Tools come from the #28 belt (empty until AppContainer installs it).
        // The transcript's Instructions entry carries no toolDefinitions —
        // the session's `tools:` parameter is the operative wiring; if
        // tool-calling misbehaves on replayed sessions, populate
        // `Transcript.ToolDefinition`s here (flagged for device verify).
        //
        // #30: both SystemLanguageModel and PrivateCloudComputeLanguageModel
        // conform to LanguageModel (iOS 27) — the session API is unified, so
        // the PCC tier is one argument, not a second code path.
        if #available(iOS 27.0, *), activeTier == .privateCloud {
            return LanguageModelSession(
                model: PrivateCloudComputeLanguageModel(),
                tools: tools,
                transcript: Transcript(entries: entries)
            )
        }
        return LanguageModelSession(model: model, tools: tools, transcript: Transcript(entries: entries))
    }

    // MARK: - Conversation bookkeeping

    /// One-shot restore from the UserDefaults conversation cache (written by
    /// ChatStore) so a kill/relaunch continues with context.
    private func restoreFromCacheIfNeeded() {
        guard !didAttemptCacheRestore, currentConversation == nil else { return }
        didAttemptCacheRestore = true
        guard let cached = persistence.loadConversationCache() else { return }
        currentConversation = cached
        Self.logger.notice("restored \(cached.messages.count) cached message(s) for transcript replay (#26)")
    }

    private func appendUserMessage(message: String, attachments: [PendingAttachment], clientMessageID: UUID) {
        if currentConversation == nil {
            currentConversation = Conversation(title: Conversation.defaultTitle)
        }
        // Mirrors ChatStore's optimistic display content so the post-turn
        // metadata merge dedupes by id instead of duplicating the turn.
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayContent = trimmed.isEmpty && !attachments.isEmpty
            ? "[\(attachments.count) attachment\(attachments.count == 1 ? "" : "s")]"
            : trimmed
        let userMessage = Message(
            id: clientMessageID,
            clientMessageID: clientMessageID,
            sender: .user,
            content: displayContent,
            status: .delivered,
            attachments: attachments.map { MessageAttachment(from: $0) }
        )
        currentConversation?.messages.append(userMessage)
        currentConversation?.lastActivity = userMessage.timestamp
    }

    private func appendAssistantMessage(_ reply: Message, usage: TokenUsage?) {
        currentConversation?.messages.append(reply)
        currentConversation?.lastActivity = reply.timestamp
        if let usage {
            currentConversation?.latestUsage = usage
        }
    }

    /// Real token usage where the OS provides it: `LanguageModelSession.usage`
    /// (iOS 27). Returns nil on iOS 26 — usage is never estimated client-side
    /// (real-data-only; the CTX meter shows "—" rather than a guess).
    private func currentTokenUsage() -> TokenUsage? {
        guard let session else { return nil }
        if #available(iOS 27.0, *) {
            let usage = session.usage
            return TokenUsage(
                promptTokens: usage.input.totalTokenCount,
                completionTokens: usage.output.totalTokenCount,
                totalTokens: usage.totalTokenCount
            )
        }
        return nil
    }

    // MARK: - Pure helpers (unit-tested)

    /// A replayable conversation turn extracted from the message history.
    struct TranscriptTurn: Equatable, Sendable {
        enum Role: Equatable, Sendable {
            case user
            case assistant
        }

        let role: Role
        let text: String
    }

    /// Maps the persisted message history onto replayable turns: delivered
    /// user/Hermes messages (voice turns included — they're real conversation
    /// content), skipping system banners, failed/in-flight sends, streaming
    /// placeholders, and the message currently being sent (`excluded` — it is
    /// the live prompt, not history).
    nonisolated static func transcriptTurns(
        from messages: [Message],
        excludingClientMessageID excluded: UUID? = nil
    ) -> [TranscriptTurn] {
        messages.compactMap { message in
            guard message.status == .delivered, !message.isStreaming else { return nil }
            if let excluded, message.id == excluded || message.clientMessageID == excluded { return nil }
            let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            switch message.sender {
            case .user, .voiceUser:
                return TranscriptTurn(role: .user, text: text)
            case .hermes, .voiceHermes:
                return TranscriptTurn(role: .assistant, text: text)
            case .system:
                return nil
            }
        }
    }

    /// The incremental delta between the text already emitted and a cumulative
    /// stream snapshot. Nil when the snapshot adds nothing, or when it rewrote
    /// earlier text (no safe increment exists — the finished message carries
    /// the authoritative final text instead).
    nonisolated static func streamDelta(from emitted: String, to snapshot: String) -> String? {
        guard !snapshot.isEmpty, snapshot != emitted else { return nil }
        guard snapshot.hasPrefix(emitted) else { return nil }
        let delta = String(snapshot.dropFirst(emitted.count))
        return delta.isEmpty ? nil : delta
    }

    /// The single prompt string for one turn: the user's message plus text
    /// attachments inlined through the shared delimiter surface
    /// (`AttachmentInlining`, #8/#43). Images have no on-device representation
    /// — they become an honest in-prompt note, never fabricated content.
    nonisolated static func composePrompt(message: String, attachments: [PendingAttachment]) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !attachments.isEmpty else { return trimmed }
        var sections: [String] = []
        if !trimmed.isEmpty { sections.append(trimmed) }
        for attachment in attachments {
            switch attachment.kind {
            case .file where PendingAttachment.isInlinableTextMime(attachment.mimeType):
                sections.append(AttachmentInlining.delimitedTextPart(
                    fileName: attachment.fileName,
                    mimeType: attachment.mimeType,
                    content: String(decoding: attachment.data, as: UTF8.self)
                ))
            case .image:
                sections.append("[Attached image \"\(attachment.fileName)\" — the on-device model cannot view images. If the image matters to the request, say honestly that you can't see it.]")
            case .file:
                sections.append("[Attachment \"\(attachment.fileName)\" (\(attachment.mimeType)) has no on-device representation and was not delivered.]")
            }
        }
        return sections.joined(separator: "\n\n")
    }

    /// Index where the verbatim tail starts: the newest turns that fit half
    /// the available budget (the rest is room for condensed memory + the turn
    /// in flight). 0 = everything fits verbatim. The newest turn is always
    /// kept, even when it alone exceeds the share.
    nonisolated static func verbatimSplitIndex(turnTokenCounts: [Int], availableBudget: Int) -> Int {
        guard !turnTokenCounts.isEmpty else { return 0 }
        let total = turnTokenCounts.reduce(0, +)
        if total <= availableBudget { return 0 }
        let verbatimBudget = max(availableBudget / 2, 256)
        var accumulated = 0
        var index = turnTokenCounts.count
        while index > 0 {
            let next = accumulated + turnTokenCounts[index - 1]
            if next > verbatimBudget, index != turnTokenCounts.count { break }
            accumulated = next
            index -= 1
        }
        return index
    }

    static let condensedMemoryPreamble = """
    ## Earlier conversation (condensed)
    Older turns were condensed to fit the on-device context window. Treat them \
    as prior conversation memory:
    """

    nonisolated static func instructionsText(deviceContext: String, date: Date = .now, hasTools: Bool = false) -> String {
        let day = date.formatted(date: .complete, time: .omitted)
        let capabilities = hasTools
            ? """
            Be direct, warm, and concise. You have device tools — health, location, motion, calendar, reminders, weather, places, contacts, device status, image text/barcode reading, and conversation search — plus action tools that can create reminders, calendar events, and alarms. Use them to work with the user's real data instead of guessing. Every action tool shows the user a confirmation card first; if they decline, accept it gracefully. When a tool reports that a permission isn't granted or no data exists, relay that honestly — never invent a value.
            """
            : """
            Be direct, warm, and concise. You have no internet access and no external tools in this mode — when you don't know something or can't do it on-device, say so plainly instead of guessing.
            """
        return """
        You are Hermes, the user's personal assistant, running entirely on their iPhone with Apple's on-device foundation model. The conversation is private and never leaves the device.
        Today is \(day).
        \(deviceContext)
        \(capabilities)
        """
    }

    private static func deviceContextLine() -> String {
        let device = UIDevice.current
        return "Device: \(device.model) running iOS \(device.systemVersion)."
    }

    /// The `/model`-style response `switchModel` returns; ChatStore parses the
    /// "Context: N tokens" line for the CTX denominator (#4).
    nonisolated static func modelSwitchResponseText(modelID: String, contextSize: Int) -> String {
        "Model switched to `\(modelID)` — Apple on-device foundation model.\nContext: \(contextSize) tokens"
    }

    nonisolated static func sessionInfo(for conversation: Conversation) -> HermesSessionInfo {
        HermesSessionInfo(
            id: conversation.id.uuidString,
            title: conversation.title == Conversation.defaultTitle ? nil : conversation.title,
            preview: conversation.generatedPreview ?? conversation.lastMessage?.content,
            model: onDeviceModelID,
            source: localSessionSource,
            messageCount: conversation.messages.count,
            lastActive: conversation.lastActivity,
            isActive: true
        )
    }

    // MARK: - Honest failure states

    nonisolated static func unavailabilityMessage(for reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            return "On-device intelligence isn't available: this device doesn't support Apple Intelligence. Connect a Hermes desktop in Settings to chat."
        case .appleIntelligenceNotEnabled:
            return "On-device intelligence is turned off. Enable Apple Intelligence in Settings → Apple Intelligence & Siri, then try again."
        case .modelNotReady:
            return "The on-device model is still getting ready (downloading or optimizing). Try again in a few minutes."
        @unknown default:
            return "On-device intelligence is unavailable right now for a reason this version of Talaria doesn't recognize."
        }
    }

    nonisolated static func isContextOverflow(_ error: Error) -> Bool {
        guard let generationError = error as? LanguageModelSession.GenerationError else { return false }
        if case .exceededContextWindowSize = generationError { return true }
        return false
    }

    /// Plain-language reasons for `.failed(String)` — never a bare error dump
    /// for the cases the on-device model actually produces.
    nonisolated static func failureMessage(for error: Error) -> String {
        guard let generationError = error as? LanguageModelSession.GenerationError else {
            let described = error.localizedDescription
            return described.isEmpty ? "The on-device model failed to respond." : described
        }
        switch generationError {
        case .exceededContextWindowSize:
            return "This conversation outgrew the on-device model's memory even after condensing older turns. Start a new chat to continue."
        case .guardrailViolation:
            return "Apple's on-device safety guardrails declined this request."
        case .rateLimited:
            return "The on-device model is rate-limited right now. Give it a moment and try again."
        case .concurrentRequests:
            return "The on-device model is still working on the previous request. Wait for it to finish, then try again."
        case .assetsUnavailable:
            return "The on-device model's assets aren't available right now — Apple Intelligence may still be downloading."
        case .refusal:
            return "The on-device model declined to answer this request."
        case .unsupportedLanguageOrLocale:
            return "The on-device model doesn't support this language or locale yet."
        case .decodingFailure:
            return "The on-device model produced a response Talaria couldn't decode."
        case .unsupportedGuide:
            return "The on-device model couldn't satisfy the requested output format."
        @unknown default:
            return generationError.localizedDescription
        }
    }
}

enum LocalChatBackendError: LocalizedError {
    case unknownModel(String)
    case sessionNotFound(String)

    var errorDescription: String? {
        switch self {
        case .unknownModel(let id):
            return "The on-device brain has no model \"\(id)\"."
        case .sessionNotFound(let id):
            return "No local conversation \"\(id)\" — standalone history keeps only the current conversation on this device."
        }
    }
}
