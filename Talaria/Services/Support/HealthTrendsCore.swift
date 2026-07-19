import Foundation

// MARK: - Trend vocabulary (#125)

/// The windows the Health Trends screen offers. Raw value = day count.
enum HealthTrendRange: Int, CaseIterable, Identifiable, Sendable {
    case week = 7
    case month = 30
    case quarter = 90

    var id: Int { rawValue }
    var days: Int { rawValue }
    var displayLabel: String { "\(rawValue)D" }
}

/// The six trend metrics of the #125 dispatch — nothing more. HRV stays in
/// the list even though the app has never requested its read scope: an
/// unauthorized read returns no samples, the series comes back empty, and the
/// card hides — the same honest-absence path as a denied metric. Adding the
/// scope is a future lane, not this one.
enum HealthTrendMetric: String, CaseIterable, Identifiable, Sendable {
    case restingHeartRate
    case heartRateVariability
    case steps
    case sleepDuration
    case activeCalories
    case respiratoryRate

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .restingHeartRate: "Resting Heart Rate"
        case .heartRateVariability: "Heart Rate Variability"
        case .steps: "Steps"
        case .sleepDuration: "Sleep"
        case .activeCalories: "Active Calories"
        case .respiratoryRate: "Respiratory Rate"
        }
    }

    /// Compact unit caption for the card header.
    var unitLabel: String {
        switch self {
        case .restingHeartRate: "BPM"
        case .heartRateVariability: "MS"
        case .steps: "STEPS"
        case .sleepDuration: "HR"
        case .activeCalories: "KCAL"
        case .respiratoryRate: "BR/MIN"
        }
    }

    /// Spoken unit for VoiceOver — never the abbreviation.
    var spokenUnit: String {
        switch self {
        case .restingHeartRate: "beats per minute"
        case .heartRateVariability: "milliseconds"
        case .steps: "steps"
        case .sleepDuration: "hours"
        case .activeCalories: "calories"
        case .respiratoryRate: "breaths per minute"
        }
    }

    /// Daily totals read as bars; sampled physiology reads as a line.
    var isCumulative: Bool {
        switch self {
        case .steps, .activeCalories, .sleepDuration: true
        case .restingHeartRate, .heartRateVariability, .respiratoryRate: false
        }
    }

    var chartKind: ChartKind { isCumulative ? .bar : .line }

    private var fractionDigits: Int {
        switch self {
        case .sleepDuration, .respiratoryRate, .heartRateVariability: 1
        case .restingHeartRate, .steps, .activeCalories: 0
        }
    }

    func formattedValue(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...fractionDigits)))
    }
}

/// One daily bucket: `day` is the calendar day start, `value` the bucket's
/// aggregate in the metric's display unit.
struct HealthTrendPoint: Equatable, Sendable {
    let day: Date
    let value: Double
}

struct HealthTrendSeries: Equatable, Sendable {
    let metric: HealthTrendMetric
    let points: [HealthTrendPoint]
}

// MARK: - Pure trends math

/// The pure half of the Health Trends screen (#125): window construction,
/// bucket alignment, the 7-day-vs-prior delta, downsampling, and ChartSpec
/// construction into the #100 pipeline. No HealthKit here — the live service
/// is thin plumbing over these.
enum HealthTrendsCore {

    /// Consecutive calendar-day starts ending on `reference`'s day. Calendar
    /// day arithmetic, never fixed 86 400 s strides — DST days are 23/25 h.
    static func dayStarts(days: Int, endingOn reference: Date, calendar: Calendar) -> [Date] {
        guard days > 0 else { return [] }
        let lastDay = calendar.startOfDay(for: reference)
        return (0..<days).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: lastDay)
        }
    }

    /// Normalizes enumerated statistics (period start, value) onto the window's
    /// day buckets: strays outside the window drop, days without data stay
    /// absent (sparse, not zero-filled), duplicate periods collapse to the
    /// latest value, output is day-ordered.
    static func alignedDailyPoints(
        statistics: [(start: Date, value: Double)],
        dayStarts: [Date],
        calendar: Calendar
    ) -> [HealthTrendPoint] {
        guard !dayStarts.isEmpty, !statistics.isEmpty else { return [] }
        let window = Set(dayStarts)
        var byDay: [Date: Double] = [:]
        for statistic in statistics {
            let day = calendar.startOfDay(for: statistic.start)
            guard window.contains(day) else { continue }
            byDay[day] = statistic.value
        }
        return byDay
            .map { HealthTrendPoint(day: $0.key, value: $0.value) }
            .sorted { $0.day < $1.day }
    }

    /// Daily asleep-hours buckets over the window, attributed to the day the
    /// sleep ends (the house rule from `HealthQueryCore`). Days without sleep
    /// stay absent.
    static func dailySleepPoints(
        intervals: [HealthQueryCore.SleepInterval],
        dayStarts: [Date],
        calendar: Calendar
    ) -> [HealthTrendPoint] {
        dayStarts.compactMap { day in
            HealthQueryCore.aggregateSleepDuration(intervals: intervals, attributedTo: day, calendar: calendar)
                .map { HealthTrendPoint(day: day, value: $0) }
        }
    }

    /// The card's trend annotation: mean of the most recent 7 days vs the mean
    /// of the 7 days before that, as a signed fraction (+0.04 = up 4%). Each
    /// window averages only the days that have data; nil when either window is
    /// empty or the baseline is zero (a percent of nothing is not a trend).
    static func weekOverWeekDelta(
        points: [HealthTrendPoint],
        endingOn reference: Date,
        calendar: Calendar
    ) -> Double? {
        let today = calendar.startOfDay(for: reference)
        guard
            let recentStart = calendar.date(byAdding: .day, value: -6, to: today),
            let priorStart = calendar.date(byAdding: .day, value: -7, to: recentStart),
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)
        else { return nil }

        let recent = points.filter { $0.day >= recentStart && $0.day < tomorrow }.map(\.value)
        let prior = points.filter { $0.day >= priorStart && $0.day < recentStart }.map(\.value)
        guard !recent.isEmpty, !prior.isEmpty else { return nil }

        let recentMean = recent.reduce(0, +) / Double(recent.count)
        let priorMean = prior.reduce(0, +) / Double(prior.count)
        guard priorMean != 0 else { return nil }
        return (recentMean - priorMean) / priorMean
    }

    /// Evenly strided reduction to `maxCount` points, endpoints preserved.
    /// With count > maxCount the stride is > 1, so picked indices are strictly
    /// increasing — no duplicates, order intact.
    static func downsampled(_ points: [HealthTrendPoint], maxCount: Int) -> [HealthTrendPoint] {
        guard maxCount > 1, points.count > maxCount else {
            return maxCount == 1 && !points.isEmpty ? [points[points.count - 1]] : points
        }
        let stride = Double(points.count - 1) / Double(maxCount - 1)
        return (0..<maxCount).map { points[Int((Double($0) * stride).rounded())] }
    }

    /// Builds the #100 ChartSpec for a series — downsampling FIRST, so an
    /// over-budget window renders reduced instead of failing the spec's
    /// point-budget validation. Nil only for an empty series (hidden card).
    static func chartSpec(
        for series: HealthTrendSeries,
        calendar: Calendar,
        locale: Locale = .current
    ) -> ChartSpec? {
        let points = downsampled(series.points, maxCount: ChartSpec.maxPointsPerSeries)
        guard !points.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("Md")

        return ChartSpec(
            kind: series.metric.chartKind,
            title: nil,
            xLabel: nil,
            xValues: points.map { formatter.string(from: $0.day) },
            yLabel: series.metric.unitLabel,
            series: [.init(name: series.metric.displayName, values: points.map(\.value))]
        )
    }

    /// One VoiceOver sentence per card: metric, range, latest value, and the
    /// trend direction when a baseline exists.
    static func cardAccessibilityLabel(
        for series: HealthTrendSeries,
        range: HealthTrendRange,
        endingOn reference: Date,
        calendar: Calendar
    ) -> String {
        var parts = ["\(series.metric.displayName), last \(range.days) days"]
        if let latest = series.points.last {
            parts.append("latest \(series.metric.formattedValue(latest.value)) \(series.metric.spokenUnit)")
        }
        if let delta = weekOverWeekDelta(points: series.points, endingOn: reference, calendar: calendar) {
            let percent = Int((abs(delta) * 100).rounded())
            parts.append("\(delta < 0 ? "down" : "up") \(percent) percent versus the prior week")
        }
        return parts.joined(separator: ", ")
    }
}
