import SwiftUI
import WidgetKit

@main
struct HermesWidgetBundle: WidgetBundle {
    var body: some Widget {
        HermesLiveActivity()
        // AlarmKit countdown presentation (#16) — its own configuration typed
        // on AlarmAttributes, never a new case on the Hermes activity.
        TalariaAlarmLiveActivity()
        HermesStatusWidget()
        HermesHealthWidget()
        // Control Center / Lock Screen / Action-button controls (#7) —
        // WidgetBundleBuilder accepts ControlWidget alongside Widget (iOS 18).
        AskHermesControl()
        TalkToHermesControl()
    }
}
