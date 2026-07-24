import AppIntents
import Foundation
import Testing

/// #58 — Control Center launch intents: static-configuration lock.
///
/// `HermesControls.swift` compiles straight into this test bundle (see the
/// TalariaTests sources in project.yml) because the widget extension isn't
/// an importable module.
///
/// The load-bearing assertions are the `openAppWhenRun == true` pair. They
/// were pinned to `false` until 2026-07-24, on the premise that the
/// `OpenURLIntent` returned from `perform()` IS the launch — true for an
/// ELIGIBLE url, and `hermes://chat` is not one: `OpenURLIntent` does not
/// support custom schemes, so AppIntents prepared `URL(nil)` and the tap died
/// silently. The launch is now the system's (`openAppWhenRun`), and the
/// destination rides the app group instead. Reverting either intent to the
/// absent/false default flips these red.
///
/// Deliberately NOT exercised: `perform()` itself — it needs the system
/// AppIntents machinery, and the extension can't be driven from a unit test
/// host. What IS pinned is the constant `perform()` hands to the app group;
/// the write and its consume-once contract are covered by
/// `ControlHandoffTests`.
struct HermesControlsTests {

    @Test func chatIntentOpensTheAppWhenRun() {
        #expect(OpenHermesChatIntent.openAppWhenRun == true)
    }

    @Test func voiceIntentOpensTheAppWhenRun() {
        #expect(OpenHermesVoiceIntent.openAppWhenRun == true)
    }

    /// Each control must hand the app ITS OWN destination. `perform()` can't
    /// be driven from here, so this constant is the only observable half of
    /// the write — and the two intents are near-identical twins, which is
    /// exactly the shape a copy-paste swap survives unnoticed.
    @Test func controlDestinationsMatchTheirRoutes() {
        #expect(OpenHermesChatIntent.destination == URL(string: "hermes://chat"))
        #expect(OpenHermesVoiceIntent.destination == URL(string: "hermes://voice"))
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
