import AlarmKit
import Foundation

/// Metadata attached to Talaria-scheduled AlarmKit alarms (#16). Compiled into
/// BOTH targets via the `Shared` sources entries in project.yml: the app
/// schedules alarms with it, and the widget extension's countdown Live
/// Activity renders `AlarmAttributes<TalariaAlarmMetadata>`.
struct TalariaAlarmMetadata: AlarmMetadata {
    /// Optional user-facing label from the `/alarm` argument tail
    /// (e.g. "/alarm 25m tea" → "tea").
    let label: String?

    init(label: String? = nil) {
        self.label = label
    }
}
