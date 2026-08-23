import Foundation
import os

/// One seam, two voice engines (#18) — the Talk-mode sibling of
/// `ChatBackendRouter`. Owns the host-bootstrapped OpenAI Realtime engine
/// (`LiveVoiceSessionService`) and the on-device pipeline
/// (`NativeVoicePipelineService`), and presents itself to TalkStore as the
/// single `any VoiceSessionServiceProtocol` it already knows.
///
/// **#383: the bootstrap host is the talaria plugin, not the relay.** The
/// rules below are unchanged in substance — read "voice host" wherever this
/// used to say "relay", and note that the existence signal is now the
/// platform link rather than relay pairing (see `isVoiceHostPaired`, whose
/// old spelling was this item's finding #1).
///
/// Routing rules:
/// - No voice host → local voice unconditionally (there is no bootstrap to
///   attempt; matches the #31 standalone posture).
/// - Otherwise the Realtime engine wins. Readiness reporting
///   `configured:false` (no OpenAI key host-side) or an unreachable host
///   (probe failed) routes to local voice.
/// - A Realtime start that fails for non-permission reasons falls back to
///   local voice for THAT session — a wedged host must not kill voice
///   outright. Microphone denial blocks both engines identically, so it
///   surfaces honestly instead of bouncing.
/// - The switch is never silent: the snapshot's `engine` tag drives the
///   overlay header, the Voice settings hero, and the transcript hand-off.
@MainActor
final class VoiceEngineRouter: VoiceSessionServiceProtocol {
    private static let logger = Logger(subsystem: "org.aethyrion.talaria", category: "VoiceEngineRouter")

    private let realtime: any VoiceSessionServiceProtocol
    private let native: any VoiceSessionServiceProtocol
    /// A reachable talaria plugin link is the Realtime engine's existence
    /// signal — without it there is no bootstrap to attempt.
    ///
    /// **#383 finding #1 lived on this line.** It read relay pairing, so when
    /// the relay was retired the gate could never open again and realtime was
    /// unselectable. Four router tests asserted "it selects realtime" while
    /// stubbing this predicate to always-true, which is why 2,455 green tests
    /// missed it.
    private let isVoiceHostPaired: @MainActor () -> Bool
    /// #221: the user's brain selection, read live. Voice must honour the same
    /// choice chat does — see `realtimeIsPermitted(for:)`.
    private let activeBrain: @MainActor () -> ChatBackendRouter.Brain
    private let eventHub = TalkSessionEventHub()
    private var forwardTasks: [Task<Void, Never>] = []

    private(set) var activeEngine: VoiceEngine

    /// #139: monotonic start intent, bumped by `endSession()`.
    ///
    /// The fallback below runs AFTER the realtime start resolves — seconds
    /// later on a slow host, 12s on a black hole — and until this existed
    /// nothing in that path asked whether the session was still wanted. So a
    /// user who dismissed during ESTABLISHING LINK got a LOCAL microphone
    /// opened by the very belt (#247 B1) that was added to bound the hang.
    /// Every realtime resolution reaches that branch: `.failed` and `.idle`
    /// both land in `shouldFallBackToNative`'s `default: return true`, and
    /// `.idle` is precisely what the user's own `endSession()` leaves behind.
    private var startGeneration = 0

    init(
        realtime: any VoiceSessionServiceProtocol,
        native: any VoiceSessionServiceProtocol,
        isVoiceHostPaired: @escaping @MainActor () -> Bool,
        activeBrain: @escaping @MainActor () -> ChatBackendRouter.Brain
    ) {
        self.realtime = realtime
        self.native = native
        self.isVoiceHostPaired = isVoiceHostPaired
        self.activeBrain = activeBrain
        // #221: the brain gates realtime BEFORE pairing is consulted.
        let initial: VoiceEngine = (Self.realtimeIsPermitted(for: activeBrain()) && isVoiceHostPaired())
            ? .realtime : .native
        self.activeEngine = initial
        // #198A: log the INITIAL selection, not just changes.
        //
        // `setActive` guards on `activeEngine != engine`, so a session that
        // never switches engines produced NO line at all — and this default is
        // assigned here, outside it. The consequence was not theoretical: the
        // 2026-08-01 real-interruption test (A1) ran two live phone calls with a
        // second person's time, and afterwards **the log could not say which
        // engine had been tested.** It was reconstructed only by noticing the
        // ABSENCE of any router line and back-inferring from pairing state.
        //
        // A device verdict that cannot name its own configuration is not a
        // verdict. Say it once, up front, always.
        Self.logger.notice("active voice engine → \(initial.rawValue, privacy: .public) (initial; voiceHostPaired=\(isVoiceHostPaired(), privacy: .public))")
        forward(from: realtime, engine: .realtime)
        forward(from: native, engine: .native)
    }

    deinit {
        for task in forwardTasks { task.cancel() }
    }

    private var active: any VoiceSessionServiceProtocol {
        activeEngine == .realtime ? realtime : native
    }

    /// #247 B1: the realtime start's whole budget. A black-holed relay (drop,
    /// not refuse) otherwise rides the shared 300s-timeout client and pins
    /// "ESTABLISHING LINK" until a force quit; at the deadline the start is
    /// cancelled and this session falls back to local voice. Var, not let:
    /// the suite shortens it. // harness-visible
    var realtimeStartTimeout: Duration = .seconds(12)

    // MARK: - Routing decisions (pure, unit-tested)

    /// After a readiness probe on the Realtime engine: route local when the
    /// relay says talk isn't configured, or the probe couldn't reach it.
    /// #221: **the brain selection governs voice, not just chat.**
    ///
    /// Owen, 2026-08-01: *"on device should signify everything on device. Local.
    /// When hermes is selected, it switches to using hermes' resources."*
    ///
    /// Until this existed, `VoiceEngineRouter` keyed on relay pairing alone and
    /// had **no reference to the brain at all**, so a user who had chosen the
    /// on-device brain had their microphone audio streamed to OpenAI Realtime
    /// and was billed for it — silently, because nothing logged the engine
    /// either (#198A). Chat obeyed the setting; voice did not.
    ///
    /// `.privateCloud` is forbidden too: PCC is Apple's compute, not Hermes',
    /// so "when hermes is selected" does not cover it — and the architecture
    /// already agrees, since `Brain.privateCloud` is routed to the local backend
    /// which owns the PCC session.
    ///
    /// **This is a HARD gate, deliberately.** Pairing state and a healthy
    /// readiness probe must not be able to re-admit realtime once the brain has
    /// forbidden it: pairing is precisely the input that used to decide alone,
    /// and it must no longer be able to win.
    nonisolated static func realtimeIsPermitted(for brain: ChatBackendRouter.Brain) -> Bool {
        brain == .hermes
    }

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
        blockedReason: String?,
        timedOut: Bool = false
    ) -> Bool {
        // #247 B1: the microphone exemption outranks everything — a mic
        // denial blocks BOTH engines, so bouncing just moves the dead end.
        if blockedReason?.localizedCaseInsensitiveContains("microphone") == true {
            return false
        }
        switch connectionState {
        case .connected:
            return false
        case .connecting:
            // #247 B1: a start that RETURNED still connecting may finish
            // asynchronously — but a TIMED-OUT start already had its whole
            // budget and doesn't get to keep "still connecting" as an
            // excuse. This is the branch Owen's ESTABLISHING LINK lockup
            // lived in: a black-holed relay rode the shared 300s client.
            return timedOut
        default:
            break
        }
        return true
    }

    // MARK: - VoiceSessionServiceProtocol

    /// #180 lane 180-L: deliberately NOT stamped with `activeEngine`. Before
    /// anything has run, `activeEngine` is only the init GUESS (brain-permitted
    /// ∧ relay-paired) — stamping it here would put that guess on the overlay
    /// header as a selected engine, which is the exact defect 180-C removes.
    /// `forward(from:engine:)` stamps what actually produced a snapshot.
    ///
    /// **#320: one narrow exception, and it is provenance rather than a guess.**
    /// `LiveVoiceSessionService` never stamps its own snapshots (only
    /// `NativeVoicePipelineService` does, `:71`), so on the realtime path the
    /// engine reached `TalkStore` **only** through the event stream above —
    /// while `TalkStore` ALSO calls `applySnapshot(voiceService.snapshot)`
    /// directly at every decision point (`startSession`, `toggleMute`,
    /// `interruptAssistant`, …). Each of those pulled an unstamped snapshot and
    /// wrote `voiceEngine = nil` over a stamp the push path had already
    /// delivered, so a live realtime session's engine blinked out until the
    /// next event happened to arrive. That was survivable for the header; it is
    /// not survivable for #320's realtime indicator, whose whole job is to be
    /// true for the duration of the session rather than most of it.
    ///
    /// The guard keeps 180-L's rule intact. It stamps only when the active
    /// service is **actually driving** (`.connecting`/`.connected`), which is
    /// the same fact `forward(from:engine:)` publishes — this snapshot came out
    /// of that service — and it never overwrites an engine the service stamped
    /// itself. Every pre-session state (`.idle`, `.checking`, `.ready`,
    /// `.blocked`, `.failed`) still returns UNKNOWN, so the init guess can no
    /// more reach the header now than it could before.
    var snapshot: TalkSessionSnapshot {
        var built = active.snapshot
        guard built.engine == nil else { return built }
        switch built.connectionState {
        case .connecting, .connected:
            built.engine = activeEngine
        case .idle, .checking, .ready, .blocked, .failed:
            break
        }
        return built
    }
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
        // #221: the brain gate comes FIRST — before pairing, before the probe.
        // A forbidden brain must not be able to reach the realtime probe at all,
        // because a healthy probe is exactly what used to select realtime.
        guard Self.realtimeIsPermitted(for: activeBrain()) else {
            if activeEngine != .native {
                Self.logger.notice("brain \(self.activeBrain().rawValue, privacy: .public) forbids realtime voice — routing native (#221)")
            }
            setActive(.native)
            await native.refreshReadiness()
            return
        }
        // #383: this used to read RELAY pairing, and that is why realtime
        // voice silently fell back to the local pipeline after the relay was
        // retired — the gate could never open again. It now asks whether a
        // voice HOST is reachable at all; the readiness probe just below is
        // the real verdict, and it can now distinguish ready / not-configured
        // / host-too-old / unreachable, which the relay's boolean never could.
        guard isVoiceHostPaired() else {
            Self.logger.notice("no voice host — routing native")
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
        // #198A: name the engine at the START of every session, unconditionally.
        //
        // This is the line a device verdict quotes. `setActive` fires only on a
        // CHANGE and the init default is assigned outside it, so a session that
        // simply used the default engine start-to-finish left NO trace of which
        // engine that was. Two real phone calls were spent before anyone noticed
        // the record could not answer "local or realtime?".
        // `self.` is required: os_log interpolations are autoclosures.
        Self.logger.notice("voice session starting on engine \(self.activeEngine.rawValue, privacy: .public) (voiceHostPaired=\(self.isVoiceHostPaired(), privacy: .public))")
        // #139: claim this start's generation before the first await.
        startGeneration &+= 1
        let generation = startGeneration
        // #221: last line of defence. `refreshReadiness` may not have run since
        // the user changed brain, so re-check here rather than trusting
        // `activeEngine` — the whole defect was a stale routing decision nobody
        // re-evaluated.
        if activeEngine == .realtime, !Self.realtimeIsPermitted(for: activeBrain()) {
            Self.logger.notice("brain \(self.activeBrain().rawValue, privacy: .public) forbids realtime voice — starting native instead (#221)")
            setActive(.native)
            await native.startSession()
            return
        }
        if activeEngine == .realtime, isVoiceHostPaired() {
            // #247 B1: belt the start. A REFUSED relay fails fast and the
            // fallback below always ran; a BLACK-HOLED one (tailnet drop)
            // rode the shared 300s-timeout client and pinned ESTABLISHING
            // LINK until a force quit. The belt cancels the start at the
            // deadline — cancellation aborts the underlying bootstrap
            // request, so the await returns — and a timed-out start falls
            // back to local voice like any failed one.
            let start = Task { await realtime.startSession() }
            let belt = Task { [timeout = realtimeStartTimeout] in
                try? await Task.sleep(for: timeout)
                start.cancel()
            }
            await start.value
            let timedOut = belt.isCancelled == false && start.isCancelled
            belt.cancel()
            let attempted = realtime.snapshot
            // #139: the user dismissed while the realtime start was in flight.
            // Falling back now would open a LOCAL microphone for a session
            // nobody is in — the privacy defect, arriving by the fallback door.
            if generation != startGeneration {
                Self.logger.notice("voice start abandoned mid-connect — not falling back to local voice (#139)")
                return
            }
            if Self.shouldFallBackToNative(
                connectionState: attempted.connectionState,
                blockedReason: attempted.blockedReason,
                timedOut: timedOut
            ) {
                let cause = timedOut
                    ? "timed out after \(realtimeStartTimeout)"
                    : "failed (\(attempted.blockedReason ?? "no reason"))"
                Self.logger.notice("Realtime start \(cause, privacy: .public) — falling back to local voice for this session (#247)")
                // **#397: end what we are abandoning, BEFORE opening the local
                // mic.** `start.cancel()` above cancels a Swift Task — it does
                // not tear down a peer connection. A start that times out at 12 s
                // but whose WebRTC connection completes a moment later leaves
                // `LiveVoiceSessionService` holding a live session, and the line
                // below then starts the native engine beside it: two engines, two
                // voices, each hearing the other.
                //
                // The severity is privacy rather than audio — a surviving
                // realtime session is a live microphone streaming to OpenAI for a
                // session the app believes it is not in. That is #139's shape.
                //
                // Safe here specifically because `generation == startGeneration`
                // was just checked: this branch provably owns the session. The
                // #139 abandonment branch above does NOT own it (a NEW start also
                // bumps the generation), so it is deliberately left alone — see
                // #397-C.
                await realtime.endSession()
                setActive(.native)
                await native.startSession()
            }
            return
        }
        setActive(.native)
        await native.startSession()
    }

    func endSession() async {
        // #139: revoke any start still in flight, so the post-start fallback
        // above knows the session was abandoned rather than merely unlucky.
        startGeneration &+= 1
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
                if case .snapshot(var snapshot) = event {
                    // #180 lane 180-L: stamp the engine that PRODUCED this
                    // snapshot. The router already knows — it is the loop's
                    // own constant — and it was the value being left unwritten.
                    // Only NativeVoicePipelineService stamped its own, so a
                    // realtime snapshot arrived unstamped and every reader fell
                    // back to `TalkSessionSnapshot.engine`'s default. This is a
                    // FACT (a snapshot really did come out of this service),
                    // not the router's provisional pick — see `snapshot` below,
                    // which is deliberately left unstamped.
                    snapshot.engine = engine
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
        // A committed switch is a fact too — stamp it.
        var snapshot = active.snapshot
        snapshot.engine = engine
        eventHub.publish(snapshot: snapshot)
    }
}
