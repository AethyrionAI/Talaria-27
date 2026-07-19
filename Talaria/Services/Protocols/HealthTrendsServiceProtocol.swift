import Foundation

/// Daily-bucketed trend queries for the Health Trends screen (#125).
@MainActor
protocol HealthTrendsServiceProtocol {
    /// One series per `HealthTrendMetric` that has ANY data in the window,
    /// day-bucketed oldest-first. Metrics with nothing to show — no samples,
    /// a denied read, or a scope the app never requested (HRV today) — are
    /// simply absent, which is what hides their cards.
    func trendSeries(range: HealthTrendRange) async -> [HealthTrendSeries]
}
