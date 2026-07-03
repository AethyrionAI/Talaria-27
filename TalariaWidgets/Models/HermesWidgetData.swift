import Foundation

/// Snapshot of app state shared between the main app and widget extension
/// via App Group UserDefaults. Updated by the main app whenever state changes;
/// read by widget timeline providers to render Home Screen and CarPlay widgets.
struct HermesWidgetData: Codable, Sendable {
    var hostName: String?
    var hostOnline: Bool = false
    var lastMessagePreview: String?
    var lastMessageSender: String?   // "assistant", "user", "system"
    var lastMessageAt: Date?
    var voiceSessionActive: Bool = false
    var steps: Int?
    var activeCalories: Int?
    var sleepHours: Double?
    var heartRate: Int?
    var updatedAt: Date = .now
    // Active app appearance (raw AppearanceTheme/AppearanceAccent values) so
    // widgets set to "Match App" can resolve the same ThemePalette. Optional -
    // absent in pre-theme snapshots, resolved as Deep Field x cyan.
    var appearanceTheme: String?
    var appearanceAccent: String?

    static let empty = HermesWidgetData()
}
