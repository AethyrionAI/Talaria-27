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

/// #269-B: what the app is willing to SAY once a conversational-setup turn is
/// over. An EXTENSION of the closed vocabulary above, never a fork — every
/// link-derived case is `resolve`d from a `TalariaLinkDisplayState`, so the
/// chat card and the Server screen's PLUGIN LINK row are two renderings of
/// one measurement rather than two opinions.
///
/// The copy obeys #269-A-C, which is the whole architecture in one sentence:
/// **the agent narrates WHY, the app verifies WHETHER.** From here "never
/// installed", "on disk but not enabled" and "enabled but not restarted" are
/// the same 503 — so `notLive` says what was observed, says out loud that the
/// cause is not knowable from the phone, and hands the reader the two places
/// the answer actually lives: the agent's own message, and the host's own
/// Restart Gateway control.
///
/// ⛔ It points at that control and never offers one. Owen ruled 2026-08-25
/// that the flow ends by directing the user to the affordance Hermes already
/// ships (the statusbar Gateway popover's power button, or the Command
/// Palette entry) — no new restart mechanism is built, ever, and upstream's
/// own comment says that button was visually isolated "so it can't be hit by
/// mistake."
enum TalariaPluginSetupCompletion: String, CaseIterable, Equatable {
    /// The probe answered 401 — the adapter is registered and answering.
    case live
    /// The probe answered 503 — the platform is absent. Why is not knowable
    /// from here.
    case notLive
    /// No answer at all: the host did not respond to the probe.
    case hostUnreachable
    /// The probe produced nothing usable (an unexpected status, or no host
    /// configured). Not a verdict — an absence of one.
    case notMeasured
    /// The PHONE's own state, not the link's: the turn never dispatched, so
    /// nothing was asked of the agent and nothing was measured. Deliberately
    /// unreachable from any observation.
    case promptNotSent

    static func resolve(from state: TalariaLinkDisplayState) -> TalariaPluginSetupCompletion {
        switch state {
        case .livePaired, .liveNotPaired: .live
        case .notLive: .notLive
        case .hostUnreachable: .hostUnreachable
        case .unknown: .notMeasured
        }
    }

    var headline: String {
        switch self {
        case .live: "PLUGIN LINK LIVE"
        case .notLive: "STILL NOT LIVE"
        case .hostUnreachable: "HOST UNREACHABLE"
        case .notMeasured: "NOT MEASURED"
        case .promptNotSent: "NOTHING WAS SENT"
        }
    }

    var detail: String {
        switch self {
        case .live:
            "Talaria probed the host and the plugin answered. Setup is done."
        case .notLive:
            "Talaria probed the host and the plugin did not answer. Talaria cannot tell from here whether it is missing, switched off, or waiting on a restart — your agent's message above says what it actually ran. A plugin only loads when the gateway starts, so if it was just installed, use Restart Gateway on the host (the Gateway popover's power button, or the Command Palette entry) and open this screen again."
        case .hostUnreachable:
            "Talaria could not reach the host, so it has nothing to report about the plugin either way."
        case .notMeasured:
            "The host did not give Talaria an answer it can read, so Talaria is not claiming anything about the plugin."
        case .promptNotSent:
            "Talaria could not send the setup message, so nothing was asked of your agent and nothing on the host was touched."
        }
    }

    /// Only a live probe reads as success — the "never render 👍 off a Done!"
    /// line (#269's momentum-report sharpening), applied to our own copy.
    var isSuccess: Bool { self == .live }
}
