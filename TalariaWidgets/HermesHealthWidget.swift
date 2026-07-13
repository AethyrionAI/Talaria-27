import SwiftUI
import WidgetKit

/// Health metrics grid — steps, calories, sleep, heart rate. Renders with the
/// configured widget theme; metric icons keep their semantic system colors
/// (they read on all four theme backgrounds).
struct HermesHealthWidget: Widget {
    let kind = "HermesHealth"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: HermesWidgetConfigurationIntent.self,
            provider: HermesTimelineProvider(queriesHealthKit: true)
        ) { entry in
            HermesHealthView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetEntryThemeBackground(entry: entry)
                }
        }
        .configurationDisplayName("Hermes Health")
        .description("Daily health metrics at a glance.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Views

private struct HermesHealthView: View {
    let entry: HermesWidgetEntry
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = entry.palette(for: colorScheme)
        return VStack(spacing: 8) {
            HStack {
                WidgetOrbGlyph(palette: palette, size: 16)
                Text("Hermes Health")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.foreground)
                Spacer()
                Text(entry.data.updatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(palette.mutedForeground)
            }

            HStack(spacing: 12) {
                metricCard(
                    icon: "figure.walk",
                    color: .green,
                    label: "Steps",
                    value: entry.data.steps.map { formatNumber($0) } ?? "--",
                    palette: palette
                )
                metricCard(
                    icon: "flame.fill",
                    color: .orange,
                    label: "Calories",
                    value: entry.data.activeCalories.map { formatNumber($0) } ?? "--",
                    palette: palette
                )
                metricCard(
                    icon: "bed.double.fill",
                    color: .indigo,
                    label: "Sleep",
                    value: entry.data.sleepHours.map { String(format: "%.1fh", $0) } ?? "--",
                    palette: palette
                )
                metricCard(
                    icon: "heart.fill",
                    color: .red,
                    label: "Heart",
                    value: entry.data.heartRate.map { "\($0)" } ?? "--",
                    palette: palette
                )
            }
        }
        .widgetURL(URL(string: "hermes://health"))
    }

    private func metricCard(icon: String, color: Color, label: String, value: String, palette: ThemePalette) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(palette.foreground)
            Text(label)
                .font(.caption2)
                .foregroundStyle(palette.secondaryForeground)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1000 {
            return String(format: "%.1fk", Double(n) / 1000.0)
        }
        return "\(n)"
    }
}

// MARK: - Previews

#Preview("Medium", as: .systemMedium) {
    HermesHealthWidget()
} timeline: {
    HermesWidgetEntry.placeholder
    HermesWidgetEntry(date: .now, data: .empty)
    HermesWidgetEntry(date: .now, data: .empty, widgetTheme: .terminal)
    HermesWidgetEntry(date: .now, data: .empty, widgetTheme: .paperTape)
}
