import Foundation

@MainActor
@Observable
final class MockHealthService: HealthServiceProtocol {
    var authorizationStatus: PermissionStatus = .notDetermined

    func requestAuthorization() async -> PermissionStatus {
        try? await Task.sleep(for: .seconds(0.5))
        authorizationStatus = .authorized
        return .authorized
    }

    func refreshAuthorizationStatus() async {}
}
