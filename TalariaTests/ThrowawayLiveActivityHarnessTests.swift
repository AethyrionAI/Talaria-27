#if DEBUG
import ActivityKit
import Foundation
import Testing
@testable import Talaria

/// **#250 bar 250T-B** — the Debug-only throwaway Live Activity trigger that
/// makes device row §R2 runnable.
///
/// What these have to prove, and why each half is here:
///
/// - **Through the REAL service.** R2's question is what the *real* activity
///   puts in the island's leading icon slot, so a harness that renders a mock
///   attributes type or drives `LiveActivityPreviews`' SwiftUI scaffolding
///   answers a different question. The assertions therefore read
///   `LiveActivityService`'s own `hasActiveActivity` — the same
///   `currentActivity` handle production's `startToolCall` sets and
///   `endActivity()` clears — rather than any counter the harness keeps for
///   itself.
/// - **Ends BOTH ways, no zombie.** Live Activities draw on a system budget; a
///   leaked throwaway would make the REAL run activity flaky, and that failure
///   would read as a #250 regression while being the harness's fault.
///
/// **On what the start assertion may compare against — corrected by #326,
/// 2026-08-11, after this suite red-gated a clean tree.** It used to read
/// `hasActiveActivity == service.isAvailable`, reasoning that production's
/// `guard isAvailable else { return }` makes an activity exist *exactly when*
/// activities are enabled. The instinct was right — an environment-adaptive
/// assertion beats a bare `== true` — but the equality covered only half the
/// path. **`isAvailable` gates the ATTEMPT and says nothing about whether the
/// attempt SUCCEEDS**, and the equality quietly asserted that it always does.
///
/// Measured (#326-B, on `CC-321-iPhone-Air`, iOS 27.0 sim, verbatim):
///
///     foreign_refused_at=5 domain=com.apple.ActivityKit.ActivityAuthorization
///     code=5 raw=targetMaximumExceeded | foreign_vended=5 |
///     enabled_under_load=true | isAvailable=true | hasActiveActivity=false |
///     OLD_ASSERTION_HOLDS=false
///
/// So: the ceiling is **five concurrent activities per APP**, shared across
/// attributes types, and the sixth request throws while `areActivitiesEnabled`
/// still reads `true`. In that state the old equality read `false == true`.
///
/// **Why that state is reachable in a gate run rather than exotic.** This test
/// host is ONE app running many suites in parallel, and other suites vend real
/// Live Activities through the same production path: `AppStoresTests` drives
/// real `ChatStore`s, and `ChatStore`'s `tool.started` handling calls
/// `chatLiveActivity.startToolCall(...)`. A free slot is therefore a contended,
/// process-global resource, not a constant — which is also why the two tests
/// below failed in a 2116-test gate and passed 5/5 when the suite was run
/// alone, on the same commit, on both sims (#326-A).
///
/// **What replaced the premise, and why not something simpler.** Deleting the
/// assertion was not available: it is the only thing pinning the throwaway to
/// the production start path, which is 250T-B's whole content. The three tests
/// that need a vend now (a) carry an `.enabled` condition that MEASURES whether
/// ActivityKit will vend on this host instead of predicting it from a flag, so
/// a host that refuses SKIPS visibly — the gate prints and counts skips — and
/// (b) re-establish a free slot immediately before the tap, so ordinary
/// cross-suite contention is ridden out rather than reported as a defect. The
/// assertion itself is then the strong, premise-free `hasActiveActivity` — it
/// still fails loudly if the harness ever stops driving the production service.
@Suite(.serialized)
struct ThrowawayLiveActivityHarnessTests {

    /// Bounded pump — polls a MainActor condition instead of guessing at a
    /// sleep. Returns whether the condition ever held.
    @MainActor
    private func waitUntil(
        _ description: String,
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<400 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("timed out waiting for: \(description)")
        return false
    }

    /// Clears any activity a previous test (or a previous run of the app in
    /// this simulator) left behind. `endActivity()` hands the actual `end()` to
    /// a detached task, so this waits for the system list to drain rather than
    /// assuming it drained — otherwise `adoptExistingActivityIfNeeded()` would
    /// pick a stale activity up and the next test would assert on it.
    @MainActor
    private func drainExistingActivities() async {
        LiveActivityService.endAllActivities()
        _ = await waitUntil("the system activity list to drain") {
            Activity<HermesActivityAttributes>.activities.isEmpty
        }
    }

    /// Asks ActivityKit the question the old assertion only inferred: **will a
    /// request actually succeed right now?** Requests one activity of the real
    /// production type and hands it straight back.
    ///
    /// Returns `nil` when a vend succeeded, or the refusal verbatim when it did
    /// not — so a caller can say WHY instead of printing a bare boolean
    /// mismatch, which is what the 2026-08-11 red gate left its reader with.
    ///
    /// Bounded-retry, because the ceiling is per app and this host runs suites
    /// in parallel: a slot occupied by another suite's `ChatStore` activity is
    /// an ordinary transient, not a verdict.
    @MainActor
    static func vendRefusal(attempts: Int = 120) async -> String? {
        var last = "no attempt was made"
        for _ in 0..<max(1, attempts) {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                return "areActivitiesEnabled == false (Live Activities are switched off on this host)"
            }
            do {
                let probe = try Activity.request(
                    attributes: HermesActivityAttributes(agentName: "Hermes"),
                    content: .init(
                        state: .init(status: "vend probe", toolName: nil, elapsedSeconds: 0,
                                     startDate: .now, sessionType: "tool"),
                        staleDate: nil),
                    pushType: nil)
                await probe.end(nil, dismissalPolicy: .immediate)
                return nil
            } catch {
                last = String(describing: error)
                try? await Task.sleep(for: .milliseconds(25))
            }
        }
        return last
    }

    /// The in-test half of the precondition. The `.enabled` condition proved a
    /// vend was possible when the test was SELECTED; this proves it again
    /// immediately before the tap and leaves the system list empty, so the
    /// service vends rather than adopting the probe.
    ///
    /// Records an issue naming the refusal if the slot never frees — five
    /// seconds of sustained starvation inside one test host is a fact worth
    /// seeing, and it now arrives with its cause attached.
    @MainActor
    private func requireAFreeActivitySlot() async {
        if let refusal = await Self.vendRefusal() {
            Issue.record("ActivityKit would not vend for the whole precondition window — last refusal: \(refusal)")
        }
        await drainExistingActivities()
    }

    /// Skip reason shared by every test below that needs ActivityKit to vend.
    /// A skip is not a pass: the gate prints and counts these, and the tracker
    /// item named here carries the measurement behind the condition.
    /// Typed as `Comment` on purpose: `.enabled(_:)` takes a `Comment?`, and a
    /// bare `String` variable does not implicitly convert (a string *literal*
    /// does, which is why the sibling suites get away with inlining theirs).
    static let vendRequired: Comment = "ActivityKit must actually VEND on this host — measured, not inferred from areActivitiesEnabled (OPEN_ITEMS #326)"

    // MARK: - 250T-B: it ends on a second tap

    @MainActor
    @Test(.enabled(ThrowawayLiveActivityHarnessTests.vendRequired) {
        await ThrowawayLiveActivityHarnessTests.vendRefusal() == nil
    })
    func aSecondTapEndsTheThrowawayAndLeavesNoZombie() async {
        await drainExistingActivities()
        await requireAFreeActivitySlot()
        let service = LiveActivityService()
        // A long window so the timeout cannot be what ends this one — the
        // second tap has to be doing the work.
        let harness = ThrowawayLiveActivityHarness(service: service, autoEndAfter: .seconds(600))

        #expect(harness.isRunning == false)
        #expect(service.hasActiveActivity == false, "a fresh service must hold no activity")

        harness.toggle()   // first tap
        #expect(harness.isRunning)
        #expect(service.hasActiveActivity,
                "the throwaway must go through the production start path — a free slot was measured immediately above, so a missing handle means the tap never reached LiveActivityService")

        harness.toggle()   // second tap
        #expect(harness.isRunning == false)
        #expect(harness.lastEndReason == .secondTap)
        #expect(harness.endCount == 1)
        #expect(service.hasActiveActivity == false,
                "the second tap must clear production's own handle — a surviving handle is the zombie 250T-B forbids")
        _ = await waitUntil("the system activity list to drain after the second tap") {
            Activity<HermesActivityAttributes>.activities.isEmpty
        }
        #expect(Activity<HermesActivityAttributes>.activities.isEmpty,
                "no throwaway may outlive its second tap at the system level either")
    }

    // MARK: - 250T-B: it ends on the timeout, with nobody tapping

    @MainActor
    @Test(.enabled(ThrowawayLiveActivityHarnessTests.vendRequired) {
        await ThrowawayLiveActivityHarnessTests.vendRefusal() == nil
    })
    func theAutoEndWindowEndsAThrowawayNobodyTappedAgain() async {
        await drainExistingActivities()
        await requireAFreeActivitySlot()
        let service = LiveActivityService()
        let harness = ThrowawayLiveActivityHarness(service: service, autoEndAfter: .milliseconds(50))

        harness.start()
        #expect(harness.isRunning)
        #expect(service.hasActiveActivity,
                "same pin as the second-tap test: a free slot was measured, so no handle means no production start path")

        // Nothing taps. The budget guard has to fire on its own.
        let ended = await waitUntil("the auto-end window to fire") { harness.isRunning == false }
        #expect(ended)
        #expect(harness.lastEndReason == .timeout)
        #expect(harness.endCount == 1)
        #expect(service.hasActiveActivity == false,
                "the auto-end must clear production's handle, not merely flip the harness flag")
        _ = await waitUntil("the system activity list to drain after the timeout") {
            Activity<HermesActivityAttributes>.activities.isEmpty
        }
        #expect(Activity<HermesActivityAttributes>.activities.isEmpty,
                "an un-tapped throwaway is exactly the leak that would starve the REAL run activity")
    }

    // MARK: - 250T-B: the two end routes race, and must not double-end

    @MainActor
    @Test func aTapAfterTheAutoEndIsANoOpRatherThanASecondEnd() async {
        await drainExistingActivities()
        let service = LiveActivityService()
        let harness = ThrowawayLiveActivityHarness(service: service, autoEndAfter: .milliseconds(50))

        harness.start()
        _ = await waitUntil("the auto-end window to fire") { harness.isRunning == false }
        #expect(harness.endCount == 1)

        // The user's finger arrives after the timeout already ended it. This is
        // the ordinary case on a screen left open, not an edge case.
        harness.toggle()
        #expect(harness.isRunning, "a tap on an already-ended throwaway starts a new one")
        #expect(harness.endCount == 1, "the stale tap must not have been counted as a second end")

        harness.end(.secondTap)
        #expect(harness.endCount == 2)
        #expect(service.hasActiveActivity == false)
    }

    /// A re-entrant start must not stack activities: the second
    /// `Activity.request` would return a handle the service never stored, and
    /// `endActivity()` clears only what it holds — that untracked activity is
    /// the leak shape.
    @MainActor
    @Test(.enabled(ThrowawayLiveActivityHarnessTests.vendRequired) {
        await ThrowawayLiveActivityHarnessTests.vendRefusal() == nil
    })
    func aSecondStartWhileRunningDoesNotStackActivities() async {
        await drainExistingActivities()
        // #326-D named this one too. `count <= 1` is a BOUND, not an equality,
        // so it never carried the premise the two tests above did — but on a
        // host where ActivityKit refuses it is satisfied VACUOUSLY by count 0,
        // and a bound that passes when nothing happened is not coverage. The
        // precondition is what makes the bound mean something.
        await requireAFreeActivitySlot()
        let service = LiveActivityService()
        let harness = ThrowawayLiveActivityHarness(service: service, autoEndAfter: .seconds(600))

        harness.start()
        harness.start()
        harness.start()
        #expect(harness.isRunning)
        #expect(service.hasActiveActivity,
                "the first of the three taps must have vended — otherwise the bound below is vacuous")
        #expect(Activity<HermesActivityAttributes>.activities.count <= 1,
                "three taps must not leave three activities burning the system budget")

        harness.end(.secondTap)
        #expect(harness.endCount == 1, "the ignored starts must not each owe an end")
        #expect(service.hasActiveActivity == false)
    }

    // MARK: - 250T-B: the shipped configuration

    /// The window the brief specifies (~60s) and the labels that keep a
    /// throwaway from ever being mistaken for a real run. These are the values
    /// the device operator will actually meet in §R2, so they are pinned rather
    /// than left to drift.
    @MainActor
    @Test func theShippedHarnessIsShortLivedAndObviouslySynthetic() {
        #expect(ThrowawayLiveActivityHarness.shared.autoEndAfter == .seconds(60))
        #expect(ThrowawayLiveActivityHarness.toolLabel.contains("THROWAWAY"))
        #expect(ThrowawayLiveActivityHarness.statusLabel.contains("THROWAWAY"))
        #expect(ThrowawayLiveActivityHarness.toolLabel.contains("#250"),
                "the label should say which item put it on screen")
    }
}
#endif
