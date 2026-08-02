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

    // MARK: - Router seam behavior

    /// Scriptable engine stub: enough of the protocol to drive the router.
    @MainActor
    final class StubVoiceService: VoiceSessionServiceProtocol {
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

        init(engine: VoiceEngine) {
            self.engine = engine
        }

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
                voiceSessionID: nil,
                readiness: readiness,
                engine: engine
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
            connectionState = stateAfterStart
        }
        func endSession() async { connectionState = .idle }
        func toggleMute() async { isMuted.toggle() }
        func manuallyInterruptAssistantOutput() {}
        @discardableResult
        func sendImage(_ imageData: Data, mimeType: String, triggerResponse: Bool) -> Bool { false }
    }

    @MainActor
    @Test func unpairedDeviceRoutesStraightToNativeEngine() async {
        let realtime = StubVoiceService(engine: .realtime)
        let native = StubVoiceService(engine: .native)
        let router = VoiceEngineRouter(realtime: realtime, native: native, isRelayPaired: { false }, activeBrain: { .hermes })

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
        let router = VoiceEngineRouter(realtime: realtime, native: native, isRelayPaired: { true }, activeBrain: { .hermes })

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
        let router = VoiceEngineRouter(realtime: realtime, native: native, isRelayPaired: { true }, activeBrain: { .hermes })

        await router.startSession()
        #expect(realtime.startCalls == 1)
        #expect(native.startCalls == 1)
        #expect(router.activeEngine == .native)
    }

    @MainActor
    @Test func healthyRealtimeStartNeverTouchesNative() async {
        let realtime = StubVoiceService(engine: .realtime)
        let native = StubVoiceService(engine: .native)
        let router = VoiceEngineRouter(realtime: realtime, native: native, isRelayPaired: { true }, activeBrain: { .hermes })

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
            isRelayPaired: { true },          // pairing says yes …
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
            isRelayPaired: { true },
            activeBrain: { brain }
        )
        #expect(router.activeEngine == .realtime)

        brain = .onDevice                      // user switches; no refresh runs
        await router.startSession()

        #expect(realtime.startCalls == 0, "the stale realtime routing must not survive a brain change")
        #expect(native.startCalls == 1)
        #expect(router.activeEngine == .native)
    }

    // MARK: - Snapshot / hand-off tagging

    @Test func snapshotEngineDefaultsToRealtime() {
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
        #expect(snapshot.engine == .realtime)
    }
}
