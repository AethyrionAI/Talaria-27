import Foundation
import HealthKit

/// HealthKit plumbing for the Health Trends screen (#125): one
/// `HKStatisticsCollectionQuery` per quantity metric (daily interval, DST
/// handled by the calendar), sleep via a sample query bucketed through
/// `HealthTrendsCore`. Never requests authorization — it reads behind the
/// grant `LiveHealthService` already obtained, and a metric outside that
/// grant just comes back empty. HealthKit runs the queries and result
/// enumeration on its own background queues; only the assembled value
/// structs return to the main actor.
@MainActor
final class LiveHealthTrendsService: HealthTrendsServiceProtocol {
    private let store: HKHealthStore?
    /// The existing auth surface (`LiveHealthService.authorizationStatus`) —
    /// queries are pointless before the in-app grant has been established.
    private let isAuthorized: @MainActor () -> Bool

    init(isAuthorized: @escaping @MainActor () -> Bool) {
        self.store = HKHealthStore.isHealthDataAvailable() ? HKHealthStore() : nil
        self.isAuthorized = isAuthorized
    }

    func trendSeries(range: HealthTrendRange) async -> [HealthTrendSeries] {
        guard let store, isAuthorized() else { return [] }

        let calendar = Calendar.current
        let dayStarts = HealthTrendsCore.dayStarts(days: range.days, endingOn: Date(), calendar: calendar)
        guard
            let windowStart = dayStarts.first,
            let lastDay = dayStarts.last,
            let windowEnd = calendar.date(byAdding: .day, value: 1, to: lastDay)
        else { return [] }

        var allSeries: [HealthTrendSeries] = []
        for metric in HealthTrendMetric.allCases {
            let points: [HealthTrendPoint] = if metric == .sleepDuration {
                await sleepPoints(dayStarts: dayStarts, windowEnd: windowEnd, store: store, calendar: calendar)
            } else {
                await quantityPoints(
                    for: metric,
                    dayStarts: dayStarts,
                    windowStart: windowStart,
                    windowEnd: windowEnd,
                    store: store,
                    calendar: calendar
                )
            }
            if !points.isEmpty {
                allSeries.append(HealthTrendSeries(metric: metric, points: points))
            }
        }
        return allSeries
    }

    // MARK: - Quantity metrics

    private func quantityPoints(
        for metric: HealthTrendMetric,
        dayStarts: [Date],
        windowStart: Date,
        windowEnd: Date,
        store: HKHealthStore,
        calendar: Calendar
    ) async -> [HealthTrendPoint] {
        guard
            let identifier = metric.quantityIdentifier,
            let quantityType = HKQuantityType.quantityType(forIdentifier: identifier)
        else { return [] }

        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd)
        let isCumulative = metric.isCumulative
        let unit = metric.hkUnit

        let statistics: [(start: Date, value: Double)] = await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: isCumulative ? .cumulativeSum : .discreteAverage,
                anchorDate: windowStart,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, _ in
                guard let collection else {
                    continuation.resume(returning: [])
                    return
                }
                var results: [(start: Date, value: Double)] = []
                collection.enumerateStatistics(from: windowStart, to: windowEnd) { dayStatistics, _ in
                    let quantity = isCumulative ? dayStatistics.sumQuantity() : dayStatistics.averageQuantity()
                    if let value = quantity?.doubleValue(for: unit) {
                        results.append((dayStatistics.startDate, value))
                    }
                }
                continuation.resume(returning: results)
            }
            store.execute(query)
        }

        return HealthTrendsCore.alignedDailyPoints(statistics: statistics, dayStarts: dayStarts, calendar: calendar)
    }

    // MARK: - Sleep

    private func sleepPoints(
        dayStarts: [Date],
        windowEnd: Date,
        store: HKHealthStore,
        calendar: Calendar
    ) async -> [HealthTrendPoint] {
        guard
            let firstDay = dayStarts.first,
            // 18h look-back so a sleep starting the prior evening lands in the
            // first bucket — same rule as HealthQueryCore.sleepDuration.
            let queryStart = calendar.date(byAdding: .hour, value: -18, to: firstDay)
        else { return [] }

        let predicate = HKQuery.predicateForSamples(withStart: queryStart, end: windowEnd)
        let intervals: [HealthQueryCore.SleepInterval] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKCategoryType(.sleepAnalysis),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, results, _ in
                let samples = (results as? [HKCategorySample]) ?? []
                continuation.resume(returning: samples.map {
                    .init(value: $0.value, startDate: $0.startDate, endDate: $0.endDate)
                })
            }
            store.execute(query)
        }

        guard !intervals.isEmpty else { return [] }
        return HealthTrendsCore.dailySleepPoints(intervals: intervals, dayStarts: dayStarts, calendar: calendar)
    }
}

// MARK: - HealthKit mapping

private extension HealthTrendMetric {
    var quantityIdentifier: HKQuantityTypeIdentifier? {
        switch self {
        case .restingHeartRate: .restingHeartRate
        case .heartRateVariability: .heartRateVariabilitySDNN
        case .steps: .stepCount
        case .activeCalories: .activeEnergyBurned
        case .respiratoryRate: .respiratoryRate
        case .sleepDuration: nil
        }
    }

    var hkUnit: HKUnit {
        switch self {
        case .restingHeartRate, .respiratoryRate: HKUnit.count().unitDivided(by: .minute())
        case .heartRateVariability: .secondUnit(with: .milli)
        case .steps: .count()
        case .activeCalories: .kilocalorie()
        case .sleepDuration: .hour()
        }
    }
}
