import Foundation
import HealthKit
import Testing
@testable import Talaria

/// Shared HealthKit query core (#15) — the logic both the app snapshot and the
/// widget tiles run. `LiveHealthService`'s statics forward here; these tests
/// pin the core directly so the forwards can't silently diverge from it.
struct HealthQueryCoreTests {

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test func aggregateSleepDurationCountsOnlyAsleepIntervalsEndingInBucket() async throws {
        let calendar = utcCalendar
        let bucketDay = calendar.date(from: DateComponents(year: 2026, month: 7, day: 6))!

        let intervals: [HealthQueryCore.SleepInterval] = [
            // Overnight sleep ending inside the bucket day — counts (7h).
            .init(
                value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                startDate: calendar.date(from: DateComponents(year: 2026, month: 7, day: 5, hour: 23))!,
                endDate: calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 6))!
            ),
            // In-bed (not asleep) — excluded.
            .init(
                value: HKCategoryValueSleepAnalysis.inBed.rawValue,
                startDate: calendar.date(from: DateComponents(year: 2026, month: 7, day: 5, hour: 22))!,
                endDate: calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 7))!
            ),
            // Ends after the bucket day — attributed to tomorrow, excluded.
            .init(
                value: HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                startDate: calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 23))!,
                endDate: calendar.date(from: DateComponents(year: 2026, month: 7, day: 7, hour: 6))!
            ),
        ]

        let hours = HealthQueryCore.aggregateSleepDuration(
            intervals: intervals,
            attributedTo: bucketDay,
            calendar: calendar
        )
        #expect(hours == 7.0)
    }

    @Test func aggregateSleepDurationReturnsNilForNoSleep() async throws {
        let calendar = utcCalendar
        let bucketDay = calendar.date(from: DateComponents(year: 2026, month: 7, day: 6))!
        let hours = HealthQueryCore.aggregateSleepDuration(
            intervals: [],
            attributedTo: bucketDay,
            calendar: calendar
        )
        #expect(hours == nil)
    }

    @Test func sharedWindowsMatchSnapshotSemantics() async throws {
        let calendar = utcCalendar
        let evening = calendar.date(from: DateComponents(year: 2026, month: 7, day: 6, hour: 18, minute: 30))!
        let dayStart = calendar.date(from: DateComponents(year: 2026, month: 7, day: 6))!

        #expect(HealthQueryCore.sleepBucketDay(for: evening, calendar: calendar) == dayStart)
        #expect(HealthQueryCore.startOfToday(for: evening, calendar: calendar) == dayStart)
        #expect(HealthQueryCore.heartRateLookback == 86_400)
    }

    @Test func widgetMetricsEmptinessDrivesSnapshotFallback() async throws {
        var metrics = HealthQueryCore.WidgetHealthMetrics()
        #expect(metrics.isEmpty, "all-nil metrics must read as empty so the widget falls back to the snapshot")

        metrics.heartRate = 68
        #expect(!metrics.isEmpty, "a single live value is enough to prefer the live read")
    }
}
