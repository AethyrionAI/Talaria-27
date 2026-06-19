import Foundation

@MainActor
@Observable
final class MockNotificationService: NotificationServiceProtocol {
    var authorizationStatus: PermissionStatus = .notDetermined
    var currentPushToken: String?
    var isPushTokenRegistered: Bool = false

    func requestAuthorization() async -> PermissionStatus {
        try? await Task.sleep(for: .seconds(0.5))
        authorizationStatus = .authorized
        return .authorized
    }

    func refreshAuthorizationStatus() async {}

    func updatePushToken(_ token: String?) async {
        currentPushToken = token
    }

    func markPushTokenRegistered(_ registered: Bool) async {
        isPushTokenRegistered = registered
    }
}
