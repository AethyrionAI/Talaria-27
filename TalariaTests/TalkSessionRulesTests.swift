import Foundation
import Testing
@testable import Talaria

/// #118 / #119 — voice-residuals lane decision cores. Backgrounding ends the
/// voice session (the mic indicator must go dark — privacy) except while
/// CarPlay drives; a cancel racing an already-completed response is a normal
/// race, not a session failure. Live audio/session behavior is a device
/// concern covered by the OPEN_ITEMS #118/#119 device checklists.
struct TalkSessionRulesTests {

    // MARK: - TalkBackgroundRule (#118)

    @Test func backgroundEndsActiveSession() {
        #expect(TalkBackgroundRule.shouldEndSession(
            isSessionActive: true,
            routeHasCarAudio: false
        ))
    }

    @Test func backgroundIgnoresIdleSession() {
        #expect(!TalkBackgroundRule.shouldEndSession(
            isSessionActive: false,
            routeHasCarAudio: false
        ))
    }

    @Test func backgroundSparesCarPlaySession() {
        // CarPlay voice runs with the phone UI backgrounded by design (#19) —
        // the privacy hook must not kill the session the car is driving.
        #expect(!TalkBackgroundRule.shouldEndSession(
            isSessionActive: true,
            routeHasCarAudio: true
        ))
    }

    @Test func backgroundIgnoresIdleSessionEvenUnderCarPlay() {
        #expect(!TalkBackgroundRule.shouldEndSession(
            isSessionActive: false,
            routeHasCarAudio: true
        ))
    }
}
