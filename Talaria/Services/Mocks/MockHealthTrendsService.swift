import Foundation

/// Deterministic synthetic trends for previews and tests (#125) — no
/// HealthKit, no randomness (values derive from the day index). HRV and
/// respiratory rate are deliberately absent to exercise the hidden-card
/// path.
@MainActor
final class MockHealthTrendsService: HealthTrendsServiceProtocol {
    func trendSeries(range: HealthTrendRange) async -> [HealthTrendSeries] {
        let calendar = Calendar.current
        let dayStarts = HealthTrendsCore.dayStarts(days: range.days, endingOn: Date(), calendar: calendar)

        func series(_ metric: HealthTrendMetric, base: Double, swing: Double, period: Double) -> HealthTrendSeries {
            HealthTrendSeries(
                metric: metric,
                points: dayStarts.enumerated().map { index, day in
                    HealthTrendPoint(day: day, value: base + swing * sin(Double(index) / period))
                }
            )
        }

        return [
            series(.restingHeartRate, base: 58, swing: 4, period: 5),
            series(.steps, base: 8200, swing: 2600, period: 3),
            series(.sleepDuration, base: 7.2, swing: 1.1, period: 4),
            series(.activeCalories, base: 540, swing: 180, period: 6),
        ]
    }
}
