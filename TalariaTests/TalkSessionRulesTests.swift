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

    // MARK: - RealtimeErrorRule (#119a)

    @Test func observedNoOpCancelShapeIsSwallowed() {
        // The exact backend string from the #82 confirm-run screenshot.
        #expect(RealtimeErrorRule.disposition(
            code: nil,
            message: "Cancellation failed: no active response found"
        ) == .swallowNoOpCancel)
    }

    @Test func noOpCancelCodeIsSwallowedRegardlessOfWording() {
        #expect(RealtimeErrorRule.disposition(
            code: "response_cancel_not_active",
            message: "Some rephrased server wording"
        ) == .swallowNoOpCancel)
    }

    @Test func responseCreateRaceKeepsItsSuppression() {
        // The pre-existing suppression (our response.create after MCP tool
        // completion racing an active response) — now classified, still silent.
        #expect(RealtimeErrorRule.disposition(
            code: nil,
            message: "Conversation already has an active response in progress"
        ) == .swallowResponseCreateRace)
    }

    @Test func otherCancelFailuresStillSurface() {
        #expect(RealtimeErrorRule.disposition(
            code: nil,
            message: "Cancellation failed: connection lost"
        ) == .surface)
    }

    @Test func unrelatedErrorsSurface() {
        #expect(RealtimeErrorRule.disposition(
            code: nil,
            message: "Session expired."
        ) == .surface)
        #expect(RealtimeErrorRule.disposition(
            code: "session_expired",
            message: ""
        ) == .surface)
        // The handler's fallback message for a shapeless error payload.
        #expect(RealtimeErrorRule.disposition(
            code: nil,
            message: "Realtime talk failed."
        ) == .surface)
    }
}
