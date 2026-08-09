import Foundation

/// Metadata captured when a voice session completes, used to trigger transcript injection.
/// Carries the finalized transcript itself (#1): the relay inject endpoint is out of the
/// chat path, so the hand-off into the conversation is composed entirely from this
/// on-device snapshot — it must be captured before the voice service resets its state.
struct CompletedVoiceSession: Sendable {
    let voiceSessionId: UUID
    let duration: TimeInterval
    let turnCount: Int
    let transcript: [TranscriptItem]
    /// Which engine ran the session (#18). Native-engine turns already rode
    /// the chat backend, so the post-to-Hermes context turn is skipped for
    /// them — only the local transcript rendering applies.
    ///
    /// #180 lane 180-L: optional, because the store's `voiceEngine` now is.
    /// The one consumer (`ContentView`) already tests `== .realtime`, so an
    /// unknown engine falls to the conservative side — no duplicate context
    /// turn posted for a session whose engine nobody published.
    let engine: VoiceEngine?
}

@MainActor
@Observable
final class TalkStore {
    var voiceState: VoiceState = .idle
    var connectionState: TalkConnectionState = .idle
    var transcriptItems: [TranscriptItem] = []
    var sessionDuration: TimeInterval = 0
    var isMuted = false
    var isSessionActive = false
    /// #254: **a start is in flight.** Published because `isSessionActive`
    /// cannot answer the question the background observer needs to ask.
    ///
    /// `isSessionActive` is derived in `applySnapshot` from the *engine's*
    /// published `connectionState`, so it stays false through the whole
    /// prologue of a start — the brain gate, the pairing check, the #82 mic
    /// preflight (which can sit on a permission dialog indefinitely) — and it
    /// goes false AGAIN during the realtime→native fallback, where a start
    /// that landed `.failed` opens a LOCAL microphone from a not-active state.
    /// Backgrounding in either window used to revoke nothing, and the session
    /// then landed live, speaking, with no UI and no owner.
    ///
    /// **Not `sessionGeneration`.** That counter is private and monotonic — it
    /// records how many intents have been claimed, not whether one is
    /// outstanding, and no external reader can compare it against anything.
    /// This is the state; that is the tally.
    private(set) var isStartingSession = false
    var blockedReason: String?
    var statusMessage: String?
    var canStartSession = true
    var latencyMetrics = TalkLatencyMetrics()
    var voiceSessionID: UUID?
    var readiness = TalkReadinessInfo()
    /// The engine driving (or last driving) the voice session (#18) — feeds
    /// the overlay's LOCAL VOICE badge and the Voice settings engine row.
    ///
    /// #180 lane 180-L: **nil until a snapshot publishes one.** It defaulted to
    /// `.realtime`, which meant every surface reading it named an engine before
    /// anything had selected one (bar 180-C).
    var voiceEngine: VoiceEngine?
    /// #84: flatline-tripwire hint — connected but no mic signal evidence.
    var micHealthHint: String?
    /// #84: current audio route summary while a session is (or was) live.
    var audioRouteSummary: String?

    /// Set after a voice session ends; consumed by MainTabView to trigger transcript injection.
    var lastCompletedSession: CompletedVoiceSession?

    /// Called when voice session state changes (start/end/state transition).
    var onSessionStateChanged: (@MainActor () -> Void)?

    private let voiceService: any VoiceSessionServiceProtocol
    private let liveActivity = LiveActivityService()
    private var eventTask: Task<Void, Never>?
    /// #139: monotonic session intent. Dismissal bumps it, so a connect that
    /// returns afterwards is recognised as belonging to a session the user
    /// already left, and is discarded instead of being flipped live.
    private var sessionGeneration = 0

    init(voiceService: any VoiceSessionServiceProtocol) {
        self.voiceService = voiceService
        applySnapshot(voiceService.snapshot)
        subscribeToEvents()
    }

    func refreshReadiness() async {
        await voiceService.refreshReadiness()
        applySnapshot(voiceService.snapshot)
    }

    /// Re-sync Live Activity state when returning from background.
    func handleAppDidBecomeActive() {
        liveActivity.handleAppDidBecomeActive()
    }

    /// Start without a prior readiness check — goes straight to session create.
    func startSessionDirectly() async {
        canStartSession = true
        connectionState = .connecting
        voiceState = .thinking
        statusMessage = "Connecting..."
        let generation = beginSessionGeneration()
        // #254: publish the intent BEFORE the first await — the whole point is
        // to be visible during the window the awaited call occupies. `defer`
        // clears it on every exit, including the abandoned-start return below.
        isStartingSession = true
        defer { isStartingSession = false }
        await voiceService.startSession()
        guard generation == sessionGeneration else {
            await discardAbandonedStart()
            return
        }
        applySnapshot(voiceService.snapshot)
        if isSessionActive {
            liveActivity.startVoiceSession()
        }
    }

    func startSession() async {
        let generation = beginSessionGeneration()
        // #254: same publication as `startSessionDirectly` — both start doors
        // must be visible to the background observer, not just the overlay's.
        isStartingSession = true
        defer { isStartingSession = false }
        await voiceService.startSession()
        guard generation == sessionGeneration else {
            await discardAbandonedStart()
            return
        }
        applySnapshot(voiceService.snapshot)
        if isSessionActive {
            liveActivity.startVoiceSession()
        }
    }

    /// #139: the dismissal path.
    ///
    /// Unlike `endSessionIfNeeded()` this does NOT guard on `isSessionActive` —
    /// and that guard is the whole reason the defect survived overlay teardown.
    /// A start that has not yet published `.connecting` is invisible to the
    /// flag, and a session that IS still connecting is exactly the one that
    /// must be revoked. Bumping the generation first means a connect already in
    /// flight is discarded on return even if its RPC cannot be cancelled.
    func abandonSession() async {
        sessionGeneration &+= 1
        await endSession()
    }

    /// Belt for a start that resolved after its session was abandoned. The
    /// engines guard their own late connects (#139), so this should find
    /// nothing live — but adopting such a snapshot is precisely the bug, so
    /// end rather than apply.
    private func discardAbandonedStart() async {
        await voiceService.endSession()
        applySnapshot(voiceService.snapshot)
    }

    private func beginSessionGeneration() -> Int {
        sessionGeneration &+= 1
        return sessionGeneration
    }

    func endSession() async {
        // #139: an explicit end revokes any connect still in flight, so a slow
        // start cannot land live after the user hung up.
        sessionGeneration &+= 1
        // #254: the start is no longer wanted. Clearing here as well as in the
        // start's own `defer` means a second background event during the same
        // (possibly 12-second, #247 B1) connect does not re-fire the revoke.
        isStartingSession = false
        // Capture session metadata before the service resets
        let sessionId = voiceSessionID
        let duration = sessionDuration
        let finalizedTranscript = transcriptItems.filter { !$0.isPartial }
        let turnCount = finalizedTranscript.count
        let engine = voiceEngine

        // End Live Activity
        liveActivity.endActivity()

        await voiceService.endSession()
        applySnapshot(voiceService.snapshot)

        // Publish completed session for injection
        if let sessionId, turnCount > 0 {
            lastCompletedSession = CompletedVoiceSession(
                voiceSessionId: sessionId,
                duration: duration,
                turnCount: turnCount,
                transcript: finalizedTranscript,
                engine: engine
            )
        }
    }

    func toggleMute() async {
        await voiceService.toggleMute()
        applySnapshot(voiceService.snapshot)
    }

    /// Manually interrupt assistant speech (e.g., from a stop button).
    /// Unlike VAD-triggered interruption, this sends cancel + clear + truncate.
    func interruptAssistant() {
        voiceService.manuallyInterruptAssistantOutput()
        applySnapshot(voiceService.snapshot)
    }

    /// Send an image to the Realtime model during an active voice session.
    @discardableResult
    func sendImage(_ imageData: Data, triggerResponse: Bool = true) -> Bool {
        guard isSessionActive else { return false }
        return voiceService.sendImage(imageData, mimeType: "image/jpeg", triggerResponse: triggerResponse)
    }

    func endSessionIfNeeded() async {
        // #139: revoke first, THEN decide whether there is a live session to
        // tear down — an in-flight connect is not `isSessionActive` yet, and it
        // is the one that must not survive this call.
        sessionGeneration &+= 1
        guard isSessionActive else { return }
        await endSession()
    }

    func clearLastCompletedSession() {
        lastCompletedSession = nil
    }

    func reset() {
        voiceState = .idle
        connectionState = .idle
        transcriptItems = []
        sessionDuration = 0
        isMuted = false
        isSessionActive = false
        isStartingSession = false
        blockedReason = nil
        statusMessage = nil
        canStartSession = true
        latencyMetrics = TalkLatencyMetrics()
        voiceSessionID = nil
        readiness = TalkReadinessInfo()
        // #180 lane 180-L: reset returns this to UNKNOWN, not to the
        // historical engine — a reset store has not selected anything.
        voiceEngine = nil
        micHealthHint = nil
        audioRouteSummary = nil
        lastCompletedSession = nil
    }

    private func subscribeToEvents() {
        eventTask?.cancel()
        let stream = voiceService.events()
        eventTask = Task { @MainActor [weak self] in
            for await event in stream {
                guard let self else { return }
                switch event {
                case .snapshot(let snapshot):
                    self.applySnapshot(snapshot)
                }
            }
        }
    }

    private func applySnapshot(_ snapshot: TalkSessionSnapshot) {
        voiceState = snapshot.voiceState
        connectionState = snapshot.connectionState
        transcriptItems = snapshot.transcriptItems
        sessionDuration = snapshot.sessionDuration
        isMuted = snapshot.isMuted
        blockedReason = snapshot.blockedReason
        statusMessage = snapshot.statusMessage
        canStartSession = snapshot.canStartSession
        latencyMetrics = snapshot.latencyMetrics
        voiceSessionID = snapshot.voiceSessionID
        readiness = snapshot.readiness
        voiceEngine = snapshot.engine
        micHealthHint = snapshot.micHealthHint
        audioRouteSummary = snapshot.audioRouteSummary
        isSessionActive = connectionState == .connecting || connectionState == .connected

        // Update Live Activity on voice state changes
        if isSessionActive {
            let status: String
            switch snapshot.voiceState {
            case .listening: status = "Listening"
            case .thinking:  status = snapshot.statusMessage ?? "Thinking..."
            case .speaking:  status = "Speaking"
            default:         status = snapshot.statusMessage ?? "Connected"
            }
            // Extract tool name from status message if it mentions a tool
            let toolName = snapshot.statusMessage?.contains("working") == true
                ? snapshot.statusMessage : nil
            liveActivity.updateVoiceState(status, toolName: toolName)
        }

        onSessionStateChanged?()
    }
}
