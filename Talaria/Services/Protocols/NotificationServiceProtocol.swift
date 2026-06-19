import Foundation

@MainActor
protocol NotificationServiceProtocol {
    var authorizationStatus: PermissionStatus { get }
    var currentPushToken: String? { get }
    var isPushTokenRegistered: Bool { get }
    func requestAuthorization() async -> PermissionStatus
    func refreshAuthorizationStatus() async
    func updatePushToken(_ token: String?) async
    func markPushTokenRegistered(_ registered: Bool) async
}
