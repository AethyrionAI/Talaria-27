import Foundation
import Testing
@testable import Talaria

/// #156a D2/D6 — the client-derived status, including EVERY needsAttention
/// branch. The server has no aggregate status field; this derivation is
/// what makes the UI more truthful than the API.
struct CronJobStatusTests {

    private func job(_ json: String) throws -> CronJob {
        try JSONDecoder().decode(CronJob.self, from: Data(json.utf8))
    }

    // MARK: - running

    @Test func inFlightExecutionIsRunning() throws {
        let running = try job("""
        {"id": "aaa111aaa111", "enabled": true, "state": "scheduled",
         "schedule": {"kind": "interval", "minutes": 30},
         "next_run_at": "2026-07-23T09:00:00+00:00",
         "latest_execution": {"status": "running"}}
        """)
        #expect(running.derivedStatus == .running)

        let claimed = try job("""
        {"id": "aaa111aaa111", "latest_execution": {"status": "claimed"}}
        """)
        #expect(claimed.derivedStatus == .running)
    }

    @Test func completedExecutionIsNotRunning() throws {
        let done = try job("""
        {"id": "aaa111aaa111", "enabled": true, "state": "scheduled",
         "schedule": {"kind": "interval", "minutes": 30},
         "next_run_at": "2026-07-23T09:00:00+00:00",
         "latest_execution": {"status": "completed"}}
        """)
        #expect(done.derivedStatus == .active)
    }

    /// A live execution outranks even an errored record — it is happening
    /// now.
    @Test func runningOutranksError() throws {
        let value = try job("""
        {"id": "aaa111aaa111", "last_error": "boom",
         "latest_execution": {"status": "running"}}
        """)
        #expect(value.derivedStatus == .running)
    }

    // MARK: - paused

    /// Pause sets `enabled=false` AND `state="paused"` (verified upstream) —
    /// paused must be classified before the disabled branches swallow it.
    @Test func pausedJobIsPausedNotOffOrAttention() throws {
        let value = try job("""
        {"id": "aaa111aaa111", "enabled": false, "state": "paused",
         "schedule": {"kind": "interval", "minutes": 30},
         "paused_at": "2026-07-22T08:00:00+00:00", "next_run_at": null}
        """)
        #expect(value.derivedStatus == .paused)
    }

    @Test func pausedWithLastErrorIsStillPaused() throws {
        let value = try job("""
        {"id": "aaa111aaa111", "enabled": false, "state": "paused",
         "schedule": {"kind": "cron", "expr": "0 9 * * *"},
         "last_error": "old failure", "next_run_at": null}
        """)
        #expect(value.derivedStatus == .paused)
    }

    // MARK: - completed → off

    /// Repeat-exhausted recurring jobs get `enabled=false, state="completed"`
    /// (verified upstream) — that job did what was asked; off, not
    /// attention.
    @Test func repeatExhaustedJobIsOff() throws {
        let value = try job("""
        {"id": "aaa111aaa111", "enabled": false, "state": "completed",
         "schedule": {"kind": "interval", "minutes": 30},
         "repeat": {"times": 3, "completed": 3}, "next_run_at": null}
        """)
        #expect(value.derivedStatus == .off)
    }

    // MARK: - needsAttention branch 1: recurring + disabled + no next run

    @Test func disabledRecurringWithNoNextRunNeedsAttention() throws {
        let interval = try job("""
        {"id": "aaa111aaa111", "enabled": false, "state": "scheduled",
         "schedule": {"kind": "interval", "minutes": 30}, "next_run_at": null}
        """)
        #expect(interval.derivedStatus == .needsAttention)

        let cron = try job("""
        {"id": "aaa111aaa111", "enabled": false, "state": "scheduled",
         "schedule": {"kind": "cron", "expr": "0 9 * * *"}, "next_run_at": null}
        """)
        #expect(cron.derivedStatus == .needsAttention)
    }

    // MARK: - needsAttention branch 2: recurring + last_error + no next run

    /// The croniter-missing shape: upstream deliberately leaves the job
    /// enabled with `state="error"`, `last_error` set, no next_run_at — "not
    /// silently disabled". This is the state the aggregation exists for.
    @Test func erroredRecurringWithNoNextRunNeedsAttention() throws {
        let value = try job("""
        {"id": "aaa111aaa111", "enabled": true, "state": "error",
         "schedule": {"kind": "cron", "expr": "0 9 * * *"},
         "last_error": "Failed to compute next run for recurring schedule",
         "next_run_at": null}
        """)
        #expect(value.derivedStatus == .needsAttention)
    }

    @Test func lastStatusErrorAloneQualifiesAsError() throws {
        let value = try job("""
        {"id": "aaa111aaa111", "enabled": true, "state": "scheduled",
         "schedule": {"kind": "interval", "minutes": 30},
         "last_status": "error", "next_run_at": "2026-07-23T09:00:00+00:00"}
        """)
        #expect(value.derivedStatus == .error)
    }

    // MARK: - needsAttention does NOT fire for…

    @Test func oneShotWithNoNextRunIsNotAttention() throws {
        // One-shots aren't recurring — a spent one-shot is not a silent
        // death.
        let value = try job("""
        {"id": "aaa111aaa111", "enabled": false, "state": "scheduled",
         "schedule": {"kind": "once", "run_at": "2026-07-20T09:00:00+00:00"},
         "next_run_at": null}
        """)
        #expect(value.derivedStatus == .off)
    }

    @Test func erroredRecurringWithFutureRunIsErrorNotAttention() throws {
        // A next run exists — the scheduler is still driving; error, not
        // attention.
        let value = try job("""
        {"id": "aaa111aaa111", "enabled": true, "state": "scheduled",
         "schedule": {"kind": "interval", "minutes": 30},
         "last_error": "transient failure",
         "next_run_at": "2026-07-23T09:00:00+00:00"}
        """)
        #expect(value.derivedStatus == .error)
    }

    /// A naive (host wall-clock) next_run_at still counts as "the server has
    /// a next run" — attention keys off the RAW field, not the parsed
    /// instant.
    @Test func naiveNextRunStillCountsAsScheduled() throws {
        let value = try job("""
        {"id": "aaa111aaa111", "enabled": true, "state": "scheduled",
         "schedule": {"kind": "cron", "expr": "0 9 * * *"},
         "last_error": "boom", "next_run_at": "2026-07-23T09:00:00"}
        """)
        #expect(value.derivedStatus == .error)
    }

    // MARK: - off / active defaults

    @Test func disabledOneShotIsOff() throws {
        let value = try job("""
        {"id": "aaa111aaa111", "enabled": false,
         "schedule": {"kind": "once", "run_at": "2026-08-01T09:00:00+00:00"}}
        """)
        #expect(value.derivedStatus == .off)
    }

    @Test func healthyRecurringJobIsActive() throws {
        let value = try job("""
        {"id": "aaa111aaa111", "enabled": true, "state": "scheduled",
         "schedule": {"kind": "interval", "minutes": 30},
         "last_status": "ok", "next_run_at": "2026-07-23T09:00:00+00:00"}
        """)
        #expect(value.derivedStatus == .active)
    }

    @Test func minimalRecordDefaultsToActive() throws {
        let value = try job(#"{"id": "aaa111aaa111"}"#)
        #expect(value.derivedStatus == .active)
    }

    // MARK: - recurring definition

    @Test func recurringKinds() throws {
        let interval = try job(#"{"id": "aaa111aaa111", "schedule": {"kind": "interval", "minutes": 5}}"#)
        let cron = try job(#"{"id": "aaa111aaa111", "schedule": {"kind": "cron", "expr": "0 9 * * *"}}"#)
        let once = try job(#"{"id": "aaa111aaa111", "schedule": {"kind": "once", "run_at": "2026-08-01T09:00:00"}}"#)
        let none = try job(#"{"id": "aaa111aaa111"}"#)
        #expect(interval.isRecurring)
        #expect(cron.isRecurring)
        #expect(!once.isRecurring)
        #expect(!none.isRecurring)
    }
}
