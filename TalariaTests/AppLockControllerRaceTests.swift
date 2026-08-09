import Foundation
import Testing
@testable import Talaria

// MARK: - #272 bar 272-A — the App Lock re-prompt loop, no-device reproduction
//
// Owen, 2026-07-25: the app "continually tries to unlock and won't stay
// stagnant on the app provided unlock prompt, and gives the system/faceid
// stuff." Unreproduced since; never diagnosed. These tests are the no-device
// half — a deterministic harness for the hypothesis in
// `dispatch/OPUS-T27-272-applock-prereq.md` §1b and the bars in OPEN_ITEMS
// #272.
//
// **Why the existing suite cannot express any of this.** Every case in
// `AppLockTests.swift`'s `AppLockControllerTests` drives `requestUnlock()`
// DIRECTLY and awaits it. The `autoAuthenticateIfNeeded()` →
// `Task { await requestUnlock() }` path IS spawned there (by the
// `scenePhaseChanged(to: .active)` those tests call first) but is never
// awaited and never asserted on — the tell is
// `retryAfterFailureUsesNewEvaluation`'s `#expect(auth.authenticateCallCount
// >= 2)`, a `>=` hedging against an auto-fire nobody controls. And
// `MockAppLockAuthenticator.authenticate(reason:)` returns SYNCHRONOUSLY, so
// awaiting it never yields to the scheduler: no interleaving can be
// expressed at all. `GatedAppLockAuthenticator` below genuinely parks on a
// `CheckedContinuation` (the `GatedSecureStore` / `DebounceGate` idiom), so
// the test controls exactly when a pending attempt resolves relative to a
// second `scenePhaseChanged` delivery.
//
// ⚠️ **THESE ASSERTIONS PIN THE BUG, NOT THE DESIRED BEHAVIOUR.** #272's
// dispatch scope is "reproduce, record, stop" — the fix is explicitly a
// later lane's work, reviewed against bar 272-D. So the reproducing cases
// below assert what the code ACTUALLY does today, each one flagged
// `PINS THE BUG`, so the reproduction survives as an executable artifact and
// the gate stays green. **The fix lane MUST invert every `PINS THE BUG`
// assertion**; a fix that leaves them passing has not fixed anything.
//
// Everything here is `@MainActor`, so there is no true parallelism —
// interleaving is possible only at `await` suspension points, which is what
// makes these deterministic rather than flaky.

// MARK: - The gate

/// An `AppLockAuthenticating` that ACTUALLY suspends inside
/// `authenticate(reason:)` until the test resumes it, and counts every call.
///
/// The live `BiometricAppLockAuthenticator` suspends for as long as the
/// system Face ID / passcode sheet is on screen — seconds, during which the
/// scene phase demonstrably moves (`AppLockCore.swift`'s own comment: "the
/// Face ID sheet itself" is `.inactive`). Nothing in the shipping test suite
/// could model that window. This can.
@MainActor
private final class GatedAppLockAuthenticator: AppLockAuthenticating {
    var stubbedCapability: AppLockCapability = .faceID

    /// Every `authenticate` call, in order — the evidence, not the wording
    /// of the assertions.
    private(set) var log: [String] = []
    private(set) var callCount = 0

    private var continuations: [CheckedContinuation<Bool, Never>] = []

    /// How many attempts are suspended right now. Every park point asserts
    /// on this: a repro that never parked would prove nothing at all.
    var pendingCount: Int { continuations.count }

    func capability() -> AppLockCapability { stubbedCapability }

    func authenticate(reason: String) async -> Bool {
        callCount += 1
        log.append("authenticate#\(callCount)")
        return await withCheckedContinuation { continuations.append($0) }
    }

    /// Resumes every parked attempt with `result` — the user cancelling the
    /// sheet (`false`) or succeeding (`true`).
    func release(_ result: Bool) {
        let held = continuations
        continuations = []
        for continuation in held { continuation.resume(returning: result) }
    }
}

@MainActor
struct AppLockControllerRaceTests {

    // MARK: - Fixtures

    private func makeController(
        grace: AppLockGracePeriod = .immediate,
        authenticator: GatedAppLockAuthenticator
    ) -> AppLockController {
        AppLockController(
            configuration: { AppLockConfiguration(isEnabled: true, gracePeriod: grace) },
            authenticator: authenticator,
            now: { Date(timeIntervalSince1970: 2_000_000) }
        )
    }

    /// Spins until `authenticator` has parked at least `count` attempts.
    /// Bounded, and deliberately does NOT assert — every call site asserts on
    /// `pendingCount` itself so a failure message names the interleaving.
    private func waitForPark(
        _ authenticator: GatedAppLockAuthenticator,
        expecting count: Int = 1
    ) async {
        var spins = 0
        while authenticator.pendingCount < count, spins < 1_000 {
            await Task.yield()
            spins += 1
        }
        let deadline = Date().addingTimeInterval(2)
        while authenticator.pendingCount < count, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(2))
        }
    }

    /// Lets the MainActor drain: a resumed continuation returns into
    /// `requestUnlock()`'s tail (flag writes + `refreshCover()`), and a
    /// freshly spawned `Task { await requestUnlock() }` needs a hop to start.
    private func settle(_ spins: Int = 200) async {
        for _ in 0..<spins { await Task.yield() }
    }

    // MARK: - A-i — a second `.active` arriving while the FIRST attempt is parked

    /// §1b-2's TOCTOU window, driven through the realistic delivery shape
    /// (`.active` → `.inactive` → `.active`, since SwiftUI's `onChange` only
    /// fires on a CHANGE). Result: the guard HOLDS — `requestUnlock()`
    /// re-checks `!isAuthenticating` after the `Task` body starts, and
    /// because `isAuthenticating = true` is set synchronously before its
    /// first `await`, a serial MainActor leaves no window.
    @Test func secondActiveWhileFirstAttemptParkedDoesNotDoubleFire() async {
        let auth = GatedAppLockAuthenticator()
        let controller = makeController(authenticator: auth)
        #expect(controller.cover == .locked, "cold launch with the lock enabled must be locked")

        controller.scenePhaseChanged(to: .active)
        await waitForPark(auth)
        #expect(auth.pendingCount == 1, "the auto-fired attempt must actually be parked (anti-vacuous)")
        #expect(auth.callCount == 1)

        // The sheet is up; the scene blips and comes back.
        controller.scenePhaseChanged(to: .inactive)
        controller.scenePhaseChanged(to: .active)
        await settle()

        #expect(auth.callCount == 1, "no second prompt may fire while one attempt is still in flight")
        #expect(auth.pendingCount == 1)
        #expect(controller.isAuthenticating)

        auth.release(false)
        await settle()
        #expect(controller.didFailAuthentication)
    }

    /// A-v — the pure structural TOCTOU probe: two `.active` deliveries with
    /// NO suspension point between them, which is the only shape that could
    /// see `isAuthenticating` before the spawned `Task` sets it. (SwiftUI
    /// cannot deliver `.active` twice in a row — `onChange` fires on change —
    /// so this is a probe of the guard, not a claim about production.)
    /// Result: still one prompt. §1b-2 is REFUTED.
    @Test func synchronousDoubleActiveSpawnsOnlyOneEvaluation() async {
        let auth = GatedAppLockAuthenticator()
        let controller = makeController(authenticator: auth)

        controller.scenePhaseChanged(to: .active)
        controller.scenePhaseChanged(to: .active)   // no `await` between: the TOCTOU window
        await waitForPark(auth)
        await settle()

        #expect(auth.pendingCount == 1, "an attempt must actually be parked (anti-vacuous)")
        #expect(auth.callCount == 1, "two Task spawns must collapse to one evaluation")
        #expect(auth.log == ["authenticate#1"])

        auth.release(false)
        await settle()
    }

    // MARK: - A-ii — the reproduction

    /// **A-ii — REPRODUCES THE LOOP. PINS THE BUG.**
    ///
    /// The Face ID sheet's own dismissal is the trigger. `AppLockCore.swift`
    /// states in its own comment that the sheet is `.inactive`; dismissing it
    /// therefore delivers `.active`. `scenePhaseChanged(to:)` clears
    /// `didFailAuthentication = false` UNCONDITIONALLY at the top of the
    /// function, and then calls `autoAuthenticateIfNeeded()` at the bottom of
    /// the SAME call — so the flag that is the class's only anti-loop guard
    /// is destroyed before it is ever read. A cancelled attempt re-arms
    /// itself, with no user input whatsoever.
    ///
    /// What this test establishes is a CONDITIONAL, and the distinction is
    /// load-bearing: *given* an `.active` delivery after a failed attempt
    /// within the same lock episode, the controller re-prompts with no user
    /// interaction. Whether iOS 27 delivers that `.active` on sheet dismissal
    /// (and orders it after `evaluatePolicy` resolves) is a device fact this
    /// test cannot settle — that is bar 272-C's job, and 272-B's logging is
    /// what will read it.
    ///
    /// **The fix lane must invert this: `callCount` should stay 1 and the
    /// retry button should be the only way forward.**
    @Test func inactiveBlipAfterCancelledAttemptRePromptsWithoutUserTap() async {
        let auth = GatedAppLockAuthenticator()
        let controller = makeController(authenticator: auth)

        controller.scenePhaseChanged(to: .active)
        await waitForPark(auth)
        #expect(auth.pendingCount == 1, "the auto-fired attempt must actually be parked (anti-vacuous)")

        // The user cancels the sheet.
        auth.release(false)
        await settle()
        #expect(controller.didFailAuthentication, "a cancelled attempt must flag retry")
        #expect(controller.cover == .locked)
        #expect(auth.callCount == 1)

        // Dismissing the sheet takes the scene .inactive and back .active.
        // No tap on the retry button. No backgrounding. Nothing the user did.
        controller.scenePhaseChanged(to: .inactive)
        controller.scenePhaseChanged(to: .active)
        await waitForPark(auth, expecting: 1)
        await settle()

        // PINS THE BUG — this is the loop.
        #expect(
            auth.callCount == 2,
            "REPRODUCED: a foreground blip re-fires the prompt with no user tap"
        )
        #expect(!controller.didFailAuthentication, "the retry flag was wiped by the .active reset")
        #expect(auth.log == ["authenticate#1", "authenticate#2"])

        auth.release(false)
        await settle()
    }

    /// **A-iii — the `.background` variant of A-ii. PINS THE BUG.**
    /// Same mechanism via a real background round trip rather than a blip,
    /// which is the shape `dispatch/DEVICE-PASS-RUNNING-LIST.md` already
    /// tried to provoke by hand.
    @Test func backgroundRoundTripAfterCancelledAttemptRePromptsWithoutUserTap() async {
        let auth = GatedAppLockAuthenticator()
        let controller = makeController(authenticator: auth)

        controller.scenePhaseChanged(to: .active)
        await waitForPark(auth)
        #expect(auth.pendingCount == 1, "the auto-fired attempt must actually be parked (anti-vacuous)")

        auth.release(false)
        await settle()
        #expect(controller.didFailAuthentication)

        controller.scenePhaseChanged(to: .background)
        controller.scenePhaseChanged(to: .active)
        await waitForPark(auth, expecting: 1)
        await settle()

        // PINS THE BUG.
        #expect(auth.callCount == 2, "REPRODUCED: a background round trip re-fires the prompt")
        #expect(!controller.didFailAuthentication)

        auth.release(false)
        await settle()
    }

    /// **A-ii variant — the attempt is INTERRUPTED rather than declined.**
    /// The scene leaves while `evaluatePolicy` is still pending (the OS
    /// cancels it and `BiometricAppLockAuthenticator`'s `catch { return
    /// false }` reports `false`), then comes back. Same collapse. PINS THE BUG.
    @Test func interruptedAttemptResolvingAfterBackgroundRePromptsOnReturn() async {
        let auth = GatedAppLockAuthenticator()
        let controller = makeController(authenticator: auth)

        controller.scenePhaseChanged(to: .active)
        await waitForPark(auth)
        #expect(auth.pendingCount == 1, "the auto-fired attempt must actually be parked (anti-vacuous)")

        // Backgrounded with the sheet still up — the attempt is still pending.
        controller.scenePhaseChanged(to: .background)
        await settle()
        #expect(auth.pendingCount == 1, "the attempt is still in flight while backgrounded")
        #expect(auth.callCount == 1, "a background delivery must not fire a prompt")

        // The OS cancels the pending evaluation; it resolves false.
        auth.release(false)
        await settle()
        #expect(controller.didFailAuthentication)

        controller.scenePhaseChanged(to: .active)
        await waitForPark(auth, expecting: 1)
        await settle()

        // PINS THE BUG.
        #expect(auth.callCount == 2, "REPRODUCED: an interrupted attempt re-arms on return")

        auth.release(false)
        await settle()
    }

    // MARK: - A-iv — the loop is unbounded

    /// **A-iv — five cancellations, zero user taps, six prompts. PINS THE BUG.**
    /// This is the symptom in its own words: the prompt "won't stay stagnant."
    /// Nothing in the controller bounds this — there is no attempt cap, no
    /// backoff, and the retry button is never the only way forward because
    /// the flag that would reveal it is cleared on every foreground.
    @Test func repeatedCancellationsNeverSettleOnTheRetryButton() async {
        let auth = GatedAppLockAuthenticator()
        let controller = makeController(authenticator: auth)

        controller.scenePhaseChanged(to: .active)
        await waitForPark(auth)
        #expect(auth.pendingCount == 1, "the auto-fired attempt must actually be parked (anti-vacuous)")

        for round in 1...5 {
            auth.release(false)
            await settle()
            #expect(controller.didFailAuthentication, "round \(round): a cancelled attempt flags retry…")

            controller.scenePhaseChanged(to: .inactive)
            controller.scenePhaseChanged(to: .active)
            await waitForPark(auth, expecting: 1)
            await settle()

            // …and the very next foreground event throws that flag away.
            #expect(
                !controller.didFailAuthentication,
                "round \(round): the retry flag did not survive the foreground"
            )
            #expect(
                auth.callCount == round + 1,
                "round \(round): the prompt re-fired instead of settling"
            )
        }

        // PINS THE BUG: 1 auto-prompt + 5 unrequested re-prompts.
        #expect(auth.callCount == 6, "REPRODUCED: the loop is unbounded — six prompts, zero taps")
        #expect(controller.cover == .locked, "and the app never got past the lock")

        auth.release(false)
        await settle()
    }

    // MARK: - Controls

    /// The contrast that isolates the mechanism to the `.active` reset, not
    /// to anything about repeated evaluation: with NO foreground event after
    /// a cancelled attempt, the retry flag stands and nothing re-fires.
    @Test func withoutAForegroundEventTheRetryFlagStands() async {
        let auth = GatedAppLockAuthenticator()
        let controller = makeController(authenticator: auth)

        controller.scenePhaseChanged(to: .active)
        await waitForPark(auth)
        #expect(auth.pendingCount == 1, "the auto-fired attempt must actually be parked (anti-vacuous)")

        auth.release(false)
        await settle()
        #expect(controller.didFailAuthentication)

        // Inactive only — no return to .active.
        controller.scenePhaseChanged(to: .inactive)
        await settle()

        #expect(auth.callCount == 1, "no foreground event, no re-fire")
        #expect(controller.didFailAuthentication, "the flag survives when nothing clears it")
    }

    /// A successful unlock ends the episode: the cover clears and the
    /// auto-fire path stops arming, so the loop cannot be an artifact of the
    /// harness parking forever.
    @Test func successfulUnlockEndsTheEpisode() async {
        let auth = GatedAppLockAuthenticator()
        let controller = makeController(authenticator: auth)

        controller.scenePhaseChanged(to: .active)
        await waitForPark(auth)
        #expect(auth.pendingCount == 1, "the auto-fired attempt must actually be parked (anti-vacuous)")

        auth.release(true)
        await settle()
        #expect(controller.cover == .none)
        #expect(!controller.didFailAuthentication)

        controller.scenePhaseChanged(to: .inactive)
        controller.scenePhaseChanged(to: .active)
        await settle()
        #expect(auth.callCount == 1, "an unlocked app must not prompt again")
    }
}
