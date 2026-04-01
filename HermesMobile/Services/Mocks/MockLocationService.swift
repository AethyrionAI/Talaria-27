import Foundation

@MainActor
@Observable
final class MockLocationService: LocationServiceProtocol {
    var authorizationStatus: PermissionStatus = .notDetermined
    var authorizationLevel: LocationAuthorizationLevel = .notDetermined
    var accuracyLevel: LocationAccuracyLevel = .full
    var syncPreference: LocationSyncPreference = .foregroundOnly

    func requestAuthorization() async -> PermissionStatus {
        try? await Task.sleep(for: .seconds(0.5))
        authorizationStatus = .authorizedWhenInUse
        authorizationLevel = .whenInUse
        return .authorizedWhenInUse
    }

    func requestBackgroundAuthorization() async -> PermissionStatus {
        try? await Task.sleep(for: .seconds(0.5))
        authorizationStatus = .authorizedAlways
        authorizationLevel = .always
        syncPreference = .backgroundAllowed
        return .authorizedAlways
    }

    func refreshAuthorizationState() {}

    func updateSyncPreference(_ preference: LocationSyncPreference) {
        syncPreference = preference
    }

    func openSystemSettings() {
        authorizationStatus = .authorizedAlways
        authorizationLevel = .always
    }
}
