import Testing
@testable import Talaria

struct SettingsChannelsTests {
    /// Was `deckOrderIsNineAndStable` — #395-D added the tenth case,
    /// deliberately between `.about` and `.developer` so `.about` keeps its
    /// long-standing "08" and a non-PCC device's visible numbering stays
    /// contiguous (the tile is filtered out entirely there, never blank).
    @Test func deckOrderIsTenAndStable() {
        let all = SettingsSubsystem.allCases
        #expect(all.count == 10)
        #expect(all.first == .uplink)
        #expect(all.last == .developer)
        #expect(SettingsSubsystem.about.indexLabel == "08")
        #expect(SettingsSubsystem.privateCloud.indexLabel == "09")
        #expect(SettingsSubsystem.uplink.a11yID == "settings.card.uplink")
        #expect(SettingsSubsystem.developer.a11yID == "settings.row.developer")
    }

    /// #256-G: "DIRECT" → "CONNECTED" (Owen's verbiage round) — the
    /// DIRECT/RELAY distinction retires with the relay itself (#251 P4).
    @Test func uplinkValueMirrorsRootRowLogic() {
        #expect(SettingsCardValues.uplink(state: .online, isDirect: true) == "CONNECTED")
        #expect(SettingsCardValues.uplink(state: .online, isDirect: false) == "RELAY")
        #expect(SettingsCardValues.uplink(state: .offline, isDirect: false) == "STANDBY")
        #expect(SettingsCardValues.uplink(state: .unreachable, isDirect: false) == "OFFLINE")
        #expect(SettingsCardValues.uplink(state: .notConnected, isDirect: false) == "NOT LINKED")
    }

    @Test func serverValue() {
        #expect(SettingsCardValues.server(activeProfileName: "Studio", isPaired: true) == "STUDIO")
        #expect(SettingsCardValues.server(activeProfileName: nil, isPaired: true) == "PAIRED")
        #expect(SettingsCardValues.server(activeProfileName: nil, isPaired: false) == "NO PROFILE")
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
            state: .online, isDirect: true, hostName: "OJAMD",
            modelName: "deepseek-v4-flash", brainLabel: nil)
            == "LINKED · OJAMD · DEEPSEEK-V4-FLASH")
        #expect(SettingsCardValues.statusStrip(
            state: .online, isDirect: false, hostName: "Mac Mini",
            modelName: "kimi-k2", brainLabel: nil)
            == "LINKED · RELAY · MAC MINI · KIMI-K2")
        #expect(SettingsCardValues.statusStrip(
            state: .unreachable, isDirect: false, hostName: "Mac Mini",
            modelName: nil, brainLabel: nil)
            == "OFFLINE · MAC MINI · SELECT")
        #expect(SettingsCardValues.statusStrip(
            state: .notConnected, isDirect: false, hostName: nil,
            modelName: nil, brainLabel: "On-Device")
            == "ON-DEVICE")
        #expect(SettingsCardValues.statusStrip(
            state: .notConnected, isDirect: false, hostName: nil,
            modelName: "qwen-local", brainLabel: nil)
            == "ON-DEVICE · QWEN-LOCAL")
    }

    @Test func sessionsValueHandlesUnloaded() {
        #expect(SettingsCardValues.sessions(count: nil, isPaired: false) == "…")
        #expect(SettingsCardValues.sessions(count: 12, isPaired: false) == "12 SESSIONS")
        #expect(SettingsCardValues.sessions(count: 1, isPaired: false) == "1 SESSION")
        #expect(SettingsCardValues.sessions(count: 148, isPaired: true) == "148 · SYNCED")
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
    @Test func coldLaunchNeverClaimsOnline() {
        #expect(ChatConnectionPresentation.effectiveState(.disconnected) != .online)
        #expect(ChatConnectionPresentation.effectiveState(.connecting) != .online)
    }

    /// The full mapping: measured verdicts present as themselves; anything
    /// unmeasured is `.checking` — #25's absent-not-asserted, as a link state.
    @Test func effectiveStateMapsMeasurementsOnly() {
        #expect(ChatConnectionPresentation.effectiveState(.connected) == .online)
        #expect(ChatConnectionPresentation.effectiveState(.error) == .offline)
        #expect(ChatConnectionPresentation.effectiveState(.disconnected) == .checking)
        #expect(ChatConnectionPresentation.effectiveState(.connecting) == .checking)
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
    @Test func settingsEffectiveStateIsOneMeasuredTruth() {
        // Measured online.
        #expect(ChatConnectionPresentation.settingsEffectiveState(
            direct: .connected, hostFallback: .notConnected, hostConfigured: true) == .online)
        // Measured direct failure cannot stay green via relay memory.
        #expect(ChatConnectionPresentation.settingsEffectiveState(
            direct: .error, hostFallback: .online, hostConfigured: true) == .unreachable)
        // Unprobed + configured host: checking, never online.
        #expect(ChatConnectionPresentation.settingsEffectiveState(
            direct: .disconnected, hostFallback: .online, hostConfigured: true) == .checking)
        #expect(ChatConnectionPresentation.settingsEffectiveState(
            direct: .connecting, hostFallback: .notConnected, hostConfigured: true) == .checking)
        // Hostless: the on-device story unchanged.
        #expect(ChatConnectionPresentation.settingsEffectiveState(
            direct: .disconnected, hostFallback: .notConnected, hostConfigured: false) == .notConnected)
        #expect(ChatConnectionPresentation.settingsEffectiveState(
            direct: .disconnected, hostFallback: .unreachable, hostConfigured: false) == .unreachable)
    }

    /// The card/strip values render `.checking` as explicitly unknown —
    /// no LINKED, no CONNECTED, no accent.
    @Test func checkingRendersExplicitlyUnknownInSettings() {
        #expect(SettingsCardValues.uplink(state: .checking, isDirect: false) == "CHECKING")
        let strip = SettingsCardValues.statusStrip(
            state: .checking, isDirect: false,
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
        #expect(ChatConnectionPresentation.showsConnectionBanner(isPaired: true, state: .checking) == false)
        #expect(ChatConnectionPresentation.showsConnectionBanner(isPaired: true, state: .online) == false)
        #expect(ChatConnectionPresentation.showsConnectionBanner(isPaired: true, state: .offline) == true)
        #expect(ChatConnectionPresentation.showsConnectionBanner(isPaired: true, state: .unreachable) == true)
        #expect(ChatConnectionPresentation.showsConnectionBanner(isPaired: false, state: .offline) == false)
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
