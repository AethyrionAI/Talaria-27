import Foundation

@MainActor
@Observable
final class PermissionsStore {
    var capabilities: [DeviceCapability] = []

    private let locationService: any LocationServiceProtocol
    private let healthService: any HealthServiceProtocol
    private let notificationService: any NotificationServiceProtocol
    private let mediaService: any MediaServiceProtocol

    init(
        locationService: any LocationServiceProtocol,
        healthService: any HealthServiceProtocol,
        notificationService: any NotificationServiceProtocol,
        mediaService: any MediaServiceProtocol
    ) {
        self.locationService = locationService
        self.healthService = healthService
        self.notificationService = notificationService
        self.mediaService = mediaService
        self.capabilities = currentCapabilities()
    }

    func reloadCapabilities() async {
        locationService.refreshAuthorizationState()
        capabilities = currentCapabilities()
    }

    func requestPermission(for type: PermissionType) async {
        switch type {
        case .location:
            _ = await locationService.requestAuthorization()
        case .health:
            _ = await healthService.requestAuthorization()
        case .notifications:
            _ = await notificationService.requestAuthorization()
        case .camera:
            _ = await mediaService.requestCameraAuthorization()
        case .photos:
            _ = await mediaService.requestPhotosAuthorization()
        }

        capabilities = currentCapabilities()
    }

    var locationAuthorizationLevel: LocationAuthorizationLevel {
        locationService.authorizationLevel
    }

    var locationAccuracyLevel: LocationAccuracyLevel {
        locationService.accuracyLevel
    }

    var healthBackgroundDeliveryEnabled: Bool {
        healthService.backgroundDeliveryEnabled
    }

    func requestBackgroundLocationAccess() async {
        _ = await locationService.requestBackgroundAuthorization()
        capabilities = currentCapabilities()
    }

    func updateLocationSyncPreference(_ preference: LocationSyncPreference) {
        locationService.updateSyncPreference(preference)
        capabilities = currentCapabilities()
    }

    func openLocationSystemSettings() {
        locationService.openSystemSettings()
    }

    private func currentCapabilities() -> [DeviceCapability] {
        [
            DeviceCapability(
                permissionType: .location,
                status: locationService.authorizationStatus,
                statusDetail: locationStatusDetail()
            ),
            DeviceCapability(
                permissionType: .health,
                status: healthService.authorizationStatus,
                statusDetail: healthStatusDetail()
            ),
            DeviceCapability(permissionType: .notifications, status: notificationService.authorizationStatus),
            DeviceCapability(permissionType: .camera, status: mediaService.cameraAuthorizationStatus),
            DeviceCapability(permissionType: .photos, status: mediaService.photosAuthorizationStatus),
        ]
    }

    private func locationStatusDetail() -> String? {
        switch locationService.authorizationLevel {
        case .whenInUse, .always:
            return "\(locationService.authorizationLevel.displayLabel) • \(locationService.accuracyLevel.displayLabel)"
        case .notDetermined, .denied, .restricted:
            return nil
        }
    }

    private func healthStatusDetail() -> String? {
        guard healthService.authorizationStatus == .authorized else { return nil }
        let backgroundStatus = healthService.backgroundDeliveryEnabled ? "Background Sync On" : "Background Sync Off"
        return "Read Only • \(backgroundStatus)"
    }
}
