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
/// 2026-08-11.** This used to read `hasActiveActivity == service.isAvailable`,
/// on the reasoning that production's `guard isAvailable else { return }` means
/// an activity exists *exactly when* activities are enabled. The reasoning
/// covered only half the path. `isAvailable` gates the *attempt*; it says
/// nothing about whether the attempt *succeeds*, and the equality quietly
/// asserted that it always does.
///
/// **Measured, on the iOS 27.0 simulator host:** the sixth concurrent Live
/// Activity throws `ActivityAuthorizationError.targetMaximumExceeded`
/// (`com.apple.ActivityKit.ActivityAuthorization`, code 5) while
/// `areActivitiesEnabled` is still `true`. The ceiling is **per app, not per
/// attributes type** — five activities of an unrelated type starve
/// `HermesActivityAttributes` completely, and because
/// `adoptExistingActivityIfNeeded()` only adopts activities of *our* type,
/// there is then nothing to adopt either. In that state the old equality read
/// `false == true` and the suite went red on a clean tree.
///
/// The assertions below therefore compare the service's handle against the
/// service's own `lastStartOutcome` — what its start attempt actually did —
/// which is a fact about this code rather than a prediction about ActivityKit.
/// The 250T-B pin is *stronger* for it: `lastStartOutcome != .notAttempted`
/// holds on every host, so a harness that stopped calling the production start
/// path goes red even where ActivityKit refuses to vend.
///
/// A second attributes type, declared in this target only, exists to reproduce
/// that refusal on purpose — see `theStartAssertionSurvivesAnExhaustedBudget`.
struct ForeignBudgetAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable { var n: Int }
    var name: String
}

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

    // MARK: - 250T-B: it ends on a second tap

    @MainActor
    @Test func aSecondTapEndsTheThrowawayAndLeavesNoZombie() async {
        await drainExistingActivities()
        let service = LiveActivityService()
        // A long window so the timeout cannot be what ends this one — the
        // second tap has to be doing the work.
        let harness = ThrowawayLiveActivityHarness(service: service, autoEndAfter: .seconds(600))

        #expect(harness.isRunning == false)
        #expect(service.hasActiveActivity == false, "a fresh service must hold no activity")

        harness.toggle()   // first tap
        #expect(harness.isRunning)
        #expect(service.lastStartOutcome != .notAttempted,
                "the tap must reach LiveActivityService's own start path — this is the 250T-B pin, and it holds on every host")
        #expect(service.hasActiveActivity == service.lastStartOutcome.leftAHandle,
                "the service's handle must agree with what its own start attempt did (outcome: \(service.lastStartOutcome))")

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
    @Test func theAutoEndWindowEndsAThrowawayNobodyTappedAgain() async {
        await drainExistingActivities()
        let service = LiveActivityService()
        let harness = ThrowawayLiveActivityHarness(service: service, autoEndAfter: .milliseconds(50))

        harness.start()
        #expect(harness.isRunning)
        #expect(service.lastStartOutcome != .notAttempted)
        #expect(service.hasActiveActivity == service.lastStartOutcome.leftAHandle,
                "outcome: \(service.lastStartOutcome)")

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
    @Test func aSecondStartWhileRunningDoesNotStackActivities() async {
        await drainExistingActivities()
        let service = LiveActivityService()
        let harness = ThrowawayLiveActivityHarness(service: service, autoEndAfter: .seconds(600))

        harness.start()
        harness.start()
        harness.start()
        #expect(harness.isRunning)
        // `count <= 1` is a BOUND, not an equality, so it cannot carry the
        // premise #326 removed above — but it is satisfied vacuously by
        // `count == 0` on a host where ActivityKit refuses, so the pin below
        // is what keeps this test from passing on a harness that never
        // reached production at all.
        #expect(service.lastStartOutcome != .notAttempted)
        #expect(Activity<HermesActivityAttributes>.activities.count <= 1,
                "three taps must not leave three activities burning the system budget")

        harness.end(.secondTap)
        #expect(harness.endCount == 1, "the ignored starts must not each owe an end")
        #expect(service.hasActiveActivity == false)
    }

    // MARK: - #326: the start assertion in the state that broke the old one

    /// **The state that turned a clean tree red, produced on purpose.**
    ///
    /// Filling the app's Live Activity budget with a *different* attributes type
    /// puts ActivityKit into the exact configuration that failed the merged-`main`
    /// gate on 2026-08-11: `areActivitiesEnabled` still `true`, nothing of our
    /// type adoptable, and `Activity.request` refusing with
    /// `targetMaximumExceeded`. Measured that day: the ceiling is **5 concurrent
    /// activities per app**, and it is shared across attributes types.
    ///
    /// The old assertion (`hasActiveActivity == service.isAvailable`) reads
    /// `false == true` here and fails. The replacement holds, and — the part
    /// that matters — it still *catches* a harness that stopped driving the
    /// production service, because `lastStartOutcome` stays `.notAttempted`
    /// unless `LiveActivityService`'s own start path ran.
    @MainActor
    @Test func theStartAssertionSurvivesAnExhaustedBudget() async {
        await drainExistingActivities()

        var foreign: [Activity<ForeignBudgetAttributes>] = []
        var refusedAt: Int?
        for i in 0..<16 {
            do {
                foreign.append(try Activity.request(
                    attributes: ForeignBudgetAttributes(name: "#326 budget filler"),
                    content: .init(state: .init(n: i), staleDate: nil),
                    pushType: nil))
            } catch {
                refusedAt = i
                break
            }
        }
        // If this ever stops holding, the per-app ceiling moved and the whole
        // premise below needs re-measuring rather than the bar relaxing.
        #expect(refusedAt != nil,
                "could not exhaust the Live Activity budget in 16 requests — the per-app ceiling has moved; re-measure before trusting this test")
        let oursAdoptable = Activity<HermesActivityAttributes>.activities.contains { $0.activityState == .active }
        #expect(oursAdoptable == false,
                "the budget must be full of FOREIGN activities, or the service would simply adopt one and the state under test is not reached")

        let service = LiveActivityService()
        let harness = ThrowawayLiveActivityHarness(service: service, autoEndAfter: .seconds(600))
        harness.start()

        // Preconditions of the failing state, asserted rather than assumed —
        // otherwise a host that happily vends would pass this test while never
        // entering the state it exists to cover.
        #expect(service.isAvailable, "ActivityKit still reports ENABLED while refusing to vend — that is the whole finding")
        if case .refused = service.lastStartOutcome {} else {
            Issue.record("expected the production start path to be REFUSED with the budget full, got \(service.lastStartOutcome)")
        }

        // The replacement assertion, in the state that broke the old one.
        #expect(service.lastStartOutcome != .notAttempted,
                "the harness must still be driving the production start path even when ActivityKit refuses")
        #expect(service.hasActiveActivity == service.lastStartOutcome.leftAHandle,
                "handle and outcome must agree (outcome: \(service.lastStartOutcome))")
        #expect(service.hasActiveActivity == false,
                "a refused request must leave no handle")

        harness.end(.secondTap)
        #expect(harness.endCount == 1, "a throwaway that never vended must still end cleanly")

        // Hand the budget back before the next test runs — a leaked filler here
        // would starve every activity assertion that follows, which is exactly
        // the failure this suite exists to keep out.
        for a in foreign { await a.end(nil, dismissalPolicy: .immediate) }
        _ = await waitUntil("the foreign budget fillers to drain") {
            Activity<ForeignBudgetAttributes>.activities.isEmpty
        }
        await drainExistingActivities()
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
