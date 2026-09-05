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
    /// #198: `nonisolated` so the audio-session notification observers can
    /// reach it — those closures are `@Sendable` (the system delivers off the
    /// main actor), and the class's global actor would otherwise isolate this
    /// static along with everything else. Safe: `Logger` is Sendable, this is
    /// a `let`.
    private nonisolated static let logger = Logger(
        subsystem: "org.aethyrion.talaria", category: "NativeVoicePipeline")

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
    /// #428: injectable so a test can drive the capture stack without an
    /// `AVAudioEngine`. Production always gets `NativeVoiceCaptureController`
    /// via the convenience initializer below.
    private let capture: any NativeVoiceCapturing
    private let eventHub = TalkSessionEventHub()

    /// Locally minted per session so the end-of-session transcript hand-off
    /// (`CompletedVoiceSession`) works without a relay voice-session id.
    private var localSessionID: UUID?
    private var startedAt: Date?
    private var timerTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    /// Serializes route/interruption capture restarts (see restartCapture).
    private var restartTask: Task<Void, Never>?
    /// Sliding window of restart timestamps feeding the thrash breaker.
    private var recentCaptureRestarts: [Date] = []
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
    /// Guards against route-change feedback loops immediately after the
    /// capture stack reconfigures the audio session.
    private var isConfiguringAudioSession = false
    /// Debounce window during which routine configuration side-effect route
    /// notifications are ignored (prevents the start() → categoryChange →
    /// restart() → categoryChange loop observed in the console log).
    private static let audioSessionConfigurationCooldown: Duration = .milliseconds(750)

    init(
        backendProvider: @escaping @MainActor () -> (any HermesClientProtocol)?,
        speechOutput: SpeechOutputService,
        capture: any NativeVoiceCapturing
    ) {
        self.backendProvider = backendProvider
        self.speechOutput = speechOutput
        self.capture = capture
        registerAudioSessionObservers()
    }

    /// The production shape — every existing call site (#428: `AppContainer`
    /// and the test host) reaches the real capture controller through this.
    convenience init(
        backendProvider: @escaping @MainActor () -> (any HermesClientProtocol)?,
        speechOutput: SpeechOutputService
    ) {
        self.init(
            backendProvider: backendProvider,
            speechOutput: speechOutput,
            capture: NativeVoiceCaptureController()
        )
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
        let transcriptionSupported = await capture.isTranscriptionSupported()
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
        isConfiguringAudioSession = true
        do {
            let stream = try await capture.start(muted: isMuted)
            captureTask = Task { @MainActor [weak self] in
                for await event in stream {
                    guard let self, !self.isEndingSession else { return }
                    self.handleTranscriptionEvent(event)
                }
            }
        } catch {
            isConfiguringAudioSession = false
            throw error
        }
        // Hold the route-change gate open briefly so the category/active change
        // side effects do not loop back into a restart.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.audioSessionConfigurationCooldown)
            self?.isConfiguringAudioSession = false
        }
    }

    /// Route/interruption recovery: tear down and rebuild the tap + analyzer.
    /// The mic hardware (and its format) changes across CarPlay/Bluetooth
    /// attach and detach, so a fresh engine start is the reliable path.
    ///
    /// Serialized + circuit-broken (post-#82 device findings): a wedged
    /// capture stack thrashes route-change notifications, and overlapping
    /// restarts raced stop/start into a double tap-install — an uncatchable
    /// `nullptr == Tap()` NSException — while each pass re-entered audio
    /// session activation on the main thread (the observed UI lockup). One
    /// restart runs at a time; a thrash storm trips the breaker into the
    /// honest #84 blocked state instead of looping.
    private func restartCapture() async {
        guard connectionState == .connected, !isEndingSession else { return }
        // Ignore self-triggered configuration side effects. A genuine restart is
        // only needed for real hardware changes, not for our own category
        // changes during setup.
        guard !isConfiguringAudioSession else { return }
        // Coalesce: a restart already in flight covers this trigger too.
        if let inFlight = restartTask {
            await inFlight.value
            return
        }
        // Breaker: >3 restarts inside 30s is not route churn — it's the #82
        // wedge thrashing. Stop retrying; block with the reboot guidance.
        let now = Date.now
        recentCaptureRestarts = recentCaptureRestarts.filter { now.timeIntervalSince($0) < 30 }
        recentCaptureRestarts.append(now)
        if recentCaptureRestarts.count > 3 {
            Self.logger.error("capture restart storm (\(self.recentCaptureRestarts.count, privacy: .public) in 30s) — #82 wedge shape; blocking instead of looping")
            captureTask?.cancel()
            captureTask = nil
            await capture.stop()
            blockedReason = TalkMicPreflight.noMicInputMessage
            canStartSession = false
            connectionState = .blocked
            voiceState = .disconnected
            statusMessage = blockedReason
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            self.captureTask?.cancel()
            self.captureTask = nil
            await self.capture.stop()
            do {
                try await self.beginCapture()
                if self.voiceState == .interrupted {
                    self.voiceState = .listening
                    self.statusMessage = "Listening"
                }
            } catch {
                Self.logger.warning("capture restart failed: \(error.localizedDescription, privacy: .public)")
                self.connectionState = .failed
                self.voiceState = .disconnected
                self.statusMessage = "Audio capture could not resume."
            }
        }
        restartTask = task
        await task.value
        restartTask = nil
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
        try? await AudioSessionOffMain.setActive(
            false,
            options: .notifyOthersOnDeactivation,
            reason: "native-pipeline-stop"
        )
    }

    private func resetUtteranceState() {
        currentUserItemID = nil
        pendingVolatileText = ""
        lastTranscriptionChangeAt = nil
        lastCommittedUtterance = ""
        currentAssistantItemID = nil
    }

    // MARK: - Transcription → turns

    private func handleTranscriptionEvent(_ event: NativeVoiceCaptureEvent) {
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

    // harness-visible (#304 review fixes): private in spirit — the voice
    // turn's one entry, widened only so the approval honest-refusal test can
    // drive a real turn through `runTurn` without the audio stack.
    func commitUserUtterance(_ text: String) {
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
        statusMessage = "Talaria is thinking."
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
                    statusMessage = "Talaria is speaking."
                }
            case .reasoningDelta:
                // Reasoning is a separate channel — never spoken, never folded
                // into the answer.
                break
            case .artifactProduced:
                // #258: an agent-written file is a transcript surface —
                // never spoken. ChatStore renders the chip.
                break
            case .contextPrimed:
                // P1 (#90): a hop transplant is chat-surface bookkeeping —
                // never spoken; ChatStore renders the notice and cost.
                break
            case .toolActivity(let event):
                if event.phase == .started {
                    voiceState = .thinking
                    statusMessage = "Talaria is working on that\u{2026}"
                }
            case .modelResolved:
                // #223 Lane 5: header attribution is a chat-surface concern;
                // ChatStore consumes it. Never spoken.
                break
            case .steerLanded, .steerUnconsumed:
                // #357 (3C): steering outcomes are a composer concern —
                // ChatStore renders applied/queued. Never spoken.
                break
            case .finished(let message, _, _):
                let final = message.content.isEmpty ? streamedText : message.content
                finalizeAssistantItem(text: final)
                speechOutput.finishStream(messageID: ttsTurnID)
                if latencyMetrics.firstAssistantFinalizedAt == nil {
                    latencyMetrics.firstAssistantFinalizedAt = .now
                }
            case .approvalRequested:
                // #304 review-2 RULING (option b — Owen's O5 honest-refusal
                // shape, applied to the voice surface): this surface cannot
                // show or answer the approval, and it must SAY so — nothing
                // more. Round 1 raised the shared chat card and said "open
                // the chat"; the re-review traced that the only route from
                // Talk to chat is ending the session, whose teardown
                // (`endSession` → `turnTask?.cancel()`) destroyed the card
                // before the chat was reachable — the promise stayed false.
                // A voice-surface answer path is explicitly #305's scope.
                voiceState = .thinking
                statusMessage = "Talaria is waiting on a host approval this voice surface can't show or answer. If it isn't answered, the host denies it when its approval window expires."
            case .approvalResolved:
                // The host resolved it (or it expired) — the run continues or
                // terminates on its own; nothing voice-side to tear down.
                break
            case .failed(let reason), .unreachable(let reason):
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
        // #301: the completion MUST be `@Sendable`. Without it, a closure
        // formed in this `@MainActor` context inherits MainActor isolation;
        // `SFSpeechRecognizer.requestAuthorization` invokes it on TCC's XPC
        // reply queue (`com.apple.root.default-qos`), and the Swift 6 runtime's
        // `_swift_task_checkIsolatedSwift` then traps `BUG IN CLIENT OF
        // LIBDISPATCH: … expected to execute on queue [com.apple.main-thread]`
        // the instant `continuation.resume` runs off-main — killing the app on
        // the FIRST-EVER speech grant (the only path this closure runs; an
        // already-authorized status returns above and never forms it, which is
        // why existing installs never saw it). Reproduced deterministically on
        // the iOS 27.0 simulator 2026-08-10, byte-identical to the #254 device
        // corpus crash. `@Sendable` drops the isolation inheritance;
        // `CheckedContinuation` is Sendable and `.resume` is thread-safe, so
        // the resume is correct from any queue. This is the same remedy the
        // archived EventKit `fetchReminders` trap used (`@Sendable` on the
        // framework completion) — applied ONLY to this named site, no sweep.
        let requested: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { @Sendable status in
                continuation.resume(returning: status)
            }
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
        // #198: one interruption notification became two. Extract-and-delegate
        // only — the decisions live in `AudioInterruptionRule`, since neither
        // notification can be synthesized in a test (both context types declare
        // `init` as `NS_UNAVAILABLE`).
        center.addObserver(
            forName: AVAudioSession.didBecomeInactiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let context = notification.userInfo?[AVAudioSession.deactivationContextKey]
                    as? AVAudioSession.DeactivationContext
            else { return }
            guard AudioInterruptionRule.isInterruption(source: context.source) else {
                // Our own teardown — the common arm, so verbose-gated.
                if TalariaLog.isVerbose {
                    Self.logger.notice("audio deactivated by app — not an interruption (#198)")
                }
                return
            }
            // .notice so the #198 device pass can read the filter working.
            let reason = context.interruptionContext.map { String(describing: $0.reason) } ?? "none"
            Self.logger.notice("audio interrupted — system deactivation, reason: \(reason, privacy: .public) (#198)")
            Task { @MainActor [weak self] in
                self?.handleInterruptionBegan()
            }
        }
        center.addObserver(
            forName: AVAudioSession.resumptionRecommendationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let context = notification.userInfo?[AVAudioSession.resumptionContextKey]
                    as? AVAudioSession.ResumptionContext
            else { return }
            let shouldResume = AudioInterruptionRule.shouldResume(context.recommendation)
            Self.logger.notice(
                "audio resumption recommendation: \(shouldResume ? "resume" : "do not resume", privacy: .public) (#198)")
            Task { @MainActor [weak self] in
                await self?.handleInterruptionEnded(shouldResume: shouldResume)
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
        guard connectionState == .connected, !isConfiguringAudioSession else { return }
        guard shouldResume else {
            statusMessage = "Audio interrupted."
            return
        }
        await restartCapture()
    }

    /// The mic hardware (and its format) changes across CarPlay / Bluetooth /
    /// headset transitions — rebuild the capture chain on the new route.
    private func handleRouteChange(_ reason: AVAudioSession.RouteChangeReason) async {
        guard connectionState == .connected, !isConfiguringAudioSession else { return }
        updateAudioRouteSummary()
        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable, .override:
            statusMessage = "Audio route changed."
            await restartCapture()
        case .routeConfigurationChange, .categoryChange:
            // Self-inflicted configuration changes (we set the category above,
            // and the system emits configuration/route changes as side effects)
            // must not trigger a restart loop. Only react to actual hardware
            // transitions.
            statusMessage = "Audio route configured."
            updateAudioRouteSummary()
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

#if DEBUG
    // MARK: - #428 Task 0 probe doors (TEMPORARY)
    //
    // harness-visible (#428, Task 0 probe). These exist ONLY so
    // `NativeVoiceCaptureProbeTests` can measure the premises the #428 plan
    // rests on (does the sim clear the preflight; does the real capture chain
    // start; does a posted route-change reach `restartCapture`, and does the
    // 750 ms configuration cooldown gate it). Task 4 deletes them together
    // with the probe file — nothing in production reads them.

    /// The real capture controller, so a probe can read `probeStartCount`.
    /// Optional since #428's Task 1 seam: `capture` is now `any
    /// NativeVoiceCapturing`, and only the production controller has probes.
    var probeCaptureController: NativeVoiceCaptureController? {
        capture as? NativeVoiceCaptureController
    }

    /// The route-change gate's flag, so a probe can see the cooldown clear.
    var probeIsConfiguringAudioSession: Bool { isConfiguringAudioSession }

    /// Arms/disarms the gate without going through a real capture start.
    func probeSetConfiguringAudioSession(_ value: Bool) {
        isConfiguringAudioSession = value
    }

    /// The real `beginCapture()`, so a probe can measure the REAL cooldown
    /// rather than a hand-set flag.
    func probeBeginCapture() async throws {
        try await beginCapture()
    }
#endif
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
// harness-visible (#428) — widened from `private` so tests can drive the REAL
// controller. This is now PERMANENT, not the temporary widening Task 0's probe
// asked for: 428-B's `NativeVoiceCaptureGenerationTests` constructs this type
// directly with an injected assembler, and its `CaptureError.superseded` is the
// discriminator the whole capture-generation bar rests on. The tag still means
// "private in spirit" — nothing outside this file and the suites constructs it.
actor NativeVoiceCaptureController: NativeVoiceCapturing {
    private static let logger = Logger(subsystem: "org.aethyrion.talaria", category: "NativeVoiceCapture")

    /// #428: every suspension point between the audio-session configuration
    /// and the tap install lives behind this. Production gets
    /// `SpeechTranscriberAssembler`; a test can park a start here.
    private let assembler: any SpeechAnalysisAssembling

    init(assembler: any SpeechAnalysisAssembling = SpeechTranscriberAssembler()) {
        self.assembler = assembler
    }

    /// Realtime-safe mute flag: written from the service (MainActor), read on
    /// the audio tap thread.
    private let muteState = OSAllocatedUnfairLock(initialState: false)

    private let audioEngine = AVAudioEngine()
    /// harness-visible (#428) — the engine's own state, not a wrapper flag.
    /// PERMANENT (it outlives Task 0's probe file): 428-B's bar is "nothing
    /// installed", and the only honest reading of that is the engine's.
    var isEngineRunning: Bool { audioEngine.isRunning }
#if DEBUG
    /// harness-visible (#428, Task 0 probe) — counts `start(muted:)` entries so
    /// probe 3 can see a route-change restart as a SECOND start even when that
    /// start then throws. TEMPORARY, deleted with the probe file (Task 4).
    /// `#if DEBUG` because nothing in production reads it (#218's rule: a
    /// harness-only member does not ship).
    private(set) var probeStartCount = 0
#endif
    /// #428 (428-B): monotonic teardown counter. `stop()` bumps it first thing;
    /// a start captures it after its own leading `stop()` and refuses to touch
    /// the engine if it has moved by the time the start resumes. Same shape as
    /// `TalkStore.sessionGeneration` — no new mechanism.
    private var captureGeneration = 0
    /// #428 (428-B2): the adopted assembly's release hook — the ONE mechanism
    /// that gives back a prepared analyzer and its locale reservation. Replaces
    /// the separate `analyzer` / `reservedLocale` stored properties, whose only
    /// readers were `stop()`'s two hand-rolled releases.
    private var releaseAdoptedResources: (@Sendable () async -> Void)?
    private var analyzerTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var outputContinuation: AsyncStream<NativeVoiceCaptureEvent>.Continuation?

    enum CaptureError: LocalizedError {
        case transcriptionUnavailable
        /// #82 wedge caught at the engine: the input node reported a
        /// degenerate format (0 Hz / 0 ch) — installing a tap would raise an
        /// uncatchable NSException. Carries the #84 third-state wording.
        case noAudioInput
        /// #428: a `stop()` moved the capture generation while this start was
        /// parked in the analyzer assembly, so the start was abandoned before
        /// anything touched the engine. `point` names the suspension point it
        /// resumed from. This is a control signal, not a device fault — the
        /// restart path swallows it rather than surfacing it (Task 3).
        case superseded(point: String)

        var errorDescription: String? {
            switch self {
            case .transcriptionUnavailable:
                "On-device speech transcription isn't available on this device."
            case .noAudioInput:
                TalkMicPreflight.noMicInputMessage
            case .superseded:
                "Voice capture start was superseded by a session teardown."
            }
        }
    }

    /// True when either transcriber flavor supports a locale equivalent to
    /// the current one. `SpeechTranscriber` is device-gated by model
    /// availability; `DictationTranscriber` is the broader fallback (#18).
    ///
    /// The result is cached per locale because the `supportedLocale` probe
    /// spawns an XPC speech service (`com.apple.speech.localspeechrecognition`)
    /// each call; hammering it on every readiness check can return false and
    /// causes log churn. We invalidate on app background or significant locale
    /// changes via `NotificationCenter`.
    func isTranscriptionSupported() async -> Bool {
        if let cached = transcriptionSupportCache, cached.locale == .current {
            return cached.supported
        }
        let supported = await probeTranscriptionSupport()
        transcriptionSupportCache = (locale: .current, supported: supported)
        return supported
    }

    private func probeTranscriptionSupport() async -> Bool {
        if await SpeechTranscriber.supportedLocale(equivalentTo: .current) != nil { return true }
        return await DictationTranscriber.supportedLocale(equivalentTo: .current) != nil
    }

    /// Cache slot for the last-locale support check. Stored as an instance
    /// property on the isolated actor to avoid nonisolated static mutable state.
    private var transcriptionSupportCache: (locale: Locale, supported: Bool)?

    func setMuted(_ muted: Bool) {
        muteState.withLock { $0 = muted }
    }

    func start(muted: Bool) async throws -> AsyncStream<NativeVoiceCaptureEvent> {
#if DEBUG
        probeStartCount += 1  // harness-visible (#428, Task 0 probe)
#endif
        stop()
        // #428 (428-B): the ticket. Taken AFTER this start's own leading
        // `stop()` (which bumped the generation) and before the one suspension
        // point below — so it equals the generation for exactly as long as no
        // OTHER teardown runs. `checkTicket` re-reads the counter after the
        // suspension; a mismatch means a `stop()` interleaved and this start
        // must install nothing.
        let ticket = captureGeneration
        muteState.withLock { $0 = muted }

        // Session category: playAndRecord because TTS plays while the mic
        // stays live; .voiceChat enables the system voice-processing chain.
        // .allowBluetoothHFP covers headsets and car audio.
        // Deactivate first to avoid reconfiguring an active session; the
        // previous stop() already deactivated, but this call is harmless and
        // makes the intent explicit (prevents category-change thrash).
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetoothHFP]
        )
        try session.setActive(true)
        // #302-A: always-on capture-chain instrument. The App Lock question
        // ("is the mic live behind the cover?") is answered by intersecting
        // these timestamped transitions with AppLock's own `.notice` lines —
        // so they must be `.notice` (Console hides `.info`), `privacy:
        // .public` (or they redact), and NEVER gated behind Verbose Logging.
        // This line marks the session going active; the chain is not hot
        // until the HOT line below reports the ENGINE's own state.
        Self.logger.notice("audio session activated for capture (#302-A)")

        // Echo cancellation FIRST — it changes the input format, and the
        // format is what the assembly negotiates against. (#428: this pair
        // moved up out of `startAnalyzer`; both calls are synchronous, so
        // nothing suspends between the session going active and the assembly.)
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

        // The ONE suspension point of a capture start (#428). Everything the
        // analyzer needs — transcriber selection, locale reservation, format
        // negotiation, `prepareToAnalyze` — happens in here; everything after
        // it is a single synchronous stretch that ends with a live tap.
        let assembly = try await assembler.assemble(inputFormat: inputFormat)
        do {
            try checkTicket(ticket, at: "assembled")
        } catch {
            // #428 (428-B2): the assembly RETURNED, so the assembler's own
            // error path cannot clean it up — and `startEngine`, the only thing
            // that adopts it, is never reached. Give back what it built before
            // throwing, or the fix trades a stray tap for a stray analyzer and
            // a stray locale reservation. Awaited (not fired into a `Task`)
            // because this start has nothing left to do: the release completes
            // before the abandonment is visible to the caller.
            await assembly.releaseResources()
            throw error
        }
        return try startEngine(assembly: assembly, inputNode: inputNode, inputFormat: inputFormat)
    }

    /// #428 (428-B): refuse a startup that a `stop()` interleaved with.
    ///
    /// Actor serialization does not survive a suspension, so every suspension
    /// point between "the audio session is configured" and "a tap is installed"
    /// is a window where a teardown can run to completion and return. After
    /// each one, this asks whether it did. A mismatch means the engine this
    /// start is about to touch belongs to a session that has already ended.
    ///
    /// There is exactly ONE such window today (`assemble`); the `point`
    /// parameter exists so a second one cannot be added without naming itself
    /// in the log.
    private func checkTicket(_ ticket: Int, at point: String) throws {
        guard captureGeneration != ticket else { return }
        // #302-A's rule for the capture chain: `.notice` (Console hides
        // `.info`), `privacy: .public` (or it redacts), never gated behind
        // Verbose Logging. This line is the positive control for an ABSENCE —
        // without it an archive cannot tell "the ticket caught a superseded
        // start" from "no restart was ever attempted".
        Self.logger.notice("\(Self.abandonedStartLogDetail(point: point), privacy: .public)")
        throw CaptureError.superseded(point: point)
    }

    /// The abandoned-start line, as a pure function so its text is pinned by a
    /// test rather than by a device archive (`VoiceInstrumentLogLineTests`).
    nonisolated static func abandonedStartLogDetail(point: String) -> String {
        "capture start ABANDONED — capture generation moved during startup at \(point); nothing installed (#428)"
    }

    func stop() {
        // #428 (428-B): the generation moves FIRST, before a single resource is
        // torn down. A start parked in `assemble` compares its ticket against
        // this counter when it resumes — so a bump that happened at the END of
        // the teardown would leave a window in which a start resumes mid-
        // teardown and still matches.
        captureGeneration &+= 1
        // #302-A: read the engine's own state BEFORE tearing it down, so the
        // COLD line can say whether this stop ended a hot chain (was=true)
        // or was a defensive no-op (was=false — negative evidence that the
        // chain never went hot, e.g. a start that died in permission checks).
        let wasRunning = audioEngine.isRunning
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        let stillRunning = audioEngine.isRunning
        Self.logger.notice("capture chain COLD — AVAudioEngine.isRunning was=\(wasRunning, privacy: .public) now=\(stillRunning, privacy: .public) inputTap=removed (#302-A)")
        inputContinuation?.finish()
        inputContinuation = nil

        analyzerTask?.cancel()
        resultsTask?.cancel()
        analyzerTask = nil
        resultsTask = nil

        // #428 (428-B2): ONE release mechanism. This used to be two hand-rolled
        // releases reading two stored properties — cancel the analyzer, release
        // the locale — which is the shape a SUPERSEDED start (which never
        // adopts either) would have had to duplicate to avoid leaking. The
        // assembly now carries its own release; `startEngine` adopts it and
        // this hands it back. Fire-and-forget because `stop()` is synchronous
        // by protocol; the two releases are now sequential inside one `Task`
        // (cancel, then release the locale) rather than racing in two.
        let releaseAdopted = releaseAdoptedResources
        releaseAdoptedResources = nil
        if let releaseAdopted {
            Task { await releaseAdopted() }
        }

        outputContinuation?.finish()
        outputContinuation = nil
    }

    // MARK: - Engine start
    //
    // #428: the analyzer ASSEMBLY (transcriber selection, locale reservation,
    // format negotiation, `prepareToAnalyze` + the no-VAD retry) moved to
    // `SpeechTranscriberAssembler`; `reserveLocaleIfPossible` went with it, as
    // the reservation's only caller. What is left below is the synchronous
    // stretch — it contains NO `await`, which is precisely the property #428's
    // capture generation needs.

    private func startEngine(
        assembly: SpeechAnalysisAssembly,
        inputNode: AVAudioInputNode,
        inputFormat: AVAudioFormat
    ) throws -> AsyncStream<NativeVoiceCaptureEvent> {
        // Adopt the assembly's resources FIRST, so any throw below still
        // leaves `stop()` able to cancel the analyzer and release the locale.
        // (#428, 428-B2: "adopt" now means taking over the assembly's own
        // release hook — from this line on `stop()` owns it, which is exactly
        // why the superseded path, which never gets here, must call it itself.)
        let analyzerFormat = assembly.analyzerFormat
        self.releaseAdoptedResources = assembly.releaseResources

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
        let outputStream = AsyncStream<NativeVoiceCaptureEvent> { continuation in
            self.outputContinuation = continuation
        }

        let muteState = muteState
        let capturedFormat = analyzerFormat
        // #82 wedge backstop, check 2 of 2 (#428 — DEFENCE IN DEPTH, not a
        // move). `SpeechTranscriberAssembler.assemble` runs the same predicate
        // as its first statement, so on device the fail-fast is unchanged;
        // this second call guards the thing a degenerate format actually
        // breaks — the install below, which with a 0 Hz / 0 ch format raises
        // an uncatchable NSException. It is repeated here because the
        // assembler is INJECTABLE: a test double skips check 1, and the
        // engine must still refuse. Same predicate both times, never a copy
        // of its body.
        guard TalkMicPreflight.isViableCaptureFormat(
            sampleRate: inputFormat.sampleRate,
            channelCount: inputFormat.channelCount
        ) else {
            Self.logger.error("capture format degenerate (rate=\(inputFormat.sampleRate, privacy: .public) ch=\(inputFormat.channelCount, privacy: .public)) — #82 wedge shape; refusing tap install")
            throw CaptureError.noAudioInput
        }
        // #128: this remove must be IMMEDIATELY adjacent to the install —
        // the earlier defensive removeTap sits before the assembly's
        // suspension point (#428 collapsed the four that used to sit here into
        // one), and actor serialization does not survive awaits: two
        // interleaved capture starts both passed it and double-installed,
        // throwing AVAudioEngine's `CreateRecordingTap: nullptr == Tap()`
        // (device crash 2026-07-17, mid-session voice change). Remove-then-
        // install in the same synchronous stretch makes the last writer win
        // cleanly instead.
        inputNode.removeTap(onBus: 0)
        // #198: the iOS 27 installer REPORTS the failure this comment
        // describes instead of raising it, so a double-install that slips past
        // the adjacency invariant above now throws out of here — the caller's
        // existing failure path — rather than crashing the app.
        try AudioNodeTap.install(on: inputNode, bufferSize: 1024, format: inputFormat) { buffer, _ in
            if muteState.withLock({ $0 }) { return }
            if let converted = Self.convertBuffer(buffer, using: converter, outputFormat: capturedFormat) {
                localInputContinuation?.yield(AnalyzerInput(buffer: converted))
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        // #302-A: the honest instrument reads the ENGINE's own state, not a
        // wrapper flag — the wrapper is the thing under suspicion. From this
        // line until the matching COLD line, microphone buffers are flowing
        // into the tap. A device pass intersects [HOT..COLD] with AppLock's
        // locked interval to answer #302 (a)-vs-(b) by measurement.
        let engineRunning = audioEngine.isRunning
        Self.logger.notice("capture chain HOT — AVAudioEngine.isRunning=\(engineRunning, privacy: .public) inputTap=installed (#302-A)")

        let startedAnalyzer = assembly.analyzer
        analyzerTask = Task { [weak self] in
            do {
                try await startedAnalyzer.start(inputSequence: inputStream)
            } catch {
                Self.logger.error("speech analyzer failed: \(error.localizedDescription, privacy: .public)")
                await self?.emit(.failed("Speech analysis failed."))
                await self?.stop()
            }
        }
        // #428: the results loop used to arrive as a closure built at the
        // transcriber-selection site; it now switches on the assembly's own
        // choice. Same two loops, same typing.
        let transcriber = assembly.transcriber
        resultsTask = Task { [weak self] in
            switch transcriber {
            case .speech(let transcriber):
                await self?.consumeSpeechTranscriberResults(transcriber)
            case .dictation(let transcriber):
                await self?.consumeDictationTranscriberResults(transcriber)
            }
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

    private func emit(_ event: NativeVoiceCaptureEvent) {
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
