import Foundation

// MARK: - #318 Settings SEARCH (Claude Design 1b) — model layer
//
// A pure, data-driven index over the Settings surface: the ten subsystem
// channels plus their user-facing leaf settings, so a query like "haptics"
// or "verbose" lands on the OWNING deck page (1b layers onto the shipped 1c
// grid/deck — search never grows its own navigation; results route through
// the screen's existing `openSubsystem` seam, pinned by 318-D).
//
// Honesty rules, inherited from the house ("real data only"):
// - every entry names a control that EXISTS at HEAD — the catalog was built
//   from a full leaf inventory of the ten screens (2026-08-25), and 318-A/B
//   pin the load-bearing rows;
// - DEBUG-only rows live inside `#if DEBUG`, so a Release build cannot
//   offer a setting it does not ship;
// - availability filters through the SAME `SettingsSubsystem.cases(...)`
//   list the grid renders from (#395-D's one-list rule) — search cannot
//   surface a tile the device does not have.
struct SettingsSearchEntry: Identifiable, Equatable {
    let title: String
    let keywords: [String]
    let subsystem: SettingsSubsystem
    /// The human path for a NESTED target (e.g. "Appearance → Tuning") —
    /// search lands on the deck page (inherited behaviour, as-is), so the
    /// row owes the user the rest of the route.
    let detail: String?

    var id: String { "\(subsystem.rawValue).\(title)" }

    init(_ title: String, _ keywords: [String], _ subsystem: SettingsSubsystem, detail: String? = nil) {
        self.title = title
        self.keywords = keywords
        self.subsystem = subsystem
        self.detail = detail
    }
}

enum SettingsSearchIndex {
    static let entries: [SettingsSearchEntry] = {
        var all: [SettingsSearchEntry] = [
            // Subsystems themselves — every tile findable by its own name
            // (318-A) and by its chip's vocabulary.
            SettingsSearchEntry("Uplink", ["connection", "gateway", "host", "link"], .uplink),
            SettingsSearchEntry("Server", ["backend profiles", "hosts"], .server),
            SettingsSearchEntry("Models", ["model catalog", "brain"], .models),
            SettingsSearchEntry("Voice", ["talk engine", "speech"], .voice),
            SettingsSearchEntry("Appearance", ["theme channels", "look"], .appearance),
            SettingsSearchEntry("Privacy", ["permissions"], .privacy),
            SettingsSearchEntry("Sessions", ["storage", "data", "history"], .sessions),
            SettingsSearchEntry("Private Cloud", ["pcc", "apple compute", "private cloud compute"], .privateCloud),
            SettingsSearchEntry("About", ["diagnostics", "version", "build"], .about),
            SettingsSearchEntry("Developer", ["internal tools", "debug"], .developer),

            // UPLINK
            SettingsSearchEntry("Base URL", ["hermes url", "gateway address", "host address"], .uplink),
            SettingsSearchEntry("API Key", ["bearer key", "sessions key"], .uplink),
            SettingsSearchEntry("Connect Host", ["pair", "qr", "pairing", "devices", "gateway url", "api key", "scan"], .uplink),
            SettingsSearchEntry("Test Connection", ["ping", "probe", "check connection"], .uplink),

            // SERVER
            SettingsSearchEntry("Backend Profiles", ["switch backend", "active host", "profile"], .server),
            SettingsSearchEntry("Add Profile", ["new backend", "add host"], .server),
            SettingsSearchEntry("Approvals", ["approval mode", "auto-approve", "dangerous commands"], .server),
            SettingsSearchEntry("Plugin Link", ["talaria plugin", "link status"], .server),
            SettingsSearchEntry("Disconnect Host", ["unpair", "disconnect", "forget host"], .uplink),

            // MODELS
            SettingsSearchEntry("Chat Brain", ["on-device model", "automatic routing", "which ai"], .models),
            SettingsSearchEntry("Model Catalog", ["select model", "lock model", "provider", "refresh models"], .models),
            SettingsSearchEntry("Host Default Model", ["default model"], .models),

            // VOICE
            SettingsSearchEntry("Voice Sensitivity", ["mic sensitivity", "noise", "quiet", "noisy", "detection tuning"], .voice),
            SettingsSearchEntry("Auto-Read Replies", ["read aloud", "speak replies", "tts"], .voice),
            SettingsSearchEntry("Read-Aloud Voice", ["tts voice", "speech voice", "choose voice"], .voice),
            SettingsSearchEntry("Reading Speed", ["speech rate", "talk speed"], .voice),
            SettingsSearchEntry("Personal Voice", ["personal voice"], .voice),
            SettingsSearchEntry("Send Transcripts to Hermes", ["voice transcripts"], .voice),
            SettingsSearchEntry("Start Voice Session", ["start talk", "voice call"], .voice),

            // APPEARANCE
            SettingsSearchEntry("Theme Channels", ["theme", "color scheme", "seasonal", "channel browser"], .appearance),
            SettingsSearchEntry("App Icon", ["home screen icon", "alternate icon", "icon"], .appearance),
            SettingsSearchEntry("Accent Color", ["accent"], .appearance, detail: "Appearance → Channel browser"),
            SettingsSearchEntry("Glow", ["glow intensity", "hud glow"], .appearance, detail: "Appearance → Tuning"),
            SettingsSearchEntry("Grid Density", ["background grid"], .appearance, detail: "Appearance → Tuning"),
            SettingsSearchEntry("Reduce Motion", ["less animation", "motion reduction"], .appearance, detail: "Appearance → Tuning"),
            SettingsSearchEntry("Haptic Feedback", ["haptics", "vibration", "tap feedback"], .appearance, detail: "Appearance → Tuning"),
            SettingsSearchEntry("Surprise Me", ["random theme"], .appearance, detail: "Appearance → Channel browser"),

            // PRIVACY
            SettingsSearchEntry("App Lock", ["face id", "touch id", "biometric", "passcode lock"], .privacy),
            SettingsSearchEntry("Lock Grace Period", ["lock delay", "grace period"], .privacy),
            SettingsSearchEntry("Share Sensors with Hermes", ["sensor sharing", "sensors"], .privacy),
            SettingsSearchEntry("Location Access", ["location permission", "gps"], .privacy),
            SettingsSearchEntry("Health Access", ["health permission"], .privacy),
            SettingsSearchEntry("Motion Access", ["motion permission"], .privacy),
            SettingsSearchEntry("Microphone Access", ["mic access", "microphone permission"], .privacy),
            SettingsSearchEntry("Spotlight Indexing", ["system search", "spotlight"], .privacy),
            SettingsSearchEntry("Revoke Data Sharing", ["revoke health", "revoke location", "stop sharing"], .privacy),

            // SESSIONS
            SettingsSearchEntry("Show Empty Sessions", ["empty sessions"], .sessions),
            SettingsSearchEntry("Send While Streaming", ["queue", "steer", "mid-turn send"], .sessions),
            SettingsSearchEntry("Export Conversations", ["export chat", "download", "json"], .sessions),
            SettingsSearchEntry("Clear Conversation", ["clear chat", "delete conversation"], .sessions),

            // PRIVATE CLOUD
            SettingsSearchEntry("Private Cloud β", ["pcc toggle", "apple compute"], .privateCloud),
            SettingsSearchEntry("PCC Quota", ["usage limit", "quota"], .privateCloud),

            // ABOUT
            SettingsSearchEntry("App Version", ["version", "build number"], .about),
            SettingsSearchEntry("Terms & Privacy Policy", ["terms of service", "policy", "support"], .about),

            // DEVELOPER (Release-visible rows)
            SettingsSearchEntry("Verbose Logging", ["verbose", "debug logging", "logs"], .developer),
            SettingsSearchEntry("Environment", ["server environment", "staging"], .developer),
            SettingsSearchEntry("Composer Writing Tools", ["writing tools"], .developer),
        ]
        #if DEBUG
        // DEBUG-only surfaces — compiled out of Release, so a shipping build
        // cannot offer a row it does not have.
        all += [
            SettingsSearchEntry("Batteries & Instruments", ["battery", "instrument", "a/b test"], .developer),
            SettingsSearchEntry("Entitlement Override", ["paywall", "entitlement"], .developer),
        ]
        #endif
        return all
    }()

    /// Case-insensitive match over titles and keywords, filtered to the
    /// subsystems visible on THIS device. Empty/whitespace queries match
    /// nothing (the grid stays). Title matches rank above keyword matches;
    /// ties keep deck order.
    static func matches(query: String, visible: [SettingsSubsystem]) -> [SettingsSearchEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        let visibleSet = Set(visible)
        func rank(_ entry: SettingsSearchEntry) -> Int? {
            let title = entry.title.lowercased()
            if title.hasPrefix(needle) { return 0 }
            if title.contains(needle) { return 1 }
            if entry.keywords.contains(where: { $0.hasPrefix(needle) }) { return 2 }
            if entry.keywords.contains(where: { $0.contains(needle) }) { return 3 }
            return nil
        }
        func deckOrder(_ subsystem: SettingsSubsystem) -> Int {
            visible.firstIndex(of: subsystem) ?? Int.max
        }
        return entries
            .filter { visibleSet.contains($0.subsystem) }
            .compactMap { entry in rank(entry).map { (entry, $0) } }
            .sorted { lhs, rhs in
                (lhs.1, deckOrder(lhs.0.subsystem)) < (rhs.1, deckOrder(rhs.0.subsystem))
            }
            .map(\.0)
    }
}
