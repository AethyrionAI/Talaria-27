import Foundation

@MainActor
protocol HealthServiceProtocol {
    var authorizationStatus: PermissionStatus { get }
    var backgroundDeliveryEnabled: Bool { get }
    func requestAuthorization() async -> PermissionStatus
    func refreshAuthorizationStatus() async
}
