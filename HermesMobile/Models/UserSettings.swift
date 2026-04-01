import Foundation

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

struct UserSettings: Codable, Hashable, Sendable {
    var userName: String
    var avatarInitials: String
    var notificationsEnabled: Bool
    var hapticFeedbackEnabled: Bool
    var environment: AppEnvironment
    var autoConnectOnLaunch: Bool
    var locationSyncPreference: LocationSyncPreference

    init(
        userName: String = "User",
        avatarInitials: String = "U",
        notificationsEnabled: Bool = true,
        hapticFeedbackEnabled: Bool = true,
        environment: AppEnvironment = AppEnvironmentPolicy.currentBuild.defaultEnvironment,
        autoConnectOnLaunch: Bool = true,
        locationSyncPreference: LocationSyncPreference = .foregroundOnly
    ) {
        self.userName = userName
        self.avatarInitials = avatarInitials
        self.notificationsEnabled = notificationsEnabled
        self.hapticFeedbackEnabled = hapticFeedbackEnabled
        self.environment = environment
        self.autoConnectOnLaunch = autoConnectOnLaunch
        self.locationSyncPreference = locationSyncPreference
    }

    func applyingEnvironmentPolicy(_ policy: AppEnvironmentPolicy = .currentBuild) -> UserSettings {
        policy.sanitize(self)
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
        case .production: "https://hermes-mobile-relay-dylan.fly.dev/v1"
        case .staging: "https://staging.relay.example.com/v1"
        case .development: "http://127.0.0.1:8000/v1"
        }
    }
}
