import Foundation

/// #224: the HOST's persistent approval mode, as its own wire-shaped state.
///
/// ⛔ Deliberately NOT `ApprovalMode` (ApprovalModeCore.swift) — that enum is
/// the app's own on-device confirm gate ("mirrored for OUR OWN gate and
/// NOTHING else"), its selectable set is pinned to `[.manual]` by Phase-0
/// bars, and it is ruled a GLOBAL UserSettings key where the host mode is
/// PER-HOST. This type carries raw wire strings instead: upstream's table is
/// the table (224-V-C), and the app validates nothing it would then have to
/// keep in sync.
enum HostApprovalModeState: Equatable, Sendable {
    /// No answer yet — the DEFAULT branch (#180 rule 5), rendered "—",
    /// never an optimistic guess.
    case unknown
    /// The host answered `unknown_event_type` — its plugin predates the
    /// approval-mode verb.
    case unsupported
    /// The host's reported mode — a raw wire string (`manual`/`smart`/`off`
    /// today; whatever upstream grows tomorrow).
    case mode(String)

    /// The verb's reply — `{ok, mode, changed, message}` mapped from
    /// upstream's `ApprovalModeResult` by the plugin.
    struct Envelope: Decodable, Equatable {
        let ok: Bool
        let mode: String
        let changed: Bool?
        let message: String?
    }

    /// The three modes the picker offers, in display order. Selection is an
    /// OFFER, not validation — an invalid mode would pass through to
    /// upstream's own rejection, whose message surfaces via `message`.
    static let selectableModes = ["manual", "smart", "off"]

    /// Maps a verb outcome to state plus any host message worth surfacing.
    ///
    /// An `ok: false` reply (managed config, upstream refusing) still
    /// carries the host's REPORTED mode — the picker lands there, never on
    /// the mode the user tapped: state comes from the response, never
    /// optimism (224-APP-E).
    static func from(_ outcome: VoiceVerbOutcome) -> (state: HostApprovalModeState, message: String?) {
        switch outcome {
        case .unsupported:
            return (.unsupported, nil)
        case .unreachable:
            return (.unknown, nil)
        case .ok(let data):
            guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
                return (.unknown, nil)
            }
            return (.mode(envelope.mode), envelope.ok ? nil : envelope.message)
        }
    }
}
