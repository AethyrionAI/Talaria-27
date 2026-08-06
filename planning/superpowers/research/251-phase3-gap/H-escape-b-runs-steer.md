# H — ESCAPE B verified: a plugin CAN steer a live `/v1/runs` agent

**Question:** report F §5.3 claimed the `/v1/runs` lane retains a live `AIAgent` per run, so
in-process plugin code could steer it with zero Hermes-core edits — even though no HTTP route
exposes steering. **Confirm or refute.**

**Verdict: `PLUGIN-CAN-STEER-RUNS` — CONFIRMED, on the wire, on the live Mac Mini gateway.**
Two runs, same prompt, same build, same model. Control answered `BANANA`. The steered run
answered `PLUM`. The only difference was one in-process `agent.steer(text)` call fired from
plugin code 9 seconds into the run.

**Method:** code-read of the read-only clone at `01a1037d1`
(`…/scratchpad/hermes-agent-ro`), then two live runs against the Mac Mini gateway
(`127.0.0.1:8642`, PID 74582 → 80999 → 81552, `/health` reports `0.20.0`, install at
`~/.hermes/hermes-agent` is the same commit `01a1037d1`). Model: default `kimi-k3`
(`~/.hermes/config.yaml:1-4`). Date: 2026-08-06. Total spend: 2 runs, ~124k tokens.

---

## 1. Code-read — where the agent lives, and whether arbitrary in-process code can reach it

### 1.1 The store, its key, and its lifetime

| fact | answer | citation |
|---|---|---|
| **owning object** | `APIServerAdapter` — an *instance attribute*, not closure-local | `gateway/platforms/api_server.py:1345` (class), `:1368` (`__init__`), `:1422` (`self._active_run_agents: Dict[str, Any] = {}`) |
| **key** | **`run_id`** — not `session_key`, not `session_id` | `gateway/platforms/api_server.py:6462` |
| **written** | immediately after `_create_agent()` returns, inside the `_run_and_close()` asyncio task | `:6435` (task def), `:6451` (`agent = self._create_agent(`), `:6462` (`self._active_run_agents[run_id] = agent`) |
| **lifetime** | until the task's `finally` pops it — i.e. the entire duration of the agent's work | `:6681` (`self._active_run_agents.pop(run_id, None)` in `finally`) |
| **also popped** | by the 60s orphan sweep, but **only when the task is already done** (`task_done` gate) — the sweep cannot yank a live agent | `:6919-6929` |
| **the agent actually runs on a worker thread** | `_run_sync` is handed to `run_in_executor`, so the event loop stays free to serve HTTP *while* the agent works | `:6493` (`def _run_sync()`), `:6562` (`run_in_executor(None, _run_sync)`) |
| **an existing route already uses the reference mid-run** | `POST /v1/runs/{id}/stop` reads the same dict and calls `request_hard_interrupt(agent, …)` | `:6867` (`agent = self._active_run_agents.get(run_id)`), route table `:2025` |

That last row is the structural proof that the window is real and usable from a request
handler: `/stop` is the same shape as a steer, minus the method name.

### 1.2 Reachability from arbitrary in-process code — YES, via a module-level weakref

There are **two** independent, non-monkeypatch paths, and both are attribute walks from a
module global. Neither needs `api_server.py` to cooperate.

**Path 1 — module-level weakref (works from *any* code in the process, no adapter needed):**

```
gateway/run.py:3383   # Module-level weak reference to the active GatewayRunner instance.
gateway/run.py:3384   # Used by tools (e.g. send_message) that need to route through a live
gateway/run.py:3385   # adapter for plugin platforms.  Set in GatewayRunner.__init__().
gateway/run.py:3387   _gateway_runner_ref: _weakref.ref = lambda: None
gateway/run.py:5842           _gateway_runner_ref = _weakref.ref(self)
gateway/run.py:5834           self.adapters: Dict[Platform, BasePlatformAdapter] = {}
```

So: `_gateway_runner_ref()` → `runner.adapters[Platform.API_SERVER]` →
`._active_run_agents[run_id]` → `.steer(text)`. The seam is *documented as intended for
plugin platforms* in its own comment, and `api_server.py` itself already uses it twice
(`:1481-1485` draining check, `:2471-2485` model override).

**Path 2 — the adapter back-reference (available to any plugin platform adapter):**

```
gateway/run.py:13690                    adapter.gateway_runner = self
```

This is in `_create_adapter`'s **plugin-registry branch**, set *unconditionally* for every
plugin-registered platform (the comment says so out loud: "Unconditional: `BasePlatformAdapter`
declares `gateway_runner`, so this reaches ALL platforms"). The Talaria adapter is created
through exactly this branch (`gateway/run.py:13679-13691`; plugin registration at
`~/.hermes/plugins/talaria/__init__.py` → `ctx.register_platform(name="talaria", …)`).
And `Platform.API_SERVER` is a normal key in `runner.adapters` (`gateway/run.py:13737-13742`,
read back at `:7362` and `:21776`).

**So the answer to step 1 is: module-level singleton → instance attribute. Not
closure-local, not a weakref-to-agent, not private-name-mangled.** The only "private" names
in the walk are `_gateway_runner_ref` and `_active_run_agents`, and the first of the two is
already load-bearing public-ish plumbing for plugins.

### 1.3 The steer entry point

Same substrate as the tui plane's proven `session.steer` (D dossier, Arm 4 RE-RUN). It is a
plain thread-safe setter on the agent object — no route, no queue, no adapter:

```
run_agent.py:3225   def steer(self, text: str) -> bool:
run_agent.py:3234       Thread-safe: callable from gateway/CLI/TUI threads. Multiple calls
run_agent.py:3235       before the drain point concatenate with newlines.
```

It stashes text on `agent._pending_steer` under `agent._pending_steer_lock`. Requirements:
a non-empty string, and that's all. The drain is
`apply_pending_steer_to_tool_results(agent, messages, num_tool_msgs)`
(`agent/agent_runtime_helpers.py:3921`), which appends the steer to the **last `role:"tool"`
message** at the end of a tool batch, before the next API call, with a marker
(`format_steer_marker`, `:3964`). If the batch produced no tool result the steer is **put
back** (`:3950-3963`) and requeued as the next turn (`agent/turn_finalizer.py:683`).

**Carried limit, unchanged from F:** a steer only lands mid-turn if the turn runs at least
one more tool. This is not a `/v1/runs` property — it is the substrate's property, identical
on the tui plane.

### 1.4 Correction to report F

F cited the registry's owner as `HermesAPIServer`. **There is no such class in
`api_server.py`.** The owner is `APIServerAdapter` (`gateway/platforms/api_server.py:1345`).
The line numbers F gave (`:1422`, `:6462`, `:6867`) are all **correct**; only the class name
was wrong. Verified live: the probe reported `"api_adapter": "APIServerAdapter"`.

---

## 2. Live arm A (control) — the steerable window is real and ~20s wide

`POST /v1/runs` → `run_9ac6b5c6…`, `{"status": "started"}`, HTTP 202.

Prompt (identical in both arms):

> Step 1: use your terminal tool to run this exact shell command: `sleep 20 && echo PHASE1OK`
> Step 2: after that command finishes, reply with exactly one word and nothing else: BANANA
> Do not explain. Do not run any other command.

Polled `GET /v1/runs/{id}`:

| t | status | last_event |
|---|---|---|
| 5s | running | `tool.started` |
| 10s | running | `tool.started` |
| 15s | running | `tool.started` |
| 20s | running | `tool.completed` |
| 25s | **completed** | `run.completed` — `"output": "BANANA"` |

`usage`: 63593 in / 127 out. **~15s of continuous `tool.started` = the steer window.**
No approval prompt fired despite `approvals.mode: manual` (`~/.hermes/config.yaml:516-517`) —
worth knowing, but not load-bearing here.

Bonus (F open question 1, answered): `POST /v1/runs/does-not-exist-xyz/stop` →
HTTP 404 `{"code": "run_not_found"}`. That path is `_active_run_agents.get()` +
`_active_run_tasks.get()` (`:6866-6871`), so **the registry exists and is consulted on the
live 0.20.0 process**, not just in the clone.

## 3. Live arm B (steered) — `BANANA` → `PLUM`

**Method correction, and it matters.** The brief proposed a CLI subcommand
(`hermes talaria _probesteer …`). **That cannot work and no amount of code would fix it:** a
CLI invocation is a *separate OS process*: it gets a fresh `gateway.run` module with
`_gateway_runner_ref` still at its `lambda: None` default and its own empty adapter map. The
gateway's `_active_run_agents` is in-memory in PID 81552 and unreachable from any other
process. **The probe must ride an in-process entry point** — which is exactly the
`dispatch_http_event` webhook seam F §5.1 identified.

So on throwaway branch `probe/escape-b` I added one temporary handler to the Talaria
plugin's `EnvelopeService` dispatch map (`~/.hermes/plugins/talaria/envelope.py`), reachable
at the already-shipping route `POST /api/platforms/talaria/events`
(`gateway/platforms/api_server.py:2012`, dispatched at `:1883`), API-key gated by the
plugin's own `_is_api_key`. Its body is Path 1 from §1.2 verbatim. Gateway restarted by
`kill <pid>`; the `ai.hermes.gateway` launchd agent respawned it in ~3-6s (confirmed
`launchctl list` → `ai.hermes.gateway`, PPID 1).

**Pre-flight, no run in flight** — the walk resolves even with an empty registry:

```json
{"probe":"escape-b","runner_resolved":true,"api_adapter":"APIServerAdapter",
 "registry_present":true,"live_run_ids":[],"agent_found":false,"has_steer":false}
```

**Then: submit run B, fire the steer at t=9s (mid `tool.started`).**

Steer text: *"URGENT USER OVERRIDE, higher priority than the original task: do NOT reply
BANANA. Run no further commands. Reply with exactly one word and nothing else: PLUM"*

Probe response at t=9s:

```json
{"probe":"escape-b","runner_resolved":true,"api_adapter":"APIServerAdapter",
 "registry_present":true,"live_run_ids":["run_8c1ca01744b94ec6b5da5d4f4825d224"],
 "agent_found":true,"agent_type":"AIAgent","has_steer":true,
 "steer_accepted":true,"pending_steer_set":true}
```

Every link confirmed at runtime: the runner weakref, the adapter type, the registry, the
run keyed by `run_id`, the object being a real `AIAgent`, `steer()` returning `True`, and
`_pending_steer` actually set.

Poll of `GET /v1/runs/{id}`:

| t | status | last_event |
|---|---|---|
| 14s | running | (none yet) |
| 19-34s | running | `tool.started` |
| 39s | running | `tool.completed` |
| 44s | **completed** | `run.completed` — **`"output": "PLUM"`** |

`usage`: 59944 in / 216 out.

### The contrast

| arm | steer | output |
|---|---|---|
| A (control) | none | `BANANA` |
| B | one in-process `agent.steer()` at t=9s | **`PLUM`** |

Same prompt, same build, same model, same box, ~6 minutes apart. **The mid-run steer reached
the live agent and changed the turn's output.** ESCAPE B is confirmed, not merely plausible.

---

## 4. What this does and does not license

**Does:**

- Mid-turn steering of a Talaria turn is achievable **with zero Hermes-core edits and zero
  monkeypatching** — the only names touched are `_gateway_runner_ref` (documented as the
  plugin routing seam) and `_active_run_agents` (a plain instance attribute already read by
  a shipping route). This is materially cheaper than F §5.2's `_create_agent` monkeypatch and
  vastly cheaper than the tui_gateway move (different process, protocol, auth, registry —
  F §4).
- It survives `curl install.sh | bash`: everything lives in `~/.hermes/plugins/talaria`.
- The `/v1/runs` lane also already has **stop** (`POST /v1/runs/{id}/stop`) and **approval**
  (`POST /v1/runs/{id}/approval`) as real routes. The Sessions-API chat lane has neither
  (F §2.6). So moving chat to `/v1/runs` buys steer + stop + approval together.

**Does not:**

- Make the **Sessions-API chat lane** steerable. F's structural NO stands unchanged — nothing
  publishes that lane's agent. Escape B is a reason to *move lanes*, not a fix for the
  current lane.
- Escape the substrate's limit: **the steer lands only if the turn runs another tool**
  (`agent/agent_runtime_helpers.py:3950-3963`). Arm B worked because the prompt guaranteed a
  tool batch was in flight. A toolless answer turn will requeue the steer as a next turn.
  Any Phase 3 UX must be designed around that, not around a hoped-for interrupt.
- Erase the transport cost: `/v1/runs` emits `message.delta` / `tool.*` / `run.completed`,
  **not** the `assistant.delta` / `assistant.completed` SSE taxonomy Talaria consumes today
  (CLAUDE.md "SSE taxonomy"). That client-side rewrite is the real price of this option.
- Constitute a decision. Standing rule applies: this is a finding, not a build order.

**One honest risk to carry:** `_active_run_agents` is a private attribute with no stability
contract. If a Hermes update renames it, the steer stops landing **silently** — the probe
handler returns `agent_found: false` and the turn just proceeds unsteered. Any production
version of this must surface that failure loudly rather than degrade quietly. That is a
smaller exposure than F §5.2's monkeypatch (which binds to a private *signature*), but it is
not zero.

---

## 5. Cleanup — verified

| step | result |
|---|---|
| `git checkout main` + `git branch -D probe/escape-b` in `~/.hermes/plugins/talaria` | branch deleted, `(was 023316c)` = **no commit was ever made on it** |
| `git restore envelope.py` (the edit was uncommitted and rode the checkout across) | `git status --short` → **empty** |
| `grep -c "_probesteer" envelope.py` | **0** (grep exit 1) |
| `git branch -a` | `* main`, `remotes/origin/main` — **no probe branch, nothing pushed** |
| head | `023316c` — unchanged from session start |
| stale `__pycache__/envelope.cpython-311.pyc` purged | done |
| gateway restarted onto clean code | PID 81552, `Thu Aug 6 10:51:20 2026`, `/health` 200 `0.20.0` |
| **probe verb gone from the live process** | `{"type":"_probesteer",…}` → `{"error":"Unknown event type","code":"unknown_event_type"}` |
| **fail-closed still holds** | `POST /api/platforms/talaria/events` with **no** auth → **HTTP 401** `{"code":"missing_bearer"}` |
| `hermes plugins list` | `talaria │ enabled │ 0.1.0 │ … │ git` |
| scratch file that briefly held the API key | `probe-payload.json` deleted, confirmed absent |

No file in the Talaria-27 app repo was touched. `~/.hermes/config.yaml` and `~/.hermes/.env`
were read only (key length checked, never printed).
