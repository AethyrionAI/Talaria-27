import CoreMotion
import Foundation

/// Activity classification codes matching the sensor pipeline format.
/// These are sent as health metrics with unit "activity_code".
enum ActivityCode: Int, Sendable {
    case stationary = 0
    case walking = 1
    case running = 2
    case automotive = 3
    case cycling = 4
    case unknown = 5

    var label: String {
        switch self {
        case .stationary: "stationary"
        case .walking:    "walking"
        case .running:    "running"
        case .automotive: "automotive"
        case .cycling:    "cycling"
        case .unknown:    "unknown"
        }
    }

    static func from(_ activity: CMMotionActivity) -> ActivityCode {
        if activity.automotive { return .automotive }
        if activity.cycling    { return .cycling }
        if activity.running    { return .running }
        if activity.walking    { return .walking }
        if activity.stationary { return .stationary }
        return .unknown
    }
}

/// Monitors device motion activity via CoreMotion and reports changes
/// through the sensor pipeline as health metrics.
@MainActor
@Observable
final class LiveMotionService {
    private(set) var currentActivity: ActivityCode = .unknown
    private(set) var authorizationStatus: PermissionStatus = .notDetermined

    var onActivityUpdate: (@MainActor (ActivityCode) -> Void)?

    private let activityManager = CMMotionActivityManager()
    private var isMonitoring = false

    // MARK: - Authorization

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

    // MARK: - Monitoring

    func startMonitoring() {
        guard !isMonitoring,
              CMMotionActivityManager.isActivityAvailable(),
              CMMotionActivityManager.authorizationStatus() == .authorized else { return }

        isMonitoring = true
        activityManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self, let activity else { return }
            Task { @MainActor in
                let code = ActivityCode.from(activity)
                if code != self.currentActivity {
                    self.currentActivity = code
                    self.onActivityUpdate?(code)
                }
            }
        }
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        activityManager.stopActivityUpdates()
        isMonitoring = false
    }
}
