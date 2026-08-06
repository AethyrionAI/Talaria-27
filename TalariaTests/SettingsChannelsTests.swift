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

    @Test func uplinkValueMirrorsRootRowLogic() {
        #expect(SettingsCardValues.uplink(state: .online, isDirect: true) == "DIRECT")
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

    @Test func voiceValue() {
        #expect(SettingsCardValues.voice(readAloudOn: true, sessionLive: false, engineStateText: "STANDBY") == "READ-ALOUD ON")
        #expect(SettingsCardValues.voice(readAloudOn: false, sessionLive: false, engineStateText: "STANDBY") == "READ-ALOUD OFF")
        #expect(SettingsCardValues.voice(readAloudOn: true, sessionLive: true, engineStateText: "SESSION LIVE") == "SESSION LIVE")
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
        #expect(SettingsCardValues.statusStrip(
            state: .online, isDirect: true, hostName: "OJAMD",
            modelName: "deepseek-v4-flash", brainLabel: nil)
            == "LINKED · DIRECT · OJAMD · DEEPSEEK-V4-FLASH")
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
}
