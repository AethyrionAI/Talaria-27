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
@MainActor
protocol VoiceBootstrapTransport: AnyObject {
    /// May a realtime session start? Bare JSON readiness fields, or nil if the
    /// host could not be reached at all.
    func talkReadiness() async -> Data?

    /// Mint one. Bare JSON `{voiceSession, bootstrap}`, or nil on failure.
    func talkSessionCreate() async -> Data?

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
    func talkReadiness() async -> Data? { nil }
    func talkSessionCreate() async -> Data? { nil }
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

    var errorDescription: String? {
        "Could not reach the Hermes host to start voice."
    }
}

