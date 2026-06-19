import Foundation
import WidgetKit

/// Timeline entry backed by the App Group shared data snapshot.
struct HermesWidgetEntry: TimelineEntry {
    let date: Date
    let data: HermesWidgetData

    static let placeholder = HermesWidgetEntry(
        date: .now,
        data: HermesWidgetData(
            hostName: "Hermes",
            hostOnline: true,
            lastMessagePreview: "Good morning! How can I help?",
            lastMessageSender: "assistant",
            lastMessageAt: .now,
            voiceSessionActive: false,
            steps: 4_230,
            activeCalories: 185,
            sleepHours: 7.4,
            heartRate: 68,
            updatedAt: .now
        )
    )
}

/// Reads the latest snapshot from the App Group shared container.
struct HermesTimelineProvider: TimelineProvider {
    private static let appGroupID: String = {
        if let custom = Bundle.main.object(forInfoDictionaryKey: "APP_GROUP_ID") as? String, !custom.isEmpty {
            return custom
        }
        return "group.org.aethyrion.talaria"
    }()
    private static let dataKey = "hermes.widget.data"

    func placeholder(in context: Context) -> HermesWidgetEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (HermesWidgetEntry) -> Void) {
        completion(HermesWidgetEntry(date: .now, data: readData()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HermesWidgetEntry>) -> Void) {
        let entry = HermesWidgetEntry(date: .now, data: readData())
        // Refresh every 15 minutes; immediate refreshes are triggered by
        // WidgetCenter.shared.reloadAllTimelines() in the main app.
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
        let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
        completion(timeline)
    }

    private func readData() -> HermesWidgetData {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID),
              let raw = defaults.data(forKey: Self.dataKey),
              let decoded = try? JSONDecoder().decode(HermesWidgetData.self, from: raw)
        else {
            return .empty
        }
        return decoded
    }
}
