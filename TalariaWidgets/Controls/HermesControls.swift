import AppIntents
import os
import SwiftUI
import WidgetKit

// Control Center / Lock Screen / Action-button controls (#7).
//
// Two `ControlWidget` buttons (iOS 18 GA API — no availability gating needed
// at this deployment target): "Ask Hermes" opens the chat transcript (the
// surface where an Ask Hermes #6 exchange lands) and "Talk to Hermes" starts
// a hands-free voice session. Registering them in `HermesWidgetBundle` is all
// it takes for the system to offer them in the Control Center gallery, on the
// Lock Screen, and in the Action-button picker.
//
// Architecture (#7 — deliberate, do not "simplify" by sharing intent
// sources): the app target's real intents (`AskHermesIntent`,
// `StartVoiceSessionIntent`) are NOT compiled into this extension. Their
// `perform()` reaches `AppContainer.sharedDefault()` → ChatStore → the whole
// app object graph, so sharing those sources would drag the app into the
// widget target — and a control's intent performs in the EXTENSION process,
// where a fresh AppContainer would mutate router state the app process never
// observes. Each control instead runs a lightweight extension-local intent
// whose only job is to name a `hermes://` destination; the SYSTEM launches
// the app (`openAppWhenRun`) and `AppEntry` feeds that destination to
// `handleDeeplink`, which flips the SAME router flags the real intents flip,
// in the right process — so both controls run the exact code paths the Siri
// intents exercise.
//
// How the destination travels (#58, 2026-07-24): NOT as a returned
// `OpenURLIntent` — that shape does not support custom URL schemes, so
// AppIntents prepared `URL(nil)` and the tap died silently while every log
// line said success. It rides `ControlHandoffStore` (the app group) instead.
//
// iOS 27 upgrade path: `ExecutionTargets.main` (beta API) would let the real
// app intents perform directly in the main app process, removing the handoff
// entirely. Not adopted — verify the SDK shape on a Mac session first.

/// The extension's only diagnostics (#58): one line per control tap so
/// Console.app can answer "did perform() fire?". `.notice` because Console's
/// default view suppresses `.info`; `privacy: .public` because interpolations
/// redact without it.
private let controlLog = Logger(
    subsystem: "org.aethyrion.talaria27.widgets",
    category: "controls"
)

/// Both control intents do the same two things: say so in the log, and leave
/// the destination where the app will look. Losing the app group is NOT fatal
/// — the system still launches the app, it just lands on the default screen —
/// but it has to be visible, because on a device that outcome is
/// indistinguishable from #179's swallowed first tap.
private func handOffToApp(_ destination: URL, from intentName: String) {
    controlLog.notice(
        "\(intentName, privacy: .public).perform fired — handing off \(destination.absoluteString, privacy: .public)"
    )
    guard let store = ControlHandoffStore.appGroup() else {
        controlLog.error(
            "\(intentName, privacy: .public).perform — app group unreachable; the app will open to its default screen"
        )
        return
    }
    store.writeDestination(destination)
}

// MARK: - Launch intents (extension-local)

/// Launches the app on `hermes://chat` — `AppEntry.handleDeeplink` clears any
/// sheet, pops to root, and selects the Chat tab: the transcript surface an
/// Ask Hermes (#6) answer lands in.
struct OpenHermesChatIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Hermes"
    static let description = IntentDescription(
        "Opens Talaria to the Hermes chat.",
        categoryName: "Chat"
    )
    // The system performs the launch. This was `false` (absent) until
    // 2026-07-24, on the premise that the `OpenURLIntent` returned from
    // `perform()` IS the launch — correct for an ELIGIBLE url, and
    // `hermes://chat` is not one. The older warning here said pairing
    // `openAppWhenRun = true` WITH that returned intent made Control Center
    // swallow the tap: true, and not an argument against this shape. With an
    // `OpensIntent` result the returned intent is the launch, so setting both
    // makes two mechanisms compete. This intent returns a plain
    // `IntentResult` — there is no second mechanism left to compete with.
    static let openAppWhenRun = true
    /// Control-only plumbing — keep it out of Shortcuts/Spotlight so it never
    /// shadows the app target's full-featured `AskHermesIntent`.
    static let isDiscoverable = false

    /// Compile-time literal — parsing cannot fail (the no-force-unwrap
    /// convention targets network payloads, not constants). Internal rather
    /// than private so `HermesControlsTests` can pin which route this control
    /// claims: `perform()` itself needs the system AppIntents machinery and
    /// can't be driven from a test host.
    static let destination = URL(string: "hermes://chat")!

    func perform() async throws -> some IntentResult {
        handOffToApp(Self.destination, from: "OpenHermesChatIntent")
        return .result()
    }
}

/// Launches the app on `hermes://voice` — `AppEntry.handleDeeplink` sets
/// `router.isVoiceOverlayPresented`, the same flag
/// `StartVoiceSessionIntent.perform()` sets; `VoiceOverlayScreen` auto-starts
/// the session on appear. A voice session cannot run here in the extension
/// (mic + WebRTC + UI need the foreground app).
struct OpenHermesVoiceIntent: AppIntent {
    static let title: LocalizedStringResource = "Talk to Hermes"
    static let description = IntentDescription(
        "Opens Talaria and starts a hands-free voice session.",
        categoryName: "Voice"
    )
    // Same shape as `OpenHermesChatIntent` — see the #58 reasoning there.
    // `StartVoiceSessionIntent` (app target) already ships
    // `openAppWhenRun = true`; this is now the same mechanism.
    static let openAppWhenRun = true
    /// Control-only plumbing — `StartVoiceSessionIntent` is the discoverable
    /// Shortcuts/Siri entry point.
    static let isDiscoverable = false

    /// Compile-time literal — parsing cannot fail. Internal for the same
    /// route pin as `OpenHermesChatIntent.destination`.
    static let destination = URL(string: "hermes://voice")!

    func perform() async throws -> some IntentResult {
        handOffToApp(Self.destination, from: "OpenHermesVoiceIntent")
        return .result()
    }
}

// MARK: - Controls

/// "Ask Hermes" control (#7). Symbol matches the app's Ask Hermes shortcut
/// (`text.bubble` in `TalariaAppShortcuts`).
struct AskHermesControl: ControlWidget {
    /// Stable identity — the system keys placed controls by it; never rename.
    static let kind = "org.aethyrion.talaria27.control.askHermes"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenHermesChatIntent()) {
                Label("Ask Hermes", systemImage: "text.bubble")
            }
        }
        .displayName("Ask Hermes")
        .description("Open the Hermes chat and ask a question.")
    }
}

/// "Talk to Hermes" control (#7). Symbol matches the voice-session shortcut
/// (`waveform` in `TalariaAppShortcuts`).
struct TalkToHermesControl: ControlWidget {
    /// Stable identity — never rename.
    static let kind = "org.aethyrion.talaria27.control.talkToHermes"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenHermesVoiceIntent()) {
                Label("Talk to Hermes", systemImage: "waveform")
            }
        }
        .displayName("Talk to Hermes")
        .description("Open Talaria and start a hands-free voice session.")
    }
}
