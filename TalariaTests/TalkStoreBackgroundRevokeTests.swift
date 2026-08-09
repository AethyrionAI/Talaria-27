import Foundation
import Testing
@testable import Talaria

/// #254 — **voice session lifetime ownership**, at the store level.
///
/// The defect this file pins: the voice session's lifetime was owned by a
/// SwiftUI *view*'s `onDisappear`, with the #118 background observer as the
/// only backstop — and that observer was guarded on `isSessionActive`, which
/// is FALSE while a start is in flight. Bar **254-F** (2026-08-09, two trials
/// plus a positive control on `CC-272-iPhone-Air`, iOS 27.0, engine pin
/// `voice session starting on engine native (relayPaired=false)`) established
/// that `onDisappear` does **not** fire when the app backgrounds a presented
/// `fullScreenCover`, so #139's unguarded `abandonSession()` never covers this
/// path. The observer is the whole defence.
///
/// **These tests deliberately re-enact the observer's body rather than posting
/// `UIApplication.didEnterBackgroundNotification`.** The real observer lives in
/// `AppContainer` (`Talaria/Stores/AppContainer.swift`, the
/// `didEnterBackgroundNotification` registration), which needs the ~100-line
/// container harness to build, and posting the notification would test
/// NotificationCenter rather than the decision. `simulateDidEnterBackground`
/// below is a line-for-line transcription of that closure's body: read the
/// two together, and if the observer ever grows a step this harness does not
/// have, these tests stop meaning what they claim.
@MainActor
struct TalkStoreBackgroundRevokeTests {

    // MARK: - Harness

    /// A voice service whose `startSession()` **parks** until the test releases
    /// it, which is the only way to hold a store inside the connect window long
    /// enough to background it.
    ///
    /// Polling, not a continuation, and deliberately BOUNDED: a stranded
    /// `CheckedContinuation` in a `@MainActor` service hangs the whole suite
    /// with no message, and this file exists to prove a lifecycle claim, not to
    /// win a concurrency-style argument.
    @MainActor
    final class ParkedStartVoiceService: VoiceSessionServiceProtocol {
        private(set) var startCallCount = 0
        private(set) var endCallCount = 0
        /// True from the moment `startSession()` is entered until it returns.
        private(set) var isInsideStart = false
        private var released = false

        var voiceState: VoiceState = .idle
        var connectionState: TalkConnectionState = .idle
        var transcriptItems: [TranscriptItem] = []
        var sessionDuration: TimeInterval = 0
        var isMuted = false
        var blockedReason: String?
        var statusMessage: String?
        var canStartSession = true
        var latencyMetrics = TalkLatencyMetrics()

        var snapshot: TalkSessionSnapshot {
            TalkSessionSnapshot(
                voiceState: voiceState,
                connectionState: connectionState,
                transcriptItems: transcriptItems,
                sessionDuration: sessionDuration,
                isMuted: isMuted,
                blockedReason: blockedReason,
                statusMessage: statusMessage,
                canStartSession: canStartSession,
                latencyMetrics: latencyMetrics,
                voiceSessionID: nil
            )
        }

        /// Only the initial snapshot is streamed. `TalkStore` also calls
        /// `applySnapshot(voiceService.snapshot)` directly at each decision
        /// point, and THAT is the path under test — leaving the hub silent
        /// keeps the assertions deterministic instead of racing two routes to
        /// the same flag.
        func events() -> AsyncStream<TalkSessionEvent> {
            AsyncStream { continuation in
                continuation.yield(.snapshot(snapshot))
                continuation.finish()
            }
        }

        func refreshReadiness() async {}

        func startSession() async {
            startCallCount += 1
            isInsideStart = true
            // Park until released, with a ceiling so a mistaken test fails
            // loudly instead of hanging.
            for _ in 0..<600 {
                if released { break }
                try? await Task.sleep(for: .milliseconds(5))
            }
            isInsideStart = false
            // The connect LANDS: this is the moment #254 is about.
            connectionState = .connected
            voiceState = .listening
        }

        func endSession() async {
            endCallCount += 1
            connectionState = .idle
            voiceState = .idle
        }

        func toggleMute() async { isMuted.toggle() }
        func manuallyInterruptAssistantOutput() {}

        @discardableResult
        func sendImage(_ imageData: Data, mimeType: String, triggerResponse: Bool) -> Bool { true }

        func release() { released = true }
    }

    /// A line-for-line transcription of `AppContainer`'s
    /// `didEnterBackgroundNotification` closure body. Returns whether the
    /// revoke fired, so the negative bar can assert on the decision as well as
    /// on its consequences.
    @discardableResult
    private func simulateDidEnterBackground(
        _ store: TalkStore,
        routeHasCarAudio: Bool = false
    ) async -> Bool {
        guard TalkBackgroundRule.shouldEndSession(
            isSessionActive: store.isSessionActive,
            isStartingSession: store.isStartingSession,
            routeHasCarAudio: routeHasCarAudio
        ) else { return false }
        await store.abandonSession()
        return true
    }

    /// Bounded spin on the main actor. Returns false on timeout rather than
    /// hanging, so a broken expectation reads as a failure and not as a stall.
    private func settle(
        within milliseconds: Int = 2_000,
        until predicate: @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<(milliseconds / 5) {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return predicate()
    }

    // MARK: - 254-B — backgrounding revokes a start in flight

    /// **Bar 254-B.** Backgrounding while a start is in flight revokes it, and
    /// the connect that lands afterwards does not flip the store live.
    ///
    /// RED-first against the pre-fix rule: with the observer gated on
    /// `isSessionActive` alone, `shouldEndSession` returns false here — the
    /// store is not active yet — so nothing is called, `endCallCount` stays 0,
    /// and the parked connect lands live in the background. That is the ghost.
    @Test func backgroundingDuringAStartRevokesIt() async {
        let service = ParkedStartVoiceService()
        let store = TalkStore(voiceService: service)

        let start = Task { await store.startSessionDirectly() }

        // Hold until the store is genuinely inside the connect window.
        #expect(await settle { service.isInsideStart })
        #expect(store.isStartingSession, "the start must be published before the first await")
        #expect(!store.isSessionActive, "the whole defect is that this flag is false here")

        let revoked = await simulateDidEnterBackground(store)
        #expect(revoked, "254-B: backgrounding mid-start must fire the revoke")
        #expect(service.endCallCount >= 1, "254-B: the voice service must record an endSession")

        // Let the parked connect land, exactly as a slow host would.
        service.release()
        await start.value

        #expect(!store.isSessionActive, "254-B: a connect that lands after the revoke must not go live")
        #expect(!store.isStartingSession, "the start flag must not survive its own start")
    }

    /// The CarPlay exemption survives the new arm (#19). A start in flight in a
    /// car is still a session CarPlay is driving.
    @Test func backgroundingDuringAStartUnderCarPlayRevokesNothing() async {
        let service = ParkedStartVoiceService()
        let store = TalkStore(voiceService: service)

        let start = Task { await store.startSessionDirectly() }
        #expect(await settle { service.isInsideStart })

        let revoked = await simulateDidEnterBackground(store, routeHasCarAudio: true)
        #expect(!revoked, "#19: CarPlay is exempt on the starting arm too")
        #expect(service.endCallCount == 0)

        service.release()
        await start.value
    }

    // MARK: - 254-C — backgrounding an idle store calls nothing

    /// **Bar 254-C — the negative case, and it is the reason the rule gained a
    /// third input instead of losing its first.**
    ///
    /// Firing the revoke on *every* backgrounding would call `endSession()`
    /// with no session live, which reaches
    /// `AudioSessionOffMain.setActive(false, .notifyOthersOnDeactivation)`
    /// unconditionally — the #84 shape, where each stray `stop()` reached
    /// `setActive(false)` on the shared session and killed the live mic.
    ///
    /// Green before and after the fix, by design: this is a regression guard,
    /// not a red-first bar, and saying so is cheaper than letting a future
    /// reader score it as evidence the fix works.
    @Test func backgroundingWithNoSessionAndNoStartCallsNothing() async {
        let service = ParkedStartVoiceService()
        let store = TalkStore(voiceService: service)

        #expect(!store.isSessionActive)
        #expect(!store.isStartingSession)

        let revoked = await simulateDidEnterBackground(store)
        #expect(!revoked, "254-C: an idle store must not fire the revoke")
        #expect(service.endCallCount == 0, "254-C: no endSession")
        #expect(service.startCallCount == 0)
    }

    /// The flag must not leak past its own start: a resolved session that has
    /// already ended leaves the store in the 254-C state, so a later
    /// backgrounding is silent. Without this, `isStartingSession` would turn
    /// every subsequent backgrounding into a stray deactivation.
    @Test func backgroundingAfterAResolvedSessionCallsNothing() async {
        let service = ParkedStartVoiceService()
        let store = TalkStore(voiceService: service)

        service.release()
        await store.startSessionDirectly()
        #expect(store.isSessionActive, "precondition: the start landed")
        #expect(!store.isStartingSession)

        await store.endSession()
        #expect(!store.isSessionActive)
        let endsAfterUserEnd = service.endCallCount

        let revoked = await simulateDidEnterBackground(store)
        #expect(!revoked)
        #expect(service.endCallCount == endsAfterUserEnd, "no second teardown")
    }

    /// A live session still tears down on background — #118's original
    /// guarantee, re-pinned through the new call site (`abandonSession`, which
    /// reaches `endSession` internally).
    @Test func backgroundingALiveSessionStillTearsItDown() async {
        let service = ParkedStartVoiceService()
        let store = TalkStore(voiceService: service)

        service.release()
        await store.startSessionDirectly()
        #expect(store.isSessionActive)

        let revoked = await simulateDidEnterBackground(store)
        #expect(revoked, "#118: a live session must not survive backgrounding")
        #expect(service.endCallCount >= 1)
        #expect(!store.isSessionActive)
    }
}
