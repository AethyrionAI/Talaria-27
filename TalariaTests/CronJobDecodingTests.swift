import Foundation
import Testing
@testable import Talaria

/// #156a D2/D6 — tolerant decoding of the `/api/jobs` record. Upstream is
/// not contractual: every field optional, unknown fields ignored, wrong
/// types degrade to nil, and one poison row must never blank the whole
/// list.
struct CronJobDecodingTests {

    private func decodeJob(_ json: String) throws -> CronJob {
        try JSONDecoder().decode(CronJob.self, from: Data(json.utf8))
    }

    private func decodeList(_ json: String) throws -> CronJobListResponse {
        try JSONDecoder().decode(CronJobListResponse.self, from: Data(json.utf8))
    }

    // MARK: - Full record

    @Test func fullRecordDecodes() throws {
        let job = try decodeJob("""
        {
            "id": "abc123def456",
            "name": "Morning brief",
            "prompt": "Summarize my day",
            "skills": ["brief", "weather"],
            "skill": "brief",
            "model": "claude-fable-5",
            "provider": "anthropic",
            "provider_snapshot": "anthropic",
            "model_snapshot": "claude-fable-5",
            "base_url": null,
            "script": null,
            "no_agent": false,
            "context_from": null,
            "schedule": {"kind": "cron", "expr": "0 9 * * *", "display": "0 9 * * *"},
            "schedule_display": "0 9 * * *",
            "repeat": {"times": null, "completed": 4},
            "enabled": true,
            "state": "scheduled",
            "paused_at": null,
            "paused_reason": null,
            "created_at": "2026-07-01T08:00:00+00:00",
            "next_run_at": "2026-07-23T09:00:00+00:00",
            "last_run_at": "2026-07-22T09:00:00+00:00",
            "last_status": "ok",
            "last_error": null,
            "last_delivery_error": null,
            "deliver": "origin",
            "origin": {"platform": "api_server"},
            "enabled_toolsets": ["web"],
            "workdir": null,
            "attach_to_session": false,
            "latest_execution": {
                "id": "exec1", "job_id": "abc123def456", "status": "completed",
                "claimed_at": "2026-07-22T09:00:00+00:00", "started_at": "2026-07-22T09:00:01+00:00",
                "finished_at": "2026-07-22T09:00:30+00:00", "error": null
            }
        }
        """)

        #expect(job.id == "abc123def456")
        #expect(job.name == "Morning brief")
        #expect(job.skills == ["brief", "weather"])
        #expect(job.schedule?.kind == "cron")
        #expect(job.schedule?.expr == "0 9 * * *")
        #expect(job.repeatPolicy?.times == nil)
        #expect(job.repeatPolicy?.completed == 4)
        #expect(job.enabled == true)
        #expect(job.state == "scheduled")
        #expect(job.lastStatus == "ok")
        #expect(job.deliver == "origin")
        #expect(job.enabledToolsets == ["web"])
        #expect(job.latestExecution?.status == "completed")
        #expect(job.nextRunAt != nil)
    }

    // MARK: - Minimal + missing fields

    @Test func idOnlyRecordDecodes() throws {
        let job = try decodeJob(#"{"id": "abc123def456"}"#)
        #expect(job.id == "abc123def456")
        #expect(job.name == nil)
        #expect(job.schedule == nil)
        #expect(job.isEnabled) // server default: absent enabled = enabled
        #expect(job.displayName == "abc123def456")
    }

    @Test func missingIDThrows() {
        #expect(throws: (any Error).self) {
            _ = try decodeJob(#"{"name": "No id"}"#)
        }
    }

    @Test func blankIDThrows() {
        #expect(throws: (any Error).self) {
            _ = try decodeJob(#"{"id": "   "}"#)
        }
    }

    // MARK: - Wrong types degrade, never throw

    @Test func wrongTypedFieldsDegradeToNil() throws {
        let job = try decodeJob("""
        {
            "id": "abc123def456",
            "name": 42,
            "skills": "not-a-list",
            "enabled": "yes",
            "schedule": 17,
            "repeat": "many",
            "next_run_at": 12345,
            "latest_execution": "running"
        }
        """)
        #expect(job.name == nil)
        #expect(job.skills == nil)
        #expect(job.enabled == nil)
        #expect(job.isEnabled) // degraded enabled still reads as the default
        #expect(job.schedule == nil)
        #expect(job.repeatPolicy == nil)
        #expect(job.nextRunAtRaw == nil)
        #expect(job.latestExecution == nil)
    }

    @Test func unknownFieldsAreIgnored() throws {
        let job = try decodeJob("""
        {"id": "abc123def456", "brand_new_field": {"nested": true}, "another": [1, 2]}
        """)
        #expect(job.id == "abc123def456")
    }

    // MARK: - Alternate shapes

    @Test func bareStringScheduleBecomesDisplay() throws {
        let job = try decodeJob(#"{"id": "abc123def456", "schedule": "every 30m"}"#)
        #expect(job.schedule?.display == "every 30m")
        #expect(job.schedule?.kind == nil)
        #expect(job.scheduleText == "every 30m")
    }

    @Test func bareIntRepeatBecomesTimes() throws {
        let job = try decodeJob(#"{"id": "abc123def456", "repeat": 5}"#)
        #expect(job.repeatPolicy?.times == 5)
        #expect(job.repeatPolicy?.completed == nil)
    }

    @Test func numericStringMinutesDecodes() throws {
        let job = try decodeJob("""
        {"id": "abc123def456", "schedule": {"kind": "interval", "minutes": "30"}}
        """)
        #expect(job.schedule?.minutes == 30)
    }

    // MARK: - Timestamps: offset vs naive (the timezone footgun)

    @Test func offsetTimestampParsesToInstant() throws {
        let job = try decodeJob(#"{"id": "abc123def456", "next_run_at": "2026-07-23T09:00:00+00:00"}"#)
        #expect(job.nextRunAt != nil)
        #expect(job.nextRunAtRaw == "2026-07-23T09:00:00+00:00")
    }

    @Test func fractionalOffsetTimestampParses() throws {
        let job = try decodeJob(#"{"id": "abc123def456", "next_run_at": "2026-07-23T09:00:00.123456+05:30"}"#)
        #expect(job.nextRunAt != nil)
    }

    /// A NAIVE timestamp is host wall-clock the device cannot place on its
    /// own timeline — it must stay raw (shown labeled), never silently
    /// converted.
    @Test func naiveTimestampStaysRaw() throws {
        let job = try decodeJob(#"{"id": "abc123def456", "next_run_at": "2026-07-23T09:00:00"}"#)
        #expect(job.nextRunAt == nil)
        #expect(job.nextRunAtRaw == "2026-07-23T09:00:00")
    }

    @Test func offsetDetection() {
        #expect(CronDateParsing.hasExplicitOffset("2026-07-23T09:00:00Z"))
        #expect(CronDateParsing.hasExplicitOffset("2026-07-23T09:00:00+05:30"))
        #expect(CronDateParsing.hasExplicitOffset("2026-07-23T09:00:00-05:00"))
        #expect(!CronDateParsing.hasExplicitOffset("2026-07-23T09:00:00"))
        #expect(!CronDateParsing.hasExplicitOffset("2026-07-23"))
    }

    // MARK: - List row-skip (#58 posture)

    @Test func poisonRowIsSkippedNotFatal() throws {
        let response = try decodeList("""
        {"jobs": [
            {"id": "aaa111aaa111", "name": "Good one"},
            {"name": "No id — poison"},
            {"id": "bbb222bbb222", "name": "Good two"}
        ]}
        """)
        #expect(response.jobs.map(\.id) == ["aaa111aaa111", "bbb222bbb222"])
        #expect(response.skippedRowCount == 1)
    }

    @Test func nonObjectRowIsSkipped() throws {
        let response = try decodeList("""
        {"jobs": ["just-a-string", {"id": "ccc333ccc333"}, 42]}
        """)
        #expect(response.jobs.map(\.id) == ["ccc333ccc333"])
        #expect(response.skippedRowCount == 2)
    }

    @Test func emptyListDecodes() throws {
        let response = try decodeList(#"{"jobs": []}"#)
        #expect(response.jobs.isEmpty)
        #expect(response.skippedRowCount == 0)
    }

    // MARK: - Envelopes

    @Test func envelopeAndErrorBodiesDecode() throws {
        let envelope = try JSONDecoder().decode(
            CronJobEnvelope.self,
            from: Data(#"{"job": {"id": "abc123def456"}}"#.utf8)
        )
        #expect(envelope.job.id == "abc123def456")

        let errorBody = try JSONDecoder().decode(
            CronErrorBody.self,
            from: Data(#"{"error": "Schedule is required"}"#.utf8)
        )
        #expect(errorBody.error == "Schedule is required")
    }
}
