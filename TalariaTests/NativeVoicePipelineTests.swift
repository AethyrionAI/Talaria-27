import Foundation
import Testing
@testable import Talaria

/// #18 — native voice engine: the pure routing/endpointing decisions, engine
/// switching through the router seam, and the honest engine tagging on
/// snapshots. Audio capture and TTS are device concerns covered by the
/// OPEN_ITEMS device checklist.
struct NativeVoicePipelineTests {

    // MARK: - Fallback endpointer

    @Test func endpointerFiresAfterSilenceWithPendingText() {
        let lastChange = Date(timeIntervalSince1970: 1_000)
        let now = lastChange.addingTimeInterval(NativeVoicePipelineService.endpointSilence + 0.01)
        #expect(NativeVoicePipelineService.shouldEndpoint(
            pendingText: "turn off the lights",
            lastChangeAt: lastChange,
            now: now
        ))
    }

    @Test func endpointerHoldsWhileTranscriptionIsStillMoving() {
        let lastChange = Date(timeIntervalSince1970: 1_000)
        let now = lastChange.addingTimeInterval(0.4)
        #expect(!NativeVoicePipelineService.shouldEndpoint(
            pendingText: "turn off the",
            lastChangeAt: lastChange,
            now: now
        ))
    }

    @Test func endpointerNeverFiresOnEmptyOrUntimedText() {
        let now = Date(timeIntervalSince1970: 2_000)
        #expect(!NativeVoicePipelineService.shouldEndpoint(
            pendingText: "   ",
            lastChangeAt: now.addingTimeInterval(-10),
            now: now
        ))
        #expect(!NativeVoicePipelineService.shouldEndpoint(
            pendingText: "hello",
            lastChangeAt: nil,
            now: now
        ))
    }

    // MARK: - Duplicate-final dedupe

    @Test func lateFinalMatchingCommittedUtteranceIsDuplicate() {
        #expect(NativeVoicePipelineService.isDuplicateFinalization(
            committed: "What's the weather today?",
            candidate: "what's   the weather today?"
        ))
    }

    @Test func lateFinalThatIsPrefixOfCommittedIsDuplicate() {
        // The endpointer committed the longer volatile text; a shorter final
        // covering the same audio must not re-send the turn.
        #expect(NativeVoicePipelineService.isDuplicateFinalization(
            committed: "what's the weather today",
            candidate: "What's the weather"
        ))
    }

    @Test func freshUtteranceIsNotDuplicate() {
        #expect(!NativeVoicePipelineService.isDuplicateFinalization(
            committed: "what's the weather today",
            candidate: "And how about tomorrow?"
        ))
        #expect(!NativeVoicePipelineService.isDuplicateFinalization(
            committed: "",
            candidate: "anything"
        ))
    }

    // MARK: - Engine routing decisions

    @Test func readinessRoutesNativeWhenTalkUnconfigured() {
        #expect(VoiceEngineRouter.shouldRouteNative(configured: false, connectionState: .blocked))
    }

    @Test func readinessRoutesNativeWhenRelayUnreachable() {
        #expect(VoiceEngineRouter.shouldRouteNative(configured: nil, connectionState: .failed))
    }

    @Test func readinessKeepsRealtimeWhenConfigured() {
        #expect(!VoiceEngineRouter.shouldRouteNative(configured: true, connectionState: .ready))
        // Unknown configured on a healthy probe stays Realtime — no silent
        // downgrade on missing data.
        #expect(!VoiceEngineRouter.shouldRouteNative(configured: nil, connectionState: .ready))
    }

    // MARK: - #221: the brain selection governs voice, not just chat

    /// **On-device means on-device — in every modality.** Owen, 2026-08-01:
    /// *"on device should signify everything on device. Local. When hermes is
    /// selected, it switches to using hermes' resources."*
    ///
    /// Before this, `VoiceEngineRouter` keyed on relay pairing alone and had no
    /// reference to the brain at all, so a user on the on-device brain had their
    /// microphone audio streamed to OpenAI Realtime and billed for it.
    @Test func onDeviceBrainForbidsRealtimeVoice() {
        #expect(!VoiceEngineRouter.realtimeIsPermitted(for: .onDevice))
    }

    @Test func hermesBrainPermitsRealtimeVoice() {
        #expect(VoiceEngineRouter.realtimeIsPermitted(for: .hermes))
    }

    /// PCC is Apple's compute, not Hermes' — so "when hermes is selected" does
    /// not cover it. The architecture already agrees: `Brain.privateCloud` is
    /// documented as *"routed to the local backend (which owns the PCC
    /// session)"*, so voice follows chat onto the local side.
    @Test func privateCloudBrainForbidsRealtimeVoice() {
        #expect(!VoiceEngineRouter.realtimeIsPermitted(for: .privateCloud))
    }

    /// The permission is a HARD gate, not a preference: no pairing state and no
    /// healthy probe may re-admit realtime once the brain has forbidden it.
    /// Pinned because the old code's only input was pairing, and that is exactly
    /// the path that must no longer be able to win.
    @Test func everyNonHermesBrainForbidsRealtimeRegardlessOfProbe() {
        for brain in ChatBackendRouter.Brain.allCases where brain != .hermes {
            #expect(!VoiceEngineRouter.realtimeIsPermitted(for: brain),
                    "\(brain.rawValue) must not reach realtime voice")
        }
    }

    @Test func failedRealtimeStartFallsBackToNative() {
        #expect(VoiceEngineRouter.shouldFallBackToNative(
            connectionState: .failed,
            blockedReason: "Could not reach the relay."
        ))
    }

    @Test func microphoneDenialDoesNotBounceBetweenEngines() {
        #expect(!VoiceEngineRouter.shouldFallBackToNative(
            connectionState: .blocked,
            blockedReason: "Microphone access is required for talk mode."
        ))
    }

    @Test func successfulRealtimeStartStaysRealtime() {
        #expect(!VoiceEngineRouter.shouldFallBackToNative(connectionState: .connected, blockedReason: nil))
        #expect(!VoiceEngineRouter.shouldFallBackToNative(connectionState: .connecting, blockedReason: nil))
    }

    // MARK: - #247 B1: the timed-out start (bars 247-A)
    //
    // Owen's outage lockup: a black-holed relay (tailnet drop, not refuse)
    // rode the shared 300s-timeout client, so "ESTABLISHING LINK" sat for
    // minutes and the refused-path fallback never fired. A timed-out start
    // loses the right to claim "still connecting."

    @Test func timedOutStartFallsBackEvenWhileConnecting() {
        #expect(VoiceEngineRouter.shouldFallBackToNative(
            connectionState: .connecting, blockedReason: nil, timedOut: true))
        #expect(VoiceEngineRouter.shouldFallBackToNative(
            connectionState: .checking, blockedReason: nil, timedOut: true))
        #expect(VoiceEngineRouter.shouldFallBackToNative(
            connectionState: .failed, blockedReason: nil, timedOut: true))
    }

    /// A start that connected right at the deadline SUCCEEDED — late is not
    /// failed, and bouncing a live connection would be the #221 sin.
    @Test func lateButConnectedStartIsNotBounced() {
        #expect(!VoiceEngineRouter.shouldFallBackToNative(
            connectionState: .connected, blockedReason: nil, timedOut: true))
    }

    /// The microphone exemption outranks the timeout: a mic denial blocks
    /// BOTH engines, so falling back just moves the same dead end.
    @Test func microphoneDenialStillExemptsEvenWhenTimedOut() {
        #expect(!VoiceEngineRouter.shouldFallBackToNative(
            connectionState: .blocked,
            blockedReason: "Microphone access is required for talk mode.",
            timedOut: true))
    }

    // MARK: - Router seam behavior

    /// #139: a releasable suspension point, so a test can hold a
    /// `startSession()` open across the window a user dismisses in. The whole
    /// zombie lives inside that window, so no bar here is meaningful without
    /// a start that can actually be caught mid-flight.
    @MainActor
    final class StartGate {
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private var isOpen = false

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func open() {
            isOpen = true
            let pending = waiters
            waiters = []
            for waiter in pending { waiter.resume() }
        }
    }

    /// Scriptable engine stub: enough of the protocol to drive the router.
    @MainActor
    final class StubVoiceService: VoiceSessionServiceProtocol {
        /// #139: when set, `startSession()` suspends here until the test opens
        /// it. Unset (the default) keeps every pre-#139 test synchronous.
        var startGate: StartGate?
        var endCalls = 0
        var voiceState: VoiceState = .idle
        var connectionState: TalkConnectionState = .idle
        var transcriptItems: [TranscriptItem] = []
        var sessionDuration: TimeInterval = 0
        var isMuted = false
        var blockedReason: String?
        var statusMessage: String?
        var canStartSession = true
        var latencyMetrics = TalkLatencyMetrics()
        var engine: VoiceEngine
        var readiness = TalkReadinessInfo()
        var startCalls = 0
        var refreshCalls = 0
        /// Applied when startSession runs, simulating the engine's outcome.
        var stateAfterStart: TalkConnectionState = .connected
        /// Applied when refreshReadiness runs, simulating the probe outcome.
        var stateAfterRefresh: TalkConnectionState = .ready

        /// #180 lane 180-L (bar 180-C): when false the snapshot omits `engine:`
        /// entirely — which is exactly what the REALTIME service does in
        /// production. `NativeVoicePipelineService.swift:71` is the ONLY
        /// producer that has ever stamped it, so a realtime-path snapshot
        /// carries whatever the struct's default is. Models "no engine has
        /// been selected yet."
        var stampsEngine = true

        init(engine: VoiceEngine) {
            self.engine = engine
        }

        var snapshot: TalkSessionSnapshot {
            var built = unstampedSnapshot
            if stampsEngine { built.engine = engine }
            return built
        }

        private var unstampedSnapshot: TalkSessionSnapshot {
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
                voiceSessionID: nil,
                readiness: readiness
            )
        }

        private let hub = TalkSessionEventHub()
        func events() -> AsyncStream<TalkSessionEvent> { hub.stream(initial: snapshot) }
        func refreshReadiness() async {
            refreshCalls += 1
            connectionState = stateAfterRefresh
        }
        func startSession() async {
            startCalls += 1
            if let startGate { await startGate.wait() }
            connectionState = stateAfterStart
        }
        func endSession() async {
            endCalls += 1
            connectionState = .idle
        }
        func toggleMute() async { isMuted.toggle() }
        func manuallyInterruptAssistantOutput() {}
        @discardableResult
        func sendImage(_ imageData: Data, mimeType: String, triggerResponse: Bool) -> Bool { false }
    }

    // MARK: - #180 lane 180-L / L2: the overlay must not name an unselected engine
    //
    // Bars 180-C (RED on the defect) and 180-D (the green-today regression
    // PIN). The form being removed is `HostFedListPresentation`'s rule 5
    // "optimistic default": a stored property whose declared default is the
    // affirmative value, corrected only if some producer bothers to stamp it.
    //
    // This settles the residual #139 explicitly left unasserted — and settles
    // it WITHOUT the tethered device sitting that entry said it needed,
    // because the defect turns out to be a default in a struct rather than a
    // runtime routing question. That is the finding: #139 filed this as
    // needing a quoted log line; it needed a unit test.

    /// **180-C, first RED — the label.** With no engine selected, the header
    /// must name none. Before L2 the derivation read `voiceEngine == .native`,
    /// `voiceEngine` defaulted to `.realtime`, and `.idle` fell through to
    /// **"VOICE LINK · CONNECTING"** — an engine name produced by a struct
    /// default, in a state where nothing had chosen an engine at all.
    @Test func overlayHeaderNamesNoEngineBeforeOneIsSelected() {
        let label = VoiceOverlayScreen.sessionHeaderLabel(
            engine: nil, connectionState: .idle, duration: 0)

        #expect(!label.contains("VOICE LINK"),
                "no engine has been selected — the header must not claim the Realtime link")
        #expect(!label.contains("LOCAL VOICE"),
                "…and it must not claim the on-device pipeline either")
    }

    /// The same neutrality across every pre-connect state the router can sit
    /// in, including the up-to-12s realtime start budget that ends in a
    /// fallback to native (`VoiceEngineRouter.realtimeStartTimeout`).
    @Test func overlayHeaderStaysNeutralAcrossEveryPreSelectionState() {
        for state in [TalkConnectionState.idle, .checking, .ready, .connecting, .blocked, .failed] {
            let label = VoiceOverlayScreen.sessionHeaderLabel(
                engine: nil, connectionState: state, duration: 0)
            #expect(!label.contains("VOICE LINK"), "\(state.rawValue) named the Realtime link")
            #expect(!label.contains("LOCAL VOICE"), "\(state.rawValue) named the on-device pipeline")
        }
    }

    /// **180-C, second RED — the mechanism itself.** A snapshot built with no
    /// `engine:` argument must not report `.realtime`. This is the optimistic
    /// default caught directly at `VoiceState.swift`, one layer below the
    /// label: no re-wording of the HUD copy can satisfy it.
    @Test func anUnstampedSnapshotDoesNotClaimTheRealtimeEngine() {
        let snapshot = TalkSessionSnapshot(
            voiceState: .idle,
            connectionState: .idle,
            transcriptItems: [],
            sessionDuration: 0,
            isMuted: false,
            blockedReason: nil,
            statusMessage: nil,
            canStartSession: true,
            latencyMetrics: TalkLatencyMetrics(),
            voiceSessionID: nil
        )

        #expect(snapshot.engine != .realtime,
                "an unstamped snapshot must not silently claim the historical engine")
    }

    /// **180-C, third RED — end to end through the store.** The realtime
    /// service never stamps its snapshots, so a `TalkStore` built on one
    /// starts with no engine known, and the header derived from it must stay
    /// neutral.
    @MainActor
    @Test func aStoreFedByAnUnstampingServiceKnowsOfNoEngine() {
        let service = StubVoiceService(engine: .realtime)
        service.stampsEngine = false     // exactly what LiveVoiceSessionService does
        let store = TalkStore(voiceService: service)

        #expect(store.voiceEngine != .realtime,
                "the store must not adopt an engine nobody published")

        let label = VoiceOverlayScreen.sessionHeaderLabel(
            engine: store.voiceEngine,
            connectionState: store.connectionState,
            duration: store.sessionDuration)
        #expect(!label.contains("VOICE LINK"))
        #expect(!label.contains("LOCAL VOICE"))
    }

    /// **180-D — the regression PIN. GREEN TODAY BY CONSTRUCTION**, recorded
    /// as a pin rather than implied to be a proof. #18's rule is that local
    /// voice is never silently substituted for the Realtime experience, so an
    /// unknown state must not erase the distinction it exists to draw.
    @Test func aSelectedEngineIsStillNamed() {
        #expect(VoiceOverlayScreen.sessionHeaderLabel(
            engine: .native, connectionState: .idle, duration: 0) == "LOCAL VOICE · STARTING")
        #expect(VoiceOverlayScreen.sessionHeaderLabel(
            engine: .realtime, connectionState: .connecting, duration: 0) == "VOICE LINK · CONNECTING")
        #expect(VoiceOverlayScreen.sessionHeaderLabel(
            engine: .native, connectionState: .connected, duration: 65) == "LOCAL VOICE · 01:05")
        #expect(VoiceOverlayScreen.sessionHeaderLabel(
            engine: .realtime, connectionState: .connected, duration: 65) == "VOICE SESSION · 01:05")
        #expect(VoiceOverlayScreen.sessionHeaderLabel(
            engine: .realtime, connectionState: .failed, duration: 0) == "VOICE LINK · FAILED")
        #expect(VoiceOverlayScreen.sessionHeaderLabel(
            engine: .native, connectionState: .blocked, duration: 0) == "LOCAL VOICE · UNAVAILABLE")
    }

    /// **180-D, second half — a stamped snapshot still reaches the store**, so
    /// the `LOCAL VOICE · ON-DEVICE PIPELINE` badge (`VoiceOverlayScreen`
    /// `:138`) keeps its input. Green today; pinned so the unknown state
    /// cannot swallow a real selection.
    @MainActor
    @Test func aStampedSnapshotStillNamesItsEngineInTheStore() async {
        let service = StubVoiceService(engine: .native)
        let store = TalkStore(voiceService: service)

        #expect(store.voiceEngine == .native)
    }

    @MainActor
    @Test func unpairedDeviceRoutesStraightToNativeEngine() async {
        let realtime = StubVoiceService(engine: .realtime)
        let native = StubVoiceService(engine: .native)
        let router = VoiceEngineRouter(realtime: realtime, native: native, isVoiceHostPaired: { false }, activeBrain: { .hermes })

        #expect(router.activeEngine == .native)
        await router.startSession()
        #expect(native.startCalls == 1)
        #expect(realtime.startCalls == 0)
        #expect(router.snapshot.engine == .native)
    }

    @MainActor
    @Test func unconfiguredReadinessSwitchesToNative() async {
        let realtime = StubVoiceService(engine: .realtime)
        realtime.stateAfterRefresh = .blocked
        realtime.readiness = TalkReadinessInfo(hostOnline: true, configured: false, ready: false)
        let native = StubVoiceService(engine: .native)
        let router = VoiceEngineRouter(realtime: realtime, native: native, isVoiceHostPaired: { true }, activeBrain: { .hermes })

        #expect(router.activeEngine == .realtime)
        await router.refreshReadiness()
        #expect(router.activeEngine == .native)
        #expect(native.refreshCalls == 1)
    }

    @MainActor
    @Test func failedRealtimeStartFallsBackToNativeSession() async {
        let realtime = StubVoiceService(engine: .realtime)
        realtime.stateAfterStart = .failed
        realtime.blockedReason = "Could not reach the relay."
        let native = StubVoiceService(engine: .native)
        let router = VoiceEngineRouter(realtime: realtime, native: native, isVoiceHostPaired: { true }, activeBrain: { .hermes })

        await router.startSession()
        #expect(realtime.startCalls == 1)
        #expect(native.startCalls == 1)
        #expect(router.activeEngine == .native)
    }

    @MainActor
    @Test func healthyRealtimeStartNeverTouchesNative() async {
        let realtime = StubVoiceService(engine: .realtime)
        let native = StubVoiceService(engine: .native)
        let router = VoiceEngineRouter(realtime: realtime, native: native, isVoiceHostPaired: { true }, activeBrain: { .hermes })

        await router.startSession()
        #expect(realtime.startCalls == 1)
        #expect(native.startCalls == 0)
        #expect(router.activeEngine == .realtime)
    }

    /// **#221 regression guard — this is the bug Owen found, reproduced.**
    ///
    /// Same setup as `healthyRealtimeStartNeverTouchesNative` above (paired,
    /// realtime healthy) with ONE difference: the brain is on-device. Before the
    /// fix this reached realtime and billed OpenAI for microphone audio while the
    /// app displayed on-device.
    @MainActor
    @Test func onDeviceBrainNeverReachesRealtimeEvenWhenPairedAndHealthy() async {
        let realtime = StubVoiceService(engine: .realtime)
        let native = StubVoiceService(engine: .native)
        let router = VoiceEngineRouter(
            realtime: realtime, native: native,
            isVoiceHostPaired: { true },          // pairing says yes …
            activeBrain: { .onDevice }        // … and the brain still wins
        )

        #expect(router.activeEngine == .native, "init must not default to realtime on a forbidden brain")
        await router.refreshReadiness()
        #expect(router.activeEngine == .native, "a healthy probe must not re-admit realtime")
        await router.startSession()

        #expect(realtime.startCalls == 0, "realtime must never be started on the on-device brain")
        #expect(native.startCalls == 1)
        #expect(router.activeEngine == .native)
        // The probe itself must not run either — reaching OpenAI at all is the
        // thing being prevented, not just speaking to it.
        #expect(realtime.refreshCalls == 0, "a forbidden brain must not even probe realtime")
    }

    /// The gate is re-checked at `startSession`, not trusted from a stale
    /// `activeEngine` — the original defect was a routing decision nobody
    /// re-evaluated after the user changed their mind.
    @MainActor
    @Test func switchingToOnDeviceMidSessionForcesNativeOnTheNextStart() async {
        let realtime = StubVoiceService(engine: .realtime)
        let native = StubVoiceService(engine: .native)
        var brain = ChatBackendRouter.Brain.hermes
        let router = VoiceEngineRouter(
            realtime: realtime, native: native,
            isVoiceHostPaired: { true },
            activeBrain: { brain }
        )
        #expect(router.activeEngine == .realtime)

        brain = .onDevice                      // user switches; no refresh runs
        await router.startSession()

        #expect(realtime.startCalls == 0, "the stale realtime routing must not survive a brain change")
        #expect(native.startCalls == 1)
        #expect(router.activeEngine == .native)
    }

    // MARK: - #139: a dismissed session must never reach a live mic

    /// Bounded pump — polls a MainActor condition instead of guessing at a
    /// sleep. Returns whether the condition ever held.
    @MainActor
    private func waitUntil(
        _ description: String,
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<400 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("timed out waiting for: \(description)")
        return false
    }

    /// **139-C — the bar that covers the zombie #247 created.**
    ///
    /// `VoiceEngineRouter.startSession()` falls back to the native engine
    /// after the realtime start resolves, and nothing in that path asks
    /// whether the session is still wanted. So a user who dismisses during
    /// ESTABLISHING LINK gets a LOCAL microphone opened seconds later, by the
    /// very belt that was added to bound the hang.
    ///
    /// Every realtime resolution reaches the fallback branch: `.failed` and
    /// `.idle` both land in `shouldFallBackToNative`'s `default: return true`,
    /// and `.idle` is precisely what the user's own `endSession()` leaves
    /// behind.
    @MainActor
    @Test(arguments: [TalkConnectionState.failed, .idle])
    func abandonedRealtimeStartNeverOpensTheLocalMic(outcome: TalkConnectionState) async {
        let realtime = StubVoiceService(engine: .realtime)
        let gate = StartGate()
        realtime.startGate = gate
        realtime.stateAfterStart = outcome
        let native = StubVoiceService(engine: .native)
        let router = VoiceEngineRouter(
            realtime: realtime, native: native,
            isVoiceHostPaired: { true }, activeBrain: { .hermes }
        )
        // Keep the belt out of this arm — the timeout has its own test below.
        router.realtimeStartTimeout = .seconds(600)

        let start = Task { await router.startSession() }
        let inFlight = await waitUntil("the realtime start to be in flight") { realtime.startCalls == 1 }
        #expect(inFlight)

        // The user gives up and dismisses, mid-connect.
        await router.endSession()
        // …and only now does the slow relay finally answer.
        gate.open()
        await start.value

        #expect(native.startCalls == 0,
                "an abandoned session must not fall back into a live local mic (outcome: \(outcome))")
    }

    /// **139-C, timeout arm.** Same invariant on the belt path: the 12s
    /// cancellation is what makes `timedOut` true, and `shouldFallBackToNative`
    /// treats a timed-out start as fallback-worthy by design (#247 B1). That is
    /// correct for a session the user still wants and wrong for one they left.
    @MainActor
    @Test func abandonedRealtimeStartNeverFallsBackAfterTheBeltFires() async {
        let realtime = StubVoiceService(engine: .realtime)
        let gate = StartGate()
        realtime.startGate = gate
        // MUST be set, and the first draft of this test did not set it: the
        // default is `.connected`, and `shouldFallBackToNative` exempts a
        // late-but-connected start by design (`lateButConnectedStartIsNotBounced`).
        // So the test passed on the pre-fix code — a green that proved nothing,
        // because it never reached the fallback branch it claimed to guard.
        realtime.stateAfterStart = .failed
        let native = StubVoiceService(engine: .native)
        let router = VoiceEngineRouter(
            realtime: realtime, native: native,
            isVoiceHostPaired: { true }, activeBrain: { .hermes }
        )
        router.realtimeStartTimeout = .milliseconds(50)

        let start = Task { await router.startSession() }
        let inFlight = await waitUntil("the realtime start to be in flight") { realtime.startCalls == 1 }
        #expect(inFlight)

        await router.endSession()
        // Let the belt reach its deadline and cancel the start, then release
        // the stub: the continuation is not cancellation-aware, so the gate
        // must open or `start.value` would never return.
        try? await Task.sleep(for: .milliseconds(150))
        gate.open()
        await start.value

        #expect(native.startCalls == 0,
                "a timed-out start on an abandoned session must not open the local mic either")
        // **#397-C — the abandonment path is deliberately NOT swept into
        // #397's fix.** Exactly ONE end, the explicit `router.endSession()`
        // above; the fallback branch must not add a second here.
        //
        // Why this branch is left alone: `startGeneration` is bumped by a NEW
        // start as well as by a dismissal, so an unconditional
        // `realtime.endSession()` on the abandonment path could tear down a
        // session the NEXT start owns. The fallback branch has no such hazard
        // (`generation == startGeneration` is checked immediately before it).
        // Fixing it properly needs a generation-scoped end, which is a design
        // question rather than a line — filed at #397, not smuggled in here.
        #expect(realtime.endCalls == 1,
                "the abandonment path grew a second endSession — #397 was swept in where it does not belong")
    }

    /// **#397-A — a timed-out realtime start must END the realtime session
    /// before the local mic opens.**
    ///
    /// `start.cancel()` cancels a Swift Task; it does not tear down a peer
    /// connection. So a start that times out at 12 s but whose WebRTC
    /// connection completes a moment later leaves `LiveVoiceSessionService`
    /// holding a LIVE session — and the fallback then starts the native engine
    /// beside it. Two engines, two voices, each hearing the other.
    ///
    /// **Severity is privacy, not audio:** a surviving realtime session is a
    /// live microphone streaming to OpenAI for a session the app believes it
    /// is not in — #139's shape, and #139 exists because that happened.
    ///
    /// Found 2026-08-22 while chasing #138, and explicitly NOT its cause (the
    /// device log shows no fallback in the affected session). Filed and fixed
    /// on its own merits rather than allowed to wear another item's evidence.
    @MainActor
    @Test func aTimedOutRealtimeStartEndsThatSessionBeforeOpeningTheLocalMic() async {
        let realtime = StubVoiceService(engine: .realtime)
        let gate = StartGate()
        realtime.startGate = gate
        // Reach the fallback branch. The default is `.connected`, which
        // `shouldFallBackToNative` exempts by design — the sibling test above
        // records that trap costing a green that proved nothing.
        realtime.stateAfterStart = .failed
        let native = StubVoiceService(engine: .native)
        let router = VoiceEngineRouter(
            realtime: realtime, native: native,
            isVoiceHostPaired: { true }, activeBrain: { .hermes }
        )
        router.realtimeStartTimeout = .milliseconds(50)

        let start = Task { await router.startSession() }
        let inFlight = await waitUntil("the realtime start to be in flight") { realtime.startCalls == 1 }
        #expect(inFlight)
        try? await Task.sleep(for: .milliseconds(150))
        gate.open()
        await start.value

        #expect(realtime.endCalls == 1,
                "the abandoned realtime session was left running beside the native engine")
        // **#397-B — #247's belt survives.** A build that stops falling back
        // has traded a rare double-session for a dead voice feature, which is
        // strictly worse. The fallback must still happen, and for the same
        // reason it always did.
        #expect(native.startCalls == 1, "the fallback to local voice stopped happening")
    }

    /// **139-A — the core bar.** A start that resolves AFTER the user
    /// dismissed must be discarded: no live state, and no Live Activity.
    ///
    /// On the Live Activity assertion: `TalkStore` starts it at
    /// `startSessionDirectly()`'s tail, guarded by `isSessionActive` in the
    /// same four lines — so pinning that flag false is what proves the call did
    /// not happen. `LiveActivityService` is a concrete `private let` with no
    /// counter, and widening it purely for this assertion would be a
    /// production change made for a test.
    @MainActor
    @Test func startResolvingAfterDismissalIsDiscarded() async {
        let stub = StubVoiceService(engine: .realtime)
        let gate = StartGate()
        stub.startGate = gate
        let store = TalkStore(voiceService: stub)

        let start = Task { await store.startSessionDirectly() }
        let inFlight = await waitUntil("the start to be in flight") { stub.startCalls == 1 }
        #expect(inFlight)

        await store.abandonSession()
        gate.open()
        await start.value

        #expect(store.isSessionActive == false,
                "an abandoned session must never flip live — this also gates the Live Activity")
        #expect(store.connectionState != .connected)
        #expect(stub.endCalls == 2,
                "one end from the dismissal, one from the stale-return belt")
    }

    /// **139-B — abandon must not guard on `isSessionActive`.**
    ///
    /// The prefix window: the engine has not published `.connecting` yet
    /// (it is still inside the microphone-permission await), so
    /// `isSessionActive` is false and every teardown that guards on it —
    /// `onDisappear`, `endSessionIfNeeded`, the background rule — sees nothing
    /// to do. The stub models this exactly by publishing no snapshot until its
    /// start completes.
    @MainActor
    @Test func abandonTearsDownAStartThatHasNotReportedConnectingYet() async {
        let stub = StubVoiceService(engine: .realtime)
        let gate = StartGate()
        stub.startGate = gate
        let store = TalkStore(voiceService: stub)

        let start = Task { await store.startSessionDirectly() }
        let inFlight = await waitUntil("the start to be in flight") { stub.startCalls == 1 }
        #expect(inFlight)
        #expect(store.isSessionActive == false,
                "precondition: the prefix window is exactly where isSessionActive is false")

        await store.abandonSession()

        #expect(stub.endCalls >= 1, "abandon must tear down regardless of isSessionActive")

        gate.open()
        await start.value
        #expect(store.isSessionActive == false)
    }

    /// **139-D — the engine-level guard.**
    ///
    /// AMENDED from the pre-registered bar, and this is a falsification of that
    /// text rather than a redefinition of it. The bar asked for "never reaches
    /// `.connected`" driven through `startSession()`, and
    /// `LiveVoiceSessionService.startSession()` cannot be run in a headless test
    /// host: it awaits `ensureMicrophonePermission()` (a system prompt on an
    /// undetermined permission), then `configureAudioSession()`, then builds a
    /// real `RTCPeerConnection`. The suite's existing convention for this class
    /// (see `AppStoresTests.liveVoiceSessionServiceIgnoresLateRealtimeErrors…`)
    /// is to drive it by poking state, never by running a start.
    ///
    /// What IS pinned here is the mechanism the guard rides on: an intentional
    /// end invalidates the generation an in-flight start captured. Placement of
    /// the call site is covered by 139-F on device.
    @MainActor
    @Test func intentionalEndInvalidatesAnInFlightRealtimeStart() async {
        let service = LiveVoiceSessionService()
        let captured = service.startGeneration

        await service.endSession()

        #expect(service.startGeneration != captured,
                "endSession must revoke a start that is still in flight")
    }

    /// **139-E (ii) — control.** Abandon revokes only the start it superseded.
    /// A fresh start afterwards goes fully live — the fix must not leave the
    /// store permanently poisoned.
    @MainActor
    @Test func aRestartAfterAbandonStillGoesLive() async {
        let stub = StubVoiceService(engine: .realtime)
        let gate = StartGate()
        stub.startGate = gate
        let store = TalkStore(voiceService: stub)

        let first = Task { await store.startSessionDirectly() }
        let inFlight = await waitUntil("the first start to be in flight") { stub.startCalls == 1 }
        #expect(inFlight)
        await store.abandonSession()
        gate.open()
        await first.value
        #expect(store.isSessionActive == false)

        // A new session, ungated this time.
        stub.startGate = nil
        await store.startSessionDirectly()

        #expect(store.isSessionActive, "the newest start must win")
        #expect(store.connectionState == .connected)
    }

    /// **139-E (i) — control.** The no-regression half: a healthy start with
    /// nobody dismissing still goes fully live. This one passes before the fix
    /// and must keep passing after it.
    @MainActor
    @Test func healthyStartStillGoesFullyLive() async {
        let stub = StubVoiceService(engine: .realtime)
        let store = TalkStore(voiceService: stub)

        await store.startSessionDirectly()

        #expect(store.isSessionActive, "an unabandoned start must still go live")
        #expect(store.connectionState == .connected)
        #expect(stub.startCalls == 1)
        #expect(stub.endCalls == 0, "a healthy start must not be torn down")
    }

    /// **139-E (i) — control, router half.** The four #247 routing tests above
    /// cover the engine choice; this pins that an ungated, unabandoned start
    /// still reaches the realtime engine and never touches native.
    @MainActor
    @Test func healthyRealtimeStartIsUnaffectedByTheAbandonGuard() async {
        let realtime = StubVoiceService(engine: .realtime)
        let native = StubVoiceService(engine: .native)
        let router = VoiceEngineRouter(
            realtime: realtime, native: native,
            isVoiceHostPaired: { true }, activeBrain: { .hermes }
        )

        await router.startSession()

        #expect(realtime.startCalls == 1)
        #expect(native.startCalls == 0)
        #expect(router.activeEngine == .realtime)
    }

    // MARK: - Snapshot / hand-off tagging

    /// **INVERTED IN PLACE 2026-08-09 (#180 lane 180-L, bar 180-C).**
    ///
    /// This test used to read `snapshotEngineDefaultsToRealtime` and assert
    /// `snapshot.engine == .realtime`. **It was a pin on the defect** — it
    /// certified the optimistic default that made every unstamped snapshot
    /// claim the Realtime engine, which is what put "VOICE LINK · CONNECTING"
    /// on the overlay in states where nothing had selected an engine. Kept
    /// here, inverted, rather than deleted: the assertion that changed sign is
    /// the clearest record of what the lane actually changed.
    ///
    /// The live assertion lives at
    /// `anUnstampedSnapshotDoesNotClaimTheRealtimeEngine`; this one pins the
    /// stronger property — the default is *absent*, not merely different.
    @Test func snapshotEngineIsUnknownUntilAProducerStampsIt() {
        let snapshot = TalkSessionSnapshot(
            voiceState: .idle,
            connectionState: .idle,
            transcriptItems: [],
            sessionDuration: 0,
            isMuted: false,
            blockedReason: nil,
            statusMessage: nil,
            canStartSession: true,
            latencyMetrics: TalkLatencyMetrics(),
            voiceSessionID: nil
        )
        #expect(snapshot.engine == nil)
    }
}
