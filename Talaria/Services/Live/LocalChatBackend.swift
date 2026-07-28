import Foundation
import FoundationModels
import UIKit
import os
#if DEBUG
import EventKit // #200 action battery: the teardown reap reads-and-removes marked artifacts
#endif

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
    /// Tool names the LIVE session was created with (#176). The offered belt
    /// is conditioned on whether the conversation carries an image, and a
    /// session is stuck with the tool list it was born with — so when the
    /// condition flips (an image arrives, or a fresh thread has none) the
    /// session has to be recreated to match.
    private var sessionToolNames: [String] = []
    /// #196 (PROMOTED 2026-07-28): the current turn's route — true when the
    /// router judged this turn answerable without the device. Set per turn
    /// in `preparedSession` before the session gates consult it; the #176
    /// recreate seam then swaps the session automatically when the route
    /// flips between turns. Device evidence for the promotion: battery-4
    /// 60/60 content AND clean on canary/haiku/norway, router probe
    /// 200/200 both directions, armed control diseased in the same run.
    private var turnRoutedToolless = false
    /// The memory block synthesized by the last condensation, kept for
    /// diagnostics. Session-lifetime only: rebuilds re-derive it from the full
    /// message history, which the Conversation always retains.
    private(set) var condensedMemory: String?
    private var didAttemptCacheRestore = false

    /// Shared trimming/token-measuring helpers (#4.8) — reused so the
    /// tokenizer-facing surface (and its iOS 26.4 gate) lives in one place.
    private let intelligence: LocalIntelligenceService
    /// The UserDefaults conversation cache — written by ChatStore — stays the
    /// restore source for kill/relaunch continuity (#26). Since #190 it is no
    /// longer the sessions backing: that's `sessionStore`.
    private let persistence: any AppPersistenceStoreProtocol
    /// #190: keyed, durable session storage. Nil only when the SwiftData
    /// container failed to create — sessions then degrade to the pre-#190
    /// single-slot behavior instead of crashing at boot.
    private let sessionStore: (any LocalSessionStoring)?
    /// #190: whether a conversation belongs to the standalone path — the one
    /// discriminator shared by the walk-away persist (ChatStore side) and the
    /// legacy-cache adoption here. Defaults to "everything is local", the
    /// correct reading for never-paired devices and standalone tests;
    /// AppContainer wires the real rule (no configured host, or a
    /// local-brained turn in the transcript).
    private let isLocalThread: @MainActor (Conversation) -> Bool
    /// One-shot legacy adoption gate (#190 Phase 3) — see
    /// `adoptLegacySingleSlotIfNeeded`.
    private var didAttemptLegacyAdoption = false

    init(
        persistence: any AppPersistenceStoreProtocol,
        intelligence: LocalIntelligenceService,
        sessionStore: (any LocalSessionStoring)? = nil,
        isLocalThread: @escaping @MainActor (Conversation) -> Bool = { _ in true }
    ) {
        self.persistence = persistence
        self.intelligence = intelligence
        self.sessionStore = sessionStore
        self.isLocalThread = isLocalThread
    }

    /// Installs the device tool belt (#28). Invalidates the live session so
    /// the next turn is created with the tools (and tool-aware instructions).
    func installTools(_ tools: [any Tool], relay: ToolEventRelay) {
        self.tools = tools
        self.toolRelay = relay
        session = nil
        sessionToolNames = []
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
    ///
    /// #154: this flag is now the SOLE gate on every PCC site. Each of them
    /// used to read `#available(iOS 27.0, *), Self.pccGrantConfirmed` — but
    /// the shipping floor is 27.0, so the version clause was always true and
    /// only made the sites LOOK like they had an iOS-26 fallback. They never
    /// did: the live path today is the one this flag being `false` selects.
    static let pccGrantConfirmed = false

    /// Whether PCC exists for this install at all: grant confirmed, iOS 27+,
    /// entitlement granted, device/region eligible. Denied/pending Apple
    /// approval reads as unavailable — the on-device path is unaffected.
    var isPrivateCloudAvailable: Bool {
        guard Self.pccGrantConfirmed else { return false }
        return PrivateCloudComputeLanguageModel().isAvailable
    }

    /// Whether PCC can take a turn RIGHT NOW: available and not over the
    /// daily quota. The router consults this per new message, so a
    /// rate-limited tier degrades to on-device with a visible indicator
    /// change instead of failing turns.
    var isPrivateCloudUsable: Bool {
        guard Self.pccGrantConfirmed else { return false }
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
        guard Self.pccGrantConfirmed else { return nil }
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
        guard Self.pccGrantConfirmed else { return }
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
        if Self.pccGrantConfirmed, activeTier == .privateCloud {
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
        var liveSession = await preparedSession(nextPrompt: prompt, attachments: attachments, excludingClientMessageID: clientMessageID)
        appendUserMessage(message: message, attachments: attachments, clientMessageID: clientMessageID)

        var didCondenseRetry = false
        while true {
            do {
                let response = try await liveSession.respond(to: Prompt(prompt), options: effectiveGenerationOptions())
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
                    liveSession = await rebuildSession(attachments: attachments, excludingClientMessageID: clientMessageID, forceCondense: true)
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
        var liveSession = await preparedSession(nextPrompt: prompt, attachments: attachments, excludingClientMessageID: clientMessageID)
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
                let stream = liveSession.streamResponse(to: Prompt(prompt), options: effectiveGenerationOptions())
                for try await snapshot in stream {
                    if Task.isCancelled { break }
                    latestFull = snapshot.content
                    if let delta = Self.streamDelta(from: emitted, to: latestFull) {
                        emitted += delta
                        continuation.yield(.textDelta(delta))
                    }
                    if activeTier == .privateCloud {
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
                    liveSession = await rebuildSession(attachments: attachments, excludingClientMessageID: clientMessageID, forceCondense: true)
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

    // MARK: - Sessions (#190: backed by the keyed store; the single-slot
    // cache remains only the kill/relaunch restore path)

    func listSessions() async throws -> [HermesSessionInfo] {
        restoreFromCacheIfNeeded()
        adoptLegacySingleSlotIfNeeded()
        guard let sessionStore else {
            // Degraded mode (container creation failed): the pre-#190 single
            // slot, honestly — one live conversation or nothing.
            guard let conversation = currentConversation, !conversation.messages.isEmpty else { return [] }
            return [Self.sessionInfo(for: conversation)]
        }
        let currentID = currentConversation?.id
        var infos = sessionStore.sessionSummaries().map {
            Self.sessionInfo(for: $0, isActive: $0.id == currentID)
        }
        if let current = currentConversation, !current.messages.isEmpty, isLocalThread(current) {
            // The live thread outranks its stored row — the store's copy is
            // frozen at the last walk-away and may lag the conversation.
            infos.removeAll { $0.id == current.id.uuidString }
            infos.append(Self.sessionInfo(for: current))
        }
        return infos.sorted { ($0.lastActive ?? .distantPast) > ($1.lastActive ?? .distantPast) }
    }

    func openSession(_ id: String) async throws -> Conversation {
        restoreFromCacheIfNeeded()
        adoptLegacySingleSlotIfNeeded()
        if let conversation = currentConversation, conversation.id.uuidString == id {
            // Recreate the LanguageModelSession on next send so the reopened
            // history is replayed into the transcript.
            session = nil
            return conversation
        }
        guard let uuid = UUID(uuidString: id) else {
            throw LocalChatBackendError.sessionNotFound(id)
        }
        guard let stored = sessionStore?.conversation(withID: uuid) else {
            // #190B: a row that EXISTS but yields no conversation is a
            // transcript decode failure, not an unknown id — folding the two
            // together would tell the user a stored session doesn't exist.
            // The store already logged the decode error; this is the honest
            // user-facing half.
            if sessionStore?.hasSession(withID: uuid) == true {
                throw LocalChatBackendError.sessionUnreadable(id)
            }
            throw LocalChatBackendError.sessionNotFound(id)
        }
        // Persistence of the DEPARTING thread is not this path's job: it
        // lives in ChatStore's abandonPendingRun — #184's one teardown
        // primitive, which every context switch already routes through.
        currentConversation = stored
        session = nil
        condensedMemory = nil
        // #30: the escalation offer is per-conversation.
        shouldOfferPrivateCloudEscalation = false
        escalationOfferDismissed = false
        return stored
    }

    /// #190 Phase 3: adopt the single-slot cached conversation into the keyed
    /// store. Runs once per process before any sessions read; the id-keyed
    /// upsert makes it idempotent across relaunches (running twice can never
    /// produce two copies), and the cache itself is deliberately untouched —
    /// it stays the kill/relaunch restore path. Beyond the one-time upgrade
    /// migration, this is also the standing catch-up for a thread that was
    /// live when the process died: no walk-away ran, so the cache alone
    /// holds its newest turns.
    private func adoptLegacySingleSlotIfNeeded() {
        guard !didAttemptLegacyAdoption, let sessionStore else { return }
        didAttemptLegacyAdoption = true
        guard let cached = persistence.loadConversationCache(),
              !cached.messages.isEmpty,
              isLocalThread(cached) else { return }
        sessionStore.upsertSession(cached)
    }

    func reconcileFromServer() async -> Conversation? {
        // No server: a local run either finishes in-process or fails honestly.
        nil
    }

    // MARK: - Session lifecycle

    /// Returns the live session when the next turn still fits its context;
    /// otherwise rebuilds (condensing as needed). Also the lazy-creation path.
    private func preparedSession(
        nextPrompt: String,
        attachments: [PendingAttachment],
        excludingClientMessageID: UUID?
    ) async -> LanguageModelSession {
        restoreFromCacheIfNeeded()
        if currentConversation == nil {
            currentConversation = Conversation(title: Conversation.defaultTitle)
        }
        // #196 (PROMOTED): classify THIS turn before any gate reads the
        // route. One extra guided generation (~0.6s measured on device,
        // greedy); errors fail safe to armed inside the router. In DEBUG
        // the A/B picker can pin a legacy cell, which disables routing for
        // the launch so every non-routed cell stays pure.
        if Self.turnRoutingEnabled {
            turnRoutedToolless = !(await routeNeedsDeviceTool(prompt: nextPrompt))
            Self.logger.notice("router: turn routed \(self.turnRoutedToolless ? "toolless" : "armed", privacy: .public) (#196)")
        } else {
            turnRoutedToolless = false
        }
        // #176: the turn's incoming attachments count. This runs BEFORE the
        // user message is appended, so the stored conversation doesn't know
        // about the image being sent right now.
        let hasImage = ConversationImageSource.hasImage(in: currentConversation, incoming: attachments)
        if let session {
            let offered = effectiveOfferedTools(hasImageInContext: hasImage)
            if offered.map(\.name) != sessionToolNames {
                Self.logger.notice("preparedSession: offered tool set changed for this turn — recreating the session (#176)")
            } else {
                let turns = Self.transcriptTurns(
                    from: currentConversation?.messages ?? [],
                    excludingClientMessageID: excludingClientMessageID
                )
                if await fitsContext(turns: turns, nextPrompt: nextPrompt, hasImageInContext: hasImage) {
                    return session
                }
                Self.logger.notice("preparedSession: context budget approached — condensing older turns (#26)")
            }
        }
        return await rebuildSession(
            attachments: attachments,
            excludingClientMessageID: excludingClientMessageID,
            forceCondense: false
        )
    }

    @discardableResult
    private func rebuildSession(
        attachments: [PendingAttachment],
        excludingClientMessageID: UUID?,
        forceCondense: Bool
    ) async -> LanguageModelSession {
        let turns = Self.transcriptTurns(
            from: currentConversation?.messages ?? [],
            excludingClientMessageID: excludingClientMessageID
        )
        // #176: one image-presence read drives BOTH the offered belt and the
        // instructions' capability list, so the persona can never advertise a
        // tool this session wasn't given.
        let hasImage = ConversationImageSource.hasImage(in: currentConversation, incoming: attachments)
        let blueprint = await sessionBlueprint(
            for: turns,
            hasImageInContext: hasImage,
            forceCondense: forceCondense
        )
        condensedMemory = blueprint.condensedMemory
        let fresh = makeSession(
            from: blueprint,
            offering: effectiveOfferedTools(hasImageInContext: hasImage)
        )
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

    private func sessionBlueprint(
        for turns: [TranscriptTurn],
        hasImageInContext: Bool,
        forceCondense: Bool
    ) async -> SessionBlueprint {
        let baseInstructions = effectiveInstructionsText(hasImageInContext: hasImageInContext)
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
        #if DEBUG
        // #196 `-noinstr` cells: NO instructions means no instructions even
        // when condensation fires — the memory block has nowhere to live,
        // so the condensed turns are DROPPED outright (kept in
        // `condensedMemory` for diagnostics only). Without this, the
        // preamble concatenation below would silently convert the cell
        // into an instructions-bearing session mid-conversation.
        // Production base instructions are never empty.
        if baseInstructions.isEmpty {
            Self.logger.notice("sessionBlueprint: \(split, privacy: .public) condensed turn(s) DROPPED — the -noinstr cell carries no instructions entry for memory (#196)")
            return SessionBlueprint(
                instructions: "",
                verbatimTurns: Array(turns[split...]),
                condensedMemory: memory
            )
        }
        #endif
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
    private func fitsContext(turns: [TranscriptTurn], nextPrompt: String, hasImageInContext: Bool) async -> Bool {
        let baseInstructions = effectiveInstructionsText(hasImageInContext: hasImageInContext)
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

    private func makeSession(from blueprint: SessionBlueprint, offering offered: [any Tool]) -> LanguageModelSession {
        #if DEBUG
        // #196: device A/B runs are self-labeling — Console shows which
        // cell built this session.
        Self.logger.notice("session shape: \(Self.activeSessionShape.rawValue, privacy: .public) — \(offered.count, privacy: .public) tool(s) registered (#196)")
        #endif
        let entries = Self.transcriptEntries(
            instructions: blueprint.instructions,
            verbatimTurns: blueprint.verbatimTurns
        )
        // Tools come from the #28 belt, gated for this turn by #176 (empty
        // until AppContainer installs the belt). The transcript's Instructions
        // entry carries no toolDefinitions — the session's `tools:` parameter
        // is the operative wiring; if tool-calling misbehaves on replayed
        // sessions, populate `Transcript.ToolDefinition`s here (flagged for
        // device verify).
        //
        // Recorded so `preparedSession` can tell when the live session's tool
        // list has gone stale against the current turn's context.
        sessionToolNames = offered.map(\.name)
        //
        // #30: both SystemLanguageModel and PrivateCloudComputeLanguageModel
        // conform to LanguageModel (iOS 27) — the session API is unified, so
        // the PCC tier is one argument, not a second code path.
        if Self.pccGrantConfirmed, activeTier == .privateCloud {
            return LanguageModelSession(
                model: PrivateCloudComputeLanguageModel(),
                tools: offered,
                transcript: Transcript(entries: entries)
            )
        }
        return LanguageModelSession(model: model, tools: offered, transcript: Transcript(entries: entries))
    }

    /// The transcript entries a rebuilt session replays: the instructions
    /// block — when there IS one: the #196 `-noinstr` cells carry none, and
    /// an empty string means the transcript simply has no instructions
    /// entry (production instructions are never empty, so the guard is
    /// inert outside the DEBUG instrument) — followed by the verbatim
    /// turns. Static + nonisolated so the no-instructions-entry constraint
    /// is unit-pinned.
    nonisolated static func transcriptEntries(
        instructions: String,
        verbatimTurns: [TranscriptTurn]
    ) -> [Transcript.Entry] {
        var entries: [Transcript.Entry] = []
        if !instructions.isEmpty {
            entries.append(.instructions(Transcript.Instructions(
                id: UUID().uuidString,
                segments: [.text(Transcript.TextSegment(id: UUID().uuidString, content: instructions))],
                toolDefinitions: []
            )))
        }
        for turn in verbatimTurns {
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
        return entries
    }

    // MARK: - Session-shape seam (#196, reworked from #194/176C)

    /// The tools this session should REGISTER, after the #176 turn gate. In
    /// DEBUG the #196 session-shape instrument can empty the belt (the
    /// `toolless` cell); Release compiles down to the production expression.
    private func effectiveOfferedTools(hasImageInContext hasImage: Bool) -> [any Tool] {
        // #196 (PROMOTED): a routed-toolless turn registers NO belt — the
        // full structural cure, not a call gate (nocall proved schemas in
        // context sustain the disclaimer tic on their own). Only ever true
        // when routing is enabled for this launch.
        if turnRoutedToolless { return [] }
        #if DEBUG
        guard Self.activeSessionShape.registersTools else { return [] }
        return Self.shapedBelt(
            from: DeviceToolBelt.offeredTools(from: tools, hasImageInContext: hasImage),
            shape: Self.activeSessionShape
        )
        #else
        return DeviceToolBelt.offeredTools(from: tools, hasImageInContext: hasImage)
        #endif
    }

    /// The generation options for this turn's respond/stream call. In DEBUG
    /// the #196 instrument reroutes through the shaped variant — identity
    /// for every cell but `armed-nocall`, which is the one cell whose
    /// treatment lives in the OPTIONS, not the belt or the text. This is
    /// the clean live-path seam the dispatch asked about: nocall works from
    /// the Diagnostics picker, not only in the battery. Release compiles
    /// down to the production expression.
    private func effectiveGenerationOptions() -> GenerationOptions {
        #if DEBUG
        return Self.shapedGenerationOptions(
            Self.chatGenerationOptions(for: activeTier),
            shape: Self.activeSessionShape
        )
        #else
        return Self.chatGenerationOptions(for: activeTier)
        #endif
    }

    /// The base instructions for this turn's session. In DEBUG the #196
    /// instrument reroutes through the shaped variants (the `armed` control
    /// cell delegates straight back to production); Release compiles down to
    /// the production expression.
    private func effectiveInstructionsText(hasImageInContext hasImage: Bool) -> String {
        // #196 (PROMOTED): a routed-toolless turn speaks the licensed bare
        // branch — the toolless-lic2 payload, the text that measured 60/60
        // content and clean on device.
        if turnRoutedToolless {
            return Self.instructionsText(
                deviceContext: Self.deviceContextLine(),
                hasTools: false,
                hasImageTools: hasImage,
                includeToollessLic2Clause: true
            )
        }
        #if DEBUG
        return Self.instructionsText(
            for: Self.activeSessionShape,
            deviceContext: Self.deviceContextLine(),
            hasTools: !tools.isEmpty,
            hasImageTools: hasImage
        )
        #else
        return Self.instructionsText(
            deviceContext: Self.deviceContextLine(),
            hasTools: !tools.isEmpty,
            hasImageTools: hasImage
        )
        #endif
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

    /// Real token usage from the OS: `LanguageModelSession.usage` (iOS 27).
    /// Usage is never estimated client-side (real-data-only; the CTX meter
    /// shows "—" rather than a guess), so nil here means "no session yet".
    /// #154: the iOS-26 `return nil` fallback this used to carry became
    /// unreachable when the floor moved to 27.0 — deleted, not preserved.
    private func currentTokenUsage() -> TokenUsage? {
        guard let session else { return nil }
        let usage = session.usage
        return TokenUsage(
            promptTokens: usage.input.totalTokenCount,
            completionTokens: usage.output.totalTokenCount,
            totalTokens: usage.totalTokenCount
        )
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

    /// The armed branch opens by licensing tool-free answering and creation
    /// (#176B/#194): with no such clause the on-device model treats the belt
    /// as its job description — every turn routes to a tool, "write a poem"
    /// deflects to reminders/weather, and one permission denial becomes every
    /// later turn's answer. Keep the "use tools" instruction scoped to the
    /// user's own data, never to general knowledge, and keep the recovery
    /// sentence: a failed tool is information about the tool, not the reply.
    ///
    /// 176C Part 2 (#194): the prose belt roster — the sentence enumerating
    /// the tools — was the convicted creative suppressor and is gone from the
    /// armed branch. The tools' native `Tool.description` metadata, already
    /// registered on the session, is the ONLY enumeration; the instructions
    /// therefore can never claim a tool the session wasn't given. The
    /// #176/#148 vision gate lives structurally in
    /// `DeviceToolBelt.offeredTools`; `hasImageTools` is kept for call-site
    /// stability but no longer varies this text.
    ///
    /// #196 measurement seams, the `includeBeltRoster` precedent: production
    /// call sites never pass either flag, so both production branches are
    /// byte-identical with the defaults. `includeCompositionLicensingSentence`
    /// inserts ONLY the composition-licensing sentence into the armed
    /// licensing clause (the `armed-complic` / `armed-fix` cells — the first
    /// battery's knowledge-denial finding: composing about world knowledge
    /// was refused as retrieval). `includeToollessLicensingClause` swaps ONLY
    /// the bare branch for its licensed form (the `toolless-lic` cell — the
    /// bare branch never received #176B's clause and measured 0/10 on
    /// composition with the purest denials). The first battery's
    /// `includeDirectnessSentence` (measured loser) and
    /// `includeHonestyAndRecoveryClauses` thermometer (measured NOT the
    /// source: 10/10 reminder grabs with the clauses gone) are retired.
    nonisolated static func instructionsText(
        deviceContext: String,
        date: Date = .now,
        hasTools: Bool = false,
        hasImageTools: Bool = false,
        includeCompositionLicensingSentence: Bool = false,
        includeToollessLicensingClause: Bool = false,
        includeToollessLic2Clause: Bool = false
    ) -> String {
        let day = date.formatted(date: .complete, time: .omitted)
        // #196 second battery: the composition-licensing sentence — the
        // `armed-complic` / `armed-fix` instruction treatment. "summarize
        // Norway" was refused as "can't access external knowledge" across
        // every tool cell: the model equates composing about world knowledge
        // with retrieval. This sentence licenses composition specifically.
        let composition = "You know a great deal about the world — places, people, history, ideas — and writing about it needs no internet, database, or lookup: composing from your own knowledge is not retrieval. "
        // #176's absorbing-state exits — the honesty sentence and the
        // recovery clause. Real jobs in production. (The armed-noneg
        // thermometer that lifted them is retired: measured NOT the tic's
        // source — 10/10 reminder grabs with them gone.)
        let honestyAndRecovery = " When a tool reports that a permission isn't granted or no data exists, relay that honestly — never invent a value. A failed or denied tool is never the answer to the user's question: answer as well as you can without that tool, and don't repeat a denial you've already given in this conversation."
        let capabilities: String
        if hasTools {
            capabilities = "Be direct, warm, and concise. Answering from what you know, writing and composing, summarizing, and ordinary conversation are your job and need no tool — facts you know are not guesses, and general knowledge is not device data. "
                + (includeCompositionLicensingSentence ? composition : "")
                + "Use the tools for the user's own data — their health, location, schedule, reminders, contacts, and past conversations — instead of guessing at it. Every action tool shows the user a confirmation card first; if they decline, accept it gracefully."
                + honestyAndRecovery
        } else if includeToollessLic2Clause {
            // #196 battery 4, toolless-lic2: the licensed bare branch plus
            // the two device-observed canary fixes — a math/facts license
            // (third battery: the licensing sentence covers writing, not
            // calculation; the bare branch denied arithmetic 20/20) and an
            // explicit output-format mandate in Apple's own template
            // convention (kills the degenerate `response_format` JSON
            // wrapper the licensed branch produced on 4/20 canary trials).
            capabilities = "Be direct, warm, and concise. Answering from what you know, writing and composing, summarizing, and ordinary conversation are your job — facts you know are not guesses, and writing about the world from your own knowledge needs no internet or lookup. Simple math and everyday factual questions you answer directly yourself. Reply in plain conversational prose — never JSON, XML, code blocks, or tool syntax unless the user asks for them. You have no internet access and no external tools in this mode; when you genuinely don't know something, say so plainly instead of guessing."
        } else if includeToollessLicensingClause {
            // #196 toolless-lic cell: the bare branch, licensed. Composition
            // licensed up front; the no-internet honesty caveat KEPT — the
            // branch must still forbid guessing at what the model truly
            // doesn't know (current events, the user's data).
            capabilities = "Be direct, warm, and concise. Answering from what you know, writing and composing, summarizing, and ordinary conversation are your job — facts you know are not guesses, and writing about the world from your own knowledge needs no internet or lookup. You have no internet access and no external tools in this mode; when you genuinely don't know something, say so plainly instead of guessing."
        } else {
            capabilities = """
            Be direct, warm, and concise. You have no internet access and no external tools in this mode — when you don't know something or can't do it on-device, say so plainly instead of guessing.
            """
        }
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

    /// Row form (#190): a stored session listed without decoding its
    /// transcript — the store's denormalized columns carry everything here.
    nonisolated static func sessionInfo(for summary: LocalSessionSummary, isActive: Bool) -> HermesSessionInfo {
        HermesSessionInfo(
            id: summary.id.uuidString,
            title: summary.title == Conversation.defaultTitle ? nil : summary.title,
            preview: summary.preview,
            model: onDeviceModelID,
            source: localSessionSource,
            messageCount: summary.messageCount,
            lastActive: summary.lastActivity,
            isActive: isActive
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
    /// #190B: the session's row exists but its stored transcript failed to
    /// decode — distinct from an unknown id so the failure the user sees
    /// tells the truth about what went wrong.
    case sessionUnreadable(String)

    var errorDescription: String? {
        switch self {
        case .unknownModel(let id):
            return "The on-device brain has no model \"\(id)\"."
        case .sessionNotFound(let id):
            return "No local conversation \"\(id)\" is stored on this device."
        case .sessionUnreadable:
            return "This conversation is stored on the device, but its transcript couldn't be read."
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
            let liveSession = await preparedSession(nextPrompt: prompt, attachments: attachments, excludingClientMessageID: clientMessageID)
            // Through the #196 seam like every live generation: with a
            // nocall-armed picker, even this held stream must not fire
            // tools mid-instrument.
            let options = effectiveGenerationOptions()
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

// MARK: - Session-shape instrument (#196, reworked from #194/176C — DEBUG builds only)

/// A/B cells for #196, third battery: STRUCTURAL decomposition of the armed
/// disease, after two batteries of prose treatments. Owen's verdict on the
/// second battery (n=20/cell, build 686d2e2): nothing on the armed path is
/// fixed — every prose cell edits sentences; none decomposed the structure.
/// The six battery cells (`batteryCells`) now isolate the armed session's
/// INGREDIENTS: instruction text (`armed-noinstr` / `toolless-noinstr`),
/// action-tool availability (`armed-readonly`), decode-time call ability
/// with schemas kept in context (`armed-nocall`, on the iOS-27
/// `GenerationOptions.toolCallingMode` control verified in Part 0), and
/// schema text with calling kept (`armed-noschema`, on
/// `Tool.includesSchemaInInstructions`). Battery-2's treatment cells stay in
/// the enum as HELD ship candidates (measured wins, held by Owen's verdict) —
/// picker-reachable for spot checks, no longer burning battery trials.
/// Armed by the `TALARIA_SESSION_SHAPE` launch environment or, at
/// a desk, the persisted Diagnostics override — following the
/// `UITEST_DUPID_PROBE` seam precedent: inert in every normal run, compiled
/// out of Release entirely. The selector touches session construction only
/// (`effectiveOfferedTools` / `effectiveInstructionsText` /
/// `effectiveGenerationOptions`).
extension LocalChatBackend {

    // CaseIterable (#196 third battery): lets the test pins iterate
    // `allCases` minus the treated shapes, so a future cell can never
    // dodge the identity pins by not being in an enumerated list.
    enum SessionShape: String, CaseIterable {
        /// Production behavior — the in-run control; both mechanisms live
        /// here (first battery: haiku 6/10, 8/10 reminder grabs, Norway
        /// 4/10 with 0 clean opens).
        case armed
        /// Production instructions, belt with ONLY `createReminder`'s
        /// description scoped against task-verb confusion
        /// (`ReminderCreateTool.scopedDescription196`). Fix the tool, not
        /// the prompt. Target: grabs ~8/10 → ~0.
        case armedRemfix = "armed-remfix"
        /// Production belt, instructions PLUS the composition-licensing
        /// sentence in the licensing clause. Target: Norway content up at
        /// unchanged haiku.
        case armedComplic = "armed-complic"
        /// Both treatments together — the actual ship candidate, measured
        /// in the same run so an interaction effect can't hide behind two
        /// individually-clean cells.
        case armedFix = "armed-fix"
        /// The production tool-less branch with tools unregistered — the far
        /// control (first battery: haiku 10/10 clean, Norway 0/10).
        case toolless
        /// The tool-less branch rebuilt with the licensing clause the bare
        /// branch never received in #176B, honesty caveat kept.
        case toollessLic = "toolless-lic"
        /// Third battery (#196 decomposition): production belt, NO
        /// instructions. Vs `armed`, isolates whether OUR instruction text
        /// is a net cause of the armed disease or the belt registration
        /// itself is — the fork every future fix routes on.
        case armedNoinstr = "armed-noinstr"
        /// No belt, no instructions — the in-app replica of the Shortcuts
        /// "Use Model" probe that wrote haiku happily on this same phone.
        /// Vs `toolless`, prices the bare branch's prose (which denies
        /// arithmetic 20/20 — text or model?).
        case toollessNoinstr = "toolless-noinstr"
        /// Production instructions; belt MINUS the three action tools
        /// (grabs die structurally — no tool to grab). If haiku CLEAN
        /// recovers toward toolless levels, the ship path is extending
        /// #176 availability gating to action tools.
        case armedReadonly = "armed-readonly"
        /// Production instructions AND belt, but every call runs with
        /// `toolCallingMode: .disallowed` (iOS 27): schemas stay in
        /// context, calling is impossible. The per-turn-routing ship
        /// path's proof cell.
        case armedNocall = "armed-nocall"
        /// Production instructions; the three action tools carry
        /// `includesSchemaInInstructions = false` — still callable,
        /// schemas hidden. Can the model grab what it cannot see? The
        /// semantics are undocumented; surprising results are findings,
        /// not bugs.
        case armedNoschema = "armed-noschema"
        /// Battery 4 (#196 cure lane): the licensed bare branch plus the
        /// two device-observed canary fixes — math/facts license and an
        /// output-format mandate (Apple template convention). The routed
        /// architecture's non-tool payload.
        case toollessLic2 = "toolless-lic2"
        /// Battery 4: the production candidate. A per-turn guided-generation
        /// router (few-shot, greedy — 80/80 on the Mac-host probe grid)
        /// decides whether the turn needs the device; tool turns get the
        /// production armed session, everything else gets `toolless-lic2`.
        /// WWDC26 session 242's sanctioned shape: tools withheld where
        /// "known to be irrelevant," decided contextually.
        case armedRouted = "armed-routed"

        /// Whether this cell hands the session a tool belt at all.
        /// `armedRouted` returns true — it CAN register; the per-turn
        /// router decides whether a given turn actually does.
        var registersTools: Bool {
            switch self {
            case .armed, .armedRemfix, .armedComplic, .armedFix,
                 .armedNoinstr, .armedReadonly, .armedNocall, .armedNoschema,
                 .armedRouted:
                return true
            case .toolless, .toollessLic, .toollessNoinstr, .toollessLic2:
                return false
            }
        }

        /// Whether this cell's belt carries the #196-scoped
        /// `createReminder` description (the remfix treatment).
        var usesScopedReminderDescription: Bool {
            switch self {
            case .armedRemfix, .armedFix:
                return true
            case .armed, .armedComplic, .toolless, .toollessLic,
                 .armedNoinstr, .toollessNoinstr, .armedReadonly, .armedNocall, .armedNoschema,
                 .toollessLic2, .armedRouted:
                return false
            }
        }

        /// Whether this cell hands the session instructions at all. The two
        /// `-noinstr` cells pass NOTHING: the battery builds the session
        /// with the `instructions:` parameter omitted entirely (resolving
        /// to the SDK's `Instructions? = nil` designated convenience init),
        /// and the live path builds a transcript with no instructions
        /// entry. `instructionsText(for:)` returns the empty string for
        /// them only so its switch stays exhaustive.
        var passesInstructions: Bool {
            switch self {
            case .armedNoinstr, .toollessNoinstr:
                return false
            case .armed, .armedRemfix, .armedComplic, .armedFix,
                 .toolless, .toollessLic, .armedReadonly, .armedNocall, .armedNoschema,
                 .toollessLic2, .armedRouted:
                return true
            }
        }
    }

    /// The belt each cell registers (#196): identity for every cell except
    /// the structural treatments —
    /// - remfix cells: ONLY the `createReminder` description string is
    ///   swapped (same instances, same order, same relay and gate);
    /// - `armed-readonly`: the three action tools are removed outright
    ///   (the #176 availability-gating mechanism, extended — filter by
    ///   concrete type so belt order never matters);
    /// - `armed-noschema`: the three action tools are COPIES with
    ///   `includesSchemaInInstructions` flipped off — still registered,
    ///   still callable, schemas hidden from the instructions. Read tools
    ///   untouched in both.
    nonisolated static func shapedBelt(from tools: [any Tool], shape: SessionShape) -> [any Tool] {
        switch shape {
        case .armedRemfix, .armedFix:
            return tools.map { tool in
                if var reminder = tool as? ReminderCreateTool {
                    reminder.description = ReminderCreateTool.scopedDescription196
                    return reminder
                }
                return tool
            }
        case .armedReadonly:
            return tools.filter {
                !($0 is ReminderCreateTool || $0 is CalendarEventTool || $0 is AlarmTool)
            }
        case .armedNoschema:
            return tools.map { tool in
                if var reminder = tool as? ReminderCreateTool {
                    reminder.includesSchemaInInstructions = false
                    return reminder
                }
                if var event = tool as? CalendarEventTool {
                    event.includesSchemaInInstructions = false
                    return event
                }
                if var alarm = tool as? AlarmTool {
                    alarm.includesSchemaInInstructions = false
                    return alarm
                }
                return tool
            }
        case .armed, .armedComplic, .toolless, .toollessLic, .armedNoinstr, .toollessNoinstr, .armedNocall,
             .toollessLic2, .armedRouted:
            // armedRouted's belt treatment happens per turn in the routing
            // gates, never here — shapedBelt stays the identity for it.
            return tools
        }
    }

    /// The generation options each cell runs with (#196 third battery):
    /// identity for every cell except `armed-nocall`, which sets the
    /// iOS-27 `toolCallingMode: .disallowed` — schemas stay in context,
    /// decode-time tool calling is impossible. Production options carry no
    /// override (pinned in `LocalChatBackendTests`), so `armed` remains
    /// byte-identical production.
    nonisolated static func shapedGenerationOptions(_ options: GenerationOptions, shape: SessionShape) -> GenerationOptions {
        guard shape == .armedNocall else { return options }
        var shaped = options
        shaped.toolCallingMode = .disallowed
        return shaped
    }

    /// Read once per process — the cells are launch-scoped, so a mid-run env
    /// mutation can never make one conversation's session builds disagree.
    static let activeSessionShape: SessionShape = {
        if let raw = ProcessInfo.processInfo.environment["TALARIA_SESSION_SHAPE"],
           let shape = SessionShape(rawValue: raw) {
            return shape
        }
        // Desk A/B (#196, folded from the 176C side branch): a DEBUG-only
        // persisted override so the cells are reachable from a home-screen
        // launch — OTA installs cannot carry launch environment, and the
        // phone is unreachable by Xcode over the tailnet. Read ONCE here like
        // the env path, so the launch-scoped invariant above holds: the
        // Diagnostics picker takes effect on the NEXT launch (force-quit
        // between cells is the A/B protocol anyway). Launch env wins when
        // both are set. A retired cell name still persisted on a phone
        // fails to parse and falls through to the default — production, by
        // design.
        if let raw = UserDefaults.standard.string(forKey: "debug.sessionShape"),
           let shape = SessionShape(rawValue: raw) {
            return shape
        }
        // The default is the PRODUCTION shape. Pre-promotion this was
        // `.armed`; since the 2026-07-28 battery-4 verdict the production
        // path routes, so an untouched Debug install behaves like Release.
        return .armedRouted
    }()

    /// The instructions each cell hands the session. `hasTools` /
    /// `hasImageTools` are the PRODUCTION inputs for this turn; the shape
    /// overrides from there, so `armed` is provably the production text.
    nonisolated static func instructionsText(
        for shape: SessionShape,
        deviceContext: String,
        date: Date = .now,
        hasTools: Bool = false,
        hasImageTools: Bool = false
    ) -> String {
        switch shape {
        case .armed, .armedRemfix, .armedReadonly, .armedNocall, .armedNoschema:
            // armed-remfix, and the third battery's belt/options
            // treatments (readonly / nocall / noschema), are STRUCTURAL:
            // their instructions are the production text verbatim — the
            // seams live in `shapedBelt` / `shapedGenerationOptions`.
            return instructionsText(
                deviceContext: deviceContext, date: date,
                hasTools: hasTools, hasImageTools: hasImageTools
            )
        case .armedNoinstr, .toollessNoinstr:
            // These cells pass NO instructions (`passesInstructions ==
            // false` — callers omit the parameter / the transcript entry).
            // Empty keeps this switch exhaustive and the live context
            // budget honest at zero.
            return ""
        case .armedComplic, .armedFix:
            return instructionsText(
                deviceContext: deviceContext, date: date,
                hasTools: hasTools, hasImageTools: hasImageTools,
                includeCompositionLicensingSentence: true
            )
        case .toolless:
            return instructionsText(
                deviceContext: deviceContext, date: date,
                hasTools: false, hasImageTools: hasImageTools
            )
        case .toollessLic:
            return instructionsText(
                deviceContext: deviceContext, date: date,
                hasTools: false, hasImageTools: hasImageTools,
                includeToollessLicensingClause: true
            )
        case .toollessLic2:
            return instructionsText(
                deviceContext: deviceContext, date: date,
                hasTools: false, hasImageTools: hasImageTools,
                includeToollessLic2Clause: true
            )
        case .armedRouted:
            // The ARMED half of the routed pair — the toolless half is
            // resolved by the routing gates (`effectiveInstructionsText`
            // consults the turn's route and returns the `toollessLic2`
            // text instead when the turn needs no tool).
            return instructionsText(
                deviceContext: deviceContext, date: date,
                hasTools: hasTools, hasImageTools: hasImageTools
            )
        }
    }
}
#endif

// MARK: - Per-turn tool-intent routing (#196, PROMOTED to production 2026-07-28)
//
// The production session architecture as of the battery-4 device verdict:
// every turn is classified by a few-shot guided-generation router before the
// session is built. Words-only turns get NO belt and the `toolless-lic2`
// instruction text (device: 60/60 content AND clean across the three #196
// prompts); device turns get the production armed session, byte-identical to
// the pre-promotion path. Router accuracy on device: 200/200, both
// directions; fail-safe on error is ARMED. WWDC26 session 242 sanctions the
// shape: tools withheld where "known to be irrelevant," decided contextually.

extension LocalChatBackend {

    /// Whether this launch routes turns. Production truth: always. DEBUG:
    /// only the `armed-routed` shape routes, so every legacy A/B cell
    /// (including the `armed` control) stays pure.
    static var turnRoutingEnabled: Bool {
        #if DEBUG
        return activeSessionShape == .armedRouted
        #else
        return true
        #endif
    }

    /// Few-shot router instructions — the ONLY framing that cleared the
    /// Mac-host probe grid (200/200 at n=20), reconfirmed 200/200 on the
    /// 27b4 device model. The guide-only framing misrouted EVERY creative
    /// verb to the device — the #196 task-verb confusion lives in
    /// classification too — and the flipped-polarity framing collapsed to
    /// always-true. Few-shot examples are Apple's own template convention.
    /// Pinned by tests: this text is a measured artifact, not prose.
    nonisolated static let toolIntentRouterInstructions = """
    You route requests for a phone assistant. Decide if a request needs the device or is answerable with words alone.
    Examples:
    "Write a haiku about rain" -> needsDeviceTool: false
    "Summarize the French Revolution in 50 words" -> needsDeviceTool: false
    "What's 15% of 80?" -> needsDeviceTool: false
    "Remind me to call Shelley tomorrow" -> needsDeviceTool: true
    "How did I sleep last night?" -> needsDeviceTool: true
    "What's the weather?" -> needsDeviceTool: true
    """

    /// Greedy + tiny cap: routing must be deterministic and fast (~0.6s
    /// measured on device); guided generation constrains decode to the
    /// `ToolIntentRoute` shape, so the router can never ramble.
    nonisolated static var toolIntentRouterOptions: GenerationOptions {
        GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 64)
    }

    /// Classifies one turn. Fail-safe: any error routes to the ARMED
    /// session — full production behavior, tools available.
    func routeNeedsDeviceTool(prompt: String) async -> Bool {
        let session = LanguageModelSession(
            model: model,
            instructions: Instructions(Self.toolIntentRouterInstructions)
        )
        do {
            let route = try await session.respond(
                to: Prompt("Request: \(prompt)"),
                generating: ToolIntentRoute.self,
                options: Self.toolIntentRouterOptions
            ).content
            return route.needsDeviceTool
        } catch {
            Self.logger.notice("router: classification failed — failing safe to armed (\(String(String(describing: error).prefix(80)), privacy: .public)) (#196)")
            return true
        }
    }
}

/// The route classification for one turn. File scope: the `@Generable`
/// macro expansion needs a non-nested, non-private type. The @Guide text is
/// a measured artifact (pinned) — it carries the device-data/device-action
/// enumeration AND the explicit words-only enumeration.
@Generable
struct ToolIntentRoute {
    @Guide(description: "True only when the request needs the user's device data (health, location, weather, calendar, reminders, contacts, past chats) or a device action (create a reminder, calendar event, or alarm). Writing, poems, summaries, math, facts, and conversation are false — they need nothing from the device.")
    var needsDeviceTool: Bool
}

#if DEBUG
// MARK: - #196 rate battery (Diagnostics-triggered, DEBUG builds only)

extension LocalChatBackend {
    /// The fourth battery's cell list (#196 cure lane): control, the two
    /// payload candidates, and the routed production candidate. Battery-3's
    /// decomposition cells and battery-2's treatment cells stay in the enum
    /// — picker-reachable, no longer burning trials.
    nonisolated static let batteryCells: [SessionShape] = [
        .armed, .toollessLic, .toollessLic2, .armedRouted,
    ]

    /// #196 results-page lane: structured run capture, ADDITIVE to the
    /// emit sinks below — full reply texts, tool details, routes, and
    /// latencies persist per run for the in-app results view + export
    /// (Console-less work sessions). Static like the relay's trial tag:
    /// the instrument is one global surface. The store is exposed
    /// separately because the results screens read and delete through it.
    static let batteryRunStore = BatteryRunStore()
    static let batteryRecorder = BatteryRunRecorder(store: batteryRunStore)

    /// Battery lines go to THREE sinks: os_log (Console.app, the desk
    /// path), stdout (what `devicectl device process launch --console`
    /// bridges — flushed per line, because piped stdout is block-buffered
    /// and a SIGKILL'd run would otherwise capture NOTHING), and an
    /// append-only file in the app container (pullable via
    /// `devicectl device copy from … --domain-type appDataContainer` even
    /// after the process dies — the locked-screen background kill left a
    /// zero-byte capture on 2026-07-28's first headless attempt).
    static func batteryEmit(_ line: String) {
        print(line)
        fflush(stdout)
        logger.notice("\(line, privacy: .public)")
        batteryFileSink(line)
    }

    /// The file sink's location, exposed for the results page's share
    /// button (#200 crash diagnostics): the log survives a crashed run,
    /// and with the phone off-LAN there is no other way to get it out —
    /// Documents isn't Files-app-exposed and devicectl needs USB/LAN.
    static var batteryCaptureLogURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("battery-capture.log")
    }

    /// The container file sink for `batteryEmit` — Documents/battery-capture.log,
    /// appended with a trailing newline per line. Failures are silent by
    /// design (the other two sinks still carry the line).
    private static func batteryFileSink(_ line: String) {
        guard let url = batteryCaptureLogURL else { return }
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    /// Third-battery instrument (#196 decomposition): six STRUCTURAL cells
    /// × three prompts × `trials` generations in-process, one classifiable
    /// notice line per trial. Deliberately bypasses `activeSessionShape`
    /// for instructions, belt, AND options — each session is parameterized
    /// explicitly (the first battery's belt still consulted the live
    /// selector; a non-armed phone selection would have contaminated every
    /// tool cell), so the launch-scoped invariant is untouched and no
    /// force-quit cycling is needed. Tools EXECUTE during tool-registered
    /// cells (real reads) — that is the point — and every tool start logs
    /// through `ToolEventRelay.batteryTrialTag`. "What's 2+2?" is the
    /// always-pass canary — though the second battery discovered the BARE
    /// branch denies arithmetic (toolless canary 0/20), so the canary is
    /// itself a measurement in the no-instructions cells.
    func runShapeBattery(trials: Int) async {
        let prompts: [(tag: String, text: String)] = [
            ("canary", "What's 2+2?"),
            ("haiku", "Write a haiku about sledding"),
            ("norway", "write a 50 word summary about Norway"),
        ]
        let cells = Self.batteryCells
        Self.batteryEmit("battery: START trials=\(trials) cells=\(cells.count) prompts=\(prompts.count) (#196)")
        Self.batteryRecorder.beginRun(trialsPerCell: trials, cells: cells.map(\.rawValue))
        for shape in cells {
            let belt: [any Tool] = shape.registersTools
                ? Self.shapedBelt(from: DeviceToolBelt.offeredTools(from: tools, hasImageInContext: false), shape: shape)
                : []
            let instructions = Self.instructionsText(
                for: shape,
                deviceContext: Self.deviceContextLine(),
                hasTools: !belt.isEmpty,
                hasImageTools: false
            )
            for (tag, prompt) in prompts {
                for trial in 1...trials {
                    // Tag set BEFORE the trial so every tool start inside it
                    // logs attributably. A post-guillotine straggler can
                    // mislabel into the following trial — rare and visible
                    // (it trails a TIMEOUT line), acceptable for an
                    // instrument.
                    ToolEventRelay.batteryTrialTag = "shape=\(shape.rawValue) p=\(tag) t=\(trial)"
                    // Trial clock starts here, so a routed trial's latency
                    // includes its router generation — the real turn cost.
                    Self.batteryRecorder.beginTrial()
                    // #196 battery 4: armed-routed classifies each trial's
                    // prompt first, then builds the routed session — the
                    // toolless-lic2 payload, or the full armed construction.
                    var trialBelt = belt
                    var trialInstructions = instructions
                    if shape == .armedRouted {
                        let needsTool = await routeNeedsDeviceTool(prompt: prompt)
                        Self.batteryEmit("battery: route=\(needsTool ? "armed" : "toolless") shape=\(shape.rawValue) p=\(tag) t=\(trial)")
                        Self.batteryRecorder.recordRoute(needsTool ? "armed" : "toolless")
                        if !needsTool {
                            trialBelt = []
                            trialInstructions = Self.instructionsText(
                                for: .toollessLic2,
                                deviceContext: Self.deviceContextLine(),
                                hasTools: false,
                                hasImageTools: false
                            )
                        }
                    }
                    // The `-noinstr` cells omit the `instructions:` argument
                    // entirely — the SDK's `Instructions? = nil` designated
                    // convenience init, its native no-instructions form (the
                    // `String?` overload is @_disfavoredOverload) — never an
                    // empty string, which would still inject an instructions
                    // block into the prompt.
                    let session = shape.passesInstructions
                        ? LanguageModelSession(model: model, tools: trialBelt, instructions: Instructions(trialInstructions))
                        : LanguageModelSession(model: model, tools: trialBelt)
                    // Identity except armed-nocall (`toolCallingMode:
                    // .disallowed` per call — the schemas stay in context).
                    let options = Self.shapedGenerationOptions(Self.chatGenerationOptions(for: activeTier), shape: shape)
                    await executeBatteryTrial(session: session, options: options,
                                              shape: shape.rawValue, promptTag: tag,
                                              prompt: prompt, trial: trial)
                }
            }
        }
        ToolEventRelay.batteryTrialTag = nil
        Self.batteryEmit("battery: DONE (#196)")
        Self.batteryRecorder.endRun()
    }

    /// Knowledge-denial forms observed in the first battery — matched
    /// anywhere in the reply, unlike the prefix-only `cant` flag which
    /// missed "I don't have access…" openings entirely. Shared by every
    /// battery so the heuristics can never drift between instruments.
    nonisolated static let batteryDenialPatterns = [
        "can't access", "can\u{2019}t access", "cannot access",
        "don't have access", "don\u{2019}t have access", "do not have access",
        "no access", "external knowledge", "external database", "external data",
        "no internet", "internet access", "real-time",
    ]

    /// One battery trial: respond, guillotine at 35s, classify, emit, and
    /// record — the shared executor behind the shape battery (#196) and the
    /// action battery (#200). Byte-identical lines to the pre-extraction
    /// emit path; callers set the trial tag and begin the recorder trial
    /// BEFORE calling.
    private func executeBatteryTrial(session: LanguageModelSession, options: GenerationOptions,
                                     shape: String, promptTag: String,
                                     prompt: String, trial: Int) async {
        // 35s guillotine per trial: backstop only now that the confirmation
        // gate auto-resolves — a wedged trial still logs and the run still
        // moves.
        let respondTask = Task { try await session.respond(to: Prompt(prompt), options: options).content }
        let timeoutTask = Task { try? await Task.sleep(for: .seconds(35)); respondTask.cancel() }
        do {
            let text = try await respondTask.value
            timeoutTask.cancel()
            let flat = text.replacingOccurrences(of: "\n", with: " / ")
            let lower = text.lowercased()
            let cant = lower.hasPrefix("i can\u{2019}t") || lower.hasPrefix("i cant") || lower.hasPrefix("i cannot") || lower.hasPrefix("i can not") || lower.hasPrefix("i can't")
            let denial = Self.batteryDenialPatterns.contains { lower.contains($0) }
            Self.batteryEmit("battery: shape=\(shape) p=\(promptTag) t=\(trial) cant=\(cant) denial=\(denial) chars=\(text.count) text=\(String(flat.prefix(500)))")
            Self.batteryRecorder.endTrial(shape: shape, prompt: promptTag, trial: trial,
                                          text: text, cant: cant, denial: denial)
        } catch is CancellationError {
            timeoutTask.cancel()
            Self.batteryEmit("battery: shape=\(shape) p=\(promptTag) t=\(trial) TIMEOUT — wedged trial guillotined")
            Self.batteryRecorder.endTrialTimeout(shape: shape, prompt: promptTag, trial: trial)
        } catch {
            timeoutTask.cancel()
            Self.batteryEmit("battery: shape=\(shape) p=\(promptTag) t=\(trial) ERROR=\(String(String(describing: error).prefix(200)))")
            Self.batteryRecorder.endTrialError(shape: shape, prompt: promptTag, trial: trial,
                                               error: String(describing: error))
        }
    }

    /// #200B: the action battery's treatment-cell dimension. The FILED
    /// #200 table (remind 0/20, 15 list-stalls) routes treatment as
    /// MEASURED CELLS per the #196 remfix precedent — nothing ships to
    /// production without a battery verdict.
    enum ActionBatteryCell: String, CaseIterable {
        /// Production control — belt identity.
        case armed
        /// `ReminderCreateToolGuidefix` copy: de-stalled @Guide texts on
        /// the optional fields, production description.
        case armedGuidefix = "armed-guidefix"
        /// Production struct, `destalledDescription200` — the remfix
        /// description-var mechanism.
        case armedToolfix = "armed-toolfix"
        /// Both texts together — interaction effects can't hide behind
        /// two individually-clean cells (#196 battery-2 lesson).
        case armedBothfix = "armed-bothfix"
    }

    /// The belt each treatment cell registers: identity except the
    /// reminder tool, which swaps text (toolfix), struct (guidefix), or
    /// both (bothfix). Same instances and order for every other tool.
    nonisolated static func destallBelt(from tools: [any Tool], cell: ActionBatteryCell) -> [any Tool] {
        switch cell {
        case .armed:
            return tools
        case .armedGuidefix:
            return tools.map { tool in
                if let reminder = tool as? ReminderCreateTool {
                    return ReminderCreateToolGuidefix(relay: reminder.relay, confirmations: reminder.confirmations)
                }
                return tool
            }
        case .armedToolfix:
            return tools.map { tool in
                if var reminder = tool as? ReminderCreateTool {
                    reminder.description = ReminderCreateTool.destalledDescription200
                    return reminder
                }
                return tool
            }
        case .armedBothfix:
            return tools.map { tool in
                if let reminder = tool as? ReminderCreateTool {
                    return ReminderCreateToolGuidefix(
                        description: ReminderCreateTool.destalledDescription200,
                        relay: reminder.relay, confirmations: reminder.confirmations
                    )
                }
                return tool
            }
        }
    }

    /// #200 action-path battery: does an APPROPRIATE create go through?
    /// Single-turn create prompts × `trials` per cell, ARMED production
    /// construction — the armed-routed armed branch, whose belt,
    /// instructions, and options are all identity with `.armed` (verified
    /// against `shapedBelt` / `instructionsText` / `shapedGenerationOptions`).
    /// NO per-trial routing: the router probe already measured these
    /// prompts as correctly ROUTED; this measures what the armed session
    /// does next. The launcher arms auto-ACCEPT, so appropriate creates
    /// EXECUTE — real EventKit/AlarmKit writes, every artifact
    /// marker-tagged by the gate — and the teardown reaps everything
    /// marked BEFORE the DONE line, so the phone ends the run clean.
    /// Protocol: run with Reminders/Calendar granted.
    ///
    /// #200B: `cells` swaps the reminder tool's TEXT per cell
    /// (`destallBelt`); `includeGrabCanary` adds the #196 haiku prompt —
    /// the de-stall texts push toward immediate creation, so the grab
    /// disease is the collateral to measure (a grab creates a real marked
    /// reminder under auto-accept; the reap deletes it; the confirm line
    /// makes it countable). Defaults preserve the FILED #200 protocol
    /// byte-for-byte.
    func runActionBattery(trials: Int, cells: [ActionBatteryCell] = [.armed],
                          includeGrabCanary: Bool = false) async {
        var prompts: [(tag: String, text: String)] = [
            ("remind", "Remind me to test Talaria at 4:30pm"),
            ("alarm", "Set an alarm for 6:30"),
            ("calendar", "Put lunch with Sam on my calendar Friday at noon"),
        ]
        if includeGrabCanary {
            prompts.append(("haiku", "Write a haiku about sledding"))
        }
        let shape = SessionShape.armedRouted
        let base = Self.shapedBelt(
            from: DeviceToolBelt.offeredTools(from: tools, hasImageInContext: false),
            shape: shape
        )
        let instructions = Self.instructionsText(
            for: shape,
            deviceContext: Self.deviceContextLine(),
            hasTools: !base.isEmpty,
            hasImageTools: false
        )
        Self.batteryEmit("battery: START trials=\(trials) cells=\(cells.count) prompts=\(prompts.count) (#200)")
        Self.batteryRecorder.beginRun(trialsPerCell: trials, cells: cells.map(\.rawValue), kind: "action")
        for cell in cells {
            let belt = Self.destallBelt(from: base, cell: cell)
            for (tag, prompt) in prompts {
                for trial in 1...trials {
                    ToolEventRelay.batteryTrialTag = "shape=\(cell.rawValue) p=\(tag) t=\(trial)"
                    // Live-only BEGIN line (never rendered from records): if
                    // the run dies inside this trial, the capture log's last
                    // BEGIN names it exactly.
                    Self.batteryEmit("battery: BEGIN shape=\(cell.rawValue) p=\(tag) t=\(trial)")
                    Self.batteryRecorder.beginTrial()
                    let session = LanguageModelSession(model: model, tools: belt, instructions: Instructions(instructions))
                    let options = Self.shapedGenerationOptions(Self.chatGenerationOptions(for: activeTier), shape: shape)
                    await executeBatteryTrial(session: session, options: options,
                                              shape: cell.rawValue, promptTag: tag,
                                              prompt: prompt, trial: trial)
                }
            }
        }
        ToolEventRelay.batteryTrialTag = nil
        let reapSummary = await reapBatteryArtifacts()
        Self.batteryEmit("battery: REAP \(reapSummary) (#200)")
        Self.batteryRecorder.recordReapSummary(reapSummary)
        Self.batteryEmit("battery: DONE (#200)")
        Self.batteryRecorder.endRun()
    }

    /// #200B one-tap wrapper: all four treatment cells × four prompts
    /// (grab canary included) — 16 × trials generations.
    func runDestallBattery(trials: Int) async {
        await runActionBattery(trials: trials, cells: ActionBatteryCell.allCases, includeGrabCanary: true)
    }

    /// #200 teardown: delete every [T27-battery]-marked reminder and
    /// calendar event, and cancel every battery-tracked alarm. Reminders
    /// and events are found by marker match on their titles (idempotent —
    /// leftovers from a crashed earlier run get swept too); alarms come
    /// from `AlarmService.batteryScheduledAlarmIDs`, because AlarmKit's
    /// `Alarm` carries no label back on enumeration. Returns the REAP
    /// accounting in the export's words. Missing read access shows up as
    /// skips, never as a silent zero.
    private func reapBatteryArtifacts() async -> String {
        let marker = ToolConfirmationCenter.batteryArtifactMarker
        let store = EKEventStore()
        var failures = 0

        // Step markers (live-only): all four 2026-07-28 action-battery
        // crashes died somewhere in THIS function (records complete
        // through the last trial, never sealed) — the capture log's last
        // REAP-STEP line names the killing sub-step.
        Self.batteryEmit("battery: REAP-STEP reminders begin (#200)")

        // Reminders: enumeration needs full access. Snapshot Sendable
        // identifiers inside the completion handler (EKReminder must not
        // cross the continuation boundary), then re-fetch each by id to
        // remove it.
        //
        // The completion MUST be @Sendable: EventKit invokes it on its
        // private queue (com.apple.eventkit.reminders.search), and a plain
        // closure formed here — a MainActor context — inherits MainActor
        // isolation, which the 27b4 DEVICE runtime dynamically enforces:
        // dispatch_assert_queue_fail → brk 1. That trap was ALL FOUR
        // 2026-07-28 action-battery crashes (.ips 12:18 + 12:39, faulting
        // thread on the eventkit queue, this closure on the stack). The
        // sim runtime does not enforce the check — the probe passed while
        // every device run died. @Sendable severs the actor-context
        // inheritance; ReminderReadTool's twin closure never needed it
        // because Tool.call is nonisolated.
        var remindersLine = "reminders=skipped(no-access)"
        if EKEventStore.authorizationStatus(for: .reminder) == .fullAccess {
            let predicate = store.predicateForIncompleteReminders(
                withDueDateStarting: nil, ending: nil, calendars: nil
            )
            let markedIDs: [String] = await withCheckedContinuation { continuation in
                store.fetchReminders(matching: predicate) { @Sendable found in
                    let ids = (found ?? [])
                        .filter { ($0.title ?? "").contains(marker) }
                        .map(\.calendarItemIdentifier)
                    continuation.resume(returning: ids)
                }
            }
            Self.batteryEmit("battery: REAP-STEP reminders fetched marked=\(markedIDs.count) (#200)")
            var removed = 0
            for id in markedIDs {
                guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
                    failures += 1
                    continue
                }
                do {
                    try store.remove(reminder, commit: true)
                    removed += 1
                } catch {
                    failures += 1
                }
            }
            remindersLine = "reminders=\(removed)"
        }
        Self.batteryEmit("battery: REAP-STEP events begin (#200)")

        // Events: enumeration also needs full access (write-only can save
        // but never read, so it cannot reap). WRITABLE calendars only, and
        // a −1d…+14d window: battery events are always near-future ("Friday
        // at noon" is days out) and can only live where a save landed —
        // birthday/subscribed/holiday calendars cannot hold them. (This
        // narrowing was first shipped as a crash-lane suspect; the .ips
        // later proved the crash was the reminders completion's isolation
        // trap above and this step never even ran. The narrowing stays as
        // scope-correctness: it is the minimal honest query for what the
        // reap needs.) events(matching:) here is SYNCHRONOUS on the
        // calling thread — no cross-queue closure, no isolation hazard.
        var eventsLine = "events=skipped(no-access)"
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess {
            let start = Date().addingTimeInterval(-1 * 86_400)
            let end = Date().addingTimeInterval(14 * 86_400)
            let writable = store.calendars(for: .event).filter(\.allowsContentModifications)
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: writable)
            let marked = store.events(matching: predicate).filter { ($0.title ?? "").contains(marker) }
            Self.batteryEmit("battery: REAP-STEP events fetched marked=\(marked.count) (#200)")
            var removed = 0
            for event in marked {
                do {
                    try store.remove(event, span: .thisEvent, commit: true)
                    removed += 1
                } catch {
                    failures += 1
                }
            }
            eventsLine = "events=\(removed)"
        }
        Self.batteryEmit("battery: REAP-STEP alarms begin (#200)")

        let alarmReap = AlarmService.reapBatteryAlarms()
        failures += alarmReap.failed
        Self.batteryEmit("battery: REAP-STEP alarms done cancelled=\(alarmReap.cancelled) failed=\(alarmReap.failed) (#200)")

        return "\(remindersLine) \(eventsLine) alarms=\(alarmReap.cancelled) failures=\(failures)"
    }

    /// #196 battery 4: on-device router-accuracy probe — ten probes
    /// (five words-only, five device) × `trials`, one `router:` line per
    /// probe. The Mac-host grid measured 200/200; this measures the
    /// 27-beta device model, which is the one that ships.
    func runRouterProbe(trials: Int) async {
        let probes: [(text: String, expected: Bool)] = [
            ("What's 2+2?", false),
            ("Write a haiku about sledding", false),
            ("write a 50 word summary about Norway", false),
            ("Tell me a joke about penguins", false),
            ("Write a poem for my mom's birthday", false),
            ("Remind me to buy milk tomorrow at 9am", true),
            ("What's the weather like right now?", true),
            ("Set an alarm for 6:30", true),
            ("How many steps have I taken today?", true),
            ("Do I have anything on my calendar Friday?", true),
        ]
        Self.batteryEmit("router: PROBE START trials=\(trials) probes=\(probes.count) (#196)")
        Self.batteryRecorder.beginRun(trialsPerCell: trials, cells: [])
        for probe in probes {
            var correct = 0
            for _ in 1...trials {
                if await routeNeedsDeviceTool(prompt: probe.text) == probe.expected { correct += 1 }
            }
            Self.batteryEmit("router: \(correct)/\(trials) expected=\(probe.expected) probe=\(probe.text)")
            Self.batteryRecorder.recordProbe(probe: probe.text, expected: probe.expected, correct: correct, trials: trials)
        }
        Self.batteryEmit("router: PROBE DONE (#196)")
        Self.batteryRecorder.endRun()
    }
}
#endif
