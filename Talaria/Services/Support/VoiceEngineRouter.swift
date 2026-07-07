import Foundation
import os

/// One seam, two voice engines (#18) — the Talk-mode sibling of
/// `ChatBackendRouter`. Owns the relay-bootstrapped OpenAI Realtime engine
/// (`LiveVoiceSessionService`) and the on-device pipeline
/// (`NativeVoicePipelineService`), and presents itself to TalkStore as the
/// single `any VoiceSessionServiceProtocol` it already knows.
///
/// Routing rules:
/// - Never-paired device → local voice unconditionally (the relay bootstrap
///   can't exist; matches the #31 standalone posture).
/// - Paired: the Realtime engine wins. `talk/readiness` reporting
///   `configured:false` (no OpenAI key host-side) or an unreachable relay
///   (probe failed) routes to local voice.
/// - A Realtime start that fails for non-permission reasons falls back to
///   local voice for THAT session — a wedged relay (#24f) must not kill
///   voice outright. Microphone denial blocks both engines identically, so
///   it surfaces honestly instead of bouncing.
/// - The switch is never silent: the snapshot's `engine` tag drives the
///   overlay header, the Voice settings hero, and the transcript hand-off.
@MainActor
final class VoiceEngineRouter: VoiceSessionServiceProtocol {
    private static let logger = Logger(subsystem: "org.aethyrion.talaria", category: "VoiceEngineRouter")

    private let realtime: any VoiceSessionServiceProtocol
    private let native: any VoiceSessionServiceProtocol
    /// Relay pairing is the Realtime engine's existence signal — without it
    /// there is no `talk/session` bootstrap to attempt.
    private let isRelayPaired: @MainActor () -> Bool
    private let eventHub = TalkSessionEventHub()
    private var forwardTasks: [Task<Void, Never>] = []

    private(set) var activeEngine: VoiceEngine

    init(
        realtime: any VoiceSessionServiceProtocol,
        native: any VoiceSessionServiceProtocol,
        isRelayPaired: @escaping @MainActor () -> Bool
    ) {
        self.realtime = realtime
        self.native = native
        self.isRelayPaired = isRelayPaired
        self.activeEngine = isRelayPaired() ? .realtime : .native
        forward(from: realtime, engine: .realtime)
        forward(from: native, engine: .native)
    }

    deinit {
        for task in forwardTasks { task.cancel() }
    }

    private var active: any VoiceSessionServiceProtocol {
        activeEngine == .realtime ? realtime : native
    }

    // MARK: - Routing decisions (pure, unit-tested)

    /// After a readiness probe on the Realtime engine: route local when the
    /// relay says talk isn't configured, or the probe couldn't reach it.
    nonisolated static func shouldRouteNative(
        configured: Bool?,
        connectionState: TalkConnectionState
    ) -> Bool {
        if configured == false { return true }
        if connectionState == .failed { return true }
        return false
    }

    /// After a Realtime start attempt: fall back to local voice unless the
    /// start actually took (connecting/connected) or failed on the
    /// microphone permission — which blocks the native engine identically.
    nonisolated static func shouldFallBackToNative(
        connectionState: TalkConnectionState,
        blockedReason: String?
    ) -> Bool {
        switch connectionState {
        case .connected, .connecting:
            return false
        default:
            break
        }
        if blockedReason?.localizedCaseInsensitiveContains("microphone") == true {
            return false
        }
        return true
    }

    // MARK: - VoiceSessionServiceProtocol

    var snapshot: TalkSessionSnapshot { active.snapshot }
    var voiceState: VoiceState { active.voiceState }
    var connectionState: TalkConnectionState { active.connectionState }
    var transcriptItems: [TranscriptItem] { active.transcriptItems }
    var sessionDuration: TimeInterval { active.sessionDuration }
    var isMuted: Bool { active.isMuted }
    var blockedReason: String? { active.blockedReason }
    var statusMessage: String? { active.statusMessage }
    var canStartSession: Bool { active.canStartSession }
    var latencyMetrics: TalkLatencyMetrics { active.latencyMetrics }

    func events() -> AsyncStream<TalkSessionEvent> {
        eventHub.stream(initial: active.snapshot)
    }

    func refreshReadiness() async {
        // Never re-route under an active session — no silent engine swaps.
        if connectionState == .connected || connectionState == .connecting {
            await active.refreshReadiness()
            return
        }
        guard isRelayPaired() else {
            setActive(.native)
            await native.refreshReadiness()
            return
        }
        await realtime.refreshReadiness()
        let probed = realtime.snapshot
        if Self.shouldRouteNative(
            configured: probed.readiness.configured,
            connectionState: probed.connectionState
        ) {
            Self.logger.notice("readiness routed voice to the native engine (configured=\(String(describing: probed.readiness.configured), privacy: .public), state=\(probed.connectionState.rawValue, privacy: .public))")
            setActive(.native)
            await native.refreshReadiness()
        } else {
            setActive(.realtime)
        }
    }

    func startSession() async {
        if activeEngine == .realtime, isRelayPaired() {
            await realtime.startSession()
            let attempted = realtime.snapshot
            if Self.shouldFallBackToNative(
                connectionState: attempted.connectionState,
                blockedReason: attempted.blockedReason
            ) {
                Self.logger.notice("Realtime start failed (\(attempted.blockedReason ?? "no reason", privacy: .public)) — falling back to local voice for this session")
                setActive(.native)
                await native.startSession()
            }
            return
        }
        setActive(.native)
        await native.startSession()
    }

    func endSession() async {
        await active.endSession()
    }

    func toggleMute() async {
        await active.toggleMute()
    }

    func manuallyInterruptAssistantOutput() {
        active.manuallyInterruptAssistantOutput()
    }

    @discardableResult
    func sendImage(_ imageData: Data, mimeType: String, triggerResponse: Bool) -> Bool {
        active.sendImage(imageData, mimeType: mimeType, triggerResponse: triggerResponse)
    }

    // MARK: - Event plumbing

    /// TalkStore subscribes once, so the router's stream must stay live
    /// across engine switches: both engines are consumed permanently and
    /// only the active one's snapshots pass through.
    private func forward(from service: any VoiceSessionServiceProtocol, engine: VoiceEngine) {
        let stream = service.events()
        let task = Task { @MainActor [weak self] in
            for await event in stream {
                guard let self, self.activeEngine == engine else { continue }
                if case .snapshot(let snapshot) = event {
                    self.eventHub.publish(snapshot: snapshot)
                }
            }
        }
        forwardTasks.append(task)
    }

    private func setActive(_ engine: VoiceEngine) {
        guard activeEngine != engine else { return }
        activeEngine = engine
        Self.logger.notice("active voice engine → \(engine.rawValue, privacy: .public)")
        eventHub.publish(snapshot: active.snapshot)
    }
}
