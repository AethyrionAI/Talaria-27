import AppIntents
import SwiftUI
import WidgetKit

// Control Center / Lock Screen / Action-button controls (#7).
//
// Two `ControlWidget` buttons: "Ask Hermes" opens the chat transcript and
// "Talk to Hermes" starts a hands-free voice session. Registering them in
// `HermesWidgetBundle` is all it takes for the system to offer them in the
// Control Center gallery, on the Lock Screen, and in the Action-button
// picker.
//
// The intents they run (`OpenHermesChatIntent` / `OpenHermesVoiceIntent`)
// live in `Shared/HermesControlIntents.swift`, compiled into BOTH the app
// and this extension: they declare `allowedExecutionTargets = .main`, so the
// system performs the tap in the APP process, where the router lives (#58 —
// see that file's header for the whole story, including why
// `openAppWhenRun` is gone and what the extension-side fallback is). The app
// target's full intents (`AskHermesIntent`, `StartVoiceSessionIntent`) are
// still NOT shared into this target — their `perform()` reaches the whole
// app object graph, which must not be dragged into a widget binary; the
// shared launch intents stay deliberately thin instead.

/// "Ask Hermes" control (#7). Symbol matches the app's Ask Hermes shortcut
/// (`text.bubble` in `TalariaAppShortcuts`).
struct AskHermesControl: ControlWidget {
    /// Stable identity — the system keys placed controls by it; never rename.
    /// The value lives in `HermesControlKind` so `HermesControlsTests` can
    /// pin it through the app module; keep this a reference, not a literal.
    static let kind = HermesControlKind.askHermes

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
    /// Stable identity — never rename; same reference rule as above.
    static let kind = HermesControlKind.talkToHermes

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
