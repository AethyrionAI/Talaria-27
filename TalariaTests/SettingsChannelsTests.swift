import Testing
@testable import Talaria

struct SettingsChannelsTests {
    @Test func deckOrderIsNineAndStable() {
        let all = SettingsSubsystem.allCases
        #expect(all.count == 9)
        #expect(all.first == .uplink)
        #expect(all.last == .developer)
        #expect(SettingsSubsystem.about.indexLabel == "08")
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
}
