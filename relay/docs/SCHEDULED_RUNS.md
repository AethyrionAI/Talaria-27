# Scheduled runs (#98, Lane G)

The relay can start Hermes runs on a schedule. A schedule names a prompt and
a recurrence; a background trigger loop (coarse ~60 s tick) fires due
schedules by creating a **fresh gateway session** and starting a detached run
through the same Sessions-API path the app uses, then hands the session to
the existing run-watch machinery (#38) — so the result arrives as the usual
completion push (APNs alert, `session_id` in the payload, tap deep-links into
the conversation). There is no scheduler-specific delivery code.

v0 is **API-managed** (this document is the contract); the iOS management UI
is a later lane.

## Requirements / configuration

| Env var | Meaning |
|---|---|
| `GATEWAY_BASE_URL` / `GATEWAY_API_KEY` | The gateway the runs execute on (same settings as the #38 push watch). Schedule **creation is refused with 503** when `GATEWAY_API_KEY` is unset — a schedule that can never fire is a config error. |
| `APNS_*` | Delivery channel. Runs still fire without APNs (results land in gateway session history); only the push is skipped. |
| `SCHEDULER_ENABLED` | Ops kill switch for the trigger loop (default `true`; `0/false/no/off` disables). Schedule rows persist while it's off; nothing fires. |
| `SCHEDULER_TICK_SECONDS` | Trigger-loop tick (default `60`). Schedules can never be sub-hourly, so there is no reason to lower this. |

Dependency note: schedule timezones use `zoneinfo`; on Windows hosts (OJAMD)
the IANA data comes from the `tzdata` package, which is a declared relay
dependency as of this change.

## Auth

All `/v1/schedules*` endpoints use the standard device bearer token
(`Authorization: Bearer <accessToken>`), exactly like the other `/v1` routes.
Schedules belong to the authenticated user; a foreign/unknown id is a 404.

## Recurrence grammar

Every schedule has exactly one `kind`, with exactly its own fields — cross-kind
fields are rejected (422). **Hard floor: nothing may fire more often than
hourly.**

| `kind` | Required fields | Optional | Semantics |
|---|---|---|---|
| `once` | `runAt` (ISO 8601 datetime; must be in the future → else 400) | — | Fires once, then the schedule disables itself (`enabled=false`, `nextRunAt=null`). |
| `interval` | `intervalMinutes` (integer ≥ 60 → else 422; ≤ 527040) | — | Fires every N minutes, anchored to the last fire (`next = fire time + N`). |
| `daily` | `timeOfDay` (`"HH:MM"`, 24 h) | `timezone` (IANA name, default UTC) | Fires at that wall-clock time every day. Wall time is stable across DST. |
| `weekly` | `timeOfDay`, `weekday` (0=Monday … 6=Sunday) | `timezone` | Fires at that wall-clock time on that weekday. |

`sessionStrategy` is `"fresh"` (the only v0 value): every fire creates a new
gateway session, so runs never see each other's context.

## Endpoints

All responses use the standard `{data, meta}` envelope. Datetimes in schedule
payloads are aware UTC (ISO 8601 with offset).

| Method + path | Purpose |
|---|---|
| `POST /v1/schedules` | Create. Body: `prompt` (1–8000 chars), `kind`, recurrence fields, optional `sessionStrategy`. Returns the schedule with computed `nextRunAt`. 503 if the gateway is unconfigured. |
| `GET /v1/schedules` | List (creation order). |
| `GET /v1/schedules/{id}` | Fetch one. |
| `PATCH /v1/schedules/{id}` | Partial update. `prompt` / `sessionStrategy` change independently. A recurrence change must send `kind` **with its full field set** (same shape as create); it re-anchors `nextRunAt` from now. Recurrence subfields without `kind` → 422. Enabled state is *not* settable here. |
| `POST /v1/schedules/{id}/pause` | `enabled=false`, `nextRunAt=null`. Idempotent. |
| `POST /v1/schedules/{id}/resume` | Re-enables and **re-anchors from now** (a schedule paused for days does not fire a stale catch-up). Resuming a one-shot whose `runAt` has passed → 409. |
| `DELETE /v1/schedules/{id}` | Removes the row. A run already in flight is unaffected — its completion watch is keyed on the gateway session, not the schedule. |

### Schedule object

```json
{
  "id": "…uuid…",
  "prompt": "Summarize overnight CI failures",
  "sessionStrategy": "fresh",
  "kind": "daily",
  "runAt": null,
  "intervalMinutes": null,
  "timeOfDay": "07:30",
  "weekday": null,
  "timezone": "America/Chicago",
  "enabled": true,
  "lastRunAt": "2026-07-12T12:30:00Z",
  "lastRunSessionId": "api_…",
  "nextRunAt": "2026-07-13T12:30:00Z",
  "createdAt": "2026-07-10T02:11:09Z",
  "updatedAt": "2026-07-12T12:30:00Z"
}
```

### Example (PowerShell on the box: use `curl.exe`, not the alias)

```bash
curl.exe -s -X POST http://127.0.0.1:8000/v1/schedules \
  -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d '{"prompt":"Morning digest: calendar, weather, inbox triage.","kind":"daily","timeOfDay":"07:00","timezone":"America/Chicago"}'
```

## Trigger-loop semantics (the load-bearing rules)

- **Fire path:** due schedule → `POST /api/sessions` (fresh session) →
  `POST /api/sessions/{id}/chat/stream` with the prompt, disconnecting once
  the first SSE event confirms the run started (runs complete server-side
  after stream disconnect — the verified #38 detach behavior) → register the
  session with the completion watch. `lastRunAt`, `lastRunSessionId`, and
  `nextRunAt` update atomically after a successful start.
- **Missed runs:** if a due time was missed (relay or gateway down), at most
  **one** catch-up run fires, and only if the miss is smaller than one
  recurrence period (`interval` → its interval; `daily` → 24 h; `weekly` →
  7 d; `once` → the 60-minute floor). A staler miss skips forward to the next
  occurrence without firing — a one-shot in that case becomes
  `enabled=false` without firing. Missed occurrences are never queued.
- **In-flight guard:** while the previous run's watch is still live, a due
  schedule skips the tick (logged) instead of stacking runs. The guard clears
  when the run completes, when the watch TTL (default 30 min) expires, or on
  relay restart (watches are in-memory by design).
- **Transient gateway failure at fire time:** the row is left untouched, so
  the next tick retries; the missed-run policy caps how late a fire can
  happen.
- **Audit trail:** fires and skip-forwards are recorded in `audit_log`
  (`schedule.fire` / `schedule.skip_forward`, actor `relay`), alongside the
  API's `schedule.*` actions.

## Storage / migration

One new table, `schedules` (plus index `ix_schedules_enabled_next_run`),
created additively and idempotently on boot (`CREATE TABLE IF NOT EXISTS`
semantics via `create_all` + `CREATE INDEX IF NOT EXISTS`). An existing
production `hermes_mobile.db` needs **no manual steps** beyond the normal
service restart.
