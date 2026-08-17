import CoreLocation
import UIKit

/// CoreLocation AUTHORIZATION surface for `PermissionsStore` and the Privacy
/// screen. #352 deleted the capture half (monitoring sessions, background
/// activity, single-shot fixes, the sync preference) with the sensor-upload
/// pipeline — query-time reads live in the belt's shared
/// `DeviceLocationProvider` (#242), which owns its own `CLLocationManager`.
@MainActor
@Observable
final class LiveLocationService: NSObject, LocationServiceProtocol, CLLocationManagerDelegate {
    private(set) var authorizationStatus: PermissionStatus = .notDetermined
    private(set) var authorizationLevel: LocationAuthorizationLevel = .notDetermined
    private(set) var accuracyLevel: LocationAccuracyLevel = .unknown

    private let manager = CLLocationManager()
    private var authContinuation: CheckedContinuation<PermissionStatus, Never>?
    private var authTimeoutTask: Task<Void, Never>?
    /// Held only while an authorization request is pending — creating the
    /// session is what raises the system prompt.
    private var serviceSession: CLServiceSession?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        refreshAuthorizationState()
    }

    func requestAuthorization() async -> PermissionStatus {
        if authorizationLevel == .whenInUse || authorizationLevel == .always {
            return authorizationStatus
        }

        return await awaitAuthorizationChange { [self] in
            self.serviceSession = CLServiceSession(authorization: .whenInUse)
        }
    }

    func refreshAuthorizationState() {
        let currentStatus = manager.authorizationStatus
        authorizationLevel = mapAuthorizationLevel(currentStatus)
        authorizationStatus = mapPermissionStatus(currentStatus)
        accuracyLevel = mapAccuracy(manager.accuracyAuthorization)
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            refreshAuthorizationState()
            resumeAuthorizationContinuationIfNeeded()
        }
    }

    // MARK: - Authorization

    private func awaitAuthorizationChange(trigger: @escaping @MainActor () -> Void) async -> PermissionStatus {
        refreshAuthorizationState()
        authTimeoutTask?.cancel()
        return await withCheckedContinuation { continuation in
            authContinuation = continuation
            trigger()
            authTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                await MainActor.run {
                    self?.resumeAuthorizationContinuationIfNeeded()
                }
            }
        }
    }

    private func resumeAuthorizationContinuationIfNeeded() {
        authTimeoutTask?.cancel()
        authTimeoutTask = nil

        guard let authContinuation else { return }
        self.authContinuation = nil
        authContinuation.resume(returning: authorizationStatus)
    }

    private func mapPermissionStatus(_ status: CLAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .authorizedWhenInUse: .authorizedWhenInUse
        case .authorizedAlways: .authorizedAlways
        @unknown default: .notDetermined
        }
    }

    private func mapAuthorizationLevel(_ status: CLAuthorizationStatus) -> LocationAuthorizationLevel {
        switch status {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .authorizedWhenInUse: .whenInUse
        case .authorizedAlways: .always
        @unknown default: .notDetermined
        }
    }

    private func mapAccuracy(_ accuracy: CLAccuracyAuthorization) -> LocationAccuracyLevel {
        switch accuracy {
        case .fullAccuracy: .full
        case .reducedAccuracy: .reduced
        @unknown default: .unknown
        }
    }
}
