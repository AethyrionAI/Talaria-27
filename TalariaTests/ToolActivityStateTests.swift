import Foundation
import Testing
@testable import Talaria

/// #296 — the rail's glyph decision, as a pure function.
///
/// The defect these pin: `ToolActivityRail` was two-valued (running /
/// not-running), so *everything* not-running drew the same accent ✓ — a tool
/// the user killed mid-flight included. On the turn Owen photographed the
/// chip was the ENTIRE message, so a checkmark was the whole content of a
/// bubble asserting that a command he had just stopped had completed.
///
/// These are deliberately not view tests. The old decision was an inline
/// boolean inside `body` and could only be checked by eye; extracting it is
/// most of the fix, and this file is the reason the extraction was worth it.
struct ToolActivityStateTests {

    private func activity(
        label: String = "terminal",
        isActive: Bool = false,
        failure: String? = nil
    ) -> ToolActivity {
        ToolActivity(label: label, isActive: isActive, detail: "sleep 30", failure: failure)
    }

    // MARK: - Per-step state

    @Test func runningActivityIsRunning() {
        #expect(ToolActivityRail.state(of: activity(isActive: true)) == .running)
    }

    /// **296-B.** The regression bar in its smallest form: a tool that really
    /// did finish is resolved (`isActive == false`) and carries no failure,
    /// and it must still read as completed. This is what stops the lane from
    /// "fixing" the ✓ by deleting it.
    @Test func resolvedActivityWithNoFailureIsCompleted() {
        #expect(ToolActivityRail.state(of: activity(isActive: false)) == .completed)
    }

    /// **296-A.** The third state the rail never had.
    @Test func activityWithFailureIsInterrupted() {
        #expect(ToolActivityRail.state(of: activity(failure: ToolActivity.stoppedByUser)) == .interrupted)
    }

    /// A host-reported error is the same state, arriving by a different road
    /// (296-C1). The marker is not a Stop flag — it is "why this did not
    /// complete", whoever supplied the reason.
    @Test func hostErrorTextIsAlsoInterrupted() {
        #expect(ToolActivityRail.state(of: activity(failure: "exit_code 1: no such file")) == .interrupted)
    }

    /// Ordering pin. `ChatStore.cancelStreaming` marks and clears `isActive`
    /// in two separate passes (on purpose — it has to read the flag before it
    /// destroys it), so a marked-but-still-active activity is a state the app
    /// genuinely passes through. Interrupted is the right answer in that
    /// window, and this test is what keeps someone from "simplifying"
    /// `state(of:)` into an `isActive`-first check that reports `.running`.
    @Test func failureWinsOverAStillSetIsActiveFlag() {
        #expect(ToolActivityRail.state(of: activity(isActive: true, failure: ToolActivity.stoppedByUser)) == .interrupted)
    }

    /// An activity written by a build that predates #296 decodes with
    /// `failure == nil` and must read exactly as it always did.
    @Test func preFixActivityWithNoMarkerIsUnchanged() {
        let legacy = ToolActivity(label: "read_file", isActive: false, detail: "notes.txt")
        #expect(legacy.failure == nil)
        #expect(ToolActivityRail.state(of: legacy) == .completed)
    }

    // MARK: - The collapsed chip

    /// **296-A, at the surface Owen actually photographed.** One completed
    /// step beside one interrupted step must not collapse to a ✓ — the whole
    /// point is that a summary glyph cannot average away the stopped call.
    @Test func summaryIsInterruptedWhenAnyStepIs() {
        let steps = [
            activity(label: "read_file"),
            activity(label: "terminal", failure: ToolActivity.stoppedByUser),
        ]
        #expect(ToolActivityRail.summaryState(of: steps) == .interrupted)
    }

    /// …and it does not matter which end the interrupted step sits at.
    @Test func summaryIsInterruptedWhenTheFIRSTStepIs() {
        let steps = [
            activity(label: "terminal", failure: ToolActivity.stoppedByUser),
            activity(label: "read_file"),
        ]
        #expect(ToolActivityRail.summaryState(of: steps) == .interrupted)
    }

    /// **296-B.** Every step genuinely completed ⇒ the ✓ that has always been
    /// there is still there.
    @Test func summaryOfEntirelyCompletedStepsIsCompleted() {
        let steps = [activity(label: "read_file"), activity(label: "write_file")]
        #expect(ToolActivityRail.summaryState(of: steps) == .completed)
    }

    /// Total function. The rail does not render an empty list, but a state
    /// derivation that traps on one is a crash waiting for a caller change.
    @Test func emptyStepListSummarizesCompleted() {
        #expect(ToolActivityRail.summaryState(of: []) == .completed)
    }

    /// The collapsed chip deliberately never reports `.running`: it only ever
    /// renders on a turn that is over, and a finished turn holding an
    /// unresolved activity claiming to still be running forever is a
    /// DIFFERENT bug from #296's. `.completed` here is exactly what shipped
    /// before this lane, and this test says so out loud so the choice reads
    /// as deliberate rather than as an oversight.
    @Test func summaryDoesNotReportRunningForAnUnresolvedStep() {
        #expect(ToolActivityRail.summaryState(of: [activity(isActive: true)]) == .completed)
    }

    // MARK: - The marker must not leak into identity

    /// `Conversation.dedupingAdoptedEchoes` (#237) keys empty-content rows on
    /// their activity LABELS. `failure` must never join that key: two rows
    /// differing only in how their tool ended are still the same row, and
    /// letting the marker in would resurrect exactly the duplicate #237 was
    /// filed to heal.
    @Test func failureIsNotPartOfTheAdoptedEchoKey() {
        let timestamp = Date(timeIntervalSince1970: 1_760_000_000)
        let shell = { (failure: String?) in
            Message(
                sender: .hermes,
                content: "",
                timestamp: timestamp,
                status: .delivered,
                toolActivities: [ToolActivity(label: "terminal", isActive: false, failure: failure)]
            )
        }
        let deduped = Conversation.dedupingAdoptedEchoes([shell(nil), shell(ToolActivity.stoppedByUser)])
        #expect(deduped.count == 1, "296: the marker must not become part of the dedupe key")
    }
}
