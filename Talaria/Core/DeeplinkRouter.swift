import Foundation

/// The one deep-link switch (#48/#58) — every launch surface converges
/// here: Safari/`onOpenURL`, Spotlight's `OpenSessionIntent` destinations,
/// widget `widgetURL` taps, the Control Center intents performing in the app
/// process (#58, `.main` execution target), and the app-group fallback
/// `AppEntry.consumePendingControlDestination` drains. Extracted from
/// `TalariaApp.handleDeeplink` 2026-07-27 so the control intents — which are
/// compiled into the widget target too and therefore can't live on the App
/// struct — call the SAME switch instead of growing a second one, and so the
/// routing is finally drivable from a unit test host (it never was as a
/// private method on the App struct).
///
/// Takes the router and chat store rather than the whole `AppContainer`:
/// they are all the switch touches, and they're the two pieces a test can
/// build in three lines (`AppContainer` needs the ~100-line mock harness).
@MainActor
enum DeeplinkRouter {

    /// The schemes this app answers, and the ONLY ones — a URL outside this
    /// set changes nothing. Must stay in lockstep with `CFBundleURLTypes` in
    /// `project.yml`: a scheme registered there but missing here opens the app
    /// to a dead route, and one here but not there is never delivered at all.
    ///
    /// `talaria` is the primary, documented scheme (#77). `hermes` is the
    /// original one, kept working and undocumented on purpose — the ruling
    /// that says so, and the ⛔ that goes with it, is quoted at the
    /// registration site in `project.yml`; read it there before touching this
    /// line.
    static let registeredSchemes: Set<String> = ["talaria", "hermes"]

    static func route(_ url: URL, router: TabRouter, chatStore: ChatStore) {
        guard let scheme = url.scheme, registeredSchemes.contains(scheme) else { return }
        switch url.host {
        case "chat":
            router.activeSheet = nil
            router.popToRoot()
            router.selectedTab = .chat
        case "session":
            // #17: talaria://session/{id} — Spotlight results route here via
            // OpenSessionIntent. Lands on Chat, then adopts the session.
            guard url.pathComponents.count > 1 else { break }
            let sessionID = url.pathComponents[1]
            router.activeSheet = nil
            router.popToRoot()
            router.selectedTab = .chat
            Task { await chatStore.openSession(sessionID) }
        case "health":
            router.activeSheet = nil
            router.popToRoot()
            router.selectedTab = .chat
            router.navigate(to: .permissions)
        case "briefing":
            // #126: widget tap → the latest briefing's detail.
            router.activeSheet = nil
            router.popToRoot()
            router.selectedTab = .chat
            router.navigate(to: .briefing(nil))
        case "voice":
            // Same flag StartVoiceSessionIntent sets; the Talk to Hermes
            // control (#7) routes through this link. Clear any sheet first —
            // MainTabView presentations can't overlap (parity with the intent).
            router.activeSheet = nil
            router.isVoiceOverlayPresented = true
        case "ask":
            // #48: talaria://ask?q=… — the payload-carrying route. Lands on
            // Chat and seeds the composer; the user still taps send. Never
            // auto-sends: custom-scheme URLs are open to any app or web page,
            // and an auto-send would let external content inject agent turns.
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "q" })?
                .value ?? ""
            router.activeSheet = nil
            router.popToRoot()
            router.selectedTab = .chat
            chatStore.seedComposer(query)
        default:
            break
        }
    }
}
