import Foundation

struct AppBuildConfiguration: Equatable, Sendable {
    let hostedRelayBaseURL: String?
    let hostedRelayEnabled: Bool
    let supportURL: URL?
    let termsOfServiceURL: URL?
    let privacyPolicyURL: URL?

    static func current(bundle: Bundle = .main) -> AppBuildConfiguration {
        let info = bundle.infoDictionary ?? [:]
        let hostedRelayBaseURL = RelayConfiguration.normalizeBaseURL(
            info["APP_HOSTED_RELAY_URL"] as? String
        )
        let hostedRelayEnabled = (info["APP_HOSTED_RELAY_ENABLED"] as? Bool) ?? false

        func urlValue(_ key: String) -> URL? {
            guard let raw = info[key] as? String, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return URL(string: raw)
        }

        return AppBuildConfiguration(
            hostedRelayBaseURL: hostedRelayBaseURL,
            hostedRelayEnabled: hostedRelayEnabled && hostedRelayBaseURL != nil,
            supportURL: urlValue("APP_SUPPORT_URL"),
            termsOfServiceURL: urlValue("APP_TERMS_URL"),
            privacyPolicyURL: urlValue("APP_PRIVACY_URL")
        )
    }
}

enum RelayMode: String, Codable, CaseIterable, Hashable, Sendable {
    case custom
    case hosted

    var displayLabel: String {
        switch self {
        case .custom: "Use My Relay"
        case .hosted: "Use Hosted Relay"
        }
    }
}

struct RelayConfiguration: Codable, Hashable, Sendable {
    var relayMode: RelayMode
    var customRelayBaseURL: String
    var hostedRelayBaseURL: String?
    var hostedRelayEnabled: Bool

    init(
        relayMode: RelayMode = .custom,
        customRelayBaseURL: String = "",
        hostedRelayBaseURL: String? = nil,
        hostedRelayEnabled: Bool = false
    ) {
        self.relayMode = relayMode
        self.customRelayBaseURL = RelayConfiguration.normalizeBaseURL(customRelayBaseURL) ?? customRelayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.hostedRelayBaseURL = RelayConfiguration.normalizeBaseURL(hostedRelayBaseURL)
        self.hostedRelayEnabled = hostedRelayEnabled && self.hostedRelayBaseURL != nil
        if relayMode == .hosted && !self.canUseHosted {
            self.relayMode = .custom
        }
    }

    static func defaultValue(
        buildConfiguration: AppBuildConfiguration = .current(),
        environmentPolicy: AppEnvironmentPolicy = .currentBuild
    ) -> RelayConfiguration {
        RelayConfiguration(
            relayMode: .custom,
            customRelayBaseURL: environmentPolicy.allowsEnvironmentOverrides ? AppEnvironment.development.baseURLString : "",
            hostedRelayBaseURL: buildConfiguration.hostedRelayBaseURL,
            hostedRelayEnabled: buildConfiguration.hostedRelayEnabled
        )
    }

    static func migratedLegacyValue(
        environment: AppEnvironment,
        buildConfiguration: AppBuildConfiguration = .current(),
        environmentPolicy: AppEnvironmentPolicy = .currentBuild
    ) -> RelayConfiguration {
        if environmentPolicy.allowsEnvironmentOverrides, environment != .production {
            return RelayConfiguration(
                relayMode: .custom,
                customRelayBaseURL: environment.baseURLString,
                hostedRelayBaseURL: buildConfiguration.hostedRelayBaseURL,
                hostedRelayEnabled: buildConfiguration.hostedRelayEnabled
            )
        }

        if buildConfiguration.hostedRelayEnabled, buildConfiguration.hostedRelayBaseURL != nil {
            return RelayConfiguration(
                relayMode: .hosted,
                customRelayBaseURL: "",
                hostedRelayBaseURL: buildConfiguration.hostedRelayBaseURL,
                hostedRelayEnabled: true
            )
        }

        return RelayConfiguration.defaultValue(
            buildConfiguration: buildConfiguration,
            environmentPolicy: environmentPolicy
        )
    }

    mutating func applyBuildConfiguration(_ buildConfiguration: AppBuildConfiguration) {
        hostedRelayBaseURL = buildConfiguration.hostedRelayBaseURL
        hostedRelayEnabled = buildConfiguration.hostedRelayEnabled && hostedRelayBaseURL != nil
        customRelayBaseURL = RelayConfiguration.normalizeBaseURL(customRelayBaseURL) ?? customRelayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if relayMode == .hosted && !canUseHosted {
            relayMode = .custom
        }
    }

    var canUseHosted: Bool {
        hostedRelayEnabled && hostedRelayBaseURL != nil
    }

    var activeBaseURLString: String? {
        switch relayMode {
        case .custom:
            return RelayConfiguration.normalizeBaseURL(customRelayBaseURL)
        case .hosted:
            guard canUseHosted else { return RelayConfiguration.normalizeBaseURL(customRelayBaseURL) }
            return hostedRelayBaseURL
        }
    }

    var relayOriginLabel: String {
        guard let baseURLString = activeBaseURLString, let url = URL(string: baseURLString) else {
            return "Not Configured"
        }
        return url.host ?? baseURLString
    }

    var validationMessage: String? {
        switch relayMode {
        case .custom:
            let trimmed = customRelayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "Enter your relay URL." }
            guard RelayConfiguration.normalizeBaseURL(trimmed) != nil else {
                return "Relay URL must be an absolute http(s) URL ending with /v1."
            }
            return nil
        case .hosted:
            return canUseHosted ? nil : "Hosted relay is not configured in this app build."
        }
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

    /// Display name — single source of truth is the catalog definition (#49).
    var displayLabel: String {
        ThemeCatalog.definition(id: rawValue)?.displayName ?? rawValue
    }

    /// Whether this is a light environment — drives the root
    /// `preferredColorScheme` so system chrome (keyboard, sheets, toggles)
    /// follows the theme. Resolved from the palette data (#49).
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
    var displayLabel: String { displayLabel(for: .deepField) }

    /// Contextual label for the slot as resolved inside a theme — read from
    /// the theme's accent-variant data (#49), so a new theme names its slots
    /// in its catalog entry instead of a switch arm here.
    func displayLabel(for theme: AppearanceTheme) -> String {
        ThemePaletteCatalog.definition(for: theme.themeID).accents[slot].displayName
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
    var notificationsEnabled: Bool
    var hapticFeedbackEnabled: Bool
    var environment: AppEnvironment
    var relayConfiguration: RelayConfiguration
    var autoConnectOnLaunch: Bool
    var locationSyncPreference: LocationSyncPreference
    // In-app permission revocation (#6): the app can't rescind an iOS grant,
    // so revoke = durably stop USING it. These gate SensorUploadService's
    // launch-time wiring so a revoke survives relaunch (start() would
    // otherwise re-assert health auth and restart monitoring every launch).
    var healthCollectionEnabled: Bool
    var locationCollectionEnabled: Bool
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

    init(
        userName: String = "User",
        avatarInitials: String = "U",
        notificationsEnabled: Bool = true,
        hapticFeedbackEnabled: Bool = true,
        environment: AppEnvironment = AppEnvironmentPolicy.currentBuild.defaultEnvironment,
        relayConfiguration: RelayConfiguration = RelayConfiguration.defaultValue(),
        autoConnectOnLaunch: Bool = true,
        locationSyncPreference: LocationSyncPreference = .foregroundOnly,
        healthCollectionEnabled: Bool = true,
        locationCollectionEnabled: Bool = true,
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
        spotlightIndexingEnabled: Bool = false
    ) {
        self.userName = userName
        self.avatarInitials = avatarInitials
        self.notificationsEnabled = notificationsEnabled
        self.hapticFeedbackEnabled = hapticFeedbackEnabled
        self.environment = environment
        self.relayConfiguration = relayConfiguration
        self.autoConnectOnLaunch = autoConnectOnLaunch
        self.locationSyncPreference = locationSyncPreference
        self.healthCollectionEnabled = healthCollectionEnabled
        self.locationCollectionEnabled = locationCollectionEnabled
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
    }

    private enum CodingKeys: String, CodingKey {
        case userName
        case avatarInitials
        case notificationsEnabled
        case hapticFeedbackEnabled
        case environment
        case relayConfiguration
        case autoConnectOnLaunch
        case locationSyncPreference
        case healthCollectionEnabled
        case locationCollectionEnabled
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
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userName = try container.decodeIfPresent(String.self, forKey: .userName) ?? "User"
        avatarInitials = try container.decodeIfPresent(String.self, forKey: .avatarInitials) ?? "U"
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        hapticFeedbackEnabled = try container.decodeIfPresent(Bool.self, forKey: .hapticFeedbackEnabled) ?? true
        environment = try container.decodeIfPresent(AppEnvironment.self, forKey: .environment) ?? AppEnvironmentPolicy.currentBuild.defaultEnvironment
        relayConfiguration = try container.decodeIfPresent(RelayConfiguration.self, forKey: .relayConfiguration)
            ?? RelayConfiguration.migratedLegacyValue(environment: environment)
        autoConnectOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .autoConnectOnLaunch) ?? true
        locationSyncPreference = try container.decodeIfPresent(LocationSyncPreference.self, forKey: .locationSyncPreference) ?? .foregroundOnly
        healthCollectionEnabled = try container.decodeIfPresent(Bool.self, forKey: .healthCollectionEnabled) ?? true
        locationCollectionEnabled = try container.decodeIfPresent(Bool.self, forKey: .locationCollectionEnabled) ?? true
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
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userName, forKey: .userName)
        try container.encode(avatarInitials, forKey: .avatarInitials)
        try container.encode(notificationsEnabled, forKey: .notificationsEnabled)
        try container.encode(hapticFeedbackEnabled, forKey: .hapticFeedbackEnabled)
        try container.encode(environment, forKey: .environment)
        try container.encode(relayConfiguration, forKey: .relayConfiguration)
        try container.encode(autoConnectOnLaunch, forKey: .autoConnectOnLaunch)
        try container.encode(locationSyncPreference, forKey: .locationSyncPreference)
        try container.encode(healthCollectionEnabled, forKey: .healthCollectionEnabled)
        try container.encode(locationCollectionEnabled, forKey: .locationCollectionEnabled)
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
    }

    func applyingEnvironmentPolicy(
        _ policy: AppEnvironmentPolicy = .currentBuild,
        buildConfiguration: AppBuildConfiguration = .current()
    ) -> UserSettings {
        var sanitized = policy.sanitize(self)
        sanitized.relayConfiguration.applyBuildConfiguration(buildConfiguration)
        if sanitized.relayConfiguration.relayMode == .hosted, !sanitized.relayConfiguration.canUseHosted {
            sanitized.relayConfiguration.relayMode = .custom
        }
        return sanitized
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
