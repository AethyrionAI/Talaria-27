# F — Cross-plane steering probe (code-read arm)

**Question:** can the gateway-plane mid-turn steering machinery reach a turn that is
running on the Sessions API (`POST /api/sessions/{id}/chat/stream`), given that Talaria
also registers a `talaria` platform adapter — **without patching Hermes core**?

**Method:** read-only analysis of the Hermes clone at
`…/scratchpad/hermes-agent-ro`, working tree at `01a1037d1`
(`chore: map contributor email for rille111`). All citations below are
repo-relative paths inside that clone. No live probes were run.

---

## VERDICT: STRUCTURALLY-NO (for the Sessions-API chat lane), with two named escapes

The steering machinery does not fail on Talaria's lane because of key namespacing, thread
boundaries, or adapter identity. It fails for one reason:

> **Nothing ever stores an object reference to the AIAgent that serves a
> `/api/sessions/{id}/chat[/stream]` turn.** The steer/redirect/interrupt substrate is a
> *method call on a live agent instance*. On the Sessions-API lane that instance is a local
> variable inside a closure running on a `run_in_executor` worker thread, and it is
> discarded when the turn ends. There is no registry entry, no weakref, no contextvar, no
> back-reference to reach it from — from plugin code or from anywhere else in the process.

The key namespace *is* bridgeable (§2.3). The process boundary *is not* a problem (the
plugin, the api_server adapter and the agent all live in the one `hermes gateway run`
process, §5.1). The blocker is narrower and harder than any of those: **the registry key is
reachable; the registry value is never written.**

Two escapes exist and are named honestly in §5 — a plugin-side monkeypatch that captures the
agent at construction (real, works in principle, brittle by construction), and the `/v1/runs`
lane, which **does** retain a live agent per run and is therefore steerable in-process today
(this corrects a prior claim). Neither makes the Sessions-API chat lane steerable as shipped.

---

## 1. How platform steering actually works

### 1.1 The trigger: a second inbound message on an adapter that is already busy

`BasePlatformAdapter.handle_message` (`gateway/platforms/base.py:5554`) is the entry point
for every inbound platform message. It computes the routing key itself:

```
gateway/platforms/base.py:5578
        session_key = build_session_key(
            event.source,
            group_sessions_per_user=self.config.extra.get("group_sessions_per_user", True),
            thread_sessions_per_user=self.config.extra.get("thread_sessions_per_user", False),
        )
```

The busy path is gated on the **adapter's own** in-flight dict:

```
gateway/platforms/base.py:5593        if session_key in self._active_sessions:
…
gateway/platforms/base.py:5713                    if await self._busy_session_handler(event, session_key):
```

`_active_sessions` is a per-adapter-instance `Dict[str, asyncio.Event]`
(`gateway/platforms/base.py:2782`), populated only by that adapter's own
`_start_session_processing` (`gateway/platforms/base.py:5391`, `5803-5804`). **An adapter
that has not itself started a turn for that key never enters the busy branch at all** — it
falls through to `_start_session_processing` (`gateway/platforms/base.py:5757`) and starts a
*new* gateway turn.

`_busy_session_handler` is wired by the runner to `_handle_active_session_busy_message` at
three sites, and **plugin adapters get it too** — the wiring is in the generic adapter-setup
path, not a per-platform special case:

```
gateway/run.py:11041            adapter.set_busy_session_handler(self._handle_active_session_busy_message)
gateway/run.py:12413                    adapter.set_busy_session_handler(…)   # reconnect path
gateway/run.py:13355        adapter.set_busy_session_handler(…)               # _configure_profile_adapter
```

### 1.2 What keys the "running turn" registry

`_handle_active_session_busy_message` (`gateway/run.py:8687`) resolves the running agent
from the runner's per-session state map, keyed by the same `session_key` string the adapter
computed:

```
gateway/run.py:8826        _busy_state = self._peek_session_state(session_key)
gateway/run.py:8827        running_agent = _busy_state.turn.agent if _busy_state else None
```

`_peek_session_state` reads `self._sessions: Dict[str, SessionState]`
(`gateway/run.py:5768-5793`); `SessionState.turn.agent` is documented as
*"Running AIAgent instance (or `_AGENT_PENDING_SENTINEL`); None = idle"*
(`gateway/session_state.py:52-63`). The legacy `_running_agents` dict is a live view onto
the same map (`gateway/run.py:5741`).

So the registry is keyed by **session_key**, not chat_id and not adapter identity. The key
format is built by `build_session_key` (`gateway/session.py:1058`) as
`agent:<profile-ns>:<platform>:<chat_type>:<ids…>` — e.g. `agent:main:telegram:dm:12345`
(`gateway/session.py:1038-1055` for the namespace slot).

**The registry has exactly three write sites, all in `gateway/run.py`, all on the
platform-dispatched turn path:**

| line | what | when |
|---|---|---|
| `gateway/run.py:10504` | `_resume_state.turn.agent = _AGENT_PENDING_SENTINEL` | startup session resume |
| `gateway/run.py:15622` | `_claim_state.turn.agent = _AGENT_PENDING_SENTINEL` | `_handle_message` claims the slot before any await |
| `gateway/run.py:24725` | `self._session_state(session_key).turn.agent = agent_holder[0]` | `_run_agent_inner`'s `track_agent()` promotes the sentinel to the real agent |

A repo-wide grep for `turn.agent =` outside `tests/` returns those three lines and one
comment. **`gateway/platforms/api_server.py` contains none of them.**

### 1.3 Where the injected text lands

`_handle_active_session_busy_message` branches on `effective_mode` (from
`display.busy_input_mode`, `gateway/run.py:8223-8232`, default `"interrupt"`):

```
gateway/run.py:8874        if effective_mode == "steer":
…
gateway/run.py:8894                and running_agent is not None
gateway/run.py:8895                and running_agent is not _AGENT_PENDING_SENTINEL
gateway/run.py:8896                and hasattr(running_agent, "steer")
…
gateway/run.py:8900                    steered = bool(running_agent.steer(steer_text))
```

`AIAgent.steer` (`run_agent.py:3225-3259`) is a plain thread-safe setter — it stashes the
text on `agent._pending_steer` under `agent._pending_steer_lock`
(both created in `agent/agent_init.py:798-799`) and returns `True`. Nothing else.
The docstring is explicit: *"Thread-safe: callable from gateway/CLI/TUI threads."*

Drain points (this is the whole mechanism):

- `agent/agent_runtime_helpers.py:3921` `apply_pending_steer_to_tool_results(agent, messages, num_tool_msgs)`
  — appends the steer to the **last `role:"tool"` message's content** with a marker, at the
  end of a tool-call batch, before the next API call. Role alternation is preserved because
  nothing new is inserted. If the batch produced no tool result it **puts the steer back**
  (`agent/agent_runtime_helpers.py:3949-3963`).
- Called from `agent/tool_executor.py:1507`, `:2269`, `:2331`.
- Pre-API-call drain: `agent/conversation_loop.py:1498`.
- Leftover at turn end: `agent/turn_finalizer.py:683` (requeued as the next turn).

Consequence worth carrying into Phase 3: **a steer only lands if the turn runs at least one
more tool.** A toolless answer turn cannot be steered; the text is requeued as a fresh turn.

`redirect()` (`run_agent.py:3260+`) is the harder sibling — it cancels the in-flight model
request, keeps completed work, appends the correction as a real user message and retries;
during tool execution it *degrades to `steer()`*. It is gated on
`agent._supports_active_turn_redirect` (`gateway/run.py:8914`). `interrupt()` clears any
pending steer (`run_agent.py:3215-3223`).

---

## 2. What a Sessions-API streaming turn looks like to that machinery

### 2.1 It is invisible — by design, and the code says so out loud

`_handle_session_chat_stream` (`gateway/platforms/api_server.py:3632`) builds an SSE queue,
spawns `_run_and_signal()` as an asyncio task, and calls `self._run_agent(...)`
(`gateway/platforms/api_server.py:3748`). `_run_agent`
(`gateway/platforms/api_server.py:5957`) hands a closure to a thread-pool worker:

```
gateway/platforms/api_server.py:6020                    agent = self._create_agent(…)
gateway/platforms/api_server.py:6035                    if agent_ref is not None:
gateway/platforms/api_server.py:6036                        agent_ref[0] = agent
…
gateway/platforms/api_server.py:6178            return await loop.run_in_executor(None, _run)
```

`agent` is a local in `_run()`. `agent_ref` is the only escape hatch — and
**neither `_handle_session_chat_stream` nor `_handle_session_chat` passes one.** The only
callers that do are `_handle_chat_completions` (`gateway/platforms/api_server.py:4098-4126`)
and `_handle_responses` (`:5216-5246`), and even there the ref is a request-local list used
solely to call `agent.interrupt()` on SSE disconnect — not a registry.

The only cross-plane bookkeeping the Sessions-API turn does is:

- `_bind_api_server_session(...)` (`gateway/platforms/api_server.py:5925`, called at `:6013`)
  — sets **contextvars** (`platform="api_server"`, `chat_id`, `session_key`, `session_id`,
  `async_delivery=False`). Contextvars, not an object registry, and cleared in `finally`.
- `_publish_turn_process_ownership(agent, task_id)`
  (`gateway/platforms/api_server.py:758`, called at `:6043`) — writes three marker
  *attributes onto the agent* and stores an **int epoch** in a module dict
  (`_TURN_PROCESS_EPOCHS[task_id] = epoch`). No agent reference is stored.

The gateway itself documents the separation:

```
gateway/run.py:7355    def _active_api_run_count(self) -> int:
gateway/run.py:7356        """Count API-server work that is outside ``_running_agents``.
```

…which delegates to `adapter.active_agent_work_count()`
(`gateway/platforms/api_server.py:1460`) — a **counter**
(`_pending_agent_requests + _inflight_agent_runs + live run tasks`), deliberately built
because Sessions-API work is not in the runner's registry.

### 2.2 The api_server touches the runner in exactly two places, and neither writes a turn

Grepping `gateway/platforms/api_server.py` for runner access yields only:

- `gateway/platforms/api_server.py:1481-1485` — `_gateway_is_draining()` (read).
- `gateway/platforms/api_server.py:2471-2485` — `_session_model_override_for()`, which does
  `runner._session_model_overrides.get(session_key)` (read).

That is the whole cross-plane surface. No write to `_sessions`, `_running_agents`,
`_active_session_leases`, or anything turn-shaped.

### 2.3 The key namespace is NOT the blocker — it is already deliberately shared

This is the finding that makes the negative verdict clean rather than hand-wavy.

`X-Hermes-Session-Key` (`_parse_session_key_header`,
`gateway/platforms/api_server.py:2046`) accepts any client-supplied string ≤ 256 chars
(`_MAX_SESSION_HEADER_LEN`, `:2045`), behind API-key auth. It is threaded through
`_run_agent` → `_create_agent` as `gateway_session_key`, and `_create_agent`'s docstring
states the intent explicitly:

```
gateway/platforms/api_server.py:2549-2554
        ``gateway_session_key`` is a stable per-channel identifier supplied
        by the client (via ``X-Hermes-Session-Key``). … this
        key is meant to persist across transcripts so long-term memory
        providers (e.g. Honcho) can scope their per-chat state correctly
        — matching the semantics of the native gateway's ``session_key``.
```

And it is *already used* to index gateway runner state:
`session_key = gateway_session_key or session_id` (`gateway/platforms/api_server.py:2667`)
→ `runner._session_model_overrides.get(session_key)` (`:2485`).

**So Talaria can already make its Sessions-API turns share the gateway's session-key
namespace** — send `X-Hermes-Session-Key: agent:main:talaria:dm:<chat>` and the
platform-plane key and the chat-plane key are the same string. The lookup in
`_handle_active_session_busy_message` (`gateway/run.py:8826`) would find a `SessionState`
under that key. It would find `turn.agent is None`, because §1.2's three write sites never
run for this lane.

### 2.4 What actually happens if the talaria adapter tries it anyway

Two sub-cases, both dead ends, both worth stating because they are the obvious things to try:

**(a) Normal inbound talaria message while a Sessions-API turn is streaming.**
The talaria adapter's `_active_sessions` has no entry (it never started that turn), so
`gateway/platforms/base.py:5593` is False and the busy branch is skipped entirely. The
message starts a *new*, concurrent gateway turn under the talaria session_key.

**(b) Plugin adapter overrides `handle_message` and calls the busy handler directly** with a
forged `session_key` matching the `X-Hermes-Session-Key`. This is legal plugin code and
reaches `gateway/run.py:8826`. `running_agent` is `None` → `can_steer` is False
(`gateway/run.py:8894-8896`) → `effective_mode` falls back to `"queue"`
(`gateway/run.py:8905-8906`) → `self._queue_or_replace_pending_event(session_key, event)`
(`gateway/run.py:8939`). The text lands in a gateway-plane pending-message FIFO that
**nothing will ever drain**, because no gateway turn is running for that key and the drain
runs at gateway turn teardown. Silent loss.

### 2.5 There is no side door to the agent object either

Checked and negative:

- **Plugin tools** — `registry.dispatch` passes only `task_id`, `session_id`, `user_task`
  (`model_tools.py:1426-1438`, `tools/registry.py:759-777`). No agent.
- **Plugin hooks** — `pre_tool_call` receives `tool_name/args/task_id/session_id/
  tool_call_id/turn_id/api_request_id/middleware_trace` (`hermes_cli/plugins.py:2168-2179`).
  No agent. Same shape across the other lifecycle hooks (`run_agent.py:2850`,
  `model_tools.py:1103`, `:1492`).
- **Interrupt signalling** — `tools/interrupt.py` is a set of *thread idents*
  (`tools/interrupt.py:35`) carrying a boolean. It cannot carry text, and the target thread
  id is known only to the code that started the turn.
- **No weak registry** — no `weakref` / `WeakValueDictionary` in
  `gateway/platforms/api_server.py`, `agent/agent_init.py`, or `run_agent.py`.

### 2.6 Bonus structural fact for Phase 3: the Sessions-API chat lane cannot even be *stopped*

`/v1/runs` has `POST /v1/runs/{run_id}/stop` (`gateway/platforms/api_server.py:6860`) which
calls `request_hard_interrupt(agent, …)` on the retained agent. The Sessions-API chat lane
has no equivalent: on client disconnect `_handle_session_chat_stream` does only

```
gateway/platforms/api_server.py:3836        except (asyncio.CancelledError, ConnectionResetError):
gateway/platforms/api_server.py:3837            task.cancel()
```

`task` is the asyncio wrapper awaiting `run_in_executor`. Cancelling it does not stop the
worker thread — `run_conversation` runs to completion regardless. **So today Talaria's chat
lane has no steer, no redirect, and no stop.** That is a bigger gap than steering alone and
should be weighed in the Phase 3 decision.

---

## 3. Minimal honest statement of why it is unbridgeable

> The gateway's mid-turn steer/redirect/interrupt is not a message-routing feature. It is a
> **method call on a live `AIAgent` object** (`run_agent.py:3225`), and every door to it —
> the platform busy path (`gateway/run.py:8900`), the `/steer` slash command
> (`gateway/run.py:14212-14229`), the tui_gateway RPC
> (`tui_gateway/methods_session.py:3070-3074`) — differs only in *how it obtains that object
> reference*. On the Sessions-API lane the reference is a local in a closure on a worker
> thread (`gateway/platforms/api_server.py:6020`, executed at `:6178`) and is never
> published. The three sites that publish a turn's agent into
> `SessionState.turn.agent` (`gateway/run.py:10504`, `:15622`, `:24725`) are all on the
> platform-dispatched path in `gateway/run.py`; `api_server.py` contains none of them.
>
> Session-key scoping is *not* the obstacle — the `X-Hermes-Session-Key` header is
> explicitly documented as sharing the gateway's `session_key` semantics
> (`gateway/platforms/api_server.py:2549-2554`) and is already used to index runner state
> (`:2485`). Thread and event-loop boundaries are *not* the obstacle either — `steer()` is
> documented thread-safe and takes a lock (`run_agent.py:3244-3258`).
>
> The obstacle is object lifetime and publication: **the key is bridgeable, the value is
> never written.**

---

## 4. Bonus: one substrate, three registries, and not all in one process

**One substrate.** All three doors call the same `AIAgent.steer()` →
`agent._pending_steer` → `apply_pending_steer_to_tool_results`. There is no second
implementation.

- gateway platform busy path → `running_agent.steer(steer_text)` — `gateway/run.py:8900`
- `/steer` slash command → `running_agent.steer(steer_text)` — `gateway/run.py:14229`
- tui_gateway `session.steer` RPC → `agent.steer(text)` — `tui_gateway/methods_session.py:3074`
- tui_gateway busy-submit policy → `agent.steer(plain_text)` — `tui_gateway/server.py:7436`
- tui_gateway `/steer` slash → `agent.steer(arg)` — `tui_gateway/methods_tools.py:748`

**Three registries.** They do *not* share a turn registry:

| registry | owner | key | populated by |
|---|---|---|---|
| `GatewayRunner._sessions[key].turn.agent` | `gateway/run.py:5768`, `gateway/session_state.py:63` | `session_key` (`agent:main:<platform>:…`) | `gateway/run.py:10504`, `:15622`, `:24725` |
| `HermesAPIServer._active_run_agents[run_id]` | `gateway/platforms/api_server.py:1422` | `run_id` | `gateway/platforms/api_server.py:6462` (`/v1/runs` only) |
| `tui_gateway.server._sessions[sid]["agent"]` | `tui_gateway/server.py:143` | tui session id | `tui_gateway/server.py:2172`, `:6136` |
| *(none)* | Sessions-API chat | — | **never** |

**And not one process.** `hermes gateway run` (the `:8642` process the phone talks to) has
**zero** imports of `tui_gateway` or `hermes_cli.web_server` anywhere under `gateway/`
(verified by grep). tui_gateway runs either as its own process
(`tui_gateway/entry.py`, stdio JSON-RPC for the Ink TUI) or in-process with the **dashboard**
web server at `:9119`, which mounts it at `/api/ws`
(`hermes_cli/web_server.py:15844-15857`, `from tui_gateway.ws import handle_ws`). Its
`_sessions` is a module-global dict — one per process.

**Phase-3 consequence:** "adopt tui_gateway" is not a route change on `:8642`. It is moving
Talaria's chat onto a **different process, different protocol (JSON-RPC over WS/stdio),
different auth (dashboard token, `_ws_auth_ok` at `hermes_cli/web_server.py:15849`), and a
different session registry** — with a config gate (`_DASHBOARD_EMBEDDED_CHAT_ENABLED`,
`hermes_cli/web_server.py:355`, gated at `:15845`) in front of it. That is a strictly larger move than it looks from the feature list
in D.

---

## 5. What plugin-side code CAN do (named honestly, with their costs)

### 5.1 Precondition, verified: plugin code runs in the gateway process

- Plugin platform adapters are created by the runner from the registry:
  `platform_registry.create_adapter(platform.value, config)` (`gateway/run.py:13681`), and
  registered via `PluginContext.register_platform` (`hermes_cli/plugins.py:953-1000`).
- Plugin discovery is triggered at `model_tools.py:230-232` (module import time) and
  `hermes_cli/gateway.py:5393`, so any process that builds an agent loads plugins.
- Webhook ingress is real and fully plugin-controlled:
  `POST /api/platforms/{platform}/events` (`gateway/platforms/api_server.py:2012`) verifies
  with the **adapter's own** `verify_http_event_request` and then calls the adapter's
  `dispatch_http_event(payload)` (`gateway/platforms/api_server.py:1883`). That handler is
  plugin code with unrestricted in-process reach — it can call
  `gateway.run._gateway_runner_ref()` (the same seam `api_server.py:1481` uses) and walk to
  `runner.adapters[Platform.API_SERVER]`.

So a plugin **can** reach every object in §4's table. It just cannot reach an object that
was never stored.

### 5.2 Escape A — plugin-side monkeypatch capture (works in principle; brittle by construction)

A plugin loaded in the gateway process can wrap `HermesAPIServer._create_agent` (or
`_run_agent`) at load time and record the returned agent in a plugin-owned dict keyed by
`gateway_session_key or session_id`, clearing it when the call returns. The talaria
adapter's `dispatch_http_event` could then call `.steer(text)` on it.

This is plugin-side code — it lives in `~/.hermes/plugins/`, edits no core file, and
survives `curl install.sh | bash`. Costs, stated plainly:

- It binds to **private method names and signatures** (`_create_agent`,
  `gateway_session_key`) with no stability contract. A rename in any Hermes update breaks
  it silently — the steer just stops landing, with no error surface.
- It is a *hardening-shaped* dependency on someone else's internals, which is the failure
  mode CLAUDE.md's standing "do not harden" rule exists to avoid — friction that compounds
  across updates, on a component (§2.6) whose whole gap may be better solved by moving lanes.
- It still inherits the substrate's limit: **the steer lands only if the turn runs another
  tool** (`agent/agent_runtime_helpers.py:3949-3963`), else it is requeued
  (`agent/turn_finalizer.py:683`).

Verdict: viable, not recommended as the Phase 3 foundation. Reasonable as a
throwaway *experiment* to measure what steering feels like before committing.

### 5.3 Escape B — the `/v1/runs` lane is steerable in-process today (corrects a prior claim)

Prior research recorded that "`/v1/runs` structurally cannot steer (fresh agent per
request)". The *fresh agent per request* half is true; the *cannot steer* half is not.

```
gateway/platforms/api_server.py:1422        self._active_run_agents: Dict[str, Any] = {}
gateway/platforms/api_server.py:6462                self._active_run_agents[run_id] = agent
gateway/platforms/api_server.py:6867        agent = self._active_run_agents.get(run_id)   # /v1/runs/{id}/stop
```

The agent is retained for the run's lifetime and is only popped once the task is done
(`:6681-6682`, `:6926-6927`). `POST /v1/runs/{run_id}/stop` already proves the reference is
usable from a request handler. **There is no HTTP route that calls `steer()` on it — but a
plugin holding the adapter reference can**, with no monkeypatch, no core edit, and no
private-signature dependency beyond the `_active_run_agents` attribute name.

That makes "move Talaria's chat to `/v1/runs` + a plugin-side steer webhook" a materially
different option than "adopt tui_gateway", and it deserves its own row in the Phase 3
decision matrix. It is still a lane move (the `/v1/runs` event shape is not the
`assistant.delta` SSE taxonomy Talaria consumes today), just a much smaller one than a
process/protocol change.

### 5.4 What does NOT work

- Forging a `session_key` from the talaria adapter — §2.4(b), the injected text is queued
  into a FIFO nothing drains.
- A plugin tool or hook capturing the agent — §2.5, neither receives it.
- Reaching it via the interrupt machinery — §2.5, thread-keyed booleans only.
- Anything at all on the **sync** `POST /api/sessions/{id}/chat` — identical shape,
  identical absence of a reference.

---

## 6. What a live probe would still need to confirm

These are the points where the code read is suggestive but not conclusive. All are cheap.

1. **Version currency.** This read is against clone head `01a1037d1`. OJAMD self-updated to
   0.20.0 on 2026-08-03 and CLAUDE.md's standing rule is that a version string proves
   nothing about which code serves. Confirm the three `turn.agent =` write sites and the
   absence of `agent_ref` on the session-chat handlers **on the running OJAMD process** —
   e.g. `POST /v1/runs/{fake}/stop` returning 404 `run_not_found` confirms
   `_active_run_agents` exists and is reachable on that build.
2. **That §2.4(b) really is silent loss, not a crash.** The pending-FIFO claim
   (`gateway/run.py:8939` → nothing drains) is read from code paths, not observed. A probe:
   start a `/chat/stream` turn with `X-Hermes-Session-Key: agent:main:talaria:dm:X`, send a
   talaria webhook event that forces the busy handler on that key, then check whether the
   text ever surfaces on any later turn.
3. **Whether `display.busy_input_mode` is even set to `steer` on OJAMD.** Default is
   `"interrupt"` (`gateway/run.py:5714`, `:8223-8232`). Every steer path in §1.3 is gated on
   it. Read `config.yaml`'s `display.busy_input_mode` (or
   `HERMES_GATEWAY_BUSY_INPUT_MODE`, set at `gateway/run.py:2152`) before concluding
   anything about what platform steering does on that box today.
4. **That a `talaria` plugin adapter actually receives `set_busy_session_handler`.** The
   wiring is generic in the code read (`gateway/run.py:11041`), but confirm the talaria
   adapter is constructed through `_create_adapter`'s registry branch
   (`gateway/run.py:13679-13681`) and not some webhook-only shortcut.
5. **Escape B's steer semantics end-to-end.** `_active_run_agents[run_id].steer(text)` is a
   code-level certainty; whether the steer *arrives usefully* (turn runs another tool, marker
   renders sanely, `/v1/runs` event stream reflects it) is behaviour and must be measured,
   not read.
6. **Process topology on OJAMD.** The read says `hermes gateway run` does not host
   tui_gateway. Confirm on the box: whether anything is listening on `:9119`, and whether
   `_DASHBOARD_EMBEDDED_CHAT_ENABLED` is on — that decides whether "adopt tui_gateway" means
   "use a thing already running" or "stand up a second service".

---

## 7. Corrections to prior claims in this research series

| prior claim | status | evidence |
|---|---|---|
| "`/v1/runs` structurally cannot steer (fresh agent per request)" | **Half wrong.** Fresh agent per request is true; the agent is nonetheless retained in a live registry for the run's duration and is steerable in-process. No route exposes it. | `gateway/platforms/api_server.py:1422`, `:6462`, `:6867` |
| "The gateway plane has mid-turn steer machinery for platform-dispatched turns" | **Confirmed**, and the cited lines are accurate. | `gateway/run.py:8874-8920`, `gateway/platforms/base.py:5589-5713` |
| "tui_gateway has `session.steer`/`redirect`/`interrupt` with a busy-input queue" | **Confirmed**, and it is a *third* registry in a *different process* — one substrate, three doors, three registries. | `tui_gateway/methods_session.py:3055`, `tui_gateway/server.py:143`, `:7395`; no `tui_gateway` import anywhere under `gateway/` |
| (new) "the Sessions-API chat lane at least supports stop/cancel" | **Not asserted before, and it is false.** Disconnect cancels only the asyncio wrapper; the worker thread runs to completion. | `gateway/platforms/api_server.py:3836-3837` vs `:6860-6880` |
