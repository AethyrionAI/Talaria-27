import Foundation

@MainActor
protocol HealthServiceProtocol {
    var authorizationStatus: PermissionStatus { get }
    func requestAuthorization() async -> PermissionStatus
    func refreshAuthorizationStatus() async
}
