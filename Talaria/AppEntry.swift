import SwiftUI
import UIKit
import os

private let appDelegateLog = Logger(subsystem: "org.aethyrion.talaria", category: "AppDelegate")

final class HermesAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // If the app was previously killed while a Live Activity was active,
        // the OS can still show that stale activity. Clear any orphaned Hermes
        // activities immediately on launch; real active sessions will recreate
        // or adopt an activity once state is restored.
        LiveActivityService.endAllActivities()

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
        appDelegateLog.notice("APNs device token delivered")
        Task { @MainActor in
            UserDefaults.standard.set(token, forKey: AppContainer.apnsTokenDefaultsKey)
            await AppContainer.sharedDefault().registerPushTokenIfNeeded(token)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Normal on simulators; on-device it means no token was issued this
        // launch (e.g. missing aps-environment entitlement or no network).
        appDelegateLog.notice("APNs registration failed: \(error.localizedDescription, privacy: .public)")
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Handle silent push without marking the app foreground.
        Task { @MainActor in
            let container = AppContainer.sharedDefault()
            await container.handleRemoteNotificationWake()
            completionHandler(.newData)
        }
    }
}

@main
struct TalariaApp: App {
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
                .environment(ThemeRuntime.shared)
                .task { await container.initialize() }
                .onChange(of: container.settingsStore.settings) { oldSettings, newSettings in
                    // Mirror the appearance prefs into the runtime theme so the
                    // whole app re-skins live (theme / accent / glow / grid /
                    // reduce-motion).
                    ThemeRuntime.shared.apply(newSettings)
                    // Push the new appearance to "Match App" widgets (write +
                    // timeline reload). Only on theme/accent changes — not for
                    // every settings mutation (e.g. glow-slider drags).
                    if oldSettings.effectiveAppearanceTheme() != newSettings.effectiveAppearanceTheme()
                        || oldSettings.appearanceAccent != newSettings.appearanceAccent {
                        container.updateWidgetData()
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        // Re-resolve automatic (seasonal) theme on foreground so a
                        // season rollover applies without a relaunch (issue #24).
                        // No-op in manual mode.
                        ThemeRuntime.shared.apply(container.settingsStore.settings)
                        Task { await container.handleAppDidBecomeActive() }
                    } else if newPhase == .background {
                        Task { await container.reportAppStateIfNeeded("background") }
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
