import Foundation
import Testing
@testable import Talaria

/// **#383 — voice bootstraps over the talaria plugin, not the relay.**
///
/// The relay and the connector behind it are retired (#346/#375), so voice was
/// bootstrapping against nothing. These pin the app half of the re-home.
///
/// **What is NOT covered here, stated rather than implied:** the session-create
/// and compensating-end paths run through WebRTC preparation and an audio
/// session, neither of which exists in a unit test. They are gated by 383-F,
/// which requires end-to-end voice on the Mac before OJAMD sees the plugin —
/// i.e. the coverage those paths get is a device run, deliberately, not a
/// mock that would prove the mock works.
@MainActor
struct VoiceBootstrapTransportTests {

    /// Records which verbs were asked for, so a test can prove a call happened
    /// rather than merely that a state changed.
    private final class StubTransport: VoiceBootstrapTransport {
        var readinessPayload: Data?
        var createPayload: Data?
        private(set) var calls: [String] = []
        private(set) var endedSessionIDs: [String] = []

        init(readiness: Data? = nil, create: Data? = nil) {
            self.readinessPayload = readiness
            self.createPayload = create
        }

        /// nil payload models an unreachable host; `unsupported` is set
        /// explicitly by the test that wants a host with an older plugin.
        var unsupported = false

        func talkReadiness() async -> VoiceVerbOutcome {
            calls.append("talk_readiness")
            if unsupported { return .unsupported }
            return readinessPayload.map { .ok($0) } ?? .unreachable
        }

        func talkSessionCreate() async -> VoiceVerbOutcome {
            calls.append("talk_session_create")
            if unsupported { return .unsupported }
            return createPayload.map { .ok($0) } ?? .unreachable
        }

        @discardableResult
        func talkSessionEnd(voiceSessionID: String) async -> Bool {
            calls.append("talk_session_end")
            endedSessionIDs.append(voiceSessionID)
            return true
        }
    }

    /// **BARE JSON — the contract change this lane turns on.**
    ///
    /// The relay wrapped every response in `{"data": …}` and `RelayAPIClient`
    /// unwrapped it. The plugin answers bare, like its five existing verbs. A
    /// payload shaped the old way would decode to nothing, so this is the
    /// difference that would break voice silently if it were assumed.
    private static let pluginReadiness = Data("""
    {"ready":true,"hostOnline":true,"configured":true,"blockedReason":null,
     "selectedModel":"gpt-realtime-1.5","voice":"ballad",
     "voiceContextUpdatedAt":"2026-08-22T04:12:00.000000Z"}
    """.utf8)

    @Test func readinessDecodesThePluginsBareJSONRatherThanTheRelaysEnvelope() async {
        let transport = StubTransport(readiness: Self.pluginReadiness)
        let service = LiveVoiceSessionService()
        service.voiceTransportProvider = { transport }

        await service.refreshReadiness()

        #expect(transport.calls == ["talk_readiness"])
        #expect(service.canStartSession)
        #expect(service.connectionState == .ready)
        #expect(service.blockedReason == nil)
        #expect(service.readinessInfo.selectedModel == "gpt-realtime-1.5")
        #expect(service.readinessInfo.voice == "ballad")
    }

    /// The relay's envelope must NOT still decode — if it did, this suite
    /// could not tell the two contracts apart and would pass against either.
    @Test func aRelayShapedEnvelopeNoLongerDecodes() async {
        let wrapped = Data("""
        {"data":{"ready":true,"hostOnline":true,"configured":true,"blockedReason":null}}
        """.utf8)
        let service = LiveVoiceSessionService()
        service.voiceTransportProvider = { StubTransport(readiness: wrapped) }

        await service.refreshReadiness()

        #expect(service.canStartSession == false)
        #expect(service.connectionState == .failed)
    }

    /// #180: an unreachable host degrades honestly, and every readiness detail
    /// becomes unknowable rather than stale-but-confident.
    @Test func anUnreachableHostBlocksWithAnActionableMessageAndForgetsTheDetails() async {
        let service = LiveVoiceSessionService()
        service.voiceTransportProvider = { StubTransport(readiness: nil) }

        await service.refreshReadiness()

        #expect(service.canStartSession == false)
        #expect(service.connectionState == .failed)
        #expect(service.statusMessage == "Could not reach the Hermes host to start voice.")
        // The relay's ladder is gone with the relay — no "re-pair with your
        // relay" message survives to confuse a user who has no relay.
        #expect(service.statusMessage?.contains("relay") != true)
        #expect(service.readinessInfo.selectedModel == nil)
        #expect(service.readinessInfo.ready == nil)
    }

    /// A profile with no talaria plugin reachable — #310's honest state.
    @Test func theUnavailableTransportIsTheHonestGatewayOnlyState() async {
        let service = LiveVoiceSessionService()
        service.voiceTransportProvider = { UnavailableVoiceTransport() }

        await service.refreshReadiness()

        #expect(service.canStartSession == false)
        #expect(service.connectionState == .failed)
    }

    /// The provider resolves PER CALL (#310's rule), so a link that is rebound
    /// — a profile switch, a Server-settings edit — is picked up with no
    /// rewiring. A captured instance would have frozen the first answer.
    @Test func theTransportIsResolvedPerCallSoARebindIsPickedUp() async {
        let unreachable = StubTransport(readiness: nil)
        let healthy = StubTransport(readiness: Self.pluginReadiness)
        var current: any VoiceBootstrapTransport = unreachable

        let service = LiveVoiceSessionService()
        service.voiceTransportProvider = { current }

        await service.refreshReadiness()
        #expect(service.connectionState == .failed)

        current = healthy
        await service.refreshReadiness()
        #expect(service.connectionState == .ready, "a rebound link was not picked up")
        #expect(healthy.calls == ["talk_readiness"])
    }

    /// A readiness probe must not interrupt a live session — pre-existing
    /// behaviour, pinned because the transport swap rewrote this method's
    /// first lines and a guard is easy to lose in a rewrite.
    @Test func readinessDoesNotProbeWhileASessionIsConnected() async {
        let transport = StubTransport(readiness: Self.pluginReadiness)
        let service = LiveVoiceSessionService()
        service.voiceTransportProvider = { transport }
        service.connectionState = .connected

        await service.refreshReadiness()

        #expect(transport.calls.isEmpty, "a connected session was disturbed by a readiness probe")
        #expect(service.connectionState == .connected)
    }

    /// **#383 hazard 5, and the state Owen is in tonight.** The plugin half is
    /// deployed on the Mac only, so OJAMD answers `unknown_event_type` — over
    /// HTTP **200**, with the error in the BODY. Treated as success those bytes
    /// fail to decode and the user is shown a JSON error for what is really
    /// "this host has not been updated".
    @Test func aHostWhosePluginPredatesVoiceSaysSoInsteadOfLookingUnreachable() async {
        let transport = StubTransport()
        transport.unsupported = true
        let service = LiveVoiceSessionService()
        service.voiceTransportProvider = { transport }

        await service.refreshReadiness()

        #expect(service.canStartSession == false)
        #expect(service.connectionState == .failed)
        #expect(service.statusMessage?.contains("doesn't support voice yet") == true,
                "got: \(service.statusMessage ?? "nil")")
        // The distinction is the point: this must NOT read as a network fault.
        #expect(service.statusMessage?.contains("Could not reach") != true)
    }

    /// **The plugin's date shapes, against the app's real decoder.**
    ///
    /// Python's `datetime.isoformat()` emits `+00:00`, not the `Z` the relay
    /// used — and it emits fractional seconds only when the value has them, so
    /// ONE create response carries both shapes: `startedAt` with microseconds,
    /// `expiresAt` without. Every one of these must decode or the whole
    /// bootstrap fails as a decoding error, which is indistinguishable from an
    /// unreachable host to the user.
    @Test func everyDateShapeThePluginEmitsDecodes() throws {
        struct Box: Decodable { let d: Date }
        let decoder = RelayCoders.makeDecoder()
        let shapes = [
            "2026-08-22T07:11:27.389434+00:00",  // startedAt — micro + offset
            "2026-08-22T07:21:27+00:00",         // expiresAt — no fraction
            "2026-08-22T07:21:27.636600Z",       // the relay's old shape
        ]
        for shape in shapes {
            let json = Data("{\"d\":\"\(shape)\"}".utf8)
            #expect(throws: Never.self, "did not decode: \(shape)") {
                try decoder.decode(Box.self, from: json)
            }
        }
    }
}

