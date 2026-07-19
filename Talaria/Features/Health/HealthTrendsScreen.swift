import SwiftUI

/// Health Trends (#125): on-device daily-bucket trends over the
/// already-granted HealthKit metrics, rendered through the #100 chart
/// pipeline (`ChartCanvas` — the same plot the chat surface draws). Cards
/// exist only for metrics with data in the window; an empty window and a
/// missing grant each get an honest panel, never a zeroed chart.
struct HealthTrendsScreen: View {
    @Environment(AppContainer.self) private var container

    @State private var range: HealthTrendRange = .month
    @State private var loadedSeries: [HealthTrendSeries]?
    @State private var expandedChart: ExpandedChart?

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Design.Spacing.md) {
                    header
                    rangePicker
                    content
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)
            }
        }
        .navigationTitle("Health Trends")
        .toolbarBackground(.hidden, for: .navigationBar)
        .task(id: range) { await reload() }
        .fullScreenCover(item: $expandedChart) { expanded in
            ChartViewerScreen(spec: expanded.spec)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            MonoLabel(
                "ON-DEVICE · NO SERVER",
                size: 10,
                weight: .medium,
                tracking: Design.Tracking.monoWide,
                color: Design.Colors.mutedForeground
            )
            Text("Daily trends from Health data already on this phone. Only granted metrics appear.")
                .font(Design.Typography.callout)
                .foregroundStyle(Design.Colors.secondaryForeground)
        }
        .padding(.horizontal, Design.Spacing.xxs)
    }

    // MARK: - Range picker

    private var rangePicker: some View {
        HStack(spacing: Design.Spacing.xs) {
            ForEach(HealthTrendRange.allCases) { candidate in
                let isSelected = candidate == range
                Button {
                    range = candidate
                } label: {
                    MonoLabel(
                        candidate.displayLabel,
                        size: 11,
                        weight: .medium,
                        tracking: Design.Tracking.mono,
                        color: isSelected ? Design.Brand.accentBright : Design.Colors.mutedForeground
                    )
                    .padding(.horizontal, Design.Spacing.md)
                    .frame(minHeight: Design.Size.minTapTarget)
                    .background(
                        isSelected ? Design.Colors.accentTint(0.14) : .clear,
                        in: Capsule()
                    )
                    .overlay {
                        Capsule().strokeBorder(
                            isSelected ? Design.Colors.accentTint(0.6) : Design.Colors.hairline,
                            lineWidth: 1
                        )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Last \(candidate.days) days")
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if !isHealthAuthorized {
            statusPanel(
                title: "HEALTH ACCESS OFF",
                message: "Grant Health access from the Permissions screen to see trends."
            )
        } else if let loadedSeries {
            if loadedSeries.isEmpty {
                statusPanel(
                    title: "NO TREND DATA",
                    message: "Nothing recorded in the last \(range.days) days for the granted metrics."
                )
            } else {
                ForEach(loadedSeries, id: \.metric) { series in
                    TrendCard(series: series, range: range) { spec in
                        expandedChart = ExpandedChart(spec: spec)
                    }
                }
            }
        } else {
            HStack(spacing: Design.Spacing.sm) {
                ProgressView()
                MonoLabel("QUERYING HEALTH DATA", size: 10, weight: .medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Design.Spacing.xl)
        }
    }

    private func statusPanel(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            MonoLabel(title, size: 10, weight: .medium, color: Design.Brand.forge)
            Text(message)
                .font(Design.Typography.callout)
                .foregroundStyle(Design.Colors.secondaryForeground)
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPanel(
            cornerRadius: Design.CornerRadius.md,
            borderColor: Design.Colors.hairline,
            fill: Design.Colors.surface
        )
    }

    // MARK: - Data

    private var isHealthAuthorized: Bool {
        container.permissionsStore.capabilities
            .first { $0.permissionType == .health }?
            .status == .authorized
    }

    private func reload() async {
        guard isHealthAuthorized, let service = container.healthTrendsService else {
            loadedSeries = []
            return
        }
        loadedSeries = nil
        loadedSeries = await service.trendSeries(range: range)
    }
}

// MARK: - Trend card

private struct TrendCard: View {
    let series: HealthTrendSeries
    let range: HealthTrendRange
    let onExpand: (ChartSpec) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                MonoLabel(
                    series.metric.displayName,
                    size: 10,
                    weight: .medium,
                    tracking: Design.Tracking.monoWide,
                    color: Design.Colors.mutedForeground
                )
                Spacer()
                if let deltaText {
                    MonoLabel(
                        deltaText,
                        size: 10,
                        weight: .medium,
                        tracking: Design.Tracking.mono,
                        color: Design.Brand.accentBright
                    )
                }
            }

            if let latest = series.points.last {
                HStack(alignment: .firstTextBaseline, spacing: Design.Spacing.xxs) {
                    Text(series.metric.formattedValue(latest.value))
                        .font(Design.Typography.display(24, weight: .semibold, relativeTo: .title3))
                        .foregroundStyle(Design.Colors.foregroundBright)
                    MonoLabel(series.metric.unitLabel, size: 10, color: Design.Colors.mutedForeground)
                }
            }

            if let spec = HealthTrendsCore.chartSpec(for: series, calendar: Calendar.current) {
                Button {
                    onExpand(spec)
                } label: {
                    ChartCanvas(spec: spec, showsAxisTitles: false)
                        .frame(height: 160)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPanel(
            cornerRadius: Design.CornerRadius.md,
            borderColor: Design.Colors.accentTint(0.18),
            fill: Design.Colors.surface
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            HealthTrendsCore.cardAccessibilityLabel(
                for: series,
                range: range,
                endingOn: Date(),
                calendar: Calendar.current
            )
        )
    }

    /// "↑ 4%" vs the prior week — accent-tinted, never good/bad-colored:
    /// whether "up" is good depends on the metric, and the app doesn't guess.
    private var deltaText: String? {
        guard let delta = HealthTrendsCore.weekOverWeekDelta(
            points: series.points,
            endingOn: Date(),
            calendar: Calendar.current
        ) else { return nil }
        let percent = Int((abs(delta) * 100).rounded())
        return "\(delta < 0 ? "↓" : "↑") \(percent)%"
    }
}

/// Identifiable wrapper so a tapped chart can drive `fullScreenCover(item:)`
/// into the #100 fullscreen viewer.
private struct ExpandedChart: Identifiable {
    let id = UUID()
    let spec: ChartSpec
}
