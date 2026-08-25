import Foundation

/// **#383: how the realtime voice bootstrap reaches its host.**
///
/// Voice used to speak to the relay, which delegated to the connector, which
/// minted an ephemeral provider credential. Both of those tiers are retired
/// (#346 on OJAMD, #375 on the Mac), so voice was bootstrapping against
/// nothing. The talaria plugin — which runs *inside* the gateway — now serves
/// three verbs over the platform link, and this is the seam between the voice
/// service and that transport.
///
/// **Raw `Data`, not decoded models, and that is deliberate.** The plugin
/// answers with BARE JSON where the relay wrapped every response in
/// `{"data": …}`. Putting decode on the caller keeps the wire contract with
/// the type that owns it (`LiveVoiceSessionService` holds the decode targets
/// a shipped client froze) rather than splitting it across a transport that
/// would then have to know about voice.
/// What a voice verb came back with.
///
/// **`unsupported` exists because the envelope answers HTTP 200 with an error
/// BODY** — `{"error": …, "code": "unknown_event_type"}` — rather than a 4xx.
/// Without this case that response is "success" whose bytes then fail to
/// decode, and the user is shown a JSON error for what is really "this host
/// has not been updated yet". #383 hazard 5 named exactly this: two hosts, one
/// app, and the older host must degrade honestly instead of confusingly.
enum VoiceVerbOutcome {
    case ok(Data)
    /// The host answered, and does not know this verb — its talaria plugin
    /// predates #383.
    case unsupported
    /// No usable answer: unreachable, unpaired, superseded, or a real error.
    case unreachable
}

@MainActor
protocol VoiceBootstrapTransport: AnyObject {
    /// May a realtime session start?
    func talkReadiness() async -> VoiceVerbOutcome

    /// Mint one — `{voiceSession, bootstrap}` as bare JSON. `tuning` is the
    /// user's coarse sensitivity pick (#396: `quiet`/`normal`/`noisy`),
    /// resolved to vetted `turn_detection` values HOST-side; an older plugin
    /// ignores the unknown field and mints with its default.
    func talkSessionCreate(tuning: String) async -> VoiceVerbOutcome

    /// #224: the host's persistent approval mode — READ with nil, SET with
    /// `manual`/`smart`/`off`. Rides the same envelope the talk family does;
    /// an old plugin answers `unknown_event_type` → `.unsupported`, which is
    /// the picker's host-predates state. Not voice — this protocol is simply
    /// where the app's one generic envelope-verb seam lives today.
    func approvalMode(setting mode: String?) async -> VoiceVerbOutcome

    /// Release one.
    ///
    /// **This is #383's compensation path** (383-C, Owen's ruling: compensate
    /// rather than exempt). It is called on every abandonment — a dismissal
    /// mid-connect, a thrown bootstrap, a superseded link — so it must be
    /// safe to call for a session the host has never heard of. The plugin
    /// acks an unknown id for exactly that reason.
    @discardableResult
    func talkSessionEnd(voiceSessionID: String) async -> Bool
}

/// The honest no-op for a profile that cannot reach a talaria plugin.
///
/// #310's precedent: a gateway-only profile says *"no realtime voice"* rather
/// than sitting silently un-refreshed. This returns nil rather than throwing
/// so the caller's existing "host unreachable" path handles it — an absent
/// transport and an unreachable one are the same thing to the user, and
/// inventing a second failure mode would only add a message nobody can act on
/// differently.
@MainActor
final class UnavailableVoiceTransport: VoiceBootstrapTransport {
    func talkReadiness() async -> VoiceVerbOutcome { .unreachable }
    func talkSessionCreate(tuning: String) async -> VoiceVerbOutcome { .unreachable }
    func approvalMode(setting mode: String?) async -> VoiceVerbOutcome { .unreachable }
    @discardableResult
    func talkSessionEnd(voiceSessionID: String) async -> Bool { false }
}

/// The single failure the voice bootstrap can now report.
///
/// **#383 collapsed two error families into one, and that is the point.**
/// Voice used to carry the relay's 401 ladder (#15/#94) — expired token,
/// refresh, retry, then "re-pair with your relay". The platform link re-pairs
/// itself on 401 and gives up after one attempt, so an expired credential
/// never surfaces here as an auth error. What is left is the only thing a
/// user can act on: the host could not be reached.
enum VoiceTransportError: LocalizedError {
    case hostUnreachable
    /// The host is fine; its plugin is older than #383.
    case hostDoesNotSupportVoice

    var errorDescription: String? {
        switch self {
        case .hostUnreachable:
            return "Could not reach the Hermes host to start voice."
        case .hostDoesNotSupportVoice:
            // Names the fix, because the user CAN act on this one: the other
            // host, or an updated plugin. A generic "unreachable" would send
            // them looking for a network fault they do not have.
            return "This Hermes host doesn't support voice yet — update its talaria plugin, or switch to a host that has it."
        }
    }
}

