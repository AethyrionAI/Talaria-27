import Foundation
import HealthKit

/// HealthKit AUTHORIZATION surface for `PermissionsStore` and the Privacy
/// screen. #352 deleted the capture half (observer queries, anchored change
/// tracking, snapshot collection, background delivery) with the sensor-upload
/// pipeline — query-time reads live in `DeviceHealthTool` (its own
/// `HKHealthStore` per read), and the widget queries HealthKit directly via
/// `HealthQueryCore`.
@MainActor
@Observable
final class LiveHealthService: HealthServiceProtocol {
    private(set) var authorizationStatus: PermissionStatus

    private let store: HKHealthStore?

    /// The read set the app actually uses since #352: the four query-time /
    /// widget metrics. Mirrors `DeviceHealthTool.readTypes` — the permission
    /// sheet should name exactly what a query can reach, nothing more.
    private static let readTypes: Set<HKObjectType> = {
        var types: Set<HKObjectType> = [HKCategoryType(.sleepAnalysis)]
        types.insert(HKQuantityType(.stepCount))
        types.insert(HKQuantityType(.activeEnergyBurned))
        types.insert(HKQuantityType(.heartRate))
        return types
    }()

    init() {
        guard HKHealthStore.isHealthDataAvailable() else {
            self.store = nil
            self.authorizationStatus = .unsupported
            return
        }
        self.store = HKHealthStore()
        self.authorizationStatus = .notDetermined
    }

    func requestAuthorization() async -> PermissionStatus {
        guard let store else {
            authorizationStatus = .unsupported
            return .unsupported
        }

        do {
            try await store.requestAuthorization(toShare: [], read: Self.readTypes)
            authorizationStatus = .authorized
        } catch {
            authorizationStatus = .denied
        }

        return authorizationStatus
    }

    func refreshAuthorizationStatus() async {
        guard let store else {
            authorizationStatus = .unsupported
            return
        }

        // Apple's privacy model: authorizationStatus(for:) only works for
        // write (share) access. For read access, the system always returns
        // .notDetermined to prevent apps from learning what the user denied.
        // If requestAuthorization was previously called, we trust that result.
        // See: https://developer.apple.com/documentation/healthkit/hkhealthstore/authorizationstatus(for:)
        let requestStatus = store.authorizationStatus(for: HKQuantityType(.stepCount))
        if requestStatus == .sharingDenied {
            // User explicitly denied write access — implies they saw the prompt
            // but we only care about read. Check if we got data previously.
            authorizationStatus = authorizationStatus == .authorized ? .authorized : .notDetermined
        } else {
            // If we previously got authorized via requestAuthorization, keep it.
            // Otherwise stay at current state — we can't distinguish denied from not-asked for read.
            if authorizationStatus != .authorized {
                authorizationStatus = .notDetermined
            }
        }
    }
}
