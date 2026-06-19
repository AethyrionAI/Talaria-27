import SwiftUI
import WidgetKit

@main
struct HermesWidgetBundle: WidgetBundle {
    var body: some Widget {
        HermesLiveActivity()
        HermesStatusWidget()
        HermesHealthWidget()
    }
}
