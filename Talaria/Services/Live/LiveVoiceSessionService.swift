import AVFoundation
import Foundation
import os

#if canImport(WebRTC)
@preconcurrency import WebRTC
#endif

@MainActor
final class LiveVoiceSessionService: NSObject, VoiceSessionServiceProtocol {
    /// #198: `nonisolated` so the audio-session notification handlers can reach
    /// it — the system delivers those off the main actor, and the class's
    /// global actor would otherwise isolate this static along with everything
    /// else. Safe: `Logger` is Sendable and this is a `let`.
    private nonisolated static let logger = Logger(
        subsystem: "org.aethyrion.talaria", category: "LiveVoiceSessionService")
    private struct EmptyBody: Encodable {}


    private struct TalkReadinessResponse: Decodable {
        let ready: Bool
        let hostOnline: Bool
        let configured: Bool
        let blockedReason: String?
        let preferredModels: [String]?
        let selectedModel: String?
        let voice: String?
        let voiceContextUpdatedAt: Date?
        /// #396: the tuning names the host accepts on the mint. Tolerant —
        /// a plugin that predates tuning simply omits it, and nil is what
        /// keeps the picker's footnote honest.
        let tunings: [String]?
    }

    private struct TalkSessionResponse: Decodable {
        let voiceSession: RelayVoiceSession
        let bootstrap: TalkBootstrap
    }

    private struct RelayVoiceSession: Decodable {
        let id: UUID
        let status: String
        let model: String?
        let voice: String?
        let startedAt: Date
        let endedAt: Date?
        let lastError: String?
    }

    private struct TalkBootstrap: Decodable {
        let clientSecret: String
        let expiresAt: Date?
        let session: RealtimeSession
        let model: String?
        let voice: String?
    }

    private struct RealtimeSession: Decodable {
        let id: String?
    }


    private struct VoiceTurnPersistResponse: Decodable {
        let turn: PersistedTurn
    }

    private struct PersistedTurn: Decodable {
        let id: UUID
    }

    var voiceState: VoiceState = .idle { didSet { publishSnapshot() } }
    var connectionState: TalkConnectionState = .idle { didSet { publishSnapshot() } }
    var transcriptItems: [TranscriptItem] = [] { didSet { publishSnapshot() } }
    var sessionDuration: TimeInterval = 0 { didSet { publishSnapshot() } }
    var isMuted = false { didSet { publishSnapshot() } }
    var blockedReason: String? { didSet { publishSnapshot() } }
    var statusMessage: String? { didSet { publishSnapshot() } }
    var canStartSession = false { didSet { publishSnapshot() } }
    var latencyMetrics = TalkLatencyMetrics() { didSet { publishSnapshot() } }
    var readinessInfo = TalkReadinessInfo() { didSet { publishSnapshot() } }

    /// #396: the user's coarse sensitivity pick, read at mint time — a
    /// provider closure so this service keeps no settings dependency (the
    /// house pattern). AppContainer arms it from `UserSettings`.
    var voiceTuningProvider: @MainActor () -> String = { VoiceSensitivity.normal.rawValue }
    // #84: flatline tripwire + route visibility — "connected" is a transport
    // claim, not proof the microphone is delivering audio.
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
            voiceSessionID: voiceSessionID,
            readiness: readinessInfo,
            micHealthHint: micHealthHint,
            audioRouteSummary: audioRouteSummary
        )
    }

    /// #383: the voice bootstrap's transport, resolved PER CALL.
    ///
    /// Was `RelayAPIClient`; the relay and the connector behind it are retired
    /// (#346/#375), so voice rides the talaria plugin over the platform link.
    ///
    /// A provider rather than a stored instance for two reasons. The link is
    /// minted after this service (it needs the profile store), so there is
    /// nothing to hold at construction — and #310's rule applies: resolving
    /// per call means a profile switch or a Server-settings edit changes the
    /// answer with no rewiring. Assigned post-construction, exactly like the
    /// router's capability predicates beside it.
    var voiceTransportProvider: @MainActor () -> (any VoiceBootstrapTransport)? = { nil }

    private var voiceTransport: any VoiceBootstrapTransport {
        voiceTransportProvider() ?? UnavailableVoiceTransport()
    }

    /// The house's one lenient ISO date coder — a second date parser is how
    /// two decoders drift until they disagree about a boundary case (#256).
    /// This is a coder, not a transport; nothing here speaks to the relay any
    /// more, and since #309 Lane C there is no relay client left to share it
    /// with: `RelayCoders` lives in its own file, and voice is its main
    /// reader.
    private static let decoder = RelayCoders.makeDecoder()
    private let urlSession: URLSession
    private let realtimeEventTransportOverride: ((Data) -> Bool)?
    private let eventHub = TalkSessionEventHub()
    private var voiceSessionID: UUID?
    private var startedAt: Date?
    private var timerTask: Task<Void, Never>?
    private var transcriptItemIDsByConversationItemID: [String: UUID] = [:]
    private var currentAssistantItemID: UUID?
    private var assistantTextSource: String?
    private var currentRealtimeResponseID: String?
    private var currentAssistantConversationItemID: String?
    private var currentUserConversationItemID: String?
    private var currentAssistantContentIndex = 0
    private var assistantAudioPlaybackStartedAtUptime: TimeInterval?
    private var accumulatedAssistantAudioPlaybackMilliseconds = 0
    private var ignoreCurrentAssistantFinalization = false
    private var lastImageItemID: String?
    fileprivate var isEndingSession = false
    /// #139: monotonic start intent. `endSession()` bumps it, so a start whose
    /// relay bootstrap returns AFTER the user dismissed can tell that it was
    /// abandoned and refuse to finish connecting.
    ///
    /// This is load-bearing, not defensive. `prepareWebRTC()` returns the peer
    /// connection, data channel and audio track as a LOCAL value; they are
    /// assigned to `self` only inside `connectWithPrepared`. So during the whole
    /// connect window `peerConnection`/`dataChannel`/`audioTrack` are still nil,
    /// `endSession()`'s teardown closes NOTHING, and the late
    /// `connectWithPrepared` re-arms a live mic over the nil'd properties and
    /// flips `.connected` — with no overlay on screen. `isEndingSession` alone
    /// could not cover this: it guards the delegate callbacks, and the direct
    /// path through `connectWithPrepared` never consults it.
    // harness-visible
    private(set) var startGeneration = 0
    // #84 flatline tripwire — armed at `.connected`, disarmed by the first
    // speech evidence off the data channel or by session teardown.
    private var flatlineTask: Task<Void, Never>?
    private var speechEvidenceObserved = false

    #if canImport(WebRTC)
    private static let peerFactory = RTCPeerConnectionFactory()
    private let peerDelegate = RealtimePeerDelegate()
    nonisolated(unsafe) private var peerConnection: RTCPeerConnection?
    nonisolated(unsafe) private var dataChannel: RTCDataChannel?
    nonisolated(unsafe) private var audioTrack: RTCAudioTrack?
    #endif

    init(
        urlSession: URLSession = .shared,
        realtimeEventTransportOverride: ((Data) -> Bool)? = nil
    ) {
        self.urlSession = urlSession
        self.realtimeEventTransportOverride = realtimeEventTransportOverride
        super.init()
        registerAudioSessionObservers()
        #if canImport(WebRTC)
        peerDelegate.owner = self
        #endif
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func events() -> AsyncStream<TalkSessionEvent> {
        eventHub.stream(initial: snapshot)
    }


    /// #383 hazard 5: two hosts, one app. A host whose plugin predates the
    /// voice verbs answers `unknown_event_type`, and that must reach the user
    /// as something they can act on rather than as an unreachable host.
    private func requireData(_ outcome: VoiceVerbOutcome) throws -> Data {
        switch outcome {
        case let .ok(data): return data
        case .unsupported: throw VoiceTransportError.hostDoesNotSupportVoice
        case .unreachable: throw VoiceTransportError.hostUnreachable
        }
    }

    func refreshReadiness() async {
        // Don't disrupt an active or connecting session with a readiness check.
        if connectionState == .connected || connectionState == .connecting {
            return
        }
        connectionState = .checking
        do {
            let data = try requireData(await voiceTransport.talkReadiness())
            let response = try Self.decoder.decode(TalkReadinessResponse.self, from: data)
            blockedReason = response.blockedReason
            canStartSession = response.ready
            readinessInfo = TalkReadinessInfo(
                hostOnline: response.hostOnline,
                configured: response.configured,
                ready: response.ready,
                selectedModel: response.selectedModel,
                voice: response.voice,
                voiceContextUpdatedAt: response.voiceContextUpdatedAt,
                tunings: response.tunings
            )
            statusMessage = response.ready ? "Hermes talk is ready." : (response.blockedReason ?? "Talk is unavailable.")
            connectionState = response.ready ? .ready : .blocked
            if !response.ready {
                voiceState = .disconnected
            }
        } catch {
            Self.logger.error("voice readiness FAILED: \(String(describing: error), privacy: .public)")
            blockedReason = error.localizedDescription
            canStartSession = false
            // The probe failed — every readiness detail is now unknowable.
            readinessInfo = TalkReadinessInfo()
            statusMessage = friendlyStatusMessage(for: error)
            connectionState = .failed
            voiceState = .disconnected
        }
    }

    func startSession() async {
        latencyMetrics = TalkLatencyMetrics(sessionStartRequestedAt: .now)
        isEndingSession = false
        // #139: claim this start's generation before the first await.
        startGeneration &+= 1
        let generation = startGeneration
        // Skip readiness check — already done by VoiceOverlayScreen.task before
        // calling startSession. Removing it saves one HTTP round trip + RPC.
        guard canStartSession else { return }

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

        connectionState = .connecting
        voiceState = .thinking
        statusMessage = "Starting talk mode."
        transcriptItems = []
        transcriptItemIDsByConversationItemID = [:]
        currentAssistantItemID = nil
        currentUserConversationItemID = nil
        assistantTextSource = nil

        do {
            #if canImport(WebRTC)
            // Phase 1: Prepare WebRTC (peer connection + SDP offer) in parallel
            // with the host bootstrap request (talaria plugin, #383). This
            // saves ~200-500ms.
            // Awaited: activation must complete before the WebRTC engine starts.
            try await configureAudioSession()
            let prepared = try await prepareWebRTC()
            #endif

            // #396-Q: name the preset this session is minted with, always-on.
            // Read ONCE and reused for both the log and the wire, so the line
            // can never describe a different pick than the one that shipped.
            let tuning = voiceTuningProvider()
            Self.logger.notice("\(Self.sessionTuningLogDetail(preset: tuning, engine: "realtime", hostTunings: self.readinessInfo.tunings), privacy: .public)")
            let data = try requireData(await voiceTransport.talkSessionCreate(tuning: tuning))
            let response = try Self.decoder.decode(TalkSessionResponse.self, from: data)
            voiceSessionID = response.voiceSession.id
            // #139: the user dismissed while this request was in flight. Do not
            // open a microphone for a session nobody is in — close the prepared
            // WebRTC objects (they are LOCAL, so `endSession()` could not reach
            // them) and hand the freshly-minted remote session straight back.
            if generation != startGeneration || isEndingSession {
                Self.logger.notice("realtime start abandoned mid-connect — discarding the bootstrap without connecting (#139)")
                #if canImport(WebRTC)
                prepared.channel?.close()
                prepared.connection.close()
                #endif
                await endRemoteSession()
                voiceSessionID = nil
                stopTimer()
                return
            }
            startedAt = .now
            latencyMetrics.hostBootstrapReceivedAt = .now
            startTimer()
            #if canImport(WebRTC)
            // Phase 2: Exchange SDP with the ephemeral key from bootstrap
            try await connectWithPrepared(prepared, bootstrap: response.bootstrap)
            #else
            await endRemoteSession()
            blockedReason = "This build does not include the WebRTC client transport yet."
            canStartSession = false
            connectionState = .blocked
            voiceState = .disconnected
            statusMessage = blockedReason
            #endif
        } catch {
            // #383: this path had NO log. A realtime start that failed set a
            // `blockedReason`, fell back to the local pipeline, and left the
            // reason on screen for the length of a flash — so the one question
            // worth asking ("why did it fall back?") was the one thing the
            // device could not answer. Tonight's recurring shape: the failure
            // path is the path with no instrument.
            Self.logger.error("realtime start FAILED — falling back to local voice: \(String(describing: error), privacy: .public)")
            await endRemoteSession()
            voiceSessionID = nil
            startedAt = nil
            blockedReason = error.localizedDescription
            canStartSession = false
            connectionState = .failed
            voiceState = .disconnected
            statusMessage = friendlyStatusMessage(for: error)
            stopTimer()
        }
    }

    func endSession() async {
        stopTimer()
        startedAt = nil
        isEndingSession = true
        // #139: revoke any start still in flight. `isEndingSession` is reset by
        // the NEXT startSession, so it cannot by itself distinguish "this start
        // was abandoned" from "a new start is underway"; the generation can.
        startGeneration &+= 1
        currentAssistantItemID = nil
        currentUserConversationItemID = nil
        assistantTextSource = nil
        currentRealtimeResponseID = nil
        currentAssistantConversationItemID = nil
        currentAssistantContentIndex = 0
        transcriptItemIDsByConversationItemID = [:]
        resetAssistantAudioPlaybackTracking()
        ignoreCurrentAssistantFinalization = false
        lastImageItemID = nil
        disarmFlatlineTripwire()
        audioRouteSummary = nil
        // #302-A / #415: read the capture state BEFORE tearing it down, so
        // the COLD line can say whether this stop ended a HOT chain
        // (was=true) or was a defensive no-op (was=false — negative evidence
        // that the chain never went hot, e.g. a start that died in the #82
        // mic preflight). The native pipeline's COLD line reads
        // `AVAudioEngine.isRunning` for exactly this reason.
        #if canImport(WebRTC)
        let wasCapturing = peerConnection != nil && audioTrack != nil
        dataChannel?.close()
        dataChannel = nil
        peerConnection?.close()
        peerConnection = nil
        audioTrack = nil
        #else
        let wasCapturing = false
        #endif
        try? await AudioSessionOffMain.setActive(
            false,
            options: .notifyOthersOnDeactivation,
            reason: "realtime-session-end"
        )
        Self.logger.notice(
            "capture chain COLD — was=\(wasCapturing, privacy: .public) audioTrack=released session=deactivated (#302-A)")
        await endRemoteSession()
        voiceSessionID = nil
        voiceState = .idle
        connectionState = .idle
        blockedReason = nil
        canStartSession = true
        statusMessage = nil
    }

    func toggleMute() async {
        isMuted.toggle()
        #if canImport(WebRTC)
        audioTrack?.isEnabled = !isMuted
        #endif
        // #84: unmuting restarts the flatline window — silence while muted
        // was expected, silence from here on is evidence of a mic problem.
        if !isMuted, connectionState == .connected, !speechEvidenceObserved {
            armFlatlineTripwire()
        }
    }

    @discardableResult
    func sendImage(_ imageData: Data, mimeType: String = "image/jpeg", triggerResponse: Bool = true) -> Bool {
        guard connectionState == .connected else { return false }

        // Delete the previous image item so the model only sees the latest one.
        // Without this, the model references stale camera frames or old photos.
        if let previousID = lastImageItemID {
            _ = sendRealtimeEvent([
                "type": "conversation.item.delete",
                "event_id": UUID().uuidString,
                "item_id": previousID,
            ])
            lastImageItemID = nil
        }

        let base64 = imageData.base64EncodedString()
        let dataURL = "data:\(mimeType);base64,\(base64)"
        let imageItemID = "img\(UUID().uuidString.prefix(28))"

        let sent = sendRealtimeEvent([
            "type": "conversation.item.create",
            "event_id": UUID().uuidString,
            "item": [
                "id": imageItemID,
                "type": "message",
                "role": "user",
                "content": [
                    [
                        "type": "input_image",
                        "image_url": dataURL,
                    ] as [String: Any]
                ],
            ] as [String: Any],
        ])

        if sent {
            lastImageItemID = imageItemID
        }

        if sent && triggerResponse {
            // Only trigger response if no response is already in-flight
            if currentRealtimeResponseID == nil {
                _ = sendRealtimeEvent([
                    "type": "response.create",
                    "event_id": UUID().uuidString,
                ])
            }
            // Add thumbnail to transcript so the user sees what they sent
            transcriptItems.append(TranscriptItem(speaker: .user, text: "", imageData: imageData))
        }

        return sent
    }

    private func publishSnapshot() {
        eventHub.publish(snapshot: snapshot)
    }

    private func startTimer() {
        stopTimer()
        timerTask = Task {
            while !Task.isCancelled {
                if let startedAt {
                    sessionDuration = Date().timeIntervalSince(startedAt)
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func friendlyStatusMessage(for error: Error) -> String {
        if let transportError = error as? VoiceTransportError {
            return transportError.localizedDescription
        }
        // #383: the relay's 401 ladder is gone with the relay. The platform
        // link re-pairs itself on 401 (one attempt, then it gives up), so an
        // expired credential never reaches here as an auth error — it arrives
        // as an unreachable host, which is what the user can actually act on.
        return "Could not reach the Hermes host."
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
        sessionDuration = 0
    }

    private func registerAudioSessionObservers() {
        let center = NotificationCenter.default
        // #198: the single interruption notification became two. See
        // `AudioInterruptionRule` — this is not a rename, and the
        // did-become-inactive half now also fires for our OWN deactivations.
        center.addObserver(
            self,
            selector: #selector(handleAudioSessionDidBecomeInactiveNotification(_:)),
            name: AVAudioSession.didBecomeInactiveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleAudioSessionResumptionRecommendationNotification(_:)),
            name: AVAudioSession.resumptionRecommendationNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleAudioSessionRouteChangeNotification(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    private func ensureMicrophonePermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    private var hasActiveRealtimeSession: Bool {
        voiceSessionID != nil || connectionState == .connected || connectionState == .connecting
    }

    // MARK: - Mic health (#84)

    /// Arm the flatline tripwire: if a connected, unmuted session produces
    /// zero speech evidence for a full window, surface a mic-health hint
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

    /// The server heard the user — the mic is demonstrably alive.
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

    /// #198: extract-and-delegate only. The decision lives in
    /// `AudioInterruptionRule` because this notification cannot be synthesized
    /// in a test — `DeactivationContext.init` is `NS_UNAVAILABLE`.
    @objc
    private nonisolated func handleAudioSessionDidBecomeInactiveNotification(_ notification: Notification) {
        guard let context = notification.userInfo?[AVAudioSession.deactivationContextKey]
                as? AVAudioSession.DeactivationContext
        else { return }
        guard AudioInterruptionRule.isInterruption(source: context.source) else {
            // Our own teardown. Verbose-gated because read-aloud deactivates
            // the session after every utterance — this arm is the common one.
            if TalariaLog.isVerbose {
                Self.logger.notice("audio deactivated by app — not an interruption (#198)")
            }
            return
        }
        // .notice so the #198 device pass can read the filter working in
        // Console without enabling verbose: rare by construction.
        let reason = context.interruptionContext.map { String(describing: $0.reason) } ?? "none"
        Self.logger.notice("audio interrupted — system deactivation, reason: \(reason, privacy: .public) (#198)")

        Task { @MainActor [weak self] in
            self?.handleAudioInterruptionBegan()
        }
    }

    /// #198: replaces the `.ended` arm. The resume decision used to ride the
    /// same notification as an option flag; it is now its own event.
    @objc
    private nonisolated func handleAudioSessionResumptionRecommendationNotification(_ notification: Notification) {
        guard let context = notification.userInfo?[AVAudioSession.resumptionContextKey]
                as? AVAudioSession.ResumptionContext
        else { return }
        let shouldResume = AudioInterruptionRule.shouldResume(context.recommendation)
        Self.logger.notice(
            "audio resumption recommendation: \(shouldResume ? "resume" : "do not resume", privacy: .public) (#198)")

        Task { @MainActor [weak self] in
            await self?.handleAudioInterruptionEnded(shouldResume: shouldResume)
        }
    }

    @objc
    private nonisolated func handleAudioSessionRouteChangeNotification(_ notification: Notification) {
        let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt

        Task { @MainActor [weak self] in
            guard let self,
                  let rawReason,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason)
            else {
                return
            }
            await self.handleAudioRouteChange(reason)
        }
    }

    func handleAudioInterruptionBegan() {
        guard hasActiveRealtimeSession else { return }
        stopAssistantAudioPlaybackTracking()
        voiceState = .interrupted
        statusMessage = "Audio interrupted."
    }

    func handleAudioInterruptionEnded(shouldResume: Bool) async {
        guard hasActiveRealtimeSession else { return }
        guard shouldResume else {
            statusMessage = "Audio interrupted."
            return
        }

        do {
            try await configureAudioSession()
            if connectionState == .connected || connectionState == .connecting {
                voiceState = .listening
                statusMessage = "Listening"
            }
        } catch {
            Self.logger.warning("Failed to reactivate audio session after interruption: \(error.localizedDescription)")
            connectionState = .failed
            voiceState = .disconnected
            statusMessage = "Audio session could not resume."
        }
    }

    func handleAudioRouteChange(_ reason: AVAudioSession.RouteChangeReason) async {
        guard hasActiveRealtimeSession else { return }
        updateAudioRouteSummary()
        // #418: a mid-session route swap (AirPods in/out) re-logs the route.
        // Read off-main per #198B; the formatter runs inside the same hop.
        if let routeDetail = try? await AudioSessionOffMain.run({ audioSession in
            LiveVoiceSessionService.audioRouteLogDetail(
                inputs: audioSession.currentRoute.inputs.map { ($0.portType.rawValue, $0.portName) },
                outputs: audioSession.currentRoute.outputs.map { ($0.portType.rawValue, $0.portName) },
                sampleRateHz: audioSession.sampleRate
            )
        }) {
            Self.logger.notice("#418 route after change: \(routeDetail, privacy: .public)")
        }
        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable, .override, .routeConfigurationChange, .categoryChange:
            if voiceState == .interrupted {
                voiceState = .listening
            }
            statusMessage = "Audio route changed."
            // #19: the car taking the route (CarPlay connect mid-session)
            // needs the session category re-asserted — the WebRTC audio unit
            // configures AVAudioSession itself and can leave it shaped for
            // the previous route.
            await reassertAudioSessionForCarAudioIfNeeded()
            // Re-assert speaker output when a device is removed (e.g. headphones unplugged)
            // or the route is reconfigured by the system / WebRTC.
            // (Skips itself when car audio / headphones are attached.)
            forceSpeakerIfNeeded()
        default:
            break
        }
    }

    /// #19: with CarPlay in the route, re-apply the voice-chat category so
    /// mic capture and playback follow the car after WebRTC's own session
    /// meddling. No speaker override here — the car owns the route. Safe to
    /// call when the session is already correctly configured.
    private func reassertAudioSessionForCarAudioIfNeeded() async {
        do {
            try await AudioSessionOffMain.run(activating: true, reason: "realtime-carplay-reassert") { audioSession in
                let routeHasCarAudio = audioSession.currentRoute.outputs.contains { $0.portType == .carAudio }
                    || audioSession.currentRoute.inputs.contains { $0.portType == .carAudio }
                guard routeHasCarAudio else { return }
                try audioSession.setCategory(
                    .playAndRecord,
                    mode: .voiceChat,
                    options: [.allowBluetoothHFP]
                )
                try audioSession.setActive(true)
            }
        } catch {
            Self.logger.warning("CarPlay audio session re-assert failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// #383-C's compensation. No longer throws: every caller already treated
    /// a failed release as unrecoverable (`try?`), and the plugin acks a
    /// session it has never heard of — so there is nothing left for a thrown
    /// error to mean.
    private func endRemoteSession() async {
        guard let voiceSessionID else { return }
        await voiceTransport.talkSessionEnd(voiceSessionID: voiceSessionID.uuidString.lowercased())
    }

    // #383: `persistFinalTurn` is GONE, and this note is the record of why.
    //
    // It POSTed every realtime turn to `talk/session/{id}/turns`. Investigated
    // 2026-08-22 before the plugin half was built:
    //
    //   * nothing ever read those turns back — the POST had no GET anywhere in
    //     the app, and its response type was decoded only to be discarded;
    //   * #1's `postVoiceTranscriptsToHermes` already posts the transcript to
    //     the Sessions API as a normal text turn, which is what actually gives
    //     the agent voice context on the next exchange;
    //   * and it was gated on NOTHING — not on
    //     `UserSettings.postVoiceTranscriptsToHermes`, which #1's path IS
    //     gated on. A user who turned voice-transcript posting OFF still had
    //     every realtime turn shipped host-side by this method.
    //
    // Re-homing it onto the plugin would have rebuilt that toggle bypass
    // deliberately. Reported to Owen with a recommendation to drop; the plugin
    // half ships without `talk_turn_append` and answers `unknown_event_type`
    // for it. **If it is ever wanted back, it comes back GATED on the toggle**
    // — which is a behaviour change to be decided, not a port to be resumed.

    /// Rider: one off-main hop — category, activation, and the speaker
    /// override keep their relative order inside the closure, and callers
    /// await, so nothing downstream starts before activation completes.
    private func configureAudioSession() async throws {
        try await AudioSessionOffMain.run(activating: true, reason: "realtime-session-start") { audioSession in
            try audioSession.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetoothHFP]
            )
            try audioSession.setActive(true)

            // Force output to the speaker for maximum volume — but only when no
            // headphones or Bluetooth audio device is connected, and only when
            // the route is not already there (#138-B).
            if LiveVoiceSessionService.shouldOverrideOutputToSpeaker(
                currentOutputPortTypes: audioSession.currentRoute.outputs.map(\.portType)
            ) {
                try audioSession.overrideOutputAudioPort(.speaker)
            }
            // #418: name the route the capture actually rides, at the moment
            // the session is shaped. Logged after the override so it shows
            // the route the session will really use.
            Self.logger.notice("#418 route at session start: \(LiveVoiceSessionService.audioRouteLogDetail(inputs: audioSession.currentRoute.inputs.map { ($0.portType.rawValue, $0.portName) }, outputs: audioSession.currentRoute.outputs.map { ($0.portType.rawValue, $0.portName) }, sampleRateHz: audioSession.sampleRate), privacy: .public)")
        }
        // #302-A / #415: the capture-chain instrument, in the SAME words the
        // native pipeline uses, so one Console predicate reads both engines.
        //
        // It was missing here until #415, and that omission cost a
        // measurement: the realtime engine carried all three stuck launches
        // in the device log and the app could not say whether its own
        // microphone was hot — the forensics had to fall back to framework
        // CoreAudio `AURemoteIO` rows, which a later `log collect` may no
        // longer retain. #302's 2026-08-20 device pass scored the one engine
        // that carried the instrument, which is a large part of why it held.
        //
        // `.notice` (Console hides `.info`), `privacy: .public` (or it
        // redacts), and NEVER behind Verbose Logging. This line marks the
        // session going active; the chain is not hot until the HOT line.
        Self.logger.notice("audio session activated for capture (#302-A)")
    }

    /// **#138-B — should the output route be forced to the speaker?**
    ///
    /// Pure, so the decision is unit-testable without an audio session (the
    /// `NativeVoicePipelineService` convention). Two reasons to decline, and
    /// the second is this lane's:
    ///
    /// 1. **An external output is connected.** Headsets handle their own
    ///    volume and routing; overriding them is user-hostile. Pre-existing.
    /// 2. **The route is ALREADY the built-in speaker (#138-B).** Overriding
    ///    then is a semantic no-op that still hands CoreAudio a route
    ///    reconfiguration — and a route change makes the echo canceller
    ///    re-adapt. `forceSpeakerIfNeeded` is called twice around connect, the
    ///    second time on a 500 ms timer that lands squarely in the window where
    ///    the FIRST assistant utterance plays. Measured 2026-08-22: the
    ///    assistant's own audio leaked into the mic and was transcribed as a
    ///    user turn on **4 of 4** session starts, always the first utterance,
    ///    never later.
    ///
    /// **The earpiece case must still override**, which is what keeps this a
    /// skip rather than a deletion: `.builtInReceiver` returns true here, so a
    /// route WebRTC genuinely moved is still corrected (138-C).
    nonisolated static func shouldOverrideOutputToSpeaker(
        currentOutputPortTypes: [AVAudioSession.Port]
    ) -> Bool {
        let external: Set<AVAudioSession.Port> = [
            .headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .airPlay, .carAudio,
        ]
        if currentOutputPortTypes.contains(where: external.contains) { return false }
        if currentOutputPortTypes.contains(.builtInSpeaker) { return false }
        return true
    }

    /// Re-assert the speaker override after WebRTC (or any other subsystem) may
    /// have reset the audio route.  Safe to call at any time — skips the override
    /// when headphones, Bluetooth, AirPlay, or CarPlay are connected, and (#138-B)
    /// when the route is already the built-in speaker.
    private func forceSpeakerIfNeeded() {
        let audioSession = AVAudioSession.sharedInstance()
        guard Self.shouldOverrideOutputToSpeaker(
            currentOutputPortTypes: audioSession.currentRoute.outputs.map(\.portType)
        ) else { return }
        do {
            try audioSession.overrideOutputAudioPort(.speaker)
        } catch {
            Self.logger.warning("forceSpeakerIfNeeded: override failed — \(error.localizedDescription)")
        }
    }

    func handleDataChannelEvent(_ payload: [String: Any]) {
        let type = payload["type"] as? String ?? ""
        switch type {
        case "input_audio_buffer.speech_started":
            noteSpeechEvidence()
            handleServerVADInterruption()
            voiceState = .listening
            statusMessage = "Listening"
        case "input_audio_buffer.committed":
            noteSpeechEvidence()
            createPendingUserTranscriptItem(from: payload)
        case "conversation.item.created",  // beta
             "conversation.item.added":      // GA
            if let item = payload["item"] as? [String: Any],
               let role = item["role"] as? String,
               role == "assistant",
               let itemID = item["id"] as? String {
                // #419: emitted BEFORE the reset and BEFORE the id overwrite,
                // so both values this branch destroys are captured. The reset
                // below is the only in-session path that can zero a RUNNING
                // playback counter — this line names whether it just did.
                let elapsedMs: Int? = assistantAudioPlaybackStartedAtUptime != nil
                    ? currentAssistantAudioPlaybackMilliseconds() : nil
                Self.logger.notice("#419 \(Self.assistantItemArrivalLogDetail(eventType: type, itemID: itemID, currentItemID: self.currentAssistantConversationItemID, playbackElapsedMs: elapsedMs), privacy: .public)")
                currentAssistantConversationItemID = itemID
                currentAssistantContentIndex = 0
                resetAssistantAudioPlaybackTracking()
                ignoreCurrentAssistantFinalization = false
            }
        case "conversation.item.truncated":
            stopAssistantAudioPlaybackTracking()
            currentAssistantConversationItemID = nil
            currentRealtimeResponseID = nil
            voiceState = .listening
            statusMessage = "Listening"
        // #138: these three drive the app's ONLY model of "is the assistant
        // speaking", and the 2026-08-22 archive could not say whether they
        // arrive at all — every phantom `speech_started` logged
        // `state=listening`, which is ambiguous between "the assistant really
        // was idle" and "we never learned it started". Those two readings take
        // OPPOSITE fixes: the first makes an app-side gate viable, the second
        // makes it impossible and forces the fix server-side. Logged so the
        // next archive answers it instead of leaving it to argument.
        case "output_audio_buffer.started":
            Self.logger.notice("#138 audio.started — assistant playback begins")
            startAssistantAudioPlaybackTracking()
            voiceState = .speaking
            statusMessage = "Talaria is speaking."
        case "output_audio_buffer.stopped":
            Self.logger.notice("#138 audio.stopped after \(self.currentAssistantAudioPlaybackMilliseconds(), privacy: .public)ms")
            stopAssistantAudioPlaybackTracking()
            currentRealtimeResponseID = nil
            voiceState = .listening
            statusMessage = "Listening"
        case "output_audio_buffer.cleared":
            Self.logger.notice("#138 audio.cleared after \(self.currentAssistantAudioPlaybackMilliseconds(), privacy: .public)ms")
            stopAssistantAudioPlaybackTracking()
            currentRealtimeResponseID = nil
            voiceState = .listening
            statusMessage = "Listening"
        case "response.created":
            // #138: `create_response: true` means EVERY detection — phantom or
            // real — spawns a response. Two overlapping responses is what
            // "there's two of y'all responding" sounds like, so the arrival
            // pattern of this event is the direct evidence for or against that.
            Self.logger.notice("#138 response.created (state=\(self.voiceState.rawValue, privacy: .public))")
            currentRealtimeResponseID = ((payload["response"] as? [String: Any])?["id"] as? String)
            ignoreCurrentAssistantFinalization = false
            voiceState = .thinking
            statusMessage = "Talaria is thinking."
        case "response.function_call_arguments.delta",
             "response.function_call_arguments.done",
             "response.mcp_call_arguments.delta",
             "response.mcp_call_arguments.done",
             "response.mcp_call.in_progress":
            // Tool or MCP call in progress — show "working on it" state
            if voiceState != .thinking {
                voiceState = .thinking
            }
            statusMessage = "Talaria is working on that\u{2026}"
        case "response.mcp_call.completed":
            // MCP tool call finished — trigger a new response so the model speaks the result.
            // The response lifecycle completes BEFORE the MCP call executes, so no automatic
            // follow-up audio is generated. We must explicitly request one.
            if currentRealtimeResponseID == nil {
                _ = sendRealtimeEvent([
                    "type": "response.create",
                    "event_id": UUID().uuidString,
                ])
                voiceState = .thinking
                statusMessage = "Talaria has the answer\u{2026}"
            }
        case "response.mcp_call.failed":
            statusMessage = "A tool call failed — Talaria will try another way."
        case "response.done":
            let doneResponse = payload["response"] as? [String: Any]
            let status = doneResponse?["status"] as? String
            // If the response completed with tool calls (not "completed"), keep thinking
            // until the next response starts with the tool result.
            if status == "completed" {
                currentRealtimeResponseID = nil
            }
        case "response.audio_transcript.delta",              // beta
             "response.output_audio_transcript.delta":         // GA
            assistantTextSource = assistantTextSource ?? "audio"
            if assistantTextSource == "audio" {
                appendAssistantDelta(payload["delta"] as? String ?? "")
            }
        case "response.output_text.delta":
            assistantTextSource = assistantTextSource ?? "text"
            if assistantTextSource == "text" {
                appendAssistantDelta(payload["delta"] as? String ?? "")
            }
        case "response.audio_transcript.done",               // beta
             "response.output_audio_transcript.done":          // GA
            assistantTextSource = assistantTextSource ?? "audio"
            if assistantTextSource == "audio" {
                finalizeAssistantText(payload["transcript"] as? String ?? payload["text"] as? String)
            }
        case "response.output_text.done":
            assistantTextSource = assistantTextSource ?? "text"
            if assistantTextSource == "text" {
                finalizeAssistantText(payload["transcript"] as? String ?? payload["text"] as? String)
            }
        case "conversation.item.input_audio_transcription.delta":
            noteSpeechEvidence()
            updateUserTranscriptDelta(
                for: payload["item_id"] as? String,
                delta: payload["delta"] as? String ?? ""
            )
        case "conversation.item.input_audio_transcription.completed":
            finalizeUserText(
                itemID: payload["item_id"] as? String,
                finalText: payload["transcript"] as? String ?? ""
            )
        case "error":
            if isEndingSession {
                break
            }
            let errorPayload = payload["error"] as? [String: Any]
            let message = (errorPayload?["message"] as? String) ?? "Realtime talk failed."
            switch RealtimeErrorRule.disposition(code: errorPayload?["code"] as? String, message: message) {
            case .swallowNoOpCancel:
                // #119a: the cancel raced a response that already completed —
                // a normal race. The session is healthy; never bubble the
                // backend string into the UI or flag the connection failed.
                Self.logger.notice("no-op cancel race swallowed: \(message, privacy: .public)")
            case .swallowResponseCreateRace:
                Self.logger.notice("response.create race swallowed: \(message, privacy: .public)")
            case .surface:
                blockedReason = message
                connectionState = .failed
                voiceState = .disconnected
                statusMessage = message
            }
        default:
            break
        }
    }

    #if canImport(WebRTC)
    /// #302-A / #415: a readable peer state for the HOT line. `String(describing:)`
    /// on an imported ObjC enum prints `RTCPeerConnectionState(rawValue: 2)`,
    /// which is not what an operator reading a device archive at 2 a.m. needs.
    private static func label(_ state: RTCPeerConnectionState) -> String {
        switch state {
        case .new: "new"
        case .connecting: "connecting"
        case .connected: "connected"
        case .disconnected: "disconnected"
        case .failed: "failed"
        case .closed: "closed"
        @unknown default: "unknown"
        }
    }

    private struct PreparedWebRTC {
        let connection: RTCPeerConnection
        let channel: RTCDataChannel?
        let track: RTCAudioTrack
        let offerSDP: String
    }

    /// Phase 1: Create peer connection, audio track, data channel, and generate SDP offer.
    /// Can run in parallel with the host bootstrap request (talaria plugin, #383).
    private func prepareWebRTC() async throws -> PreparedWebRTC {
        let rtcConfig = RTCConfiguration()
        rtcConfig.sdpSemantics = .unifiedPlan
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let connection = Self.peerFactory.peerConnection(with: rtcConfig, constraints: constraints, delegate: peerDelegate) else {
            throw APIClientError.requestFailed("Failed to create WebRTC peer connection.")
        }
        let audioSource = Self.peerFactory.audioSource(with: constraints)
        let track = Self.peerFactory.audioTrack(with: audioSource, trackId: "hermes-mobile-audio")
        _ = connection.add(track, streamIds: ["hermes-mobile-stream"])
        let dataChannelConfig = RTCDataChannelConfiguration()
        let channel = connection.dataChannel(forLabel: "oai-events", configuration: dataChannelConfig)
        channel?.delegate = peerDelegate

        let offer = try await connection.createOfferAsync()
        try await connection.setLocalDescriptionAsync(offer)

        return PreparedWebRTC(connection: connection, channel: channel, track: track, offerSDP: offer.sdp)
    }

    /// Phase 2: Exchange SDP with the ephemeral key and complete the connection.
    private func connectWithPrepared(_ prepared: PreparedWebRTC, bootstrap: TalkBootstrap) async throws {
        peerConnection = prepared.connection
        dataChannel = prepared.channel
        audioTrack = prepared.track
        audioTrack?.isEnabled = !isMuted

        let answerSDP = try await exchangeSDP(
            localSDP: prepared.offerSDP,
            clientSecret: bootstrap.clientSecret,
            model: bootstrap.model
        )
        let answer = RTCSessionDescription(type: .answer, sdp: answerSDP)
        try await prepared.connection.setRemoteDescriptionAsync(answer)

        latencyMetrics.realtimeConnectedAt = .now
        // #302-A / #415: the honest instrument reads the TRANSPORT's own
        // state, not a wrapper flag — the wrapper is the thing under
        // suspicion. This is the realtime engine's equivalent of the native
        // pipeline's `AVAudioEngine.isRunning`: from here until the matching
        // COLD line, the local audio track is attached to a live peer
        // connection and microphone buffers are leaving the device. In the
        // #415 archive this is the moment `Starting AURemoteIO` appears.
        let trackEnabled = audioTrack?.isEnabled ?? false
        let peerState = Self.label(prepared.connection.connectionState)
        Self.logger.notice(
            "capture chain HOT — RTCAudioTrack.isEnabled=\(trackEnabled, privacy: .public) peerConnection=\(peerState, privacy: .public) (#302-A)")
        connectionState = .connected
        voiceState = .listening
        blockedReason = nil
        canStartSession = true
        statusMessage = "Listening"

        // #84: connected ≠ hearing you. Publish the live route and start the
        // flatline window so a dead mic surfaces as a hint, not silence.
        updateAudioRouteSummary()
        armFlatlineTripwire()

        // Re-assert speaker override AFTER WebRTC finishes its audio setup.
        // WebRTC's RTCPeerConnectionFactory reconfigures the audio session
        // internally, which can reset our overrideOutputAudioPort(.speaker).
        forceSpeakerIfNeeded()

        // WebRTC may continue adjusting the audio route asynchronously after
        // setRemoteDescription returns. Fire another override after a short
        // delay as a safety net.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            self?.forceSpeakerIfNeeded()
        }
    }

    private func exchangeSDP(localSDP: String, clientSecret: String, model: String?) async throws -> String {
        let modelName = model ?? "gpt-realtime"
        guard let url = URL(string: "https://api.openai.com/v1/realtime/calls?model=\(modelName)") else {
            throw APIClientError.invalidURL("https://api.openai.com/v1/realtime/calls")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(clientSecret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/sdp", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await urlSession.upload(for: request, from: Data(localSDP.utf8))
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw APIClientError.requestFailed(String(data: data, encoding: .utf8) ?? "OpenAI Realtime SDP exchange failed.")
        }
        return String(decoding: data, as: UTF8.self)
    }
    #endif

    private func appendAssistantDelta(_ delta: String) {
        guard !delta.isEmpty else { return }
        if let currentAssistantItemID,
           let index = transcriptItems.firstIndex(where: { $0.id == currentAssistantItemID }) {
            transcriptItems[index].text += delta
            transcriptItems[index].isPartial = true
        } else {
            let item = TranscriptItem(speaker: .hermes, text: delta, isPartial: true)
            currentAssistantItemID = item.id
            if let currentAssistantConversationItemID {
                transcriptItemIDsByConversationItemID[currentAssistantConversationItemID] = item.id
            }
            transcriptItems.append(item)
        }
    }

    private func finalizeAssistantText(_ finalText: String?) {
        if ignoreCurrentAssistantFinalization && currentAssistantItemID == nil {
            ignoreCurrentAssistantFinalization = false
            currentRealtimeResponseID = nil
            currentAssistantConversationItemID = nil
            assistantTextSource = nil
            voiceState = .listening
            statusMessage = "Listening"
            return
        }

        let text = (finalText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let turnID: UUID?
        if let currentAssistantItemID,
           let index = transcriptItems.firstIndex(where: { $0.id == currentAssistantItemID }) {
            if !text.isEmpty {
                transcriptItems[index].text = text
            }
            transcriptItems[index].isPartial = false
            turnID = transcriptItems[index].id
            if let currentAssistantConversationItemID {
                transcriptItemIDsByConversationItemID[currentAssistantConversationItemID] = transcriptItems[index].id
            }
        } else if let last = transcriptItems.last,
                  last.speaker == .hermes,
                  !last.isPartial,
                  last.text == text {
            turnID = nil
        } else if !text.isEmpty {
            let item = TranscriptItem(speaker: .hermes, text: text, isPartial: false)
            transcriptItems.append(item)
            turnID = item.id
            if let currentAssistantConversationItemID {
                transcriptItemIDsByConversationItemID[currentAssistantConversationItemID] = item.id
            }
        } else {
            turnID = nil
        }
        currentAssistantItemID = nil
        currentRealtimeResponseID = nil
        assistantTextSource = nil
        ignoreCurrentAssistantFinalization = false
        if latencyMetrics.firstAssistantFinalizedAt == nil {
            latencyMetrics.firstAssistantFinalizedAt = .now
        }
        // #419-B: transcript-done is the end of the TEXT, not of the audio.
        // Realtime emits it when generation completes, seconds ahead of
        // playout, and until 2026-09-01 this branch treated it as the end of
        // the utterance: it zeroed the playback tracker, dropped the live item
        // id, and flipped to `.listening` while the buffer was still draining.
        // Every `audio.stopped after 0ms` in the project's archives, every
        // barge-in in the tail of an utterance that sent NO truncate, and every
        // mid-playback `speech_started … assistant not playing (state=listening)`
        // line was this. While playback is live the audio-buffer lifecycle
        // (`output_audio_buffer.stopped/cleared`, `conversation.item.truncated`)
        // owns all three; only an audio-less response finalizes here.
        if assistantAudioPlaybackStartedAtUptime == nil {
            currentAssistantConversationItemID = nil
            resetAssistantAudioPlaybackTracking()
            voiceState = .listening
            statusMessage = "Listening"
        }
    }

    private func createPendingUserTranscriptItem(from payload: [String: Any]) {
        let itemID = (payload["item_id"] as? String) ?? ((payload["item"] as? [String: Any])?["id"] as? String)
        guard let itemID else { return }
        currentUserConversationItemID = itemID
        guard transcriptItemIDsByConversationItemID[itemID] == nil else { return }

        let placeholder = TranscriptItem(speaker: .user, text: "\u{2026}", isPartial: true)
        let insertIndex: Int
        if let previousItemID = payload["previous_item_id"] as? String,
           let previousTranscriptID = transcriptItemIDsByConversationItemID[previousItemID],
           let previousIndex = transcriptItems.firstIndex(where: { $0.id == previousTranscriptID }) {
            insertIndex = min(previousIndex + 1, transcriptItems.count)
        } else {
            insertIndex = transcriptItems.count
        }

        transcriptItems.insert(placeholder, at: insertIndex)
        transcriptItemIDsByConversationItemID[itemID] = placeholder.id
    }

    private func updateUserTranscriptDelta(for itemID: String?, delta: String) {
        guard !delta.isEmpty,
              let itemID,
              let transcriptID = transcriptItemIDsByConversationItemID[itemID],
              let index = transcriptItems.firstIndex(where: { $0.id == transcriptID }) else {
            return
        }
        if transcriptItems[index].text == "\u{2026}" {
            transcriptItems[index].text = delta
        } else {
            transcriptItems[index].text += delta
        }
        transcriptItems[index].isPartial = true
    }

    private func finalizeUserText(itemID: String?, finalText: String) {
        let text = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedItemID = itemID ?? currentUserConversationItemID
        if text.isEmpty {
            if let resolvedItemID,
               let transcriptID = transcriptItemIDsByConversationItemID.removeValue(forKey: resolvedItemID),
               let index = transcriptItems.firstIndex(where: { $0.id == transcriptID }) {
                transcriptItems.remove(at: index)
            }
            currentUserConversationItemID = nil
            return
        }
        let turnID: UUID
        if let resolvedItemID,
           let transcriptID = transcriptItemIDsByConversationItemID[resolvedItemID],
           let index = transcriptItems.firstIndex(where: { $0.id == transcriptID }) {
            transcriptItems[index].text = text
            transcriptItems[index].isPartial = false
            turnID = transcriptItems[index].id
        } else if let last = transcriptItems.last,
                  last.speaker == .user,
                  !last.isPartial,
                  last.text == text {
            return
        } else {
            let item = TranscriptItem(speaker: .user, text: text, isPartial: false)
            transcriptItems.append(item)
            turnID = item.id
            if let resolvedItemID {
                transcriptItemIDsByConversationItemID[resolvedItemID] = item.id
            }
        }
        currentUserConversationItemID = nil
        if latencyMetrics.firstUserFinalizedAt == nil {
            latencyMetrics.firstUserFinalizedAt = .now
        }
        voiceState = .thinking
        statusMessage = "Talaria is thinking."
    }

    private func startAssistantAudioPlaybackTracking() {
        if assistantAudioPlaybackStartedAtUptime == nil {
            assistantAudioPlaybackStartedAtUptime = ProcessInfo.processInfo.systemUptime
        }
    }

    private func stopAssistantAudioPlaybackTracking() {
        accumulatedAssistantAudioPlaybackMilliseconds = currentAssistantAudioPlaybackMilliseconds()
        assistantAudioPlaybackStartedAtUptime = nil
    }

    private func resetAssistantAudioPlaybackTracking() {
        assistantAudioPlaybackStartedAtUptime = nil
        accumulatedAssistantAudioPlaybackMilliseconds = 0
    }

    // MARK: - #418/#419 log-line formatters (pure — pinned in VoiceInstrumentLogLineTests)

    /// #419: describes an assistant `conversation.item.created`/`.added`
    /// arrival. Two discriminations are load-bearing and separately pinned:
    /// same-item-re-announced vs new-item (separates the beta/GA double-fire
    /// candidate from the second-item candidate), and mid-playback vs idle
    /// (mid-playback is the counter-zeroing event this instrument exists to
    /// catch — the elapsed value it names is the one the reset destroys).
    nonisolated static func assistantItemArrivalLogDetail(
        eventType: String,
        itemID: String,
        currentItemID: String?,
        playbackElapsedMs: Int?
    ) -> String {
        let relation: String
        if currentItemID == nil {
            relation = "first assistant item"
        } else if currentItemID == itemID {
            relation = "same item re-announced"
        } else {
            relation = "new item (replacing \(currentItemID ?? "?"))"
        }
        let playback: String
        if let elapsedMs = playbackElapsedMs {
            playback = "MID-PLAYBACK: resetting tracker at \(elapsedMs)ms"
        } else {
            playback = "assistant idle"
        }
        return "\(eventType) \(itemID) — \(relation) — \(playback)"
    }

    /// #418: describes the audio route + capture sample rate. Every port is
    /// listed (an empty list says "none" rather than rendering blank) because
    /// the whole question is WHICH input the capture rode — a line that
    /// dropped ports would be #419's defect wearing #418's number.
    nonisolated static func audioRouteLogDetail(
        inputs: [(portType: String, portName: String)],
        outputs: [(portType: String, portName: String)],
        sampleRateHz: Double
    ) -> String {
        func list(_ ports: [(portType: String, portName: String)]) -> String {
            guard !ports.isEmpty else { return "[none]" }
            return "[" + ports.map { "\($0.portType) \"\($0.portName)\"" }.joined(separator: ", ") + "]"
        }
        return "in=\(list(inputs)) out=\(list(outputs)) sampleRate=\(Int(sampleRateHz))Hz"
    }

    /// **#396-Q — the tuning preset the app actually minted with.** Pure,
    /// pinned by `VoiceInstrumentLogLineTests`.
    ///
    /// #413's 2026-08-26 device pass measured a per-session phantom rate while
    /// Owen switched between the Noisy and Normal presets, and the archive
    /// cannot attribute those sessions to a preset — the pick reached the
    /// plugin as a request field and left no trace in the phone's own record.
    ///
    /// **`values=host` is not a placeholder.** 396-P's ruled design resolves
    /// the vetted `server_vad` numbers HOST-side; the app composes no
    /// `turn_detection` block and sends only a NAME, so the line states where
    /// the values live rather than inventing a threshold it never sent.
    ///
    /// `hostTunings` is the readiness probe's advertised list: nil means the
    /// host's plugin predates tuning and IGNORES the field, so the pick does
    /// not bind. The line says that outright — the same honesty the picker's
    /// own footnote carries.
    nonisolated static func sessionTuningLogDetail(
        preset: String,
        engine: String,
        hostTunings: [String]?
    ) -> String {
        let accepts: String
        if let hostTunings {
            accepts = hostTunings.isEmpty ? "[none]" : "[" + hostTunings.joined(separator: ",") + "]"
        } else {
            accepts = "unknown (host predates tuning)"
        }
        return "#396 tuning preset=\(preset) engine=\(engine) values=host hostAccepts=\(accepts)"
    }

    /// #419-B: `// harness-visible` — the same value the `audio.stopped after Nms`
    /// line prints and the truncate carries, so the pins read the instrument
    /// rather than a shadow of it.
    func currentAssistantAudioPlaybackMilliseconds() -> Int { // harness-visible
        guard let startedAt = assistantAudioPlaybackStartedAtUptime else {
            return accumulatedAssistantAudioPlaybackMilliseconds
        }
        let elapsed = max(0, ProcessInfo.processInfo.systemUptime - startedAt)
        return accumulatedAssistantAudioPlaybackMilliseconds + Int((elapsed * 1000).rounded())
    }

    /// Called when server VAD detects user speech (`input_audio_buffer.speech_started`).
    ///
    /// The session config already enables `interrupt_response`, which asks the server
    /// to automatically cancel the in-flight response on VAD start. The client still
    /// needs to cut off any buffered playback locally and truncate the assistant item
    /// to the portion the user actually heard.
    /// **#138: the barge-in event, and until 2026-08-22 it was SILENT.**
    ///
    /// This is the one moment that answers *"was the assistant cut off?"*, and
    /// it logged nothing — so the question had to be answered from the live
    /// transcript, which **structurally cannot answer it**. Realtime generates
    /// text ahead of audio playout, so a response whose AUDIO is cancelled
    /// mid-sentence still shows a COMPLETE sentence in the transcript. Reading
    /// completeness as "not interrupted" produced a wrong verdict on
    /// 2026-08-22, corrected by Owen from what he actually heard.
    ///
    /// Both arms log, because the distinction is the measurement: fired while
    /// the assistant was SPEAKING is a barge-in (self-inflicted when the audio
    /// is our own echo); fired while it was not is speech detected in silence,
    /// which is a phantom TURN without an interruption. #138 has both symptoms
    /// and they had no way to be told apart.
    private func handleServerVADInterruption() {
        let elapsed = assistantAudioPlaybackStartedAtUptime.map {
            String(format: "%.2f", ProcessInfo.processInfo.systemUptime - $0)
        } ?? "n/a"
        guard voiceState == .speaking || assistantAudioPlaybackStartedAtUptime != nil else {
            // Deliberately NOT called "phantom" — that was this line's first
            // wording and it baked in a conclusion the log cannot support.
            // speech_started while the assistant is idle is ALSO exactly what a
            // legitimate user turn looks like, and the 2026-08-22 20:13 archive
            // opened with one: Owen's own greeting, labelled "phantom" by this
            // very line. Echo is distinguished by ARRIVING DURING PLAYBACK, not
            // by this branch — so the branch reports what it saw and nothing more.
            Self.logger.notice("#138 speech_started, assistant not playing (state=\(self.voiceState.rawValue, privacy: .public))")
            return
        }
        Self.logger.notice("#138 BARGE-IN: assistant audio cancelled \(elapsed, privacy: .public)s into playback (state=\(self.voiceState.rawValue, privacy: .public))")
        interruptAssistantOutput(sendCancelAndClear: true)
    }

    /// Called when the user explicitly requests interruption (e.g., a stop button).
    ///
    /// Unlike VAD-triggered interruption, the server has NOT auto-cancelled, so we
    /// must send the full sequence: cancel → clear → truncate.
    func manuallyInterruptAssistantOutput() {
        guard voiceState == .speaking || assistantAudioPlaybackStartedAtUptime != nil else { return }
        interruptAssistantOutput(sendCancelAndClear: true)
        voiceState = .listening
        statusMessage = "Listening"
    }

    private func interruptAssistantOutput(sendCancelAndClear: Bool) {
        if sendCancelAndClear, let responseID = currentRealtimeResponseID {
            if !sendRealtimeEvent([
                "type": "response.cancel",
                "event_id": UUID().uuidString,
                "response_id": responseID,
            ]) {
                Self.logger.warning("Failed to send response.cancel for response \(responseID)")
            }
        }

        if sendCancelAndClear, !sendRealtimeEvent([
            "type": "output_audio_buffer.clear",
            "event_id": UUID().uuidString,
        ]) {
            Self.logger.warning("Failed to send output_audio_buffer.clear")
        }

        truncateAndCleanUpAssistantState()
    }

    /// Shared cleanup: sends `conversation.item.truncate` and resets local tracking state.
    private func truncateAndCleanUpAssistantState() {
        if let itemID = currentAssistantConversationItemID {
            let audioMs = currentAssistantAudioPlaybackMilliseconds()
            if !sendRealtimeEvent([
                "type": "conversation.item.truncate",
                "event_id": UUID().uuidString,
                "item_id": itemID,
                "content_index": currentAssistantContentIndex,
                "audio_end_ms": audioMs,
            ]) {
                Self.logger.warning("Failed to send conversation.item.truncate for item \(itemID) at \(audioMs)ms")
            }
        }

        stopAssistantAudioPlaybackTracking()
        freezeCurrentAssistantTurnForInterruption()
        currentRealtimeResponseID = nil
        currentAssistantConversationItemID = nil
    }

    private func freezeCurrentAssistantTurnForInterruption() {
        if let currentAssistantItemID,
           let index = transcriptItems.firstIndex(where: { $0.id == currentAssistantItemID }) {
            transcriptItems[index].isPartial = false
            if let currentAssistantConversationItemID {
                transcriptItemIDsByConversationItemID[currentAssistantConversationItemID] = currentAssistantItemID
            }
        }
        currentAssistantItemID = nil
        assistantTextSource = nil
        ignoreCurrentAssistantFinalization = true
    }

    private func sendRealtimeEvent(_ payload: [String: Any]) -> Bool {
        guard JSONSerialization.isValidJSONObject(payload) else {
            Self.logger.warning("Realtime event payload was not valid JSON: \(String(describing: payload["type"]))")
            return false
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            if let realtimeEventTransportOverride {
                return realtimeEventTransportOverride(data)
            }
            #if canImport(WebRTC)
            guard let dataChannel, dataChannel.readyState == .open else {
                Self.logger.warning("Realtime event transport unavailable for event: \(String(describing: payload["type"]))")
                return false
            }
            return dataChannel.sendData(RTCDataBuffer(data: data, isBinary: false))
            #else
            Self.logger.warning("Realtime event transport unavailable in non-WebRTC build for event: \(String(describing: payload["type"]))")
            return false
            #endif
        } catch {
            Self.logger.warning("Failed to encode realtime event \(String(describing: payload["type"])): \(error.localizedDescription)")
            return false
        }
    }
}

#if canImport(WebRTC)
private final class RealtimePeerDelegate: NSObject, RTCPeerConnectionDelegate, RTCDataChannelDelegate, @unchecked Sendable {
    weak var owner: LiveVoiceSessionService?

    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        let state = dataChannel.readyState
        Task { @MainActor [weak self] in
            guard let owner = self?.owner else { return }
            if owner.isEndingSession {
                return
            }
            switch state {
            case .open:
                owner.connectionState = .connected
                owner.voiceState = .listening
                owner.statusMessage = "Listening"
            case .closed, .closing:
                owner.connectionState = .failed
                owner.voiceState = .disconnected
                owner.statusMessage = "Connection lost."
            default:
                break
            }
        }
    }

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        guard !buffer.isBinary,
              let text = String(data: buffer.data, encoding: .utf8),
              let data = text.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return
        }

        Task { @MainActor in
            owner?.handleDataChannelEvent(payload)
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        dataChannel.delegate = self
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCPeerConnectionState) {
        Task { @MainActor in
            guard let owner else { return }
            if owner.isEndingSession {
                return
            }
            switch stateChanged {
            case .connected:
                if owner.latencyMetrics.realtimeConnectedAt == nil {
                    owner.latencyMetrics.realtimeConnectedAt = .now
                }
                owner.connectionState = .connected
                owner.voiceState = .listening
                owner.statusMessage = "Listening"
            case .failed, .disconnected, .closed:
                owner.connectionState = .failed
                owner.voiceState = .disconnected
                owner.statusMessage = "Talk connection lost."
            default:
                break
            }
        }
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didStartReceivingOn transceiver: RTCRtpTransceiver) {}
}

private extension RTCPeerConnection {
    func createOfferAsync() async throws -> RTCSessionDescription {
        try await withCheckedThrowingContinuation { continuation in
            self.offer(for: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil), completionHandler: { sdp, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let sdp {
                    continuation.resume(returning: sdp)
                } else {
                    continuation.resume(throwing: APIClientError.requestFailed("Failed to create WebRTC offer."))
                }
            })
        }
    }

    func setLocalDescriptionAsync(_ description: RTCSessionDescription) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            self.setLocalDescription(description) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func setRemoteDescriptionAsync(_ description: RTCSessionDescription) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            self.setRemoteDescription(description) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
#endif
