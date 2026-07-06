import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

/// #16: Lock Screen / Dynamic Island presentation for Talaria-scheduled
/// AlarmKit countdown timers. A SEPARATE configuration typed on AlarmKit's own
/// `AlarmAttributes<TalariaAlarmMetadata>` — deliberately NOT a new case on
/// the Hermes activity (verified caveat: AlarmKit requires its own
/// ActivityConfiguration). Fixed-time alarms are presented by the system
/// alert; this activity carries the countdown phase.
struct TalariaAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<TalariaAlarmMetadata>.self) { context in
            lockScreenView(context)
                .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "alarm.fill")
                        .foregroundStyle(context.attributes.tintColor)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(alarmTitle(context))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    phaseText(context)
                        .font(.subheadline.monospacedDigit())
                }
            } compactLeading: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(context.attributes.tintColor)
            } compactTrailing: {
                phaseText(context)
                    .font(.caption2.monospacedDigit())
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(context.attributes.tintColor)
            }
        }
    }

    private func lockScreenView(_ context: ActivityViewContext<AlarmAttributes<TalariaAlarmMetadata>>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "alarm.fill")
                .font(.title3)
                .foregroundStyle(context.attributes.tintColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(alarmTitle(context))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                phaseText(context)
                    .font(.title3.monospacedDigit())
            }
            Spacer()
        }
    }

    private func alarmTitle(_ context: ActivityViewContext<AlarmAttributes<TalariaAlarmMetadata>>) -> String {
        if let label = context.attributes.metadata?.label, !label.isEmpty {
            return label
        }
        return "Hermes Timer"
    }

    /// Countdown renders as a live system timer; the ringing/paused phases
    /// fall back to static text. Tolerant switch — AlarmKit owns this enum.
    private func phaseText(_ context: ActivityViewContext<AlarmAttributes<TalariaAlarmMetadata>>) -> some View {
        Group {
            switch context.state.mode {
            case .countdown(let countdown):
                Text(timerInterval: Date.now ... countdown.fireDate, countsDown: true)
            case .paused:
                Text("Paused")
            default:
                Text("Ringing")
            }
        }
    }
}
