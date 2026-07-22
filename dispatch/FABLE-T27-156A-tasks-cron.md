# FABLE-T27-156A — Tasks: browse, create, edit and control the agent's scheduled cron jobs

**Item:** OPEN_ITEMS #156a (lane of #156), sized by #158, design-referenced by #160, constrained by #161 ·
**Repo:** AethyrionAI/Talaria-27 · **Base:** main · **Branch:** `claude/t27-156a-tasks-cron` ·
**Size:** medium-large, one PR (may split at D4 if it runs long — see Splitting)
**Staleness check:** re-run at start (`gh pr list --repo AethyrionAI/Talaria-27`,
`git log --grep t27-156a`). OPEN_ITEMS numbers ≠ GitHub numbers — do not assume #156 is a PR.

## Mission

Give the phone a real surface on the agent's scheduled jobs: list them, see status truthfully,
create and edit them, and run/pause/resume/delete. **No new services, no new installs, no upstream
changes** (#161) — every endpoint below is already on the Hermes gateway `:8642` that Talaria
authenticates to for chat today. This is pure client work.

The single differentiating deliverable is **D4, the schedule input**. Read it before starting D3.

## Verified API surface — do NOT invent shapes

All on `:8642`, `Authorization: Bearer <API_SERVER_KEY>` — the same auth the chat path uses.
Verified against hermes-agent 0.19.0 (`GET /api/jobs` returns `HTTP 200 {"jobs": []}` on an empty host).

| Method | Path | Notes |
|---|---|---|
| GET | `/api/jobs` | → `{"jobs": [...]}` |
| POST | `/api/jobs` | create |
| GET | `/api/jobs/{job_id}` | → `{"job": {...}}` |
| PATCH | `/api/jobs/{job_id}` | see whitelist below |
| DELETE | `/api/jobs/{job_id}` | |
| POST | `/api/jobs/{job_id}/pause` | |
| POST | `/api/jobs/{job_id}/resume` | |
| POST | `/api/jobs/{job_id}/run` | trigger now |

**PATCH accepts exactly:** `name`, `schedule`, `prompt`, `deliver`, `skills`, `skill`, `repeat`,
`enabled`. Anything else is ignored — build the edit form to this whitelist, not to the full record.

**The HTTP surface does NOT expose** `script`, `no_agent`, `workdir`, or model override on create,
even though those fields exist on the record (they are CLI/tool-only). Do not build inputs for them.
Display them read-only if present on an existing job.

**Job record fields** (present on read; treat every one as optional and decode tolerantly):
`id`, `name`, `prompt`, `skills`, `skill`, `model`, `provider`, `provider_snapshot`,
`model_snapshot`, `base_url`, `script`, `no_agent`, `context_from`, `schedule` (object with
`kind`/`display`), `schedule_display`, `repeat` (`{times, completed}`), `enabled`, `state`
(`"scheduled"`/`"paused"`), `paused_at`, `paused_reason`, `created_at`, `next_run_at`,
`last_run_at`, `last_status`, `last_error`, `last_delivery_error`, `deliver`, `origin`,
`enabled_toolsets`, `workdir`, `attach_to_session`.

**Tolerant decoding is mandatory.** Every field optional, unknown fields ignored, wrong-typed
fields degrade rather than throw. Upstream is not contractual (see `UPSTREAM_TESTED_SHA`); a server
field changing type must never blank the screen. This is the one pattern worth copying wholesale
from the hermex review (#160).

## Deliverables

### D1 — `Talaria/Services/Live/CronJobService.swift`

Client over the eight endpoints above. Returns typed, user-renderable errors
(unreachable / auth / not-found / server-rejected-with-message / timeout). The
server-rejected case **must carry the server's message string through verbatim** — D4 depends on
surfacing it, because the server is the only cron validator that exists.

Not paired: there is no host-side work in this lane. If you find yourself wanting a relay endpoint,
stop and re-read #161 — the constraint is deliberate.

### D2 — `Talaria/Models/CronJob.swift`

Tolerant `Decodable` models for the record above, plus a **client-derived status**:
`running` / `active` / `paused` / `off` / `error` / `needsAttention`.

The server has no single status field — derive it. Include a synthesized `needsAttention`
(recurring job + not enabled + no `next_run_at`, or recurring + `last_error` + no `next_run_at`):
states the API does not aggregate but the user needs to see. This is the strongest idea from the
hermex review (#160) — the UI ends up more truthful than the API.

### D3 — `Talaria/Features/Tasks/TasksScreen.swift` + `TaskDetailScreen.swift`

List → detail. Four content states, distinguished explicitly:

- **loading + empty** → progress
- **error + empty** → error view with a retry action
- **empty + loaded** → empty state that *offers creation inline*, not just a toolbar `+`
- **loaded** → list, pull-to-refresh

**Errors never replace content that already exists.** A failed refresh with jobs on screen keeps
the jobs and surfaces the error non-destructively. (Copied from #160; they got this right.)

List rows: name, status badge, next-run, and a short prompt preview — **not** the nine-row metadata
stack hermex uses. Push the rest to detail (#160 weakness 2). Detail carries full metadata,
recent output if present, and the actions: Run Now, Pause/Resume, Edit, Delete (destructive,
confirmed).

Mutations propagate list↔detail via a small `upsert`/`delete` enum rather than a refetch, so the
two never disagree or flicker (#160 idea 2).

### D4 — The schedule input ⭐ **the point of this lane**

hermex ships a bare free-text field validated only for non-emptiness; users type cron blind and
discover mistakes via a server error (#160 weakness 1). **We do better, and it is cheap.**

**Verified schedule grammar** (`cron/jobs.py:512` `parse_schedule`) — the server accepts four forms:

| Input | Parsed as |
|---|---|
| `every 30m`, `every 2h` | recurring interval |
| `0 9 * * *` | cron expression (5–6 fields, validated by `croniter`) |
| `2026-02-03T14:00` | one-shot at timestamp |
| `30m`, `2h`, `1d` | one-shot, that far from now |

Build a **structured picker that emits one of these strings**:

- **Interval** — "every N" with a unit stepper → emits `every 30m`
- **Daily / weekly at a time** — time picker (+ weekday) → emits the cron expression
- **Once** — relative (`2h`) or a date-time picker → emits duration or ISO
- **Advanced** — raw text field, exactly hermex's behaviour, for anything the presets can't express

**Preview rule, and be precise here:** for preset-generated schedules we render the humanized
description **from our own inputs** ("Every day at 9:00 AM") because we generated the string and
know what it means. **Do NOT ship a cron parser** to preview Advanced-mode input. For Advanced,
show no local preview; after save, display the server's returned `schedule_display` /
`schedule.display`, which is authoritative. Honest silence beats a second parser that disagrees
with the server.

**⚠️ Timezone footgun — must be surfaced in UI.** Naive timestamps are anchored to the *configured
Hermes timezone on the host*, not the device's (`cron/jobs.py`, and the `#51021` comment there
explains why). A user in a different timezone from their host will otherwise set 9:00 AM and get
a different hour. Show the host's timezone next to any absolute time input. If the host timezone
is not obtainable from an existing endpoint, state that the time is the host's, not the phone's —
do not silently assume they match.

**Validation:** non-empty gating client-side, exactly as hermex does — but on server rejection the
sheet **stays open with the input intact** and renders the server's message inline. That is the one
thing hermex got right about this flow and it must be preserved.

Also note: cron expressions require `croniter` on the host. If absent the server raises. Surface
that error text as-is rather than translating it; the message names the missing package.

### D5 — Create/edit sheet

**One sheet for both**, driven by a draft value type, per #160 idea 1. Fields limited to the PATCH
whitelist. `deliver` uses a **server-driven picker with free-text fallback**: if the options list is
unavailable or empty, degrade to a plain text field; if the current value is not in the server's
list, preserve it as a marked "(custom)" row so editing never clobbers a legacy value. Zero data
loss across server versions.

`skills` is free text (comma-separated) in this lane. A picker fed from `GET /v1/skills` is 156b's
business — do not couple the lanes.

### D6 — Tests

Swift Testing (`@Test`), not XCTest. Cover: tolerant decoding (missing fields, wrong types, unknown
fields), status derivation including every `needsAttention` branch, **schedule-string emission for
every preset** (table-driven — this is the highest-value test in the lane), the draft's validation
gating, and the list↔detail mutation propagation. No network in tests; fixture the service.

## Explicitly out of scope

- Run history — the endpoint does not exist (hermex has the same gap; theirs is roadmap P2)
- Skills/model/provider pickers — 156b and later
- Any relay or connector change (#161)
- Any upstream hermes-agent change (#159 — Owen has ruled out PRs)
- Polling/auto-refresh. **But do not repeat hermex's bug:** elapsed time must not be presented as
  live when it is a load-time snapshot. Either timestamp it ("as of 14:02") or omit it (#160 weakness 3)

## Splitting

If this runs long, split at D4: **Lane A1** = D1+D2+D3+D6-partial (browse, detail, run/pause/resume/
delete, read-only). **Lane A2** = D4+D5 (create/edit + the schedule picker). A1 is useful shipped alone;
A2 is where the differentiation is. Do not ship A2 without A1.

## Conventions — non-negotiable

- **Merge commits only**, never squash. File-scoped commits.
- **OPEN_ITEMS.md edits go in their OWN commit**, never mixed into a feature commit. This has been
  violated repeatedly on prior lanes — check before pushing.
- `xcodegen generate` is required because this lane adds new Swift files; the pbxproj regen goes in
  a **separate commit** from the feature work. After regen, verify `aps-environment: development`
  survived in `Talaria/Talaria.entitlements`.
- Toolchain: `export DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer` in every shell.
  "Cannot find in scope" on iOS 27 APIs means the wrong SDK, not broken app code — never edit app
  code to satisfy a stale SDK.
- Build/test: `xcodebuild test -project Talaria.xcodeproj -scheme Talaria -destination
  'platform=iOS Simulator,id=47F68496-24F9-45D9-93D3-1C778DB6B557' CODE_SIGNING_ALLOWED=NO`.
  Baseline to beat: **931 tests / 84 suites green**. Swift Testing reports separately — read the
  `Test run with N tests in M suites passed` line, not `Executed N tests` (that one counts only the
  8 XCUITests).
- Swift 6.2 strict concurrency. **Do not** introduce mutable `static let shared` singletons,
  retroactive conformances on stdlib types, or block-based `NotificationCenter` observers — all three
  are patterns the hermex codebase uses that will not survive here (#160).

## Provenance

This lane was informed by reading `uzairansaruzi/hermex` (MIT) as a **design reference**. No hermex
source is used or adapted — the analysis captured structure and decisions only, deliberately.
`THIRD_PARTY_LICENSES.md` records this as attribution, not a license obligation. **If you find
yourself wanting to copy their Swift, stop** and flag it; that would change the licensing posture
and the file must be updated to a full MIT notice first.
