import AppIntents
import Foundation
import os

// Control Center / Lock Screen launch intents (#7/#58).
//
// Compiled into BOTH the app and the widget extension — that dual membership
// is load-bearing, not convenience: the intents declare
// `allowedExecutionTargets = .main`, which asks the system to run `perform()`
// in the MAIN APP process even though the control lives in the widget
// extension, and the app process can only perform an intent whose type is
// compiled into it. (Same dual-inclusion contract as a LiveActivityIntent.)
//
// Why `.main` (#58, 2026-07-27): the device pass of 2026-07-25 showed every
// control tap dying ~6–11 ms in with `openAppWhenRun is not supported in
// extensions` (Code 2001) — `perform()` NEVER executed, on any pass, ever.
// `openAppWhenRun` is gone from these intents for that reason. In its place:
//   - `supportedModes = .foreground` (iOS 26+, the documented replacement
//     for `openAppWhenRun`): the tap foregrounds the app.
//   - `allowedExecutionTargets = .main` (iOS 27+): `perform()` runs in the
//     app process, where the router lives.
// Both shapes were verified against Apple's current documentation
// (2026-07-27): `supportedModes: IntentModes` and `allowedExecutionTargets:
// IntentExecutionTargets` — note the property's DOC type is
// `IntentExecutionTargets`; WWDC26 session code said `ExecutionTargets`,
// which is the spelling older comments here carried. Doc-verified is not
// SDK-verified: the compile on 27A5228h is the arbiter (this file was
// written off-Mac). Deployment floor is iOS 27.0 (project.yml
// options.deploymentTarget), so no `#available` guards.
//
// The `#if TALARIA_MAIN_APP` split (flag set only on the app target in
// project.yml): the app-compiled branch routes through `DeeplinkRouter` —
// the same switch Safari, Spotlight and Siri land in — and the
// widget-compiled branch keeps the #58 app-group handoff as a FALLBACK that
// only runs if the OS performs in the extension anyway (i.e. `.main` not
// honored on this SDK). The branch a tap actually took is readable in
// Console.app: the log subsystem below names the process. Once a device
// pass proves `.main` holds, the fallback branch, `ControlHandoffStore`,
// and `AppEntry.consumePendingControlDestination()` can all go together —
// do not remove one without the others.

/// One line per control tap so Console.app can answer "did perform() fire,
/// and in WHICH process?" — the subsystem is the process fingerprint.
/// `.notice` because Console's default view suppresses `.info`;
/// `privacy: .public` because interpolations redact without it.
#if TALARIA_MAIN_APP
private let controlLog = Logger(
    subsystem: "org.aethyrion.talaria",
    category: "controls"
)
#else
private let controlLog = Logger(
    subsystem: "org.aethyrion.talaria27.widgets",
    category: "controls"
)
#endif

/// Control identities — the system keys placed controls by these; a rename
/// orphans every control Owen has already placed. Declared here (not on the
/// `ControlWidget` structs, which are widget-target-only) so
/// `HermesControlsTests` can pin the values through the app module.
enum HermesControlKind {
    static let askHermes = "org.aethyrion.talaria27.control.askHermes"
    static let talkToHermes = "org.aethyrion.talaria27.control.talkToHermes"
}

#if TALARIA_MAIN_APP
/// App-process branch: the tap landed where the router lives — route it on
/// the spot, exactly as the Siri intents do. State-based (router flags), so
/// it works mid-cold-launch the same way `StartVoiceSessionIntent` does.
///
/// Known, bounded hazard (mirror of the old handoff race): on a COLD launch
/// `perform()` can run before `container.initialize()` finishes, and the
/// local critical path ends in `drainShareInbox` — a router write — which
/// could then land on top of this route. Only reachable when a share is
/// pending at the moment of a cold control tap. If the device pass shows
/// that shape, sequence against `initialize()` here rather than reviving
/// the app-group indirection.
@MainActor
private func routeInAppProcess(_ destination: URL, from intentName: String) {
    controlLog.notice(
        "\(intentName, privacy: .public).perform fired in the APP process — routing \(destination.absoluteString, privacy: .public)"
    )
    let container = AppContainer.sharedDefault()
    DeeplinkRouter.route(destination, router: container.router, chatStore: container.chatStore)
}
#else
/// Extension-process branch — the #58 app-group FALLBACK. Running at all
/// means `.main` was NOT honored on this SDK (say so in the log, loudly:
/// that is the fact the next device pass needs). The destination rides
/// `ControlHandoffStore`; `supportedModes = .foreground` still opens the
/// app, and `AppEntry.consumePendingControlDestination()` routes it.
/// Losing the app group is still not fatal — the app opens on its default
/// screen — but it must be visible, because on a device that outcome is
/// indistinguishable from a swallowed tap (#179).
private func handOffToApp(_ destination: URL, from intentName: String) {
    controlLog.error(
        "\(intentName, privacy: .public).perform fired in the EXTENSION process — .main execution did not hold; handing off \(destination.absoluteString, privacy: .public) via the app group"
    )
    guard let store = ControlHandoffStore.appGroup() else {
        controlLog.error(
            "\(intentName, privacy: .public).perform — app group unreachable; the app will open to its default screen"
        )
        return
    }
    store.writeDestination(destination)
}
#endif

// MARK: - Launch intents

/// "Ask Hermes" control tap → the chat transcript (the surface where an Ask
/// Hermes #6 exchange lands): `DeeplinkRouter`'s `chat` case clears any
/// sheet, pops to root, and selects the Chat tab.
struct OpenHermesChatIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Hermes"
    static let description = IntentDescription(
        "Opens Talaria to the Hermes chat.",
        categoryName: "Chat"
    )
    /// The tap foregrounds the app (iOS 26+ replacement for the
    /// `openAppWhenRun` the OS rejects in extensions — the #58 root cause).
    static let supportedModes: IntentModes = .foreground
    /// `perform()` runs in the main app process (iOS 27+) — see the file
    /// header for why this is the whole fix.
    static let allowedExecutionTargets: IntentExecutionTargets = .main
    /// Control-only plumbing — keep it out of Shortcuts/Spotlight so it never
    /// shadows the app target's full-featured `AskHermesIntent`.
    static let isDiscoverable = false

    /// Compile-time literal — parsing cannot fail (the no-force-unwrap
    /// convention targets network payloads, not constants). Internal so
    /// `HermesControlsTests` can pin which route this control claims.
    static let destination = URL(string: "talaria://chat")!

    @MainActor
    func perform() async throws -> some IntentResult {
        #if TALARIA_MAIN_APP
        routeInAppProcess(Self.destination, from: "OpenHermesChatIntent")
        #else
        handOffToApp(Self.destination, from: "OpenHermesChatIntent")
        #endif
        return .result()
    }
}

/// "Talk to Hermes" control tap → the voice overlay: `DeeplinkRouter`'s
/// `voice` case sets `router.isVoiceOverlayPresented`, the same flag
/// `StartVoiceSessionIntent.perform()` sets; `VoiceOverlayScreen` auto-starts
/// the session on appear. The session itself needs the foreground app
/// (mic + WebRTC + UI), which `supportedModes = .foreground` provides.
struct OpenHermesVoiceIntent: AppIntent {
    static let title: LocalizedStringResource = "Talk to Hermes"
    static let description = IntentDescription(
        "Opens Talaria and starts a hands-free voice session.",
        categoryName: "Voice"
    )
    // Same shape as `OpenHermesChatIntent` — see the reasoning there.
    static let supportedModes: IntentModes = .foreground
    static let allowedExecutionTargets: IntentExecutionTargets = .main
    /// Control-only plumbing — `StartVoiceSessionIntent` is the discoverable
    /// Shortcuts/Siri entry point.
    static let isDiscoverable = false

    /// Compile-time literal — parsing cannot fail. Internal for the same
    /// route pin as `OpenHermesChatIntent.destination`.
    static let destination = URL(string: "talaria://voice")!

    @MainActor
    func perform() async throws -> some IntentResult {
        #if TALARIA_MAIN_APP
        routeInAppProcess(Self.destination, from: "OpenHermesVoiceIntent")
        #else
        handOffToApp(Self.destination, from: "OpenHermesVoiceIntent")
        #endif
        return .result()
    }
}
