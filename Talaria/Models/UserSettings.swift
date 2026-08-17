import Foundation

struct AppBuildConfiguration: Equatable, Sendable {
    let supportURL: URL?
    let termsOfServiceURL: URL?
    let privacyPolicyURL: URL?

    static func current(bundle: Bundle = .main) -> AppBuildConfiguration {
        let info = bundle.infoDictionary ?? [:]

        func urlValue(_ key: String) -> URL? {
            guard let raw = info[key] as? String, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return URL(string: raw)
        }

        return AppBuildConfiguration(
            supportURL: urlValue("APP_SUPPORT_URL"),
            termsOfServiceURL: urlValue("APP_TERMS_URL"),
            privacyPolicyURL: urlValue("APP_PRIVACY_URL")
        )
    }
}

/// The user's relay endpoint. Lane M (#114) retired the "hosted relay" mode
/// (never used, never will be — Owen) and the mode switch with it: every
/// backend profile is its-own-relay by construction, and this struct
/// survives only as the legacy seed the profile migration reads plus the
/// pre-profile persistence shape. Old persisted blobs (with `relayMode` /
/// hosted keys) decode by ignoring the dead keys.
struct RelayConfiguration: Codable, Hashable, Sendable {
    var customRelayBaseURL: String

    init(customRelayBaseURL: String = "") {
        self.customRelayBaseURL = RelayConfiguration.normalizeBaseURL(customRelayBaseURL) ?? customRelayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum CodingKeys: String, CodingKey {
        case customRelayBaseURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        customRelayBaseURL = try container.decodeIfPresent(String.self, forKey: .customRelayBaseURL) ?? ""
    }

    static func defaultValue(
        environmentPolicy: AppEnvironmentPolicy = .currentBuild
    ) -> RelayConfiguration {
        RelayConfiguration(
            customRelayBaseURL: environmentPolicy.allowsEnvironmentOverrides ? AppEnvironment.development.baseURLString : ""
        )
    }

    static func migratedLegacyValue(
        environment: AppEnvironment,
        environmentPolicy: AppEnvironmentPolicy = .currentBuild
    ) -> RelayConfiguration {
        if environmentPolicy.allowsEnvironmentOverrides, environment != .production {
            return RelayConfiguration(customRelayBaseURL: environment.baseURLString)
        }
        return RelayConfiguration.defaultValue(environmentPolicy: environmentPolicy)
    }

    var activeBaseURLString: String? {
        RelayConfiguration.normalizeBaseURL(customRelayBaseURL)
    }

    var relayOriginLabel: String {
        guard let baseURLString = activeBaseURLString, let url = URL(string: baseURLString) else {
            return "Not Configured"
        }
        return url.host ?? baseURLString
    }

    var validationMessage: String? {
        let trimmed = customRelayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Enter your relay URL." }
        guard RelayConfiguration.normalizeBaseURL(trimmed) != nil else {
            return "Relay URL must be an absolute http(s) URL ending with /v1."
        }
        return nil
    }

    static func normalizeBaseURL(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if !trimmed.hasPrefix("http://"), !trimmed.hasPrefix("https://") {
            return nil
        }

        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }

        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme)
        else {
            return nil
        }

        let normalizedPath: String
        switch components.path {
        case "", "/":
            normalizedPath = "/v1"
        default:
            normalizedPath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        }
        guard normalizedPath.hasSuffix("/v1") else {
            return nil
        }
        components.path = normalizedPath
        return components.string
    }
}

/// #144 — a test run must never enrol as a LIVE device.
///
/// **The pollution was real, ongoing, and measurable.** The Mac relay's `devices`
/// table held **92 `iPhone 17 Pro Max` + 5 `CC-M4a-Baseline` rows against 2 real
/// `iPhone` rows** on 2026-08-02 — and **five of them were created that same day
/// by this project's own suite and gate runs.** Each carries an ACTIVE push
/// registration, so the relay fans real pushes out to dead simulator tokens.
///
/// **Mechanism:** UI tests launch the app with a fresh `UITEST_DEFAULTS_SUITE`, so
/// `state.deviceRegistered` is false and `bootstrap` registers a brand-new device
/// with a fresh `installationID` (`AppSessionStore.swift:88-99`). Of the nine
/// `.launch()` sites in the UI test target, only four set
/// `UITEST_PAIRING_MODE = "mock"` — **including the auto-generated `testLaunch`,
/// which runs on every gate.** The other five got `LivePairingService`.
///
/// **Why detection and not "remember to set the env var":** the env var already
/// existed and was the mechanism — it just relied on every test author
/// remembering. **A guard that depends on being remembered is the thing that
/// failed.** This makes the safe path the default and the live path the one that
/// has to be earned.
///
/// **Gated on `allowsEnvironmentOverrides` deliberately.** Without that, setting
/// an environment variable on a SHIPPED build would silently disable real
/// pairing. A diagnostic convenience must never become a production off-switch.
enum TestRunGuard {
    /// XCTest sets `XCTestConfigurationFilePath` in the process it hosts, which
    /// covers unit tests. A UI test runs the app as a SEPARATE process that never
    /// sees it — so the `UITEST_` prefix the target already uses is the signal
    /// there. Any key with that prefix counts: a launch that configures itself
    /// for testing at all is a test.
    nonisolated static func isRunningUnderTest(_ environment: [String: String]) -> Bool {
        if environment["XCTestConfigurationFilePath"] != nil { return true }
        return environment.keys.contains { $0.hasPrefix("UITEST_") }
    }

    /// The decision the container actually makes. `explicitMockRequested` keeps
    /// the existing `UITEST_PAIRING_MODE == "mock"` contract working unchanged.
    ///
    /// **There is deliberately no opt-IN to LIVE pairing under test** — only an
    /// opt-in to mock. The asymmetry is the point: the safe path is the default
    /// and the live path has to be earned, because #144 was caused by a guard
    /// that depended on every test author remembering to set a variable. The
    /// cost, noted so it is not discovered mid-lane (external audit, 2026-08-02):
    /// a future UI lane that genuinely needs real pairing against a staging relay
    /// will need a CODE change here, not an environment variable. That is the
    /// intended friction — an env var that re-enables live enrolment is exactly
    /// what a shipped build must never honour.
    nonisolated static func mustUseMockPairing(
        environment: [String: String],
        explicitMockRequested: Bool,
        allowsEnvironmentOverrides: Bool
    ) -> Bool {
        if explicitMockRequested { return true }
        guard allowsEnvironmentOverrides else { return false }
        return isRunningUnderTest(environment)
    }
}

struct AppEnvironmentPolicy: Equatable, Sendable {
    let allowsEnvironmentOverrides: Bool

    var availableEnvironments: [AppEnvironment] {
        allowsEnvironmentOverrides ? AppEnvironment.allCases : [.production]
    }

    var defaultEnvironment: AppEnvironment {
        .production
    }

    func sanitize(_ settings: UserSettings) -> UserSettings {
        var sanitized = settings
        if !availableEnvironments.contains(sanitized.environment) {
            sanitized.environment = defaultEnvironment
        }
        return sanitized
    }

    static let currentBuild: AppEnvironmentPolicy = {
        #if DEBUG
        AppEnvironmentPolicy(allowsEnvironmentOverrides: true)
        #else
        AppEnvironmentPolicy(allowsEnvironmentOverrides: false)
        #endif
    }()
}

enum LocationSyncPreference: String, Codable, Hashable, Sendable {
    case foregroundOnly
    case backgroundAllowed

    var displayLabel: String {
        switch self {
        case .foregroundOnly: "Foreground Only"
        case .backgroundAllowed: "Background Allowed"
        }
    }
}

/// Full visual environment (background, foregrounds, surfaces, textures, orb
/// identity). The accent (`AppearanceAccent`) selects the energetic hue *inside*
/// a theme — see `ThemePaletteCore.swift` for the resolved color tables.
///
/// A thin persisted id (#49): naming lives on the catalog's `ThemeDefinition`,
/// render data on the shared `ThemePaletteCatalog` — no per-case behavior here.
enum AppearanceTheme: String, Codable, CaseIterable, Hashable, Sendable {
    case deepField
    case solarForge
    case terminal
    case paperTape
    case winterFrost
    case summerSolar
    case springSprout
    case autumnHarvest
    case cerealBox
    case bubblegumMecha
    case retroSciFi
    case eventHorizon
    case glitchGarden
    case witchsBrew
    case holoSushi
    case lunarDiner
    case cyberCactus
    case discoInferno
    case graffitiGalaxy
    case karaokeSupernova
    case midnightAquarium
    case moltenForge
    case luchaLibre
    case kaijuAttack
    case pulpNoir
    case casinoLucky7s
    case cosmicBowling
    case stickerBombToybox
    /// The first ADAPTIVE theme (Lane L Phase 2): one persisted identity
    /// that renders as `comicVillain` under the dark system appearance and
    /// `comicFunnies` under light. Raw value pinned to
    /// `AdaptiveThemeIdentity.comicBookRawValue`.
    case comicBook

    /// Display name — single source of truth is the catalog definition (#49).
    var displayLabel: String {
        ThemeCatalog.definition(id: rawValue)?.displayName ?? rawValue
    }

    /// Whether this is a light environment — feeds the root
    /// `preferredColorScheme` (via `AppearanceTheme.preferredColorScheme`,
    /// Design.swift) so system chrome (keyboard, sheets, toggles) follows
    /// the theme. Resolved from the palette data (#49) through the
    /// scheme-free canonical identity — the adaptive Comic Book reads its
    /// dark (villain) half here, but the root never consults `isLight` for
    /// it (adaptive themes leave the scheme to the system).
    var isLight: Bool {
        ThemePaletteCatalog.definition(for: themeID).isLight
    }
}

/// How the active theme is chosen (issue #24). `.manual` (default) uses the
/// user's persisted `appearanceTheme` unchanged — so default behavior, and the
/// Deep Field byte-identical guarantee, are preserved. `.automatic` rotates the
/// theme by season (see `ThemeCatalog`), with manual selection still overriding.
enum AppearanceThemeMode: String, Codable, CaseIterable, Hashable, Sendable {
    case manual
    case automatic

    var displayLabel: String {
        switch self {
        case .manual: "Manual"
        case .automatic: "Automatic"
        }
    }
}

/// Three persisted accent *slots*. Raw values are stable (`cyan`/`amber`/`violet`,
/// no migration); each theme re-interprets the slots as its own hue family, with
/// the `.cyan` slot always resolving to the theme's hero accent (Cyan Arc /
/// Forge Amber / Phosphor Green / Tracker Red).
enum AppearanceAccent: String, Codable, CaseIterable, Hashable, Sendable {
    case cyan
    case amber
    case violet

    /// The slot's canonical (Deep Field) label.
    var displayLabel: String { displayLabel(for: ThemeID.deepField) }

    /// Contextual label for the slot as resolved inside a theme — read from
    /// the theme's accent-variant data (#49), so a new theme names its slots
    /// in its catalog entry instead of a switch arm here. Resolves through
    /// the canonical (scheme-free) identity; surfaces that present the
    /// adaptive theme's live variant use the `ThemeID` overload instead.
    func displayLabel(for theme: AppearanceTheme) -> String {
        displayLabel(for: theme.themeID)
    }

    /// Render-identity overload — the single label path for callers that
    /// already hold a scheme-resolved `ThemeID` (Lane L Phase 2).
    func displayLabel(for themeID: ThemeID) -> String {
        ThemePaletteCatalog.definition(for: themeID).accents[slot].displayName
    }
}

enum GridDensity: String, Codable, CaseIterable, Hashable, Sendable {
    case off
    case faint
    case bold

    var displayLabel: String {
        switch self {
        case .off: "Off"
        case .faint: "Faint"
        case .bold: "Bold"
        }
    }

    /// HUD grid-line opacity (0…1) for HUDScreenBackground.
    var gridIntensity: Double {
        switch self {
        case .off: 0.0
        case .faint: 0.35
        case .bold: 0.8
        }
    }
}

struct UserSettings: Codable, Hashable, Sendable {
    static let defaultHermesAPIBaseURL = "http://ojamd:8642"
    /// Default Talaria models-shim endpoint — OJAMD, the production Hermes host (same
    /// box as the chat gateway above). The shim exposes the Hermes model list +
    /// persistent set-default without the privileged dashboard plane. See tools/models-shim/.
    static let defaultModelsShimBaseURL = "http://ojamd:8765"

    var userName: String
    var avatarInitials: String
    var hapticFeedbackEnabled: Bool
    var environment: AppEnvironment
    var relayConfiguration: RelayConfiguration
    var autoConnectOnLaunch: Bool
    var locationSyncPreference: LocationSyncPreference
    // In-app permission revocation (#6): the app can't rescind an iOS grant,
    // so revoke = durably stop USING it. Since #352 these gate
    // `PhoneQueryResponder.deniedGate` — the flag IS the mechanism, so a
    // revoke survives relaunch by construction (nothing captures outside a
    // query).
    var healthCollectionEnabled: Bool
    var locationCollectionEnabled: Bool
    /// #137: master opt-in for the optional sensor streaming layer. OFF by
    /// default — pairing grants chat, nothing else. Grandfathered ON once
    /// for devices already streaming (SensorStreamingGrandfathering).
    var sensorStreamingEnabled: Bool
    /// #137: motion joins health/location as an individually gated sensor.
    var motionCollectionEnabled: Bool
    var hermesAPIBaseURL: String
    var modelsShimBaseURL: String
    /// After a Talk session ends, also POST the transcript to the Sessions API
    /// as a normal text turn so the agent has voice context for the next
    /// exchange (#1). Off = voice sessions stay local-only.
    var postVoiceTranscriptsToHermes: Bool
    // Read-aloud (#2): local AVSpeechSynthesizer output for Hermes replies.
    /// Speak replies automatically as they stream (sentence-buffered). The
    /// per-bubble speaker toggle works regardless of this flag.
    var readAloudAutoPlay: Bool
    /// Persisted `AVSpeechSynthesisVoice` identifier; nil = best system voice.
    var readAloudVoiceIdentifier: String?
    /// `AVSpeechUtterance` rate on its native 0…1 scale (0.5 = system default).
    var readAloudRate: Double
    /// Opts the composer into `.writingToolsBehavior(.complete)` (#4). Default
    /// OFF: the full Writing Tools panel froze the device on iOS 27 beta 2
    /// (broken PresentWritingToolsResult handoff — see 73034b7/03f3862). The
    /// Developer screen exposes this for re-testing on newer betas; off means
    /// the system-default (.automatic) inline tier, which is safe.
    var composerWritingToolsEnabled: Bool
    var appearanceTheme: AppearanceTheme
    var appearanceThemeMode: AppearanceThemeMode
    var appearanceAccent: AppearanceAccent
    var hudGlowIntensity: Double
    var gridDensity: GridDensity
    var reduceMotion: Bool
    var verboseLogging: Bool
    /// #17: donate sessions + agent files to Spotlight. Default OFF — chat
    /// previews entering the system index is an explicit opt-in privacy trade.
    var spotlightIndexingEnabled: Bool
    /// Sessions drawer: show rows the host reports as having zero messages.
    /// Default OFF — the gateway accepts `?min_messages=1` and ignores it
    /// (OPEN_ITEMS #187), so the shelf filters them client-side. The active
    /// session and any pinned session are exempt from the filter regardless.
    var showEmptySessions: Bool
    /// #124: biometric app lock (`.deviceOwnerAuthentication` — biometry with
    /// passcode fallback, never biometry-only). Default OFF, free tier.
    var appLockEnabled: Bool
    /// #124: how long the app may sit backgrounded before return requires auth.
    var appLockGracePeriod: AppLockGracePeriod
    /// #283: Developer-screen switch for the runs-plane transport
    /// (`/v1/runs` + status-poll recovery). Default OFF — the sessions path
    /// stays the default transport until 3A-F passes; `SessionsHermesClient`
    /// reads this through a provider closure, not a direct settings read.
    var useRunsTransport: Bool
    /// #224 Phase 0: the on-device confirm gate's approval mode. **GLOBAL,
    /// not per-profile** (Owen's ballot, ruling 2) — the gate governs THIS
    /// PHONE's writes (EventKit, AlarmKit, Reminders), which happen
    /// identically whichever host a turn came from and happen at all when no
    /// host is configured, so making the safety posture change with the
    /// active profile would be a footgun with no upside.
    ///
    /// `.manual` is the default AND the only value this build resolves to: no
    /// user-facing control ships in Phase 0 (ruling 1), and the decoder
    /// clamps through `ApprovalMode.resolved(_:)` so no persisted blob can
    /// arm a mode whose handling does not exist yet.
    var approvalMode: ApprovalMode

    init(
        userName: String = "User",
        avatarInitials: String = "U",
        hapticFeedbackEnabled: Bool = true,
        environment: AppEnvironment = AppEnvironmentPolicy.currentBuild.defaultEnvironment,
        relayConfiguration: RelayConfiguration = RelayConfiguration.defaultValue(),
        autoConnectOnLaunch: Bool = true,
        locationSyncPreference: LocationSyncPreference = .foregroundOnly,
        healthCollectionEnabled: Bool = false,
        locationCollectionEnabled: Bool = false,
        sensorStreamingEnabled: Bool = false,
        motionCollectionEnabled: Bool = false,
        hermesAPIBaseURL: String = UserSettings.defaultHermesAPIBaseURL,
        modelsShimBaseURL: String = UserSettings.defaultModelsShimBaseURL,
        postVoiceTranscriptsToHermes: Bool = true,
        readAloudAutoPlay: Bool = false,
        readAloudVoiceIdentifier: String? = nil,
        readAloudRate: Double = 0.5,
        composerWritingToolsEnabled: Bool = false,
        appearanceTheme: AppearanceTheme = .deepField,
        appearanceThemeMode: AppearanceThemeMode = .manual,
        appearanceAccent: AppearanceAccent = .cyan,
        hudGlowIntensity: Double = 1.0,
        gridDensity: GridDensity = .faint,
        reduceMotion: Bool = false,
        verboseLogging: Bool = false,
        spotlightIndexingEnabled: Bool = false,
        showEmptySessions: Bool = false,
        appLockEnabled: Bool = false,
        appLockGracePeriod: AppLockGracePeriod = .immediate,
        useRunsTransport: Bool = false,
        approvalMode: ApprovalMode = .manual
    ) {
        self.userName = userName
        self.avatarInitials = avatarInitials
        self.hapticFeedbackEnabled = hapticFeedbackEnabled
        self.environment = environment
        self.relayConfiguration = relayConfiguration
        self.autoConnectOnLaunch = autoConnectOnLaunch
        self.locationSyncPreference = locationSyncPreference
        self.healthCollectionEnabled = healthCollectionEnabled
        self.locationCollectionEnabled = locationCollectionEnabled
        self.sensorStreamingEnabled = sensorStreamingEnabled
        self.motionCollectionEnabled = motionCollectionEnabled
        self.hermesAPIBaseURL = hermesAPIBaseURL
        self.modelsShimBaseURL = modelsShimBaseURL
        self.postVoiceTranscriptsToHermes = postVoiceTranscriptsToHermes
        self.readAloudAutoPlay = readAloudAutoPlay
        self.readAloudVoiceIdentifier = readAloudVoiceIdentifier
        self.readAloudRate = readAloudRate
        self.composerWritingToolsEnabled = composerWritingToolsEnabled
        self.appearanceTheme = appearanceTheme
        self.appearanceThemeMode = appearanceThemeMode
        self.appearanceAccent = appearanceAccent
        self.hudGlowIntensity = hudGlowIntensity
        self.gridDensity = gridDensity
        self.reduceMotion = reduceMotion
        self.verboseLogging = verboseLogging
        self.spotlightIndexingEnabled = spotlightIndexingEnabled
        self.showEmptySessions = showEmptySessions
        self.appLockEnabled = appLockEnabled
        self.appLockGracePeriod = appLockGracePeriod
        self.useRunsTransport = useRunsTransport
        self.approvalMode = approvalMode
    }

    private enum CodingKeys: String, CodingKey {
        case userName
        case avatarInitials
        case hapticFeedbackEnabled
        case environment
        case relayConfiguration
        case autoConnectOnLaunch
        case locationSyncPreference
        case healthCollectionEnabled
        case locationCollectionEnabled
        case sensorStreamingEnabled
        case motionCollectionEnabled
        case hermesAPIBaseURL
        case modelsShimBaseURL
        case postVoiceTranscriptsToHermes
        case readAloudAutoPlay
        case readAloudVoiceIdentifier
        case readAloudRate
        case composerWritingToolsEnabled
        case appearanceTheme
        case appearanceThemeMode
        case appearanceAccent
        case hudGlowIntensity
        case gridDensity
        case reduceMotion
        case verboseLogging
        case spotlightIndexingEnabled
        case showEmptySessions
        case appLockEnabled
        case appLockGracePeriod
        case useRunsTransport
        case approvalMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userName = try container.decodeIfPresent(String.self, forKey: .userName) ?? "User"
        avatarInitials = try container.decodeIfPresent(String.self, forKey: .avatarInitials) ?? "U"
        hapticFeedbackEnabled = try container.decodeIfPresent(Bool.self, forKey: .hapticFeedbackEnabled) ?? true
        environment = try container.decodeIfPresent(AppEnvironment.self, forKey: .environment) ?? AppEnvironmentPolicy.currentBuild.defaultEnvironment
        relayConfiguration = try container.decodeIfPresent(RelayConfiguration.self, forKey: .relayConfiguration)
            ?? RelayConfiguration.migratedLegacyValue(environment: environment)
        autoConnectOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .autoConnectOnLaunch) ?? true
        locationSyncPreference = try container.decodeIfPresent(LocationSyncPreference.self, forKey: .locationSyncPreference) ?? .foregroundOnly
        healthCollectionEnabled = try container.decodeIfPresent(Bool.self, forKey: .healthCollectionEnabled) ?? true
        locationCollectionEnabled = try container.decodeIfPresent(Bool.self, forKey: .locationCollectionEnabled) ?? true
        // #137: absent keys mean a pre-opt-in blob — master stays OFF here;
        // SensorStreamingGrandfathering (not the decoder) decides whether an
        // active pairing grandfathers it ON.
        sensorStreamingEnabled = try container.decodeIfPresent(Bool.self, forKey: .sensorStreamingEnabled) ?? false
        motionCollectionEnabled = try container.decodeIfPresent(Bool.self, forKey: .motionCollectionEnabled) ?? false
        hermesAPIBaseURL = try container.decodeIfPresent(String.self, forKey: .hermesAPIBaseURL) ?? UserSettings.defaultHermesAPIBaseURL
        modelsShimBaseURL = try container.decodeIfPresent(String.self, forKey: .modelsShimBaseURL) ?? UserSettings.defaultModelsShimBaseURL
        postVoiceTranscriptsToHermes = try container.decodeIfPresent(Bool.self, forKey: .postVoiceTranscriptsToHermes) ?? true
        readAloudAutoPlay = try container.decodeIfPresent(Bool.self, forKey: .readAloudAutoPlay) ?? false
        readAloudVoiceIdentifier = try container.decodeIfPresent(String.self, forKey: .readAloudVoiceIdentifier)
        readAloudRate = try container.decodeIfPresent(Double.self, forKey: .readAloudRate) ?? 0.5
        composerWritingToolsEnabled = try container.decodeIfPresent(Bool.self, forKey: .composerWritingToolsEnabled) ?? false
        // try? — a persisted theme whose case was removed (e.g. Deep Sea
        // Diner) must degrade to Deep Field, not fail the whole settings
        // decode and reset every preference.
        appearanceTheme = (try? container.decodeIfPresent(AppearanceTheme.self, forKey: .appearanceTheme)) ?? .deepField
        appearanceThemeMode = try container.decodeIfPresent(AppearanceThemeMode.self, forKey: .appearanceThemeMode) ?? .manual
        appearanceAccent = try container.decodeIfPresent(AppearanceAccent.self, forKey: .appearanceAccent) ?? .cyan
        hudGlowIntensity = try container.decodeIfPresent(Double.self, forKey: .hudGlowIntensity) ?? 1.0
        gridDensity = try container.decodeIfPresent(GridDensity.self, forKey: .gridDensity) ?? .faint
        reduceMotion = try container.decodeIfPresent(Bool.self, forKey: .reduceMotion) ?? false
        verboseLogging = try container.decodeIfPresent(Bool.self, forKey: .verboseLogging) ?? false
        spotlightIndexingEnabled = try container.decodeIfPresent(Bool.self, forKey: .spotlightIndexingEnabled) ?? false
        showEmptySessions = try container.decodeIfPresent(Bool.self, forKey: .showEmptySessions) ?? false
        appLockEnabled = try container.decodeIfPresent(Bool.self, forKey: .appLockEnabled) ?? false
        appLockGracePeriod = try container.decodeIfPresent(AppLockGracePeriod.self, forKey: .appLockGracePeriod) ?? .immediate
        useRunsTransport = try container.decodeIfPresent(Bool.self, forKey: .useRunsTransport) ?? false
        // #224 Phase 0: `try?` for the `appearanceTheme` reason — a mode
        // written by some later build must degrade to the default, never
        // fail the whole settings decode and reset every preference — and
        // `resolved(_:)` on top of it, because a blob that NAMES a mode
        // this build ships no handling for must not arm it.
        approvalMode = ApprovalMode.resolved(
            (try? container.decodeIfPresent(ApprovalMode.self, forKey: .approvalMode)) ?? nil)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userName, forKey: .userName)
        try container.encode(avatarInitials, forKey: .avatarInitials)
        try container.encode(hapticFeedbackEnabled, forKey: .hapticFeedbackEnabled)
        try container.encode(environment, forKey: .environment)
        try container.encode(relayConfiguration, forKey: .relayConfiguration)
        try container.encode(autoConnectOnLaunch, forKey: .autoConnectOnLaunch)
        try container.encode(locationSyncPreference, forKey: .locationSyncPreference)
        try container.encode(healthCollectionEnabled, forKey: .healthCollectionEnabled)
        try container.encode(locationCollectionEnabled, forKey: .locationCollectionEnabled)
        try container.encode(sensorStreamingEnabled, forKey: .sensorStreamingEnabled)
        try container.encode(motionCollectionEnabled, forKey: .motionCollectionEnabled)
        try container.encode(hermesAPIBaseURL, forKey: .hermesAPIBaseURL)
        try container.encode(modelsShimBaseURL, forKey: .modelsShimBaseURL)
        try container.encode(postVoiceTranscriptsToHermes, forKey: .postVoiceTranscriptsToHermes)
        try container.encode(readAloudAutoPlay, forKey: .readAloudAutoPlay)
        try container.encodeIfPresent(readAloudVoiceIdentifier, forKey: .readAloudVoiceIdentifier)
        try container.encode(readAloudRate, forKey: .readAloudRate)
        try container.encode(composerWritingToolsEnabled, forKey: .composerWritingToolsEnabled)
        try container.encode(appearanceTheme, forKey: .appearanceTheme)
        try container.encode(appearanceThemeMode, forKey: .appearanceThemeMode)
        try container.encode(appearanceAccent, forKey: .appearanceAccent)
        try container.encode(hudGlowIntensity, forKey: .hudGlowIntensity)
        try container.encode(gridDensity, forKey: .gridDensity)
        try container.encode(reduceMotion, forKey: .reduceMotion)
        try container.encode(verboseLogging, forKey: .verboseLogging)
        try container.encode(spotlightIndexingEnabled, forKey: .spotlightIndexingEnabled)
        try container.encode(showEmptySessions, forKey: .showEmptySessions)
        try container.encode(appLockEnabled, forKey: .appLockEnabled)
        try container.encode(appLockGracePeriod, forKey: .appLockGracePeriod)
        try container.encode(useRunsTransport, forKey: .useRunsTransport)
        try container.encode(approvalMode, forKey: .approvalMode)
    }

    var appLockConfiguration: AppLockConfiguration {
        AppLockConfiguration(isEnabled: appLockEnabled, gracePeriod: appLockGracePeriod)
    }

    func applyingEnvironmentPolicy(
        _ policy: AppEnvironmentPolicy = .currentBuild
    ) -> UserSettings {
        policy.sanitize(self)
    }

    /// The theme actually rendered: the manual pick, or the seasonal theme when
    /// automatic mode is on. `.manual` (the default) returns `appearanceTheme`
    /// unchanged, so default behavior — and the Deep Field byte-identical
    /// guarantee — is preserved.
    func effectiveAppearanceTheme(on date: Date = Date()) -> AppearanceTheme {
        switch appearanceThemeMode {
        case .manual: return appearanceTheme
        case .automatic: return ThemeCatalog.seasonalTheme(on: date)
        }
    }
}

enum AppEnvironment: String, Codable, CaseIterable, Hashable, Sendable {
    case production
    case staging
    case development

    var displayLabel: String {
        switch self {
        case .production: "Production"
        case .staging: "Staging"
        case .development: "Development"
        }
    }

    var baseURLString: String {
        switch self {
        case .production: ""  // Use custom relay URL from RelayConfiguration
        case .staging: ""     // Use custom relay URL from RelayConfiguration
        case .development: "http://127.0.0.1:8000/v1"
        }
    }
}
