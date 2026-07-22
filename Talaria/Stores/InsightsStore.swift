import Foundation

/// #156d — state for the Insights screen (D3): the fetched session window,
/// its aggregation, and load/error state. No caching beyond memory, no
/// polling — fetch on appear + pull-to-refresh, same posture as Tasks and
/// Skills. Owns the same hard rule as `SkillsStore`: **errors never replace
/// content that already exists** — a failed refresh with numbers on screen
/// keeps the numbers and only surfaces the message.
@MainActor
@Observable
final class InsightsStore {
    private let service: any InsightsServiceProtocol

    private(set) var rows: [SessionStatsRow] = []
    /// Aggregated once per successful fetch — never recomputed per render
    /// (the window can be 600 rows).
    private(set) var summary: InsightsSummary?
    /// True when the page cap cut the window short — drives the "showing
    /// the N most recent sessions" banner.
    private(set) var isTruncated = false
    private(set) var isLoading = false
    /// True once ANY fetch has succeeded — distinguishes "the host has no
    /// sessions" from "nothing loaded yet".
    private(set) var hasLoaded = false
    private(set) var lastErrorMessage: String?
    /// When the on-screen numbers were last actually fetched — rendered as
    /// "as of HH:mm" so a load-time snapshot is never presented as live.
    private(set) var lastRefreshedAt: Date?

    init(service: any InsightsServiceProtocol) {
        self.service = service
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let fetch = try await service.fetchRecentSessions()
            rows = fetch.rows
            summary = InsightsSummary.summarize(fetch.rows)
            isTruncated = fetch.isTruncated
            hasLoaded = true
            lastRefreshedAt = Date()
            lastErrorMessage = nil
        } catch {
            // Existing numbers stay on screen; only the message updates.
            lastErrorMessage = Self.message(for: error)
        }
    }

    private nonisolated static func message(for error: Error) -> String {
        if let serviceError = error as? InsightsServiceError {
            return serviceError.errorDescription ?? "The Hermes host request failed."
        }
        let described = error.localizedDescription
        return described.isEmpty ? "The Hermes host request failed." : described
    }
}
