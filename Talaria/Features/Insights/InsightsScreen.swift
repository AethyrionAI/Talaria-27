import SwiftUI

/// #156d D3 — read-only usage panel: what the agent has been doing and
/// roughly what it costs, over an explicitly labeled recency window. Joins
/// Tasks and Skills as the third agent surface with the same content-state
/// grammar (loading / error+retry / empty / loaded; a failed refresh with
/// numbers on screen keeps the numbers and surfaces the error as a strip).
///
/// Every figure here is **activity and billing volume** (#25 settled law):
/// session token totals are cumulative across API calls and grow
/// superlinearly, so nothing on this screen frames them against a model
/// limit — the CTX gauge is a separate, already-correct surface and the two
/// must never appear to disagree. Honest absence throughout: a session
/// without usage data renders no numbers, a cost that is null or 0.0 renders
/// no cost element at all. Numbers-only by design — the #100 chart pipeline
/// is a chat-fence plot and does not drop in for share bars ("no second
/// chart impl" is standing law).
struct InsightsScreen: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            if let store = container.insightsStore {
                InsightsContent(store: store, hostLabel: hostLabel)
            } else {
                notConfiguredState
            }
        }
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    /// The window banner's host: the active profile's name — same scope as
    /// Tasks and Skills (active profile only, no cross-host aggregation).
    private var hostLabel: String? {
        let name = container.profilesStore?.activeProfile?.name
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? nil : name
    }

    /// Bare containers (tests) construct no store; a real launch always has
    /// one. Honest state, no mock data.
    private var notConfiguredState: some View {
        ContentUnavailableView {
            Label {
                Text("Insights Unavailable")
                    .font(Design.Typography.sectionTitle)
                    .foregroundStyle(Design.Colors.foregroundBright)
            } icon: {
                Image(systemName: "chart.bar.xaxis")
                    .foregroundStyle(Design.Brand.forge)
            }
        } description: {
            MonoLabel(
                "NO HERMES HOST CONFIGURED",
                size: 10,
                weight: .regular,
                tracking: Design.Tracking.monoWide,
                color: Design.Colors.mutedForeground
            )
        }
    }
}

private struct InsightsContent: View {
    let store: InsightsStore
    let hostLabel: String?

    @State private var expandedSessionIDs: Set<String> = []

    var body: some View {
        Group {
            if store.rows.isEmpty {
                // Scrollable so pull-to-refresh works from every empty
                // state, not just the loaded list.
                ScrollView {
                    Group {
                        if store.isLoading, !store.hasLoaded {
                            loadingState
                        } else if let message = store.lastErrorMessage, !store.hasLoaded {
                            errorState(message)
                        } else {
                            emptyState
                        }
                    }
                    .containerRelativeFrame([.horizontal, .vertical])
                }
            } else {
                statsList
            }
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
    }

    // MARK: - Loaded layout

    private var statsList: some View {
        ScrollView {
            VStack(spacing: 0) {
                header

                if store.isTruncated {
                    truncationStrip
                        .padding(.top, Design.Spacing.sm)
                }

                if let message = store.lastErrorMessage {
                    refreshFailedStrip(message)
                        .padding(.top, Design.Spacing.sm)
                }

                if let summary = store.summary {
                    totalsStrip(summary)
                        .padding(.top, Design.Spacing.md)

                    if let costText = InsightsReadout.costText(summary.totals) {
                        costCard(costText, totals: summary.totals)
                            .padding(.top, Design.Spacing.sm)
                    }

                    breakdownSection(title: "BY SOURCE", slices: summary.bySource)
                        .padding(.top, Design.Spacing.md)
                    breakdownSection(title: "BY MODEL", slices: summary.byModel)
                        .padding(.top, Design.Spacing.md)
                }

                sessionsSection
                    .padding(.top, Design.Spacing.md)
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.sm)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            Text("INSIGHTS")
                .font(Design.Typography.screenTitle2)
                .tracking(Design.Tracking.display)
                .foregroundStyle(Design.Colors.foregroundBright)

            HStack(spacing: Design.Spacing.xs) {
                StatusPip(color: Design.Brand.accent, diameter: 7)
                MonoLabel(
                    windowBanner,
                    size: 11,
                    weight: .medium,
                    tracking: Design.Tracking.monoWide,
                    color: Design.Colors.secondaryForeground
                )
                .hudSingleLine()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, Design.Spacing.md)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Design.Colors.hairline)
                .frame(height: 1)
        }
    }

    /// The scope of every number on this screen, on screen — never implied:
    /// "LAST 214 SESSIONS · OJAMD · AS OF 14:32".
    private var windowBanner: String {
        var parts = ["LAST \(store.rows.count) SESSION\(store.rows.count == 1 ? "" : "S")"]
        if let hostLabel { parts.append(hostLabel) }
        if let refreshedAt = store.lastRefreshedAt {
            parts.append("AS OF \(refreshedAt.formatted(date: .omitted, time: .shortened))")
        }
        return parts.joined(separator: " · ")
    }

    /// The page cap cut the crawl short — say so rather than letting totals
    /// read as all-time.
    private var truncationStrip: some View {
        HStack(spacing: Design.Spacing.xs) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Design.Colors.mutedForeground)
            MonoLabel(
                "SHOWING THE \(store.rows.count) MOST RECENT SESSIONS",
                size: 9,
                weight: .medium,
                tracking: Design.Tracking.mono,
                color: Design.Colors.mutedForeground
            )
            Spacer(minLength: 0)
        }
        .padding(Design.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPanel(cornerRadius: Design.CornerRadius.md, borderColor: Design.Colors.hairline)
    }

    /// The non-destructive failure surface: numbers stay, the strip explains.
    private func refreshFailedStrip(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Design.Spacing.xs) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Design.Brand.forge)
            VStack(alignment: .leading, spacing: 2) {
                MonoLabel("REFRESH FAILED — SHOWING LAST FETCH", size: 9,
                          weight: .medium, tracking: Design.Tracking.mono,
                          color: Design.Brand.forge)
                Text(message)
                    .font(Design.Typography.body(12))
                    .foregroundStyle(Design.Colors.secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Design.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPanel(cornerRadius: Design.CornerRadius.md, borderColor: Design.Brand.forge.opacity(0.4))
    }

    // MARK: - Totals

    private func totalsStrip(_ summary: InsightsSummary) -> some View {
        let totals = summary.totals
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                totalTile("TOKENS IN",
                          InsightsReadout.tileText(totals.inputTokens,
                                                   usageSessionCount: totals.usageSessionCount))
                tileDivider
                totalTile("TOKENS OUT",
                          InsightsReadout.tileText(totals.outputTokens,
                                                   usageSessionCount: totals.usageSessionCount))
            }
            Rectangle()
                .fill(Design.Colors.divider)
                .frame(height: 1)
            HStack(spacing: 0) {
                totalTile("TOOL CALLS",
                          InsightsReadout.tileText(totals.toolCallCount,
                                                   usageSessionCount: totals.usageSessionCount))
                tileDivider
                totalTile("API CALLS",
                          InsightsReadout.tileText(totals.apiCallCount,
                                                   usageSessionCount: totals.usageSessionCount))
            }
        }
        .hudPanel(cornerRadius: Design.CornerRadius.md, borderColor: Design.Colors.hairline)
    }

    private var tileDivider: some View {
        Rectangle()
            .fill(Design.Colors.divider)
            .frame(width: 1)
    }

    private func totalTile(_ caption: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
            MonoLabel(caption, size: 9, weight: .medium,
                      tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)
            Text(value.uppercased())
                .font(Design.Typography.display(20, weight: .semibold, relativeTo: .title3))
                .foregroundStyle(Design.Colors.foregroundBright)
                .hudSingleLine()
        }
        .padding(Design.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Cost only ever appears here as an estimate over the sessions that
    /// actually carry one ("hides rather than lies" — rule 3).
    ///
    /// #169 — its OWN card, not a row inside the totals card. The coverage
    /// caveat belongs to the cost figure alone; the four totals above cover
    /// every fetched session. Sharing a card made "COVERS 21 OF 230" read as
    /// a footnote on the whole panel — a factually wrong reading of correct
    /// data that understated the totals by an order of magnitude (device pass
    /// #171, and it caught the author of the screen, not a stranger). The
    /// separation makes the caveat's scope structural rather than
    /// typographic; the wording carries the scope too, so a future re-nest
    /// cannot silently reintroduce the misread.
    private func costCard(_ costText: String, totals: InsightsSummary.Totals) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Design.Spacing.xs) {
            MonoLabel("EST COST", size: 9, weight: .medium,
                      tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)
            Spacer(minLength: Design.Spacing.xs)
            VStack(alignment: .trailing, spacing: 2) {
                Text(costText)
                    .font(Design.Typography.display(17, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(Design.Colors.foregroundBright)
                if let coverage = InsightsReadout.costCoverageText(totals) {
                    MonoLabel(
                        coverage,
                        size: 8,
                        tracking: Design.Tracking.mono,
                        color: Design.Colors.dimForeground
                    )
                    .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(Design.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPanel(cornerRadius: Design.CornerRadius.md, borderColor: Design.Colors.hairline)
    }

    // MARK: - Breakdowns

    private func breakdownSection(title: String, slices: [InsightsSummary.Slice]) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            MonoLabel(title, size: 9, weight: .medium,
                      tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)
            VStack(spacing: 0) {
                ForEach(Array(slices.enumerated()), id: \.element.id) { index, slice in
                    if index > 0 {
                        Rectangle()
                            .fill(Design.Colors.divider)
                            .frame(height: 1)
                    }
                    sliceRow(slice)
                }
            }
            .hudPanel(cornerRadius: Design.CornerRadius.md, borderColor: Design.Colors.hairline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sliceRow(_ slice: InsightsSummary.Slice) -> some View {
        HStack(alignment: .center, spacing: Design.Spacing.xs) {
            Text(slice.label)
                .font(Design.Typography.body(13, weight: .medium))
                .foregroundStyle(Design.Colors.foregroundBright)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: Design.Spacing.xs)
            VStack(alignment: .trailing, spacing: 2) {
                if let tokens = InsightsReadout.sliceTokenText(slice.tokens) {
                    MonoLabel(
                        [InsightsReadout.shareText(slice.share), "\(tokens) TOK"]
                            .compactMap { $0 }.joined(separator: " · "),
                        size: 10,
                        weight: .medium,
                        tracking: Design.Tracking.mono,
                        color: Design.Colors.secondaryForeground
                    )
                }
                MonoLabel(
                    "\(slice.sessionCount) SESSION\(slice.sessionCount == 1 ? "" : "S")",
                    size: 8,
                    tracking: Design.Tracking.mono,
                    color: Design.Colors.dimForeground
                )
            }
        }
        .padding(Design.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Session list

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            MonoLabel("SESSIONS", size: 9, weight: .medium,
                      tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)
            LazyVStack(spacing: Design.Spacing.sm) {
                ForEach(store.rows) { row in
                    SessionStatsRowView(
                        row: row,
                        isExpanded: expandedSessionIDs.contains(row.id)
                    ) {
                        withAnimation(Design.Motion.standard) {
                            if expandedSessionIDs.contains(row.id) {
                                expandedSessionIDs.remove(row.id)
                            } else {
                                expandedSessionIDs.insert(row.id)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Empty states

    private var loadingState: some View {
        VStack(spacing: Design.Spacing.md) {
            ProgressView()
                .tint(Design.Brand.accent)
            MonoLabel(
                "FETCHING SESSION STATS",
                size: 10,
                weight: .regular,
                tracking: Design.Tracking.monoWide,
                color: Design.Colors.mutedForeground
            )
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: Design.Spacing.md) {
            ContentUnavailableView {
                Label {
                    Text("Insights Unreachable")
                        .font(Design.Typography.sectionTitle)
                        .foregroundStyle(Design.Colors.foregroundBright)
                } icon: {
                    Image(systemName: "wifi.exclamationmark")
                        .foregroundStyle(Design.Brand.forge)
                }
            } description: {
                Text(message)
                    .font(Design.Typography.body(13))
                    .foregroundStyle(Design.Colors.mutedForeground)
            }
            GhostButton(title: "Retry", systemImage: "arrow.clockwise", height: 44) {
                Task { await store.refresh() }
            }
            .frame(maxWidth: 200)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label {
                Text("No Sessions Yet")
                    .font(Design.Typography.sectionTitle)
                    .foregroundStyle(Design.Colors.foregroundBright)
            } icon: {
                Image(systemName: "chart.bar.xaxis")
                    .foregroundStyle(Design.Brand.accent)
            }
        } description: {
            MonoLabel(
                "NO SESSIONS RECORDED ON THIS HOST",
                size: 10,
                weight: .regular,
                tracking: Design.Tracking.monoWide,
                color: Design.Colors.mutedForeground
            )
        }
    }
}

// MARK: - Session row

/// Collapsed: title, source badge + model + relative recency, and the usage
/// line when the row honestly has one. Expanded: duration, cache/reasoning
/// tokens, message count, cost if present — in place; three-and-a-bit fields
/// do not earn a screen, and there is deliberately no navigation into chat.
private struct SessionStatsRowView: View {
    let row: SessionStatsRow
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                HStack(alignment: .center, spacing: Design.Spacing.xs) {
                    Text(row.displayTitle)
                        .font(Design.Typography.body(14, weight: .medium))
                        .foregroundStyle(Design.Colors.foregroundBright)
                        .lineLimit(1)
                    Spacer(minLength: Design.Spacing.xs)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Design.Colors.dimForeground)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }

                metaLine

                if let usageLine {
                    MonoLabel(usageLine, size: 9, weight: .medium,
                              tracking: Design.Tracking.mono,
                              color: Design.Colors.secondaryForeground)
                }

                if isExpanded {
                    expandedDetail
                        .padding(.top, Design.Spacing.xxs)
                }
            }
            .padding(Design.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .hudPanel(cornerRadius: Design.CornerRadius.md, borderColor: Design.Colors.divider)
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel(row.displayTitle)
        .accessibilityHint(isExpanded ? "Collapses the session details" : "Expands the session details")
    }

    private var metaLine: some View {
        HStack(spacing: Design.Spacing.xs) {
            if let source = trimmedNonEmpty(row.source) {
                MonoLabel(source, size: 8, weight: .medium,
                          tracking: Design.Tracking.mono,
                          color: Design.Colors.secondaryForeground)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Design.Colors.chipSurface,
                                in: RoundedRectangle(cornerRadius: Design.CornerRadius.sm))
                    .overlay {
                        RoundedRectangle(cornerRadius: Design.CornerRadius.sm)
                            .strokeBorder(Design.Colors.chipBorder, lineWidth: 1)
                    }
            }
            if let model = trimmedNonEmpty(row.model) {
                MonoLabel(model, size: 9,
                          tracking: Design.Tracking.mono,
                          color: Design.Colors.mutedForeground)
                    .hudSingleLine()
            }
            Spacer(minLength: 0)
            if let recency = row.recency {
                MonoLabel(recency.formatted(.relative(presentation: .named)),
                          size: 9,
                          tracking: Design.Tracking.mono,
                          color: Design.Colors.dimForeground)
            }
        }
    }

    /// "IN 66.4K · OUT 1.2K · 5 TOOLS" — only segments the row honestly
    /// carries; a usage-less session renders no line at all.
    private var usageLine: String? {
        guard let usage = row.usage else { return nil }
        var parts: [String] = []
        if let text = SessionCostReadout.positiveTokenText(usage.inputTokens) {
            parts.append("IN \(text)")
        }
        if let text = SessionCostReadout.positiveTokenText(usage.outputTokens) {
            parts.append("OUT \(text)")
        }
        if let count = usage.toolCallCount, count > 0 {
            parts.append("\(count) TOOL\(count == 1 ? "" : "S")")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var expandedDetail: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
            if let duration = row.duration,
               let text = InsightsReadout.durationText(duration) {
                detailLine("DURATION", text)
            }
            if let text = SessionCostReadout.positiveTokenText(row.usage?.cacheReadTokens) {
                detailLine("CACHE READ", text)
            }
            if let text = SessionCostReadout.positiveTokenText(row.usage?.cacheWriteTokens) {
                detailLine("CACHE WRITE", text)
            }
            if let text = SessionCostReadout.positiveTokenText(row.usage?.reasoningTokens) {
                detailLine("REASONING", text)
            }
            if let count = row.messageCount, count > 0 {
                detailLine("MESSAGES", InsightsReadout.groupedText(count))
            }
            if let usage = row.usage {
                let (costText, estimated) = SessionCostReadout.cost(for: usage)
                if let costText {
                    detailLine("COST", (estimated ? "~" : "") + costText)
                }
            }
            if detailIsEmpty {
                // Real data only — say the detail is absent.
                MonoLabel("NO USAGE DATA RECORDED", size: 9,
                          tracking: Design.Tracking.mono,
                          color: Design.Colors.dimForeground)
            }
        }
    }

    private func detailLine(_ caption: String, _ value: String) -> some View {
        HStack(spacing: Design.Spacing.xs) {
            MonoLabel(caption, size: 9,
                      tracking: Design.Tracking.mono,
                      color: Design.Colors.mutedForeground)
            Spacer(minLength: Design.Spacing.xs)
            MonoLabel(value, size: 9, weight: .medium,
                      tracking: Design.Tracking.mono,
                      color: Design.Colors.foreground)
        }
    }

    /// True when the expanded panel would show nothing — the one honest
    /// filler line replaces silence.
    private var detailIsEmpty: Bool {
        row.duration == nil
            && SessionCostReadout.positiveTokenText(row.usage?.cacheReadTokens) == nil
            && SessionCostReadout.positiveTokenText(row.usage?.cacheWriteTokens) == nil
            && SessionCostReadout.positiveTokenText(row.usage?.reasoningTokens) == nil
            && (row.messageCount ?? 0) <= 0
            && (row.usage.map { SessionCostReadout.cost(for: $0).text } ?? nil) == nil
    }

    private func trimmedNonEmpty(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
