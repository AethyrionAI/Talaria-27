import CoreSpotlight
import SwiftUI
import UIKit
import os

private let appDelegateLog = Logger(subsystem: "org.aethyrion.talaria", category: "AppDelegate")

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

@MainActor
// #147: `@preconcurrency` on the notification-center conformance is what
// lets the @MainActor `didReceive` witness below satisfy the nonisolated
// protocol requirement — without it, Swift 6 region isolation rejects
// parameters into a main-actor-isolated implementation. The system delivers
// these delegate callbacks on the main thread, so the dynamic isolation
// precondition this conformance inserts always holds.
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

        // Lane J (J-2): refuse second app windows on iPad; see SingleWindowPolicy.
        SingleWindowPolicy.activate()

        // #14: the BGAppRefreshTask launch handler must be registered before
        // the app finishes launching; scheduling happens on background entry.
        BackgroundRefreshScheduler.register()
        Task { @MainActor in
            await AppContainer.sharedDefault().handleSystemLaunch()
        }
        return true
    }

}

@main
struct TalariaApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(HermesAppDelegate.self) private var appDelegate
    @State private var container = AppContainer.sharedDefault()
    // #124: biometric app lock. SettingsStore loads synchronously in its
    // init, so the cold-launch lock decision lands before the first frame.
    @State private var appLock = AppLockController(
        configuration: { AppContainer.sharedDefault().settingsStore.settings.appLockConfiguration }
    )
    @State private var appLockPresenter = AppLockWindowPresenter()

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
                .environment(appLock)
                .task {
                    // #124: mount the lock cover window before anything else
                    // async — a cold launch with the lock enabled must never
                    // render content first.
                    appLockPresenter.attach(controller: appLock)
                    await container.initialize()
                    // #58: cold-launch pickup for a Control Center tap. After
                    // initialize() so the local critical path (which ends in
                    // drainShareInbox, itself a router write) can't land on
                    // top of the route we just chose.
                    consumePendingControlDestination()
                    #if DEBUG
                    // #333 instrument trigger: headless registry-instrument
                    // runs, armed only by launch environment (the #196 pair
                    // — TALARIA_AUTO_BATTERY / TALARIA_AUTO_ROUTER_PROBE —
                    // still works, mapped onto the same registry). Last —
                    // everything above is the production launch path,
                    // untouched.
                    await container.runAutoInstrumentsIfArmed()
                    #endif
                }
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
                    // #124: toggling the lock off releases it; toggling on
                    // never locks mid-session.
                    if oldSettings.appLockConfiguration != newSettings.appLockConfiguration {
                        appLock.configurationChanged()
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    // #124: the lock decision runs first so the cover is up
                    // before any foreground work repaints content beneath it.
                    appLock.scenePhaseChanged(to: AppLockScenePhase(newPhase))
                    if newPhase == .active {
                        // Re-resolve automatic (seasonal) theme on foreground so a
                        // season rollover applies without a relaunch (issue #24).
                        // No-op in manual mode.
                        ThemeRuntime.shared.apply(container.settingsStore.settings)
                        // #123: stage anything the share extension queued —
                        // BEFORE handleAppDidBecomeActive, which returns early
                        // when unpaired (shares are a free-tier surface).
                        container.drainShareInbox()
                        // #58: the warm-launch pickup for the app-group
                        // FALLBACK lane (extension-performed intents only —
                        // a no-op when `.main` execution holds). On that
                        // lane `perform()` runs while the system is already
                        // launching us, so the write can land just after
                        // the cold-launch read; this is the second look.
                        consumePendingControlDestination()
                        Task { await container.handleAppDidBecomeActive() }
                    } else if newPhase == .background {
                        // #14: arm the native background-refresh safety net
                        // alongside the relay app-state report.
                        BackgroundRefreshScheduler.schedule()
                        Task {
                            await container.reportAppStateIfNeeded("background")
                        }
                    }
                    // Voice sessions END on background (#118, privacy):
                    // AppContainer's didEnterBackground observer runs the
                    // user-end path so the mic indicator goes dark. CarPlay
                    // routes are exempt — CarPlay voice runs with the phone
                    // UI backgrounded by design (#19), which is what the
                    // "audio" background mode remains for.
                }
                .onOpenURL { url in
                    handleDeeplink(url)
                }
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    handleSpotlightItem(activity)
                }
        }
    }

    /// #66: Spotlight taps on `indexAppEntities` results arrive as a
    /// CSSearchableItemActionType user activity — NOT through OpenSessionIntent
    /// (that path serves Siri/Shortcuts; device run 2026-07-17 proved the
    /// intents never fire from a Spotlight tap). Breadcrumb the raw identifier
    /// FIRST: if the on-device format is namespaced rather than a bare id,
    /// the log tells us the shape for round 2 instead of failing silently.
    private func handleSpotlightItem(_ activity: NSUserActivity) {
        let raw = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String ?? ""
        Self.spotlightLogger.notice("SpotlightOpen tap identifier: \(raw, privacy: .public)")
        guard !raw.isEmpty else { return }
        let indexing = container.spotlightIndexing
        if indexing.resolveSessions([raw]).first != nil {
            Self.spotlightLogger.notice("SpotlightOpen routing session \(raw, privacy: .public)")
            container.router.activeSheet = nil
            container.router.popToRoot()
            container.router.selectedTab = .chat
            Task { await container.chatStore.openSession(raw) }
        } else if indexing.resolveFiles([raw]).first != nil {
            // No file deep-route exists yet — land on Chat and log; the file
            // is one tap away and the breadcrumb proves resolution worked.
            Self.spotlightLogger.notice("SpotlightOpen resolved FILE \(raw, privacy: .public) — no file route, landing on chat")
            container.router.activeSheet = nil
            container.router.popToRoot()
            container.router.selectedTab = .chat
        } else {
            Self.spotlightLogger.notice("SpotlightOpen identifier \(raw, privacy: .public) resolved to NOTHING — format mismatch? (see #66)")
        }
    }

    private static let spotlightLogger = Logger(subsystem: "org.aethyrion.talaria", category: "SpotlightOpen")

    /// #58: the app-group FALLBACK pickup. Since 2026-07-27 the control
    /// intents declare `allowedExecutionTargets = .main`, so on the expected
    /// path `perform()` runs in THIS process and routes via `DeeplinkRouter`
    /// directly — nothing is ever written here and this read finds nothing.
    /// The store is only written by the intents' extension-compiled branch,
    /// i.e. only if the OS performs the intent in the widget process after
    /// all (`.main` not honored — see the branch log lines, subsystem
    /// `…talaria27.widgets`). Keep this pickup until a device pass proves
    /// `.main` holds on 27A5228h; then the store, this method, and both call
    /// sites go together.
    ///
    /// Nothing pending is the ordinary case, not a fault: every launch from
    /// the home screen reads this store too.
    private func consumePendingControlDestination() {
        guard let destination = ControlHandoffStore.appGroup()?.consumeDestination() else { return }
        Self.controlHandoffLogger.notice(
            "Control handoff: routing \(destination.absoluteString, privacy: .public)"
        )
        handleDeeplink(destination)
    }

    private static let controlHandoffLogger = Logger(subsystem: "org.aethyrion.talaria", category: "ControlHandoff")

    /// The switch itself lives in `DeeplinkRouter` (#58, 2026-07-27) so the
    /// Control Center intents — performing in THIS process under the `.main`
    /// execution target — route through the same table without reaching into
    /// the App struct. This thin wrapper is what `onOpenURL` and the handoff
    /// pickup call.
    private func handleDeeplink(_ url: URL) {
        DeeplinkRouter.route(url, router: container.router, chatStore: container.chatStore)
    }
}
