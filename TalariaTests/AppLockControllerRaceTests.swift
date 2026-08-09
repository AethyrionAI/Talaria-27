import Foundation
import Testing
@testable import Talaria

// MARK: - #272 — the App Lock re-prompt loop: reproduction (272-A) and fix pins (272-E/F)
//
// Owen, 2026-07-25: the app "continually tries to unlock and won't stay
// stagnant on the app provided unlock prompt, and gives the system/faceid
// stuff." Reproduced here deterministically (bar 272-A), confirmed on device
// at millisecond resolution (272-C), and FIXED 2026-08-09 (bars 272-E/F;
// Option B — one auto-prompt per locked stretch). This file is both the
// no-device harness from the repro lane
// (`dispatch/OPUS-T27-272-applock-prereq.md` §1b) and the fix's pins
// (`dispatch/FABLE-T27-272-applock-fix.md`; bars in OPEN_ITEMS #272).
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
// **HISTORY: the reproducing cases below originally PINNED THE BUG** — the
// repro lane's scope was "reproduce, record, stop," so each asserted what the
// code actually did (the loop), flagged `PINS THE BUG`, keeping the
// reproduction executable and the gate green while the fix waited on Owen's
// ruling. That lane's header demanded the fix lane invert every one of them,
// and the 272-F fix commit did exactly that: the episode-attempt reset on
// the transition into `.locked` plus the `episodeAttempt == 0` fifth
// auto-auth guard, with the UNLOCK tap path left guard-free. The inverted
// cases now pin the FIX; each is flagged `INVERTED 2026-08-09` at the
// assertion it flipped.
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

    // MARK: - A-ii — the reproduction, inverted into the fix's pin

    /// **A-ii — WAS the reproduction; now pins the fix.**
    ///
    /// The Face ID sheet's own dismissal is the trigger. `AppLockCore.swift`
    /// states in its own comment that the sheet is `.inactive`; dismissing it
    /// therefore delivers `.active` (272-C confirmed iOS 27 really does).
    /// `scenePhaseChanged(to:)` still clears `didFailAuthentication = false`
    /// at the top of the function and calls `autoAuthenticateIfNeeded()` at
    /// the bottom of the SAME call — that clear is deliberate (it un-sticks
    /// a stale flag at the start of a NEW episode) — but the auto-prompt no
    /// longer keys on that flag alone: the `episodeAttempt == 0` guard holds
    /// because the episode's attempt was already consumed, and the counter
    /// resets only on the transition INTO `.locked`, never on a foreground.
    @Test func inactiveBlipAfterCancelledAttemptDoesNotReprompt() async {
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
        await settle()

        // INVERTED 2026-08-09 (was: callCount == 2, "REPRODUCED: a foreground
        // blip re-fires the prompt with no user tap").
        #expect(auth.callCount == 1, "FIXED: a foreground blip must not re-fire the prompt")
        #expect(auth.pendingCount == 0, "the sheet stays down")
        #expect(!controller.didFailAuthentication, "the .active reset still wipes the flag — the fifth guard is what holds")
        #expect(controller.showsRetryUnlockButton, "the UNLOCK button carries the episode after the wipe")
        #expect(auth.log == ["authenticate#1"])
    }

    /// **A-iii — the `.background` variant of A-ii; now pins the fix.**
    /// Same mechanism via a real background round trip rather than a blip,
    /// which is the shape `dispatch/DEVICE-PASS-RUNNING-LIST.md` already
    /// tried to provoke by hand. The cover never leaves `.locked` on this
    /// trip, so it is the SAME episode and the consumed attempt still blocks.
    @Test func backgroundRoundTripAfterCancelledAttemptDoesNotReprompt() async {
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
        await settle()

        // INVERTED 2026-08-09 (was: callCount == 2, "REPRODUCED: a background
        // round trip re-fires the prompt").
        #expect(auth.callCount == 1, "FIXED: a background round trip must not re-fire the prompt")
        #expect(auth.pendingCount == 0, "the sheet stays down")
        #expect(controller.showsRetryUnlockButton, "the UNLOCK button is the way forward")
    }

    /// **A-ii variant — the attempt is INTERRUPTED rather than declined; now
    /// pins the fix.** The scene leaves while `evaluatePolicy` is still
    /// pending (the OS cancels it and `BiometricAppLockAuthenticator`'s
    /// `catch { return false }` reports `false`), then comes back. The
    /// interrupted attempt still counted against the episode, so the return
    /// must not re-arm.
    @Test func interruptedAttemptResolvingAfterBackgroundDoesNotRepromptOnReturn() async {
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
        await settle()

        // INVERTED 2026-08-09 (was: callCount == 2, "REPRODUCED: an
        // interrupted attempt re-arms on return").
        #expect(auth.callCount == 1, "FIXED: an interrupted attempt must not re-arm on return")
        #expect(auth.pendingCount == 0, "the sheet stays down")
        #expect(controller.showsRetryUnlockButton, "the UNLOCK button is the way forward")
    }

    // MARK: - A-iv — the loop is gone: the cover settles on the retry button

    /// **A-iv inverted — one cancellation, five foreground blips, ONE
    /// prompt.** The original pinned the unbounded loop (five cancellations,
    /// zero taps, SIX prompts — the symptom in Owen's own words: the prompt
    /// "won't stay stagnant"); on device it reached attempt=4 in ~7 s with
    /// only backgrounding ending it (272-C). Fixed, the episode consumes its
    /// one auto-prompt and every later foreground settles on the UNLOCK
    /// button, which stays offered throughout.
    @Test func repeatedForegroundBlipsAfterOneCancelSettleOnTheRetryButton() async {
        let auth = GatedAppLockAuthenticator()
        let controller = makeController(authenticator: auth)

        controller.scenePhaseChanged(to: .active)
        await waitForPark(auth)
        #expect(auth.pendingCount == 1, "the auto-fired attempt must actually be parked (anti-vacuous)")

        auth.release(false)
        await settle()
        #expect(controller.didFailAuthentication, "a cancelled attempt flags retry")

        for round in 1...5 {
            controller.scenePhaseChanged(to: .inactive)
            controller.scenePhaseChanged(to: .active)
            await settle()

            // INVERTED 2026-08-09 (was: callCount == round + 1 — one fresh
            // prompt per blip, unbounded).
            #expect(auth.callCount == 1, "round \(round): no re-fire, ever")
            #expect(auth.pendingCount == 0, "round \(round): the sheet stays down")
            #expect(controller.showsRetryUnlockButton, "round \(round): the UNLOCK button stands")
        }

        // INVERTED 2026-08-09 (was: callCount == 6, "the loop is unbounded").
        #expect(auth.callCount == 1, "FIXED: one auto-prompt, five blips, zero re-prompts")
        #expect(controller.cover == .locked, "still locked — the button, not a fresh prompt, is the way forward")
    }

    // MARK: - 272-E — the fix's contract (written RED-FIRST against HEAD)

    /// **Bar 272-E — one auto-prompt per locked stretch (Option B, ruled
    /// 2026-08-09).** Drives `scenePhaseChanged(to:)` only — never
    /// `requestUnlock()` directly — with the gated authenticator:
    /// auto-prompt → the user cancels → the sheet's dismissal blips the
    /// scene (`.inactive` → `.active`) → NO second `authenticate` call may
    /// fire without a tap. Per the bar this was run RED against HEAD before
    /// the fix (HEAD re-fires: callCount reached 2; failure text recorded
    /// verbatim in OPEN_ITEMS #272) and is made green by 272-F's fix —
    /// the episode-attempt reset on the transition into `.locked` plus the
    /// `episodeAttempt == 0` fifth auto-auth guard.
    @Test func bar272E_cancelledAutoPromptDoesNotRefireOnForegroundBlip() async {
        let auth = GatedAppLockAuthenticator()
        let controller = makeController(authenticator: auth)

        controller.scenePhaseChanged(to: .active)
        await waitForPark(auth)
        #expect(auth.pendingCount == 1, "the auto-fired attempt must actually be parked (anti-vacuous)")
        #expect(auth.callCount == 1, "a fresh locked stretch auto-prompts exactly once")

        // The user cancels the system sheet.
        auth.release(false)
        await settle()
        #expect(controller.cover == .locked)

        // Dismissing the sheet blips the scene. No tap anywhere.
        controller.scenePhaseChanged(to: .inactive)
        controller.scenePhaseChanged(to: .active)
        await settle()

        #expect(auth.callCount == 1, "272-E: no second authenticate call may fire without a user tap")
        #expect(auth.pendingCount == 0, "the sheet stays down — nothing may be parked")
    }

    // MARK: - 272-F — positive pins (the fix must not over-reach)

    /// A FRESH locked stretch still auto-prompts exactly once — the
    /// cold-launch shape. Unchanged from today, pinned so the new guard can
    /// never eat the first prompt.
    @Test func coldLaunchLockedStretchAutoPromptsExactlyOnce() async {
        let auth = GatedAppLockAuthenticator()
        let controller = makeController(authenticator: auth)
        #expect(controller.cover == .locked, "cold launch with the lock enabled must be locked")

        controller.scenePhaseChanged(to: .active)
        await waitForPark(auth)
        #expect(auth.pendingCount == 1, "the auto-prompt must actually park (anti-vacuous)")
        #expect(auth.callCount == 1, "exactly one auto-prompt")

        auth.release(true)
        await settle()
        #expect(controller.cover == .none)
    }

    /// A FRESH locked stretch still auto-prompts exactly once — the
    /// grace-expiry shape: successful unlock, background past grace, return.
    /// This is the episode BOUNDARY doing its job: the counter that blocked
    /// the old episode's re-prompts must not silence the new episode's one
    /// auto-prompt.
    @Test func freshLockedStretchAfterGraceExpiryAutoPromptsExactlyOnce() async {
        let auth = GatedAppLockAuthenticator()
        let controller = makeController(authenticator: auth)

        controller.scenePhaseChanged(to: .active)
        await waitForPark(auth)
        #expect(auth.pendingCount == 1, "the auto-fired attempt must actually be parked (anti-vacuous)")
        auth.release(true)
        await settle()
        #expect(controller.cover == .none, "unlocked")

        // Background past the (immediate) grace period and return: the cover
        // newly locks — a NEW episode.
        controller.scenePhaseChanged(to: .background)
        controller.scenePhaseChanged(to: .active)
        await waitForPark(auth, expecting: 1)
        #expect(auth.pendingCount == 1, "the new episode's auto-prompt must actually park (anti-vacuous)")
        #expect(auth.callCount == 2, "a fresh locked stretch fires exactly ONE fresh auto-prompt")

        auth.release(true)
        await settle()
        #expect(controller.cover == .none)
        #expect(auth.callCount == 2, "…and exactly one")
    }

    /// The UNLOCK button's path stays guard-free: after a cancel and the
    /// blip that wipes the failure flag, a tap (the overlay's exact
    /// `Task { await requestUnlock() }`) always gets a fresh attempt — and a
    /// successful one ends the episode. This is the ruling's accepted cost
    /// made concrete: within a cancelled episode the tap is the ONLY path,
    /// and it must work.
    @Test func unlockTapAfterCancelAndBlipStillAuthenticates() async {
        let auth = GatedAppLockAuthenticator()
        let controller = makeController(authenticator: auth)

        controller.scenePhaseChanged(to: .active)
        await waitForPark(auth)
        #expect(auth.pendingCount == 1, "the auto-fired attempt must actually be parked (anti-vacuous)")
        auth.release(false)
        await settle()

        controller.scenePhaseChanged(to: .inactive)
        controller.scenePhaseChanged(to: .active)
        await settle()
        #expect(auth.callCount == 1, "no auto re-fire before the tap")
        #expect(controller.showsRetryUnlockButton, "the button is offered")

        // The user taps UNLOCK — AppLockOverlayView's exact action.
        Task { await controller.requestUnlock() }
        await waitForPark(auth, expecting: 1)
        #expect(auth.pendingCount == 1, "the tap's attempt must actually park (anti-vacuous)")
        #expect(auth.callCount == 2, "a user tap ALWAYS gets an attempt")

        auth.release(true)
        await settle()
        #expect(controller.cover == .none, "the tap's success unlocks")
    }

    /// The episode-boundary reset itself, exercised on the one path that
    /// exits `.locked` WITHOUT touching the counter: a capability change
    /// neutralizing the lock mid-episode (`refreshCapability` →
    /// `.unavailable` → effective configuration disabled) bypasses both
    /// `requestUnlock`'s success reset and `configurationChanged`'s disable
    /// reset. When the lock later re-arms, the transition into `.locked`
    /// must clear the stale count — or the new episode's auto-prompt would
    /// be silenced forever.
    @Test func staleAttemptCountDoesNotLeakIntoTheNextLockEpisode() async {
        let auth = GatedAppLockAuthenticator()
        let controller = makeController(authenticator: auth)

        controller.scenePhaseChanged(to: .active)
        await waitForPark(auth)
        #expect(auth.pendingCount == 1, "the auto-fired attempt must actually be parked (anti-vacuous)")
        auth.release(false)
        await settle()
        #expect(controller.episodeAttempt == 1, "one consumed attempt this episode")

        // Passcode removed while backgrounded: the next foreground
        // neutralizes the lock without passing through success or
        // configurationChanged.
        auth.stubbedCapability = .unavailable
        controller.scenePhaseChanged(to: .inactive)
        controller.scenePhaseChanged(to: .active)
        await settle()
        #expect(controller.cover == .none, "capability loss neutralizes the lock")
        #expect(controller.episodeAttempt == 1, "…and nothing on that path reset the counter (the leak this pin guards)")

        // Passcode restored; a background round trip re-arms the lock.
        auth.stubbedCapability = .faceID
        controller.scenePhaseChanged(to: .background)
        controller.scenePhaseChanged(to: .active)
        await waitForPark(auth, expecting: 1)
        #expect(auth.pendingCount == 1, "the NEW episode's auto-prompt fired and parked (anti-vacuous)")
        #expect(auth.callCount == 2, "the transition into .locked reset the stale count")

        auth.release(true)
        await settle()
    }

    /// The retry surface across the episode (what `AppLockOverlayView` keys
    /// on): hidden while the fresh episode's attempt is in flight, offered
    /// from the cancel onward, and — the #272 trap — STILL offered after the
    /// sheet's dismissal blip wipes `didFailAuthentication`. Without this,
    /// the fixed guard would hold the prompt down AND the button would
    /// vanish, stranding a cancelled episode with no way forward: exactly
    /// what bar 272-H's "reachable and works" forbids.
    @Test func retrySurfaceSurvivesTheForegroundBlipThatWipesTheFailureFlag() async {
        let auth = GatedAppLockAuthenticator()
        let controller = makeController(authenticator: auth)

        controller.scenePhaseChanged(to: .active)
        await waitForPark(auth)
        #expect(auth.pendingCount == 1, "the auto-fired attempt must actually be parked (anti-vacuous)")
        #expect(!controller.showsRetryUnlockButton, "no button behind the fresh episode's own sheet")

        auth.release(false)
        await settle()
        #expect(controller.didFailAuthentication)
        #expect(controller.showsRetryUnlockButton, "the cancel offers the button")

        controller.scenePhaseChanged(to: .inactive)
        controller.scenePhaseChanged(to: .active)
        await settle()
        #expect(!controller.didFailAuthentication, "the .active reset wiped the flag…")
        #expect(controller.showsRetryUnlockButton, "…but the button MUST survive the wipe (it is the only path)")
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
