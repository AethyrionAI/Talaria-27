import SwiftUI
import WidgetKit

// #126: latest-briefing widget — pre-derived title + first line from the
// app-group snapshot, deep-linking into the in-app briefing detail.
struct HermesBriefingWidget: Widget {
    let kind = "HermesBriefing"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: HermesWidgetConfigurationIntent.self,
            provider: HermesTimelineProvider()
        ) { entry in
            HermesBriefingView(entry: entry)
                .containerBackground(for: .widget) { WidgetEntryThemeBackground(entry: entry) }
        }
        .configurationDisplayName("Daily Briefing")
        .description("The latest briefing from Hermes.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct HermesBriefingView: View {
    let entry: HermesWidgetEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = entry.palette(for: colorScheme)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "sunrise.fill")
                    .font(.caption)
                    .foregroundStyle(palette.forge)
                Text("BRIEFING")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(palette.mutedForeground)
                Spacer()
                if let receivedAt = entry.data.briefingReceivedAt {
                    Text(receivedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(palette.mutedForeground)
                }
            }

            if let title = entry.data.briefingTitle {
                Text(title)
                    .font(family == .systemSmall ? .subheadline.weight(.semibold) : .headline)
                    .foregroundStyle(palette.foreground)
                    .lineLimit(2)

                if let firstLine = entry.data.briefingFirstLine, !firstLine.isEmpty {
                    Text(firstLine)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryForeground)
                        .lineLimit(family == .systemSmall ? 2 : 3)
                }
                Spacer(minLength: 0)
            } else {
                Spacer()
                // Real data only: no briefing has ever arrived — say so.
                Text("No briefing yet")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryForeground)
                Spacer()
            }
        }
        .widgetURL(URL(string: "hermes://briefing"))
    }
}
