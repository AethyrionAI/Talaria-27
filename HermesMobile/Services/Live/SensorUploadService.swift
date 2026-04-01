import Foundation

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
            "distance_walking"
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
    private let persistence: AppPersistenceStoreProtocol
    private let isPairedProvider: @MainActor () -> Bool
    private let locationService: LiveLocationService
    private let healthService: LiveHealthService

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
        persistence: AppPersistenceStoreProtocol,
        isPairedProvider: @escaping @MainActor () -> Bool,
        locationService: LiveLocationService,
        healthService: LiveHealthService
    ) {
        self.apiClient = apiClient
        self.accessTokenProvider = accessTokenProvider
        self.persistence = persistence
        self.isPairedProvider = isPairedProvider
        self.locationService = locationService
        self.healthService = healthService
        self.outboxState = persistence.loadSensorOutboxState()
    }

    func start() {
        guard !isActive else { return }
        isActive = true
        outboxState = persistence.loadSensorOutboxState()

        locationService.onLocationUpdate = { [weak self] update in
            guard let self else { return }
            Task { @MainActor in
                self.outboxState.enqueue(location: update)
                self.persistOutboxState()
                await self.drainOutboxIfPossible()
            }
        }

        healthService.onHealthUpdate = { [weak self] changedIdentifiers in
            guard let self else { return }
            Task { @MainActor in
                await self.captureHealthSnapshot(changedIdentifiers: changedIdentifiers)
            }
        }

        locationService.startMonitoring()
        healthService.startMonitoring()
    }

    func stop() {
        isActive = false
        isDraining = false
        locationService.onLocationUpdate = nil
        healthService.onHealthUpdate = nil
        locationService.stopMonitoring()
        healthService.stopMonitoring()
    }

    func resetOutbox() {
        outboxState = SensorOutboxState()
        persistence.clearSensorOutboxState()
    }

    func handleAppDidBecomeActive() async {
        guard isActive else { return }

        locationService.requestSingleLocation()
        await captureHealthSnapshot(forceFullRefresh: true)
        await drainOutboxIfPossible()
    }

    func handleSystemLaunch() async {
        guard isActive else { return }

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
            return
        }
        guard !snapshot.samples.isEmpty else { return }
        outboxState.enqueue(healthSamples: snapshot.samples)
        persistOutboxState()
        await drainOutboxIfPossible()
    }

    private func drainOutboxIfPossible() async {
        guard !isDraining else { return }
        guard isActive else { return }
        guard isPairedProvider() else { return }

        guard let accessToken = await accessTokenProvider(), !accessToken.isEmpty else {
            return
        }

        isDraining = true
        defer { isDraining = false }

        while isActive && isPairedProvider() {
            if let pendingLocation = outboxState.pendingLocation {
                let delivered = await uploadLocation(pendingLocation, accessToken: accessToken)
                guard delivered else { break }
                outboxState.pendingLocation = nil
                persistOutboxState()
                continue
            }

            if !outboxState.pendingHealthSamples.isEmpty {
                let delivered = await uploadHealth(outboxState.pendingHealthSamples, accessToken: accessToken)
                guard delivered else { break }
                outboxState.pendingHealthSamples.removeAll()
                persistOutboxState()
                continue
            }

            break
        }
    }

    private func persistOutboxState() {
        if outboxState.isEmpty {
            persistence.clearSensorOutboxState()
        } else {
            persistence.saveSensorOutboxState(outboxState)
        }
    }

    private func uploadLocation(_ pending: SensorOutboxState.PendingLocation, accessToken: String) async -> Bool {
        let body = SensorLocationBody(
            latitude: pending.latitude,
            longitude: pending.longitude,
            altitude: pending.altitude,
            accuracy: pending.accuracy,
            address: nil,
            recordedAt: iso8601Formatter.string(from: pending.recordedAt)
        )

        do {
            let result: DeliveryResult = try await apiClient.post(
                path: "device/sensor/location",
                body: body,
                accessToken: accessToken
            )
            return result.wasDelivered
        } catch {
            return false
        }
    }

    private func uploadHealth(_ samples: [SensorOutboxState.PendingHealthSample], accessToken: String) async -> Bool {
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

        do {
            let result: DeliveryResult = try await apiClient.post(
                path: "device/sensor/health",
                body: body,
                accessToken: accessToken
            )
            return result.wasDelivered
        } catch {
            return false
        }
    }
}
