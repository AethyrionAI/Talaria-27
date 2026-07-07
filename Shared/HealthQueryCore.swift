import Foundation
import HealthKit

/// HealthKit query primitives shared by the app target (`LiveHealthService`
/// sensor snapshots) and the widget extension (`HermesHealthWidget` tiles
/// querying HealthKit directly, #15). Compiled into BOTH targets via the
/// `Shared` sources entries in project.yml — keep it dependency-free:
/// Foundation + HealthKit only, no app models or stores.
enum HealthQueryCore {

    // MARK: - Shared query windows

    /// Heart-rate look-back window (latest sample within the last day) —
    /// single source of truth for the app snapshot and the widget tile.
    static let heartRateLookback: TimeInterval = 86_400

    /// Start of the "today" window for cumulative rollups (steps, calories).
    static func startOfToday(for referenceDate: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: referenceDate)
    }

    // MARK: - Sleep aggregation

    /// One sleep sample flattened for aggregation (mirror of HKCategorySample).
    struct SleepInterval: Sendable {
        let value: Int
        let startDate: Date
        let endDate: Date
    }

    /// The day bucket sleep is attributed to — the day the sleep *ends*, so
    /// last night's sleep counts toward today.
    static func sleepBucketDay(
        for referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        calendar.startOfDay(for: referenceDate)
    }

    static func aggregateSleepDuration(
        intervals: [SleepInterval],
        attributedTo bucketDay: Date,
        calendar: Calendar = .current
    ) -> Double? {
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: bucketDay) else {
            return nil
        }

        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]

        let totalSeconds = intervals
            .filter { asleepValues.contains($0.value) }
            .filter { $0.endDate >= bucketDay && $0.endDate < nextDay }
            .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }

        let hours = totalSeconds / 3600.0
        return hours > 0 ? hours : nil
    }

    // MARK: - Query primitives

    /// `.cumulativeSum` rollup over [startDate, endDate]. Errors — including a
    /// locked device's `errorDatabaseInaccessible` — surface as nil; callers
    /// treat nil as "no data" and fall back.
    @MainActor
    static func cumulativeSum(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from startDate: Date,
        to endDate: Date,
        store: HKHealthStore
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
            store.execute(query)
        }
    }

    /// Most recent sample of `identifier`, optionally bounded to on-or-after
    /// `startDate`. Returns (value, sample start date).
    @MainActor
    static func latestSample(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from startDate: Date? = nil,
        store: HKHealthStore
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
            store.execute(query)
        }
    }

    /// Total asleep hours attributed to `bucketDay`. The 18h look-back keeps
    /// a sleep that started the previous evening inside the query window.
    @MainActor
    static func sleepDuration(
        attributedTo bucketDay: Date,
        store: HKHealthStore,
        calendar: Calendar = .current
    ) async -> Double? {
        let sleepType = HKCategoryType(.sleepAnalysis)
        guard
            let queryStart = calendar.date(byAdding: .hour, value: -18, to: bucketDay),
            let queryEnd = calendar.date(byAdding: .day, value: 1, to: bucketDay)
        else {
            return nil
        }
        let predicate = HKQuery.predicateForSamples(withStart: queryStart, end: queryEnd)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, results, _ in
                guard let samples = results as? [HKCategorySample] else {
                    continuation.resume(returning: nil)
                    return
                }
                let intervals = samples.map {
                    SleepInterval(value: $0.value, startDate: $0.startDate, endDate: $0.endDate)
                }
                continuation.resume(
                    returning: aggregateSleepDuration(
                        intervals: intervals,
                        attributedTo: bucketDay,
                        calendar: calendar
                    )
                )
            }
            store.execute(query)
        }
    }

    // MARK: - Widget tile metrics (#15)

    /// The four tile metrics `HermesHealthWidget` renders, queried with the
    /// same windows and rounding the app's sensor snapshot uses.
    struct WidgetHealthMetrics: Sendable {
        var steps: Int?
        var activeCalories: Int?
        var sleepHours: Double?
        var heartRate: Int?

        var isEmpty: Bool {
            steps == nil && activeCalories == nil && sleepHours == nil && heartRate == nil
        }
    }

    /// Queries the four widget tile metrics directly from HealthKit. Returns
    /// nil when HealthKit is unavailable on this hardware. A denied read
    /// authorization is indistinguishable from empty data by design, and a
    /// locked device (`errorDatabaseInaccessible`) errors every query — both
    /// come back as an `isEmpty` result, which callers treat as "fall back to
    /// the app-written snapshot". Deliberately NOT an auth check.
    @MainActor
    static func loadWidgetMetrics(now: Date = Date()) async -> WidgetHealthMetrics? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let store = HKHealthStore()
        var metrics = WidgetHealthMetrics()

        if let steps = await cumulativeSum(
            .stepCount, unit: .count(), from: startOfToday(for: now), to: now, store: store
        ) {
            metrics.steps = Int(steps.rounded())
        }
        if let calories = await cumulativeSum(
            .activeEnergyBurned, unit: .kilocalorie(), from: startOfToday(for: now), to: now, store: store
        ) {
            metrics.activeCalories = Int(calories.rounded())
        }
        metrics.sleepHours = await sleepDuration(attributedTo: sleepBucketDay(for: now), store: store)
        if let (heartRate, _) = await latestSample(
            .heartRate,
            unit: .count().unitDivided(by: .minute()),
            from: now.addingTimeInterval(-heartRateLookback),
            store: store
        ) {
            metrics.heartRate = Int(heartRate.rounded())
        }
        return metrics
    }
}
