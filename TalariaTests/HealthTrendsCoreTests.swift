import Foundation
import HealthKit
import Testing
@testable import Talaria

/// Pure trends math for the Health Trends screen (#125): day-window
/// construction, HK-statistics alignment, sleep bucketing, the 7-day-vs-prior
/// delta, and pre-budget downsampling into the #100 chart pipeline. All logic
/// here runs without HealthKit — the live service is thin plumbing over it.
struct HealthTrendsCoreTests {

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    /// America/New_York — 2026 spring-forward lands on March 8.
    private var newYorkCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    // MARK: - Windowing

    @Test func dayStartsProducesConsecutiveDaysEndingToday() {
        let calendar = utcCalendar
        let reference = date(2026, 7, 17, hour: 14, minute: 30, calendar: calendar)

        let days = HealthTrendsCore.dayStarts(days: 7, endingOn: reference, calendar: calendar)

        #expect(days.count == 7)
        #expect(days.last == calendar.startOfDay(for: reference))
        #expect(days.first == date(2026, 7, 11, calendar: calendar))
        for (earlier, later) in zip(days, days.dropFirst()) {
            #expect(calendar.dateComponents([.day], from: earlier, to: later).day == 1)
        }
    }

    @Test func dayStartsSpanningSpringForwardKeepsOneBucketPerCalendarDay() {
        let calendar = newYorkCalendar
        // 30-day window ending 2026-03-15 crosses the March 8 spring-forward.
        let reference = date(2026, 3, 15, hour: 12, calendar: calendar)

        let days = HealthTrendsCore.dayStarts(days: 30, endingOn: reference, calendar: calendar)

        #expect(days.count == 30)
        #expect(Set(days).count == 30)
        #expect(days.last == calendar.startOfDay(for: reference))
        for (earlier, later) in zip(days, days.dropFirst()) {
            #expect(calendar.dateComponents([.day], from: earlier, to: later).day == 1)
            #expect(calendar.startOfDay(for: earlier) == earlier)
        }
        // The DST day itself is 23 hours long — a fixed-86400s stride would
        // have drifted here; calendar day arithmetic must not.
        let dstDay = date(2026, 3, 8, calendar: calendar)
        let nextDay = date(2026, 3, 9, calendar: calendar)
        #expect(days.contains(dstDay))
        #expect(nextDay.timeIntervalSince(dstDay) == 23 * 3600)
    }

    // MARK: - Statistics alignment

    @Test func alignedDailyPointsKeepsInWindowStatsAndDropsStrays() {
        let calendar = utcCalendar
        let reference = date(2026, 7, 17, hour: 9, calendar: calendar)
        let days = HealthTrendsCore.dayStarts(days: 7, endingOn: reference, calendar: calendar)

        let stats: [(start: Date, value: Double)] = [
            (date(2026, 7, 11, calendar: calendar), 5000),
            (date(2026, 7, 13, calendar: calendar), 7200),
            // Mid-day period start still belongs to its calendar day.
            (date(2026, 7, 16, hour: 11, calendar: calendar), 8100),
            // Outside the window — dropped.
            (date(2026, 7, 1, calendar: calendar), 999),
            (date(2026, 8, 1, calendar: calendar), 999),
        ]

        let points = HealthTrendsCore.alignedDailyPoints(statistics: stats, dayStarts: days, calendar: calendar)

        #expect(points == [
            HealthTrendPoint(day: date(2026, 7, 11, calendar: calendar), value: 5000),
            HealthTrendPoint(day: date(2026, 7, 13, calendar: calendar), value: 7200),
            HealthTrendPoint(day: date(2026, 7, 16, calendar: calendar), value: 8100),
        ])
    }

    @Test func alignedDailyPointsEmptyInputsProduceEmptySeries() {
        let calendar = utcCalendar
        let days = HealthTrendsCore.dayStarts(days: 7, endingOn: date(2026, 7, 17, calendar: calendar), calendar: calendar)
        #expect(HealthTrendsCore.alignedDailyPoints(statistics: [], dayStarts: days, calendar: calendar).isEmpty)
        #expect(HealthTrendsCore.alignedDailyPoints(
            statistics: [(date(2026, 7, 16, calendar: calendar), 1)], dayStarts: [], calendar: calendar
        ).isEmpty)
    }

    // MARK: - Sleep bucketing

    @Test func dailySleepPointsAttributesOvernightSleepToEndDayAndSkipsEmptyDays() {
        let calendar = utcCalendar
        let reference = date(2026, 7, 8, hour: 10, calendar: calendar)
        let days = HealthTrendsCore.dayStarts(days: 7, endingOn: reference, calendar: calendar)

        let intervals: [HealthQueryCore.SleepInterval] = [
            // 23:00 Jul 4 → 06:00 Jul 5: 7h attributed to Jul 5.
            .init(
                value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                startDate: date(2026, 7, 4, hour: 23, calendar: calendar),
                endDate: date(2026, 7, 5, hour: 6, calendar: calendar)
            ),
            // In-bed only — never counts.
            .init(
                value: HKCategoryValueSleepAnalysis.inBed.rawValue,
                startDate: date(2026, 7, 5, hour: 22, calendar: calendar),
                endDate: date(2026, 7, 6, hour: 7, calendar: calendar)
            ),
            // 01:00 → 07:30 Jul 7: 6.5h attributed to Jul 7.
            .init(
                value: HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                startDate: date(2026, 7, 7, hour: 1, calendar: calendar),
                endDate: date(2026, 7, 7, hour: 7, minute: 30, calendar: calendar)
            ),
        ]

        let points = HealthTrendsCore.dailySleepPoints(intervals: intervals, dayStarts: days, calendar: calendar)

        #expect(points == [
            HealthTrendPoint(day: date(2026, 7, 5, calendar: calendar), value: 7.0),
            HealthTrendPoint(day: date(2026, 7, 7, calendar: calendar), value: 6.5),
        ])
    }

    // MARK: - Trend delta

    @Test func weekOverWeekDeltaComparesRecentSevenDaysAgainstPriorSeven() {
        let calendar = utcCalendar
        let reference = date(2026, 7, 14, hour: 20, calendar: calendar)
        // Prior week (Jul 1–7) averages 100; recent week (Jul 8–14) averages 104.
        var points: [HealthTrendPoint] = []
        for day in 1...7 { points.append(.init(day: date(2026, 7, day, calendar: calendar), value: 100)) }
        for day in 8...14 { points.append(.init(day: date(2026, 7, day, calendar: calendar), value: 104)) }

        let delta = HealthTrendsCore.weekOverWeekDelta(points: points, endingOn: reference, calendar: calendar)

        #expect(delta != nil)
        #expect(abs(delta! - 0.04) < 0.0001)
    }

    @Test func weekOverWeekDeltaAveragesOnlyDaysWithData() {
        let calendar = utcCalendar
        let reference = date(2026, 7, 14, hour: 20, calendar: calendar)
        // Sparse: prior week has two days (avg 50), recent week one day (55).
        let points: [HealthTrendPoint] = [
            .init(day: date(2026, 7, 2, calendar: calendar), value: 40),
            .init(day: date(2026, 7, 5, calendar: calendar), value: 60),
            .init(day: date(2026, 7, 10, calendar: calendar), value: 55),
        ]

        let delta = HealthTrendsCore.weekOverWeekDelta(points: points, endingOn: reference, calendar: calendar)

        #expect(delta != nil)
        #expect(abs(delta! - 0.10) < 0.0001)
    }

    @Test func weekOverWeekDeltaIsNilWithoutBothWindowsOrZeroBaseline() {
        let calendar = utcCalendar
        let reference = date(2026, 7, 14, hour: 20, calendar: calendar)

        // No data at all.
        #expect(HealthTrendsCore.weekOverWeekDelta(points: [], endingOn: reference, calendar: calendar) == nil)

        // Recent week only — no prior baseline to compare against.
        let recentOnly = [HealthTrendPoint(day: date(2026, 7, 12, calendar: calendar), value: 70)]
        #expect(HealthTrendsCore.weekOverWeekDelta(points: recentOnly, endingOn: reference, calendar: calendar) == nil)

        // Prior week only — nothing recent to report.
        let priorOnly = [HealthTrendPoint(day: date(2026, 7, 3, calendar: calendar), value: 70)]
        #expect(HealthTrendsCore.weekOverWeekDelta(points: priorOnly, endingOn: reference, calendar: calendar) == nil)

        // Zero baseline — a percent change against 0 is undefined, not ∞.
        let zeroBaseline: [HealthTrendPoint] = [
            .init(day: date(2026, 7, 3, calendar: calendar), value: 0),
            .init(day: date(2026, 7, 12, calendar: calendar), value: 70),
        ]
        #expect(HealthTrendsCore.weekOverWeekDelta(points: zeroBaseline, endingOn: reference, calendar: calendar) == nil)
    }

    // MARK: - Downsampling

    @Test func downsampledLeavesSmallSeriesUntouched() {
        let calendar = utcCalendar
        let points = (0..<90).map { offset in
            HealthTrendPoint(
                day: calendar.date(byAdding: .day, value: offset, to: date(2026, 1, 1, calendar: calendar))!,
                value: Double(offset)
            )
        }
        #expect(HealthTrendsCore.downsampled(points, maxCount: ChartSpec.maxPointsPerSeries) == points)
    }

    @Test func downsampledReducesOverBudgetSeriesPreservingEndpointsAndOrder() {
        let calendar = utcCalendar
        let points = (0..<600).map { offset in
            HealthTrendPoint(
                day: calendar.date(byAdding: .day, value: offset, to: date(2024, 1, 1, calendar: calendar))!,
                value: Double(offset)
            )
        }

        let reduced = HealthTrendsCore.downsampled(points, maxCount: ChartSpec.maxPointsPerSeries)

        #expect(reduced.count <= ChartSpec.maxPointsPerSeries)
        #expect(reduced.first == points.first)
        #expect(reduced.last == points.last)
        #expect(reduced == reduced.sorted(by: { $0.day < $1.day }))
        #expect(Set(reduced.map(\.day)).count == reduced.count)
    }

    // MARK: - ChartSpec construction

    @Test func chartSpecBuildsThroughTheSharedPipeline() {
        let calendar = utcCalendar
        let points = (0..<30).map { offset in
            HealthTrendPoint(
                day: calendar.date(byAdding: .day, value: offset, to: date(2026, 6, 18, calendar: calendar))!,
                value: 60 + Double(offset % 5)
            )
        }
        let series = HealthTrendSeries(metric: .restingHeartRate, points: points)

        let spec = HealthTrendsCore.chartSpec(for: series, calendar: calendar)

        #expect(spec != nil)
        #expect(spec?.kind == HealthTrendMetric.restingHeartRate.chartKind)
        #expect(spec?.xValues.count == 30)
        #expect(spec?.series.count == 1)
        #expect(spec?.series.first?.values == points.map(\.value))
    }

    @Test func chartSpecForCumulativeMetricUsesBars() {
        let calendar = utcCalendar
        let points = [
            HealthTrendPoint(day: date(2026, 7, 15, calendar: calendar), value: 8000),
            HealthTrendPoint(day: date(2026, 7, 16, calendar: calendar), value: 9500),
        ]
        let spec = HealthTrendsCore.chartSpec(for: HealthTrendSeries(metric: .steps, points: points), calendar: calendar)
        #expect(spec?.kind == .bar)
    }

    @Test func chartSpecDownsamplesBeforeTheBudgetInsteadOfFailingDecode() {
        let calendar = utcCalendar
        // 600 daily points — over ChartSpec.maxPointsPerSeries. The builder
        // must downsample first; handing 600 to ChartSpec would nil out.
        let points = (0..<600).map { offset in
            HealthTrendPoint(
                day: calendar.date(byAdding: .day, value: offset, to: date(2024, 1, 1, calendar: calendar))!,
                value: Double(offset)
            )
        }
        let series = HealthTrendSeries(metric: .steps, points: points)

        let spec = HealthTrendsCore.chartSpec(for: series, calendar: calendar)

        #expect(spec != nil)
        #expect((spec?.xValues.count ?? 0) <= ChartSpec.maxPointsPerSeries)
        #expect(spec?.series.first?.values.count == spec?.xValues.count)
    }

    @Test func chartSpecIsNilForEmptySeries() {
        let series = HealthTrendSeries(metric: .steps, points: [])
        #expect(HealthTrendsCore.chartSpec(for: series, calendar: utcCalendar) == nil)
    }

    // MARK: - Accessibility

    @Test func cardAccessibilityLabelNamesMetricRangeLatestAndDirection() {
        let calendar = utcCalendar
        let points: [HealthTrendPoint] = [
            .init(day: date(2026, 7, 3, calendar: calendar), value: 60),
            .init(day: date(2026, 7, 12, calendar: calendar), value: 57),
        ]
        let series = HealthTrendSeries(metric: .restingHeartRate, points: points)

        let label = HealthTrendsCore.cardAccessibilityLabel(
            for: series,
            range: .month,
            endingOn: date(2026, 7, 14, calendar: calendar),
            calendar: calendar
        )

        #expect(label.localizedCaseInsensitiveContains("resting heart rate"))
        #expect(label.contains("30"))
        #expect(label.contains("57"))
        #expect(label.localizedCaseInsensitiveContains("down 5 percent"))
    }

    @Test func cardAccessibilityLabelOmitsTrendWhenNoBaseline() {
        let calendar = utcCalendar
        let series = HealthTrendSeries(
            metric: .steps,
            points: [.init(day: date(2026, 7, 12, calendar: calendar), value: 8000)]
        )

        let label = HealthTrendsCore.cardAccessibilityLabel(
            for: series,
            range: .week,
            endingOn: date(2026, 7, 14, calendar: calendar),
            calendar: calendar
        )

        #expect(label.localizedCaseInsensitiveContains("steps"))
        #expect(!label.localizedCaseInsensitiveContains("percent"))
    }
}
