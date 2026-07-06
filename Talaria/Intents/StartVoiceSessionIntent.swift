import AppIntents

/// "Hey Siri, talk to Talaria" / Action Button / Shortcuts → a live voice
/// session (#3). No wake-word API exists on iOS, so Siri → App Intents is the
/// sanctioned hands-free activation path (and the phone-side trigger for
/// CarPlay driving use).
///
/// `perform()` routes through the same flag the in-app entry points use
/// (`router.isVoiceOverlayPresented` — the `hermes://voice` deep link and the
/// Voice settings screen both set it); `VoiceOverlayScreen` auto-starts the
/// session on appear. iOS 16-era API throughout: no entitlement, no Apple
/// Intelligence requirement, identical on every hardware tier.
struct StartVoiceSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Voice Session"
    static let description = IntentDescription(
        "Opens Talaria and starts a hands-free voice session with Hermes.",
        categoryName: "Voice"
    )
    /// The voice pipeline needs the app foregrounded (mic + WebRTC + UI).
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let container = AppContainer.sharedDefault()
        // Presentations of MainTabView can't overlap — clear any sheet first,
        // same as the deep-link path.
        container.router.activeSheet = nil
        container.router.isVoiceOverlayPresented = true
        return .result()
    }
}

/// Registers the Siri phrases. Every phrase must carry the
/// `\(.applicationName)` token — fixed, pre-declared strings only. An app may
/// declare only ONE AppShortcutsProvider, so every intent's shortcut lives
/// here.
struct TalariaAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartVoiceSessionIntent(),
            phrases: [
                "Talk to \(.applicationName)",
                "Start a voice session in \(.applicationName)",
                "Start \(.applicationName) voice session",
                "Voice chat with \(.applicationName)",
            ],
            shortTitle: "Start Voice Session",
            systemImageName: "waveform"
        )
        // Ask Hermes (#6). The question can't ride the phrase itself — App
        // Shortcut phrase parameters must be AppEnum/AppEntity, not free-form
        // String — so Siri prompts for it (the parameter's requestValueDialog).
        AppShortcut(
            intent: AskHermesIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Ask \(.applicationName) a question",
                "Ask \(.applicationName) something",
                "Send \(.applicationName) a question",
            ],
            shortTitle: "Ask Hermes",
            systemImageName: "text.bubble"
        )
    }
}
