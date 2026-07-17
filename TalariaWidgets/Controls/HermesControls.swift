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
// whose only job is to launch the app on a `hermes://` deep link;
// `AppEntry.handleDeeplink` then flips the SAME router flags the real intents
// flip, in the right process — so both controls run the exact code paths the
// Siri intents exercise.
//
// iOS 27 upgrade path: `ExecutionTargets.main` (beta API) would let the real
// app intents perform directly in the main app process, removing the
// deep-link hop. Not adopted — verify the SDK shape on a Mac session first.

/// The extension's only diagnostics (#58): one line per control tap so
/// Console.app can answer "did perform() fire?". `.notice` because Console's
/// default view suppresses `.info`; `privacy: .public` because interpolations
/// redact without it.
private let controlLog = Logger(
    subsystem: "org.aethyrion.talaria27.widgets",
    category: "controls"
)

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
    // `openAppWhenRun` is deliberately ABSENT (protocol default false). The
    // `OpenURLIntent` returned from `perform()` IS the app launch — Apple's
    // sanctioned control-opens-app-to-URL shape. Pairing it with
    // `openAppWhenRun = true` made Control Center silently swallow the tap
    // (#58: control did nothing). Do not re-add it — `HermesControlsTests`
    // pins both intents to false.
    /// Control-only plumbing — keep it out of Shortcuts/Spotlight so it never
    /// shadows the app target's full-featured `AskHermesIntent`.
    static let isDiscoverable = false

    /// Compile-time literal — parsing cannot fail (the no-force-unwrap
    /// convention targets network payloads, not constants).
    private static let destination = URL(string: "hermes://chat")!

    func perform() async throws -> some IntentResult & OpensIntent {
        controlLog.notice(
            "OpenHermesChatIntent.perform fired — opening \(Self.destination.absoluteString, privacy: .public)"
        )
        return .result(opensIntent: OpenURLIntent(Self.destination))
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
    // `openAppWhenRun` deliberately absent — same #58 conflict as
    // `OpenHermesChatIntent`: the returned `OpenURLIntent` is the launch, and
    // pairing it with `openAppWhenRun = true` no-ops the tap from Control
    // Center. Do not re-add it.
    /// Control-only plumbing — `StartVoiceSessionIntent` is the discoverable
    /// Shortcuts/Siri entry point.
    static let isDiscoverable = false

    /// Compile-time literal — parsing cannot fail.
    private static let destination = URL(string: "hermes://voice")!

    func perform() async throws -> some IntentResult & OpensIntent {
        controlLog.notice(
            "OpenHermesVoiceIntent.perform fired — opening \(Self.destination.absoluteString, privacy: .public)"
        )
        return .result(opensIntent: OpenURLIntent(Self.destination))
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
