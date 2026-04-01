import Foundation
import HealthKit

struct HealthSnapshot: Sendable {
    struct Sample: Sendable {
        let metric: String
        let value: Double
        let unit: String
        let startAt: Date
        let endAt: Date?
    }

    let samples: [Sample]
    let collectedAt: Date
}

@MainActor
@Observable
final class LiveHealthService: HealthServiceProtocol {
    private struct HealthMetricDescriptor {
        let metric: String
        let sampleType: HKSampleType
        let startDateProvider: () -> Date
        let builder: @MainActor (LiveHealthService, Date) async -> HealthSnapshot.Sample?
    }

    private struct AnchoredChangeResult {
        let didChange: Bool
        let newAnchor: HKQueryAnchor?
    }

    private(set) var authorizationStatus: PermissionStatus
    private(set) var backgroundDeliveryEnabled = false
    var onHealthUpdate: (@MainActor (Set<String>) -> Void)?

    private let store: HKHealthStore?
    private let persistence: (any AppPersistenceStoreProtocol)?
    private let metricDescriptors: [String: HealthMetricDescriptor]
    private var observerQueries: [HKObserverQuery] = []

    init(persistence: (any AppPersistenceStoreProtocol)? = nil) {
        self.persistence = persistence

        guard HKHealthStore.isHealthDataAvailable() else {
            self.store = nil
            self.metricDescriptors = [:]
            self.authorizationStatus = .unsupported
            return
        }

        let store = HKHealthStore()
        self.store = store
        self.metricDescriptors = LiveHealthService.makeMetricDescriptors()
        self.authorizationStatus = .notDetermined
    }

    func requestAuthorization() async -> PermissionStatus {
        guard let store else {
            authorizationStatus = .unsupported
            return .unsupported
        }

        do {
            try await store.requestAuthorization(
                toShare: [],
                read: Set(metricDescriptors.values.map { $0.sampleType as HKObjectType })
            )
            authorizationStatus = .authorized
            await configureBackgroundDeliveryIfNeeded()
        } catch {
            authorizationStatus = .denied
            backgroundDeliveryEnabled = false
        }

        return authorizationStatus
    }

    func startMonitoring() {
        guard let store, observerQueries.isEmpty else { return }

        for (identifier, descriptor) in metricDescriptors.sorted(by: { $0.key < $1.key }) {
            let query = HKObserverQuery(sampleType: descriptor.sampleType, predicate: nil) { [weak self] _, completionHandler, error in
                defer { completionHandler() }
                guard error == nil else { return }
                Task { @MainActor in
                    self?.onHealthUpdate?([identifier])
                }
            }
            observerQueries.append(query)
            store.execute(query)
        }

        if authorizationStatus == .authorized {
            Task { @MainActor in
                await configureBackgroundDeliveryIfNeeded()
            }
        }
    }

    func stopMonitoring() {
        guard let store else { return }
        for query in observerQueries {
            store.stop(query)
        }
        observerQueries.removeAll()
    }

    func collectSnapshot(
        forceFullRefresh: Bool = false,
        changedIdentifiers: Set<String>? = nil
    ) async -> HealthSnapshot? {
        guard store != nil else { return nil }
        guard authorizationStatus == .authorized else { return nil }

        let changedMetrics = await resolveChangedMetrics(
            forceFullRefresh: forceFullRefresh,
            requestedIdentifiers: changedIdentifiers
        )
        guard !changedMetrics.isEmpty else { return nil }

        let now = Date()
        var samples: [HealthSnapshot.Sample] = []

        for identifier in changedMetrics.sorted() {
            guard let descriptor = metricDescriptors[identifier] else { continue }
            let startDate = descriptor.startDateProvider()
            if let sample = await descriptor.builder(self, startDate) {
                samples.append(sample)
            }
        }

        guard !samples.isEmpty else { return nil }
        return HealthSnapshot(samples: samples, collectedAt: now)
    }

    // MARK: - Background Delivery

    private func configureBackgroundDeliveryIfNeeded() async {
        guard let store, authorizationStatus == .authorized else { return }

        var allSucceeded = true
        for descriptor in metricDescriptors.values {
            do {
                try await store.enableBackgroundDelivery(
                    for: descriptor.sampleType,
                    frequency: .immediate
                )
            } catch {
                allSucceeded = false
            }
        }
        backgroundDeliveryEnabled = allSucceeded
    }

    // MARK: - Incremental Anchors

    private func resolveChangedMetrics(
        forceFullRefresh: Bool,
        requestedIdentifiers: Set<String>?
    ) async -> Set<String> {
        let identifiersToCheck: Set<String>
        if forceFullRefresh {
            identifiersToCheck = Set(metricDescriptors.keys)
        } else if let requestedIdentifiers, !requestedIdentifiers.isEmpty {
            identifiersToCheck = requestedIdentifiers.intersection(metricDescriptors.keys)
        } else {
            identifiersToCheck = Set(metricDescriptors.keys)
        }

        var changed: Set<String> = []
        for identifier in identifiersToCheck {
            guard let descriptor = metricDescriptors[identifier] else { continue }
            let startDate = descriptor.startDateProvider()
            let result = await fetchAnchoredChanges(
                for: identifier,
                sampleType: descriptor.sampleType,
                startDate: startDate
            )
            if forceFullRefresh || result.didChange {
                changed.insert(identifier)
            }
        }
        return changed
    }

    private func fetchAnchoredChanges(
        for identifier: String,
        sampleType: HKSampleType,
        startDate: Date
    ) async -> AnchoredChangeResult {
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: nil)
        let anchor = loadAnchor(for: identifier)

        return await withCheckedContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: sampleType,
                predicate: predicate,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { [weak self] _, sampleObjects, deletedObjects, newAnchor, _ in
                if let newAnchor {
                    Task { @MainActor in
                        self?.saveAnchor(newAnchor, for: identifier)
                    }
                }
                continuation.resume(
                    returning: AnchoredChangeResult(
                        didChange: !(sampleObjects ?? []).isEmpty || !(deletedObjects ?? []).isEmpty,
                        newAnchor: newAnchor
                    )
                )
            }
            store?.execute(query)
        }
    }

    private func loadAnchor(for identifier: String) -> HKQueryAnchor? {
        guard
            let data = persistence?.loadHealthQueryAnchorData(for: identifier),
            let anchor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
        else {
            return nil
        }
        return anchor
    }

    private func saveAnchor(_ anchor: HKQueryAnchor, for identifier: String) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) else {
            return
        }
        persistence?.saveHealthQueryAnchorData(data, for: identifier)
    }

    // MARK: - Metric Queries

    private func queryCumulativeSum(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from startDate: Date,
        to endDate: Date
    ) async -> Double? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, _ in
                continuation.resume(returning: result?.sumQuantity()?.doubleValue(for: unit))
            }
            store?.execute(query)
        }
    }

    private func queryLatestSample(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from startDate: Date? = nil
    ) async -> (Double, Date)? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let predicate = startDate.map { HKQuery.predicateForSamples(withStart: $0, end: nil) }

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, results, _ in
                guard let sample = results?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(
                    returning: (
                        sample.quantity.doubleValue(for: unit),
                        sample.startDate
                    )
                )
            }
            store?.execute(query)
        }
    }

    private static func makeMetricDescriptors() -> [String: HealthMetricDescriptor] {
        var descriptors: [String: HealthMetricDescriptor] = [:]

        if let steps = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            descriptors["steps"] = HealthMetricDescriptor(
                metric: "steps",
                sampleType: steps,
                startDateProvider: { Calendar.current.startOfDay(for: Date()) },
                builder: { service, startDate in
                    guard
                        let value = await service.queryCumulativeSum(
                            .stepCount,
                            unit: .count(),
                            from: startDate,
                            to: Date()
                        )
                    else {
                        return nil
                    }
                    return .init(
                        metric: "steps",
                        value: value,
                        unit: "count",
                        startAt: startDate,
                        endAt: Date()
                    )
                }
            )
        }

        if let calories = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            descriptors["active_calories"] = HealthMetricDescriptor(
                metric: "active_calories",
                sampleType: calories,
                startDateProvider: { Calendar.current.startOfDay(for: Date()) },
                builder: { service, startDate in
                    guard
                        let value = await service.queryCumulativeSum(
                            .activeEnergyBurned,
                            unit: .kilocalorie(),
                            from: startDate,
                            to: Date()
                        )
                    else {
                        return nil
                    }
                    return .init(
                        metric: "active_calories",
                        value: value,
                        unit: "kcal",
                        startAt: startDate,
                        endAt: Date()
                    )
                }
            )
        }

        if let distance = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) {
            descriptors["distance_walking"] = HealthMetricDescriptor(
                metric: "distance_walking",
                sampleType: distance,
                startDateProvider: { Calendar.current.startOfDay(for: Date()) },
                builder: { service, startDate in
                    guard
                        let value = await service.queryCumulativeSum(
                            .distanceWalkingRunning,
                            unit: .meter(),
                            from: startDate,
                            to: Date()
                        )
                    else {
                        return nil
                    }
                    return .init(
                        metric: "distance_walking",
                        value: value,
                        unit: "meters",
                        startAt: startDate,
                        endAt: Date()
                    )
                }
            )
        }

        if let heartRate = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            descriptors["heart_rate"] = HealthMetricDescriptor(
                metric: "heart_rate",
                sampleType: heartRate,
                startDateProvider: { Date().addingTimeInterval(-86_400) },
                builder: { service, startDate in
                    guard
                        let (value, date) = await service.queryLatestSample(
                            .heartRate,
                            unit: .count().unitDivided(by: .minute()),
                            from: startDate
                        )
                    else {
                        return nil
                    }
                    return .init(
                        metric: "heart_rate",
                        value: value,
                        unit: "bpm",
                        startAt: date,
                        endAt: nil
                    )
                }
            )
        }

        return descriptors
    }
}
