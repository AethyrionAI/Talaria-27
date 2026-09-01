import Foundation
import Testing
@testable import Talaria

/// #269-B — THE CONVERSATIONAL INSTALLER, APP HALF.
///
/// The shape #251 routed and #269 carries: *"consent surfaces in chat where
/// the user lives; the app probes to verify."* The agent narrates WHY, the
/// app verifies WHETHER, and the app never upgrades the agent's narration
/// into a verdict — from the app's side "never installed", "on disk but not
/// enabled" and "enabled but not restarted" are indistinguishable (all 503,
/// #269-A's measured seam).
///
/// Four of tonight's five bars are held here; the fifth is the gate.
///
///  - **269-B-F (consent before send, wired).** The setup prompt cannot reach
///    the transport without the consent affordance's explicit confirm, and
///    the consent copy is Owen's ruled Candidate B VERBATIM (2026-09-01), so
///    a wording change is a deliberate act rather than a drift.
///  - **269-B-G (the verdict comes only from the probe).** No string in the
///    agent's reply can flip the surface to LIVE. The verdict function is
///    HANDED the reply on purpose — the pin's whole job is to prove it is
///    not read, which a signature that never accepts it could not do.
///  - **269-B-H (honest not-live copy + the restart pointer).** The
///    completion vocabulary EXTENDS #269-A-C's closed set rather than
///    forking it, names only what was observed, and points at the host's own
///    Restart Gateway affordance — never an in-app restart (Owen's 2026-08-25
///    ruling, standing).
///  - **269-B-I (the first-contact prompt is a pinned constant).** Asserted
///    on the actual string, parameterized on install source.
///
/// B-A/B/D/E and the N ≥ 10 half of B-C need a LIVE HOST and a 🔐
/// per-experiment go; nothing here stands in for them.
@MainActor
struct PluginSetupConsentTests {

    // MARK: - Helpers

    /// A store whose three seams are recording stubs. The transport default in
    /// production is the honest dead end (a store nobody wired can never fake
    /// a send); here it records so the bars can count.
    private final class Seams {
        var sentPrompts: [String] = []
        var dispatchResult = true
        var observation: TalariaLinkObservation?
        var deviceToken: String?
        var agentReply = ""
        var probeCount = 0
    }

    private func makeStore(_ seams: Seams) -> PluginSetupStore {
        let store = PluginSetupStore()
        store.sendPrompt = { prompt in
            seams.sentPrompts.append(prompt)
            return seams.dispatchResult
        }
        store.lastAgentReply = { seams.agentReply }
        store.probe = {
            seams.probeCount += 1
            return (seams.observation, seams.deviceToken)
        }
        return store
    }

    // MARK: - 269-B-F: consent before send

    /// The ruled copy, verbatim. Owen elected Candidate B ("verification
    /// forward") on 2026-09-01 by AskUserQuestion; it is pinned copy, and this
    /// is the pin.
    @Test func theConsentCopyIsOwensRuledCandidateBVerbatim() {
        #expect(PluginSetupStore.Consent.title == "Set up the plugin over chat?")
        #expect(PluginSetupStore.Consent.body == "Talaria sends your agent the install instructions; you approve the steps on the host. Talaria then verifies the install with its own probe — it won't take the agent's word for it.")
        #expect(PluginSetupStore.Consent.confirmLabel == "Send")
        #expect(PluginSetupStore.Consent.declineLabel == "Not Now")
    }

    /// The ask carries no restart guidance — the 2026-08-25 ruling moved that
    /// to the COMPLETION state deliberately, and a lane that "helpfully" adds
    /// it back to the ask has re-litigated a ruling.
    @Test func theAskCarriesNoRestartGuidance() {
        let ask = PluginSetupStore.Consent.title + " " + PluginSetupStore.Consent.body
        #expect(!ask.lowercased().contains("restart"))
    }

    /// **269-B-F, the load-bearing arm.** Raising the ask sends nothing. A
    /// mutation that dispatches from `requestConsent` goes RED here.
    @Test func raisingTheAskDoesNotReachTheTransport() {
        let seams = Seams()
        let store = makeStore(seams)
        store.requestConsent()
        #expect(store.phase == .awaitingConsent(.default))
        #expect(seams.sentPrompts.isEmpty, "the prompt reached the transport with no confirm")
        #expect(seams.probeCount == 0)
    }

    /// **269-B-F, the gate.** `confirm()` is the ONLY door: called from any
    /// phase but `.awaitingConsent` it dispatches nothing. A mutation that
    /// drops the phase guard goes RED here.
    @Test func confirmIsTheOnlyDoorAndOnlyFromTheAsk() async {
        let seams = Seams()
        let store = makeStore(seams)

        await store.confirm()                       // from .idle
        #expect(seams.sentPrompts.isEmpty, "confirm dispatched without an ask having been raised")

        store.requestConsent()
        store.decline()
        #expect(store.phase == .idle)
        await store.confirm()                       // from .idle after a decline
        #expect(seams.sentPrompts.isEmpty, "a declined ask still dispatched")

        store.requestConsent()
        await store.confirm()
        #expect(seams.sentPrompts.count == 1)
        await store.confirm()                       // the ask is spent
        #expect(seams.sentPrompts.count == 1, "confirm dispatched twice from one ask")
    }

    /// The confirm sends the pinned prompt for the source the ask carried —
    /// not some other string, and not the default when a source was named.
    @Test func confirmSendsThePinnedPromptForTheAsksOwnSource() async {
        let seams = Seams()
        let store = makeStore(seams)
        let source = TalariaPluginInstallSource(
            repositoryURL: "https://example.invalid/some/plugin.git",
            ref: "0123456789abcdef"
        )
        store.requestConsent(source: source)
        await store.confirm()
        #expect(seams.sentPrompts == [TalariaPluginSetupPrompt.firstContact(source: source)])
        #expect(seams.sentPrompts.first?.contains("https://example.invalid/some/plugin.git") == true)
    }

    /// A decline is a decline: no send, no probe, and the surface goes quiet
    /// rather than settling on a verdict it never measured.
    @Test func decliningSendsNothingAndClaimsNothing() {
        let seams = Seams()
        let store = makeStore(seams)
        store.requestConsent()
        store.decline()
        #expect(seams.sentPrompts.isEmpty)
        #expect(seams.probeCount == 0)
        #expect(store.phase == .idle)
    }

    // MARK: - 269-B-G: the verdict comes only from the probe

    /// **269-B-G.** The agent's most confident success prose against a host
    /// whose adapter is absent still renders NOT LIVE. Wiring the verdict to
    /// reply text turns this RED.
    @Test func noProseCanFlipTheSurfaceToLive() {
        for boast in [
            "Done! The talaria plugin is installed, enabled and live.",
            "✅ Installation complete — the plugin is now running.",
            "I have restarted the gateway; everything is LIVE · PAIRED.",
            "SUCCESS: talaria installed. Plugin Link should read LIVE now.",
        ] {
            #expect(
                PluginSetupStore.verdict(
                    agentReply: boast,
                    observation: .adapterAbsent(status: 503),
                    deviceToken: "a-real-device-token"
                ) == .notLive,
                "the agent's prose moved the verdict: \(boast)"
            )
        }
    }

    /// And the inverse, which the same mutation also breaks: an agent that
    /// says it failed does not suppress a probe that says the adapter is
    /// answering. The probe is the verdict in BOTH directions.
    @Test func noProseCanSuppressALiveProbe() {
        for lament in [
            "I could not install it — the clone failed with exit code 128.",
            "Sorry, this host has no write access to ~/.hermes/plugins/.",
            "CANNOT RUN",
        ] {
            #expect(
                PluginSetupStore.verdict(
                    agentReply: lament,
                    observation: .adapterLive(status: 401),
                    deviceToken: "a-real-device-token"
                ) == .live,
                "the agent's prose suppressed a live probe: \(lament)"
            )
        }
    }

    /// The verdict is a pure function of the SAME two facts #269-A composes —
    /// the observation and the held credential — so the two surfaces can
    /// never disagree about what was seen.
    @Test func theVerdictTracksTheProbeAcrossEveryObservation() {
        let cases: [(TalariaLinkObservation?, TalariaPluginSetupCompletion)] = [
            (.adapterLive(status: 401), .live),
            (.adapterAbsent(status: 503), .notLive),
            (.hostUnreachable, .hostUnreachable),
            (.indeterminate(status: 418), .notMeasured),
            (.notConfigured, .notMeasured),
            (nil, .notMeasured),
        ]
        for (observation, expected) in cases {
            #expect(
                PluginSetupStore.verdict(agentReply: "", observation: observation, deviceToken: "t") == expected,
                "observation \(String(describing: observation)) did not resolve to \(expected)"
            )
        }
        // LIVE · NOT PAIRED is still live — the credential is the second word
        // of #269-A's composed row, never the first, and the install question
        // is answered by the first.
        #expect(
            PluginSetupStore.verdict(agentReply: "", observation: .adapterLive(status: 401), deviceToken: nil) == .live
        )
    }

    /// The full flow, end to end offline: confirm dispatches, the probe runs
    /// afterwards, and the settled phase carries the probe's verdict.
    @Test func theSettledPhaseCarriesTheProbesVerdict() async {
        let seams = Seams()
        seams.observation = .adapterAbsent(status: 503)
        seams.agentReply = "All done, the plugin is live!"
        let store = makeStore(seams)
        store.requestConsent()
        await store.confirm()
        #expect(seams.probeCount == 1, "the setup turn completed without a re-probe")
        #expect(store.phase == .settled(.notLive))

        seams.observation = .adapterLive(status: 401)
        seams.deviceToken = "tok"
        store.requestConsent()
        await store.confirm()
        #expect(store.phase == .settled(.live))
    }

    /// A prompt that never left the phone is not a measurement. The store
    /// says so instead of probing a host it never asked anything of.
    @Test func anUndispatchedPromptIsNotAVerdict() async {
        let seams = Seams()
        seams.dispatchResult = false
        seams.observation = .adapterLive(status: 401)
        let store = makeStore(seams)
        store.requestConsent()
        await store.confirm()
        #expect(seams.probeCount == 0, "the app probed after a send that never happened")
        #expect(store.phase == .settled(.promptNotSent))
    }

    // MARK: - 269-B-H: honest completion copy + the restart pointer

    /// The completion vocabulary EXTENDS #269-A-C's closed set: every display
    /// state maps onto exactly one completion, and the one completion that
    /// has no display state (`promptNotSent`) is about the PHONE, not the
    /// link — it cannot be produced by any observation.
    @Test func theCompletionVocabularyExtendsTheClosedSet() {
        #expect(TalariaPluginSetupCompletion.resolve(from: .livePaired) == .live)
        #expect(TalariaPluginSetupCompletion.resolve(from: .liveNotPaired) == .live)
        #expect(TalariaPluginSetupCompletion.resolve(from: .notLive) == .notLive)
        #expect(TalariaPluginSetupCompletion.resolve(from: .hostUnreachable) == .hostUnreachable)
        #expect(TalariaPluginSetupCompletion.resolve(from: .unknown) == .notMeasured)

        let fromObservations = [
            TalariaLinkDisplayState.livePaired, .liveNotPaired, .notLive, .hostUnreachable, .unknown,
        ].map(TalariaPluginSetupCompletion.resolve(from:))
        #expect(!fromObservations.contains(.promptNotSent),
                "a link observation produced the phone-side state")
    }

    /// **269-B-H, the restart pointer.** Exactly the not-live state points at
    /// the host's own affordance, by its shipped name, and no completion ever
    /// offers an in-app restart.
    @Test func exactlyTheNotLiveStatePointsAtTheHostsRestartAffordance() {
        #expect(TalariaPluginSetupCompletion.notLive.detail.contains("Restart Gateway"))
        for other in [
            TalariaPluginSetupCompletion.live,
            .hostUnreachable,
            .notMeasured,
            .promptNotSent,
        ] {
            #expect(!other.detail.contains("Restart Gateway"),
                    "\(other) points at the restart affordance it has no observation for")
        }

        // The ruling is "never an in-app restart, ever" — so no completion may
        // offer one, and none may claim the app or the agent did one.
        for completion in TalariaPluginSetupCompletion.allCases {
            let copy = (completion.headline + " " + completion.detail).lowercased()
            for forbidden in [
                "restart the gateway for you",
                "talaria will restart",
                "restarting the gateway",
                "tap to restart",
            ] {
                #expect(!copy.contains(forbidden), "\(completion) offers an in-app restart: \(forbidden)")
            }
        }
    }

    /// **269-B-H, the honesty arm.** The not-live copy names what was
    /// observed and says out loud that the cause is not knowable from here —
    /// it never asserts one of the three indistinguishable states.
    @Test func theNotLiveCopyNamesTheObservationAndNotACause() {
        let detail = TalariaPluginSetupCompletion.notLive.detail
        #expect(detail.contains("did not answer"))
        #expect(detail.contains("cannot tell from here"))

        for completion in TalariaPluginSetupCompletion.allCases {
            let copy = (completion.headline + " " + completion.detail).lowercased()
            for causeClaim in [
                "the install failed",
                "was not installed",
                "is not installed",
                "the agent did not install",
                "the plugin is disabled",
                "needs to be enabled",
            ] {
                #expect(!copy.contains(causeClaim),
                        "\(completion) asserts a cause the app cannot distinguish: \(causeClaim)")
            }
        }
    }

    /// No completion is empty, and none of them dresses a non-live state as
    /// success — the "never render 👍 off a Done!" line, applied to our own
    /// copy rather than the agent's.
    @Test func everyCompletionSaysSomethingAndOnlyLiveReadsAsSuccess() {
        for completion in TalariaPluginSetupCompletion.allCases {
            #expect(!completion.headline.isEmpty)
            #expect(!completion.detail.isEmpty)
        }
        #expect(TalariaPluginSetupCompletion.live.isSuccess)
        for other in TalariaPluginSetupCompletion.allCases where other != .live {
            #expect(!other.isSuccess, "\(other) reads as success")
        }
    }

    // MARK: - 269-B-I: the first-contact prompt is a pinned constant

    /// The default install source is the plugin repo's REAL origin, read once
    /// from the deployed checkout at the 269-B publication moment.
    @Test func theDefaultInstallSourceIsTheRealOrigin() {
        #expect(TalariaPluginInstallSource.default.repositoryURL == "https://github.com/AethyrionAI/talaria-plugin.git")
        #expect(TalariaPluginInstallSource.default.ref == "main")
    }

    /// **269-B-I.** Every constraint the ruling put on the prose, asserted on
    /// the actual string the app would send.
    @Test func theFirstContactPromptCarriesEveryRuledConstraint() {
        let source = TalariaPluginInstallSource(repositoryURL: "https://host.invalid/r.git", ref: "deadbeef")
        let prompt = TalariaPluginSetupPrompt.firstContact(source: source)

        // Parameterized on the install source, in the command it names.
        #expect(prompt.contains("hermes plugins install https://host.invalid/r.git --ref deadbeef"))
        #expect(prompt.contains("hermes plugins enable talaria"))

        // Narrate before acting.
        #expect(prompt.contains("before you do it"))

        // Never restart the gateway itself (Owen, 2026-08-25, standing).
        #expect(prompt.contains("Do not restart the gateway"))
        #expect(prompt.contains("Restart Gateway"))

        // Report failure honestly rather than retry silently (#180).
        #expect(prompt.contains("Do not retry silently"))
        #expect(prompt.contains("do not report a success you did not observe"))

        // The app verifies with its own probe rather than trusting prose.
        #expect(prompt.contains("Talaria probes this host itself"))
        #expect(prompt.contains("will not take your word for it"))

        // Outward identity is TALARIA; "hermes" survives only as the host's
        // own command name (Owen's standing naming ruling).
        #expect(prompt.contains("Talaria"))
        #expect(!prompt.contains("Hermes app"))
    }

    /// The prompt is a pure function of its source — same source, same bytes,
    /// no clock, no host state, nothing that would make a pinned string drift
    /// between two sends.
    @Test func thePromptIsAPureFunctionOfItsSource() {
        let a = TalariaPluginSetupPrompt.firstContact(source: .default)
        let b = TalariaPluginSetupPrompt.firstContact(source: .default)
        #expect(a == b)
        #expect(a != TalariaPluginSetupPrompt.firstContact(
            source: TalariaPluginInstallSource(repositoryURL: "https://other.invalid/x.git", ref: "main")
        ))
    }

    // MARK: - The entry affordance

    /// The Server screen offers the flow exactly where #269-A's probe says the
    /// link is NOT LIVE — "the next step instead of a command" (dispatch §2).
    /// LIVE hosts are not nagged, and an unknown/unreachable state does not
    /// invent an offer out of an absence of measurement.
    @Test func theEntryAffordanceAppearsOnlyOnAMeasuredNotLive() {
        #expect(PluginSetupStore.offersSetup(for: .notLive))
        for quiet in [
            TalariaLinkDisplayState.livePaired,
            .liveNotPaired,
            .hostUnreachable,
            .unknown,
        ] {
            #expect(!PluginSetupStore.offersSetup(for: quiet), "\(quiet) offered the setup flow")
        }
    }

    /// The entry copy states the observation and offers a next step; it does
    /// not teach a command, which is the whole point of the slice.
    @Test func theEntryCopyOffersAStepNotACommand() {
        let copy = (PluginSetupStore.EntryAffordance.actionLabel + " " + PluginSetupStore.EntryAffordance.caption)
        #expect(PluginSetupStore.EntryAffordance.actionLabel == "SET UP OVER CHAT")
        #expect(copy.contains("didn't answer"))
        #expect(!copy.contains("hermes plugins"))
        #expect(!copy.lowercased().contains("terminal"))
    }
}
