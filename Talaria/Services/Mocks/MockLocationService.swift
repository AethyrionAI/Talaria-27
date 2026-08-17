import Foundation

@MainActor
@Observable
final class MockLocationService: LocationServiceProtocol {
    var authorizationStatus: PermissionStatus = .notDetermined
    var authorizationLevel: LocationAuthorizationLevel = .notDetermined
    var accuracyLevel: LocationAccuracyLevel = .full

    func requestAuthorization() async -> PermissionStatus {
        try? await Task.sleep(for: .seconds(0.5))
        authorizationStatus = .authorizedWhenInUse
        authorizationLevel = .whenInUse
        return .authorizedWhenInUse
    }

    func refreshAuthorizationState() {}

    func openSystemSettings() {
        authorizationStatus = .authorizedAlways
        authorizationLevel = .always
    }
}
