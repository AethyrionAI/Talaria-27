#if DEBUG
import Foundation
import Testing
@testable import Talaria

/// **#336 bar 336-C — recorder integrity.**
///
/// #336 asked whether the battery recorder could MISS an accepted tool call. If
/// it could, every `toolCalls` reading across the #200-series would be a floor
/// rather than a count. The 2026-08-25 forensics determined it could not — the
/// two orphan artifacts were admitted through a CLOSED recorder (the #200V
/// warm-up window), not dropped by an open one — and 336-C is the pin that
/// keeps that determination true going forward.
///
/// **These drive the real production call site**, `ToolEventRelay.started`, not
/// the recorder in isolation. That is the whole point: the bar names "removing
/// a `recordToolCall` call site" as its RED, and there is exactly one such site
/// in the tree (`DeviceToolBelt.swift`). A pin that called
/// `recorder.recordToolCall` directly would stay green through that deletion
/// and prove nothing.
@MainActor
struct RecorderCaptureIntegrityTests {

    // MARK: - Harness

    /// Opens the real recorder around a body, then removes whatever run it
    /// persisted. The production call site reaches `LocalChatBackend`'s static
    /// recorder by name, so the pin cannot inject a capturing store — it has to
    /// use the real one and clean up after itself.
    private func withOpenRun(
        _ body: (ToolEventRelay) throws -> Void
    ) throws -> BatteryRunRecord? {
        let store = LocalChatBackend.batteryRunStore
        let before = Set(store.loadRuns().map(\.id))
        let previousTag = ToolEventRelay.batteryTrialTag
        ToolEventRelay.batteryTrialTag = "trio-336C"
        defer { ToolEventRelay.batteryTrialTag = previousTag }

        LocalChatBackend.batteryRecorder.beginRun(
            trialsPerCell: 1, cells: ["336C"], kind: "recorder-integrity")
        LocalChatBackend.batteryRecorder.beginTrial()

        let relay = ToolEventRelay()
        try body(relay)

        LocalChatBackend.batteryRecorder.endTrial(
            shape: "336C", prompt: "pin", trial: 1,
            text: "recorded.", cant: false, denial: false)
        LocalChatBackend.batteryRecorder.endRun()

        let persisted = store.loadRuns().first { !before.contains($0.id) }
        if let persisted { store.delete(persisted) }
        return persisted
    }

    // MARK: - 336-C: every admitted call is captured

    /// **336-C.** A known number of admitted calls in, exactly that many out —
    /// in order, with names and UNTRUNCATED details intact. The 80-character
    /// prefix next to this call site is a Console line width, not a capture
    /// budget, and a pin that used only short details could not tell them apart.
    ///
    /// **RED-witnessed** by deleting
    /// `LocalChatBackend.batteryRecorder.recordToolCall(name:detail:)` from
    /// `ToolEventRelay.started`: the run then persists a trial with zero tool
    /// calls and this goes red on the count.
    @Test func everyAdmittedToolCallReachesTheRecorder() throws {
        let long = String(repeating: "reminder detail ", count: 12)
        let driven: [(String, String)] = [
            ("createReminder", "take out the trash at 8"),
            ("readReminders", ""),
            ("createReminder", long),
            ("scheduleAlarm", "6:30"),
            ("createCalendarEvent", "Lunch with Sam"),
            ("readReminders", ""),
            ("createReminder", "third one"),
        ]

        let run = try #require(try withOpenRun { relay in
            for (name, detail) in driven {
                try relay.started(name, detail: detail)
            }
        })

        let trial = try #require(run.trials.first)
        #expect(trial.toolCalls.count == driven.count)
        #expect(trial.toolCalls.map(\.name) == driven.map(\.0))
        #expect(trial.toolCalls.map(\.detail) == driven.map(\.1))
        // The long one survives whole — no 80-character clipping on this path.
        #expect(trial.toolCalls[2].detail == long)
        #expect(trial.toolCalls[2].detail.count > 80)
    }

    /// **336-C, the other half of "exactly".** A REFUSED call must record
    /// nothing: `started` checks admission before emitting anything, because a
    /// recorded call that never ran is the same lie as a tool chip for work
    /// that did not happen (#180/#225). An integrity pin that only counted
    /// admissions would stay green while a refusal quietly wrote a row.
    ///
    /// With a repeat cap of 2, five calls of one tool are 2 admitted and 3
    /// refused-as-strings (the fourth refusal would throw the phase cut, which
    /// is a different mechanism and deliberately not exercised here).
    @Test func refusedCallsRecordNothing() throws {
        let run = try #require(try withOpenRun { relay in
            relay.governor = ToolCallGovernor(perTurnBudget: 12, sameToolRepeatCap: 2)
            relay.beginTurn()
            for _ in 0..<5 {
                let admission = try relay.started("createReminder", detail: "spiral")
                _ = admission
            }
        })

        let trial = try #require(run.trials.first)
        #expect(trial.toolCalls.count == 2)
        #expect(trial.toolCalls.allSatisfy { $0.name == "createReminder" })
    }

    /// **The elected mechanism, pinned.** #336's reap surplus was resolved as a
    /// CLOSED-recorder window: the #200V warm-up runs the whole prompt list
    /// before `beginRun`, every recorder mutator guards on an open run, and the
    /// artifacts those trials create are real and fold into the finish reap.
    ///
    /// This is what makes "battery `toolCalls` are FLOORS" a narrow, checkable
    /// claim rather than a lossy-recorder fear: calls outside an open run are
    /// invisible BY DESIGN, and calls inside one are captured exactly. Both
    /// halves have to hold, or the determination is only half true.
    @Test func callsOutsideAnOpenRunAreInertNotLost() throws {
        let store = LocalChatBackend.batteryRunStore
        let before = Set(store.loadRuns().map(\.id))
        let previousTag = ToolEventRelay.batteryTrialTag
        ToolEventRelay.batteryTrialTag = "trio-336C-warmup"
        defer { ToolEventRelay.batteryTrialTag = previousTag }

        // No beginRun: this is the warm-up window.
        let relay = ToolEventRelay()
        try relay.started("scheduleAlarm", detail: "6:30")
        try relay.started("createCalendarEvent", detail: "Lunch with Sam")

        // Nothing was recorded, and nothing was persisted either — the recorder
        // is inert, not buffering into the next run.
        let leaked = store.loadRuns().filter { !before.contains($0.id) }
        #expect(leaked.isEmpty)
        for run in leaked { store.delete(run) }
    }
}
#endif
