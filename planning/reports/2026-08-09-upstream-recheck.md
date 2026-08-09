# Upstream re-check — #187 · #241 · #264 · #132 (+ #170b, #224)

**Date:** 2026-08-09 · **Method:** fresh full clone of upstream `main`, code read + `git blame`.
**Nothing was written to any live Hermes install.** The Mac install (`~/.hermes/hermes-agent`)
was read only — no `fetch`, `pull`, or `--unshallow`. OJAMD was probed read-only over HTTP.

---

## 1. The baseline

| | commit | date | notes |
|---|---|---|---|
| **Upstream `main` (comparison target)** | `62431364e35aa10ea17a197a344f9b9f774c1a8e` | 2026-08-09 01:24:08 −0500 | fresh **full** clone, 21,454 commits, `NousResearch/hermes-agent` |
| **Local install** (`~/.hermes/hermes-agent`) | `ceebb21dd7cb7391a58e4b1d345951e5218860c5` | 2026-08-08 23:14:30 −0700 | shallow (`.git/shallow` present), 34 log entries = **clone floor**, 3 commits behind upstream |
| **Inferred assessment baseline (hours ago)** | `3dcbe9001` | 2026-08-08 20:54:45 −0700 | see caveat below |

Clone location: `…/scratchpad/upstream-hermes` (session scratchpad).

### The premise of this re-check is falsified — and that is the headline

The task assumed the four items were assessed against code that upstream had since
outrun by "hundreds of commits." **It had not.** The install was fast-forwarded at
**2026-08-08 23:14 local** — i.e. the assessment already read near-current code.

- **`3dcbe9001..62431364e` = 6 commits, ~4.5 hours.**
- **None of the six touches `gateway/platforms/api_server.py`, `agent/image_routing.py`,
  or `tools/approval.py`.** They are: two installer/update fixes, one pydantic
  warning-suppression fix, and three desktop/Electron commits (incl. an Electron rollback).

Upstream velocity is genuinely high — but the window that matters here is not:

| date | commits |
|---|---|
| 2026-08-01 | 171 |
| 2026-08-02 | 266 |
| 2026-08-03 | 274 |
| 2026-08-04 | 112 |
| 2026-08-05 | 81 |
| 2026-08-06 | 78 |
| 2026-08-07 | 176 |
| 2026-08-08 | 366 |
| 2026-08-09 (partial) | 3 |

**Caveat on the assessment baseline (INFERRED, not proven).** The task reports the
earlier session saw **31** `git log` entries; the install now shows **34** and sits at
`ceebb21`, which is exactly 3 commits past `3dcbe9001` (the install's `HEAD@{1}`, per its
reflog). That arithmetic fits and nothing else does, so `3dcbe9001` is the baseline used
here. If the earlier session actually read `d408fdbfc` (2026-08-08 19:20 −0500) or
`aec331899` (2026-08-04), the delta widens — but §6 surveys **2026-08-04 → HEAD** anyway,
so no conclusion below depends on which of the three it was.

### OJAMD — NOT pinned (this is a real gap)

`GET /health` on `100.110.102.59:8642` returns `{"status":"ok","version":"0.20.0"}`.
Per CLAUDE.md a version string proves nothing about which code serves, and I could not
get behind it:

- `/health/detailed` now **requires auth** (`gateway_auth_error`) — see §6.11; it is no
  longer a free probe.
- The `mcp__hermes-ojamd` session-create call was **blocked by the local permission
  classifier**, so no read-only shell command could be run on OJAMD.

**Everything below is verified against upstream `main` and the Mac install. OJAMD's
served commit is ASSUMED, not verified.** Since the phone talks to OJAMD in production,
that is the one thing worth closing before acting on any of this.

---

## 2. Per item

| Item | Status upstream | Commit(s) if changed | Disposition |
|---|---|---|---|
| **#187** `min_messages` ignored | **UNCHANGED** — absent from the handler at HEAD, and so is `order` | — | **CLOSE** — stays closed; today's close is **confirmed correct** |
| **#241** self-name model id → 404 as HTTP 200 | **UNCHANGED** — both mechanism lines byte-identical, one predates 0.20.0 | — | **KEEP** (park holds; no calculus change) |
| **#264** bind race, no retry | **UNCHANGED** — still deliberate, still `retryable=False` | — | **KEEP** — and **widen the ops rule**: a *second* cause with an identical symptom exists (§4.3) |
| **#132** images dropped host-side | **UNCHANGED** on the mechanism; one adjacent change | `e6b168855` (prompt only, platform lane) | **KEEP** |
| **#170b** phone cannot pin a job model | **UNCHANGED** — whitelist last touched 2026-03-22 | — | **KEEP** — no cleaner path appeared |
| **#224** approval-mode selection | **UNCHANGED** — no config route on `:8642` | — | **KEEP** — slice 3B is not smaller |

**Zero of the six moved.** No item closes or re-opens on upstream grounds.

---

## 3. Verified state

All `file:line` below are at upstream `62431364e`. Line numbers in `api_server.py`
(7,345 lines at HEAD) match the install's for every citation checked.

### VERIFIED

**#187 — the close was right, and still is.**
- `gateway/platforms/api_server.py:3334–3366` — `_handle_list_sessions` reads exactly
  four query params: `limit`, `offset`, `source`, `include_children`. No `min_messages`.
  No `order` — `order_by_last_active=True` is **hardcoded** at the `list_sessions_rich`
  call.
- `hermes_state.py:6500` — `list_sessions_rich(…, min_message_count: int = 0, …,
  order_by_last_active: bool = False, …)`. The DB layer has both knobs; the HTTP surface
  exposes neither. The "one kwarg upstream" characterization holds.
- **Trap worth naming:** `hermes_cli/web_routers/sessions.py:60` *does* take
  `min_messages`. That is the **dashboard (`:9119`)**, a different app. Anyone grepping
  the repo for `min_messages` will find it and mis-conclude the gateway has it. This is
  CLAUDE.md's route rule firing exactly as written.

**#241 — neither line changed.**
- `api_server.py:3397` — `model = body.get("model") or self._model_name`
  (`_handle_create_session`). `git blame` → **`f7527b0fdb`, Bailey Dixon, 2026-05-20**.
- `api_server.py:2753` — `elif session_row_model and not confirmed_runtime_lock:`
  → `7cd48733db`, 2026-07-24.
- `api_server.py:2766` — `model = resolve_effective_model(None, session_row_model, model)`
  → **`ba7da1332c`, teknium1, 2026-07-29**. Same line number as the install cited.
- The HTTP-200 half is structural and intact: `_handle_session_chat`
  (`api_server.py:3650`) ends at **`:3755–3763`** with an unconditional
  `web.json_response({… "message": {"role":"assistant","content": final_response} …})`.
  No status is derived from the agent result, so a provider failure returns as prose at
  200.

**#264 — deliberate, unchanged, and the ops rule's assumptions hold.**
- `api_server.py:7248–7284` — direct `TCPSite` bind, no pre-probe; `OSError` →
  `errno.EADDRINUSE` → `_set_fatal_error("api_server_port_in_use", …, retryable=False)`.
  `git blame` → `164bca658e` / `bda8bd76a8`, both **2026-07-16**.
- Upstream's own comment names the reason: a bare `return False` made the reconnect
  watcher "loop forever at the backoff cap (observed: 1568+ retries over 5 days …)
  filling errors.log and leaking the adapter's ResponseStore fds each retry."
- `/platform resume api_server` is real and is upstream's own prescribed recovery —
  `gateway/slash_commands.py:1438`, and named verbatim in the error string at
  `api_server.py:7165` and `:7276`.
- `~/.hermes/gateway_state.json` still carries per-platform state:
  `gateway/status.py:590` (`"platforms": {}`), `:997`, `:1019–1027`
  (`payload["platforms"][platform]["state"]`). **The proposed ops rule that reads
  `platforms.api_server.state` is valid at HEAD.**

**#132 — the Sessions lane still has no vision fallback.**
- `agent/image_routing.py`'s `decide_image_input_mode` is reached from the gateway at
  exactly one place: `gateway/run.py:16260`, inside `_prepare_inbound_message_text`
  (`gateway/run.py:16155`).
- `_prepare_inbound_message_text` has exactly **two** production callers, both in
  `gateway/run.py` (`:16574`, `:16580`) — the platform-adapter lane.
- **`gateway/platforms/api_server.py` contains zero references** to
  `_prepare_inbound_message_text`, `MessageEvent`, or `image_routing`. The phone's lane
  cannot reach the fallback.
- Both the call site and `_decide_image_input_mode` (`gateway/run.py:21956`) blame to
  `1a3a9de630`, **2026-07-29** — untouched since.
- The dispatch doc's claim that `prepare image failed` has zero hits at head is
  **confirmed** (zero hits repo-wide at `62431364e`).

**#170b — no cleaner path.**
- `api_server.py:5543` — `_UPDATE_ALLOWED_FIELDS = {"name", "schedule", "prompt",
  "deliver", "skills", "skill", "repeat", "enabled"}`. No `model`, no `provider`.
  Last changed by `0f1c97017`, **2026-03-22**.
- `api_server.py:5595–5599` — `_handle_create_job` reads `name`, `schedule`, `prompt`,
  `deliver`, `skills`, `repeat`. No `model`.
- `POST /api/sessions/{id}/model` exists (`api_server.py:2065`,
  `_handle_session_model_lock`) — but that pins a **session**, not a **job**, which is
  what #170b needs. The 2026-08-01 "0.19.0 may have made the second half solvable" lead
  does **not** pay out.

**#224 — mode selection is still not on `:8642`.**
- Full route table read at `api_server.py:2041–2092`. **No `/api/config`, `/api/settings`,
  or `/v1/config`.** The string `approvals` appears **nowhere** in `api_server.py`.
- `approvals.mode` is a config.yaml key read via `cfg_get(config, "approvals", "mode")`
  at `tools/approval.py:2932` (normalizer at `:2887`, incl. the YAML `off`→`False`
  gotcha). Selection remains dashboard/config-file only. **Slice 3B is not smaller.**

### ASSUMED (not verified)

1. **OJAMD's served commit.** Only `version: 0.20.0` was obtainable. Per CLAUDE.md that
   proves nothing. Everything above describes upstream `main` and the Mac install.
2. **The assessment baseline was `3dcbe9001`** — inferred from the 31→34 log-entry delta
   (§1). Not load-bearing for any conclusion.
3. **This is a code read, not a behavioral probe.** No live request was issued against
   any gateway to re-observe any of the six defects. Where a defect is structural
   (#187's absent params, #224's absent route, #170b's whitelist) the code read is
   dispositive; where it is behavioral (#241's 200, #132's silent drop) the code read
   shows the mechanism is present, not that it fired today.

---

## 4. ⚠️ Corrections

**Most of tonight's work survives intact.** Every substantive finding in
`dispatch/OPUS-T27-host-upstream-decisions.md` re-verifies at upstream HEAD — the four
mechanism locations, the `retryable=False` rationale, the zero-hit `prepare image failed`,
and the `min_messages`/`order` absence. Nothing there needs retraction. What follows is
additive.

**4.1 — CLAUDE.md's `:8642` route table is still accurate (confirmation, not correction).**
*Home: `CLAUDE.md`, "Hard-won gotchas".* The table was verified 2026-08-02 against 0.19.1
and carries a standing "re-verify before any NEW route claim on 0.20.0" warning. It is
**byte-for-byte correct** against `api_server.py:2041–2092` at 2026-08-09 upstream HEAD.
Worth a dated line saying so, since that saves the next lane a probe.

**4.2 — `/health/detailed` now requires auth.** *Home: `CLAUDE.md` route table.* It is
still in the table, but it is no longer an unauthenticated probe — `2d8d08cae`,
**2026-07-01**. Confirmed live: OJAMD returned `gateway_auth_error` to an unauthenticated
GET while `/health` answered fine. Any runbook step that reaches for `/health/detailed`
without a key is already broken.

**4.3 — #264 has TWO causes, not one, and they present identically.** *Home:
`OPEN_ITEMS.md` #264, and the ops rule wherever it lands.* Alongside the port-conflict
guard, `api_server.py:7147–7168` fails the adapter closed with
`_set_fatal_error("api_server_key_invalid", …, retryable=False)` when
`_api_key_passes_startup_guard()` rejects `API_SERVER_KEY` — missing, placeholder, under
16 chars, **or strength-unverifiable because `hermes_cli.auth` failed to import**. Same
non-retryable drop, same `/platform resume api_server` recovery, same user-visible
symptom: *gateway process healthy, chat plane absent.* The last clause is the nasty one —
a half-finished update that breaks an import turns a good 64-char key into a fatal error.
**An ops rule that only checks the port will misdiagnose this.** Reading
`platforms.api_server.state` from `gateway_state.json` covers both; checking the port
owner does not.

**4.4 — the shallow-clone floor is now 34, not 31.** *Home: any doc citing "31 commits
past 0.20.0".* The dispatch doc already corrects the underlying error (that number is
clone depth, not a delta). Recording the new value so the next reader does not treat
34 as a measured "+3".

**4.5 — the `/api/sessions` response shape and `has_more` semantics changed.** *Home:
wherever Talaria's session-list contract is written.* See §6.1 — this is a live contract
change, not a stale claim, but it will falsify any doc that lists the session payload
fields.

---

## 5. #241 — factual status only

- **Both mechanism lines are unchanged at upstream HEAD.** `api_server.py:3397` was last
  touched **2026-05-20** (`f7527b0fdb`) — it predates 0.20.0 entirely. `api_server.py:2766`
  was last touched **2026-07-29** (`ba7da1332c`). The defect is not a regression from a
  recent commit; it is settled code.
- **The HTTP-200 half is likewise intact** — `_handle_session_chat` returns 200
  unconditionally (`api_server.py:3755–3763`).
- **Nothing has changed that bears on the park.** No upstream commit in the surveyed
  window touches the model-resolution precedence chain or the error-status derivation.
- **I did not search upstream issues or PRs for a duplicate report**, and no upstream
  contact of any kind was made.
- **No submission recommendation is offered, and the upstream state does not change the
  calculus** — there is no question for Owen here. The park stands on its own terms.

---

## 6. What changed that we did NOT ask about

Window: **2026-08-04 → 2026-08-09 HEAD** (from `aec3318`, the last sha CLAUDE.md names).
Twelve commits touch `gateway/platforms/api_server.py` alone. Ordered by how much they
bear on our board.

**6.1 — `PATCH /api/sessions/{id}` now accepts `pinned` and `archived`. NEW CAPABILITY +
CONTRACT CHANGE.** `cef7d1a1e` (2026-08-06) + `45f23205d` (2026-08-06).
- The PATCH whitelist went from `{"title", "end_reason"}` to
  `{"title", "end_reason", "pinned", "archived"}`; non-boolean values 400 with
  `invalid_session_field`.
- `_session_response` (`api_server.py:3273–3286`) now emits `pinned` and `archived` as
  **real booleans** (SQLite 0/1 coerced).
- `_handle_list_sessions` passes `include_pinned=True`, so **pinned sessions are
  back-filled past the `limit`**, and `has_more` is computed from the *unpinned* count
  only (`api_server.py:3352–3366`).
- **For us:** pin/archive from the phone is now a supported server-side operation instead
  of client-local state. And if anything in Talaria paginates `/api/sessions` on
  `len(data) >= limit`, that assumption is now wrong — a page can legitimately return
  more rows than `limit`.

**6.2 — a gateway bounce now cooperatively interrupts in-flight Sessions-API turns.**
`51fa7db46` + `d9ddfb23d` + `416d2a015` (all landed 2026-08-07).
- Before: `_interrupt_running_agents()` walked only `GatewayRunner._running_agents`, "a
  dict no API turn ever enters." Every restart with a live API turn burned the full drain
  timeout and then amputated the turn's tool subprocesses "with no cooperative interrupt
  and no resume marker."
- Now: `api_server.py:1465` adds `_shutdown_interruptible_agents`, registered at the one
  unconditional creation site in `_run_agent`, covering **all six** non-`/v1/runs` agent
  entry points — which includes both `/api/sessions/{id}/chat` and `/chat/stream`.
  `interrupt_active_runs()` walks both registries deduped by identity, and the post-
  interrupt settle window now polls API work too.
- **For us: this lands squarely on #235, #295, and #264.** A mid-turn gateway restart is
  now a *cooperative interrupt* rather than an amputation, which changes what the phone
  should expect to see on the wire when a turn dies — and therefore what #295's
  recoverability arming is reasoning about. Worth a look before the next #295 slice.

**6.3 — upstream built its own unclean-exit turn recovery.** `6774760b6` "recover exact
turns after unclean exits" + `59a128c6f` / `5ff328cc7` / `c5e032c80` (active-turn marker
lifecycle, failure-atomicity, cleanup gaps), 2026-08-06. `gateway/session.py` +148 lines,
`gateway/run.py` +106, plus `tests/gateway/test_active_turn_recovery.py` (308 lines).
- **For us:** #295 is building client-side recovery against a host that is simultaneously
  growing server-side recovery. Not a conflict today, but the two should be read together
  before #295's next slice — this is the closest upstream has come to our problem.

**6.4 — a per-session turn lease now serializes concurrent turns — but NOT on our lane.**
`29af112cd`, `b2b681fef`, `b3e9e9170`, `3a3aed3c1` (2026-08-06/07). New
`gateway/turn_lease.py`: `SessionTurnLeaseRegistry`, fail-closed `TurnLeaseTimeoutError`,
timeout configurable as `agent.gateway_turn_lease_timeout` (default **1800s**,
`hermes_cli/config_defaults.py:42`).
- **Scope check: `gateway/run.py` only. `api_server.py` has zero references.** The
  Sessions API lane keeps its own `_admit_api_agent_request` admission decorator.
- **For us:** relevant to **#267** (message queuing mid-turn) as a *non-answer* — upstream
  solved same-session turn collision for the platform adapters and left the API lane
  alone. Do not assume the phone's lane is protected.

**6.5 — session titling moved to turn START, and it looks like it reaches our lane.**
`f726090d4` (2026-08-08). Titling used to fire on the first *response* — "p50 151s, p90
1212s across real sessions," and a failed or interrupted turn never got a title at all.
Now: a deterministic title derived from the user's opening message is written **inline
before the model runs**, then one small-model call upgrades it (JSON-constrained, so no
preamble to strip). Four surfaces' duplicate copies collapsed into one shared prologue.
- Code path (read, not device-verified):
  `api_server.py:6196 agent.run_conversation(…)` → `run_agent.py:7910` forwards to
  `agent.conversation_loop.run_conversation` → `agent/conversation_loop.py:1448
  build_turn_context(…)` → `agent/turn_context.py:1345
  _maybe_title_session_at_turn_start(…)`.
- **For us: this is #177's territory** ("session cards show title and preview as the same
  line — Hermes-side titling"). If it fires on the Sessions lane, sessions get a real
  title within ~1s of the opening message instead of minutes-or-never. **Unverified on
  our lane — worth one device check**, and it may retire most of #177.

**6.6 — the Sessions SSE stream now emits raw UTF-8.** `7098862de` / `7a1f2e3a6` /
`1a09b0725` / `221afc0cb` (2026-08-04). A `_sse_frame()` helper (`api_server.py:187–206`)
replaced five inline encode sites; the **session event stream** writes with
`ensure_ascii=False` (`api_server.py:3970`), while the OpenAI-compat chunks keep
`ensure_ascii=True`. Separately, the SSE poll loop was replaced with a
`call_soon_threadsafe`-fed `asyncio.Queue`.
- **For us:** JSON-decoding clients are unaffected — but non-ASCII now rides as raw UTF-8
  bytes rather than `\uXXXX` escapes, and frame *timing* changed (queue-fed, not polled).
  Any test fixture that pins exact SSE bytes, and anything reasoning about inter-frame
  latency, should be re-checked. Note this also confirms the sessions stream **does** emit
  `event:` lines (`_sse_frame(payload, event=name, …)`) — unlike `/v1/runs/{id}/events`,
  exactly as CLAUDE.md records.

**6.7 — auto vision preprocessing got terse.** `e6b168855` (2026-08-08). The
"describe everything in thorough detail" prompt became a 2–4 sentence summary prompt,
because image-bearing messages were generating ~2000-char descriptions (35s+ on local
models). Platform lane only — **#132's Sessions-lane gap is untouched** — but it changes
what a vision-routed description looks like wherever one does appear.

**6.8 — oversized transcripts no longer exhaust memory.** `c750d5354` (2026-08-08),
`fix(sessions)`. Relevant because the phone's lane must ride history on the request.

**6.9 — reasoning config now resolves per request model.** `93964fda3` (2026-08-08):
"resolve reasoning for the request's model, not model.default." Adjacent to #241's
resolution chain but does not touch either of its lines.

**6.10 — `hermes pause` / `hermes resume` global emergency stop.** `5db1b72b1`
(2026-08-07). A new CLI-level kill switch, distinct from `/platform resume`. Ops-relevant;
note it exists before someone confuses the two.

**6.11 — `/health/detailed` requires auth and the api_server fails closed on a weak key.**
`2d8d08cae` (2026-07-01 — predates the window, but is not recorded anywhere on our side).
Detail in §4.2 and §4.3; this is both a runbook correction and #264's second cause.

**Also seen, lower relevance:** `01bc8a875` honest recovery message for session-persistence
failures (replacing "unknown error"); `a51a4cb09` replayed tool calls marked completed in
Responses output items; `1f5a22264` model+provider added to the `agent:end` hook payload
(bears on #251's plugin lane); `566b5b16a` lone-surrogate chokepoints across agent+gateway;
`6bbe55dd0` agent cache bounded by memory rather than count/age.

---

## 7. Bottom line

Nothing upstream moved on any of the six. The four items' mechanisms are all still
present at `62431364e`, three of them last touched weeks ago. **#187's close today was
correct and is confirmed by an independent read.** The genuinely new information is in
§6 — the shutdown-interrupt and unclean-exit-recovery work (§6.2, §6.3) bearing on
#235/#295, the session pin/archive contract change (§6.1), the titling move that may
retire most of #177 (§6.5), and #264's undocumented second cause (§4.3).

**The one open verification gap: OJAMD's actual served commit.** Everything here
describes upstream `main` and the Mac install.
