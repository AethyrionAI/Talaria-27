import Charts
import SwiftUI

/// Inline render surface for a `MarkdownSegment.chart` (OPEN_ITEMS #100):
/// a HUD panel matching `MarkdownTableView`'s framing, with the chart at a
/// fixed sane height so it never fights `LazyVStack` for intrinsic size.
/// Colors resolve live from the theme palette — never a hardcoded hex.
struct ChartSegmentView: View {
    let spec: ChartSpec

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            if let title = spec.title {
                MonoLabel(title.uppercased(), size: 10, weight: .medium)
            }
            ChartCanvas(spec: spec, showsAxisTitles: false)
                .frame(height: 180)
        }
        .padding(Design.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPanel(
            cornerRadius: Design.CornerRadius.md,
            borderColor: Design.Colors.accentTint(0.18),
            fill: Design.Colors.surface
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spec.accessibilitySummary)
    }
}

// MARK: - Chart canvas

/// The Swift Charts plot shared by the inline panel and the fullscreen
/// viewer. Points are plotted by index (not category) so ordering is the
/// spec's, duplicate x labels can't collide, and dense series get thinned
/// axis marks for free; labels map back through `xValues`. No animation is
/// attached anywhere — a chart draws once, whole (the parser guarantees it
/// only exists for closed, decoded fences).
struct ChartCanvas: View {
    let spec: ChartSpec
    let showsAxisTitles: Bool

    var body: some View {
        let names = spec.seriesDisplayNames

        Chart {
            ForEach(spec.series.indices, id: \.self) { seriesIndex in
                seriesMarks(seriesIndex: seriesIndex, name: names[seriesIndex])
            }
        }
        .chartForegroundStyleScale(domain: names, range: seriesColors)
        .chartLegend(spec.series.count > 1 ? .visible : .hidden)
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(Design.Colors.accentTint(0.12))
                AxisTick().foregroundStyle(Design.Colors.accentTint(0.25))
                AxisValueLabel {
                    if let index = value.as(Int.self), spec.xValues.indices.contains(index) {
                        Text(spec.xValues[index])
                            .font(Design.Typography.monoSmall)
                            .foregroundStyle(Design.Colors.mutedForeground)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(Design.Colors.accentTint(0.12))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(number.formatted(.number.notation(.compactName).precision(.fractionLength(0...1))))
                            .font(Design.Typography.monoSmall)
                            .foregroundStyle(Design.Colors.mutedForeground)
                    }
                }
            }
        }
        .chartXAxisLabel(showsAxisTitles ? (spec.xLabel ?? "") : "")
        .chartYAxisLabel(showsAxisTitles ? (spec.yLabel ?? "") : "")
    }

    @ChartContentBuilder
    private func seriesMarks(seriesIndex: Int, name: String) -> some ChartContent {
        let values = spec.series[seriesIndex].values
        let xTitle = spec.xLabel ?? "x"
        let yTitle = spec.yLabel ?? "y"

        ForEach(values.indices, id: \.self) { pointIndex in
            switch spec.kind {
            case .line:
                LineMark(
                    x: .value(xTitle, pointIndex),
                    y: .value(yTitle, values[pointIndex])
                )
                .foregroundStyle(by: .value("Series", name))

            case .bar:
                BarMark(
                    x: .value(xTitle, pointIndex),
                    y: .value(yTitle, values[pointIndex])
                )
                .foregroundStyle(by: .value("Series", name))

            case .area:
                AreaMark(
                    x: .value(xTitle, pointIndex),
                    y: .value(yTitle, values[pointIndex])
                )
                .foregroundStyle(by: .value("Series", name))
                .opacity(0.7)

            case .point:
                PointMark(
                    x: .value(xTitle, pointIndex),
                    y: .value(yTitle, values[pointIndex])
                )
                .foregroundStyle(by: .value("Series", name))
            }
        }
    }

    /// Series colors cycle the theme's own hues (hero, bright, deep, forge),
    /// dimmed on the second pass — derived from the palette, never a rainbow.
    private var seriesColors: [Color] {
        let base = [Design.Brand.accent, Design.Brand.accentBright, Design.Brand.accentDeep, Design.Brand.forge]
        return spec.series.indices.map { index in
            index < base.count ? base[index % base.count] : base[index % base.count].opacity(0.55)
        }
    }
}

// MARK: - Fullscreen viewer

/// Fullscreen chart presentation — the `.chart` twin of `ImageViewerScreen`,
/// reached the same way (tap the inline surface, `fullScreenCover`).
struct ChartViewerScreen: View {
    let spec: ChartSpec

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: Design.Spacing.md) {
                if let title = spec.title {
                    Text(title)
                        .font(Design.Typography.body(20, weight: .bold, relativeTo: .title2))
                        .foregroundStyle(Design.Colors.foregroundBright)
                }
                ChartCanvas(spec: spec, showsAxisTitles: true)
                    .frame(maxHeight: 480)
            }
            .padding(Design.Spacing.lg)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spec.accessibilitySummary)
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Design.Colors.foregroundBright)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Close chart")
            .padding()
        }
        .statusBarHidden(true)
    }
}

// MARK: - Chartable table (Path B)

/// A pipe table whose numeric shape promoted to a `ChartSpec`
/// (`ChartSpec.promoted`): renders the normal table with a small toggle to
/// flip it into a chart, no model cooperation needed. The toggle is ephemeral
/// view state — a re-parse (new segment identity) resets to the table, which
/// is the honest default.
struct ChartableTableView: View {
    let header: [String]
    let alignments: [MarkdownTableAlignment]
    let rows: [[String]]
    let textColor: Color
    let spec: ChartSpec
    /// Tap-through on the chart form, wired to the fullscreen viewer.
    let onExpand: (ChartSpec) -> Void

    @State private var showChart = false

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
            if showChart {
                Button { onExpand(spec) } label: {
                    ChartSegmentView(spec: spec)
                }
                .buttonStyle(.plain)
            } else {
                MarkdownTableView(
                    header: header,
                    alignments: alignments,
                    rows: rows,
                    textColor: textColor
                )
            }

            Button {
                showChart.toggle()
            } label: {
                HStack(spacing: Design.Spacing.xxs) {
                    Image(systemName: showChart ? "tablecells" : "chart.bar.xaxis")
                        .font(.system(size: 10, weight: .medium))
                    Text(showChart ? "TABLE" : "CHART")
                        .font(Design.Typography.monoTiny)
                }
                .foregroundStyle(showChart ? Design.Brand.accent : Design.Colors.mutedForeground)
                .padding(.horizontal, Design.Spacing.xs)
                .padding(.vertical, 3)
                .overlay {
                    Capsule().strokeBorder(Design.Colors.accentTint(0.25), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showChart ? "Show as table" : "Show as chart")
        }
    }
}
