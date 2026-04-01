import Foundation

@MainActor
protocol LocationServiceProtocol {
    var authorizationStatus: PermissionStatus { get }
    var authorizationLevel: LocationAuthorizationLevel { get }
    var accuracyLevel: LocationAccuracyLevel { get }
    var syncPreference: LocationSyncPreference { get }
    func requestAuthorization() async -> PermissionStatus
    func requestBackgroundAuthorization() async -> PermissionStatus
    func refreshAuthorizationState()
    func updateSyncPreference(_ preference: LocationSyncPreference)
    func openSystemSettings()
}
