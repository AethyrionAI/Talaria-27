# PHASE 3 — THE RUNS-PLANE MIGRATION (approvals + steering + poll-recovery, one plugin-bundled lane)

**Status: PLAN, awaiting Owen's routing. No code was written. Nothing on the live Hermes
install was modified or bounced while writing this — every Hermes claim below is a read of
`~/.hermes/hermes-agent` (head `01a1037d1`) or of the plugin study worktree at
`~/Documents/Claude/t27-263-plugin/talaria` (`fd5d7d1`), with a `file:line`.**

Written 2026-08-07 for a morning read, in the #258/#224 pattern: one document, every open
question carries a recommendation. Say "approved", or name what you'd flip.

**Why §1 exists and is first.** Owen caught a real failure last night: steering was proven
on the wire on 2026-08-06 and the tracker still read *"parked… will stay that way. Do not
design around it."* That is not a one-off — the same night's probes settled a dozen things
that live only in handoffs. §1 is the full inventory with a disposition on every line, so
nothing proven gets silently dropped. **Two stale tracker lines are still live right now
(§1, T1/T2) and their correction text is drafted below.**

**Evidence conventions used throughout:**
- **PROVEN** — observed on the wire, live, with a control arm or a verbatim log.
- **CODE-READ** — read from source with a `file:line`; not observed running.
- **NEW (this session)** — found tonight, code-read only, never probed. Flagged inline.
- **UNVERIFIED** — named as a question, with the probe that would settle it.

---

## 1. SETTLED-FINDINGS INVENTORY

Every probe result the three 2026-08-06 handoffs record, plus the research reports they
cite, plus tonight's code-read additions. Tags: **CARRIED** (lands somewhere in this plan)
· **TRACKER-NOTE-NEEDED** (a tracker entry should record it — note text given) ·
**DROPPED** (explicit reason).

### 1.1 Steering

| # | Finding | Evidence | Disposition |
|---|---|---|---|
| S1 | **Steering WORKS, proven twice on the wire.** tui plane: `session.steer` fired mid-tool-call (`terminal: sleep 20`) → the turn's final output became the steered text (`message.complete 'STEERED-OK'`), no extra user bubble in `session.history`. Runs plane: control run answered `BANANA`, steered run answered **`PLUM`**, same prompt/model/build, one `agent.steer()` at t=9s. | PROVEN 2026-08-06 (Owen's go, "Go for a test on steering"); report `H-escape-b-runs-steer.md` §2–§3; `OPEN_ITEMS.md:5981-5999`, `:6059-6076` | **CARRIED** → §2.4 (slice 3C is built on it) |
| S2 | **`/v1/runs` retains a live agent, reachable from plugin code with zero core edits.** `APIServerAdapter._active_run_agents` is an *instance attribute* keyed by `run_id`, written right after `_create_agent()`, popped in the task's `finally`; the orphan sweep is `task_done`-gated so it cannot yank a live agent. Reached via the module-level runner weakref whose own comment says it exists for plugin platforms. | PROVEN (runtime JSON: `agent_found:true, agent_type:"AIAgent", has_steer:true`) + CODE-READ `api_server.py:1345,:1422,:6462,:6681,:6919-6929`; `gateway/run.py:3383-3387,:5842,:13690` | **CARRIED** → §2.3 (the plugin seam) |
| S3 | **The runs migration buys approvals + steering + poll-recovery on ONE plugin-bundled lane; tui_gateway becomes optional.** | Synthesis, SOLO-DAY handoff "WHAT THE PROBES SETTLED"; `OPEN_ITEMS.md:5969-5976` | **CARRIED** → this whole document |
| S4 | **THE STEER CONSTRAINT.** A steer is consumed at the next **tool-result boundary**. With no boundary left (agent writing prose) it is **silently dropped and the RPC still answers `{"status":"queued"}`** — the ACK is a false positive. Substrate-wide (`AIAgent._pending_steer`), all planes. Both earlier successes worked only because a `sleep 20` was in flight. | PROVEN 2026-08-06 boundary probe (no-tool turn, steered mid-compose, answer unaffected, no leak into the next turn) + CODE-READ `agent/agent_runtime_helpers.py:3921,:3949-3963`; `agent/turn_finalizer.py:683` | **CARRIED** → §2.5 (app-side gating) and §2.6 (composes with #267) |
| S5 | **Steer is NOT gated on `display.busy_input_mode`** — the Mac is `interrupt` and the dedicated RPC worked anyway (the mode governs bare `prompt.submit` while busy). **Supersedes** the earlier "steer needs `steer` mode set" note. Bonus: `config.get` calls `display.busy_input_mode` an unknown key, so a client cannot query the mode over RPC. | PROVEN 2026-08-06 re-run; `OPEN_ITEMS.md:6066-6072` | **CARRIED** → §2.4 (no host config precondition for steering) |
| S6 | **`_active_run_agents` is a private attribute with no stability contract** — an upstream rename makes the steer stop landing **silently**. | Report H §4 "One honest risk"; `OPEN_ITEMS.md:6015-6017` | **CARRIED** → §4.2 (the fail-loud requirement is a bar, not a nicety) |
| S7 | **The Sessions-API chat lane is structurally unsteerable.** Nothing publishes that lane's agent: the three `turn.agent =` write sites are all on the platform path in `gateway/run.py`; `api_server.py` has none. The key namespace *is* bridgeable (`X-Hermes-Session-Key`); the value is never written. | CODE-READ, report F §1.2/§2.1/§3; `gateway/run.py:10504,:15622,:24725`; `api_server.py:6020,:6178`, `:7355-7356` | **CARRIED** → §5 (the cost of not migrating) |
| S8 | **Escape A — a plugin-side monkeypatch of `_create_agent` would work** but binds to a private *signature*, is hardening-shaped, and still inherits S4. | CODE-READ, report F §5.2 | **DROPPED.** Escape B (S2) reaches the same substrate binding only an attribute *name*, with no signature dependency. Keep F §5.2 as the record; do not build. |
| S9 | **Forging a `session_key` from the talaria adapter into the gateway busy handler = silent loss** — the text lands in a pending FIFO that nothing drains. | CODE-READ, report F §2.4(b); `gateway/run.py:8905-8939` | **DROPPED** as a route. Named here so nobody re-tries it. |
| S10 | **No side door to the agent object:** plugin tools get `task_id/session_id/user_task` only; plugin hooks get no agent; the interrupt machinery is thread-keyed booleans; no weakrefs in the relevant modules. | CODE-READ, report F §2.5 | **CARRIED** as the reason §2.3's seam is the only seam. |
| S11 | **A CLI subcommand CANNOT do the steer reach** — a CLI is a separate OS process with an empty runner weakref and its own adapter map. The reach must be in-process (webhook event or tool). | PROVEN by construction (report H §3 method correction) | **CARRIED** → §2.3 (why the reach rides `POST /api/platforms/talaria/events`) |
| S12 | **Upstream PR adding a `/steer` route** — the pre-Escape-B path. | Owen's standing no-upstream-PR ruling 2026-07-22; #241 precedent ("I don't want to do a PR, anxious") | **DROPPED.** Not needed now — Escape B removes the reason it was ever considered. |

### 1.2 Approvals

| # | Finding | Evidence | Disposition |
|---|---|---|---|
| S13 | **Approvals are e2e GREEN on `/v1/runs`:** submit with `session_id` → run parks `waiting_for_approval` + emits `approval.request` → `POST /v1/runs/{id}/approval {"choice":"once"}` → `resolved: 1` → run resumes, executes, `run.completed`. The timeout arm was proven by accident in the same session (approving after the window → `approval_not_pending`, run self-completes blocked). | PROVEN 2026-08-05 (runs `run_ea99…`, `run_e6bb…`); `OPEN_ITEMS.md:5716-5726` | **CARRIED** → §2.2, slice 3B |
| S14 | **The Sessions plane has no approval wiring at all.** `register_gateway_notify` appears **exactly once** in the whole api_server — inside `_handle_runs`. The chat handlers register nothing. | CODE-READ `api_server.py:6524` (only site), `:6298` (`_handle_runs`), `:3515`/`:3632` (chat handlers) | **CARRIED** → §5 |
| S15 | **What a Talaria chat turn actually does under host `mode: manual`:** not a hang, not a silent auto-approve — `_bind_api_server_session` hardwires `platform="api_server"` so `_is_gateway_approval_context()` is true, the gate takes the gateway branch, finds no notify callback, and **blocks-and-queues** for a `/approve` nobody on our plane can reach. The agent is handed "⚠️ … Asking the user for approval" and narrates it. **The user sees the agent say it is asking, and then nothing.** | CODE-READ `api_server.py:5946-5955`; `tools/approval.py:243-261`, `:3154-3171`; `design/APPROVAL_MODES_PROPOSAL-2026-08-07.md` §4 | **TRACKER-NOTE-NEEDED → #224.** Note: *"2026-08-07: the §F7d failure has a mechanism, not just a symptom — a Sessions-plane turn under host `manual` is blocked-and-queued for an unreachable `/approve` (`tools/approval.py:3154-3171`), and the agent narrates 'asking for approval' with nothing behind it. The runs plane has the full wire (`register_gateway_notify` fires only in `_handle_runs`, `api_server.py:6524`), proven e2e 2026-08-05. Half (2) stays parked; the fix rides Phase 3 slice 3B."* |
| S16 | **The planes are disjoint:** a Sessions-API `run.started` id 404s on `/v1/runs/{id}` while the run is live and after it completes. | PROVEN 2026-08-04 (`run_597cd29e…`); `OPEN_ITEMS.md:4552-4560` | **CARRIED** → §2.1 (this is why "migrate", not "reach across") |
| S17 | **`approvals.timeout` is per-host and observed to vary** (60s Mac / 360s OJAMD; config default 300s). Timeout = deny is the safe failure and is what was observed. **`approvals.cron_mode: deny`** — cron runs deny side effects silently. | PROVEN 2026-08-05; `OPEN_ITEMS.md:5727-5731`, `:4593-4594` | **CARRIED** → §6 Q5 (a host config edit Owen must make) |
| S18 | **`approvals.mode` is dashboard-only config** (`:9119`, dashboard auth); `/api/config` 404s on `:8642`. | PROVEN 2026-08-02, re-confirmed in the approvals proposal §4 | **DROPPED** from Phase 3 (this is #224 half (2), and it stays parked). Answering approvals ≠ reading the mode; we only need the former. |
| S19 | **Every MCP elicitation AUTO-DECLINES on the chat plane** (`request_elicitation_consent` fails closed with no notify callback) — a silent capability loss that looks like the tool not working. The runs plane has it. | CODE-READ, report C §5.2; `tools/approval.py:4292,:4319-4327` | **CARRIED** → §5 (an unlisted cost of staying) |
| S20 | **Owen's routing, 2026-08-05:** option (a) chosen — *"Route gate-able turns through runs sounds good if we can get the timing right. I think this may slot well into the relay retirement."* | Owen, `OPEN_ITEMS.md:5719-5726` | **CARRIED** — this plan is that routing, made concrete. |
| S21 | **The app cannot know a turn will hit a dangerous command before sending**, so "route gate-able turns via runs" in practice means **the whole remote transport migrates**. | Reasoned in the #251 entry, `OPEN_ITEMS.md:5735-5741` | **CARRIED** → §2.1 (scope) |

### 1.3 Recovery / the runs plane's shape

| # | Finding | Evidence | Disposition |
|---|---|---|---|
| S22 | **Runs are pollable by id** (`GET /v1/runs/{run_id}`) — "a strictly more robust recovery shape than SSE reconcile; the #235/#246 machinery would get simpler, not hairier." | CODE-READ 2026-08-05; `OPEN_ITEMS.md:5737-5741` | **CARRIED, with a sharpening** → N2 below. True for the *final answer*; false for stream replay. |
| S23 | **`/v1/runs/{id}/stop` is a REAL stop** — it reads the retained agent and calls `request_hard_interrupt`. An unknown id returns 404 `run_not_found` **on the live 0.20.0 process**, which is what proved the registry exists on the running build and not just in the clone. | PROVEN 2026-08-06 (report H §2); CODE-READ `api_server.py:6860-6880` | **CARRIED** → §2.5 (interrupt-and-resend is the mid-prose fallback) |
| S24 | **The Sessions chat lane has NO real stop.** On client disconnect the handler cancels only the asyncio wrapper; the worker thread runs `run_conversation` to completion. | CODE-READ, report F §2.6; `api_server.py:3836-3837` vs `:6860` | **CARRIED** → §5. This is the cost item nobody has priced: today's Stop stops the *app listening*, not the host generating. |
| S25 | **`api_server` hard-sets `supports_async_delivery = False`** — async delivery refuses API clients; `kanban_watchers` skips the send; wake-by-push, `notify_on_complete`, background `delegate_task` all sit behind it. | CODE-READ, report A §1.1, report C §3; `api_server.py:1361`; `base.py:2690` | **DROPPED from Phase 3.** Flipping it means making our adapter a real delivery target — a separate lane, entangled with the P1 doorbell decision and #238. Recorded, not built. |
| S26 | **`deliver="origin"` cron on api_server FIRES, BURNS A FULL AGENT TURN, and NEVER DELIVERS** — and `PLATFORM_HINTS["api_server"]` carries no warning about it (cli/tui do). | CODE-READ, report C §2.2; `cron/scheduler.py:1147-1152`; `agent/prompt_builder.py:929-941` | **TRACKER-NOTE-NEEDED → #251** (it is a live money leak on Owen's own boxes, independent of Phase 3). Note: *"Check Owen's cron configs for `deliver: origin` jobs created via the API — each fire burns a turn and delivers nothing (report C §2.2). Unrelated to Phase 3; cheap to audit."* |
| S27 | **If we ever register our adapter as a delivery target, set `splits_long_messages = True`** or the 4000-char delivery cap starts clipping replies that arrive intact today. | CODE-READ, report C §22 must-not-lose list | **CARRIED as a guardrail** → §4.4. Not triggered by this migration (we are not becoming a delivery target), but one line away if slice 3E ever grows. |
| S28 | **Must-not-lose list for any plane move:** token-level SSE + the separate reasoning channel, session history + fork, model pinning. | Report C §22 | **CARRIED** → §2.1's "what stays", and N3/N4 are the two places it is at risk. |
| S29 | **`X-Hermes-Session-Key` is client-supplied, documented as sharing the gateway's `session_key` semantics, and already indexes runner state.** It is the long-term-memory scope, and `/v1/runs` accepts it. | CODE-READ `api_server.py:2046,:2549-2554,:2485`, and `_handle_runs` parses it first thing (`:6301`) | **CARRIED** → §2.1 (memory scope survives the move if we keep sending it) |

### 1.4 tui_gateway (the road not taken)

| # | Finding | Evidence | Disposition |
|---|---|---|---|
| S30 | **18/18 RPC methods live on 0.20.0**, each with the documented validation codes (`session.steer` → 4002 as source-read). | PROVEN 2026-08-06 loopback probe; D dossier §"Registration inventory", `:737` | **CARRIED as a finding**, not as a build. |
| S31 | **No version field anywhere on the wire** — `gateway.ready` advertises `skin` + one capability bit and nothing versionish. Churn risk confirmed. | PROVEN; D dossier `:197`, `:561`, `:727` | **CARRIED** → §6 Q8 (a real argument for not adopting it) |
| S32 | **The ws token is spawn-owned.** Loopback disables the auth-*provider* gate, not the credential check; the sole loopback credential is a per-process `_SESSION_TOKEN` (`secrets.token_urlsafe(32)`) unless `HERMES_DASHBOARD_SESSION_TOKEN` is injected **at spawn**. A client that did not spawn the server cannot discover it. Remote = the full auth-provider path. | PROVEN + CODE-READ; D dossier `:299-300`, `:717-722` | **CARRIED** → §6 Q8. This is what makes tui_gateway a *desktop-app* story, not a phone story. |
| S33 | **`hermes serve` runs its OWN cron ticker** — running it beside `hermes gateway run` puts **two tickers on one `state.db`** (double-fire risk). | PROVEN/CODE-READ; D dossier `:804-805`; `hermes_cli/main.py:10388` | **TRACKER-NOTE-NEEDED → #251** (it constrains slice C, the desktop face, which spawns/uses `serve`). Note: *"HAZARD for the desktop-face slice: `hermes serve` ticks cron itself, so a serve process beside the gateway = two cron tickers on one state.db. Any serve adoption must account for it (D dossier :804-805)."* |
| S34 | **tui_gateway is served by the DASHBOARD app (:9119), not the gateway** — `hermes gateway run` has zero imports of `tui_gateway`. Adopting it = a different process, protocol (JSON-RPC/WS), auth (dashboard token), and session registry, behind a config gate. | CODE-READ, report F §4; `hermes_cli/web_server.py:15844-15857`, `:355` | **DROPPED as the Phase 3 foundation** (S3 makes it unnecessary). Kept as the desktop-face reference. |
| S35 | **One steer substrate, three doors, three registries** — gateway `SessionState.turn.agent`, `APIServerAdapter._active_run_agents`, `tui_gateway.server._sessions[sid]["agent"]`, and *(none)* for Sessions-API chat. | CODE-READ, report F §4 table | **CARRIED** — it is the single cleanest statement of why this migration is a *lane move* and not a feature request. |

### 1.5 Infrastructure findings that constrain this lane

| # | Finding | Evidence | Disposition |
|---|---|---|---|
| S36 | **#263(b) PROVEN and FIXED, deployed live:** the cross-loop wake never woke the parked drain (`Event.set()` from another loop lands in `_ready` without `_write_to_self`), so every phone query rode a full 25s park cycle — 8 for 8 in `agent.log`, deterministic, not a race. After the fix: 0.15s / 0.21s / 0.07s tool waits, `enqueue_to_drain=0.001s`. `_QUERY_TIMEOUT` 25→40s against the 25s hold. | PROVEN 2026-08-06 22:49-50 under Owen's 263-G go; `OPEN_ITEMS.md:4992-5011` | **CARRIED** → §2.3. The transport this migration's steer channel rides is now fast enough to carry an interactive gesture. Before the fix it was not. |
| S37 | **#263(a) FALSIFIED as filed; kept as a WATCH.** The loader replaces only the parent package object, so submodules are cache hits — 8 forced discovery passes held one hub id. But the **early-vs-late binding asymmetry is real**: `tools.py:57-59` re-resolves `HUB` at every call while `platform_adapter.py:21` (import) and `:33-38` (construction) freeze it and `EnvelopeService` holds it for life, and two routes can still split them (manifest-name divergence; submodule eviction on a transient import error). *(The tracker's `tools.py:48-50` / `platform_adapter.py:20,:33` are pre-instrumentation line numbers; these are the post-`fd5d7d1` ones.)* | PROVEN falsification + reproduced split routes; `OPEN_ITEMS.md:4820-4847` | **CARRIED as a design rule** → §2.3: *the runs reach resolves the runner and the adapter LATE, per call, and never caches them at import.* |
| S38 | **#264 — a bounced gateway can come up WITHOUT the chat plane.** api_server loses the `:8642` bind race to the dying process's socket, logs "address already in use" + "api_server failed to connect", and runs headless: healthy PID, plugin connected, cron ticking, **dead chat plane, no retry**. Ops rule: after ANY bounce verify the LISTENER, never the process. | PROVEN live 2026-08-06; `OPEN_ITEMS.md:4700-4719` | **CARRIED** → §2.7 and §4.3 (a runs-plane client's honesty requirement) |
| S39 | **Live-install experiments need an explicit per-experiment go** (standing rule, Owen approved 2026-08-06). The 2026-08-06 blanket clearance **expired with the day**. Read-only probes and throwaway loopback servers are free. | CLAUDE.md standing rule; `OPEN_ITEMS.md:6033-6036` | **CARRIED** → §4.5 and §6 Q6 |
| S40 | **The Mac gateway is launchd-supervised** — `kill` = clean ~20s respawn; `hermes gateway restart` is the polite form; a manual `hermes gateway run` refuses. | PROVEN 2026-08-05/06 | **CARRIED** → §4.5 (deploy mechanics) |
| S41 | **Plugin lifecycle hooks fire on BOTH lanes** (the shared `turn_finalizer`); the gateway `HookRegistry` hooks remain platform-only. So `hooks.outbound` HMAC push works on our chat plane today. | CODE-READ confirmed 2026-08-06; `OPEN_ITEMS.md:6077-6083` | **CARRIED, and it is load-bearing** → §2.8 (this is what rescues artifact content on the runs plane) |
| S42 | **Artifacts + sandboxed preview shipped upstream in v0.20.0** (desktop-only surface) — the preview-panes work was parity, not speculation. No canvas, no HermesHub. | Report G / E; overnight handoff | **CARRIED as context.** Already consumed by #258/#259; noted so the runs plane's artifact regression (N1) reads as a regression against *shipped* behavior. |
| S43 | **Per-turn `model`/`provider` fields on `/chat`** = a working answer to #9's hanging model pin. | Report C / E | **DROPPED from Phase 3** (unrelated quick win). **TRACKER-NOTE-NEEDED → #9.** Note: *"2026-08-07: report C found per-turn `model`/`provider` fields on the chat body — a per-turn selection that sidesteps the hanging `/model` session pin entirely. Cheap lane, independent of Phase 3."* |
| S44 | **Media on our plane is images-only / base64 / ≤5MB**; report A's MEDIA pipeline finding is the likely long-term answer for #21 file downloads. | Report A/C | **CARRIED as an open question** → §6 Q2's probe list (does `/v1/runs` accept our attachment shape at all? N9). |

### 1.6 NEW tonight — code-read findings that change the migration's shape

These were **not** in any handoff. All are CODE-READ against `01a1037d1`; none has been
probed live. They are the reason §2 is not a one-liner.

| # | Finding | Evidence | Disposition |
|---|---|---|---|
| **N1** | **The runs stream drops tool ARGS.** Sessions `/chat/stream` emits `tool.started` with `args` (`api_server.py:3736-3738`); the runs callback emits `{event, run_id, timestamp, tool, preview}` — **no args** (`:6222-6229`). **#21 Tier 1, #258, #262 and #265 all reconstruct agent-written files from `args.content` on `tool.started`** (`SessionsHermesClient.swift:318-320`, `parseWrittenFile` `:1352`). **On the runs plane, artifact chips lose their content.** | CODE-READ | **CARRIED as a blocking design item** → §2.8. Mitigation exists (S41 + N10). **TRACKER-NOTE-NEEDED → #21 and #258.** Note: *"2026-08-07 (Phase 3 scoping): the `/v1/runs` event stream carries no tool `args` (api_server.py:6222-6229) — Tier-1 client-side file reconstruction does not survive the runs migration as-is. The replacement source is a plugin `pre_tool_call` hook, which receives the full args dict on both lanes (hermes_cli/plugins.py:1180, :2170-2179)."* |
| **N2** | **"Poll-recovery" is real for the ANSWER and false for the STREAM.** `/v1/runs/{id}/events` is a single-consumer `asyncio.Queue`, and the handler **pops `_run_streams[run_id]` in its `finally`** (`:6765-6766`); the producer only enqueues while the queue identity still matches (`:6402-6404`). **So a dropped SSE cannot be resumed — reconnect 404s and every subsequent delta is discarded.** What *does* survive is `GET /v1/runs/{id}`: status, `output`, `usage`, `last_event`, retained for `_RUN_STATUS_TTL = 3600s` (`:6187`). | CODE-READ | **CARRIED, and it sharpens S22** → §2.2. Recovery becomes "poll until terminal, take `output`" — genuinely simpler and more durable than today's SSE reconcile (#235/#246), but it is not replay. **TRACKER-NOTE-NEEDED → #235/#246.** Note: *"2026-08-07: on the runs plane, recovery = `GET /v1/runs/{id}` (status + output + usage, 1h TTL, api_server.py:6187). The event stream itself has NO replay — the queue is popped on disconnect (:6765-6766) — so a mid-turn drop loses the deltas but never the final answer. That is the shape the #235/#246 machinery simplifies into, not a superset of it."* |
| **N3** | **The runs taxonomy is a different envelope for the same content.** `message.delta{delta}` · `tool.started{tool,preview}` · `tool.completed{tool,duration,error}` · `reasoning.available{text}` · `subagent.start/complete` · `run.completed{output,usage}` · `run.failed` · `run.cancelled` · `approval.request` · `approval.responded`. `_thinking`, `subagent.tool` and `subagent_progress` are **deliberately not forwarded** ("high-volume UI noise", `:6291-6294`). **The reasoning channel is NOT lost**: both planes' reasoning comes from the same emitter (`agent/conversation_loop.py:5790`, truncated to 500 chars) — the sessions plane re-wraps it as `tool.progress`/`_thinking`, the runs plane passes it as `reasoning.available`. | CODE-READ | **CARRIED** → §2.1. Corrects the intuitive fear that #4.15's reasoning display dies with the move. It is a decoder change, not a capability loss. |
| **N4** | **`/v1/runs` does not read session history from the DB.** `_handle_runs` builds `conversation_history` from the request body or `previous_response_id` (`:6329-6360`), where the chat handlers call `_conversation_history_for_session` (`:3584`, `:3747`). Whether a run carrying an existing `session_id` **writes** its turn back into the SessionDB row that `/api/sessions/{id}/messages` reads is **UNVERIFIED** — `session_id` is passed to `_create_agent` (`:6022`) and `task_id = session_id or run_id`, but nothing in the runs handler touches the DB. | CODE-READ + UNVERIFIED | **CARRIED as slice 3A's first probe** → §3. This single answer decides whether history, `openSession`, fork and the #190 local store survive unchanged, or whether the app must supply history per run. **Do not write code before it is answered.** |
| **N5** | **Approvals are isolated per run by design:** `approval_session_key = run_id`, with a comment saying conversation/memory scopes are explicitly *not* authorization namespaces (`:6371-6375`). | CODE-READ | **CARRIED** → §2.2 (the app maps `run_id` → approval card; two concurrent runs cannot unblock each other) |
| **N6** | **The `approval.request` payload rides the SSE queue only.** A client that dropped the stream sees `status: "waiting_for_approval"` and `last_event: "approval.request"` (`:6483`) — but **not the command being approved**. | CODE-READ | **CARRIED** → §2.2 + §4.1. Approvals therefore need either a live stream or a plugin-side mirror; "poll-only" is not sufficient for the approvals UI. |
| **N7** | **Runs share the global agent admission budget.** `_handle_runs` is `@_admit_api_agent_request` and calls `_concurrency_limited_response()` (`:6297`, `:6307`) — the same `max_concurrent_runs` gate every agent-serving endpoint uses. | CODE-READ | **CARRIED** → §4.4 (a phone on runs + a `talaria_phone_query` share the budget; a low limit becomes user-visible) |
| **N8** | **Subscribing to `/events` has a ~1s race window** — the handler polls for the run's registration 20×0.05s then 404s (`:6729-6731`). | CODE-READ | **CARRIED** → §2.2 (subscribe immediately after the POST; on 404, fall back to status polling rather than failing the turn) |
| **N9** | **Attachment shape on runs is unverified.** `_handle_runs` takes `input` as a string or a message array and extracts `raw_input[-1]["content"]` without flattening multi-part content (`:6318-6320`); only *history* entries get the part-flattening treatment (`:6360-6370`). Our chat body sends attachments through `ChatTurnBody.make(...)` (`SessionsHermesClient.swift:285`). | CODE-READ + UNVERIFIED | **CARRIED** → slice 3A probe list. Images are a shipped feature; a silent regression here would be exactly the #258 "green suite certified a blank pane" shape. |
| **N10** | **The plugin can see tool args on both lanes.** `ctx.register_hook("pre_tool_call", cb)` (`hermes_cli/plugins.py:1180`) invokes with `tool_name`, the full `args` dict, `task_id`, `session_id`, `tool_call_id`, `turn_id` (`:2170-2179`) — and plugin lifecycle hooks fire on both lanes (S41). The plugin already owns a delivery path to the phone (`outbox.append` + `HUB.wake()`, `platform_adapter.py:59-61`). | CODE-READ | **CARRIED** → §2.8. This is the answer to N1, and it is ~30 plugin lines, not a core edit. |

### 1.7 Tracker corrections owed RIGHT NOW (the thing Owen caught)

| # | Where | Current text | Note to add |
|---|---|---|---|
| **T1** | `OPEN_ITEMS.md:3190` (#159) | *"156f (mid-run steering) — PARKED per Owen 2026-07-22 … unreachable from the Sessions API and will stay that way. **Do not design around it.** Revisit only if upstream exposes it independently."* | *"⛔ SUPERSEDED 2026-08-06 — read #267's CORRECTION before citing this. Steering was PROVEN on the wire twice that day (tui `session.steer`; runs plane BANANA→PLUM via `APIServerAdapter._active_run_agents`). The parked verdict is correct **only for the bare Sessions API**, which remains structurally unsteerable (report F). Steering rides the Phase 3 runs migration; 'do not design around it' no longer applies."* |
| **T2** | `OPEN_ITEMS.md:3289` (#158 summary) | *"156f Steering — parked per #159."* | *"156f Steering — parked for the Sessions API only; PROVEN reachable on the runs plane 2026-08-06 (see #267's correction and the Phase 3 plan)."* |
| **T3** | #224 | (no runs-plane approval mechanism recorded in the entry itself) | S15's note above. |
| **T4** | #235 / #246 | recovery described purely in SSE-reconcile terms | N2's note above. |
| **T5** | #21 / #258 | Tier-1 reconstruction assumed to be plane-independent | N1's note above. |
| **T6** | #251 | Phase 3 described as "chat/stream → /v1/runs, taxonomy largely carries over" | *"2026-08-07 scoping correction: the taxonomy does NOT carry over unchanged — runs `tool.started` has no `args` (N1) and the stream has no replay (N2). Both have answers (plugin `pre_tool_call` mirror; status polling), but they are work, not a rename."* Plus S26 and S33's notes. |
| **T7** | #263 | (a) WATCH recorded | *"The late-vs-early binding lesson becomes a standing design rule for Phase 3: any reach into gateway internals (runner weakref → adapter → `_active_run_agents`) resolves LATE, per call. Never cache the runner or the adapter at import."* |
| **T8** | #264 | ops rule recorded | *"Phase 3 consequence: a runs-plane chat client and the plugin's steer/approval reach share ONE point of failure — the `:8642` listener. Under the headless-gateway state both die together while the process looks healthy, so the app's honesty story must cover it (Phase 3 plan §4.3)."* |
| **T9** | #9 | — | S43's note above. |
| **T10** | #267 | correction already landed | *"Composition rule for the lane: steer and queue are ONE composer behavior — steer while a tool is in flight, queue for the prose phase where steer is silently dropped. The UI never says 'sent'; it says which of the two happened."* |

**Recommendation:** these land as **one docs commit, no code**, before slice 3A opens. I have
not committed anything.

---

## 2. THE MIGRATION DESIGN

### 2.1 What moves, what stays

**Moves — the remote TURN transport only:**

| today | after |
|---|---|
| `POST /api/sessions/{id}/chat/stream` (SSE, `SessionsHermesClient.streamTurn`, `:264`) | `POST /v1/runs` (202 + `run_id`) → `GET /v1/runs/{id}/events` (SSE) → `GET /v1/runs/{id}` (status poll, recovery + terminal truth) |
| `POST /api/sessions/{id}/chat` (sync, `:179`) | `POST /v1/runs` + poll to terminal (no separate sync path needed) |
| stop = drop the stream (cosmetic, S24) | `POST /v1/runs/{id}/stop` — a real hard interrupt (S23) |
| approvals: none (S14, S15) | `approval.request` event → card → `POST /v1/runs/{id}/approval` (S13) |
| steering: impossible (S7) | plugin `steer` event on the existing talaria webhook (S2, §2.3) |

**Stays, deliberately:**
- **Session lifecycle and history** — `POST /api/sessions`, `GET /api/sessions/{id}/messages`,
  `fork`, `POST /api/sessions/{id}/model`. The app keeps creating a session and passes its id
  as `/v1/runs`'s `session_id`. **Conditional on N4** — if runs do not persist into SessionDB,
  the app supplies `conversation_history` per run and the server-side transcript becomes
  advisory. That branch is a materially bigger slice; it is why N4 is probe #1.
- **`X-Hermes-Session-Key`** — keep sending it (S29), or long-term memory scope silently changes.
- **The local brain** — untouched. Phase 3 is remote-only.
- **The plugin transport** (pair/drain/ack/query_result/unpair, `envelope.py:101-107`) — untouched;
  it gains event types, it loses nothing.
- **Sensors / relay / connector** — untouched here. Phase 4 is their decommission and this
  migration is one of its preconditions (#223, #251).

**Decoder work (N3):** `assistant.delta`→`message.delta`, `assistant.completed`/`run.completed`
→ `run.completed{output,usage}`, `tool.progress[_thinking]`→`reasoning.available`,
`tool_name`→`tool`. Mechanical, and all of it is unit-testable offline against captured frames.

### 2.2 How approvals ride it

1. App submits the turn; subscribes to `/events` **immediately** (N8's 1s window).
2. Host gates a dangerous command → run status flips `waiting_for_approval`, `approval.request`
   lands on the stream with the (credential-redacted, `:6470-6478`) command and the choice set.
3. App renders the approval card — this is the same surface family as the on-device
   `ToolConfirmationCenter`, **but a different actor**: this one is the *host's* action, not the
   phone's. The copy must say so.
4. `POST /v1/runs/{id}/approval {"choice": once|session|always|deny}` → `resolved: n` → the run
   resumes and emits `approval.responded`.
5. **Failure modes that must be designed, not discovered:** the window closes
   (`approval_not_pending`, 409 → the card becomes "expired, the host denied it"); the stream
   dropped before the request arrived (**N6** — status says `waiting_for_approval` but the app
   has no command text; the honest UI is "the host is waiting on an approval — reconnect or
   deny"); `approvals.timeout` too short (S17 → §6 Q5).

**Recovery, precisely (N2 + S22):** on any stream loss, poll `GET /v1/runs/{id}` until the
status is terminal; `output` + `usage` are on the status object for an hour. This *replaces*
the #235/#246 reconcile shape rather than extending it — and it removes the zombie-stream class
entirely, because the run's own status is authoritative and does not depend on our connection
surviving.

### 2.3 How the plugin bundles the reach

The reach is **one new event type on the route that already exists and already authenticates**:
`POST /api/platforms/talaria/events`, verified by the adapter's own `verify_http_event_request`
→ `EnvelopeService.verify` (`envelope.py:66-75`), with per-payload device authorization binding
the device token to the claimed `device_id` (`:84-94`). New handlers slot into the dispatch map
at `envelope.py:101-107` beside `pair`/`drain`/`ack`/`query_result`/`unpair`.

```
phone ──POST /api/platforms/talaria/events {"type":"steer","run_id":…,"text":…,"auth":<device token>}
         │  (same listener, same auth, same fail-closed 401 path)
         ▼
   EnvelopeService._steer
         │  resolve LATE, per call  ← #263's lesson (S37)
         ▼
   gateway.run._gateway_runner_ref()  →  runner.adapters[Platform.API_SERVER]
         →  ._active_run_agents[run_id]  →  .steer(text)
```

**Four rules this handler must obey, each earned:**
1. **Resolve late, every call.** Never cache the runner or the adapter at import — that is
   exactly the early-binder shape #263(a) is watching for (S37).
2. **Fail LOUD.** `agent_found: false` (a rename, a finished run, a wrong id) returns an explicit
   negative the app renders. S6's silent-degradation risk is the whole reason.
3. **Never claim "applied."** The honest return is `{steer_accepted: bool, agent_found: bool}` —
   and even `steer_accepted: true` means *stashed*, not *landed* (S4).
4. **Device-scoped auth only.** A steer is a write into someone's live turn; it takes the device
   token, never the bare API key.

Optional companions on the same seam, same slice: `run_stop` (or just call
`POST /v1/runs/{id}/stop` directly — it is a first-class authenticated route, so the plugin is
not needed for stop) and the `artifact` mirror of §2.8.

### 2.4 How steering rides it

Slice 3C = the handler above + the app-side gate below + a client-side test pinning S4. **No
host config precondition** — S5 killed the `busy_input_mode` worry.

### 2.5 Where the steer-constraint gating lives (app-side, and it is the crux)

**The rule: the app offers Steer only when a tool is running or expected, and NEVER treats a
positive reply as applied.**

Concretely, the app already knows this from the stream it is decoding:
- `tool.started` seen with no matching `tool.completed` → **a tool is in flight** → Steer is live.
- Between `run.started` and the first delta with tools historically likely for this turn →
  "expected", weaker; treat as live but label it.
- After `tool.completed` with prose flowing and no new `tool.started` → **the prose phase** →
  Steer is **disabled**, and the composer offers the other two doors instead:
  - **Queue it** (#267 — it becomes the next turn's message), or
  - **Interrupt and resend** (`POST /v1/runs/{id}/stop`, S23 — a real stop, now that we are on
    the runs plane).

**What the UI must never do:** show "sent" on the strength of an ACK. S4's false-positive
`{"status":"queued"}` is precisely the failure that makes a steer button feel broken at the
moment the user most wants it. The bar for slice 3C is a test that a steer fired during the
prose phase renders as *not applied* — not as success.

### 2.6 How #267's queue composes with steer — ONE composer behavior

| turn state | send does | UI says |
|---|---|---|
| tool in flight | plugin `steer` → injected at the next tool-result boundary | "steering this turn" |
| prose phase | app-held queue, fires on `run.completed` | "queued — sends when this turn ends" |
| stream lost, run still live | queue (the run is unreachable for steering anyway) | "queued" |
| user chooses Interrupt | `/stop` then send as a fresh turn | "stopped — sending as a new message" |

The composer never asks the user to understand tool-result boundaries. It picks the door and
**names which one it used**, which is the #180 visible-degradation rule applied to a new surface.
This is why #267 should be built *inside* slice 3C rather than before it: the two share one state
machine, and building the queue alone means building half of it twice.

### 2.7 #264 interaction — a runs-plane client must survive the headless gateway honestly

Under S38's failure the gateway process is healthy, the plugin adapter is registered, cron ticks
— and `:8642` is not listening. **A runs-plane client is affected exactly as much as today's
client, and so is the plugin steer channel, because they share that listener.** What changes is
that the app now has *two* things that can be dark, so the honesty story must be one story:

- Connection refused / timeout on `POST /v1/runs` → the existing unreachable state
  (`isUnreachableError`, `SessionsHermesClient.swift:1205`), unchanged.
- **New requirement:** the Server screen must not show PLUGIN LINK as PAIRED-and-healthy while
  chat is refusing. Both facts come through the same door; one banner, one truth.
- The ops rule (verify the LISTENER, not the PID) belongs in the runbook that ships with slice 3D
  of #251 (OJAMD rollout), not in the app.

### 2.8 Artifacts on the runs plane (N1 — the one real regression, with a real answer)

The runs stream carries no tool `args`, so #21 Tier 1 / #258 / #262 / #265 lose their content
source. Three options:

- **(a) Plugin `pre_tool_call` mirror — recommended.** The plugin registers a hook (N10), sees
  `write_file`'s full args on any lane, and pushes `{path, content}` to the phone over the outbox
  it already owns. ~30 plugin lines, no core edit, survives `curl install.sh | bash`, and it also
  works for the desktop face later. Costs: a live-install deploy (§4.5), and the content now
  arrives on a *different* channel than the turn, so the app must correlate by `session_id`/
  `turn_id` (both are in the hook payload).
- **(b) Accept the loss on remote turns** — chips announce a path, no inline content. Honest, but
  it undoes work Owen device-verified 12 hours ago (258-E MET).
- **(c) Keep artifact-bearing turns on the sessions plane** — rejected: S21 says we cannot know in
  advance which turns those are, and a permanent dual path is the #218 shape (two paths, one
  tested).

---

## 3. SLICES

**Naming, reconciled:** the evening handoff's **B / C / D are #251 PHASE-2 slices**
(conversational installer, desktop face, OJAMD rollout) — a different sequence that continues
after 2A. Phase 3's slices are numbered **3A–3E** here to avoid a collision. Nothing is renumbered.

| slice | what | size | depends on | unblocks |
|---|---|---|---|---|
| **3A** | **Runs transport parity.** Probe N4/N9 first, then a runs client behind a Developer switch: submit, subscribe, decode (N3), status-poll recovery (N2), real stop (S23). Sessions path stays intact and default until 3A's device leg passes. | **L** | nothing | everything below |
| **3B** | **Approvals over runs.** `approval.request` card, `POST …/approval`, expiry + dropped-stream states (N6), humane `approvals.timeout` (S17). | **M** | 3A | the #224 §F7d dead turn; MCP elicitation (S19) |
| **3C** | **Steering + queuing, one composer.** Plugin `steer` handler (§2.3), app-side gate (§2.5), #267's queue (§2.6), never-trust-queued pin. | **M** | 3A + a plugin deploy | Owen's #1 want |
| **3D** | **Artifact mirror.** Plugin `pre_tool_call` hook → outbox → app correlation (§2.8(a)). | **S–M** | 3A + a plugin deploy | keeps #258/#262/#265 alive after the move |
| **3E** | **Cutover + simplification.** Runs becomes the default remote path; the SSE-reconcile machinery (#235/#246) collapses into status polling; sessions plane keeps only history/fork/model-pin. | **M** | 3A–3D green on device | #251 Phase 4 (relay decommission), #223 |

**Independently shippable first: 3A**, and it is shippable *without any of the others* — it is a
transport swap behind a switch that already buys a **real stop** (S23/S24) and **durable answer
recovery** (N2) on its own. Ship it, live on it a week, then decide 3B/3C ordering.

**Bars sketch (pre-registered here per the #215 convention; refine in the OPEN_ITEMS entry before
any code):**

- **3A-0 (probe, blocking):** N4 answered — does a `/v1/runs` call carrying an existing
  `session_id` write its turn into the row `/api/sessions/{id}/messages` reads? And N9 — does our
  attachment body survive `_handle_runs`'s input extraction? Read-only probes; no live-install go
  needed. **No code before both answers are written down.**
- **3A-A (decode, unit):** captured runs frames decode to the same `StreamingUpdate` sequence the
  sessions frames produce for an equivalent turn — including reasoning (N3) and usage.
- **3A-B (recovery, unit + integration):** a turn whose `/events` stream is killed mid-flight
  still delivers the final answer via status polling, exactly once, with usage — the #237
  duplicate shape explicitly pinned absent.
- **3A-C (stop, device):** Stop on a long tool actually stops host-side work (contrast: today's
  Stop leaves the worker running, S24). Evidence = the host's own log, not the app's UI.
- **3A-D (artifacts, honesty):** with 3D not yet built, an agent-written file on the runs plane
  renders a chip with **no fabricated content** — absence is honest, invention is a bar failure.
- **3A-E (gate):** `scripts/mac/lane-gate.sh` PASS, units **and** Release, unit count MOVED.
- **3A-F (device, Owen):** one real remote conversation end-to-end on the runs path, including a
  tool-using turn and a stream killed by backgrounding the app.
- **3B-A/B:** approval card round-trip (`once` and `deny` arms) with a verbatim host-side log;
  expiry arm renders honestly (409 `approval_not_pending`).
- **3C-A:** steer during a tool → the turn's output changes (the BANANA→PLUM shape, from the
  phone). **3C-B:** steer attempted during prose → the UI reports **not applied** (the S4 pin).
  **3C-C:** queue fires exactly once at `run.completed`, survives backgrounding, and is
  cancellable before it fires.
- **3D-A:** artifact content arrives over the plugin channel and correlates to the right turn; a
  mismatched/late arrival is dropped rather than attached to the wrong message.

---

## 4. RISKS

### 4.1 The migration's own risks
- **N4 unanswered is the big one.** If runs do not persist into SessionDB, slice 3A grows a
  history-supply mechanism and the app's server-side transcript story changes. This is the single
  largest sizing uncertainty in the plan, and it costs one read-only probe to remove.
- **N1's artifact regression** against work device-verified 12 hours ago. Mitigated by 3D, but 3A
  ships in the gap — hence bar 3A-D (honest absence, never invention).
- **N6:** approvals are not fully poll-recoverable. An approval that arrives while the app is
  backgrounded is visible as a *state* but not as a *question*.

### 4.2 #263 (a)-WATCH, for a runs-plane client specifically
(a) is falsified as filed but alive as a shape (S37): early binders and late binders can diverge
under manifest-name divergence or submodule eviction. **The runs reach is a new early-binder
temptation** — it is one `self._adapter = ...` away from the same class of bug, and its failure
mode is *silent* (S6: an unfound agent looks exactly like a steer that did not land). Therefore:
resolve late per call (§2.3 rule 1), stamp `id()` of the runner and adapter on the steer path the
way #263-E stamped the hub, and make `agent_found:false` a visible app state (§2.3 rules 2–3).
The counters #263 left in place are the precedent; reuse the pattern rather than inventing one.

### 4.3 The shared point of failure (#264)
A runs-plane client does not add a failure mode, but it concentrates one: chat, approvals,
steering and the phone-query transport now all depend on the `:8642` listener. Under the headless
state everything looks healthy and nothing answers. **App-side requirement:** one truth, one
banner (§2.7). **Ops-side:** the listener check is the runbook's first line.

### 4.4 Capacity and clipping
- **N7:** runs share `max_concurrent_runs` with every agent-serving endpoint. A phone that both
  chats and fires `talaria_phone_query` competes with itself. Worth reading the configured value
  on both hosts before 3A's device leg.
- **S27:** we are *not* becoming a delivery target in this migration, so the 4000-char cap does
  not bite — but slice 3E must not quietly cross that line without setting
  `splits_long_messages`.

### 4.5 Live-install constraints
Slices **3C and 3D require deploying plugin code and bouncing the gateway** — live-install
experiments under the standing rule (S39), needing Owen's **per-experiment go**; the 2026-08-06
blanket clearance expired. Mechanics: the Mac gateway is launchd-supervised, `kill` = clean ~20s
respawn (S40), and **after any bounce verify the LISTENER, not the PID** (S38). Slices 3A and 3B
need **no** live-install change — they are pure client work against routes that already exist.
That is another reason 3A ships first.

### 4.6 The failure mode of NOT migrating — what staying Sessions-only costs
Stated plainly, because "it works today" hides all of it:

1. **Host approvals are a dead turn.** Under host `manual`, the agent says it is asking for
   approval and then nothing happens; the command is blocked and queued for a `/approve` our
   plane cannot reach (S15). Owen currently runs `off`, which is why this has not bitten — it is
   one config flip from biting, and `off` is the setting that lets a deletion-shaped `del`
   execute ungated (S13's OJAMD arm).
2. **Stop is cosmetic.** The user's Stop stops the app listening; the host keeps generating and
   keeps spending (S24). This is a live cost on every long turn, today.
3. **Steering is structurally impossible** on this lane, forever, without upstream work Owen has
   ruled out (S7, S12). Owen's #1 want stays undeliverable.
4. **Every MCP elicitation auto-declines silently** (S19) — it looks like a tool that does not work.
5. **Recovery stays hard.** The #235 → #237 → #246 chain is three defects deep in one mechanism
   that exists only because the answer is not durably fetchable. On runs it is (N2, 1h TTL).
6. **#251 Phase 4 and #223 stay stalled** on the interactive story, which is what the whole plugin
   venture exists to deliver.

---

## 5. QUESTIONS FOR OWEN

Each has a recommendation. "Approved" means all of them as recommended.

1. **Do the tracker notes (§1.7, T1–T10) land now, as one docs commit with no code?**
   *Recommendation:* **Yes, first thing.** T1 and T2 are actively misleading — they tell the next
   session not to design around a thing we proved works. Everything else in §1.7 is a one-line
   note against an existing entry.

2. **Open Phase 3 now, or finish #251's Phase-2 slices (B installer / C desktop face / D OJAMD)
   first?**
   *Recommendation:* **Phase 3, slice 3A only, next.** B/C/D are distribution work whose shape
   depends on what the transport ends up being; doing them first risks building an installer and
   a desktop pane around a lane we are about to change. **Honest counter-argument:** slice D
   (OJAMD rollout) is what makes your daily driver benefit from 2A at all, and it is small. If you
   want one thing done before Phase 3, make it D.

3. **Scope: wholesale migration, or a permanent dual path?**
   *Recommendation:* **Dual path only during 3A (behind a Developer switch), then wholesale at
   3E.** A permanent dual path doubles the surface and guarantees the untested-branch shape that
   cost us two days in #218. S21 already says we cannot route per-turn intelligently anyway.

4. **Artifacts on the runs plane (§2.8): plugin mirror (a), accept the loss (b), or keep artifact
   turns on sessions (c)?**
   *Recommendation:* **(a), the plugin `pre_tool_call` mirror**, built as slice 3D. It is small,
   core-edit-free, and it is the same mechanism the desktop face would want later. It needs a
   live-install go.

5. **`approvals.timeout` — set it humane (~300s) on both hosts when 3B ships?**
   *Recommendation:* **Yes, 300s.** Observed 60s on the Mac is far too short for a phone in a
   pocket, and timeout=deny is the safe failure. This is a config edit on your boxes, so it is
   yours to make.

6. **Live-install authorization for slices 3C/3D: a standing per-slice go, or per-deploy?**
   *Recommendation:* **Per-slice, named in the OPEN_ITEMS entry** ("3C is approved, including the
   plugin deploys and gateway bounces it needs"). That respects the standing rule's intent — an
   explicit, scoped authorization rather than an assumed one — without a fresh ask for every
   iteration inside a slice. **This one is genuinely yours: the rule exists because a probe once
   assumed it.**

7. **#267 queuing — build it inside 3C, or ship it standalone first (it needs nothing from the
   host)?**
   *Recommendation:* **Inside 3C.** Standalone is tempting because it has no host dependency, but
   §2.6 shows steer and queue are one state machine; shipping the queue alone means designing the
   composer twice and risks the "sent" wording we would then have to unlearn.

8. **tui_gateway: formally drop it from the roadmap, or keep it as a someday row?**
   *Recommendation:* **Drop it from the phone's roadmap; keep the D dossier as the desktop-face
   reference.** The token is spawn-owned so a remote phone cannot authenticate without standing up
   an auth provider (S32), it is a second process on a different port with different auth (S34),
   it has no version field on the wire (S31), and Escape B gets us the same steer substrate with
   none of that (S2). If you want it kept alive as an option, say so and it stays a row.

9. **Anything in §1 you disagree with the disposition on?** Especially the **DROPPED** rows (S8,
   S9, S12, S18, S25, S34) — dropped here means "not built in Phase 3," never "refuted," and each
   one stays in the record.

---

**What I need from you:** "approved", or the numbers you would flip. No code, no plugin deploy,
and no gateway bounce happens before you answer.
