import SwiftUI
import UIKit
import UserNotifications
import os

private let appDelegateLog = Logger(subsystem: "org.aethyrion.talaria", category: "AppDelegate")

/// #47: lock-screen reply. Relay completion pushes carry this category
/// (`send_run_completion_push` in relay/app/main.py — identifiers must stay
/// in lockstep), and the category attaches a text-input Reply action so a
/// push becomes a conversation without unlocking into the app.
enum NotificationReplyAction {
    static let categoryIdentifier = "HERMES_RUN_COMPLETED"
    static let actionIdentifier = "HERMES_REPLY"

    static var category: UNNotificationCategory {
        let reply = UNTextInputNotificationAction(
            identifier: actionIdentifier,
            title: "Reply",
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Message Hermes"
        )
        return UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [reply],
            intentIdentifiers: [],
            options: []
        )
    }
}

/// Lane J (J-2): Talaria is a single-window app, by decision — the store
/// layer (`ChatStore`/`AppContainer`) has never been audited for concurrent
/// scene observation, so a second chat window must not exist yet.
///
/// `UIApplicationSupportsMultipleScenes` must stay `true` in the scene
/// manifest: CarPlay's template scene connects alongside the device window
/// and needs it. But that same key is what makes iPadOS offer "New Window" /
/// Stage Manager "+" for the app. The narrowest refusal that keeps CarPlay
/// intact: watch `UIScene.willConnectNotification`, and when an app window
/// scene connects while another app window scene is already connected, ask
/// the system to destroy the new session immediately. CarPlay scenes are
/// `CPTemplateApplicationScene` (not `UIWindowScene`) and pass untouched;
/// deliberately NOT implemented via
/// `application(_:configurationForConnecting:options:)`, which would sit in
/// the middle of SwiftUI's WindowGroup scene attachment and the manifest's
/// CarPlay config resolution.
@MainActor
enum SingleWindowPolicy {
    /// Selector-based (not block-based) observer: the block API hands the
    /// Notification to a @Sendable closure, which makes it task-isolated and
    /// un-sendable into a MainActor hop under Swift 6 region isolation. A
    /// plain @objc method parameter has no such isolation; UIKit posts scene
    /// notifications on the main thread, so the assumeIsolated hop is sound.
    private final class Watcher: NSObject {
        @objc func sceneWillConnect(_ note: Notification) {
            guard let scene = note.object as? UIWindowScene else { return }
            MainActor.assumeIsolated {
                guard scene.session.role == .windowApplication else { return }
                let hasOtherAppWindow = UIApplication.shared.connectedScenes.contains {
                    $0 !== scene && $0 is UIWindowScene && $0.session.role == .windowApplication
                }
                guard hasOtherAppWindow else { return }
                appDelegateLog.notice("SingleWindowPolicy: refusing second app window scene")
                UIApplication.shared.requestSceneSessionDestruction(scene.session, options: nil, errorHandler: nil)
            }
        }
    }

    private static let watcher = Watcher()
    private static var active = false

    static func activate() {
        guard !active else { return }
        active = true
        NotificationCenter.default.addObserver(
            watcher,
            selector: #selector(Watcher.sceneWillConnect(_:)),
            name: UIScene.willConnectNotification,
            object: nil
        )
    }
}

final class HermesAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // If the app was previously killed while a Live Activity was active,
        // the OS can still show that stale activity. Clear any orphaned Hermes
        // activities immediately on launch; real active sessions will recreate
        // or adopt an activity once state is restored.
        LiveActivityService.endAllActivities()

        // Lane J (J-2): refuse second app windows on iPad; see SingleWindowPolicy.
        SingleWindowPolicy.activate()

        // Register for remote (silent push) notifications
        application.registerForRemoteNotifications()

        // #14: the BGAppRefreshTask launch handler must be registered before
        // the app finishes launching; scheduling happens on background entry.
        BackgroundRefreshScheduler.register()
        // Receive notification taps + foreground presentation
        UNUserNotificationCenter.current().delegate = self
        // #47: register the Reply category at every launch — including
        // scene-less background ones — so the long-press action exists
        // before the first completion push arrives.
        UNUserNotificationCenter.current().setNotificationCategories([NotificationReplyAction.category])

        Task { @MainActor in
            await AppContainer.sharedDefault().handleSystemLaunch()
        }
        return true
    }

    // MARK: - UNUserNotificationCenterDelegate

    // Show banner + sound even when the app is in the foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // User tapped a notification. Remote completion pushes carry `session_id`
    // (set by the relay's run-completion watcher); local completion
    // notifications don't. Route to chat, open the pushed session when named,
    // and reconcile so the finished reply is fetched.
    //
    // Async delegate variant: the system awaits this method and keeps the
    // (possibly scene-less) process alive for its whole duration — exactly the
    // ordering the #47 reply path needs, with no completion handler to send
    // across an isolation boundary (Swift 6 region-based data-race safety).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let sessionID = response.notification.request.content.userInfo["session_id"] as? String

        // #47: a typed reply from the notification's text-input action.
        // Headless — no scene mounts. Awaiting the send before returning is
        // what keeps the process alive (the background-task assertion inside
        // buys the rest of the window).
        if response.actionIdentifier == NotificationReplyAction.actionIdentifier,
           let textResponse = response as? UNTextInputNotificationResponse {
            await AppContainer.sharedDefault().handleNotificationReply(textResponse.userText, sessionID: sessionID)
            return
        }

        await AppContainer.sharedDefault().handleNotificationTap(sessionID: sessionID)
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
                .environment(container.speechOutput)
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
                        // #14: arm the native background-refresh safety net
                        // alongside the relay app-state report.
                        BackgroundRefreshScheduler.schedule()
                        Task { await container.reportAppStateIfNeeded("background") }
                        Task {
                            await container.reportAppStateIfNeeded("background")
                            // Walking away mid-run: hand the completion notify
                            // off to the relay's APNs watcher (#38), since the
                            // in-app reconcile loop can't tick while suspended.
                            await container.watchPendingRunIfNeeded()
                        }
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
        case "session":
            // #17: hermes://session/{id} — Spotlight results route here via
            // OpenSessionIntent. Lands on Chat, then adopts the session.
            guard url.pathComponents.count > 1 else { break }
            let sessionID = url.pathComponents[1]
            container.router.activeSheet = nil
            container.router.popToRoot()
            container.router.selectedTab = .chat
            Task { await container.chatStore.openSession(sessionID) }
        case "health":
            container.router.activeSheet = nil
            container.router.popToRoot()
            container.router.selectedTab = .chat
            container.router.navigate(to: .permissions)
        case "voice":
            // Same flag StartVoiceSessionIntent sets; the Talk to Hermes
            // control (#7) launches through this link. Clear any sheet first —
            // MainTabView presentations can't overlap (parity with the intent).
            container.router.activeSheet = nil
            container.router.isVoiceOverlayPresented = true
        case "ask":
            // #48: hermes://ask?q=… — the payload-carrying route. Lands on
            // Chat and seeds the composer; the user still taps send. Never
            // auto-sends: custom-scheme URLs are open to any app or web page,
            // and an auto-send would let external content inject agent turns.
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "q" })?
                .value ?? ""
            container.router.activeSheet = nil
            container.router.popToRoot()
            container.router.selectedTab = .chat
            container.chatStore.seedComposer(query)
        default:
            break
        }
    }
}
