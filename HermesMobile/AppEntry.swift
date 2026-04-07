import SwiftUI
import UIKit

final class HermesAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Register for remote (silent push) notifications
        application.registerForRemoteNotifications()

        Task { @MainActor in
            await AppContainer.sharedDefault().handleSystemLaunch()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        Task { @MainActor in
            UserDefaults.standard.set(token, forKey: "hermes.apns.deviceToken")
            await AppContainer.sharedDefault().registerPushTokenIfNeeded(token)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Push token registration failed — this is normal on simulators
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Handle silent push: trigger sensor upload and conversation refresh
        Task { @MainActor in
            let container = AppContainer.sharedDefault()
            await container.handleAppDidBecomeActive()
            completionHandler(.newData)
        }
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
                    if newPhase == .active {
                        Task { await container.handleAppDidBecomeActive() }
                    }
                    // Note: voice sessions are NOT ended on background.
                    // The "audio" background mode keeps WebRTC alive so
                    // the user can continue talking while the app is
                    // backgrounded. The session ends only when the user
                    // explicitly closes the voice overlay.
                }
                .onOpenURL { url in
                    handleDeeplink(url)
                }
        }
    }

    private func handleDeeplink(_ url: URL) {
        guard url.scheme == "hermes" else { return }
        switch url.host {
        case "chat":
            container.router.activeSheet = nil
            container.router.popToRoot()
            container.router.selectedTab = .chat
        case "health":
            container.router.activeSheet = nil
            container.router.popToRoot()
            container.router.selectedTab = .chat
            container.router.navigate(to: .permissions)
        case "voice":
            container.router.isVoiceOverlayPresented = true
        default:
            break
        }
    }
}
