import Foundation
import Testing
@testable import Talaria

/// #156d D5 — the aggregation model is the lane's real test surface: totals
/// math, source/model splits, the counted-but-not-summed rule for nil-usage
/// sessions, cost-presence gating (0.0 and null both suppress), and the
/// screen's number formatting.
struct InsightsAggregationTests {

    private func row(
        id: String,
        model: String? = nil,
        source: String? = nil,
        messages: Int? = nil,
        usage: SessionUsage? = nil
    ) -> SessionStatsRow {
        SessionStatsRow(id: id, model: model, source: source, messageCount: messages, usage: usage)
    }

    // MARK: - Totals

    @Test func totalsSumAcrossSessions() {
        let summary = InsightsSummary.summarize([
            row(id: "a", messages: 10, usage: SessionUsage(
                inputTokens: 1_000, outputTokens: 200, cacheReadTokens: 50,
                cacheWriteTokens: 25, reasoningTokens: 5, apiCallCount: 3, toolCallCount: 7)),
            row(id: "b", messages: 4, usage: SessionUsage(
                inputTokens: 500, outputTokens: 100, cacheReadTokens: 10,
                cacheWriteTokens: 5, reasoningTokens: 1, apiCallCount: 2, toolCallCount: 1)),
        ])
        let totals = summary.totals
        #expect(totals.sessionCount == 2)
        #expect(totals.messageCount == 14)
        #expect(totals.usageSessionCount == 2)
        #expect(totals.inputTokens == 1_500)
        #expect(totals.outputTokens == 300)
        #expect(totals.cacheReadTokens == 60)
        #expect(totals.cacheWriteTokens == 30)
        #expect(totals.reasoningTokens == 6)
        #expect(totals.apiCallCount == 5)
        #expect(totals.toolCallCount == 8)
    }

    /// The binding rule: a usage-less session counts toward session/message
    /// tallies and contributes NOTHING to token math.
    @Test func nilUsageSessionsCountButNeverSum() {
        let summary = InsightsSummary.summarize([
            row(id: "a", messages: 6, usage: SessionUsage(inputTokens: 100, outputTokens: 40)),
            row(id: "b", messages: 9, usage: nil),
        ])
        let totals = summary.totals
        #expect(totals.sessionCount == 2)
        #expect(totals.messageCount == 15)
        #expect(totals.usageSessionCount == 1)
        #expect(totals.inputTokens == 100)
        #expect(totals.outputTokens == 40)
    }

    @Test func emptyWindowSummarizesToZeroes() {
        let summary = InsightsSummary.summarize([])
        #expect(summary.totals.sessionCount == 0)
        #expect(summary.totals.usageSessionCount == 0)
        #expect(summary.totals.estimatedCostUSD == nil)
        #expect(summary.bySource.isEmpty)
        #expect(summary.byModel.isEmpty)
    }

    // MARK: - Cost gating

    /// Rule 3 in numbers: null and 0.0 both mean "not computed" — only
    /// present-and-positive rows sum, and the result says how many that was.
    @Test func costSumsOnlyPresentNonzeroRows() {
        let summary = InsightsSummary.summarize([
            row(id: "a", usage: SessionUsage(inputTokens: 1, estimatedCostUSD: 0.0)),
            row(id: "b", usage: SessionUsage(inputTokens: 1, estimatedCostUSD: nil, actualCostUSD: nil)),
            row(id: "c", usage: SessionUsage(inputTokens: 1, estimatedCostUSD: 1.5)),
            row(id: "d", usage: SessionUsage(inputTokens: 1, estimatedCostUSD: 0.25)),
            row(id: "e", usage: nil),
        ])
        #expect(summary.totals.estimatedCostUSD == 1.75)
        #expect(summary.totals.costSessionCount == 2)
        #expect(summary.totals.sessionCount == 5)
    }

    @Test func actualCostPreferredOverEstimatePerRow() {
        let summary = InsightsSummary.summarize([
            row(id: "a", usage: SessionUsage(estimatedCostUSD: 9.0, actualCostUSD: 2.0)),
        ])
        #expect(summary.totals.estimatedCostUSD == 2.0)
    }

    /// A literal 0 actual reads as "not computed", not "free" — the positive
    /// estimate still carries (the `SessionCostReadout.cost` precedence).
    @Test func zeroActualFallsThroughToPositiveEstimate() {
        let summary = InsightsSummary.summarize([
            row(id: "a", usage: SessionUsage(estimatedCostUSD: 0.75, actualCostUSD: 0.0)),
        ])
        #expect(summary.totals.estimatedCostUSD == 0.75)
        #expect(summary.totals.costSessionCount == 1)
    }

    @Test func allSuppressedCostsLeaveNilNotZero() {
        let summary = InsightsSummary.summarize([
            row(id: "a", usage: SessionUsage(inputTokens: 5, estimatedCostUSD: 0.0)),
            row(id: "b", usage: SessionUsage(inputTokens: 5)),
        ])
        #expect(summary.totals.estimatedCostUSD == nil)
        #expect(summary.totals.costSessionCount == 0)
    }

    // MARK: - Splits

    @Test func slicesBucketBySourceAndModelWithShares() {
        let summary = InsightsSummary.summarize([
            row(id: "a", model: "sonnet", source: "api_server",
                usage: SessionUsage(inputTokens: 600, outputTokens: 0)),
            row(id: "b", model: "sonnet", source: "api_server",
                usage: SessionUsage(inputTokens: 100, outputTokens: 100)),
            row(id: "c", model: "opus", source: "discord",
                usage: SessionUsage(inputTokens: 150, outputTokens: 50)),
        ])
        // Heaviest token share first.
        #expect(summary.bySource.map(\.label) == ["api_server", "discord"])
        #expect(summary.bySource.map(\.sessionCount) == [2, 1])
        #expect(summary.bySource.map(\.tokens) == [800, 200])
        #expect(summary.bySource[0].share == 0.8)
        #expect(summary.bySource[1].share == 0.2)

        #expect(summary.byModel.map(\.label) == ["sonnet", "opus"])
        #expect(summary.byModel.map(\.tokens) == [800, 200])
    }

    @Test func missingLabelsBucketAsUnknownAndNilUsageAddsSessionsOnly() {
        let summary = InsightsSummary.summarize([
            row(id: "a", model: nil, source: "  ",
                usage: SessionUsage(inputTokens: 100, outputTokens: 0)),
            row(id: "b", model: "opus", source: "tui", usage: nil),
        ])
        let unknown = summary.bySource.first { $0.label == InsightsSummary.unknownLabel }
        #expect(unknown?.sessionCount == 1)
        #expect(unknown?.tokens == 100)
        let tui = summary.bySource.first { $0.label == "tui" }
        #expect(tui?.sessionCount == 1)
        #expect(tui?.tokens == 0)
    }

    /// No bucket can honestly claim a slice of nothing: a window with zero
    /// token data carries nil shares, never divide-by-zero or 0%.
    @Test func sharesAreNilWhenWindowHasNoTokenData() {
        let summary = InsightsSummary.summarize([
            row(id: "a", source: "api_server", usage: nil),
            row(id: "b", source: "discord", usage: nil),
        ])
        #expect(summary.bySource.count == 2)
        #expect(summary.bySource.allSatisfy { $0.share == nil })
    }

    @Test func tieBreaksAreDeterministicByLabel() {
        let summary = InsightsSummary.summarize([
            row(id: "a", source: "zeta", usage: SessionUsage(inputTokens: 100)),
            row(id: "b", source: "alpha", usage: SessionUsage(inputTokens: 100)),
        ])
        #expect(summary.bySource.map(\.label) == ["alpha", "zeta"])
    }

    // MARK: - Readout formatting

    /// "—" while nothing is knowable, a real 0 once any session reported
    /// usage, the canonical abbreviation above that.
    @Test func tileTextGatesOnUsagePresence() {
        #expect(InsightsReadout.tileText(0, usageSessionCount: 0) == "—")
        #expect(InsightsReadout.tileText(500, usageSessionCount: 0) == "—")
        #expect(InsightsReadout.tileText(0, usageSessionCount: 3) == "0")
        #expect(InsightsReadout.tileText(356, usageSessionCount: 3) == "356")
        #expect(InsightsReadout.tileText(66_400, usageSessionCount: 3) == "66.4k")
        #expect(InsightsReadout.tileText(2_400_000, usageSessionCount: 3) == "2.4m")
    }

    @Test func shareTextRoundsWholeAndMarksSubPercent() {
        #expect(InsightsReadout.shareText(nil) == nil)
        #expect(InsightsReadout.shareText(0) == nil)
        #expect(InsightsReadout.shareText(0.42) == "42%")
        #expect(InsightsReadout.shareText(0.004) == "<1%")
        #expect(InsightsReadout.shareText(1.0) == "100%")
    }

    @Test func costTextOmitsUnlessPositive() {
        #expect(InsightsReadout.costText(InsightsSummary.Totals()) == nil)
        var zeroed = InsightsSummary.Totals()
        zeroed.estimatedCostUSD = 0
        #expect(InsightsReadout.costText(zeroed) == nil)
        var real = InsightsSummary.Totals()
        real.estimatedCostUSD = 1.239
        #expect(InsightsReadout.costText(real) == "~$1.24")
        var subCent = InsightsSummary.Totals()
        subCent.estimatedCostUSD = 0.004
        #expect(InsightsReadout.costText(subCent) == "~<$0.01")
    }

    @Test func durationTextPicksTheRightGranularity() {
        #expect(InsightsReadout.durationText(0) == nil)
        #expect(InsightsReadout.durationText(-5) == nil)
        #expect(InsightsReadout.durationText(42) == "42s")
        #expect(InsightsReadout.durationText(192) == "3m 12s")
        #expect(InsightsReadout.durationText(3_840) == "1h 04m")
    }
}
