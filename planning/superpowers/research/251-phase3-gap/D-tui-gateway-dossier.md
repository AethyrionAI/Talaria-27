# D — `tui_gateway` Dossier

**Scope:** definitive read of Hermes' `tui_gateway` JSON-RPC/WebSocket protocol, to decide
whether Talaria Phase 3 (streaming, mid-turn steering/interrupt/queue, approvals/HITL,
slash commands, live status) rides it, rides `/v1/runs`+events, or rides webhook envelopes.

**Evidence base:** read-only clone at
`…/scratchpad/hermes-agent-ro`, HEAD `01a1037d1` (2026-08-05).
Every claim below carries `file:line`. **Caveat on §5:** the clone is `depth=1`
(`git rev-parse --is-shallow-repository` → `true`; `git log --oneline | wc -l` → 1), so the
commit history of `tui_gateway/ws.py` — including when the "iOS / web client" docstring
landed — **is not recoverable locally**. Everything else in §5 is from in-repo artifacts.

---

## 0. Answers up front

| Question | Answer |
|---|---|
| Served by default on `hermes gateway run`? | **No.** Zero code path. `gateway/` references `tui_gateway` exactly once, in a comment (`gateway/status.py:376`). The `:8642` route table has no WebSocket at all. |
| Where does it live? | Two hosts only: **stdio** (`tui_gateway/entry.py`, what `hermes --tui` spawns) and **`/api/ws` on the dashboard app** (`hermes_cli/web_server.py:15843`, port **9119**). |
| Remote phone over Tailscale? | **Feasible and precedented** — the Electron desktop app does exactly this today (`apps/desktop/src/lib/remote-url.test.ts:7` literally tests `100.64.0.1:9119`). But it costs a second server process and a dashboard auth provider. |
| Steering coverage | **Best in the codebase, by a wide margin.** `session.steer`, `session.redirect`, `session.interrupt`, server-side prompt queue, and a three-mode `busy_input_mode` policy that makes a mid-turn `prompt.submit` *never* an error. |

---

## 1. What it is — the protocol surface

### 1.1 Framing and envelope

Newline-delimited JSON-RPC 2.0, **identical on stdio and WebSocket** — `tui_gateway/ws.py:9-13`:

> "Identical to stdio: newline-delimited JSON-RPC in both directions. … No framing differences."

- Request validation: `tui_gateway/server.py:1869` `_normalize_request` — must be an object,
  `method` a non-empty string, `params` an object or absent. Violations → `-32600` / `-32602`.
- Success envelope `{"jsonrpc":"2.0","id":…,"result":{…}}` — `server.py:1858` `_ok`.
- Error envelope `{"jsonrpc":"2.0","id":…,"error":{"code":…,"message":…}}` — `server.py:1862` `_err`.
  Unknown method → `-32601` (`server.py:1899`).
- **Events are JSON-RPC notifications with a fixed shape** — `server.py:1532` `_event_frame`:
  ```json
  {"jsonrpc":"2.0","method":"event","params":{"type":"<event>","session_id":"<sid>","payload":{…}}}
  ```
  Note: **the event type is `params.type`, not the JSON-RPC `method`** — `method` is the literal
  string `"event"` for every notification.
- Dispatch: `server.py:1903` `dispatch(req, transport)`. Handlers in `_LONG_HANDLERS`
  (`server.py:193-284`, ~40 slow methods incl. `slash.exec`, `session.resume`, `model.options`,
  `shell.exec`) are punted to an 8-worker thread pool (`server.py:288-296`,
  `HERMES_TUI_RPC_POOL_WORKERS`) and return `None` inline — the worker writes its own response.
  Everything else runs inline. This is *why* `session.interrupt` and `approval.respond` stay
  responsive during a long turn.

### 1.2 Method catalog — 133 registered methods

Registered via the `@method("name")` decorator (`server.py:1863`) into `server._methods`; the
`methods_*` split modules defer registration through `HandlerRegistry` (`tui_gateway/method_ctx.py`),
which rebinds handler `__globals__` onto `server`'s namespace so bodies stayed byte-identical
across the file split. Counts: `methods_session.py` 62, `methods_tools.py` 32,
`methods_prompt.py` 16, `server.py` 10, `methods_config.py` 7, `methods_complete.py` 6.

**Prompt / turn control** (`tui_gateway/methods_prompt.py` unless noted)
| Method | Line |
|---|---|
| `prompt.submit` | `:67` |
| `prompt.background` | `:720` |
| `session.steer` | `methods_session.py:3055` |
| `session.redirect` | `methods_session.py:3088` |
| `session.interrupt` | `methods_session.py:2824` |
| `subagent.interrupt` | `methods_session.py:2926` |
| `clipboard.paste` | `:336` · `paste.collapse` `methods_complete.py:14` |

**HITL / elicitation** — every one of these is a *response* to a server-pushed request event
| Method | Line | Answers event |
|---|---|---|
| `approval.respond` | `methods_prompt.py:915` | `approval.request` |
| `clarify.respond` | `:879` | `clarify.request` |
| `sudo.respond` | `:905` | `sudo.request` / `sudo.expire` |
| `secret.respond` | `:910` | `secret.request` / `secret.expire` |
| `terminal.read.respond` | `:888` | (tool-driven read-back) |
| `preview.read.respond` | `:897` | (tool-driven read-back) |

`approval.respond` takes `{choice: once|session|always|deny, all?: bool}` and calls
`tools.approval.resolve_gateway_approval` (`methods_prompt.py:915-933`). The other four route
through a shared `_respond(...)` with `allow_expired=True` — a late answer after a WS reconnect
resolves gracefully instead of erroring (`methods_prompt.py:879-884` explains this is *because of*
WebSocket reconnects dropping `tool.complete`).

**Session lifecycle** (`tui_gateway/methods_session.py`)
`session.create :14` · `session.list :162` · `session.most_recent :214` · `session.resume :306` ·
`session.cwd.set :725` · `session.workspace.move :750` · `session.active_list :824` ·
`session.activate :862` · `session.delete :887` · `session.title :937` · `message.react :1021` ·
`session.usage :1272` · `session.context_breakdown :1296` · `session.status :2281` ·
`session.history :2357` · `session.undo :2381` · `session.compress :2416` · `session.save :2588` ·
`session.close :2660` · `session.branch :2672` · `terminal.resize :3127` ·
`handoff.request/state/fail :1133/:1221/:1248` · `delegation.status/pause :2898/:2918` ·
`spawn_tree.save/list/load :2937/:2980/:3031` · `verification.status :281` · `project.facts :263`

**Attachments / media** (`methods_prompt.py`)
`image.attach :376` · `image.attach_bytes :419` · `pdf.attach :480` · `file.attach :606` ·
`image.detach :653` · `input.detect_drop :673` · `preview.restart :766`

**Slash / commands / completion**
`commands.catalog methods_tools.py:255` · `command.resolve :412` · `command.dispatch :432` ·
`slash.exec :1073` · `cli.exec :371` · `shell.exec :1867` ·
`complete.path methods_complete.py:41` · `complete.slash :218`

**Config / model / setup**
`config.get methods_config.py:161` · `config.set server.py:10482` · `config.show methods_tools.py:1382` ·
`model.options methods_complete.py:327` · `model.save_key :350` · `model.disconnect :430` ·
`setup.status methods_config.py:340` · `setup.runtime_check :350` · `reload.mcp methods_tools.py:84` ·
`reload.env :234`

**Tools / plugins / skills / process**
`tools.list :1423` · `tools.show :1454` · `tools.configure :1497` · `toolsets.list :1566` ·
`agents.list :1596` · `plugins.list :1360` · `plugins.manage :1788` · `skills.manage :1704` ·
`skills.reload :1763` · `cron.manage :1620` · `browser.manage :1343` · `insights.get :1213` ·
`process.list/stop/kill :49/:39/:61` · `rollback.list/diff/restore :1238/:1320/:1268` ·
`learning.frames/detail/delete/edit :1647/:1671/:1682/:1693` · `system.battery :14` ·
`projects.* methods_config.py:19/:44/:108/:135`

**Voice / wake** (`server.py`) — **all host-side, see §4**
`voice.toggle :13429` · `voice.record :13543` · `voice.tts :13697` ·
`wake.start/stop/pause/resume/status/feed :13114/:13263/:13290/:13308/:13320/:13390`

**Billing / subscription** (`methods_session.py`) — Nous-hosted, irrelevant to a self-host
`billing.* :2012-:2240` · `subscription.* :2043-:2125` · `usage.bars :2028` · `llm.oneshot :1074`

**Pet** (`methods_session.py:1326-1913`) — 16 methods, cosmetic.

### 1.3 Event catalog

The authoritative typed list is the TUI's own discriminated union,
`ui-tui/src/gatewayTypes.ts:603-741` (`export type GatewayEvent`). Grouped:

| Group | Events |
|---|---|
| Connection | `gateway.ready` (`:604`), `gateway.stderr` (`:641`), `gateway.start_timeout` (`:650`), `gateway.protocol_error` (`:652`), `skin.changed` (`:605`) |
| Session | `session.info` (`:606`), `status.update` (`:610`), `dashboard.new_session_requested` (`:640`) |
| **Answer stream** | `message.start` (`:609`), `message.delta` (`:722`, `{text, rendered}`), `message.interim` (`:726`), `message.complete` (`:739`, carries `usage` + `billing` + `reasoning`) |
| **Reasoning stream — separate channel** | `thinking.delta` (`:607`), `reasoning.delta` / `reasoning.available` (`:656`) |
| Tools | `tool.start` (`:679`, `{tool_id, name, args_text, context, todos}`), `tool.progress` (`:674`), `tool.generating` (`:675`), `tool.complete` (`:693`, `{tool_id, result_text, summary, inline_diff, duration_s, error}`) |
| **HITL** | `approval.request` (`:709`, `{command, description, choices, allow_permanent, smart_denied}`), `clarify.request` (`:698`, `{question, choices, request_id}`), `sudo.request` (`:711`), `secret.request` (`:712`), `secret.expire` / `sudo.expire` (`:713`) |
| Delegation | `subagent.spawn_requested/start/thinking/tool/progress/complete` (`:716-721`), `background.complete` (`:714`), `review.summary` (`:715`) |
| MoA | `moa.reference` (`:661`), `moa.aggregating` (`:663`), `moa.progress` (`:667`), `moa.phase` (`:672`) |
| UI | `notification.show` (`:621`) / `notification.clear` (`:623`), `reaction` (`:608`), `browser.progress` (`:645`), `error` (`:741`) |
| Voice | `voice.status` (`:629`), `voice.transcript` (`:633`), `wake.detected` (`:638`) |
| Billing | `billing.step_up.verification` (`:627`) |

Plus a change-notification family the WS ready frame advertises — `pet.changed`, `cron.changed`,
`sessions.changed`, `platforms.changed`, `pairing.changed` (`server.py:3381-3385`), each with a
debounce interval and signature function, so clients can demote polling to a slow backstop.

### 1.4 Connection lifecycle (WebSocket)

`tui_gateway/ws.py:288-476` `handle_ws`:

1. `await ws.accept()` (`:297`) — **no handshake auth of its own**; the mounting route owns auth (§3).
2. `TCP_NODELAY` set (`:301`, `_disable_nagle`) so per-token frames aren't Nagle-batched.
3. `resolve_skin()` off-loop via `asyncio.to_thread` (`:313`), then **`gateway.ready` is pushed
   immediately** (`:315-329`) with `{"skin": …, "change_events": true}`.
4. On successful ready: `server._ensure_skin_watcher()` + `server.register_live_transport(transport)`
   (`:330-332`) — registers the peer for session-less global broadcasts.
5. Read loop (`:334-…`): `receive_text` → `json.loads` → `asyncio.to_thread(server.dispatch, req, transport)`.
   Parse failure → `-32700`; handler crash → `-32603`; both keep the socket alive.
6. Teardown (`:431-476`): unregister transport, release wake-word ownership,
   `_close_sessions_for_transport(transport, end_reason="ws_disconnect")`, close socket, log a
   one-line summary with `reason=` / `parse_errors=` / `send_failures=` / `reaped_sessions=`.

**Streaming backpressure design worth knowing (`ws.py:41-58`):** frames whose
`params.type` is in `{message.delta, reasoning.delta, thinking.delta}` are **coalesced** — buffered
and flushed on a ~33 ms timer (~30 fps). Any non-streaming frame drains the buffer *ahead of itself*,
so ordering is preserved. A 10 s write timeout does **not** latch the transport dead (`:169-183`) —
that was a real bug ("subagent window shows zero streaming") fixed by treating a slow write as a
stalled loop rather than a dead socket.

**Disconnect semantics — critical for a phone that backgrounds:**
`server.py:1068` `_close_sessions_for_transport` — sessions flagged `close_on_disconnect` are
reaped immediately; the rest are pointed at `_detached_ws_transport` and handed to a
**grace-windowed orphan reaper** (`server.py:1027` `_schedule_ws_orphan_reap`,
`HERMES_TUI_WS_ORPHAN_REAP_GRACE_S`, **default 20 s**, `server.py:174-180`).
**A running session is exempt** — `_ws_session_is_orphaned` returns `False` while
`session["running"]` (`server.py:947-948`). So: background mid-turn → the turn keeps running,
its events are dropped on the floor, and a reconnect + `session.resume` recovers state.
Background while *idle* for >20 s → the in-process session is torn down (the durable transcript
in `state.db` survives; the live agent does not).

`session.resume` (`methods_session.py:306`) returns `{session_id, messages, message_count,
running, status, started_at, inflight}` where `inflight` is `{user, assistant, streaming}`
(`ui-tui/src/gatewayTypes.ts:205-209`) — a **snapshot** of the in-flight turn, not a replayable
event log.

### 1.5 Versioning — **there is none**

`grep -rn 'protocol_version|PROTOCOL_VERSION|protocolVersion'` across `.py`/`.ts` returns hits only
for A2A (`plugins/platforms/a2a/protocol.py:35`), the bootstrap-installer manifest, and the
dashboard's SSH-ownership proof (`hermes_cli/web_server.py:3005`). **Nothing in `tui_gateway`.**
`gateway.ready` carries no version — only `skin` + a single capability bit `change_events`
(`ws.py:319-325`). Feature detection is ad-hoc per payload (e.g.
`agent._supports_active_turn_redirect` is probed server-side, `methods_session.py:3108`).
The client's only negotiated constants are timeouts it sets itself:
`HERMES_TUI_STARTUP_TIMEOUT_MS` 15 s, `HERMES_TUI_RPC_TIMEOUT_MS` 120 s
(`ui-tui/src/gatewayClient.ts:17-18`).

### 1.6 How the TUI itself uses it

`ui-tui/src/gatewayClient.ts` — a single `GatewayClient extends EventEmitter`:

- **Default:** spawns its own Python child over stdio (`start()`, `:522-560`; `resolvePython` `:49`).
- **Attach mode:** if `HERMES_TUI_GATEWAY_URL` is set (`resolveGatewayAttachUrl`, `:36`), it opens a
  WebSocket instead (`startAttachedGateway`, `:425`).
- **No reconnect logic.** A `close` event goes straight to `handleTransportExit`
  (`:497-508`) — the TUI treats a dropped socket as gateway death, not a retryable blip.
  A mobile client would have to write its own reconnect+resume ladder.
- Events land in a 2000-entry ring buffer until a subscriber attaches (`:141`, `publish` `:159`),
  so nothing emitted during startup is lost.
- The event reducer is `ui-tui/src/app/createGatewayEventHandler.ts` — a `switch` over
  `ev.type` (e.g. `gateway.ready` `:725`, `reasoning.delta` `:1046`, `message.delta` `:1331`).
  Its test file asserts a semantic Talaria would inherit: **`message.delta` always accumulates
  `payload.text` and ignores `payload.rendered`** (`createGatewayEventHandler.test.ts:592`) —
  `rendered` is ANSI for the terminal.

---

## 2. How it's served

### 2.1 Two hosts, and only two

| Host | Transport | Entry | Who starts it |
|---|---|---|---|
| stdio | newline JSON-RPC on stdin/stdout | `tui_gateway/entry.py:430` `main()` (`__main__` at `:498`) | `hermes --tui` spawns it as a Python child (`ui-tui/src/gatewayClient.ts:522-560`) |
| WebSocket | `/api/ws` | `hermes_cli/web_server.py:15843` `@app.websocket("/api/ws")` → `handle_ws` (`:15857-15859`) | `hermes dashboard` / `hermes serve`, **port 9119** |

`rg -n "handle_ws" -g '!tui_gateway/ws.py'` finds exactly **one** production mount:
`hermes_cli/web_server.py:15857`. Everything else is tests.

### 2.2 `hermes gateway run` does NOT serve it

Three independent confirmations:

1. `rg -n "tui_gateway" gateway/` → one hit, a comment (`gateway/status.py:376`).
2. `rg -n "websocket|WebSocket" gateway/platforms/api_server.py` → **zero hits**. The `:8642`
   adapter is aiohttp and registers no WS route. Full table at
   `gateway/platforms/api_server.py:1980-2031` (matches CLAUDE.md's verified list exactly).
3. The docs say so explicitly — `website/docs/user-guide/tui.md:284`:
   > "the OpenAI-compatible API server (`hermes gateway` / the `api_server` platform) does **not**
   > serve `/api/ws` … Setting `HERMES_TUI_GATEWAY_URL` to that port will 404."

**So on OJAMD today, `tui_gateway` is not listening anywhere.** Adopting it means standing up a
second long-lived process (`hermes serve`) alongside `hermes gateway run`.

### 2.3 Inside the dashboard process it is unconditionally on

`_DASHBOARD_EMBEDDED_CHAT_ENABLED = True` (`hermes_cli/web_server.py:355`) — a module-level constant,
not config. Comment at `:351-354`: *"Always enabled: the desktop app and the dashboard's own Chat tab
both drive the agent over the `/api/ws` + `/api/pty` WebSockets, so the embedded-chat surface is an
unconditional part of the dashboard."* No config key disables it; the gate exists only as a testable seam.

### 2.4 `dashboard` vs `serve`

Both route through `cmd_dashboard` / `start_server` (`hermes_cli/web_server.py:17423`), differing only
in the SPA. `AGENTS.md` (Desktop section) is explicit: `serve` sets `headless_backend=True`, which skips
`_build_web_ui` **and** exports `HERMES_SERVE_HEADLESS=1` so `mount_spa()` disables the SPA even if a
stray `web_dist/` exists — *"only the JSON-RPC/WS/API surface is reachable."*
Confirmed at `hermes_cli/main.py:10306` (`"serve" if _headless_backend else "dashboard"`) and
`web_server.py:17440-17442`.

**`hermes serve` is the shape Talaria would want:** no Node build, no SPA, just
`/api/ws` + the REST surface. It is exactly what the Electron desktop app launches for itself.

### 2.5 Agents run in the serving process

`hermes_cli/main.py:10388`: *"The dashboard/serve backend runs agents in-process
(`tui_gateway.ws` → `server._make_agent`) and ticks cron jobs itself when desktop-spawned."*
So `hermes serve` is a **full second agent runtime** — its own MCP discovery, its own model
metadata, its own tool processes — not a thin proxy onto the `:8642` gateway. Two agent
runtimes on one box, sharing `state.db`.

---

## 3. Auth model

**`handle_ws` has no auth of its own** — it calls `ws.accept()` at `ws.py:297` unconditionally.
All three gates live in the mounting route (`web_server.py:15844-15857`):

```
if not _DASHBOARD_EMBEDDED_CHAT_ENABLED: close(4403)   # always False → never fires
if not _ws_auth_ok(ws):                  close(4401)   # credential
if not _ws_request_is_allowed(ws):       close(4403)   # Host/Origin + peer IP
```

### 3.1 Two modes, selected purely by bind address

`should_require_auth(host)` (`web_server.py:472-491`) — one line: `return host not in _LOOPBACK_HOST_VALUES`.
Its docstring is unambiguous: *"RFC1918 / CGNAT / link-local are deliberately treated as PUBLIC — a
hostile device on the same LAN is exactly the threat model the gate is designed for."*
**A Tailscale `100.64.0.0/10` address is CGNAT, therefore public, therefore gated.**

**Mode A — loopback bind (`auth_required = False`).**
Credential: `?token=<_SESSION_TOKEN>`, constant-time compared (`_ws_auth_reason`, `web_server.py:14766-14771`).
`_SESSION_TOKEN` = `HERMES_DASHBOARD_SESSION_TOKEN` env, else a fresh `secrets.token_urlsafe(32)` per
process (`web_server.py:330-333`). Peer gate: **loopback peers only** (`_ws_client_reason`,
`:14550-14563`); an empty/unidentifiable peer **fails closed**. Host guard: Host header must be a
loopback name (`_is_accepted_host`, `:531-532`).

**Mode B — non-loopback bind (`auth_required = True`).**
Credential is one of:
- `?ticket=<single-use, 30 s TTL>` minted at `POST /api/auth/ws-ticket`
  (`hermes_cli/dashboard_auth/routes.py:799-828`; store at `dashboard_auth/ws_tickets.py:63-80`),
  authenticated by session cookie **or** `Authorization: Bearer` via the `token_auth` seam
  (`dashboard_auth/token_auth.py`).
- `?internal=<process-lifetime credential>` — **never leaves the process except through a
  server-spawned child's environment** (`ws_tickets.py:15-28`). Not obtainable by a remote client.
- **`?token=` is unconditionally rejected in gated mode** (`web_server.py:14748-14751`).

Peer gate in Mode B: **any peer allowed** (`_ws_client_is_allowed` returns `True` when
`auth_required`, `:14591`) — uvicorn runs with `proxy_headers=True` in this mode
(`:17606`), so `ws.client.host` is the X-Forwarded-For value.

Host/Origin guard still applies in both modes (`_ws_host_origin_reason`, `:14610-14640`):
Host header must match the bound interface; a `http(s)` Origin, if present, must too. Non-web
origins (`file://`, `null`, `app://` — i.e. native apps) are **explicitly waved through**
(`:14625-14630`) — good news for a native iOS client, which sends no Origin.

### 3.2 `--insecure` is a no-op — this is the load-bearing constraint

`web_server.py:17465-17476` and `should_require_auth`'s docstring (`:483-489`):

> "`--insecure` no longer disables the auth gate (June 2026 hardening: the hermes-0day
> MCP-persistence campaign abused unauthenticated public dashboards). … a non-loopback bind
> ALWAYS requires an auth provider (OAuth or the bundled password provider)."

With no provider registered, the bind **fails closed** with a fix-hint
(`web_server.py:17478-17512`), whose last line reads: *"There is no unauthenticated public-bind
option — to keep it local, bind 127.0.0.1 and tunnel in (SSH / Tailscale)."*

The bundled zero-infrastructure provider is `plugins/dashboard_auth/basic` — username + scrypt
password hash in `config.yaml` under `dashboard.basic_auth` (or
`HERMES_DASHBOARD_BASIC_AUTH_*` env), stateless HMAC session tokens, no IDP, no database.
Login is `POST /auth/password-login` (`dashboard_auth/routes.py:650`), which sets
`hermes_session_at` / `hermes_session_rt` cookies. **Set an explicit `secret`** or sessions
die on every restart (documented in the provider docstring).

### 3.3 TLS

**None.** `uvicorn.Config(...)` at `web_server.py:17597-17614` passes no `ssl_certfile` /
`ssl_keyfile`; `grep` finds neither anywhere in `web_server.py` or `main.py`. Plaintext HTTP/WS
only — TLS must be terminated externally.

### 3.4 What a remote Talaria would actually do

**Precedent: the Electron desktop already does this.** `apps/desktop/electron/connection-config.ts:12-18`
documents both auth models verbatim ("token" vs "oauth", the latter via `?ticket=` minted at
`POST /api/auth/ws-ticket`, advertised by `/api/status` field `auth_required: true`), and
`apps/desktop/src/lib/remote-url.test.ts:7-9` tests scheme-coercion for
`100.64.0.1:9119` and `mini.tailnet-1234.ts.net:9119`. This is a supported, tested,
shipping remote-over-tailnet path.

Two viable recipes for the phone:

**Recipe 1 — bind the tailnet IP + password provider (gated).**
```
hermes serve --host 100.79.222.100 --port 9119
  + dashboard.basic_auth.{username,password_hash,secret} in config.yaml
```
Phone: `POST /auth/password-login` → cookies (URLSession's `HTTPCookieStorage` handles this)
→ `POST /api/auth/ws-ticket` → `ws://100.79.222.100:9119/api/ws?ticket=…`.
Host header = `100.79.222.100:9119` (exact match required, `_is_accepted_host:534-535`).
Ticket TTL is 30 s, single-use — **mint one per connect, and on every reconnect.**

**Recipe 2 — bind loopback + tunnel (token mode).**
`hermes serve --host 127.0.0.1` + `HERMES_DASHBOARD_SESSION_TOKEN=<stable>`, reached via a
tunnel that makes the peer appear as loopback. **Hazard:** `tailscale serve` forwards the
*original* Host header (the `*.ts.net` name), which a loopback bind rejects
(`_is_accepted_host:531-532` requires a loopback name). Talaria already runs
`tailscale serve --bg 8477` for OTA, so this is a live trap, not a hypothetical.
Not verifiable from this clone — **needs a probe before anyone plans on it.**

**Recipe 1 is the one to plan for.** Notes for Talaria specifically:
- ATS: `ws://` is evaluated like `http://`. The existing `NSExceptionDomains` entry keyed on
  `100.64.0.0/10` (`project.yml`, #166b) should cover it — but this is an *untested*
  extension of a four-arm experiment that only exercised `URLSession` HTTP. Verify.
- Cookies ride plaintext over the tailnet (WireGuard-encrypted at the transport, so acceptable —
  but `detect_https()` will mark them non-`Secure`).
- `ws_max_size = 384 MiB` (`web_server.py:363`, `_DESKTOP_ATTACHMENT_WS_MAX_BYTES`, wired at `:17613`).
- Public keepalive pings are on for non-loopback binds: `ws_ping_interval/timeout = 20 s`
  (`:17611-17612`). Comment at `:17577-17590` warns a GIL-holding agent turn can starve the loop
  past that and drop an otherwise-healthy socket. **A phone on a gated bind will see spurious
  disconnects during heavy turns.** Loopback binds disable the ping precisely to avoid this.

---

## 4. Capability coverage

### 4.1 Token streaming with a separate reasoning channel — **YES, cleanly**

Answer text: `message.delta` `{text, rendered}` (`gatewayTypes.ts:722`), bracketed by
`message.start` (`:609`) and `message.complete` (`:739`, carrying `usage`, `reasoning`,
`billing`, `failure_reason`).
Reasoning: `reasoning.delta` / `reasoning.available` (`:656`) and `thinking.delta` (`:607`) —
**structurally separate event types**, never folded into `message.delta`. Server-side
`show_reasoning` gate at `server.py:_load_show_reasoning`-equivalent config
(`display.show_reasoning`, `gatewayTypes.ts:98`).
Transport tuning is already done for you: coalescing at ~30 fps + `TCP_NODELAY`
(`ws.py:41-58`, `:257-273`).
Interim commentary between tool batches: `message.interim` (`:726`), gated by
`display.interim_assistant_messages` (`server.py:470-481`).

### 4.2 Mid-turn steer / interrupt / queue — **YES; this is the protocol's standout**

Four distinct mechanisms, all first-class:

1. **`session.steer`** (`methods_session.py:3055-3084`) — *"Inject a user message into the next
   tool result without interrupting. … lands on the last tool result of the next tool batch and the
   model sees it on its next iteration. No interrupt, no new user turn, no role alternation
   violation."* Uses `_sess_nowait` (safe while running). Returns `{status: "queued"|"rejected"}`.
   Also records an inflight correction so a reconnect mid-turn still shows the user's bubble
   (`:3078-3084` — explicitly fixing "my message vanished on reload").
2. **`session.redirect`** (`:3088-3123`) — redirects the *active* turn while preserving valid
   work/context. Requires `agent._supports_active_turn_redirect is True`. Notably, if the agent is
   still building (`agent is None and running`), it **queues server-side rather than erroring**
   (`:3101-3106`).
3. **`session.interrupt`** (`:2824-2892`) — hard interrupt via `request_hard_interrupt`, clears the
   queue, bumps a generation counter, denies all pending approvals, stops streaming TTS, and
   force-clears a desynced `running` flag so a session can't brick at 4009. Background processes
   the agent started are deliberately **left running** (`:2878-2884`).
4. **`prompt.submit` while busy never errors** — `_handle_busy_submit`
   (`server.py:7395-7480`) applies `display.busy_input_mode` (`server.py:462-467`), one of:
   - `interrupt` (**default**) → redirect the live turn in place; fall back to hard-interrupt +
     server-side queue for agents without redirect support;
   - `queue` → enqueue without touching the live turn;
   - `steer` → `agent.steer()` after the current atomic action.
   A client-side drain passes `queued: true`, which **overrides the mode entirely** so an
   explicitly-queued message can never become a live-turn correction on a settle race
   (`:7410-7415`). Multi-message queue with order preservation across image turns —
   `_enqueue_prompt`, exercised at `tests/test_tui_gateway_queue_on_busy.py:36-53`.
   The test file's own docstring names the failure it fixed: *"the resubmitted message was
   silently dropped ('it just doesn't listen')."*

Also `subagent.interrupt` (`:2926`) and `delegation.pause` (`:2918`) for the delegation tree.

### 4.3 Approvals / HITL elicitation — **YES, five distinct flows**

Server pushes a `*.request` event carrying a `request_id`; client answers with the matching
`*.respond` RPC. Approval choices are `once | session | always | deny`, plus `all` to resolve a
batch (`methods_prompt.py:915-933`). `approval.request` payload carries `command`, `description`,
`choices`, `allow_permanent`, `smart_denied` (`gatewayTypes.ts:700-709`).
Expiry is modelled: `sudo.expire` / `secret.expire` carry the original `request_id` so a client
clears only the matching card (`gatewayTypes.ts:713`; documented at
`website/docs/developer-guide/programmatic-integration.md:60`). All four non-approval responders
pass `allow_expired=True` **specifically to survive a WebSocket reconnect**
(`methods_prompt.py:879-884`).

### 4.4 Slash commands — **YES, the full pipeline**

`commands.catalog` (`methods_tools.py:255`) returns the registry-backed catalog with categories,
canonical-name map, alias resolution, and skill-derived commands.
`complete.slash` (`methods_complete.py:218`) does typed-prefix completion;
`complete.path` (`:41`) does path completion with git-aware fuzzy ranking.
`command.resolve` (`methods_tools.py:412`) canonicalizes; `command.dispatch` (`:432`) executes,
returning a tagged union: `exec | plugin | alias | skill | send | prefill`
(`gatewayTypes.ts:69-75`) — i.e. the protocol tells the client whether to render output, follow an
alias, load a skill, send a message, or prefill the composer.
`slash.exec` (`methods_tools.py:1073`) is the general executor (pool-dispatched, 45 s default via
`HERMES_TUI_SLASH_TIMEOUT_S`, `server.py:157-162`).
`AGENTS.md` states flatly: *"Backend already provides everything… The desktop app does not need a
new RPC to see skills."*

### 4.5 Session management / history — **YES, richer than the Sessions API**

`session.create` accepts per-session `model`, `provider`, `reasoning_effort`, `fast`, `cwd`,
`title`, `parent_session_id`, seed `messages`, `profile` — and treats model/effort/fast as
**per-session overrides, never a global config write** (`methods_session.py:36-70`).
`session.list` / `session.most_recent` / `session.history` / `session.status` /
`session.usage` / `session.context_breakdown` / `session.undo` / `session.compress` /
`session.branch` / `session.save` / `session.title` / `session.delete`.
`session.resume` (`:306`) follows the compression-continuation chain to the live tip so resuming a
rotated-out parent id lands on the descendant holding post-compression turns (`:353-372`) — a
correctness behaviour Talaria's Sessions-API client does not get for free.
Live-session controls `session.active_list` / `activate` / `close` are **process-local** —
the docs warn to use `session.list` for durable discovery
(`website/docs/developer-guide/programmatic-integration.md:57`).

### 4.6 Model switching — **YES, and better-behaved than our shim dual-write**

`model.options` (`methods_complete.py:327`) is the same payload builder as the REST
`GET /api/model/options` — provider rows, pricing, capability hints, custom-provider probe policy
(`programmatic-integration.md:116-131`).
`config.set {key:"model"}` (`server.py:10482-10530`): if a turn is running it **stashes a pending
switch and applies it at the next turn start** instead of rejecting (the old 4009), and
`_session_info` reports the pending pick so the UI doesn't blip back to the old model
(`:10502-10527`). `model.save_key` / `model.disconnect` manage credentials.
`command.dispatch {"command": "/model …"}` is the documented equivalent
(`programmatic-integration.md:145`).
**This is a direct answer to OPEN_ITEMS #9** — the gateway `/model` session pin that hangs ~37 s+.

### 4.7 File / media transfer — **YES inbound; NO outbound (but adjacent REST fills it)**

Inbound is explicitly built for remote clients:
- `image.attach_bytes` (`methods_prompt.py:419-475`) — docstring: *"A desktop app or web dashboard
  running on a DIFFERENT machine than the gateway can't hand us a local path… So it uploads the raw
  image bytes (base64) and we write them into the gateway's own images dir."* Cap
  `_ATTACH_BYTES_MAX_BYTES = 25 MiB` (`server.py:10208`).
- `file.attach` (`:606-650`) — `data_url` upload, returns an `@file:` workspace ref the agent's
  file tools can read.
- `pdf.attach` (`:480`) — renders pages via `pdftoppm` at 150 DPI, 50 MB / 25 pages.
- `image.attach` (`:376`) — host-path variant, local-only.

**Outbound: `tui_gateway` has no file-read/download method.** There is no `file.read`,
`file.download`, or `fs.*` in the 133-method catalog.
**But** — and this matters for OPEN_ITEMS #21 — because `tui_gateway` is served *by the dashboard
app*, the dashboard's REST file family sits on the **same origin and the same auth**:
`GET /api/files` (`web_server.py:2349`), `/api/files/read` (`:2381`),
`/api/files/download` (`:2416`), `POST /api/files/upload` (`:2452`),
`/api/files/upload-stream` (`:2487`), `/api/files/mkdir` (`:2551`), `DELETE /api/files` (`:2572`).
`/api/files/download` is in `_QUERY_TOKEN_API_PATHS` (`:421`) so it accepts a query-string token —
i.e. it works from a plain URL load. **Adopting `tui_gateway` closes #21 Tier 2 as a side effect,
with no relay sidecar.**

### 4.8 Voice — **partial, and the split is not where you'd want it**

The `tui_gateway` voice RPCs are **host-side**: `voice.record` (`server.py:13543`) captures on the
*gateway machine's* microphone via `hermes_cli.voice.start_continuous`; `voice.tts` (`:13697`)
plays on the *gateway machine's* speakers via a background thread. `wake.*` likewise. For a phone
these are the wrong end of the wire.

The usable remote voice path is again on the dashboard origin, not in `tui_gateway`:
- `POST /api/audio/transcribe` (`web_server.py:4304`) — client uploads audio, server transcribes.
- `WS /api/audio/speak-stream` (`web_server.py:4615-4635`) — **text in, raw int16 PCM out**, with
  incremental feeding (`{"text":…}` as deltas arrive), `{"done":true}`, `{"stop":true}` for
  barge-in, and a `{"type":"fallback"}` signal. Same `_ws_auth_ok` / `_ws_request_is_allowed` gates
  (`:4636-4641`) — i.e. **the same ticket works** (`apps/desktop/src/lib/voice-playback.ts:100-128`
  shows the desktop swapping `/api/ws` → `/api/audio/speak-stream` on the same minted credential).
- `POST /api/audio/speak` (`:4511`) for one-shot.

### 4.9 Live status — **YES**

`status.update` `{kind, text}` (`gatewayTypes.ts:610`), with a `compacting` kind synthesized when
the compaction marker appears (`server.py:1820-1828`). Plus `session.info` (20 emit sites),
`notification.show`/`clear` with keyed replace-in-place and TTL, `tool.generating`,
`moa.phase`/`progress`, `subagent.*`, `browser.progress`, and the debounced
`*.changed` broadcast family (`server.py:3381-3385`).

---

## 5. Stability — is this a public contract?

**Documented as an integration surface — yes.**
`website/docs/developer-guide/programmatic-integration.md` lists it as one of Hermes' *three*
supported programmatic protocols (`:14`), with a selected method catalog (`:43-55`), an event list
(`:60`), and a "which one should I use?" section whose answer for our exact case is unambiguous
(`:134`):

> "**You're writing a custom desktop / web / TUI host and want every Hermes feature** (slash
> commands, approvals, clarify, multi-agent, session branching) → TUI gateway JSON-RPC."

It even ships a **Pi-mono RPC compatibility mapping** (`:64-80`) — `prompt`→`prompt.submit`,
`steer`→`session.steer`, `abort`→`session.interrupt`, `follow_up`→queued `prompt.submit`,
`ui_request`/`ui_response`→the four responders — i.e. upstream has already reasoned about
third-party hosts speaking this protocol.

**Versioned — no.** §1.5: no version field anywhere, and the ready frame advertises exactly one
capability bit. A breaking change would arrive as a silently-different payload.

**Churn signals — high traffic, but well-tested.** 25,563 lines across 22 modules, `server.py`
alone 14,006. `tests/tui_gateway/` holds **51** test files, plus `tests/test_tui_gateway_*.py`
(protocol, ws, queue-on-busy, loop-noise) and a large `ui-tui/src/__tests__/` suite on the client
side. The code is dense with issue-numbered regression comments (#12546, #21123, #38591, #39591,
#50005, #53773, #60800, #63078, #73106…), which cuts both ways: it is battle-tested *and* it is
under constant behavioural revision. `tests/tui_gateway/test_protocol.py` covers envelopes and
dispatch plumbing but **does not lock the method or event catalog** — nothing in the repo pins the
surface.

**Contradiction to hold in mind.** The developer docs say *"Any external host can speak the same
protocol over stdio (or WebSocket via `tui_gateway/ws.py`)"* (`:39`), while the user docs say
*"There is no general 'point any TUI at any standalone gateway port' mode… `/api/ws` exists only
inside the dashboard server … bound to that process's lifetime and auth"*
(`website/docs/user-guide/tui.md:282-286`). Both are literally true and they resolve cleanly: the
**protocol** is an offered integration surface; the **WebSocket endpoint** is not a standalone
service you can point anything at — you get it by running the dashboard/serve process. The
`ws.py:3-6` docstring naming "an iOS / web client" is a statement of design intent for that
endpoint, not a promise of a standalone port.

**Unverifiable here:** the docstring's commit history. Shallow clone. If that provenance matters
to the decision, it needs a `git log -S "an iOS / web client" -- tui_gateway/ws.py` against a full
clone or the GitHub UI.

---

## 6. Verdict shape — three-way comparison

### 6.1 Per-capability

| Capability | `tui_gateway` `/api/ws` (:9119) | `/v1/runs` + `/events` (:8642) | Webhook envelopes (platform adapter) |
|---|---|---|---|
| Token streaming | `message.delta`, coalesced 30 fps, TCP_NODELAY (`ws.py:41-58`) | `assistant.delta` SSE (`api_server.py:3731`) — what we ship today | Turn-granular. No token stream. |
| Separate reasoning channel | `reasoning.delta` / `thinking.delta` — distinct event types (`gatewayTypes.ts:607,656`) | `tool.progress` with `tool_name:"_thinking"` (`api_server.py:3735`) — a channel *overloaded* onto tool progress | None |
| **Mid-turn steer** | **`session.steer` + `session.redirect` + 3-mode `busy_input_mode`** (`methods_session.py:3055,3088`; `server.py:7395`) | **None.** `rg "steer" gateway/platforms/api_server.py` → 0 hits. `_run_agent` *"Create an agent and run a conversation in a thread executor"* (`api_server.py:5979`) — a fresh agent per request, so there is no live object to steer. | Gateway core *does* implement `busy_input_mode` (`gateway/run.py:8223-8232`), but it is the **messaging-gateway** path — our adapter would have to be a real platform adapter to reach it, and correlation back to a phone turn is ours to build |
| **Interrupt** | `session.interrupt` (`:2824`) — full teardown, queue clear, approval deny, TTS stop | `POST /v1/runs/{id}/stop` (`api_server.py:6860`) — runs plane only. For `/api/sessions/…/chat/stream` the **only** interrupt is client disconnect (`api_server.py:4099`, `:4410`) | Depends entirely on adapter design |
| **Queue** | Server-side multi-message queue, order-preserving, generation-counted (`_enqueue_prompt`; `test_tui_gateway_queue_on_busy.py`) | None — concurrency is admission-control only (`_admit_api_agent_request`, `api_server.py:1107`) | Client-side only |
| Approvals / HITL | 5 flows, `request_id`-correlated, expiry-aware, reconnect-tolerant (`methods_prompt.py:879-933`) | `POST /v1/runs/{id}/approval`, choices `once|session|always|deny` (`api_server.py:6772-6812`) — **runs plane only**, nothing on `/api/sessions` | Would have to be invented |
| Slash commands | `commands.catalog` + `complete.slash` + `command.dispatch` tagged union (`methods_tools.py:255,432`) | None. Slash text goes in as prompt text | None |
| Session mgmt / history | 25+ methods incl. `branch`, `compress`, `undo`, `context_breakdown`, continuation-chain resume | `/api/sessions*` — create/list/get/patch/delete/messages/fork. Solid but thinner | N/A |
| Model switching | `model.options` + `config.set model` with **deferred mid-turn apply** (`server.py:10502`) | `GET /api/model/options` + `POST /api/sessions/{id}/model` (the pin that hangs, #9) | N/A |
| File in | `image.attach_bytes` / `file.attach` / `pdf.attach` — designed for remote clients | Nothing | N/A |
| File out | Nothing in-protocol — **but `/api/files/*` shares the origin and auth** (`web_server.py:2349-2572`) | Nothing (#21 confirmed) | N/A |
| Voice | RPCs are host-side (wrong end), **but** `/api/audio/transcribe` + `WS /api/audio/speak-stream` share the origin and ticket | Nothing | N/A |
| Live status | `status.update`, `notification.*`, `*.changed` broadcasts | `run.started` / `run.completed` only | N/A |
| **Reconnect / replay** | No replay. Events fire-and-forget to the attached transport; recovery = reconnect + `session.resume` → `inflight` snapshot (`gatewayTypes.ts:205`). Running sessions survive; **idle ones are reaped after 20 s** (`server.py:174-180`, `:947`) | **Worse.** `/v1/runs/{id}/events` pops the queue on subscriber disconnect (`api_server.py:6764-6767`) — reconnecting after a drop 404s. No `Last-Event-ID`. | Inherently durable — that's the whole point of webhooks |
| Auth for a remote phone | Password provider + cookie + 30 s ticket per connect (§3.4) | `Bearer API_SERVER_KEY` — one static header, already working | Ours to design |
| Ops cost | **A second agent runtime** (`hermes serve`) alongside `hermes gateway run` | Zero — already running | New adapter surface |

### 6.2 What Phase 3 looks like on each

**Riding `tui_gateway`.** One WebSocket carries everything: streaming with a real reasoning
channel, all three steering modes, five HITL flows, slash commands with completion, model
switching that doesn't hang, media upload, live status. Talaria's Phase 3 becomes mostly a
*client* problem — a JSON-RPC codec, an event reducer, a reconnect+`session.resume` ladder — with
almost no server-side invention. Two things fall out for free that we've spent real effort on:
**#21 Tier 2** (the `/api/files/*` family is on the same origin and auth) and **#9** (the deferred
mid-turn model switch replaces the hanging pin). The price: a second long-lived Hermes process on
OJAMD, a dashboard auth provider in `config.yaml`, per-connect ticket minting, and a client that
must own reconnection because upstream's own client doesn't (`gatewayClient.ts:497-508`).

**Riding `/v1/runs` + events.** Stays on `:8642` with the auth we already have, and gets us
approvals and stop. But **it cannot steer** — `_run_agent` builds a fresh agent per request, so
there is no live object to inject into, and no amount of client work changes that. Its event
stream is also *less* recoverable than the WebSocket's: a dropped `/v1/runs/{id}/events`
subscriber destroys the queue. Concretely: this plane can deliver Phase 3 minus the owner's
top-priority feature.

**Riding webhook envelopes.** Durability is its one real advantage, and it's a genuine one for a
phone that backgrounds. Everything else — streaming, steering, HITL correlation, slash — is
invention from scratch, and the `busy_input_mode` machinery in `gateway/run.py:8223` is only
reachable if our adapter is a full platform adapter, which is a much larger commitment than a
webhook receiver.

### 6.3 What we'd give up

- **Our hardened Sessions-API recovery machinery.** It is built against `/chat/stream` SSE
  semantics — retry, backoff, resume, the URLProtocol stub-buffering workarounds. None of it
  transfers to a JSON-RPC WebSocket with a 20 s idle-orphan reaper and an `inflight` snapshot
  instead of an event log. This is not a port; it's a rewrite of the recovery layer.
- **A single auth story.** Today: one bearer header. On `tui_gateway`: login → cookie →
  30 s single-use ticket → WS, re-minted on every reconnect.
- **A single Hermes process.** `hermes serve` runs its own agent, its own MCP discovery, its own
  model metadata. Two runtimes sharing one `state.db`.
- **Loopback's forgiving keepalive.** A gated (non-loopback) bind turns on 20 s uvicorn ws pings,
  which the code itself warns a GIL-heavy turn can outrun (`web_server.py:17577-17590`).
- **A versioned contract.** There isn't one to give up — but moving off HTTP+SSE, where a 404 is
  legible, onto an unversioned RPC surface means breakage arrives as a mis-shaped payload.

### 6.4 The honest shape of the decision

The capability gap is not close: on steering — the stated top priority — `tui_gateway` is the only
one of the three that carries it at all, and it carries it four different ways. The costs are all
*operational and infrastructural*, not capability gaps: a second process, an auth provider, a
reconnect ladder we'd write ourselves, and a recovery layer rewrite. Those are real and they are
Owen's call, not a technical unknown — but note that none of them are "hardening the relay," and
one of them (`/api/files/*`) is the deletion of a planned relay sidecar.

**Two things to settle before committing**, both cheap:
1. **Live probe:** stand up `hermes serve --host <tailnet-ip>` with the basic auth provider on the
   Mac Mini and drive the login → ticket → WS → `prompt.submit` → `session.steer` loop from a
   throwaway client. That falsifies or confirms §3.4 end to end, including whether ATS's CIDR
   exception covers `ws://`.
2. **Provenance:** `git log -S "an iOS / web client" -- tui_gateway/ws.py` on a full clone, to see
   whether that docstring reflects an active upstream intention or a historical aspiration.
