import CoreMotion
import Foundation

/// CoreMotion AUTHORIZATION surface for `PermissionsStore` and the Privacy
/// screen. #352 deleted the activity-monitoring half with the sensor-upload
/// pipeline — query-time motion reads live in `MotionTool` (its own
/// `CMPedometer` / `CMMotionActivityManager` per read).
@MainActor
@Observable
final class LiveMotionService {
    private(set) var authorizationStatus: PermissionStatus = .notDetermined

    private let activityManager = CMMotionActivityManager()

    init() {
        refreshAuthorizationStatus()
    }

    // MARK: - Authorization

    /// Seeds `authorizationStatus` from the system's persisted CoreMotion grant.
    /// Unlike HealthKit reads, `CMMotionActivityManager.authorizationStatus()` reflects
    /// the real grant across process launches, so re-reading it on launch fixes the
    /// cold-start "off" display (#39) without re-presenting the permission prompt.
    func refreshAuthorizationStatus() {
        guard CMMotionActivityManager.isActivityAvailable() else {
            authorizationStatus = .unsupported
            return
        }
        authorizationStatus = Self.mapStatus(CMMotionActivityManager.authorizationStatus())
    }

    private static func mapStatus(_ status: CMAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized:    return .authorized
        case .denied:        return .denied
        case .restricted:    return .restricted
        case .notDetermined: return .notDetermined
        @unknown default:    return .notDetermined
        }
    }

    func requestAuthorization() async -> PermissionStatus {
        guard CMMotionActivityManager.isActivityAvailable() else {
            authorizationStatus = .unsupported
            return .unsupported
        }

        // CoreMotion doesn't have a separate authorization request —
        // permission is prompted on first data access. Trigger a query
        // to force the prompt.
        let status = CMMotionActivityManager.authorizationStatus()
        switch status {
        case .authorized:
            authorizationStatus = .authorized
        case .denied:
            authorizationStatus = .denied
        case .restricted:
            authorizationStatus = .restricted
        case .notDetermined:
            // Query historical data to trigger the permission dialog
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                activityManager.queryActivityStarting(
                    from: Date().addingTimeInterval(-60),
                    to: Date(),
                    to: OperationQueue.main
                ) { _, _ in
                    continuation.resume()
                }
            }
            // Re-check after the dialog
            let newStatus = CMMotionActivityManager.authorizationStatus()
            authorizationStatus = newStatus == .authorized ? .authorized : .denied
        @unknown default:
            authorizationStatus = .notDetermined
        }

        return authorizationStatus
    }
}
