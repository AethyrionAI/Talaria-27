import CoreLocation
import Foundation
@preconcurrency import MapKit
import os

private let sensorLog = Logger(subsystem: "org.aethyrion.talaria", category: "SensorUpload")

struct SensorOutboxState: Codable, Hashable, Sendable {
    struct PendingLocation: Codable, Hashable, Sendable {
        let latitude: Double
        let longitude: Double
        let altitude: Double?
        let accuracy: Double
        let recordedAt: Date
    }

    struct PendingHealthSample: Codable, Hashable, Sendable {
        let metric: String
        let value: Double
        let unit: String
        let startAt: Date
        let endAt: Date?

        private static let windowedMetrics: Set<String> = [
            "steps",
            "active_calories",
            "distance_walking",
            "workout_minutes",
            "stand_hours",
            "sleep_duration",
        ]

        var dedupeKey: String {
            if Self.windowedMetrics.contains(metric) {
                return "\(metric)|\(unit)|\(startAt.timeIntervalSince1970)"
            }

            return [
                metric,
                unit,
                String(startAt.timeIntervalSince1970),
                String(endAt?.timeIntervalSince1970 ?? 0)
            ].joined(separator: "|")
        }
    }

    var pendingLocation: PendingLocation?
    var pendingHealthSamples: [PendingHealthSample] = []

    var isEmpty: Bool {
        pendingLocation == nil && pendingHealthSamples.isEmpty
    }

    mutating func enqueue(location update: LocationUpdate) {
        pendingLocation = PendingLocation(
            latitude: update.latitude,
            longitude: update.longitude,
            altitude: update.altitude,
            accuracy: update.accuracy,
            recordedAt: update.timestamp
        )
    }

    mutating func enqueue(healthSamples: [HealthSnapshot.Sample]) {
        for sample in healthSamples {
            let pending = PendingHealthSample(
                metric: sample.metric,
                value: sample.value,
                unit: sample.unit,
                startAt: sample.startAt,
                endAt: sample.endAt
            )
            if let index = pendingHealthSamples.firstIndex(where: { $0.dedupeKey == pending.dedupeKey }) {
                pendingHealthSamples[index] = pending
            } else {
                pendingHealthSamples.append(pending)
            }
        }
    }
}

/// Coordinates durable sensor uploads from the phone to the relay.
///
/// The relay only ACKs a sample once the connector has received and stored it,
/// so sensor state is persisted locally until a real delivery succeeds.
@MainActor
@Observable
final class SensorUploadService {
    private struct SensorLocationBody: Encodable {
        let latitude: Double
        let longitude: Double
        let altitude: Double?
        let accuracy: Double
        let address: String?
        let recordedAt: String
    }

    private struct SensorHealthBody: Encodable {
        struct Sample: Encodable {
            let metric: String
            let value: Double
            let unit: String
            let startAt: String
            let endAt: String?
        }

        let samples: [Sample]
    }

    private struct DeliveryResult: Decodable {
        let deliveryState: String

        var wasDelivered: Bool {
            deliveryState == "delivered"
        }
    }

    private let apiClient: RelayAPIClient
    private let accessTokenProvider: @MainActor () async -> String?
    private let accessTokenRefresher: @MainActor () async -> String?
    private let persistence: AppPersistenceStoreProtocol
    private let isPairedProvider: @MainActor () -> Bool
    private let locationService: LiveLocationService
    private let healthService: LiveHealthService
    private let motionService: LiveMotionService?

    private var isActive = false
    private var isDraining = false
    private var outboxState: SensorOutboxState

    private let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    init(
        apiClient: RelayAPIClient,
        accessTokenProvider: @escaping @MainActor () async -> String?,
        accessTokenRefresher: @escaping @MainActor () async -> String? = { nil },
        persistence: AppPersistenceStoreProtocol,
        isPairedProvider: @escaping @MainActor () -> Bool,
        locationService: LiveLocationService,
        healthService: LiveHealthService,
        motionService: LiveMotionService? = nil
    ) {
        self.apiClient = apiClient
        self.accessTokenProvider = accessTokenProvider
        self.accessTokenRefresher = accessTokenRefresher
        self.persistence = persistence
        self.isPairedProvider = isPairedProvider
        self.locationService = locationService
        self.healthService = healthService
        self.motionService = motionService
        self.outboxState = persistence.loadSensorOutboxState()
    }

    func start() {
        guard !isActive else {
            sensorLog.notice("start() skipped — already active")
            return
        }
        isActive = true
        outboxState = persistence.loadSensorOutboxState()
        sensorLog.notice("start() — activating sensor pipeline. Outbox: loc=\(self.outboxState.pendingLocation != nil), health=\(self.outboxState.pendingHealthSamples.count)")

        locationService.onLocationUpdate = { [weak self] update in
            guard let self else { return }
            Task { @MainActor in
                sensorLog.notice("📍 location update: (\(update.latitude), \(update.longitude)) accuracy=\(update.accuracy)")
                self.outboxState.enqueue(location: update)
                self.persistOutboxState()
                await self.drainOutboxIfPossible()
            }
        }

        healthService.onHealthUpdate = { [weak self] changedIdentifiers in
            guard let self else { return }
            Task { @MainActor in
                sensorLog.notice("💓 health update for: \(changedIdentifiers.joined(separator: ", "), privacy: .public)")
                await self.captureHealthSnapshot(changedIdentifiers: changedIdentifiers)
            }
        }

        motionService?.onActivityUpdate = { [weak self] activityCode in
            guard let self else { return }
            Task { @MainActor in
                sensorLog.notice("🏃 activity update: code=\(activityCode.rawValue)")
                let now = Date()
                let sample = HealthSnapshot.Sample(
                    metric: "user_activity",
                    value: Double(activityCode.rawValue),
                    unit: "activity_code",
                    startAt: now,
                    endAt: nil
                )
                self.outboxState.enqueue(healthSamples: [sample])
                self.persistOutboxState()
                await self.drainOutboxIfPossible()
            }
        }

        locationService.startMonitoring()
        motionService?.startMonitoring()

        // Health authorization is in-memory only: LiveHealthService resets it to
        // .notDetermined on every launch, and Apple's read-privacy model means it
        // cannot be recovered via authorizationStatus(for:) (read status stays hidden).
        // collectSnapshot() hard-gates on .authorized, so without re-asserting here,
        // every snapshot returns nil after a relaunch even when the user already
        // granted access. Re-request on each start() to restore .authorized AND
        // re-enable background delivery. For read-only types iOS shows the system
        // sheet at most once per install, so repeat calls after the first decision
        // are silent — no nagging, even on denial.
        Task { [weak self] in
            guard let self else { return }
            let status = await self.healthService.requestAuthorization()
            self.healthService.startMonitoring()
            sensorLog.notice("start() — health auth re-asserted: \(String(describing: status), privacy: .public)")
            await self.captureHealthSnapshot(forceFullRefresh: true)
        }

        sensorLog.notice("start() — monitoring started (loc/motion; health pending re-auth). loc auth=\(String(describing: self.locationService.authorizationStatus), privacy: .public)")
    }

    func stop() {
        isActive = false
        isDraining = false
        locationService.onLocationUpdate = nil
        healthService.onHealthUpdate = nil
        motionService?.onActivityUpdate = nil
        locationService.stopMonitoring()
        healthService.stopMonitoring()
        motionService?.stopMonitoring()
    }

    func resetOutbox() {
        outboxState = SensorOutboxState()
        persistence.clearSensorOutboxState()
    }

    func handleAppDidBecomeActive() async {
        guard isActive else {
            sensorLog.warning("handleAppDidBecomeActive: service not active — skipping")
            return
        }
        sensorLog.notice("handleAppDidBecomeActive: requesting location + full health refresh")

        locationService.requestSingleLocation()
        await captureHealthSnapshot(forceFullRefresh: true)
        await drainOutboxIfPossible()
    }

    func handleSystemLaunch() async {
        guard isActive else {
            sensorLog.warning("handleSystemLaunch: service not active — skipping")
            return
        }
        sensorLog.notice("handleSystemLaunch: capturing health + draining outbox")

        await captureHealthSnapshot()
        await drainOutboxIfPossible()
    }

    private func captureHealthSnapshot(
        forceFullRefresh: Bool = false,
        changedIdentifiers: Set<String>? = nil
    ) async {
        guard
            let snapshot = await healthService.collectSnapshot(
                forceFullRefresh: forceFullRefresh,
                changedIdentifiers: changedIdentifiers
            )
        else {
            sensorLog.notice("captureHealth: collectSnapshot returned nil (auth=\(String(describing: self.healthService.authorizationStatus), privacy: .public))")
            return
        }
        guard !snapshot.samples.isEmpty else {
            sensorLog.notice("captureHealth: snapshot empty (no changed metrics)")
            return
        }
        sensorLog.notice("captureHealth: got \(snapshot.samples.count) samples — \(snapshot.samples.map(\.metric).joined(separator: ", "))")
        outboxState.enqueue(healthSamples: snapshot.samples)
        SharedWidgetDataStore.updateHealthMetrics(from: snapshot.samples)
        persistOutboxState()
        await drainOutboxIfPossible()
    }

    private func drainOutboxIfPossible() async {
        guard !isDraining else {
            sensorLog.debug("drain: skipped — already draining")
            return
        }
        guard isActive else {
            sensorLog.warning("drain: BLOCKED — service not active (start() never called or stop()'d)")
            return
        }
        guard isPairedProvider() else {
            sensorLog.warning("drain: BLOCKED — isPairedProvider() returned false")
            return
        }

        guard let accessToken = await accessTokenProvider(), !accessToken.isEmpty else {
            sensorLog.warning("drain: BLOCKED — accessTokenProvider() returned nil/empty")
            return
        }
        _ = accessToken

        sensorLog.notice("drain: starting. Outbox: loc=\(self.outboxState.pendingLocation != nil), health=\(self.outboxState.pendingHealthSamples.count)")

        isDraining = true
        defer { isDraining = false }

        while isActive && isPairedProvider() {
            if let pendingLocation = outboxState.pendingLocation {
                let delivered = await uploadLocation(pendingLocation)
                sensorLog.notice("drain: location upload \(delivered ? "delivered" : "FAILED", privacy: .public)")
                guard delivered else { break }
                outboxState.pendingLocation = nil
                persistOutboxState()
                continue
            }

            if !outboxState.pendingHealthSamples.isEmpty {
                let delivered = await uploadHealth(outboxState.pendingHealthSamples)
                sensorLog.notice("drain: health upload (\(self.outboxState.pendingHealthSamples.count) samples) \(delivered ? "delivered" : "FAILED", privacy: .public)")
                guard delivered else { break }
                outboxState.pendingHealthSamples.removeAll()
                persistOutboxState()
                continue
            }

            break
        }
        sensorLog.notice("drain: finished. Outbox remaining: loc=\(self.outboxState.pendingLocation != nil), health=\(self.outboxState.pendingHealthSamples.count)")
    }

    private func persistOutboxState() {
        if outboxState.isEmpty {
            persistence.clearSensorOutboxState()
        } else {
            persistence.saveSensorOutboxState(outboxState)
        }
    }

    private func uploadLocation(_ pending: SensorOutboxState.PendingLocation) async -> Bool {
        // Reverse geocode to get a human-readable address
        let address = await reverseGeocode(latitude: pending.latitude, longitude: pending.longitude)

        let body = SensorLocationBody(
            latitude: pending.latitude,
            longitude: pending.longitude,
            altitude: pending.altitude,
            accuracy: pending.accuracy,
            address: address,
            recordedAt: iso8601Formatter.string(from: pending.recordedAt)
        )

        return await performAuthorizedUpload(path: "device/sensor/location", body: body)
    }

    private func reverseGeocode(latitude: Double, longitude: Double) async -> String? {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        do {
            if #available(iOS 26.0, *) {
                guard let request = MKReverseGeocodingRequest(location: location) else {
                    return nil
                }
                let mapItems = try await request.mapItems
                guard let item = mapItems.first else { return nil }
                if let shortAddress = item.address?.shortAddress, !shortAddress.isEmpty {
                    return shortAddress
                }
                if let fullAddress = item.address?.fullAddress, !fullAddress.isEmpty {
                    return fullAddress
                }
                if let singleLine = item.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true),
                   !singleLine.isEmpty {
                    return singleLine
                }
                return item.name
            } else {
                let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
                guard let place = placemarks.first else { return nil }
                let parts = [place.name, place.thoroughfare, place.locality, place.administrativeArea]
                    .compactMap { $0 }
                return parts.isEmpty ? nil : parts.joined(separator: ", ")
            }
        } catch {
            return nil
        }
    }

    private func uploadHealth(_ samples: [SensorOutboxState.PendingHealthSample]) async -> Bool {
        let body = SensorHealthBody(
            samples: samples.map { sample in
                SensorHealthBody.Sample(
                    metric: sample.metric,
                    value: sample.value,
                    unit: sample.unit,
                    startAt: iso8601Formatter.string(from: sample.startAt),
                    endAt: sample.endAt.map { iso8601Formatter.string(from: $0) }
                )
            }
        )

        return await performAuthorizedUpload(path: "device/sensor/health", body: body)
    }

    private func performAuthorizedUpload<Body: Encodable>(path: String, body: Body) async -> Bool {
        do {
            return try await executeUpload(path: path, body: body, accessToken: await accessTokenProvider())
        } catch RelayAPIClient.ClientError.unauthorized {
            sensorLog.warning("upload \(path): 401 unauthorized, attempting token refresh…")
            guard let refreshedToken = await accessTokenRefresher(), !refreshedToken.isEmpty else {
                sensorLog.error("upload \(path): token refresh failed/empty")
                return false
            }
            return (try? await executeUpload(path: path, body: body, accessToken: refreshedToken)) ?? false
        } catch {
            sensorLog.error("upload \(path): error — \(error.localizedDescription)")
            return false
        }
    }

    private func executeUpload<Body: Encodable>(path: String, body: Body, accessToken: String?) async throws -> Bool {
        guard let accessToken, !accessToken.isEmpty else {
            sensorLog.warning("executeUpload \(path): no access token")
            return false
        }
        let result: DeliveryResult = try await apiClient.post(
            path: path,
            body: body,
            accessToken: accessToken
        )
        sensorLog.notice("executeUpload \(path, privacy: .public): deliveryState=\(result.deliveryState, privacy: .public) wasDelivered=\(result.wasDelivered, privacy: .public)")
        return result.wasDelivered
    }
}
