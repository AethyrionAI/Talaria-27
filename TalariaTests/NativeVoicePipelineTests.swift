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
        let router = VoiceEngineRouter(realtime: realtime, native: native, isRelayPaired: { false })

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
        let router = VoiceEngineRouter(realtime: realtime, native: native, isRelayPaired: { true })

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
        let router = VoiceEngineRouter(realtime: realtime, native: native, isRelayPaired: { true })

        await router.startSession()
        #expect(realtime.startCalls == 1)
        #expect(native.startCalls == 1)
        #expect(router.activeEngine == .native)
    }

    @MainActor
    @Test func healthyRealtimeStartNeverTouchesNative() async {
        let realtime = StubVoiceService(engine: .realtime)
        let native = StubVoiceService(engine: .native)
        let router = VoiceEngineRouter(realtime: realtime, native: native, isRelayPaired: { true })

        await router.startSession()
        #expect(realtime.startCalls == 1)
        #expect(native.startCalls == 0)
        #expect(router.activeEngine == .realtime)
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
