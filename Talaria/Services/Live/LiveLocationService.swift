import CoreLocation
import UIKit

struct LocationUpdate: Sendable {
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    let accuracy: Double
    let timestamp: Date
}

@MainActor
@Observable
final class LiveLocationService: NSObject, LocationServiceProtocol, CLLocationManagerDelegate {
    private(set) var authorizationStatus: PermissionStatus = .notDetermined
    private(set) var authorizationLevel: LocationAuthorizationLevel = .notDetermined
    private(set) var accuracyLevel: LocationAccuracyLevel = .unknown
    private(set) var lastLocation: LocationUpdate?
    private(set) var syncPreference: LocationSyncPreference = .foregroundOnly

    var onLocationUpdate: (@MainActor (LocationUpdate) -> Void)?

    private let manager = CLLocationManager()
    private var authContinuation: CheckedContinuation<PermissionStatus, Never>?
    private var authTimeoutTask: Task<Void, Never>?
    private var isMonitoring = false
    private var lastEmittedLocation: LocationUpdate?
    private var serviceSession: CLServiceSession?
    private var backgroundSession: CLBackgroundActivitySession?
    private var liveUpdatesTask: Task<Void, Never>?

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

    func requestBackgroundAuthorization() async -> PermissionStatus {
        syncPreference = .backgroundAllowed

        // If already authorized at any level, just reconfigure monitoring
        // to enable the background activity session.
        if authorizationLevel == .always || authorizationLevel == .whenInUse {
            configureMonitoringSessions()
            return authorizationStatus
        }

        // Not yet authorized — request When In Use first. Per iOS 26 guidance,
        // CLBackgroundActivitySession works with When In Use authorization
        // (shows blue indicator bar). Always authorization can be requested
        // later as a separate upgrade if the user wants to hide the bar.
        let status = await awaitAuthorizationChange { [self] in
            self.serviceSession = CLServiceSession(authorization: .whenInUse)
        }
        configureMonitoringSessions()
        return status
    }

    func refreshAuthorizationState() {
        let currentStatus = manager.authorizationStatus
        authorizationLevel = mapAuthorizationLevel(currentStatus)
        authorizationStatus = mapPermissionStatus(currentStatus)
        accuracyLevel = mapAccuracy(manager.accuracyAuthorization)
    }

    func updateSyncPreference(_ preference: LocationSyncPreference) {
        syncPreference = preference
        configureMonitoringSessions()
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func startMonitoring() {
        guard !isMonitoring else {
            configureMonitoringSessions()
            return
        }

        isMonitoring = true
        configureMonitoringSessions()
    }

    func stopMonitoring() {
        isMonitoring = false
        authTimeoutTask?.cancel()
        authTimeoutTask = nil
        authContinuation = nil
        liveUpdatesTask?.cancel()
        liveUpdatesTask = nil
        backgroundSession?.invalidate()
        backgroundSession = nil
        serviceSession?.invalidate()
        serviceSession = nil
        manager.stopUpdatingLocation()
    }

    func requestSingleLocation() {
        guard authorizationLevel == .whenInUse || authorizationLevel == .always else { return }
        manager.requestLocation()
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            refreshAuthorizationState()
            resumeAuthorizationContinuationIfNeeded()
            if isMonitoring {
                configureMonitoringSessions()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            emitLocation(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitude: location.altitude,
                accuracy: location.horizontalAccuracy,
                timestamp: location.timestamp
            )
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Foreground one-shot location requests may fail indoors or without a fix.
    }

    // MARK: - Monitoring

    private func configureMonitoringSessions() {
        guard isMonitoring else { return }

        liveUpdatesTask?.cancel()
        liveUpdatesTask = nil

        backgroundSession?.invalidate()
        backgroundSession = nil

        serviceSession?.invalidate()
        serviceSession = nil

        refreshAuthorizationState()

        switch syncPreference {
        case .foregroundOnly:
            if authorizationLevel == .whenInUse || authorizationLevel == .always {
                serviceSession = CLServiceSession(authorization: .whenInUse)
            }
        case .backgroundAllowed:
            // iOS 26: CLBackgroundActivitySession works with both While In Use
            // and Always authorization. With While In Use, the blue location
            // indicator bar is shown. With Always, no indicator is needed.
            if authorizationLevel == .always {
                serviceSession = CLServiceSession(authorization: .always)
                backgroundSession = CLBackgroundActivitySession()
                startLiveUpdatesIfNeeded()
            } else if authorizationLevel == .whenInUse {
                serviceSession = CLServiceSession(authorization: .whenInUse)
                backgroundSession = CLBackgroundActivitySession()
                startLiveUpdatesIfNeeded()
            }
        }
    }

    private func startLiveUpdatesIfNeeded() {
        guard liveUpdatesTask == nil else { return }

        liveUpdatesTask = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates() {
                    guard let self else { return }
                    guard let location = update.location else { continue }
                    await MainActor.run {
                        self.refreshAuthorizationState()
                        self.emitLocation(
                            latitude: location.coordinate.latitude,
                            longitude: location.coordinate.longitude,
                            altitude: location.altitude,
                            accuracy: location.horizontalAccuracy,
                            timestamp: location.timestamp
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    self?.liveUpdatesTask = nil
                }
            }
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

    // MARK: - Updates

    private func emitLocation(
        latitude: Double,
        longitude: Double,
        altitude: Double?,
        accuracy: Double,
        timestamp: Date
    ) {
        guard shouldEmit(latitude: latitude, longitude: longitude, timestamp: timestamp) else { return }
        let update = LocationUpdate(
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            accuracy: accuracy,
            timestamp: timestamp
        )
        lastEmittedLocation = update
        lastLocation = update
        onLocationUpdate?(update)
    }

    private func shouldEmit(latitude: Double, longitude: Double, timestamp: Date) -> Bool {
        guard let previous = lastEmittedLocation else { return true }
        let secondsSincePrevious = abs(timestamp.timeIntervalSince(previous.timestamp))
        let previousLocation = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
        let nextLocation = CLLocation(latitude: latitude, longitude: longitude)
        let distanceFromPrevious = nextLocation.distance(from: previousLocation)
        if secondsSincePrevious < 60, distanceFromPrevious < 25 {
            return false
        }
        return true
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
