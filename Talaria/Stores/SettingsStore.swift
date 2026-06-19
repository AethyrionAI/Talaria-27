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
        let storedSettings = persistence.loadUserSettings() ?? DemoData.sampleUserSettings
        self.settings = storedSettings.applyingEnvironmentPolicy(environmentPolicy, buildConfiguration: buildConfiguration)
    }
}
