import Foundation
import Testing
@testable import Talaria

/// The tool's return value, settled on the MainActor so a poll can see it.
///
/// A local `var` cannot be captured mutably by the escaping task body, and the
/// point of watching it is to tell "the tool finished without staging" (a guard
/// fired) apart from "the tool has not got there yet".
@MainActor
final class StagedReminderOutcome {
    var result: String?
}

/// **The one implementation of "drive `performCreate` to completion and report
/// what it staged" — hoisted, not copied (#340 Task 4).**
///
/// Task 3 built this seam inside `ReminderDueFallbackTests` as a `private func`.
/// Task 4 needs the same drive with a relay the caller has configured, and
/// Task 3's own report already made the argument for what to do at that moment:
/// *"the right move is one helper, not one more copy"* — which is why
/// `RepoSourceWitness` exists. This is that rule applied a second time, to the
/// runtime seam rather than the source-reading one.
///
/// **Why the relay is the caller's.** `ToolEventRelay` carries per-turn state
/// the tool reads (`currentTurnUserText`, and from Task 4 the DEBUG fallback
/// switch), so a probe that minted its own relay could not express the one A/B
/// this task is for. Callers that need nothing special pass a fresh one.
@MainActor
enum StagedReminderProbe {

    /// Drives `performCreate` to completion and reports BOTH what it staged and
    /// what it returned — **with two measured hazards closed.**
    ///
    /// **1. A yield-counted poll measures the WRONG PROCESS, and it cost Task 3
    /// a ten-minute hang.** `performCreate` is `nonisolated`, so the tool leaves
    /// the MainActor and runs on the generic executor while the test waits.
    /// `BareClockWiringTests`' `while … attempts < 2000 { await Task.yield() }`
    /// therefore counts the TEST's scheduling, not the tool's progress: on an
    /// idle MainActor those 2,000 yields elapse in about two milliseconds. That
    /// is enough for every row in that file, and it is not enough here —
    /// `NSDataDetector`'s FIRST construction in a process takes roughly 36 ms
    /// (measured: the card staged at `…18.409`, 36 ms after the previous suite's
    /// last line, with the poll long since given up). The loop exited, nothing
    /// declined the card, and `await task.value` waited forever on a decision
    /// that was never coming. A stall has no verdict, which makes it strictly
    /// worse than a failure.
    ///
    /// So the wait is on the WALL CLOCK, and it also watches the tool's own
    /// completion so a row that reaches a GUARD (staging nothing at all) returns
    /// immediately instead of burning the deadline.
    ///
    /// **2. It never awaits a task that may not finish.** If the deadline passes
    /// with nothing staged and nothing returned, the helper gives back a
    /// sentinel and lets the row FAIL, loudly, naming which half timed out.
    static func staged(rawDue: String, userText: String, now: Date,
                       relay: ToolEventRelay) async -> (due: String?, result: String) {
        let center = ToolConfirmationCenter()
        let outcome = StagedReminderOutcome()
        let task = Task { @MainActor in
            outcome.result = await ReminderCreateTool.performCreate(
                rawTitle: "Call mom", rawDue: rawDue, rawList: "",
                userText: userText,
                relay: relay, confirmations: center, now: now)
        }

        var due: String?
        var didStage = false
        let stageBy = Date().addingTimeInterval(30)
        while Date() < stageBy {
            if let pending = center.pending {
                due = pending.fields.first { $0.key == "due" }?.value
                didStage = true
                center.decline()
                break
            }
            // A guard returned without staging anything — done, don't wait.
            if outcome.result != nil { break }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }

        let finishBy = Date().addingTimeInterval(30)
        while outcome.result == nil && Date() < finishBy {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        task.cancel()
        return (due, outcome.result
                ?? "<TIMED OUT: the tool never returned; staged=\(didStage)>")
    }
}
