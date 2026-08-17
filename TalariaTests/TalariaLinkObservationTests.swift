import Testing
@testable import Talaria

/// #269-A: the honest-link vocabulary. Every case is a table row — the
/// classifier, the composer, and the #353(b) severity rule are pure.
struct TalariaLinkObservationTests {

    @Test func classifierMapsTheVerifiedSeam() {
        #expect(TalariaLinkObservation.classify(status: 401) == .adapterLive(status: 401))
        #expect(TalariaLinkObservation.classify(status: 503) == .adapterAbsent(status: 503))
        // An unexpected status licenses nothing (269-A-C).
        #expect(TalariaLinkObservation.classify(status: 418) == .indeterminate(status: 418))
        #expect(TalariaLinkObservation.classify(status: 200) == .indeterminate(status: 200))
    }

    @Test func composeNeverLetsTheTokenDecideAlone() {
        // 269-A-B: a token + an absent adapter is NOT LIVE, never PAIRED.
        #expect(TalariaLinkDisplayState.compose(
            observation: .adapterAbsent(status: 503), deviceToken: "tok-1") == .notLive)
        #expect(TalariaLinkDisplayState.compose(
            observation: .adapterLive(status: 401), deviceToken: "tok-1") == .livePaired)
        #expect(TalariaLinkDisplayState.compose(
            observation: .adapterLive(status: 401), deviceToken: nil) == .liveNotPaired)
        // An empty string is not a token — a cleared Keychain slot can read
        // back as one (the rule migrated from the retired TalariaLinkState).
        #expect(TalariaLinkDisplayState.compose(
            observation: .adapterLive(status: 401), deviceToken: "") == .liveNotPaired)
        #expect(TalariaLinkDisplayState.compose(
            observation: .hostUnreachable, deviceToken: "tok-1") == .hostUnreachable)
        #expect(TalariaLinkDisplayState.compose(
            observation: .indeterminate(status: 200), deviceToken: "tok-1") == .unknown)
        #expect(TalariaLinkDisplayState.compose(
            observation: .notConfigured, deviceToken: "tok-1") == .unknown)
        #expect(TalariaLinkDisplayState.compose(
            observation: nil, deviceToken: "tok-1") == .unknown)
    }

    @Test func labelsAreTheClosedVocabulary() {
        #expect(TalariaLinkDisplayState.unknown.label == "—")
        #expect(TalariaLinkDisplayState.livePaired.label == "LIVE · PAIRED")
        #expect(TalariaLinkDisplayState.liveNotPaired.label == "LIVE · NOT PAIRED")
        #expect(TalariaLinkDisplayState.notLive.label == "NOT LIVE")
        #expect(TalariaLinkDisplayState.hostUnreachable.label == "HOST UNREACHABLE")
    }

    @Test func legacyRelaySeverityDerivesFromMeasurementOnly() {
        // #353(b): red is reserved for "the phone-facing channel is down."
        #expect(TalariaLinkObservation.legacyRelayReadsAsError(pluginLive: true, relayReachable: false) == false)
        #expect(TalariaLinkObservation.legacyRelayReadsAsError(pluginLive: false, relayReachable: false) == true)
        #expect(TalariaLinkObservation.legacyRelayReadsAsError(pluginLive: true, relayReachable: true) == false)
        #expect(TalariaLinkObservation.legacyRelayReadsAsError(pluginLive: false, relayReachable: true) == false)
    }
}
