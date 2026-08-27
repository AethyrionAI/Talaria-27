import AppIntents
import SwiftUI
import WidgetKit

// Control Center / Lock Screen / Action-button controls (#7).
//
// Two `ControlWidget` buttons: "Ask Talaria" opens the chat transcript and
// "Talk to Talaria" starts a hands-free voice session. Registering them in
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

// #415 fact 2 (2026-08-26, Owen: *"The talk and chat ones should be changed
// from hermes to talaria"*): the two visible titles below name the APP, which
// is what a Control Center tile is a tile FOR. The TYPE names and the `kind`
// identifiers deliberately did not move — `kind` is how the system keys a
// control the user has already placed, so renaming one orphans it.
// "Hermes" is still correct everywhere it means the HOST (the composer
// placeholder, Connect Host, the chat status lines); this rename does not
// reach any of that.

/// The chat control (#7) — titled "Ask Talaria". Symbol matches the app's
/// Ask Hermes shortcut (`text.bubble` in `TalariaAppShortcuts`), which keeps
/// its own name: that is the Siri/Shortcuts surface, not this one.
struct AskHermesControl: ControlWidget {
    /// Stable identity — the system keys placed controls by it; never rename.
    /// The value lives in `HermesControlKind` so `HermesControlsTests` can
    /// pin it through the app module; keep this a reference, not a literal.
    static let kind = HermesControlKind.askHermes

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenHermesChatIntent()) {
                Label("Ask Talaria", systemImage: "text.bubble")
            }
        }
        .displayName("Ask Talaria")
        .description("Open the Talaria chat and ask a question.")
    }
}

/// The voice control (#7) — titled "Talk to Talaria". Symbol matches the
/// voice-session shortcut (`waveform` in `TalariaAppShortcuts`).
struct TalkToHermesControl: ControlWidget {
    /// Stable identity — never rename; same reference rule as above.
    static let kind = HermesControlKind.talkToHermes

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenHermesVoiceIntent()) {
                Label("Talk to Talaria", systemImage: "waveform")
            }
        }
        .displayName("Talk to Talaria")
        .description("Open Talaria and start a hands-free voice session.")
    }
}
