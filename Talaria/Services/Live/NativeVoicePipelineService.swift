@preconcurrency import AVFoundation
import Foundation
import os
@preconcurrency import Speech

/// On-device fallback voice engine (#18): mic → `SpeechAnalyzer` (with
/// `SpeechDetector` VAD when it behaves) → the ACTIVE chat backend
/// (`ChatBackendRouter`, per the #18 amendment — never a hardcoded
/// `SessionsHermesClient`) → sentence-buffered `SpeechOutputService`.
///
/// Conforms to `VoiceSessionServiceProtocol`, so TalkStore, the overlay,
/// transcript view, Live Activity, and CarPlay mirroring all work unchanged —
/// this is a new engine behind the existing session abstraction, not a UI
/// rewrite. `VoiceEngineRouter` selects it when the relay reports talk
/// unconfigured or is unreachable; the snapshot's `engine == .native` keeps
/// the substitution honest everywhere it renders.
///
/// Deliberate capability gaps (presented honestly, never mocked):
/// - No visual input — camera frames rode the OpenAI Realtime data channel;
///   `sendImage` returns false.
/// - Speech-to-speech naturalness and barge-in are worse than the WebRTC
///   path — this is a distinct "Local voice" mode with different latency.
@MainActor
final class NativeVoicePipelineService: VoiceSessionServiceProtocol {
    private static let logger = Logger(subsystem: "org.aethyrion.talaria", category: "NativeVoicePipeline")

    /// Fallback endpointer: commit the pending volatile utterance as a turn
    /// when transcription output has been quiet this long. Primary endpointing
    /// is the transcriber's own finalized results (SpeechDetector gates
    /// analysis to speech, so finals land at pauses); this timer only fires
    /// when the VAD/finalization path misbehaves (the iOS 26.0 SpeechDetector
    /// conformance bug, Apple forums #797544).
    nonisolated static let endpointSilence: TimeInterval = 1.35

    var voiceState: VoiceState = .idle { didSet { publishSnapshot() } }
    var connectionState: TalkConnectionState = .idle { didSet { publishSnapshot() } }
    var transcriptItems: [TranscriptItem] = [] { didSet { publishSnapshot() } }
    var sessionDuration: TimeInterval = 0 { didSet { publishSnapshot() } }
    var isMuted = false { didSet { publishSnapshot() } }
    var blockedReason: String? { didSet { publishSnapshot() } }
    var statusMessage: String? { didSet { publishSnapshot() } }
    // The local engine has no relay to gate on — it is startable until a
    // start attempt proves otherwise (mic/speech permission, model missing).
    var canStartSession = true { didSet { publishSnapshot() } }
    var latencyMetrics = TalkLatencyMetrics() { didSet { publishSnapshot() } }
    var readinessInfo = TalkReadinessInfo() { didSet { publishSnapshot() } }
    // #84: flatline tripwire + route visibility, mirroring the realtime
    // engine — capture running is a plumbing claim, not proof of audio.
    var micHealthHint: String? { didSet { publishSnapshot() } }
    var audioRouteSummary: String? { didSet { publishSnapshot() } }

    var snapshot: TalkSessionSnapshot {
        TalkSessionSnapshot(
            voiceState: voiceState,
            connectionState: connectionState,
            transcriptItems: transcriptItems,
            sessionDuration: sessionDuration,
            isMuted: isMuted,
            blockedReason: blockedReason,
            statusMessage: statusMessage,
            canStartSession: canStartSession,
            latencyMetrics: latencyMetrics,
            voiceSessionID: localSessionID,
            readiness: readinessInfo,
            engine: .native,
            micHealthHint: micHealthHint,
            audioRouteSummary: audioRouteSummary
        )
    }

    /// The active chat brain — wired to `ChatBackendRouter` by AppContainer,
    /// so a locally-routed turn makes this a fully offline voice assistant.
    private let backendProvider: @MainActor () -> (any HermesClientProtocol)?
    /// Dedicated TTS instance with `managesAudioSession == false`: this
    /// pipeline owns the `.playAndRecord` session, and the shared read-aloud
    /// instance stays gated off while a Talk session is active.
    private let speechOutput: SpeechOutputService
    private let capture = NativeVoiceCaptureController()
    private let eventHub = TalkSessionEventHub()

    /// Locally minted per session so the end-of-session transcript hand-off
    /// (`CompletedVoiceSession`) works without a relay voice-session id.
    private var localSessionID: UUID?
    private var startedAt: Date?
    private var timerTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    private var endpointTask: Task<Void, Never>?
    private var turnTask: Task<Void, Never>?

    /// Per-utterance transcription state (the tolerant, wire-mode-hedged
    /// parser: volatile text renders live; finals commit the turn; the
    /// fallback endpointer commits stale volatile text; `lastCommitted`
    /// dedupes a late final that re-covers already-committed audio).
    private var currentUserItemID: UUID?
    private var pendingVolatileText = ""
    private var lastTranscriptionChangeAt: Date?
    private var lastCommittedUtterance = ""
    private var currentAssistantItemID: UUID?
    /// Identity of the turn currently owning `turnTask` — a superseded
    /// (barge-in-cancelled) run's epilogue must not clear the new turn's
    /// handle or settle its state.
    private var activeTurnID: UUID?
    private var isEndingSession = false
    // #84 flatline tripwire — armed at `.connected`, disarmed by the first
    // transcription evidence or by session teardown.
    private var flatlineTask: Task<Void, Never>?
    private var speechEvidenceObserved = false

    init(
        backendProvider: @escaping @MainActor () -> (any HermesClientProtocol)?,
        speechOutput: SpeechOutputService
    ) {
        self.backendProvider = backendProvider
        self.speechOutput = speechOutput
        registerAudioSessionObservers()
    }

    func events() -> AsyncStream<TalkSessionEvent> {
        eventHub.stream(initial: snapshot)
    }

    // MARK: - VoiceSessionServiceProtocol

    func refreshReadiness() async {
        if connectionState == .connected || connectionState == .connecting {
            return
        }
        connectionState = .checking
        let transcriptionSupported = await NativeVoiceCaptureController.isTranscriptionSupported()
        let backendPresent = backendProvider() != nil
        // Relay concepts (hostOnline) stay nil — unknowable/not applicable on
        // the local engine; `configured` answers "is the local pipeline whole".
        readinessInfo = TalkReadinessInfo(
            hostOnline: nil,
            configured: transcriptionSupported && backendPresent,
            ready: transcriptionSupported && backendPresent
        )
        if transcriptionSupported && backendPresent {
            blockedReason = nil
            canStartSession = true
            statusMessage = "Local voice is ready — on-device speech, active chat brain."
            connectionState = .ready
        } else {
            blockedReason = transcriptionSupported
                ? "No chat backend is available for local voice."
                : "On-device speech transcription isn't available on this device."
            canStartSession = false
            statusMessage = blockedReason
            connectionState = .blocked
            voiceState = .disconnected
        }
    }

    func startSession() async {
        latencyMetrics = TalkLatencyMetrics(sessionStartRequestedAt: .now)
        isEndingSession = false

        let micCheck = TalkMicPreflight.classify(
            permissionGranted: await ensureMicrophonePermission(),
            inputAvailable: TalkMicPreflight.isMicInputAvailable()
        )
        switch micCheck {
        case .ok:
            break
        case .permissionDenied:
            // #84 preflight: actionable wording — the overlay pairs it with
            // an OPEN SETTINGS deep link. Never proceeds toward "Connected".
            blockedReason = TalkMicPreflight.microphoneDeniedMessage
            canStartSession = false
            connectionState = .blocked
            voiceState = .disconnected
            statusMessage = blockedReason
            return
        case .noInputAvailable:
            // #84 third state: permission is ON but no mic input is reachable
            // (the #82 wedge shape) — reboot guidance, no Settings dead end.
            blockedReason = TalkMicPreflight.noMicInputMessage
            canStartSession = false
            connectionState = .blocked
            voiceState = .disconnected
            statusMessage = blockedReason
            return
        }
        guard await ensureSpeechAuthorization() else {
            blockedReason = TalkMicPreflight.speechDeniedMessage
            canStartSession = false
            connectionState = .blocked
            voiceState = .disconnected
            statusMessage = blockedReason
            return
        }
        guard backendProvider() != nil else {
            blockedReason = "No chat backend is available for local voice."
            canStartSession = false
            connectionState = .blocked
            voiceState = .disconnected
            statusMessage = blockedReason
            return
        }

        connectionState = .connecting
        voiceState = .thinking
        statusMessage = "Starting local voice."
        transcriptItems = []
        resetUtteranceState()
        localSessionID = UUID()

        do {
            try await beginCapture()
            startedAt = .now
            startTimer()
            latencyMetrics.realtimeConnectedAt = .now
            connectionState = .connected
            voiceState = .listening
            blockedReason = nil
            canStartSession = true
            statusMessage = "Listening"
            startEndpointWatchdog()
            // #84: capture running ≠ hearing you. Publish the live route and
            // start the flatline window.
            updateAudioRouteSummary()
            armFlatlineTripwire()
        } catch {
            await teardownSessionResources()
            localSessionID = nil
            blockedReason = error.localizedDescription
            canStartSession = false
            connectionState = .failed
            voiceState = .disconnected
            statusMessage = "Local voice couldn't start: \(error.localizedDescription)"
        }
    }

    func endSession() async {
        isEndingSession = true
        // Freeze any in-flight assistant text before cancelling, so the
        // TalkStore transcript capture sees a finalized item.
        freezeCurrentAssistantItem()
        await teardownSessionResources()
        localSessionID = nil
        startedAt = nil
        voiceState = .idle
        connectionState = .idle
        blockedReason = nil
        canStartSession = true
        statusMessage = nil
        isMuted = false
    }

    func toggleMute() async {
        isMuted.toggle()
        await capture.setMuted(isMuted)
        // #84: unmuting restarts the flatline window — silence while muted
        // was expected, silence from here on is evidence of a mic problem.
        if !isMuted, connectionState == .connected, !speechEvidenceObserved {
            armFlatlineTripwire()
        }
    }

    /// Barge-in / stop button: cut TTS immediately, abandon the in-flight
    /// stream (the backend run fails or completes server-side on its own —
    /// there is no cancel wire on the local engine), and go back to listening.
    func manuallyInterruptAssistantOutput() {
        guard turnTask != nil || speechOutput.isSpeaking else { return }
        turnTask?.cancel()
        turnTask = nil
        speechOutput.stop()
        freezeCurrentAssistantItem()
        if connectionState == .connected {
            voiceState = .listening
            statusMessage = "Listening"
        }
    }

    /// No visual path in local voice — camera frames rode the OpenAI Realtime
    /// data channel, which doesn't exist here. Honest false, never a fake OK.
    @discardableResult
    func sendImage(_ imageData: Data, mimeType: String, triggerResponse: Bool) -> Bool {
        false
    }

    // MARK: - Capture plumbing

    private func beginCapture() async throws {
        captureTask?.cancel()
        let stream = try await capture.start(muted: isMuted)
        captureTask = Task { @MainActor [weak self] in
            for await event in stream {
                guard let self, !self.isEndingSession else { return }
                self.handleTranscriptionEvent(event)
            }
        }
    }

    /// Route/interruption recovery: tear down and rebuild the tap + analyzer.
    /// The mic hardware (and its format) changes across CarPlay/Bluetooth
    /// attach and detach, so a fresh engine start is the reliable path.
    private func restartCapture() async {
        guard connectionState == .connected, !isEndingSession else { return }
        captureTask?.cancel()
        captureTask = nil
        await capture.stop()
        do {
            try await beginCapture()
            if voiceState == .interrupted {
                voiceState = .listening
                statusMessage = "Listening"
            }
        } catch {
            Self.logger.warning("capture restart failed: \(error.localizedDescription, privacy: .public)")
            connectionState = .failed
            voiceState = .disconnected
            statusMessage = "Audio capture could not resume."
        }
    }

    private func teardownSessionResources() async {
        stopTimer()
        disarmFlatlineTripwire()
        audioRouteSummary = nil
        endpointTask?.cancel()
        endpointTask = nil
        turnTask?.cancel()
        turnTask = nil
        captureTask?.cancel()
        captureTask = nil
        speechOutput.stop()
        await capture.stop()
        resetUtteranceState()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func resetUtteranceState() {
        currentUserItemID = nil
        pendingVolatileText = ""
        lastTranscriptionChangeAt = nil
        lastCommittedUtterance = ""
        currentAssistantItemID = nil
    }

    // MARK: - Transcription → turns

    private func handleTranscriptionEvent(_ event: NativeVoiceCaptureController.Event) {
        switch event {
        case .volatile(let text):
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            noteSpeechEvidence()
            // User speech while the assistant is replying = barge-in. Voice
            // processing (echo cancellation) keeps TTS playback from landing
            // here, so volatile text during a reply is genuinely the user.
            if turnTask != nil || speechOutput.isSpeaking {
                manuallyInterruptAssistantOutput()
            }
            pendingVolatileText = text
            lastTranscriptionChangeAt = .now
            updateUserTranscriptItem(text: text, isPartial: true)
        case .finalized(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            noteSpeechEvidence()
            // A late final can re-cover audio the fallback endpointer already
            // committed — drop it instead of double-sending the turn.
            if Self.isDuplicateFinalization(committed: lastCommittedUtterance, candidate: trimmed) {
                pendingVolatileText = ""
                lastTranscriptionChangeAt = nil
                return
            }
            commitUserUtterance(trimmed)
        case .failed(let reason):
            guard !isEndingSession else { return }
            blockedReason = reason
            connectionState = .failed
            voiceState = .disconnected
            statusMessage = reason
        }
    }

    /// Fallback endpointer loop — commits stale volatile text as a turn when
    /// the transcriber never finalizes (SpeechDetector misbehaving).
    private func startEndpointWatchdog() {
        endpointTask?.cancel()
        endpointTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, self.connectionState == .connected else { continue }
                guard self.turnTask == nil else { continue }
                if Self.shouldEndpoint(
                    pendingText: self.pendingVolatileText,
                    lastChangeAt: self.lastTranscriptionChangeAt,
                    now: .now
                ) {
                    let text = self.pendingVolatileText.trimmingCharacters(in: .whitespacesAndNewlines)
                    Self.logger.notice("fallback endpointer fired (no final from transcriber)")
                    self.commitUserUtterance(text)
                }
            }
        }
    }

    private func commitUserUtterance(_ text: String) {
        // A final landing while a reply is still in flight (barge-in that
        // skipped the volatile phase) supersedes that reply.
        if turnTask != nil {
            turnTask?.cancel()
            turnTask = nil
            speechOutput.stop()
            freezeCurrentAssistantItem()
        }
        pendingVolatileText = ""
        lastTranscriptionChangeAt = nil
        lastCommittedUtterance = text
        updateUserTranscriptItem(text: text, isPartial: false)
        currentUserItemID = nil
        if latencyMetrics.firstUserFinalizedAt == nil {
            latencyMetrics.firstUserFinalizedAt = .now
        }
        voiceState = .thinking
        statusMessage = "Hermes is thinking."
        let ttsTurnID = UUID()
        activeTurnID = ttsTurnID
        turnTask = Task { @MainActor [weak self] in
            await self?.runTurn(text: text, ttsTurnID: ttsTurnID)
        }
    }

    private func runTurn(text: String, ttsTurnID: UUID) async {
        guard let backend = backendProvider() else {
            failTurn("No chat backend is available for local voice.")
            turnTask = nil
            return
        }
        let stream = backend.sendStreaming(message: text, attachments: [], clientMessageID: UUID())
        var streamedText = ""
        for await update in stream {
            if Task.isCancelled { break }
            switch update {
            case .messageSent:
                break
            case .textDelta(let delta):
                streamedText += delta
                appendAssistantDelta(delta)
                speechOutput.enqueueStreamChunk(delta, messageID: ttsTurnID)
                if voiceState != .speaking {
                    voiceState = .speaking
                    statusMessage = "Hermes is speaking."
                }
            case .reasoningDelta:
                // Reasoning is a separate channel — never spoken, never folded
                // into the answer.
                break
            case .toolActivity(let event):
                if event.phase == .started {
                    voiceState = .thinking
                    statusMessage = "Hermes is working on that\u{2026}"
                }
            case .finished(let message, _, _):
                let final = message.content.isEmpty ? streamedText : message.content
                finalizeAssistantItem(text: final)
                speechOutput.finishStream(messageID: ttsTurnID)
                if latencyMetrics.firstAssistantFinalizedAt == nil {
                    latencyMetrics.firstAssistantFinalizedAt = .now
                }
            case .failed(let reason):
                speechOutput.cancelStream(messageID: ttsTurnID)
                failTurn(reason)
            case .interrupted:
                // Server-side the run continues; locally this turn is over.
                speechOutput.cancelStream(messageID: ttsTurnID)
                failTurn("Connection dropped — the reply may finish on the host.")
            }
        }
        // A superseded run (barge-in started a newer turn) ends here — the
        // newer turn owns the task handle and the state machine.
        guard activeTurnID == ttsTurnID else { return }
        turnTask = nil
        await settleAfterSpeaking()
    }

    /// Hold `.speaking` until the sentence-buffered TTS queue drains, then
    /// return to listening. The mic stays live throughout (barge-in).
    private func settleAfterSpeaking() async {
        while speechOutput.isSpeaking, !isEndingSession, connectionState == .connected {
            try? await Task.sleep(for: .milliseconds(150))
        }
        guard connectionState == .connected, !isEndingSession else { return }
        if voiceState == .speaking || voiceState == .thinking {
            voiceState = .listening
            statusMessage = "Listening"
        }
    }

    private func failTurn(_ reason: String) {
        freezeCurrentAssistantItem()
        transcriptItems.append(TranscriptItem(speaker: .system, text: reason, isPartial: false))
        if connectionState == .connected {
            voiceState = .listening
            statusMessage = reason
        }
    }

    // MARK: - Transcript items

    private func updateUserTranscriptItem(text: String, isPartial: Bool) {
        if let currentUserItemID,
           let index = transcriptItems.firstIndex(where: { $0.id == currentUserItemID }) {
            transcriptItems[index].text = text
            transcriptItems[index].isPartial = isPartial
        } else {
            let item = TranscriptItem(speaker: .user, text: text, isPartial: isPartial)
            currentUserItemID = item.id
            transcriptItems.append(item)
        }
    }

    private func appendAssistantDelta(_ delta: String) {
        guard !delta.isEmpty else { return }
        if let currentAssistantItemID,
           let index = transcriptItems.firstIndex(where: { $0.id == currentAssistantItemID }) {
            transcriptItems[index].text += delta
            transcriptItems[index].isPartial = true
        } else {
            let item = TranscriptItem(speaker: .hermes, text: delta, isPartial: true)
            currentAssistantItemID = item.id
            transcriptItems.append(item)
        }
    }

    private func finalizeAssistantItem(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let currentAssistantItemID,
           let index = transcriptItems.firstIndex(where: { $0.id == currentAssistantItemID }) {
            if !trimmed.isEmpty {
                transcriptItems[index].text = trimmed
            }
            transcriptItems[index].isPartial = false
        } else if !trimmed.isEmpty {
            transcriptItems.append(TranscriptItem(speaker: .hermes, text: trimmed, isPartial: false))
        }
        currentAssistantItemID = nil
    }

    private func freezeCurrentAssistantItem() {
        if let currentAssistantItemID,
           let index = transcriptItems.firstIndex(where: { $0.id == currentAssistantItemID }) {
            transcriptItems[index].isPartial = false
        }
        currentAssistantItemID = nil
    }

    // MARK: - Pure decision helpers (unit-tested)

    /// True when the pending volatile utterance has been quiet long enough to
    /// commit as a turn without a transcriber final.
    nonisolated static func shouldEndpoint(
        pendingText: String,
        lastChangeAt: Date?,
        now: Date,
        silence: TimeInterval = NativeVoicePipelineService.endpointSilence
    ) -> Bool {
        guard !pendingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let lastChangeAt else { return false }
        return now.timeIntervalSince(lastChangeAt) >= silence
    }

    /// True when a transcriber final re-covers an utterance the fallback
    /// endpointer already committed (same text modulo case/whitespace, or a
    /// pure prefix/extension of it).
    nonisolated static func isDuplicateFinalization(committed: String, candidate: String) -> Bool {
        guard !committed.isEmpty else { return false }
        let normalize: (String) -> String = { text in
            text.lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
        let committedNorm = normalize(committed)
        let candidateNorm = normalize(candidate)
        guard !candidateNorm.isEmpty else { return true }
        return committedNorm == candidateNorm
            || committedNorm.hasPrefix(candidateNorm)
    }

    // MARK: - Permissions

    private func ensureMicrophonePermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await AVAudioApplication.requestRecordPermission()
        @unknown default:
            return false
        }
    }

    private func ensureSpeechAuthorization() async -> Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .authorized { return true }
        guard status == .notDetermined else { return false }
        let requested: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        return requested == .authorized
    }

    // MARK: - Mic health (#84)

    /// Arm the flatline tripwire: a connected, unmuted session with zero
    /// transcription evidence for a full window gets a mic-health hint
    /// instead of listening silently over a dead microphone.
    private func armFlatlineTripwire() {
        flatlineTask?.cancel()
        speechEvidenceObserved = false
        micHealthHint = nil
        flatlineTask = Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(for: MicFlatlineRule.window)
                if Task.isCancelled { return }
                guard let self else { return }
                switch MicFlatlineRule.verdict(
                    speechEvidence: self.speechEvidenceObserved,
                    isMuted: self.isMuted,
                    connectionState: self.connectionState
                ) {
                case .flag:
                    Self.logger.notice("mic flatline tripwire fired (route: \(self.audioRouteSummary ?? "unknown", privacy: .public))")
                    self.micHealthHint = MicFlatlineRule.hintMessage
                    return
                case .rearm:
                    continue
                case .disarm:
                    return
                }
            }
        }
    }

    /// The transcriber heard the user — the mic is demonstrably alive.
    private func noteSpeechEvidence() {
        speechEvidenceObserved = true
        flatlineTask?.cancel()
        flatlineTask = nil
        if micHealthHint != nil { micHealthHint = nil }
    }

    private func disarmFlatlineTripwire() {
        flatlineTask?.cancel()
        flatlineTask = nil
        micHealthHint = nil
    }

    private func updateAudioRouteSummary() {
        audioRouteSummary = TalkAudioRoute.currentSummary()
    }

    // MARK: - Audio session interruptions / route changes

    private func registerAudioSessionObservers() {
        let center = NotificationCenter.default
        center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor [weak self] in
                guard let self, let rawType,
                      let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
                switch type {
                case .began:
                    self.handleInterruptionBegan()
                case .ended:
                    let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
                    await self.handleInterruptionEnded(shouldResume: options.contains(.shouldResume))
                @unknown default:
                    break
                }
            }
        }
        center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor [weak self] in
                guard let self, let rawReason,
                      let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason) else { return }
                await self.handleRouteChange(reason)
            }
        }
    }

    private func handleInterruptionBegan() {
        guard connectionState == .connected else { return }
        speechOutput.stop()
        voiceState = .interrupted
        statusMessage = "Audio interrupted."
    }

    private func handleInterruptionEnded(shouldResume: Bool) async {
        guard connectionState == .connected else { return }
        guard shouldResume else {
            statusMessage = "Audio interrupted."
            return
        }
        await restartCapture()
    }

    /// The mic hardware (and its format) changes across CarPlay / Bluetooth /
    /// headset transitions — rebuild the capture chain on the new route.
    private func handleRouteChange(_ reason: AVAudioSession.RouteChangeReason) async {
        guard connectionState == .connected else { return }
        updateAudioRouteSummary()
        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable, .override, .routeConfigurationChange, .categoryChange:
            statusMessage = "Audio route changed."
            await restartCapture()
        default:
            break
        }
    }

    // MARK: - Session timer

    private func startTimer() {
        stopTimer()
        timerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                if let self, let startedAt = self.startedAt {
                    self.sessionDuration = Date().timeIntervalSince(startedAt)
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
        sessionDuration = 0
    }

    private func publishSnapshot() {
        eventHub.publish(snapshot: snapshot)
    }
}

// MARK: - Capture controller

/// Continuous mic → SpeechAnalyzer transcription. The dictation flavor of
/// this (one utterance then stop) lives in `LiveSpeechService`'s
/// `DictationController`; this one keeps the analyzer running for the whole
/// Talk session and reports volatile + finalized results as they land.
///
/// Echo cancellation: `inputNode.setVoiceProcessingEnabled(true)` before the
/// tap installs, so assistant TTS playback isn't re-transcribed as new user
/// input. Voice processing changes the input format — the format is read
/// AFTER enabling it.
private actor NativeVoiceCaptureController {
    private static let logger = Logger(subsystem: "org.aethyrion.talaria", category: "NativeVoiceCapture")

    enum Event: Sendable {
        case volatile(String)
        case finalized(String)
        case failed(String)
    }

    /// Realtime-safe mute flag: written from the service (MainActor), read on
    /// the audio tap thread.
    private let muteState = OSAllocatedUnfairLock(initialState: false)

    private let audioEngine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var reservedLocale: Locale?
    private var analyzerTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var outputContinuation: AsyncStream<Event>.Continuation?

    enum CaptureError: LocalizedError {
        case transcriptionUnavailable

        var errorDescription: String? {
            switch self {
            case .transcriptionUnavailable:
                "On-device speech transcription isn't available on this device."
            }
        }
    }

    /// True when either transcriber flavor supports a locale equivalent to
    /// the current one. `SpeechTranscriber` is device-gated by model
    /// availability; `DictationTranscriber` is the broader fallback (#18).
    static func isTranscriptionSupported() async -> Bool {
        if await SpeechTranscriber.supportedLocale(equivalentTo: .current) != nil { return true }
        return await DictationTranscriber.supportedLocale(equivalentTo: .current) != nil
    }

    func setMuted(_ muted: Bool) {
        muteState.withLock { $0 = muted }
    }

    func start(muted: Bool) async throws -> AsyncStream<Event> {
        stop()
        muteState.withLock { $0 = muted }

        // Session category: playAndRecord because TTS plays while the mic
        // stays live; .voiceChat enables the system voice-processing chain.
        // .allowBluetoothHFP covers headsets and car audio.
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetoothHFP]
        )
        try session.setActive(true)

        // Prefer SpeechTranscriber (the full model); fall back to
        // DictationTranscriber when the model isn't available on-device.
        // Both flavors get the SpeechDetector VAD module first, and retry
        // without it if the analyzer refuses to start (iOS 26.0 conformance
        // bug hedge — the fallback endpointer upstream covers endpointing).
        if SpeechTranscriber.isAvailable,
           let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) {
            let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
            try await reserveLocaleIfPossible(locale)
            return try await startAnalyzer(transcriber: transcriber, resultsLoop: { [weak self] in
                await self?.consumeSpeechTranscriberResults(transcriber)
            })
        }
        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: .current) else {
            throw CaptureError.transcriptionUnavailable
        }
        let transcriber = DictationTranscriber(locale: locale, preset: .progressiveShortDictation)
        try await reserveLocaleIfPossible(locale)
        return try await startAnalyzer(transcriber: transcriber, resultsLoop: { [weak self] in
            await self?.consumeDictationTranscriberResults(transcriber)
        })
    }

    func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        inputContinuation?.finish()
        inputContinuation = nil

        analyzerTask?.cancel()
        resultsTask?.cancel()
        analyzerTask = nil
        resultsTask = nil

        let analyzer = analyzer
        self.analyzer = nil
        if let analyzer {
            Task { await analyzer.cancelAndFinishNow() }
        }
        let reservedLocale = reservedLocale
        self.reservedLocale = nil
        if let reservedLocale {
            Task { _ = await AssetInventory.release(reservedLocale: reservedLocale) }
        }

        outputContinuation?.finish()
        outputContinuation = nil
    }

    // MARK: - Analyzer assembly

    private func reserveLocaleIfPossible(_ locale: Locale) async throws {
        if try await AssetInventory.reserve(locale: locale) {
            reservedLocale = locale
        }
    }

    private func startAnalyzer(
        transcriber: some SpeechModule,
        resultsLoop consumeResults: @escaping @Sendable () async -> Void
    ) async throws -> AsyncStream<Event> {
        // Echo cancellation FIRST — it changes the input format.
        let inputNode = audioEngine.inputNode
        do {
            try inputNode.setVoiceProcessingEnabled(true)
        } catch {
            // Non-fatal: without the voice-processing chain the pipeline still
            // works, but TTS playback may be re-transcribed. Barge-in handling
            // upstream tolerates it; log loudly for the device checklist.
            Self.logger.warning("voice processing unavailable: \(error.localizedDescription, privacy: .public)")
        }
        inputNode.removeTap(onBus: 0)
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // SpeechDetector gates analysis to detected speech; retry without it
        // if the analyzer/module combination refuses to start.
        var modules: [any SpeechModule] = [
            SpeechDetector(detectionOptions: .init(sensitivityLevel: .medium), reportResults: false),
            transcriber,
        ]

        var analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber],
            considering: inputFormat
        ) ?? inputFormat
        var analyzer: SpeechAnalyzer
        do {
            analyzer = SpeechAnalyzer(modules: modules)
            try await analyzer.prepareToAnalyze(in: analyzerFormat) { _ in }
        } catch {
            Self.logger.warning("analyzer with SpeechDetector failed (\(error.localizedDescription, privacy: .public)) — retrying without VAD module")
            modules = [transcriber]
            analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
                compatibleWith: [transcriber],
                considering: inputFormat
            ) ?? inputFormat
            analyzer = SpeechAnalyzer(modules: modules)
            try await analyzer.prepareToAnalyze(in: analyzerFormat) { _ in }
        }
        self.analyzer = analyzer

        let formatsMatch =
            inputFormat.sampleRate == analyzerFormat.sampleRate &&
            inputFormat.channelCount == analyzerFormat.channelCount &&
            inputFormat.commonFormat == analyzerFormat.commonFormat &&
            inputFormat.isInterleaved == analyzerFormat.isInterleaved
        let converter = formatsMatch ? nil : AVAudioConverter(from: inputFormat, to: analyzerFormat)
        converter?.primeMethod = .none

        var localInputContinuation: AsyncStream<AnalyzerInput>.Continuation?
        let inputStream = AsyncStream<AnalyzerInput> { continuation in
            localInputContinuation = continuation
            self.inputContinuation = continuation
        }
        let outputStream = AsyncStream<Event> { continuation in
            self.outputContinuation = continuation
        }

        let muteState = muteState
        let capturedFormat = analyzerFormat
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, _ in
            if muteState.withLock({ $0 }) { return }
            if let converted = Self.convertBuffer(buffer, using: converter, outputFormat: capturedFormat) {
                localInputContinuation?.yield(AnalyzerInput(buffer: converted))
            }
        }

        audioEngine.prepare()
        try audioEngine.start()

        let startedAnalyzer = analyzer
        analyzerTask = Task { [weak self] in
            do {
                try await startedAnalyzer.start(inputSequence: inputStream)
            } catch {
                Self.logger.error("speech analyzer failed: \(error.localizedDescription, privacy: .public)")
                await self?.emit(.failed("Speech analysis failed."))
                await self?.stop()
            }
        }
        resultsTask = Task {
            await consumeResults()
        }

        return outputStream
    }

    /// The two consume loops are shape-identical but typed to their module's
    /// own Result — kept separate rather than forced through a generic seam.
    private func consumeSpeechTranscriberResults(_ transcriber: SpeechTranscriber) async {
        do {
            for try await result in transcriber.results {
                let text = String(result.text.characters)
                emit(result.isFinal ? .finalized(text) : .volatile(text))
            }
        } catch {
            Self.logger.error("transcriber results failed: \(error.localizedDescription, privacy: .public)")
            emit(.failed("Speech transcription failed."))
        }
    }

    private func consumeDictationTranscriberResults(_ transcriber: DictationTranscriber) async {
        do {
            for try await result in transcriber.results {
                let text = String(result.text.characters)
                emit(result.isFinal ? .finalized(text) : .volatile(text))
            }
        } catch {
            Self.logger.error("dictation results failed: \(error.localizedDescription, privacy: .public)")
            emit(.failed("Speech transcription failed."))
        }
    }

    private func emit(_ event: Event) {
        outputContinuation?.yield(event)
    }

    nonisolated private static func convertBuffer(
        _ inputBuffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter?,
        outputFormat: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        final class ConversionState: @unchecked Sendable {
            var didProvideInput = false
        }

        guard let converter else { return inputBuffer }

        let frameRatio = outputFormat.sampleRate / inputBuffer.format.sampleRate
        let outputFrameCapacity = max(
            inputBuffer.frameLength,
            AVAudioFrameCount(ceil(Double(inputBuffer.frameLength) * frameRatio)) + 32
        )

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputFrameCapacity
        ) else {
            Self.logger.error("failed to allocate converted audio buffer")
            return nil
        }

        let state = ConversionState()
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if state.didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            } else {
                state.didProvideInput = true
                outStatus.pointee = .haveData
                return inputBuffer
            }
        }

        switch status {
        case .haveData, .inputRanDry, .endOfStream:
            return outputBuffer.frameLength > 0 ? outputBuffer : nil
        case .error:
            Self.logger.error("audio conversion failed: \(conversionError?.localizedDescription ?? "unknown", privacy: .public)")
            return nil
        @unknown default:
            return nil
        }
    }
}
