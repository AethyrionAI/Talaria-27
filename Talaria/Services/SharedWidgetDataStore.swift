import Foundation
import WidgetKit

/// Reads and writes `HermesWidgetData` to the App Group shared container.
/// The main app writes; the widget extension reads.
enum SharedWidgetDataStore {
    /// App Group identifier. Reads from the APP_GROUP_ID Info.plist key if set,
    /// otherwise falls back to the default. Self-hosted users who change their
    /// bundle identifier should set APP_GROUP_ID in their build settings or
    /// local xcconfig to match their App Group.
    static let appGroupID: String = {
        if let custom = Bundle.main.object(forInfoDictionaryKey: "APP_GROUP_ID") as? String, !custom.isEmpty {
            return custom
        }
        return "group.org.aethyrion.talaria"
    }()
    private static let dataKey = "hermes.widget.data"

    static func write(_ data: HermesWidgetData) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        defaults.set(encoded, forKey: dataKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func read() -> HermesWidgetData {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: dataKey),
              let decoded = try? JSONDecoder().decode(HermesWidgetData.self, from: data)
        else {
            return .empty
        }
        return decoded
    }

    /// #352: the app-side health feed is retired; the widget queries
    /// HealthKit itself each timeline pass and these snapshot fields were
    /// only its fallback. Nil fields render "—" — honest, where a
    /// months-stale step count would lie. Pure transform so the logic is
    /// unit-testable.
    static func clearingRetiredHealthMetrics(_ data: HermesWidgetData) -> HermesWidgetData {
        var cleared = data
        cleared.steps = nil
        cleared.activeCalories = nil
        cleared.sleepHours = nil
        cleared.heartRate = nil
        return cleared
    }

    /// App-Group wrapper; writes only when something actually changes so the
    /// per-launch call doesn't churn widget reloads.
    static func clearRetiredHealthMetrics() {
        let data = read()
        guard data.steps != nil || data.activeCalories != nil
            || data.sleepHours != nil || data.heartRate != nil else { return }
        write(clearingRetiredHealthMetrics(data))
    }
}
