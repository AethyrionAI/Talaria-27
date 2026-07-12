# FABLE LANE G — Scheduled / recurring agent runs (relay-side, Python only)

**OPEN_ITEMS:** #98
**Branch prefix:** `claude/t27-lane-g-`
**Collision status:** zero Swift contact — this lane lives entirely in
`relay/`. Independent of every other lane by construction.

## Objective

Both ChatGPT iOS (Scheduled Tasks, June 2026) and Claude iOS (Cowork scheduled
tasks) run recurring/monitoring agent work and push when there's something to
report. Talaria schedules only device alarms (#65). The relay already watches
runs and pushes on completion (#38) — this lane adds the missing piece: the
relay can *start* a Hermes run on a schedule, and the existing completion-push
path delivers the result. iOS UI for managing schedules is deliberately OUT of
scope (a later lane); v0 is API-managed.

## Grounding — read these BEFORE designing (probe-first rule)

- `relay/app/gateway.py` — how the relay initiates/tracks Hermes runs today
  and the run-watch machinery. The scheduler MUST reuse this path, not invent
  a parallel one.
- `relay/app/database.py` — schema conventions for `hermes_mobile.db`
  (SQLite). The DB is LIVE in production: migrations must be additive and
  idempotent (CREATE TABLE IF NOT EXISTS style), never destructive.
- `relay/app/apns.py` + the #38 completion-push flow — the delivery channel.
- `relay/app/security.py` — auth pattern for the new CRUD endpoints; match
  existing routes exactly.
- `relay/tests/` — existing test conventions and fixtures.

## Deliverables

### 1. Schema + models
- `schedules` table: id, prompt, session strategy (fresh session per run for
  v0), recurrence (one-shot ISO datetime OR simple recurrence: interval
  minutes ≥ 60, or daily/weekly at HH:MM with timezone), enabled flag,
  last_run_at, next_run_at, created_at. Pydantic schemas alongside.
- Hard floor: no schedule may fire more often than hourly (matches the
  competitor guardrail and protects the gateway).

### 2. CRUD API
- Authenticated endpoints (same auth as existing routes): create, list, get,
  update, pause/resume, delete. Validation rejects sub-hourly recurrence and
  past one-shot times.

### 3. Trigger loop
- Asyncio background task started with the app: wake on a coarse tick
  (~60s), fire due schedules by initiating a Hermes run through the EXISTING
  gateway run path with the schedule's prompt; the existing run-watch +
  completion push delivers the result. No new delivery code.
- Missed-run policy: if the relay was down past a due time, fire at most ONE
  catch-up run per schedule on startup if the miss is < 1 recurrence period;
  otherwise skip forward (never backfill a queue).
- Concurrency guard: a schedule whose previous run is still in flight skips
  the tick (log it), it does not stack runs.

### 4. Tests
- pytest, following existing `relay/tests/` conventions. Inject a fake clock
  into the trigger loop (no real sleeps). Cover: due-time firing, hourly
  floor rejection, pause/resume, missed-run policy (both branches), in-flight
  skip, additive migration on an existing DB file.

## Hard constraints

- **Python only.** No iOS/Swift changes, no `project.yml`, no `pbxproj`.
- Do NOT touch deployment/launcher scripts, NSSM config, or
  `docker-compose.yml`/`fly.toml` — deployment is Owen's manual
  `ojamd-deploy` rebase flow and stays that way.
- Do NOT modify existing run-initiation or push code paths beyond the minimal
  hook needed to start a run programmatically; if `gateway.py` needs a
  refactor to expose that, keep it surgical and covered by tests.
- The production DB (`hermes_mobile.db` on OJAMD) must survive this change
  with zero manual steps beyond the normal service restart.

## Acceptance

- Full pytest suite green including the new scheduler tests.
- A schedule created via the API fires exactly once at its due tick in the
  fake-clock harness and updates last_run_at/next_run_at correctly.
- README note in `relay/docs/` (new file) documenting the endpoints and the
  recurrence grammar, so the future iOS management UI lane has a contract.
- PR titled `Lane G — relay scheduled runs (#98)`.
