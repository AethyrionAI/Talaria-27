import SwiftUI
import UIKit

final class HermesAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Task { @MainActor in
            await AppContainer.sharedDefault().handleSystemLaunch()
        }
        return true
    }
}

@main
struct HermesMobileApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(HermesAppDelegate.self) private var appDelegate
    @State private var container = AppContainer.sharedDefault()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(container)
                .environment(container.router)
                .environment(container.sessionStore)
                .environment(container.pairingStore)
                .environment(container.hostStore)
                .environment(container.chatStore)
                .environment(container.inboxStore)
                .environment(container.permissionsStore)
                .environment(container.settingsStore)
                .environment(container.talkStore)
                .task { await container.initialize() }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    Task { await container.handleAppDidBecomeActive() }
                }
        }
    }
}
