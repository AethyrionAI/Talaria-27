import Foundation
import os

/// #269-B — THE CONVERSATIONAL INSTALLER, app half.
///
/// The store behind the in-chat consent card: it holds the ask, owns the one
/// door the setup prompt can reach the transport through, and settles on a
/// verdict that comes from #269-A's probe and from nothing else.
///
/// **A cousin of `ToolConfirmationCenter` (#29) and `HostApprovalStore`
/// (#304), and deliberately neither.** #29 suspends a Swift continuation for
/// a tool running on THIS phone; #304 answers a host-side approval against a
/// live run id with a server deadline. This one is a plain user consent for a
/// message the app wants to send in the user's name — no continuation to
/// resume, no run to answer, and no deadline. What it shares with both is the
/// vocabulary: a card at the tail of the transcript, an explicit confirm, and
/// a decline that is a real answer rather than a dismissal.
///
/// Three rules, each pinned by a bar:
///  - **Nothing reaches the transport without `confirm()`** (269-B-F). The
///    prompt is built inside `confirm()` from the source the ask carried, so
///    there is no assembled string lying around for another path to send.
///  - **The verdict is the probe's** (269-B-G). `verdict` is handed the
///    agent's reply and does not read it; that is the whole point of the
///    signature.
///  - **The completion copy never names a cause** (269-B-H). #269-A measured
///    that "never installed", "on disk but not enabled" and "enabled but not
///    restarted" are one observation from here, so the app says what it saw
///    and points at the host's own Restart Gateway affordance — never an
///    in-app restart (Owen, 2026-08-25, standing).
@MainActor
@Observable
final class PluginSetupStore {
    private static let logger = Logger(subsystem: "org.aethyrion.talaria", category: "PluginSetup")

    // MARK: - Pinned copy

    /// **Owen's ruled consent wording — Candidate B ("verification-forward"),
    /// 2026-09-01, verbatim.** Pinned copy: `PluginSetupConsentTests` holds
    /// every string, so changing one is a deliberate act rather than a drift.
    /// Restart guidance is deliberately ABSENT here — the 08-25 ruling moved
    /// it to the completion state.
    enum Consent {
        static let title = "Set up the plugin over chat?"
        static let body = "Talaria sends your agent the install instructions; you approve the steps on the host. Talaria then verifies the install with its own probe — it won't take the agent's word for it."
        static let confirmLabel = "Send"
        static let declineLabel = "Not Now"
    }

    /// The Server screen's entry into the flow — "the next step instead of a
    /// command" (the dispatch brief's §2). It states the observation and
    /// offers a step; it does not teach a command, which is the whole point
    /// of the slice (#269's founding correction: *"I didn't even know it had
    /// a terminal cli until I had update issues."*).
    enum EntryAffordance {
        static let actionLabel = "SET UP OVER CHAT"
        static let caption = "The plugin didn't answer on this host. Talaria can ask your agent to install it, in chat."
    }

    // MARK: - Phase

    enum Phase: Equatable {
        /// Nothing is being asked and nothing is being reported.
        case idle
        /// The card is up, carrying the source the confirm will send for.
        case awaitingConsent(TalariaPluginInstallSource)
        /// The turn is in flight. `confirm()` returns only when it settles,
        /// because the app's own send path awaits the whole turn.
        case sending
        /// The turn is over and the probe is running.
        case verifying
        /// What the PROBE said.
        case settled(TalariaPluginSetupCompletion)
    }

    private(set) var phase: Phase = .idle

    // MARK: - Seams
    //
    // Injected so the store never holds a client, and so every default is an
    // honest dead end: a store nobody wired cannot fake a send, cannot invent
    // a reply, and cannot manufacture an observation.

    /// Dispatches the prompt as an ordinary chat turn on the runs plane and
    /// returns when the TURN settles. `false` means the turn never dispatched
    /// — which is not a measurement of anything on the host.
    var sendPrompt: @MainActor (String) async -> Bool = { _ in false }

    /// The agent's own account of what it did. Rendered beside the verdict;
    /// never consulted for the verdict (269-B-G).
    var lastAgentReply: @MainActor () -> String = { "" }

    /// #269-A's probe, composed with the profile's held device token exactly
    /// as the Server screen composes it — one measurement, two surfaces.
    var probe: @MainActor () async -> (TalariaLinkObservation?, String?) = { (nil, nil) }

    // MARK: - The ask

    /// Raise the consent card. **Sends nothing** — it has no reference to
    /// `sendPrompt` at all, which is 269-B-F's whole content. The bar's
    /// recorded mutation is next door, on `confirm()`'s phase guard: that is
    /// where a bypass can actually be written, because this method has no
    /// await to hide one in.
    func requestConsent(source: TalariaPluginInstallSource = .default) {
        phase = .awaitingConsent(source)
    }

    /// A decline is an answer: the card goes away, nothing is sent, and the
    /// app does not settle on a verdict it never measured.
    func decline() {
        guard case .awaitingConsent = phase else { return }
        Self.logger.notice("plugin setup declined at the consent card — nothing sent")
        phase = .idle
    }

    /// Clear a settled result once the user has read it.
    func dismissResult() {
        if case .settled = phase { phase = .idle }
    }

    /// **The only door.** Guarded on `.awaitingConsent` so no other phase —
    /// idle, a spent ask, a settled result, a turn already in flight — can
    /// put the prompt on the wire.
    func confirm() async {
        guard case .awaitingConsent(let source) = phase else { return }
        phase = .sending
        let dispatched = await sendPrompt(TalariaPluginSetupPrompt.firstContact(source: source))
        guard dispatched else {
            // Nothing was asked of the agent, so nothing about the host
            // changed and there is nothing to probe. Probing here would
            // dress an unrelated prior state as this flow's result.
            Self.logger.notice("plugin setup prompt never dispatched — not probing")
            phase = .settled(.promptNotSent)
            return
        }
        phase = .verifying
        let (observation, deviceToken) = await probe()
        let completion = Self.verdict(
            agentReply: lastAgentReply(),
            observation: observation,
            deviceToken: deviceToken
        )
        Self.logger.notice("plugin setup verdict from probe: \(completion.rawValue, privacy: .public)")
        phase = .settled(completion)
    }

    // MARK: - The verdict

    /// **269-B-G.** The install verdict, from the probe and the held
    /// credential — the same two facts `TalariaLinkDisplayState.compose`
    /// reads, so the chat card and the Server screen's PLUGIN LINK row can
    /// never disagree about what was seen.
    ///
    /// `agentReply` is accepted **and deliberately not read.** A signature
    /// that never took it could not be mutated into reading it, and a pin
    /// that cannot go RED under the mutation it names is not a pin. The
    /// architecture #269 fixed in writing: *the agent narrates WHY, the app
    /// verifies WHETHER, and the app never upgrades the agent's narration
    /// into a verdict.*
    static func verdict(
        agentReply: String,
        observation: TalariaLinkObservation?,
        deviceToken: String?
    ) -> TalariaPluginSetupCompletion {
        TalariaPluginSetupCompletion.resolve(
            from: TalariaLinkDisplayState.compose(observation: observation, deviceToken: deviceToken)
        )
    }

    /// Where the entry affordance appears: on a MEASURED not-live, and
    /// nowhere else. A live host is not nagged, and an unknown or unreachable
    /// host has produced no observation to offer a next step from — offering
    /// one there would be the app guessing, which is the habit #269-A took
    /// away from this row.
    static func offersSetup(for state: TalariaLinkDisplayState) -> Bool {
        state == .notLive
    }
}
