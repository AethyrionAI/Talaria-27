import Foundation

@MainActor
@Observable
final class MockHealthService: HealthServiceProtocol {
    var authorizationStatus: PermissionStatus = .notDetermined
    var backgroundDeliveryEnabled = false

    func requestAuthorization() async -> PermissionStatus {
        try? await Task.sleep(for: .seconds(0.5))
        authorizationStatus = .authorized
        backgroundDeliveryEnabled = true
        return .authorized
    }

    func refreshAuthorizationStatus() async {}
}
