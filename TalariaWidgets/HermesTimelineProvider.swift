import Foundation
import HealthKit
import SwiftUI
import WidgetKit

/// Timeline entry backed by the App Group shared data snapshot, plus the
/// per-widget theme choice from the configuration intent.
struct HermesWidgetEntry: TimelineEntry {
    let date: Date
    let data: HermesWidgetData
    var widgetTheme: WidgetTheme = .matchApp

    /// Palette resolved for this entry (widget theme → shared tables). The
    /// scheme drives the adaptive Comic Book matchApp resolution (Lane L
    /// Phase 2) — pass the view's own `@Environment(\.colorScheme)`.
    func palette(for colorScheme: ColorScheme) -> ThemePalette {
        widgetTheme.resolvedPalette(data: data, colorScheme: colorScheme)
    }

    static let placeholder = HermesWidgetEntry(
        date: .now,
        data: HermesWidgetData(
            hostName: "Hermes",
            hostOnline: true,
            lastMessagePreview: "Good morning! How can I help?",
            lastMessageSender: "assistant",
            lastMessageAt: .now,
            lastMessageSummary: "Good morning! How can I help?",
            voiceSessionActive: false,
            steps: 4_230,
            activeCalories: 185,
            sleepHours: 7.4,
            heartRate: 68,
            updatedAt: .now,
            briefingTitle: "Morning briefing — Sun Jul 20",
            briefingFirstLine: "Sleep 7h 24m · 3 events today · clear until 3pm",
            briefingReceivedAt: .now
        )
    )
}

/// Reads the latest snapshot from the App Group shared container and carries
/// the widget's configured theme into each entry.
struct HermesTimelineProvider: AppIntentTimelineProvider {
    private static let appGroupID: String = {
        if let custom = Bundle.main.object(forInfoDictionaryKey: "APP_GROUP_ID") as? String, !custom.isEmpty {
            return custom
        }
        return "group.org.aethyrion.talaria"
    }()
    private static let dataKey = "hermes.widget.data"

    /// When true (the health widget), each timeline pass refreshes the four
    /// tile metrics straight from HealthKit instead of trusting the app-written
    /// snapshot (#15) — tiles stay current even when the app hasn't run
    /// recently. The snapshot remains the fallback when queries come back empty.
    var queriesHealthKit = false

    func placeholder(in context: Context) -> HermesWidgetEntry {
        .placeholder
    }

    func snapshot(for configuration: HermesWidgetConfigurationIntent, in context: Context) async -> HermesWidgetEntry {
        HermesWidgetEntry(date: .now, data: readData(), widgetTheme: configuration.theme)
    }

    func timeline(for configuration: HermesWidgetConfigurationIntent, in context: Context) async -> Timeline<HermesWidgetEntry> {
        var data = readData()
        if queriesHealthKit {
            data = await refreshingHealthMetrics(data)
        }
        let entry = HermesWidgetEntry(date: .now, data: data, widgetTheme: configuration.theme)
        // Refresh every 15 minutes; immediate refreshes are triggered by
        // WidgetCenter.shared.reloadAllTimelines() in the main app.
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

    /// Overlays live HealthKit values onto the snapshot. Falls back to the
    /// snapshot untouched when every query comes back empty — a denied read
    /// authorization is indistinguishable from no data by design, and a locked
    /// device (`errorDatabaseInaccessible`) errors out every query, so both
    /// land here WITHOUT any auth check (the #16 gotcha; authorization is only
    /// ever requested in the main app — widgets can't prompt).
    private func refreshingHealthMetrics(_ snapshot: HermesWidgetData) async -> HermesWidgetData {
        guard let live = await HealthQueryCore.loadWidgetMetrics(), !live.isEmpty else {
            return snapshot
        }
        var data = snapshot
        data.steps = live.steps ?? data.steps
        data.activeCalories = live.activeCalories ?? data.activeCalories
        data.sleepHours = live.sleepHours ?? data.sleepHours
        data.heartRate = live.heartRate ?? data.heartRate
        data.updatedAt = .now
        return data
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
