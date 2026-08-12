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
/// **On `service.isAvailable`:** whether ActivityKit will vend an activity is a
/// property of the host, not of this code — the test host can have Live
/// Activities disabled. So the start assertion is written as an equality
/// against `isAvailable` rather than a bare `== true`: production's own
/// `guard isAvailable else { return }` means an activity exists *exactly when*
/// activities are enabled. That keeps the assertion total — it can fail in
/// either direction — instead of a conditional that silently skips on the
/// host where it would have caught something.
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
        #expect(service.hasActiveActivity == service.isAvailable,
                "the throwaway must go through the production start path: an activity exists exactly when ActivityKit is enabled")

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
        #expect(service.hasActiveActivity == service.isAvailable)

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

    // MARK: - #326-A THROWAWAY PROBE — DELETE BEFORE CLOSE-OUT
    //
    // Records, rather than assumes, which side of `hasActiveActivity ==
    // isAvailable` diverges on a given simulator. It always fails, by design:
    // `Issue.record` is the only channel guaranteed to land the readings in
    // the xcodebuild log.
    @MainActor
    @Test func probe326AReadings() async {
        var lines: [String] = []
        let info = ActivityAuthorizationInfo()
        lines.append("enabled_at_entry=\(info.areActivitiesEnabled)")
        lines.append("frequentPushes=\(info.frequentPushesEnabled)")
        let pre = Activity<HermesActivityAttributes>.activities
        lines.append("preexisting_ours=\(pre.count) states=\(pre.map { String(describing: $0.activityState) })")

        await drainExistingActivities()
        lines.append("after_drain_ours=\(Activity<HermesActivityAttributes>.activities.count)")
        lines.append("enabled_after_drain=\(ActivityAuthorizationInfo().areActivitiesEnabled)")

        // The request side, direct — the half the old assertion never measured.
        do {
            let a = try Activity.request(
                attributes: HermesActivityAttributes(agentName: "Hermes"),
                content: .init(
                    state: .init(status: "probe", toolName: "#326-A", elapsedSeconds: 0,
                                 startDate: .now, sessionType: "tool"),
                    staleDate: nil),
                pushType: nil)
            lines.append("direct_request=SUCCEEDED")
            await a.end(nil, dismissalPolicy: .immediate)
        } catch {
            let ns = error as NSError
            lines.append("direct_request=THREW domain=\(ns.domain) code=\(ns.code) raw=\(String(describing: error)) desc=\(ns.localizedDescription)")
        }
        await drainExistingActivities()

        // And the production path, which is what the failing assertion read.
        let service = LiveActivityService()
        service.startToolCall(toolName: "#326-A probe")
        lines.append("service.isAvailable=\(service.isAvailable)")
        lines.append("service.hasActiveActivity=\(service.hasActiveActivity)")
        service.endActivity()
        await drainExistingActivities()

        let readings = lines.joined(separator: " | ")
        Issue.record("326-A READINGS :: \(readings)")
    }

    // MARK: - #326-B THROWAWAY PROBE — DELETE BEFORE CLOSE-OUT
    @MainActor
    @Test func probe326BBudget() async {
        await drainExistingActivities()
        var lines: [String] = []

        // How many activities of a FOREIGN attributes type will ActivityKit
        // vend to this app, and what does it say when it stops?
        var foreign: [Activity<ForeignBudgetProbeAttributes>] = []
        for i in 0..<12 {
            do {
                foreign.append(try Activity.request(
                    attributes: ForeignBudgetProbeAttributes(name: "#326 filler \(i)"),
                    content: .init(state: .init(n: i), staleDate: nil),
                    pushType: nil))
            } catch {
                let ns = error as NSError
                lines.append("foreign_refused_at=\(i) domain=\(ns.domain) code=\(ns.code) raw=\(String(describing: error))")
                break
            }
        }
        lines.append("foreign_vended=\(foreign.count)")
        lines.append("enabled_under_load=\(ActivityAuthorizationInfo().areActivitiesEnabled)")
        lines.append("ours_visible=\(Activity<HermesActivityAttributes>.activities.count)")

        // With the budget full of a foreign type, what does the PRODUCTION
        // start path do, and does the OLD assertion hold?
        let service = LiveActivityService()
        let harness = ThrowawayLiveActivityHarness(service: service, autoEndAfter: .seconds(600))
        harness.start()
        lines.append("isAvailable=\(service.isAvailable)")
        lines.append("hasActiveActivity=\(service.hasActiveActivity)")
        lines.append("OLD_ASSERTION_HOLDS=\(service.hasActiveActivity == service.isAvailable)")
        harness.end(.secondTap)

        // The error our own type gets, verbatim.
        do {
            let a = try Activity.request(
                attributes: HermesActivityAttributes(agentName: "Hermes"),
                content: .init(
                    state: .init(status: "probe", toolName: "#326-B", elapsedSeconds: 0,
                                 startDate: .now, sessionType: "tool"),
                    staleDate: nil),
                pushType: nil)
            lines.append("ours_request=SUCCEEDED")
            await a.end(nil, dismissalPolicy: .immediate)
        } catch {
            let ns = error as NSError
            lines.append("ours_request=THREW domain=\(ns.domain) code=\(ns.code) raw=\(String(describing: error))")
        }

        for a in foreign { await a.end(nil, dismissalPolicy: .immediate) }
        _ = await waitUntil("foreign fillers to drain") {
            Activity<ForeignBudgetProbeAttributes>.activities.isEmpty
        }
        await drainExistingActivities()

        let readings = lines.joined(separator: " | ")
        Issue.record("326-B READINGS :: \(readings)")
    }
}

// #326 THROWAWAY PROBE TYPE — DELETE BEFORE CLOSE-OUT
struct ForeignBudgetProbeAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable { var n: Int }
    var name: String
}
#endif
