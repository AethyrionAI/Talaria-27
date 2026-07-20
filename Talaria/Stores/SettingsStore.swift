import Foundation

@MainActor
@Observable
final class SettingsStore {
    var settings: UserSettings {
        didSet {
            persistence.saveUserSettings(settings)
            if oldValue.environment != settings.environment {
                Task { await onEnvironmentChanged?(settings.environment) }
            }
            if oldValue.relayConfiguration != settings.relayConfiguration {
                Task { await onRelayConfigurationChanged?(settings.relayConfiguration) }
            }
        }
    }

    var onEnvironmentChanged: (@MainActor (AppEnvironment) async -> Void)?
    var onRelayConfigurationChanged: (@MainActor (RelayConfiguration) async -> Void)?
    var availableEnvironments: [AppEnvironment] {
        environmentPolicy.availableEnvironments
    }
    let buildConfiguration: AppBuildConfiguration
    /// Whether construction found a stored settings blob (#137): the
    /// grandfathering migration needs to tell real #6 revoke decisions apart
    /// from the fresh-install defaults, which are opt-out post-#137.
    let hadPersistedSettings: Bool

    private let persistence: any AppPersistenceStoreProtocol
    private let environmentPolicy: AppEnvironmentPolicy

    init(
        persistence: any AppPersistenceStoreProtocol,
        environmentPolicy: AppEnvironmentPolicy = .currentBuild,
        buildConfiguration: AppBuildConfiguration = .current()
    ) {
        self.persistence = persistence
        self.environmentPolicy = environmentPolicy
        self.buildConfiguration = buildConfiguration
        let stored = persistence.loadUserSettings()
        self.hadPersistedSettings = stored != nil
        let storedSettings = stored ?? DemoData.sampleUserSettings
        self.settings = storedSettings.applyingEnvironmentPolicy(environmentPolicy)
    }
}
