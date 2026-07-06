import SwiftUI
import WidgetKit

@main
struct HermesWidgetBundle: WidgetBundle {
    var body: some Widget {
        HermesLiveActivity()
        HermesStatusWidget()
        HermesHealthWidget()
        // Control Center / Lock Screen / Action-button controls (#7) —
        // WidgetBundleBuilder accepts ControlWidget alongside Widget (iOS 18).
        AskHermesControl()
        TalkToHermesControl()
    }
}
