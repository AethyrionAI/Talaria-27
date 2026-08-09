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
            isStartingSession: false,
            routeHasCarAudio: false
        ))
    }

    /// **KEPT, not inverted (#254 bar 254-A).** A genuinely idle store must
    /// still be left alone — revoking on every backgrounding would reach
    /// `setActive(false, .notifyOthersOnDeactivation)` with nothing live, the
    /// #84 stray-deactivation shape. #254 ADDS an input; it does not remove
    /// this one.
    @Test func backgroundIgnoresIdleSession() {
        #expect(!TalkBackgroundRule.shouldEndSession(
            isSessionActive: false,
            isStartingSession: false,
            routeHasCarAudio: false
        ))
    }

    @Test func backgroundSparesCarPlaySession() {
        // CarPlay voice runs with the phone UI backgrounded by design (#19) —
        // the privacy hook must not kill the session the car is driving.
        #expect(!TalkBackgroundRule.shouldEndSession(
            isSessionActive: true,
            isStartingSession: false,
            routeHasCarAudio: true
        ))
    }

    @Test func backgroundIgnoresIdleSessionEvenUnderCarPlay() {
        #expect(!TalkBackgroundRule.shouldEndSession(
            isSessionActive: false,
            isStartingSession: false,
            routeHasCarAudio: true
        ))
    }

    // MARK: - TalkBackgroundRule, #254 extension (bar 254-A)

    /// **The #254 defect, as a pure function.** `isSessionActive` is derived
    /// from the ENGINE's published `connectionState`, so it is false through
    /// the whole prologue of a start and false again during the
    /// realtime→native fallback. Backgrounding in either window used to
    /// return false here and revoke nothing, and the connect then landed
    /// live in the background under `UIBackgroundModes: audio`.
    ///
    /// Bar 254-F (2026-08-09) established that this rule is the ONLY backstop:
    /// `VoiceOverlayScreen.onDisappear` does not fire on backgrounding, so
    /// #139's unguarded `abandonSession()` never runs on this path.
    @Test func backgroundRevokesAStartInFlight() {
        #expect(TalkBackgroundRule.shouldEndSession(
            isSessionActive: false,
            isStartingSession: true,
            routeHasCarAudio: false
        ))
    }

    /// **The CarPlay exemption applies to BOTH arms.** A start in flight in a
    /// car is still a session CarPlay is driving (#19); the new input must not
    /// smuggle a teardown past the exemption the live arm has always honoured.
    @Test func backgroundSparesAStartInFlightUnderCarPlay() {
        #expect(!TalkBackgroundRule.shouldEndSession(
            isSessionActive: false,
            isStartingSession: true,
            routeHasCarAudio: true
        ))
    }

    /// Both true at once is reachable: the flag is cleared when the start
    /// RESOLVES, and the engine publishes `.connecting` — which makes
    /// `isSessionActive` true — part-way through. The window overlaps by
    /// construction, so the rule must not treat the pair as contradictory.
    @Test func backgroundRevokesWhenActiveAndStartingOverlap() {
        #expect(TalkBackgroundRule.shouldEndSession(
            isSessionActive: true,
            isStartingSession: true,
            routeHasCarAudio: false
        ))
        #expect(!TalkBackgroundRule.shouldEndSession(
            isSessionActive: true,
            isStartingSession: true,
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

    // MARK: - AudioInterruptionRule (#198)

    /// A system deactivation is what the old `.began` reported: something
    /// outside the app took the session.
    @Test func systemDeactivationIsAnInterruption() {
        #expect(AudioInterruptionRule.isInterruption(source: .system))
    }

    /// **The test the migration exists for.** `didBecomeInactive` fires on our
    /// OWN deactivations too — voice teardown, TTS finishing, voice-memo stop —
    /// which the old `.began` never did. Treating those as interruptions would
    /// tell the user "Audio interrupted." every time they stopped talking.
    @Test func ourOwnDeactivationIsNotAnInterruption() {
        #expect(!AudioInterruptionRule.isInterruption(source: .app))
    }

    @Test func recommendationDrivesResumption() {
        #expect(AudioInterruptionRule.shouldResume(.shouldResume))
        #expect(!AudioInterruptionRule.shouldResume(.shouldNotResume))
    }
}
