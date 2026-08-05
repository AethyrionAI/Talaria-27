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

    @Test func privacyStreamCount() {
        #expect(SettingsCardValues.privacy(masterOn: false, health: true, location: true, motion: true) == "0 STREAMS")
        #expect(SettingsCardValues.privacy(masterOn: true, health: true, location: false, motion: true) == "2 STREAMS")
        #expect(SettingsCardValues.privacy(masterOn: true, health: true, location: false, motion: false) == "1 STREAM")
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
}
