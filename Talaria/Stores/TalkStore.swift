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
    let engine: VoiceEngine
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
    var blockedReason: String?
    var statusMessage: String?
    var canStartSession = true
    var latencyMetrics = TalkLatencyMetrics()
    var voiceSessionID: UUID?
    var readiness = TalkReadinessInfo()
    /// The engine driving (or last driving) the voice session (#18) — feeds
    /// the overlay's LOCAL VOICE badge and the Voice settings engine row.
    var voiceEngine: VoiceEngine = .realtime
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
        await voiceService.startSession()
        applySnapshot(voiceService.snapshot)
        if isSessionActive {
            liveActivity.startVoiceSession()
        }
    }

    func startSession() async {
        await voiceService.startSession()
        applySnapshot(voiceService.snapshot)
        if isSessionActive {
            liveActivity.startVoiceSession()
        }
    }

    func endSession() async {
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
        blockedReason = nil
        statusMessage = nil
        canStartSession = true
        latencyMetrics = TalkLatencyMetrics()
        voiceSessionID = nil
        readiness = TalkReadinessInfo()
        voiceEngine = .realtime
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
