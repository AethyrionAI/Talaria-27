import Foundation

@MainActor
protocol LocationServiceProtocol {
    var authorizationStatus: PermissionStatus { get }
    var authorizationLevel: LocationAuthorizationLevel { get }
    var accuracyLevel: LocationAccuracyLevel { get }
    func requestAuthorization() async -> PermissionStatus
    func refreshAuthorizationState()
    func openSystemSettings()
}
