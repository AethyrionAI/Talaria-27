import ActivityKit
import Foundation

/// Shared attributes for Hermes Live Activities.
/// Used by both the main app (to start/update activities) and the widget extension (to render them).
struct HermesActivityAttributes: ActivityAttributes {
    /// Static data — set once when the activity starts.
    struct ContentState: Codable, Hashable {
        var status: String            // "Listening", "Thinking", "Working on that…"
        var toolName: String?         // e.g., "hermes_delegate", "vision_analyze"
        var elapsedSeconds: Int       // seconds since activity started
        var sessionType: String       // "voice", "chat", "tool"
    }

    /// Immutable for the lifetime of the activity.
    var agentName: String = "Hermes"
}
