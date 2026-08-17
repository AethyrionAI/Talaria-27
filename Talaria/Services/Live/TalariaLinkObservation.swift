import Foundation

/// #269-A: what one probe of the talaria events route actually observed.
/// The seam (verified live 2026-08-09, re-proven on OJAMD during #271):
/// an UNAUTHENTICATED POST answers 401 when the adapter is registered
/// (auth rejection precedes verb dispatch — nothing drains) and 503 when
/// the platform is absent. "Never installed", "on disk but not enabled",
/// and "enabled but not restarted" are all 503 — indistinguishable here
/// by design, which is why no case names a cause (the agent narrates WHY,
/// the app verifies WHETHER).
enum TalariaLinkObservation: Equatable {
    case adapterLive(status: Int)
    case adapterAbsent(status: Int)
    case indeterminate(status: Int)
    case hostUnreachable
    case notConfigured

    static func classify(status: Int) -> TalariaLinkObservation {
        switch status {
        case 401: .adapterLive(status: status)
        case 503: .adapterAbsent(status: status)
        default: .indeterminate(status: status)
        }
    }

    /// #353(b): the legacy relay rows read as an ERROR only when the relay
    /// is unreachable AND the plugin channel is not measured live — red is
    /// reserved for "the phone-facing channel is down," never for a tier
    /// whose replacement is answering.
    static func legacyRelayReadsAsError(pluginLive: Bool, relayReachable: Bool) -> Bool {
        !relayReachable && !pluginLive
    }
}

/// The display vocabulary — closed on purpose (269-A-C): every string maps
/// to an observation; none names a cause the app cannot distinguish.
enum TalariaLinkDisplayState: Equatable {
    case unknown
    case livePaired
    case liveNotPaired
    case notLive
    case hostUnreachable

    var label: String {
        switch self {
        case .unknown: "—"
        case .livePaired: "LIVE · PAIRED"
        case .liveNotPaired: "LIVE · NOT PAIRED"
        case .notLive: "NOT LIVE"
        case .hostUnreachable: "HOST UNREACHABLE"
        }
    }

    /// Two facts, composed, never conflated: the credential is only ever
    /// the SECOND word, and only when the observation earned the first.
    /// Takes the raw token so the emptiness rule lives HERE, once — an
    /// empty string is not a token (a cleared Keychain slot can read back
    /// as one; the rule migrated from the retired `TalariaLinkState`).
    static func compose(
        observation: TalariaLinkObservation?,
        deviceToken: String?
    ) -> TalariaLinkDisplayState {
        let hasDeviceToken = deviceToken?.isEmpty == false
        switch observation {
        case .adapterLive: return hasDeviceToken ? .livePaired : .liveNotPaired
        case .adapterAbsent: return .notLive
        case .hostUnreachable: return .hostUnreachable
        case .indeterminate, .notConfigured, nil: return .unknown
        }
    }
}
