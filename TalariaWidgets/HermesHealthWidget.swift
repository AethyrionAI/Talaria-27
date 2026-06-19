import SwiftUI
import WidgetKit

/// Health metrics grid — steps, calories, sleep, heart rate.
struct HermesHealthWidget: Widget {
    let kind = "HermesHealth"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HermesTimelineProvider()) { entry in
            HermesHealthView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(.systemBackground)
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

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                HermesBrandIcon(size: 16)
                Text("Hermes Health")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(entry.data.updatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 12) {
                metricCard(
                    icon: "figure.walk",
                    color: .green,
                    label: "Steps",
                    value: entry.data.steps.map { formatNumber($0) } ?? "--"
                )
                metricCard(
                    icon: "flame.fill",
                    color: .orange,
                    label: "Calories",
                    value: entry.data.activeCalories.map { formatNumber($0) } ?? "--"
                )
                metricCard(
                    icon: "bed.double.fill",
                    color: .indigo,
                    label: "Sleep",
                    value: entry.data.sleepHours.map { String(format: "%.1fh", $0) } ?? "--"
                )
                metricCard(
                    icon: "heart.fill",
                    color: .red,
                    label: "Heart",
                    value: entry.data.heartRate.map { "\($0)" } ?? "--"
                )
            }
        }
        .widgetURL(URL(string: "hermes://health"))
    }

    private func metricCard(icon: String, color: Color, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
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
}
