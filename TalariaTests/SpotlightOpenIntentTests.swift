import AppIntents
import Foundation
import Testing
@testable import Talaria

/// #66 — Spotlight tap-through open intents: static-configuration lock,
/// sibling of `HermesControlsTests` (#58).
///
/// The load-bearing assertions are the `openAppWhenRun == false` pair:
/// pairing `true` with the `OpenURLIntent` returned from `perform()` silently
/// swallowed the tap on Control Center (#58) and killed the Spotlight
/// tap-through the same way (#66, device pass 2026-07-13). The intents
/// declare `false` explicitly because `OpenIntent`'s own default for the
/// member is undocumented — these tests keep a refactor from silently
/// restoring the conflict. Deliberately NOT exercised: `perform()` itself —
/// it needs the system AppIntents machinery.
struct SpotlightOpenIntentTests {

    @Test func sessionIntentDoesNotSetOpenAppWhenRun() {
        #expect(OpenSessionIntent.openAppWhenRun == false)
    }

    @Test func fileIntentDoesNotSetOpenAppWhenRun() {
        #expect(OpenAgentFileIntent.openAppWhenRun == false)
    }

    /// The deep link is the launch (AppEntry.handleDeeplink's `session`
    /// route) — a refactor that reroutes or drops the id breaks tap-through
    /// even with the launch shape correct.
    @Test func sessionDestinationRoutesThroughSessionDeepLink() {
        #expect(
            OpenSessionIntent.destination(forSessionID: "sess-42")
                == URL(string: "hermes://session/sess-42")
        )
        #expect(
            OpenSessionIntent.destination(forSessionID: "sess 42")
                == URL(string: "hermes://session/sess%2042"),
            "ids that aren't URL-safe must percent-encode, not drop"
        )
    }

    @Test func fileDestinationLandsOnChat() {
        #expect(OpenAgentFileIntent.destination == URL(string: "hermes://chat"))
    }
}
