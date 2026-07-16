import AppIntents
import Testing

/// #58 — Control Center launch intents: static-configuration lock.
///
/// `HermesControls.swift` compiles straight into this test bundle (see the
/// TalariaTests sources in project.yml) because the widget extension isn't
/// an importable module.
///
/// The load-bearing assertions are the `openAppWhenRun == false` pair: the
/// member is deliberately absent from both intents (protocol default), since
/// setting it alongside the `OpenURLIntent` returned from `perform()` made
/// Control Center silently swallow the tap. Re-adding
/// `static let openAppWhenRun = true` flips these red. Deliberately NOT
/// exercised: `perform()` itself — it needs the system AppIntents machinery.
struct HermesControlsTests {

    @Test func chatIntentDoesNotSetOpenAppWhenRun() {
        #expect(OpenHermesChatIntent.openAppWhenRun == false)
    }

    @Test func voiceIntentDoesNotSetOpenAppWhenRun() {
        #expect(OpenHermesVoiceIntent.openAppWhenRun == false)
    }

    /// Control-only plumbing must never shadow the app target's discoverable
    /// `AskHermesIntent` / `StartVoiceSessionIntent` in Shortcuts/Spotlight.
    @Test func launchIntentsStayUndiscoverable() {
        #expect(OpenHermesChatIntent.isDiscoverable == false)
        #expect(OpenHermesVoiceIntent.isDiscoverable == false)
    }

    /// The system keys placed controls by `kind` — a rename orphans every
    /// control Owen has already placed.
    @Test func controlKindsAreStable() {
        #expect(AskHermesControl.kind == "org.aethyrion.talaria27.control.askHermes")
        #expect(TalkToHermesControl.kind == "org.aethyrion.talaria27.control.talkToHermes")
    }
}
