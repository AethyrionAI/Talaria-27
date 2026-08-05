import SwiftUI

// MARK: - #252 Subsystem Channels — model layer
//
// Deck order and card telemetry for the settings grid/deck. Pure — no store
// access here so the formatters are unit-testable; SettingsChannelsScreen
// feeds them live values.
enum SettingsSubsystem: Int, CaseIterable, Identifiable {
    case uplink, server, models, voice, appearance, privacy, sessions, about, developer

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .uplink: "UPLINK"
        case .server: "SERVER"
        case .models: "MODELS"
        case .voice: "VOICE"
        case .appearance: "APPEARANCE"
        case .privacy: "PRIVACY"
        case .sessions: "SESSIONS"
        case .about: "ABOUT"
        case .developer: "DEVELOPER"
        }
    }

    var chip: String {
        switch self {
        case .uplink: "CONNECTION"
        case .server: "BACKEND PROFILES"
        case .models: "MODEL CATALOG"
        case .voice: "TALK ENGINE"
        case .appearance: "THEME CHANNELS"
        case .privacy: "PERMISSIONS"
        case .sessions: "STORAGE & DATA"
        case .about: "DIAGNOSTICS"
        case .developer: "INTERNAL TOOLS"
        }
    }

    var indexLabel: String { String(format: "%02d", rawValue + 1) }

    var a11yID: String {
        self == .developer ? "settings.row.developer" : "settings.card.\(String(describing: self))"
    }
}

enum SettingsCardValues {
    static func uplink(state: HermesHostConnectionState, isDirect: Bool) -> String {
        switch state {
        case .online: isDirect ? "DIRECT" : "RELAY"
        case .offline: "STANDBY"
        case .unreachable: "OFFLINE"
        case .notConnected: "NOT LINKED"
        }
    }

    static func server(activeProfileName: String?, isPaired: Bool) -> String {
        if let name = activeProfileName, !name.isEmpty { return name.uppercased() }
        return isPaired ? "PAIRED" : "NO PROFILE"
    }

    static func models(activeModelName: String?, brainLabel: String?) -> String {
        if let name = activeModelName, !name.isEmpty { return name.uppercased() }
        if let brain = brainLabel, !brain.isEmpty { return brain.uppercased() }
        return "SELECT"
    }

    static func voice(readAloudOn: Bool, sessionLive: Bool, engineStateText: String) -> String {
        if sessionLive { return engineStateText.uppercased() }
        return readAloudOn ? "READ-ALOUD ON" : "READ-ALOUD OFF"
    }

    static func appearance(themeName: String, channelIndex: Int?) -> String {
        guard let index = channelIndex else { return themeName.uppercased() }
        return "\(themeName.uppercased()) · CH \(String(format: "%02d", index))"
    }

    static func privacy(masterOn: Bool, health: Bool, location: Bool, motion: Bool) -> String {
        let count = masterOn ? [health, location, motion].filter { $0 }.count : 0
        return "\(count) STREAM\(count == 1 ? "" : "S")"
    }

    static func sessions(count: Int?, isPaired: Bool) -> String {
        guard let count else { return "…" }
        if isPaired { return "\(count) · SYNCED" }
        return "\(count) SESSION\(count == 1 ? "" : "S")"
    }

    static func about(isHealthy: Bool) -> String { isHealthy ? "HEALTHY" : "DEGRADED" }

    /// #252 final-review: unpaired/no-profile is the DESIGNED state, not a
    /// fault — a hostless user must read HEALTHY forever, never
    /// DEGRADED-by-default. Once a host IS configured, health tracks the
    /// real connection signal. Shared by the grid card and the About hero so
    /// they can never disagree.
    static func aboutIsHealthy(hostConfigured: Bool, connectionOnline: Bool) -> Bool {
        hostConfigured ? connectionOnline : true
    }

    static func developer(environmentLabel: String) -> String { environmentLabel.uppercased() }
}
