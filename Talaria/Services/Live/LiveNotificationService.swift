import Foundation
import UserNotifications

@MainActor
@Observable
final class LiveNotificationService: NotificationServiceProtocol {
    private(set) var authorizationStatus: PermissionStatus = .notDetermined
    private(set) var currentPushToken: String?
    private(set) var isPushTokenRegistered: Bool = false

    private let center = UNUserNotificationCenter.current()

    init() {
        Task { await refreshAuthorizationStatus() }
    }

    func requestAuthorization() async -> PermissionStatus {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            authorizationStatus = granted ? .authorized : .denied
        } catch {
            authorizationStatus = .denied
        }
        return authorizationStatus
    }

    func updatePushToken(_ token: String?) async {
        currentPushToken = token
    }

    func markPushTokenRegistered(_ registered: Bool) async {
        isPushTokenRegistered = registered
    }

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = mapStatus(settings.authorizationStatus)
    }

    private func mapStatus(_ status: UNAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized: .authorized
        case .provisional: .limited
        case .ephemeral: .limited
        @unknown default: .notDetermined
        }
    }
}
