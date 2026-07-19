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
    nonisolated static let onDeviceModelID = "on-device"
    nonisolated static let privateCloudModelID = "private-cloud-beta"

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
    nonisolated static let localSessionSource = "local"

    private static let logger = Logger(subsystem: "org.aethyrion.talaria", category: "LocalChatBackend")

    /// Tokens reserved out of the context window for the model's reply (the
    /// window is shared between input and output) — and, since #102, also
    /// the enforced `maximumResponseTokens` cap, so the reply can never
    /// overflow its reservation. Tier-aware: PCC's 32K window exists for
    /// long-form output, so capping it at the on-device 1024 would gut the
    /// tier's whole point.
    nonisolated static func responseHeadroomTokens(for tier: LocalModelTier) -> Int {
        tier == .privateCloud ? 4096 : 1024
    }

    /// Explicit generation options for every chat turn (#102). Passing no
    /// options leaves sampling to an UNDOCUMENTED system default and imposes
    /// no response-token bound at all — Apple's docs (verified 2026-07-12):
    /// with `maximumResponseTokens` unset "the model is allowed to produce
    /// the longest answer its context size supports", the best-fit mechanism
    /// for the observed phrase-loop + thermal "serious". Three explicit
    /// choices:
    /// - Nucleus sampling: guarantees non-greedy decoding (under greedy, a
    ///   temperature is a no-op — and whether the system default is greedy
    ///   is undocumented). 0.9 is the standard conversational threshold.
    /// - Temperature 0.7: moderate on Apple's documented 0–1 scale
    ///   (1 = no adjustment, lower sharpens toward determinism).
    /// - Token cap = the tier's reply headroom, the same reservation the
    ///   context budget carves out, now enforced. Hitting it terminates the
    ///   response early with NO error (documented), so a runaway reply
    ///   degrades to truncation instead of a thermal event.
    nonisolated static func chatGenerationOptions(for tier: LocalModelTier) -> GenerationOptions {
        GenerationOptions(
            samplingMode: .random(probabilityThreshold: 0.9),
            temperature: 0.7,
            maximumResponseTokens: responseHeadroomTokens(for: tier)
        )
    }
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

    /// Master gate: PCC needs an Apple-granted entitlement that is NOT live yet
    /// (#72, awaiting approval). On this beta seed, constructing or using
    /// `PrivateCloudComputeLanguageModel` without the grant traps (SIGTRAP) —
    /// an uncatchable crash on send. Until the grant lands we never touch the
    /// type at all. Flip to `true` (or wire to a real signal) once granted;
    /// that alone re-enables the picker, routing, status, and session paths.
    static let pccGrantConfirmed = false

    /// Whether PCC exists for this install at all: grant confirmed, iOS 27+,
    /// entitlement granted, device/region eligible. Denied/pending Apple
    /// approval reads as unavailable — the on-device path is unaffected.
    var isPrivateCloudAvailable: Bool {
        guard #available(iOS 27.0, *), Self.pccGrantConfirmed else { return false }
        return PrivateCloudComputeLanguageModel().isAvailable
    }

    /// Whether PCC can take a turn RIGHT NOW: available and not over the
    /// daily quota. The router consults this per new message, so a
    /// rate-limited tier degrades to on-device with a visible indicator
    /// change instead of failing turns.
    var isPrivateCloudUsable: Bool {
        guard #available(iOS 27.0, *), Self.pccGrantConfirmed else { return false }
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
        guard #available(iOS 27.0, *), Self.pccGrantConfirmed else { return nil }
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
        guard #available(iOS 27.0, *), Self.pccGrantConfirmed else { return }
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

    /// PCC context window, fetched once per process and cached — the window
    /// is a fixed property of the model class, not live state. (The beta-27
    /// SDK exposes `contextSize` as `async throws` on PCC, unlike the sync
    /// on-device accessor.)
    private var pccContextSize: Int?

    /// The context budget follows the ACTIVE tier's model, read at runtime —
    /// 32K on PCC vs the on-device window; neither is ever hardcoded. If the
    /// PCC fetch fails, falls back to the on-device window: a conservative
    /// budget that can never over-commit the larger tier.
    private func activeContextSize() async -> Int {
        if #available(iOS 27.0, *), Self.pccGrantConfirmed, activeTier == .privateCloud {
            if let cached = pccContextSize { return cached }
            if let size = try? await PrivateCloudComputeLanguageModel().contextSize {
                pccContextSize = size
                return size
            }
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
                let response = try await liveSession.respond(to: Prompt(prompt), options: Self.chatGenerationOptions(for: activeTier))
                connectionStatus = .connected
                let usage = currentTokenUsage()
                // #102: the sync path has no stream to break, but a capped
                // looped reply still returns as a normal success — collapse
                // it before it becomes replayable history, mirroring the
                // streaming trip.
                let content = Self.collapsingDegenerateTail(response.content)
                if content != response.content {
                    // The live session's internal transcript holds the full
                    // loop — rebuild the next turn from our (collapsed)
                    // history instead of trusting it.
                    session = nil
                    Self.logger.notice("send: degenerate tail collapsed in sync reply — session invalidated (#102)")
                }
                let reply = Message(sender: .hermes, content: content, status: .delivered)
                appendAssistantMessage(reply, usage: usage)
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
        #if DEBUG
        // #120 (UITest seam): a model-free synthetic turn armed only by the
        // UITEST_DUPID_PROBE launch env. It runs the production append →
        // finish machinery — append the reply to `currentConversation`, then
        // dwell past one poll interval BEFORE yielding `.finished` — so the
        // 2s poll tick's `loadConversation()` merge deterministically lands
        // in the exact window that seeds a duplicate id (#120). Placed ahead
        // of the availability gate so a clean CI simulator with no on-device
        // model still exercises the path. Inert in every non-UITest run.
        if Self.isUITestIdentityProbeEnabled {
            await runUITestIdentityTurn(
                message: message,
                attachments: attachments,
                clientMessageID: clientMessageID,
                into: continuation
            )
            return
        }
        #endif

        if case .unavailable(let reason) = model.availability {
            connectionStatus = .error
            continuation.yield(.failed(Self.unavailabilityMessage(for: reason)))
            return
        }

        #if DEBUG
        // #134 forced-trip harness: a one-shot turn armed from Settings →
        // Diagnostics that replays synthetic degenerate snapshots through this
        // exact path, so the #102 breaker and the #110 read-aloud retraction
        // can finally be observed tripping on device (the live model's own
        // guardrails defeat every organic loop repro). Everything downstream —
        // delta diffing, breaker, collapse, finish — is the production
        // machinery, unmodified.
        if let copies = Self.debugForcedTripCopies {
            Self.debugForcedTripCopies = nil
            let holdsLiveStream = Self.debugForcedTripHoldsLiveSDKStream
            Self.debugForcedTripHoldsLiveSDKStream = false
            await runDebugForcedTripTurn(
                message: message,
                attachments: attachments,
                clientMessageID: clientMessageID,
                copies: copies,
                holdLiveSDKStream: holdsLiveStream,
                into: continuation
            )
            return
        }
        #endif

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
                var didTripRepetitionBreaker = false
                var repetitionBreaker = RepetitionBreaker()
                let stream = liveSession.streamResponse(to: Prompt(prompt), options: Self.chatGenerationOptions(for: activeTier))
                for try await snapshot in stream {
                    if Task.isCancelled { break }
                    latestFull = snapshot.content
                    if let delta = Self.streamDelta(from: emitted, to: latestFull) {
                        emitted += delta
                        continuation.yield(.textDelta(delta))
                    }
                    if #available(iOS 27.0, *), activeTier == .privateCloud {
                        let reasoningFull = Self.reasoningText(from: Array(snapshot.transcriptEntries))
                        if let delta = Self.streamDelta(from: emittedReasoning, to: reasoningFull) {
                            emittedReasoning += delta
                            continuation.yield(.reasoningDelta(delta))
                        }
                    }
                    // #102: a model stuck in a phrase loop would otherwise
                    // burn until the token cap. The breaker arms on the
                    // first qualifying repetition and abandons the stream
                    // only when the run keeps GROWING — bounded legitimate
                    // repetition (identical code rows, a requested refrain)
                    // ends, disarms, and streams through untouched.
                    if repetitionBreaker.shouldAbandon(afterObserving: Self.degenerateTailRepetitionRun(in: latestFull)) {
                        didTripRepetitionBreaker = true
                        Self.logger.notice("streamTurn: degenerate tail repetition escalated after \(latestFull.count, privacy: .public) chars — abandoning the stream, collapsing the looped tail (#102)")
                        // Keep the reply up to ONE copy of the loop: the
                        // full run is noise by definition, and replaying it
                        // into rebuilt sessions re-primes the loop.
                        latestFull = Self.collapsingDegenerateTail(latestFull)
                        break
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
                if didTripRepetitionBreaker {
                    // The abandoned session's internal transcript state is
                    // unknowable — rebuild the next turn from OUR message
                    // history (the durable source) instead of trusting it.
                    session = nil
                }
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
        return Self.modelSwitchResponseText(modelID: identifier, contextSize: await activeContextSize())
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
        let contextBudget = max(1024, await activeContextSize() - Self.responseHeadroomTokens(for: activeTier))

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
        let contextBudget = max(1024, await activeContextSize() - Self.responseHeadroomTokens(for: activeTier))
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
        if #available(iOS 27.0, *), Self.pccGrantConfirmed, activeTier == .privateCloud {
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

    // MARK: Tail-repetition breaker (#102)

    /// Detection thresholds — deliberately conservative: judging legitimate
    /// repetition (lists, code, separator art, refrains) as a loop would
    /// truncate a good reply, so everything below errs toward letting the
    /// token cap (`chatGenerationOptions`) be the backstop instead.
    /// The shortest phrase treated as a loop unit. Anything shorter (repeated
    /// Latin syllables, `}` lines, `---|` table art) never qualifies — except
    /// CJK phrases, which pack a whole phrase into a few characters (see
    /// `repetitionUnitQualifies`).
    private nonisolated static let repetitionMinimumUnitLength = 8
    /// The longest phrase checked as a loop unit. 128 covers full-sentence
    /// loops, a common small-model degeneration shape.
    private nonisolated static let repetitionMaximumUnitLength = 128
    /// Consecutive exact copies of the unit required at the tail before a
    /// run is even DETECTED (arming, not yet abandoning — see
    /// `RepetitionBreaker`).
    private nonisolated static let repetitionMinimumRepeats = 6
    /// Total characters a detected run must cover (short units need
    /// proportionally more copies).
    private nonisolated static let repetitionMinimumSpan = 192
    /// Escalation floor: the breaker never abandons below this many copies,
    /// however early the run was detected.
    nonisolated static let repetitionEscalationRepeats = 12
    /// The scan is bounded to this tail window so it stays cheap on every
    /// stream snapshot. Sized so escalation stays observable for the largest
    /// unit: `repetitionEscalationRepeats × repetitionMaximumUnitLength`
    /// (1536) fits with headroom.
    private nonisolated static let repetitionScanWindow = 2048

    /// A detected degenerate run at the tail of a stream snapshot.
    /// `nonisolated`: nested types infer the class's @MainActor otherwise,
    /// and the nonisolated unit tests construct these directly.
    nonisolated struct TailRepetitionRun: Equatable, Sendable {
        let unitLength: Int
        let repeats: Int
    }

    /// Streaming breaker state (#102): cumulative snapshots judge PREFIXES of
    /// the reply, and a prefix of legitimate output can be tail-repetitive
    /// even when the completed text is not (twelve identical data rows, a
    /// requested refrain). So detection alone never abandons: the breaker
    /// ARMS on the first qualifying run, DISARMS when the tail stops
    /// qualifying (the bounded run ended — the closing bracket arrived), and
    /// abandons only when the same run keeps growing to twice its armed size
    /// (with an absolute floor) — a signature only a genuinely stuck loop
    /// produces.
    nonisolated struct RepetitionBreaker {
        private(set) var armedRepeats: Int?

        // Explicit: private(set) would otherwise restrict the synthesized
        // memberwise initializer below internal, and the tests construct one.
        init() {}

        mutating func shouldAbandon(afterObserving run: TailRepetitionRun?) -> Bool {
            guard let run else {
                armedRepeats = nil
                return false
            }
            guard let armed = armedRepeats else {
                armedRepeats = run.repeats
                return false
            }
            if run.repeats < armed {
                // A different (or re-started) run — re-arm at the lower count
                // rather than measuring the new run against the old baseline.
                armedRepeats = run.repeats
                return false
            }
            // The scan window bounds what a single observation can report
            // (`repetitionScanWindow / unitLength` copies), so the escalation
            // threshold is clamped to that ceiling — otherwise a run that
            // armed high off one coarse snapshot could never be seen to
            // double, and the breaker would silently never fire.
            let maxObservable = LocalChatBackend.repetitionScanWindow / run.unitLength
            let threshold = min(max(LocalChatBackend.repetitionEscalationRepeats, armed * 2), maxObservable)
            return run.repeats >= threshold
        }
    }

    /// The qualifying degenerate run `text` currently ends in, nil when the
    /// tail is healthy. Tail-anchored: a snapshot stream only ever grows at
    /// the end, so a loop the model is currently stuck in always reaches the
    /// tail — while a recovered loop earlier in the text never qualifies.
    /// Alignment doesn't matter: a periodic tail matches at its period even
    /// when the snapshot cuts mid-unit.
    nonisolated static func degenerateTailRepetitionRun(in text: String) -> TailRepetitionRun? {
        let window = Array(text.suffix(repetitionScanWindow))
        let count = window.count
        guard count >= repetitionMinimumSpan else { return nil }
        var unitLength = repetitionMinimumUnitLength
        while unitLength <= repetitionMaximumUnitLength, unitLength * 2 <= count {
            // Count consecutive copies of the last `unitLength` characters,
            // walking backward from the anchor at the very end.
            var repeats = 1
            var blockStart = count - unitLength * 2
            scan: while blockStart >= 0 {
                for offset in 0 ..< unitLength {
                    if window[blockStart + offset] != window[count - unitLength + offset] { break scan }
                }
                repeats += 1
                blockStart -= unitLength
            }
            if repeats >= repetitionMinimumRepeats,
               repeats * unitLength >= repetitionMinimumSpan,
               repetitionUnitQualifies(window, unitStart: count - unitLength, unitLength: unitLength) {
                return TailRepetitionRun(unitLength: unitLength, repeats: repeats)
            }
            unitLength += 1
        }
        return nil
    }

    /// Convenience over `degenerateTailRepetitionRun` for the unit tests and
    /// any caller that only needs the verdict.
    nonisolated static func hasDegenerateTailRepetition(_ text: String) -> Bool {
        degenerateTailRepetitionRun(in: text) != nil
    }

    /// `text` with a detected degenerate tail run collapsed to a single copy
    /// of the looped unit. The full run is noise by definition, and a reply
    /// stored verbatim would replay it into every rebuilt session's
    /// transcript — re-priming the very loop the breaker just cut. Text with
    /// a healthy tail passes through unchanged.
    nonisolated static func collapsingDegenerateTail(_ text: String) -> String {
        guard let run = degenerateTailRepetitionRun(in: text) else { return text }
        // The scan window bounds what the detector can SEE; the actual run
        // may extend further back. Walk the full text (only on a trip, cost
        // proportional to the run) so every copy is removed, not just the
        // in-window ones.
        let chars = Array(text)
        let count = chars.count
        let unitStart = count - run.unitLength
        var totalRepeats = 1
        var blockStart = count - run.unitLength * 2
        scan: while blockStart >= 0 {
            for offset in 0 ..< run.unitLength {
                if chars[blockStart + offset] != chars[unitStart + offset] { break scan }
            }
            totalRepeats += 1
            blockStart -= run.unitLength
        }
        return String(text.dropLast((totalRepeats - 1) * run.unitLength))
    }

    /// A unit only counts as a loop when it carries words (pure punctuation
    /// runs are separator art) and is not itself a shorter loop — "la la la "
    /// is judged at its fundamental 3-character period (below the minimum,
    /// so Latin syllable refrains never qualify), not at a 9-character
    /// multiple. Exception: a CJK phrase packs a whole phrase into a few
    /// characters, so a CJK-bearing fundamental period of 4+ still counts.
    private nonisolated static func repetitionUnitQualifies(_ window: [Character], unitStart: Int, unitLength: Int) -> Bool {
        var hasWordCharacter = false
        for index in unitStart ..< (unitStart + unitLength) where window[index].isLetter || window[index].isNumber {
            hasWordCharacter = true
            break
        }
        guard hasWordCharacter else { return false }
        // Only divisor periods can reproduce the same tail, so only they are
        // checked; ascending order finds the fundamental period first.
        for period in 1 ..< unitLength where unitLength % period == 0 {
            var matchesPeriod = true
            for index in (unitStart + period) ..< (unitStart + unitLength) {
                if window[index] != window[index - period] {
                    matchesPeriod = false
                    break
                }
            }
            if matchesPeriod {
                return period >= 4 && containsCJKCharacter(window, start: unitStart, length: period)
            }
        }
        return true
    }

    /// Whether the range contains a CJK scalar (Han, Hiragana, Katakana,
    /// Hangul) — the scripts whose phrases are short enough to loop below
    /// the Latin minimum unit length.
    private nonisolated static func containsCJKCharacter(_ window: [Character], start: Int, length: Int) -> Bool {
        for index in start ..< (start + length) {
            for scalar in window[index].unicodeScalars {
                switch scalar.value {
                case 0x4E00...0x9FFF, 0x3040...0x309F, 0x30A0...0x30FF, 0xAC00...0xD7AF:
                    return true
                default:
                    continue
                }
            }
        }
        return false
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

#if DEBUG
// MARK: - Forced-trip harness (#134 — DEBUG builds only)

/// Device-verification harness for the ALREADY-SHIPPED #102 breaker and #110
/// read-aloud retraction. The base model's own guardrails defeat every
/// deterministic loop repro (it refuses verbatim-repeat and declines
/// long-form), so a synthetic degenerate stream is the only way to watch the
/// trip happen on a real device. The harness owns NO detection or collapse
/// logic — it scripts the snapshots and lets the production `streamTurn`
/// consumer path (deltas → `RepetitionBreaker` → collapse → finish) do the
/// rest. None of this exists in a Release build.
extension LocalChatBackend {

    /// One-shot arming: set by `ChatStore.debugRunForcedTrip` immediately
    /// before a normal send; the next `streamTurn` consumes and clears it.
    /// Static because extensions can't add stored instance properties —
    /// AppContainer builds exactly one LocalChatBackend per process, so
    /// process-wide arming is equivalent.
    static var debugForcedTripCopies: Int?
    /// Second mode: additionally hold a REAL SDK generation in flight (output
    /// suppressed) while the synthetic loop trips — proves that abandoning a
    /// live stream doesn't wedge the next turn.
    static var debugForcedTripHoldsLiveSDKStream = false

    /// The loop unit the synthetic stream repeats. Exactly 32 characters and
    /// not periodic at any divisor period, so detection first qualifies at
    /// 6 copies (6 × 32 = 192, the span floor) — the breaker ARMS at
    /// `repetitionMinimumRepeats` and ESCALATES at the
    /// `repetitionEscalationRepeats` floor of 12, the same shape the #102
    /// thresholds were tuned for.
    nonisolated static let debugDegenerateUnit = "The device loop signal repeats. "
    /// Benign lead-in: gives read-aloud a healthy sentence to start speaking
    /// (so the #110 retraction visibly CUTS a live queue) and proves the
    /// collapse preserves pre-loop text.
    nonisolated static let debugDegeneratePreamble = "Synthetic degenerate stream armed from Diagnostics. "
    /// Default copy count: the trip lands at copy 12; 16 leaves margin
    /// without meaningfully lengthening the run.
    nonisolated static let debugDegenerateDefaultCopies = 16
    /// Pacing between synthetic snapshots — realistic enough that speech has
    /// STARTED before the trip (#110 must retract a speaking queue, not one
    /// that never began) and a held live SDK stream is genuinely
    /// mid-generation when abandoned.
    nonisolated static let debugSnapshotPacing: Duration = .milliseconds(200)

    /// Cumulative snapshots mirroring FoundationModels' stream shape: the
    /// preamble alone, then one appended copy of the loop unit per snapshot.
    nonisolated static func debugDegenerateSnapshots(copies: Int = debugDegenerateDefaultCopies) -> [String] {
        var text = debugDegeneratePreamble
        var snapshots = [text]
        for _ in 0 ..< max(1, copies) {
            text += debugDegenerateUnit
            snapshots.append(text)
        }
        return snapshots
    }

    /// The forced-trip turn: everything a real streamed turn does — the user
    /// turn lands in history, cumulative snapshots diff onto `.textDelta`,
    /// every snapshot is judged by a real `RepetitionBreaker`, and the trip
    /// collapses the tail and invalidates the session (the D3 rebuild seam) —
    /// with the model generation replaced by scripted snapshots, plus an
    /// optional suppressed live one.
    fileprivate func runDebugForcedTripTurn(
        message: String,
        attachments: [PendingAttachment],
        clientMessageID: UUID,
        copies: Int,
        holdLiveSDKStream: Bool,
        into continuation: AsyncStream<StreamingUpdate>.Continuation
    ) async {
        Self.logger.notice("debug forced trip: synthetic degenerate stream begins — \(copies, privacy: .public) copies, holds live SDK stream \(holdLiveSDKStream, privacy: .public) (#134)")
        var liveDrain: Task<Void, Never>?
        if holdLiveSDKStream {
            let prompt = Self.composePrompt(message: message, attachments: attachments)
            let liveSession = await preparedSession(nextPrompt: prompt, excludingClientMessageID: clientMessageID)
            let options = Self.chatGenerationOptions(for: activeTier)
            liveDrain = Task { @MainActor in
                // Output suppressed by design — the held stream exists only so
                // the trip abandons a REAL in-flight SDK generation.
                do {
                    for try await _ in liveSession.streamResponse(to: Prompt(prompt), options: options) {
                        if Task.isCancelled { break }
                    }
                } catch {
                    Self.logger.notice("debug forced trip: held SDK stream ended — \(error.localizedDescription, privacy: .public) (#134)")
                }
            }
        }
        appendUserMessage(message: message, attachments: attachments, clientMessageID: clientMessageID)

        var emitted = ""
        var latestFull = ""
        var didTripRepetitionBreaker = false
        var repetitionBreaker = RepetitionBreaker()
        for snapshot in Self.debugDegenerateSnapshots(copies: copies) {
            if Task.isCancelled { break }
            try? await Task.sleep(for: Self.debugSnapshotPacing)
            latestFull = snapshot
            if let delta = Self.streamDelta(from: emitted, to: latestFull) {
                emitted += delta
                continuation.yield(.textDelta(delta))
            }
            if repetitionBreaker.shouldAbandon(afterObserving: Self.degenerateTailRepetitionRun(in: latestFull)) {
                didTripRepetitionBreaker = true
                Self.logger.notice("streamTurn: degenerate tail repetition escalated after \(latestFull.count, privacy: .public) chars — abandoning the stream, collapsing the looped tail (#102)")
                latestFull = Self.collapsingDegenerateTail(latestFull)
                break
            }
        }
        liveDrain?.cancel()
        // No generation happened, so no real usage exists to report
        // (real-data-only — the receipt stays empty rather than stale).
        let reply = Message(sender: .hermes, content: latestFull, status: .delivered)
        appendAssistantMessage(reply, usage: nil)
        if didTripRepetitionBreaker {
            // Same post-trip rule as production: the abandoned stream's
            // transcript state is unknowable — the next turn rebuilds from
            // our message history (D3 verifies exactly this).
            session = nil
        }
        continuation.yield(.finished(reply, nil, nil))
    }
}

// MARK: - Message-identity UITest harness (#120 — DEBUG builds only)

/// Model-free synthetic turn for the #120 end-to-end regression guard. It
/// exercises the production append → finish sequence with a deterministic
/// dwell so the 2s poll-tick merge lands in the duplicate-seeding window,
/// letting a black-box UITest observe whether the rendered transcript ever
/// holds the same id twice. Armed only by the `UITEST_DUPID_PROBE` launch
/// env, and compiled out of Release entirely.
extension LocalChatBackend {

    static var isUITestIdentityProbeEnabled: Bool {
        ProcessInfo.processInfo.environment["UITEST_DUPID_PROBE"] == "1"
    }

    /// Dwell strictly longer than one poll interval (2s) so at least one
    /// `loadConversation()` merge is guaranteed to land after the reply is
    /// appended but before `.finished` is yielded.
    private static var uiTestIdentityDwell: Duration { .seconds(2.6) }

    fileprivate func runUITestIdentityTurn(
        message: String,
        attachments: [PendingAttachment],
        clientMessageID: UUID,
        into continuation: AsyncStream<StreamingUpdate>.Continuation
    ) async {
        connectionStatus = .connected
        appendUserMessage(message: message, attachments: attachments, clientMessageID: clientMessageID)

        // Stream a short fixed reply the same way the live path does — one
        // `.textDelta` per word — so the placeholder renders as a real
        // streaming bubble.
        let responseText = "Acknowledged \(message)"
        var emitted = ""
        for word in responseText.split(separator: " ") {
            try? await Task.sleep(for: .milliseconds(60))
            let delta = (emitted.isEmpty ? "" : " ") + word
            emitted += delta
            continuation.yield(.textDelta(delta))
        }

        // Production ordering: the reply lands in `currentConversation`
        // (which `loadConversation()` serves to the poll merge) BEFORE
        // `.finished`. The dwell holds that window open long enough for the
        // merge to adopt the reply while the store still shows the
        // placeholder — the #120 race, made deterministic.
        let reply = Message(sender: .hermes, content: emitted, status: .delivered)
        appendAssistantMessage(reply, usage: nil)
        try? await Task.sleep(for: Self.uiTestIdentityDwell)
        // Model the unprimed-client shape (#120's unmasked case): on the
        // device the duplication only SURVIVED when the client's
        // `currentConversation` was nil at `.finished` (warm launch — cache
        // short-circuits priming), because the post-finish metadata merge
        // otherwise re-imports the backend thread and silently heals the
        // duplicate in the same MainActor turn. The poll-tick merge above
        // already adopted the reply from `loadConversation()`; clearing here
        // removes only the masking source, exactly like the unit test's
        // MidTurnMergeClient keeps its `currentConversation` nil by design.
        currentConversation = nil
        continuation.yield(.finished(reply, nil, nil))
    }
}
#endif
