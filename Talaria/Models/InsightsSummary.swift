import Foundation

/// #156d D2 — pure aggregation over the fetched session window. All math
/// lives here so it is fully unit-testable without a view or a network.
///
/// The honesty rules (#25, binding):
/// - A session with `usage == nil` counts toward session/message tallies and
///   its slice's session count, but contributes NOTHING to token math —
///   `usageSessionCount` is the tiles' gate between "—" (nothing knowable)
///   and a real 0.
/// - Cost sums ONLY rows with a present-and-positive cost (actual preferred,
///   else estimate — the same precedence `SessionCostReadout.cost` ships);
///   0.0 and null both mean "not computed", never "free". The total is
///   always labeled an estimate, and `costSessionCount` says how much of the
///   window it actually covers.
/// - Everything here is billing/activity volume. Nothing is a context
///   meter, and nothing may be divided by a model's limit.
struct InsightsSummary: Equatable, Sendable {
    struct Totals: Equatable, Sendable {
        var sessionCount = 0
        var messageCount = 0
        /// Sessions whose row carried any usage block at all.
        var usageSessionCount = 0
        var inputTokens = 0
        var outputTokens = 0
        var cacheReadTokens = 0
        var cacheWriteTokens = 0
        var reasoningTokens = 0
        var apiCallCount = 0
        var toolCallCount = 0
        /// Nil when no row carried a positive cost — the strip omits the
        /// element entirely rather than rendering a confident $0.00.
        var estimatedCostUSD: Double?
        /// How many sessions the cost figure actually covers.
        var costSessionCount = 0
    }

    /// One by-source or by-model bucket: counts plus this bucket's share of
    /// the window's summed (input + output) tokens. `share` is nil when the
    /// whole window has no token data (no bucket can honestly claim a slice
    /// of nothing).
    struct Slice: Equatable, Sendable, Identifiable {
        let label: String
        var sessionCount: Int
        var tokens: Int
        var share: Double?

        var id: String { label }
    }

    let totals: Totals
    let bySource: [Slice]
    let byModel: [Slice]

    static let unknownLabel = "unknown"

    static func summarize(_ rows: [SessionStatsRow]) -> InsightsSummary {
        var totals = Totals()
        var sourceBuckets: [String: (sessions: Int, tokens: Int)] = [:]
        var modelBuckets: [String: (sessions: Int, tokens: Int)] = [:]

        for row in rows {
            totals.sessionCount += 1
            totals.messageCount += row.messageCount ?? 0

            var rowTokens = 0
            if let usage = row.usage {
                totals.usageSessionCount += 1
                totals.inputTokens += usage.inputTokens ?? 0
                totals.outputTokens += usage.outputTokens ?? 0
                totals.cacheReadTokens += usage.cacheReadTokens ?? 0
                totals.cacheWriteTokens += usage.cacheWriteTokens ?? 0
                totals.reasoningTokens += usage.reasoningTokens ?? 0
                totals.apiCallCount += usage.apiCallCount ?? 0
                totals.toolCallCount += usage.toolCallCount ?? 0
                rowTokens = (usage.inputTokens ?? 0) + (usage.outputTokens ?? 0)
                if let cost = resolvedCost(usage) {
                    totals.estimatedCostUSD = (totals.estimatedCostUSD ?? 0) + cost
                    totals.costSessionCount += 1
                }
            }

            let sourceKey = normalizedLabel(row.source)
            let modelKey = normalizedLabel(row.model)
            sourceBuckets[sourceKey, default: (0, 0)].sessions += 1
            sourceBuckets[sourceKey, default: (0, 0)].tokens += rowTokens
            modelBuckets[modelKey, default: (0, 0)].sessions += 1
            modelBuckets[modelKey, default: (0, 0)].tokens += rowTokens
        }

        return InsightsSummary(
            totals: totals,
            bySource: slices(from: sourceBuckets),
            byModel: slices(from: modelBuckets)
        )
    }

    /// The one cost a row may contribute: a positive actual, else a positive
    /// estimate, else nothing (same precedence as `SessionCostReadout.cost`;
    /// numeric because this side sums before formatting).
    static func resolvedCost(_ usage: SessionUsage) -> Double? {
        if let actual = usage.actualCostUSD, actual > 0 { return actual }
        if let estimate = usage.estimatedCostUSD, estimate > 0 { return estimate }
        return nil
    }

    private static func normalizedLabel(_ raw: String?) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? unknownLabel : trimmed
    }

    /// Buckets → display order: heaviest token share first, then more
    /// sessions, then label (case-insensitive) so ties are deterministic.
    private static func slices(
        from buckets: [String: (sessions: Int, tokens: Int)]
    ) -> [Slice] {
        let tokenTotal = buckets.values.reduce(0) { $0 + $1.tokens }
        return buckets
            .map { label, bucket in
                Slice(
                    label: label,
                    sessionCount: bucket.sessions,
                    tokens: bucket.tokens,
                    share: tokenTotal > 0 ? Double(bucket.tokens) / Double(tokenTotal) : nil
                )
            }
            .sorted { lhs, rhs in
                if lhs.tokens != rhs.tokens { return lhs.tokens > rhs.tokens }
                if lhs.sessionCount != rhs.sessionCount { return lhs.sessionCount > rhs.sessionCount }
                let ordering = lhs.label.caseInsensitiveCompare(rhs.label)
                if ordering != .orderedSame { return ordering == .orderedAscending }
                return lhs.label < rhs.label
            }
    }
}

// MARK: - Display strings

/// The screen's number formatting, pure and tested. Token/count abbreviation
/// delegates to `SessionCostReadout.positiveTokenText` — the canonical
/// (already unit-tested) "66.4k"/"2.4m" formatter — never a second one.
enum InsightsReadout {
    /// A totals tile: "—" while the window holds no usage data at all
    /// (nothing knowable ≠ zero), a real "0" once any session reported
    /// usage, abbreviated above that.
    static func tileText(_ count: Int, usageSessionCount: Int) -> String {
        guard usageSessionCount > 0 else { return "—" }
        return SessionCostReadout.positiveTokenText(count) ?? "0"
    }

    /// A slice's token figure: absent data renders nothing (the row keeps
    /// its session count only).
    static func sliceTokenText(_ tokens: Int) -> String? {
        SessionCostReadout.positiveTokenText(tokens)
    }

    /// Whole-percent share of the window's tokens: "42%", with a real but
    /// sub-half-percent share shown as "<1%" instead of rounding to a lie.
    static func shareText(_ share: Double?) -> String? {
        guard let share, share > 0 else { return nil }
        let percent = Int((share * 100).rounded())
        return percent < 1 ? "<1%" : "\(min(percent, 100))%"
    }

    /// The gated cost figure for the strip: nil unless the summary carries a
    /// positive total (rule 3 — omit, never $0.00). Always estimate-marked.
    static func costText(_ totals: InsightsSummary.Totals) -> String? {
        guard let cost = totals.estimatedCostUSD, cost > 0 else { return nil }
        return "~" + SessionCostReadout.costLabel(cost)
    }

    /// "12,847" — plain grouped integer for message/session tallies (these
    /// stay exact; only token/call volumes abbreviate).
    static func groupedText(_ count: Int) -> String {
        count.formatted(.number.grouping(.automatic))
    }

    /// Compact wall-clock span for an expanded row: "3m 12s", "1h 04m".
    static func durationText(_ interval: TimeInterval) -> String? {
        guard interval > 0 else { return nil }
        let total = Int(interval.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%dh %02dm", hours, minutes) }
        if minutes > 0 { return String(format: "%dm %02ds", minutes, seconds) }
        return "\(seconds)s"
    }
}
