import SwiftUI
import WidgetKit

/// Glanceable Hermes status — connection state, last message, voice indicator.
struct HermesStatusWidget: Widget {
    let kind = "HermesStatus"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HermesTimelineProvider()) { entry in
            HermesStatusView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(.systemBackground)
                }
        }
        .configurationDisplayName("Hermes Status")
        .description("Connection status and recent messages.")
        .supportedFamilies([
            .systemSmall,
            .accessoryCircular,
            .accessoryRectangular,
        ])
    }
}

// MARK: - Views

private struct HermesStatusView: View {
    let entry: HermesWidgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            systemSmallView
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        default:
            systemSmallView
        }
    }

    // MARK: - System Small (Home Screen)

    private var systemSmallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HermesBrandIcon(size: 22)
                Text("Hermes")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Circle()
                    .fill(entry.data.hostOnline ? .green : .gray)
                    .frame(width: 8, height: 8)
            }

            if entry.data.voiceSessionActive {
                Label("Voice Active", systemImage: "waveform")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }

            Spacer()

            if let preview = entry.data.lastMessagePreview {
                Text(preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            } else {
                Text(entry.data.hostOnline ? "Ready" : "Offline")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let messageAt = entry.data.lastMessageAt {
                Text(messageAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .widgetURL(URL(string: "hermes://chat"))
    }

    // MARK: - Accessory Circular (Lock Screen + CarPlay)

    private var circularView: some View {
        VStack(spacing: 2) {
            if entry.data.voiceSessionActive {
                Image(systemName: "waveform")
                    .font(.title3)
                    .widgetAccentable()
            } else {
                HermesBrandIcon(size: 18)
            }
            Circle()
                .fill(entry.data.hostOnline ? .green : .gray)
                .frame(width: 5, height: 5)
        }
        .widgetURL(URL(string: "hermes://chat"))
    }

    // MARK: - Accessory Rectangular (Lock Screen)

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                HermesBrandIcon(size: 14)
                Text("Hermes")
                    .font(.headline)
                Spacer()
                if entry.data.voiceSessionActive {
                    Image(systemName: "waveform")
                        .font(.caption2)
                        .widgetAccentable()
                }
            }

            if let preview = entry.data.lastMessagePreview {
                Text(preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text(entry.data.hostOnline ? "Ready" : "Offline")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .widgetURL(URL(string: "hermes://chat"))
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    HermesStatusWidget()
} timeline: {
    HermesWidgetEntry.placeholder
    HermesWidgetEntry(date: .now, data: .empty)
}

#Preview("Circular", as: .accessoryCircular) {
    HermesStatusWidget()
} timeline: {
    HermesWidgetEntry.placeholder
}

#Preview("Rectangular", as: .accessoryRectangular) {
    HermesStatusWidget()
} timeline: {
    HermesWidgetEntry.placeholder
}
