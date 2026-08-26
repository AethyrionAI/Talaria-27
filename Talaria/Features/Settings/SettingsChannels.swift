import SwiftUI

// MARK: - #252 Subsystem Channels — model layer
//
// Deck order and card telemetry for the settings grid/deck. Pure — no store
// access here so the formatters are unit-testable; SettingsChannelsScreen
// feeds them live values.
enum SettingsSubsystem: Int, CaseIterable, Identifiable {
    // #395-D2 (Owen's positional-08 ruling): `.privateCloud` sits BEFORE
    // `.about`, and card numbers are positional — computed from the tiles
    // visible on this device (`indexLabel(in:)`) — so a device without the
    // tier shows ABOUT at its classic 08 with no hole, and a device with it
    // reads 08 PRIVATE CLOUD / 09 ABOUT / 10 DEVELOPER.
    case uplink, server, models, voice, appearance, privacy, sessions, privateCloud, about, developer

    var id: Int { rawValue }

    /// #395-D: the tile exists only where the tier does. The filter is here,
    /// pure and testable, so the grid, the deck pager, and the page dots all
    /// consume ONE list and can never disagree about what exists.
    static func cases(privateCloudAvailable: Bool) -> [SettingsSubsystem] {
        privateCloudAvailable ? allCases : allCases.filter { $0 != .privateCloud }
    }

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
        case .privateCloud: "PRIVATE CLOUD"
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
        case .privateCloud: "APPLE COMPUTE"
        case .developer: "INTERNAL TOOLS"
        }
    }

    /// #395-D2: the card number is POSITIONAL — computed from the tiles
    /// visible on this device — so a filtered-out tile leaves no hole. The
    /// old rawValue-derived property is deliberately GONE: a static number
    /// beside a conditional tile is a stale source waiting to disagree.
    func indexLabel(in visible: [SettingsSubsystem]) -> String {
        String(format: "%02d", (visible.firstIndex(of: self) ?? rawValue) + 1)
    }

    var a11yID: String {
        self == .developer ? "settings.row.developer" : "settings.card.\(String(describing: self))"
    }
}

enum SettingsCardValues {
    // #256 verbiage round (Owen): "DIRECT" answered a question users don't
    // ask — and the DIRECT/RELAY distinction dies with #251 Phase 4 anyway.
    //
    // **#309 Lane B: it died.** The `isDirect` argument is gone with the
    // second transport it distinguished; an ONLINE host is reached one way
    // now, so the qualifier had exactly one possible value and printing the
    // other was unreachable code that could still be read as a claim.
    static func uplink(state: HermesHostConnectionState) -> String {
        switch state {
        case .online: "CONNECTED"
        case .offline: "STANDBY"
        case .unreachable: "OFFLINE"
        case .notConnected: "NOT LINKED"
        // #350: unknown renders as unknown — no LINKED claim, no accent.
        case .checking: "CHECKING"
        }
    }

    /// #309 Lane B re-keyed the second argument off relay pairing. The
    /// fallback word changed with it: "PAIRED" named a ceremony that no longer
    /// exists, and a profile-less install that HOLDS credentials is described
    /// by what it can do, not by what it once redeemed.
    static func server(activeProfileName: String?, hasHost: Bool) -> String {
        if let name = activeProfileName, !name.isEmpty { return name.uppercased() }
        return hasHost ? "HOST SET" : "NO PROFILE"
    }

    static func models(activeModelName: String?, brainLabel: String?) -> String {
        if let name = activeModelName, !name.isEmpty { return name.uppercased() }
        if let brain = brainLabel, !brain.isEmpty { return brain.uppercased() }
        return "SELECT"
    }

    // #256 verbiage round (Owen): the card shows the voice ROUTE, not the
    // read-aloud toggle (that detail lives on the Voice page). Three-way
    // voluntary/forced distinction: ON-DEVICE = the brain choice implies
    // local voice; LOCAL = the user picked the native engine; LOCAL ONLY =
    // linked to Hermes but realtime isn't available — the forced fallback.
    /// #180 lane 180-L: `engine` is optional — nil means no engine has been
    /// selected yet, and the card must not answer REALTIME for one. Unknown
    /// gets its own branch (rule 5) rather than falling to the affirmative
    /// side. The idle/blocked/failed answers are unchanged, because those were
    /// never engine-dependent; the transitional states reuse the EXISTING "…"
    /// placeholder rather than introducing copy.
    static func voice(brainIsLocal: Bool, engine: VoiceEngine?, talkState: TalkConnectionState) -> String {
        if brainIsLocal { return "ON-DEVICE" }
        if engine == .native { return "LOCAL" }
        if engine == nil {
            return switch talkState {
            case .idle, .blocked, .failed: "LOCAL ONLY"
            default: "…"
            }
        }
        return switch talkState {
        case .connected: "REALTIME · LIVE"
        case .ready, .connecting: "REALTIME"
        case .checking: "…"
        case .idle, .blocked, .failed: "LOCAL ONLY"
        }
    }

    static func appearance(themeName: String, channelIndex: Int?) -> String {
        guard let index = channelIndex else { return themeName.uppercased() }
        return "\(themeName.uppercased()) · CH \(String(format: "%02d", index))"
    }

    /// #256 (Owen's device-pass verdict): "0 STREAMS" clarified nothing.
    /// The value now names what the number counts — sensor streams.
    static func privacy(masterOn: Bool, health: Bool, location: Bool, motion: Bool) -> String {
        let count = masterOn ? [health, location, motion].filter { $0 }.count : 0
        if count == 0 { return "SENSORS OFF" }
        return "\(count) SENSOR\(count == 1 ? "" : "S") LIVE"
    }

    /// #256: the grid's at-a-glance status strip — LINK · HOST · MODEL.
    /// Hostless collapses to the on-device story (no "—" host noise);
    /// unknowable hosts render "—" (real data only).
    static func statusStrip(state: HermesHostConnectionState,
                            hostName: String?, modelName: String?, brainLabel: String?) -> String {
        let model = models(activeModelName: modelName, brainLabel: brainLabel)
        if case .notConnected = state {
            return model == "ON-DEVICE" ? "ON-DEVICE" : "ON-DEVICE · \(model)"
        }
        let host = (hostName?.isEmpty == false) ? hostName!.uppercased() : "—"
        // #309 Lane B: one transport, so no qualifier — see `uplink` above.
        let link: String = switch state {
        case .online: "LINKED"
        case .offline: "STANDBY"
        case .unreachable: "OFFLINE"
        case .notConnected: "ON-DEVICE" // unreachable — handled above
        case .checking: "CHECKING" // #350: measurement pending, no claim
        }
        return "\(link) · \(host) · \(model)"
    }

    /// #309 Lane B: SYNCED now means "there is a host these sessions live
    /// on", which is what the word always implied and what relay pairing
    /// stopped being able to answer.
    static func sessions(count: Int?, hasHost: Bool) -> String {
        guard let count else { return "…" }
        if hasHost { return "\(count) · SYNCED" }
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

    /// #395-D: the PCC card describes the user's own SETTING first — disabled
    /// reads OFF whatever the quota says (#180: a LIMIT REACHED over a tier
    /// the user turned off sends them hunting for a fault they don't have).
    /// Quota words appear only when the tier is on, and an unknown or
    /// unloaded quota reads plain ON (#391: no claim without a measurement).
    static func privateCloud(enabled: Bool, quota: LocalChatBackend.PrivateCloudStatus.Quota?) -> String {
        guard enabled else { return "OFF" }
        return switch quota {
        case .belowLimit(approaching: true): "NEARING LIMIT"
        case .limitReached: "LIMIT REACHED"
        case .belowLimit(approaching: false), .unknown, nil: "ON"
        }
    }
}

/// #252R-A — the ACCENT half of the card telemetry, extracted here from
/// `SettingsChannelsScreen.cardIsAccented` so it is unit-testable **at all**.
///
/// Every predicate below answers one question: *is this subsystem in a live /
/// active state?* Pure and store-free, exactly like `SettingsCardValues`
/// above — `SettingsChannelsScreen` feeds them live values.
///
/// **Why the extraction is part of the fix, not tidying.** `cardIsAccented`
/// was a `private func` on the View: unreachable even under
/// `@testable import`, so it carried zero coverage while the value formatters
/// beside it carried thirteen pins. #256-H moved the Voice card's VALUE from
/// the read-aloud toggle to the engine route and left the ACCENT reading
/// `readAloudAutoPlay`; nothing in the suite could see the divergence, and it
/// stood for four days. Testability was the missing guard, so it is restored
/// in the same change as the behaviour.
enum SettingsCardAccent {
    static func uplink(state: HermesHostConnectionState) -> Bool { state == .online }

    static func server(hasActiveProfile: Bool) -> Bool { hasActiveProfile }

    static func models(activeModelName: String?) -> Bool { activeModelName?.isEmpty == false }

    /// #252R-A: the Voice card's accent must describe the same fact its VALUE
    /// names, so the glow and the text cannot disagree. It takes the same
    /// three inputs `SettingsCardValues.voice` takes, and the equivalence
    /// `accent ⇔ value == "REALTIME · LIVE"` is pinned exhaustively over
    /// every (brain × engine × talk-state) combination in
    /// `SettingsChannelsTests`.
    ///
    /// **Owen's ruling (2026-08-09):** glow ONLY for a genuinely connected
    /// realtime session — not for any "available" route. `ON-DEVICE` is
    /// always available, so glowing for it would make the accent meaningless
    /// on a hostless install, which is the DEFAULT user under the launch
    /// pivot. Cheap to reverse if he wants the broader reading later.
    ///
    /// `readAloudAutoPlay` is deliberately absent: it is what this predicate
    /// used to return, and it names a setting the card no longer displays —
    /// the #180 family (a signal that does not say what it appears to say).
    /// The read-aloud toggle keeps its own home on `VoiceSettingsScreen`, and
    /// the auto-read pipeline keeps its own reader in `AppContainer`.
    ///
    /// `engine` is OPTIONAL, and nil is load-bearing: #180-L (L2) made the
    /// snapshot's engine optional precisely so that "no engine has been
    /// selected yet" stops being reported as `.realtime`. An unselected
    /// engine is not a live route, so it must not glow — putting UNKNOWN on
    /// the negative branch here rather than letting `?? .realtime` smuggle
    /// the optimistic default back in. Corrected 2026-08-09: this parameter
    /// shipped non-optional and, merged with #180-L, did not compile.
    static func voice(brainIsLocal: Bool, engine: VoiceEngine?,
                      talkState: TalkConnectionState) -> Bool {
        guard !brainIsLocal, engine == .realtime else { return false }
        return talkState == .connected
    }

    /// The one card whose subject is always on — a theme is always applied.
    /// Named rather than inlined so the nine read as a single table.
    static var appearance: Bool { true }

    /// Accented exactly when the value is not "SENSORS OFF" — the master
    /// switch on AND at least one stream selected.
    static func privacy(masterOn: Bool, health: Bool, location: Bool, motion: Bool) -> Bool {
        masterOn && (health || location || motion)
    }

    /// `nil` is "not loaded yet" (the value renders "…"), not zero sessions.
    static func sessions(count: Int?) -> Bool { count != nil }

    static func about(isHealthy: Bool) -> Bool { isHealthy }

    /// #395-D: glows when the tier is OFFERED — the accent tracks the user's
    /// setting, not quota health, so it can never disagree with the value's
    /// OFF/ON split.
    static func privateCloud(enabled: Bool) -> Bool { enabled }

    /// The Developer row is not a subsystem card and never glows.
    static var developer: Bool { false }
}
