import Foundation
import Testing
@testable import Talaria

struct SettingsChannelsTests {
    /// Was `deckOrderIsNineAndStable` — #395-D added the tenth case, and
    /// #395-D2 (Owen's positional-08 ruling, 2026-08-23) moved it BEFORE
    /// `.about` with the numbering made positional, so both device shapes
    /// stay contiguous — see the test below for the numbers themselves.
    @Test func deckOrderIsTenAndStable() {
        let all = SettingsSubsystem.allCases
        #expect(all.count == 10)
        #expect(all.first == .uplink)
        #expect(all.last == .developer)
        #expect(all[7] == .privateCloud, "PCC sits immediately before ABOUT (#395-D2)")
        #expect(all[8] == .about)
        #expect(SettingsSubsystem.uplink.a11yID == "settings.card.uplink")
        #expect(SettingsSubsystem.privateCloud.a11yID == "settings.card.privateCloud")
        #expect(SettingsSubsystem.developer.a11yID == "settings.row.developer")
    }

    /// **395-D2-B — positional card numbers, both device shapes, no gaps.**
    /// The number is computed from the tiles VISIBLE on this device: with
    /// the PCC tier, Owen's floated 08 PRIVATE CLOUD / 09 ABOUT; without it,
    /// ABOUT reverts to its classic 08 and nothing skips.
    @Test func cardNumbersArePositionalAndContiguousOnBothDeviceShapes() {
        let withPCC = SettingsSubsystem.cases(privateCloudAvailable: true)
        #expect(SettingsSubsystem.privateCloud.indexLabel(in: withPCC) == "08")
        #expect(SettingsSubsystem.about.indexLabel(in: withPCC) == "09")
        #expect(SettingsSubsystem.developer.indexLabel(in: withPCC) == "10")

        let withoutPCC = SettingsSubsystem.cases(privateCloudAvailable: false)
        #expect(SettingsSubsystem.about.indexLabel(in: withoutPCC) == "08")
        #expect(SettingsSubsystem.developer.indexLabel(in: withoutPCC) == "09")
        for (position, subsystem) in withoutPCC.enumerated() {
            #expect(subsystem.indexLabel(in: withoutPCC) == String(format: "%02d", position + 1),
                    "numbering must be contiguous with no hole where the filtered tile would have been")
        }
    }

    /// #256-G: "DIRECT" → "CONNECTED" (Owen's verbiage round) — the
    /// DIRECT/RELAY distinction retires with the relay itself (#251 P4).
    ///
    /// **#309 Lane B: it retired.** The `isDirect` argument is gone with the
    /// second transport, so the two lines that pinned "RELAY" and
    /// "LINKED · RELAY" are gone with it — they described values the functions
    /// can no longer produce, which is a pin on unreachable code.
    @Test func uplinkValueMirrorsRootRowLogic() {
        #expect(SettingsCardValues.uplink(state: .online) == "CONNECTED")
        #expect(SettingsCardValues.uplink(state: .offline) == "STANDBY")
        #expect(SettingsCardValues.uplink(state: .unreachable) == "OFFLINE")
        #expect(SettingsCardValues.uplink(state: .notConnected) == "NOT LINKED")
    }

    /// **#309 Lane B re-cut the no-name fallback from "PAIRED" to "HOST SET".**
    /// "Paired" named a ceremony that no longer happens — a profile that holds
    /// credentials is described by what it can do, not by what it once
    /// redeemed. The named-profile arm is untouched, which is the arm a real
    /// install always takes.
    @Test func serverValue() {
        #expect(SettingsCardValues.server(activeProfileName: "Studio", hasHost: true) == "STUDIO")
        #expect(SettingsCardValues.server(activeProfileName: nil, hasHost: true) == "HOST SET")
        #expect(SettingsCardValues.server(activeProfileName: nil, hasHost: false) == "NO PROFILE")
    }

    @Test func modelsValuePrefersModelThenBrain() {
        #expect(SettingsCardValues.models(activeModelName: "kimi-k3", brainLabel: nil) == "KIMI-K3")
        #expect(SettingsCardValues.models(activeModelName: nil, brainLabel: "ON-DEVICE") == "ON-DEVICE")
        #expect(SettingsCardValues.models(activeModelName: "", brainLabel: nil) == "SELECT")
        #expect(SettingsCardValues.models(activeModelName: nil, brainLabel: nil) == "SELECT")
    }

    /// #256-H: the card shows the voice ROUTE (Owen's verbiage round).
    /// Three-way voluntary/forced distinction: ON-DEVICE = brain choice,
    /// LOCAL = native engine picked, LOCAL ONLY = realtime unavailable.
    @Test func voiceValueShowsTheRoute() {
        // Brain choice wins over everything.
        #expect(SettingsCardValues.voice(brainIsLocal: true, engine: .realtime, talkState: .connected) == "ON-DEVICE")
        // Native engine picked on a linked brain — voluntary local.
        #expect(SettingsCardValues.voice(brainIsLocal: false, engine: .native, talkState: .ready) == "LOCAL")
        // Realtime states.
        #expect(SettingsCardValues.voice(brainIsLocal: false, engine: .realtime, talkState: .connected) == "REALTIME · LIVE")
        #expect(SettingsCardValues.voice(brainIsLocal: false, engine: .realtime, talkState: .ready) == "REALTIME")
        #expect(SettingsCardValues.voice(brainIsLocal: false, engine: .realtime, talkState: .connecting) == "REALTIME")
        // Probe in flight — honest ellipsis, resolves on its own.
        #expect(SettingsCardValues.voice(brainIsLocal: false, engine: .realtime, talkState: .checking) == "…")
        // Linked but realtime unavailable — the forced fallback.
        #expect(SettingsCardValues.voice(brainIsLocal: false, engine: .realtime, talkState: .idle) == "LOCAL ONLY")
        #expect(SettingsCardValues.voice(brainIsLocal: false, engine: .realtime, talkState: .blocked) == "LOCAL ONLY")
        #expect(SettingsCardValues.voice(brainIsLocal: false, engine: .realtime, talkState: .failed) == "LOCAL ONLY")
    }

    @Test func appearanceValue() {
        #expect(SettingsCardValues.appearance(themeName: "Deep Field", channelIndex: 3) == "DEEP FIELD · CH 03")
        #expect(SettingsCardValues.appearance(themeName: "Deep Field", channelIndex: nil) == "DEEP FIELD")
    }

    /// #256 (Owen's device-pass verdict): "0 STREAMS" clarified nothing —
    /// the value now says what the number counts. Off (master or none) →
    /// SENSORS OFF; live → counted, singular-aware.
    @Test func privacySensorValue() {
        #expect(SettingsCardValues.privacy(masterOn: false, health: true, location: true, motion: true) == "SENSORS OFF")
        #expect(SettingsCardValues.privacy(masterOn: true, health: false, location: false, motion: false) == "SENSORS OFF")
        #expect(SettingsCardValues.privacy(masterOn: true, health: true, location: false, motion: true) == "2 SENSORS LIVE")
        #expect(SettingsCardValues.privacy(masterOn: true, health: true, location: false, motion: false) == "1 SENSOR LIVE")
    }

    /// #256: the grid's status strip — link · host · model, hostless
    /// collapsing to the on-device story instead of "— " noise.
    @Test func statusStripComposesLinkHostModel() {
        // #256-G: direct is the norm — no transport qualifier in the strip.
        #expect(SettingsCardValues.statusStrip(
            state: .online, hostName: "OJAMD",
            modelName: "deepseek-v4-flash", brainLabel: nil)
            == "LINKED · OJAMD · DEEPSEEK-V4-FLASH")
        #expect(SettingsCardValues.statusStrip(
            state: .unreachable, hostName: "Mac Mini",
            modelName: nil, brainLabel: nil)
            == "OFFLINE · MAC MINI · SELECT")
        #expect(SettingsCardValues.statusStrip(
            state: .notConnected, hostName: nil,
            modelName: nil, brainLabel: "On-Device")
            == "ON-DEVICE")
        #expect(SettingsCardValues.statusStrip(
            state: .notConnected, hostName: nil,
            modelName: "qwen-local", brainLabel: nil)
            == "ON-DEVICE · QWEN-LOCAL")
    }

    @Test func sessionsValueHandlesUnloaded() {
        #expect(SettingsCardValues.sessions(count: nil, hasHost: false) == "…")
        #expect(SettingsCardValues.sessions(count: 12, hasHost: false) == "12 SESSIONS")
        #expect(SettingsCardValues.sessions(count: 1, hasHost: false) == "1 SESSION")
        #expect(SettingsCardValues.sessions(count: 148, hasHost: true) == "148 · SYNCED")
    }

    @Test func aboutAndDeveloper() {
        #expect(SettingsCardValues.about(isHealthy: true) == "HEALTHY")
        #expect(SettingsCardValues.about(isHealthy: false) == "DEGRADED")
        #expect(SettingsCardValues.developer(environmentLabel: "Production") == "PRODUCTION")
    }

    // #252 final-review: hostless is the DESIGNED state, not a degraded one —
    // a user with no profile/pairing configured must read HEALTHY, never
    // DEGRADED-forever. Once a host IS configured, health tracks the real
    // connection signal.
    @Test func aboutIsHealthyHostlessIsAlwaysHealthy() {
        #expect(SettingsCardValues.aboutIsHealthy(hostConfigured: false, connectionOnline: false) == true)
        #expect(SettingsCardValues.aboutIsHealthy(hostConfigured: false, connectionOnline: true) == true)
    }

    @Test func aboutIsHealthyConfiguredAndOnline() {
        #expect(SettingsCardValues.aboutIsHealthy(hostConfigured: true, connectionOnline: true) == true)
    }

    @Test func aboutIsHealthyConfiguredAndOffline() {
        #expect(SettingsCardValues.aboutIsHealthy(hostConfigured: true, connectionOnline: false) == false)
    }

    // MARK: - #252R-A — card ACCENT predicates
    //
    // These are the first tests that have ever reached `cardIsAccented`. Until
    // the extraction into `SettingsCardAccent` it was a `private func` on the
    // View, unreachable even under `@testable import` — which is exactly why
    // #256-H could move the Voice card's VALUE to the engine route, leave its
    // ACCENT reading `readAloudAutoPlay`, and have the whole suite stay green
    // for four days.

    /// **252R-A, watched RED.** The card can read `LOCAL ONLY` (no live voice
    /// anywhere) and still glow, purely because an unrelated read-aloud
    /// auto-play toggle is on — a glow describing a setting the card no longer
    /// names. That is the #180 family: a signal that does not say what it
    /// appears to say.
    ///
    /// Watched RED against the defect extracted verbatim out of the View
    /// (`voice(readAloudAutoPlay:brainIsLocal:engine:talkState:) ->
    /// readAloudAutoPlay`), which is what let the extra argument be passed:
    ///
    ///     ✘ Test voiceAccentDoesNotFollowReadAloudWhenTheRouteIsIdle()
    ///       recorded an issue … Expectation failed:
    ///       SettingsCardAccent.voice(readAloudAutoPlay: true,
    ///       brainIsLocal: false, engine: .realtime, talkState: .idle) == false
    ///       ↳ … → true
    ///
    /// The fix deletes `readAloudAutoPlay` from the signature outright, so the
    /// guarantee this pin was reaching for — the accent cannot move with the
    /// read-aloud toggle — is now carried by the type system rather than by a
    /// runtime assertion.
    @Test func voiceAccentDoesNotFollowReadAloudWhenTheRouteIsIdle() {
        #expect(SettingsCardAccent.voice(
            brainIsLocal: false, engine: .realtime, talkState: .idle) == false)
    }

    /// **252R-A, watched RED.** The mirror failure: a genuinely connected
    /// realtime session — the card reads `REALTIME · LIVE` — renders
    /// unaccented because read-aloud happens to be off.
    ///
    ///     ✘ Test voiceAccentIsTrueForAConnectedSessionWithReadAloudOff()
    ///       recorded an issue … Expectation failed:
    ///       SettingsCardAccent.voice(readAloudAutoPlay: false,
    ///       brainIsLocal: false, engine: .realtime, talkState: .connected)
    ///       == true
    ///       ↳ … → false
    @Test func voiceAccentIsTrueForAConnectedSessionWithReadAloudOff() {
        #expect(SettingsCardAccent.voice(
            brainIsLocal: false, engine: .realtime, talkState: .connected) == true)
    }

    /// **252R-A's real contract, pinned exhaustively.** A card's ACCENT must
    /// describe the same fact as its VALUE, so the two cannot disagree: over
    /// every (brain × engine × talk-state) combination the accent is true
    /// exactly when the value reads the live-session string. This is the pin
    /// that would have caught #256-H, and it will catch the next such move.
    ///
    /// Owen's ruling (2026-08-09): `ON-DEVICE` is always available, so glowing
    /// for it would make the accent meaningless on a hostless install — the
    /// default user under the launch pivot. Only a connected realtime session
    /// glows. Read-aloud is not an input here at all.
    @Test func voiceAccentAndValueCannotDisagree() {
        let talkStates: [TalkConnectionState] =
            [.idle, .checking, .ready, .connecting, .connected, .blocked, .failed]
        for brainIsLocal in [true, false] {
            for engine: VoiceEngine in [.realtime, .native] {
                for talkState in talkStates {
                    let value = SettingsCardValues.voice(
                        brainIsLocal: brainIsLocal, engine: engine, talkState: talkState)
                    let accent = SettingsCardAccent.voice(
                        brainIsLocal: brainIsLocal, engine: engine, talkState: talkState)
                    #expect(accent == (value == "REALTIME · LIVE"),
                            "accent \(accent) disagrees with value \(value) for brainIsLocal=\(brainIsLocal) engine=\(engine) talk=\(talkState)")
                }
            }
        }
    }

    // A fourth pin, `voiceAccentIsIndependentOfReadAloud`, was watched RED here
    // (7 issues, one per talk state) and then deliberately RETIRED rather than
    // made green: the fix removes `readAloudAutoPlay` from the signature
    // entirely, so "the accent does not move with the read-aloud toggle" became
    // a statement the compiler enforces and a runtime assertion could no longer
    // express. The read-aloud toggle keeps its own home on
    // `VoiceSettingsScreen`, and its real consumer is the auto-read pipeline in
    // `AppContainer` — which is untouched by 252R-A.

    /// The other eight predicates, moved verbatim out of the View — no
    /// behaviour change, but they had no coverage either. Each means the same
    /// thing: *this subsystem is in a live/active state.*
    @Test func accentPredicatesForTheOtherEightSubsystems() {
        #expect(SettingsCardAccent.uplink(state: .online) == true)
        #expect(SettingsCardAccent.uplink(state: .offline) == false)
        #expect(SettingsCardAccent.uplink(state: .unreachable) == false)
        #expect(SettingsCardAccent.uplink(state: .notConnected) == false)

        #expect(SettingsCardAccent.server(hasActiveProfile: true) == true)
        #expect(SettingsCardAccent.server(hasActiveProfile: false) == false)

        #expect(SettingsCardAccent.models(activeModelName: "kimi-k3") == true)
        #expect(SettingsCardAccent.models(activeModelName: "") == false)
        #expect(SettingsCardAccent.models(activeModelName: nil) == false)

        #expect(SettingsCardAccent.appearance == true)

        #expect(SettingsCardAccent.privacy(masterOn: true, health: true,
                                           location: false, motion: false) == true)
        #expect(SettingsCardAccent.privacy(masterOn: true, health: false,
                                           location: false, motion: false) == false)
        #expect(SettingsCardAccent.privacy(masterOn: false, health: true,
                                           location: true, motion: true) == false)

        // nil is "not loaded yet" (value renders "…"), not zero sessions.
        #expect(SettingsCardAccent.sessions(count: nil) == false)
        #expect(SettingsCardAccent.sessions(count: 0) == true)
        #expect(SettingsCardAccent.sessions(count: 12) == true)

        #expect(SettingsCardAccent.about(isHealthy: true) == true)
        #expect(SettingsCardAccent.about(isHealthy: false) == false)

        #expect(SettingsCardAccent.developer == false)
    }

    /// The accent predicates must agree with the value formatters wherever
    /// both describe the same fact — the same coupling 252R-A pins for Voice,
    /// checked on its nearest neighbour so the principle is not a one-off.
    @Test func privacyAccentAndValueCannotDisagree() {
        for masterOn in [true, false] {
            for health in [true, false] {
                for location in [true, false] {
                    for motion in [true, false] {
                        let value = SettingsCardValues.privacy(
                            masterOn: masterOn, health: health, location: location, motion: motion)
                        let accent = SettingsCardAccent.privacy(
                            masterOn: masterOn, health: health, location: location, motion: motion)
                        #expect(accent == (value != "SENSORS OFF"))
                    }
                }
            }
        }
    }

    // MARK: - #350: link state is a measurement, not an assertion

    /// The cold-launch lie, pinned as an assertion first: an UNPROBED direct
    /// status must never present as online. (Before #350, `.disconnected`
    /// and `.connecting` both mapped to `.online` "optimistically" — a green
    /// LINKED · ONLINE against a dead port, across a cold launch.)
    ///
    /// #264 half 2 moved the mapping into `ConnectionSignal` (the app's one
    /// derivation). Every expectation below is unchanged — only the type being
    /// called moved.
    @Test func coldLaunchNeverClaimsOnline() {
        #expect(ConnectionSignal.chatState(direct: .disconnected) != .online)
        #expect(ConnectionSignal.chatState(direct: .connecting) != .online)
    }

    /// The full mapping: measured verdicts present as themselves; anything
    /// unmeasured is `.checking` — #25's absent-not-asserted, as a link state.
    @Test func effectiveStateMapsMeasurementsOnly() {
        #expect(ConnectionSignal.chatState(direct: .connected) == .online)
        #expect(ConnectionSignal.chatState(direct: .error) == .offline)
        #expect(ConnectionSignal.chatState(direct: .disconnected) == .checking)
        #expect(ConnectionSignal.chatState(direct: .connecting) == .checking)
    }

    /// `.checking`'s detail names what IS known (paired) and leaves what
    /// isn't ABSENT — no ONLINE claim anywhere in it.
    @Test func checkingDetailCarriesNoOnlineClaim() {
        let detail = ChatConnectionPresentation.sessionsHostDetail(.checking)
        #expect(detail == "LINKED · —")
        #expect(detail.contains("ONLINE") == false)
    }

    /// The settings surfaces' shared truth (previously three verbatim
    /// private copies — the #256 drift shape). Measured connected wins;
    /// a measured direct ERROR outranks stale relay memory (the relay
    /// fallback could keep a dead link green); no verdict + a configured
    /// host is `.checking`; no verdict + hostless keeps the host-store
    /// story byte-identical.
    /// #264 half 2: same expectations, new home — `ConnectionSignal.state`'s
    /// `.settings` arm. The three argument labels survive verbatim; what
    /// changed is that no VIEW may supply them any more.
    @Test func settingsEffectiveStateIsOneMeasuredTruth() {
        func settings(
            direct: ConnectionStatus,
            hostFallback: HermesHostConnectionState,
            hostConfigured: Bool
        ) -> HermesHostConnectionState {
            ConnectionSignal.state(
                .init(direct: direct, hostFallback: hostFallback, hostConfigured: hostConfigured),
                for: .settings)
        }
        // Measured online.
        #expect(settings(
            direct: .connected, hostFallback: .notConnected, hostConfigured: true) == .online)
        // Measured direct failure cannot stay green via relay memory.
        #expect(settings(
            direct: .error, hostFallback: .online, hostConfigured: true) == .unreachable)
        // Unprobed + configured host: checking, never online.
        #expect(settings(
            direct: .disconnected, hostFallback: .online, hostConfigured: true) == .checking)
        #expect(settings(
            direct: .connecting, hostFallback: .notConnected, hostConfigured: true) == .checking)
        // Hostless: the on-device story unchanged.
        #expect(settings(
            direct: .disconnected, hostFallback: .notConnected, hostConfigured: false) == .notConnected)
        #expect(settings(
            direct: .disconnected, hostFallback: .unreachable, hostConfigured: false) == .unreachable)
    }

    // MARK: - #264 half 2: ONE connection signal

    /// **264-D.** The two surface mappings are arms of one function, and the
    /// divergence the 08-09 ruling warned about is PINNED rather than merely
    /// commented: chat's measured failure is `.offline`, settings' is
    /// `.unreachable`. Collapsing them would silently change chat-banner
    /// wording, so a future "simplification" that unifies them goes RED here.
    @Test func chatAndSettingsDivergeOnlyOnMeasuredFailure() {
        for direct in [ConnectionStatus.connected, .connecting, .disconnected, .error] {
            let inputs = ConnectionSignal.Inputs(
                direct: direct, hostFallback: .notConnected, hostConfigured: true)
            let chat = ConnectionSignal.state(inputs, for: .chat)
            let settings = ConnectionSignal.state(inputs, for: .settings)
            if direct == .error {
                #expect(chat == .offline)
                #expect(settings == .unreachable)
            } else {
                #expect(chat == settings)
            }
        }
    }

    /// **264-D, the chat plane's direct-only rule.** `.chat` ignores the
    /// relay-sourced fallback and the configured flag entirely — the relay is
    /// retired, and consulting it would paint a false "host offline" banner.
    /// Pinned across every combination so no future arm can quietly start
    /// reading them.
    @Test func chatSurfaceIgnoresRelayFallbackAndConfiguredFlag() {
        for direct in [ConnectionStatus.connected, .connecting, .disconnected, .error] {
            for fallback in [HermesHostConnectionState.online, .offline, .unreachable, .notConnected, .checking] {
                for configured in [true, false] {
                    #expect(
                        ConnectionSignal.state(
                            .init(direct: direct, hostFallback: fallback, hostConfigured: configured),
                            for: .chat)
                            == ConnectionSignal.chatState(direct: direct))
                }
            }
        }
    }

    /// **264-E — the drift this half was opened for.** Before the collapse,
    /// Uplink asked `!gatewayBaseURL.isEmpty` (which falls back to the LEGACY
    /// `settingsStore.settings.hermesAPIBaseURL`) while About and Channels
    /// asked `activeProfile?.hasGateway == true`. On a container with no active
    /// profile but a stale legacy URL, that is one signal rendering two states.
    ///
    /// The predicate now reads the profile only — the thing the app actually
    /// dials — so the legacy value cannot make any surface claim a host.
    /// **RED-witnessed** by restoring the old spelling: `hostConfigured` then
    /// returns true for a profile-less container and this goes red.
    @Test func hostConfiguredReadsTheProfileTheAppActuallyDials() {
        // No profile at all: nothing to dial, whatever a legacy setting says.
        #expect(ConnectionSignal.hostConfigured(activeProfile: nil) == false)
        // A profile with no gateway is the normal local-brain-first state.
        var profile = BackendProfile(name: "Local", gatewayBaseURL: "")
        #expect(ConnectionSignal.hostConfigured(activeProfile: profile) == false)
        // A profile that names a gateway is configured.
        profile.gatewayBaseURL = "http://100.110.102.59:8642"
        #expect(ConnectionSignal.hostConfigured(activeProfile: profile) == true)
    }

    /// **264-E, the surfaces' agreement stated as one assertion.** With no
    /// active profile and no direct verdict, all three settings surfaces derive
    /// from the SAME inputs, so they cannot disagree by construction — the
    /// hostless story, not a CHECKING promise against an undialable URL.
    @Test func hostlessContainerRendersOneStoryOnEverySettingsSurface() {
        let inputs = ConnectionSignal.Inputs(
            direct: .disconnected,
            hostFallback: .notConnected,
            hostConfigured: ConnectionSignal.hostConfigured(activeProfile: nil))
        #expect(ConnectionSignal.state(inputs, for: .settings) == .notConnected)
        #expect(ConnectionSignal.state(inputs, for: .settings) != .checking)
    }

    /// The card/strip values render `.checking` as explicitly unknown —
    /// no LINKED, no CONNECTED, no accent.
    @Test func checkingRendersExplicitlyUnknownInSettings() {
        #expect(SettingsCardValues.uplink(state: .checking) == "CHECKING")
        let strip = SettingsCardValues.statusStrip(
            state: .checking,
            hostName: "OJAMD", modelName: "deepseek-v4-flash", brainLabel: nil)
        #expect(strip.contains("LINKED") == false)
        #expect(strip.contains("CONNECTED") == false)
        #expect(strip.hasPrefix("CHECKING"))
        #expect(SettingsCardAccent.uplink(state: .checking) == false)
    }


    /// The banner is an ALARM and `.checking` is not an alarm: without this
    /// rule the honest cold-launch state would flash the red offline banner
    /// on every launch until the first probe lands. It fires only on a
    /// MEASURED non-online state, and never unpaired.
    @Test func connectionBannerWaitsForAMeasurement() {
        #expect(ChatConnectionPresentation.showsConnectionBanner(hasHost: true, state: .checking) == false)
        #expect(ChatConnectionPresentation.showsConnectionBanner(hasHost: true, state: .online) == false)
        #expect(ChatConnectionPresentation.showsConnectionBanner(hasHost: true, state: .offline) == true)
        #expect(ChatConnectionPresentation.showsConnectionBanner(hasHost: true, state: .unreachable) == true)
        #expect(ChatConnectionPresentation.showsConnectionBanner(hasHost: false, state: .offline) == false)
    }

    // MARK: - #395-D: the Private Cloud tile

    /// **395-D-A, absent half.** On a device without the tier the tile does
    /// not exist — filtered out like `.developer` in the list, never rendered
    /// blank. And the filter removes ONLY that tile: everything else keeps
    /// its order, so the numbering stays contiguous where PCC never existed.
    @Test func privateCloudTileIsAbsentWhenTheTierDoesNotExistOnTheDevice() {
        let visible = SettingsSubsystem.cases(privateCloudAvailable: false)
        #expect(!visible.contains(.privateCloud))
        #expect(visible == SettingsSubsystem.allCases.filter { $0 != .privateCloud },
                "the filter must remove ONLY the Private Cloud tile, preserving order")
    }

    /// **395-D-A, present half.**
    @Test func privateCloudTileIsPresentAndOrderedWhenTheTierExists() {
        #expect(SettingsSubsystem.cases(privateCloudAvailable: true) == SettingsSubsystem.allCases)
    }

    /// **395-D-C, the OFF half.** The card describes the user's own setting
    /// first: disabled reads OFF whatever the quota says. A card that showed
    /// LIMIT REACHED over a tier the user turned off would send them hunting
    /// for a quota problem they do not have — #180's family.
    @Test func privateCloudCardValueAnswersOffWheneverDisabledRegardlessOfQuota() {
        let quotas: [LocalChatBackend.PrivateCloudStatus.Quota?] = [
            nil, .unknown,
            .belowLimit(approaching: false), .belowLimit(approaching: true),
            .limitReached
        ]
        for quota in quotas {
            #expect(SettingsCardValues.privateCloud(enabled: false, quota: quota) == "OFF",
                    "disabled must read OFF for quota \(String(describing: quota)) — the user's setting outranks quota state")
        }
    }

    /// **395-D-C, the enabled half.** Quota words appear only when the tier
    /// is on — and an unknown or unloaded quota reads plain ON (the setting
    /// is a fact; the quota claim waits for a measurement, #391's rule).
    @Test func privateCloudCardValueSurfacesQuotaOnlyWhenEnabled() {
        #expect(SettingsCardValues.privateCloud(enabled: true, quota: .belowLimit(approaching: false)) == "ON")
        #expect(SettingsCardValues.privateCloud(enabled: true, quota: nil) == "ON")
        #expect(SettingsCardValues.privateCloud(enabled: true, quota: .unknown) == "ON")
        #expect(SettingsCardValues.privateCloud(enabled: true, quota: .belowLimit(approaching: true)) == "NEARING LIMIT")
        #expect(SettingsCardValues.privateCloud(enabled: true, quota: .limitReached) == "LIMIT REACHED")
    }

    /// The accent tracks the setting — the card glows when the tier is
    /// offered, not when quota happens to be healthy.
    @Test func privateCloudCardAccentTracksTheUsersSetting() {
        #expect(SettingsCardAccent.privateCloud(enabled: true))
        #expect(!SettingsCardAccent.privateCloud(enabled: false))
    }

    /// The tile's identity string follows the default card path.
    @Test func privateCloudTileIdentityIsStable() {
        #expect(SettingsSubsystem.privateCloud.a11yID == "settings.card.privateCloud")
    }

}

/// #318 — Settings SEARCH (Claude Design 1b), bars A..D. The index is pure
/// and data-driven; these pin coverage, the filing's own example queries,
/// availability honesty, and the single navigation door.
struct SettingsSearchTests {

    private let allVisible = SettingsSubsystem.cases(privateCloudAvailable: true)

    // MARK: 318-A — coverage

    /// Every subsystem is findable by its own title. A future case added
    /// without index entries goes RED here, which is the bar's point.
    @Test func everySubsystemIsFindableByItsOwnTitle() {
        for subsystem in SettingsSubsystem.allCases {
            let hits = SettingsSearchIndex.matches(query: subsystem.title, visible: allVisible)
            #expect(
                hits.contains { $0.subsystem == subsystem },
                "\(subsystem) is not findable by its own title \"\(subsystem.title)\""
            )
        }
    }

    // MARK: 318-B — the filing's own promises

    @Test func theFilingsOwnExampleQueriesLand() {
        let haptics = SettingsSearchIndex.matches(query: "haptics", visible: allVisible)
        #expect(haptics.first?.subsystem == .appearance, "\"haptics\" must land on APPEARANCE (the Tuning sheet's toggle)")
        #expect(haptics.first?.detail?.contains("Tuning") == true, "the haptics row owes the nested path")
        let verbose = SettingsSearchIndex.matches(query: "verbose", visible: allVisible)
        #expect(verbose.first?.subsystem == .developer, "\"verbose\" must land on DEVELOPER")
    }

    @Test func garbageAndEmptyQueriesMatchNothing() {
        #expect(SettingsSearchIndex.matches(query: "xyzzy-no-such-setting", visible: allVisible).isEmpty)
        #expect(SettingsSearchIndex.matches(query: "", visible: allVisible).isEmpty)
        #expect(SettingsSearchIndex.matches(query: "   ", visible: allVisible).isEmpty)
    }

    @Test func matchingIsCaseInsensitiveOverTitlesAndKeywords() {
        #expect(SettingsSearchIndex.matches(query: "HaPtIcS", visible: allVisible).first?.subsystem == .appearance)
        // "face id" is a KEYWORD on the App Lock entry, not a title.
        #expect(
            SettingsSearchIndex.matches(query: "FACE ID", visible: allVisible)
                .contains { $0.subsystem == .privacy },
            "keyword matching must reach App Lock via \"face id\""
        )
    }

    // MARK: 318-C — availability through the one list

    @Test func availabilityFiltersThroughTheSameListAsTheGrid() {
        let withoutTier = SettingsSubsystem.cases(privateCloudAvailable: false)
        #expect(
            !SettingsSearchIndex.matches(query: "private cloud", visible: withoutTier)
                .contains { $0.subsystem == .privateCloud },
            "a device without the PCC tier must not be offered a PCC result (#395-D's one-list rule)"
        )
        #expect(
            SettingsSearchIndex.matches(query: "private cloud", visible: allVisible)
                .contains { $0.subsystem == .privateCloud },
            "a device WITH the tier must find it"
        )
    }

    // MARK: 318-D — the single navigation door (structural, #399-shape)

    @Test func searchResultTapsRouteOnlyThroughOpenSubsystem() throws {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Talaria/Features/Settings/SettingsChannelsScreen.swift")
        let source = try #require(
            try? String(contentsOf: path, encoding: .utf8),
            "SettingsChannelsScreen.swift unreadable — this pin must fail loudly, not vacuously"
        )
        guard let region = source.range(of: "var searchResultsList") else {
            Issue.record("the search results view is gone — re-point this pin at its successor")
            return
        }
        let body = String(source[region.upperBound...].prefix(1400))
        #expect(
            body.contains("openSubsystem("),
            "search result taps must route through openSubsystem — the deck's one navigation door"
        )
    }
}
