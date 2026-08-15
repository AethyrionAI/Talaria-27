# CLAUDE.md — Talaria

Guidance for Claude / Claude Code working in this repo. This is the living, in-repo source
of truth (the project-knowledge snapshot may lag). `OPEN_ITEMS.md` tracks live issues with
dated notes; closed items live verbatim in `OPEN_ITEMS-ARCHIVE.md` (split by #261,
2026-08-06 — one numbering sequence across both files, nothing ever renumbered); the local
`handoffs/` notes (gitignored) + in-repo `CLEAN_CHAT_PATH.md` carry per-session detail.

## What this is

**Talaria** is a native SwiftUI iOS client for the owner's self-hosted **Hermes** agent.
It is **forked from `dylan-buck/Hermes-iOS`**, but the upstream shell + relay are retained
**only** for sensor ingestion + the `hermes_mobile` MCP tools. **Chat and sensors are
independent paths** — never conflate a relay/connector issue with a chat issue or vice
versa. Owen directs and tests; Claude writes all code + runs infrastructure (Owen does not
write Swift). Device target is **iOS 27 beta**, which requires **Xcode-beta4**.

## Architecture — Clean Chat Path

- **Chat** talks **directly** to the Hermes API server **Sessions API on `:8642`**
  (Bearer `API_SERVER_KEY`). `POST /api/sessions` → id at **`.session.id`**;
  `POST /api/sessions/{id}/chat` (sync) → `.message.content`; `/chat/stream` is SSE.
- **Sensors** go through the dylan-buck shell + **relay `:8000`** + connector, plus the
  **models shim `:8765`**. Independent of chat.
- **Two machines, all over Tailscale:**
  - **OJAMD** (Windows, `100.110.102.59`) — the production host the phone talks to.
  - **Mac Mini M4** (`100.79.222.100`) — always-on dev box: Xcode beta toolchain, the repo, a local
    gateway `:8642` + shim `:8765` for dev.

## SSE taxonomy (verified — Phase 0)

`run.started`, `message.started`, `tool.started`, `tool.completed`, `tool.progress`
(`tool_name:"_thinking"` = reasoning deltas, a **separate channel**), `assistant.delta`
(clean answer chunks in field `"delta"`), `assistant.completed` (final `"content"`),
`run.completed` (full transcript + **token usage**), `done`. **Reasoning is a separate
channel — never folded into the answer** (the old "thoughts fold into content" note is
stale). Token usage rides on `run.completed`, Anthropic-style
`input_tokens`/`output_tokens`/`total_tokens`.

## Agent-generated files (#21)

Files the agent produces land in its **host working dir** (`O:\Hermes\` on OJAMD) and are
**never delivered to the phone**. Sync `/chat` is prose only; the **SSE stream** surfaces a
write as `tool.started` `{tool_name:"write_file", args:{path, content}, preview:path}`
(`tool.completed` is empty). So **text files can be reconstructed client-side from
`args.content`** with no server change (#21 Tier 1). There is **no built-in file/download
endpoint** (`/openapi.json`, `/v1/files`, `/api/files`, `/files` all 404 — re-verified
2026-08-02 on a CURRENT 0.19.1 process; Hermes DOES ship an `/api/files` family but it lives
in the **dashboard app**, `web_server.py` :9119, dashboard auth — a separate app from the
`:8642` api_server the phone speaks; don't mistake dashboard routes for chat-plane routes,
see #21/#223). Durable host-side
serving for binaries / other tools (#21 Tier 2) must live in **our relay sidecar**
(`O:\Hermes\Talaria\relay`) — **never a patch to Hermes core**: `curl install.sh | bash`
replaces `~/.hermes/hermes-agent` and wipes core edits, while `config.yaml`/`.env`/skills/
sessions persist.

## Model switching (gateway-only — #223 Lane 5, 2026-08-04)

**The shim is RETIRED from the model path.** Picker `apply()` is instant by design —
"no shim POST, no session pin, nothing to await" (`ModelsSettingsScreen.swift`); the
catalog comes from the gateway (`/api/model/options` per the route table) and the pick
persists client-side (the client's per-turn lock). The OJAMD `TalariaModelsShim`
service is **STOPPED *and* DISABLED — settled 2026-08-10, re-verified live
2026-08-15.** ✅ **S2, and the prediction fired before the fix did:** this
paragraph used to warn that `StartType: Automatic` meant "a reboot RESTARTS
it." The box rebooted **2026-08-09 15:39:40**, the shim came back up
listening on `:8765` with nobody calling it — **exactly as predicted** — and
Owen stopped it by hand three minutes later, then set StartType to Disabled.
Its duplicate boot/logon scheduled task (the same component supervised twice)
was **deleted 2026-08-15**, along with the `HermesGateway` and
`TalariaConnectorWatchdog` task residue. **On OJAMD, "retired" now describes
the configured state, not merely the running one.** Keep the general lesson
even though this instance is discharged: *stopped ≠ disabled*, and a service
left on `Automatic` is a retirement that expires at the next boot. **And the MAC
shim is not stopped at all (probed 2026-08-09): `tools/models-shim/shim.py` runs
under the hermes venv, up since Jul 24, answering 401 on `:8765`.** Harmless —
the app provably never calls it (`ModelsShimClient` deleted from the tree) — but
"the shim is retired" describes the MODEL PATH, not the processes: one host will
resurrect its listener on reboot and the other never stopped its own. The old dual-write
description that stood here —
shim POST → gateway session pin, 37s hangs, shim-flagged CONFIRM — was deleted with
Lane 5; see #223 Lane 5 and archived #9, and **read the code, not this file's summary
of it**. (This section was false from 2026-08-04 until the 2026-08-06 reconciliation
audit caught it — the ATS-lines shape again: the always-loaded rules file prescribing
a falsified mechanism while the tracker was right.)

## OJAMD services (windowless, reboot-proof)

> **⚠️ STATE AS OF 2026-08-15 — most of what this section describes is now
> STOPPED, DISABLED, or DELETED. Read it as the map of a tier being retired,
> not of a tier that is running.** Live-verified on the box that day:
> `HermesMobileRelay` and `TalariaModelsShim` are both **Stopped + Disabled**;
> all three scheduled tasks (`HermesGateway`, `TalariaModelsShim`,
> `TalariaConnectorWatchdog`) are **deleted**; `Hermes_Connector.cmd` is
> **removed from the Startup folder** (backed up to
> `<HERMES_HOME>\retired-supervision-20260815\`); and
> `mcp_servers.hermes_mobile` is **`enabled: false`**, with zero
> `hermes-mobile` processes left anywhere on the box. **The gateway is the
> only piece of this still running.** Full inventory + retirement order:
> `planning/reports/2026-08-10-ojamd-supervision-inventory.md`; the decision
> and its evidence are OPEN_ITEMS #346, the lane is #271.

- **Relay `:8000`** — `HermesMobileRelay` (NSSM service; `nssm.exe` at `O:\Hermes\nssm\`;
  uvicorn from `O:\Hermes\Talaria\relay`). **Stopped + Disabled since 2026-08-10**;
  the service registration and the DB/logs remain.
- **Shim `:8765`** — `TalariaModelsShim` (**NSSM service**, not a scheduled task).
  **Stopped + Disabled since 2026-08-10.**
- **Gateway/API server `:8642`** — **NOT a service and NOT a scheduled task.** It runs as
  Owen's user process (`hermes gateway run`) and answers ~15–20s after start.
  **S1 — how it STARTS, which this file never said: `Hermes_Gateway.vbs` in the
  user Startup folder** (`%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\`),
  which presets `HERMES_HOME`, `PYTHONIOENCODING`, `HERMES_GATEWAY_DETACHED=1`,
  `VIRTUAL_ENV` and `PYTHONPATH`, then runs the venv **`python.exe`** windowless
  (window style 0) — **not `pythonw.exe`** as this file used to imply. **⛔ NEVER
  delete that .vbs: it is the chat plane's autostart, and it is the one thing in
  this whole section that must survive the retirement.** Relaunch by hand with
  `wscript.exe "<that path>"`.
  **It is a TWO-PROCESS chain and the PORT OWNER IS THE CHILD:** the venv python
  re-execs a child on the bundled runtime (`.hermes-runtime\...\python.exe`), and
  that child owns `:8642`. Killing only the port owner leaves the parent alive —
  **stop the parent first, then the child**, and confirm zero survivors matching
  `hermes_cli.main gateway run` before relaunching.
  **Do NOT `Start-Service HermesGateway`** — no such service exists, and its absence does
  **not** mean chat is down. Check the port owner instead:
  `Get-NetTCPConnection -State Listen -LocalPort 8642 → OwningProcess`. The API server is a
  **gateway adapter**, not standalone — `hermes gateway run` serves the API server + all
  enabled platforms (Discord, etc.) in **one** process. ~~Discord is one token away.~~
  **S6 — Discord is already CONNECTED on OJAMD** (`gateway_state.json` and
  `/health/detailed` both report `discord: connected`; 4 of 5 platforms connected,
  2026-08-10 and re-verified 2026-08-15). It is through the door, not one token
  away — which also means a gateway bounce takes Discord down with chat.
- **Connector** — a plain bat-launched process (`O:\Hermes\Talaria\scripts\start-connector.bat`,
  `PYTHONUTF8=1`). **`connector\logs\connector.log` is DEAD (last write 2026-07-02) — the
  live connector signal is `O:\Hermes\Talaria\logs\connector-watchdog.log`** (found
  2026-08-03; where the process's stdout goes now is unlocated). Supervision gap is
  **OPEN_ITEMS #113**. `restart-relay.ps1` in
  `C:\Users\Owen\.hermes\scripts\` does `Restart-Service HermesMobileRelay` then the bat.
  ~~**⚠️ This shape is OJAMD-ONLY (found 2026-08-09): on the Mac the connector is an MCP
  stdio CHILD of the gateway**~~ **S5 — CORRECTED 2026-08-10: OJAMD ran BOTH shapes at
  once.** The stdio-child shape (`connector\.venv\Scripts\hermes-mobile-mcp.exe`,
  registered in `config.yaml` as MCP server `hermes_mobile`) is **not Mac-only** — OJAMD
  carried it *alongside* the bat-launched process. So "two hosts, two stories" was wrong;
  it was two shapes on one host. **All of it is now MOOT ON OJAMD (2026-08-15):**
  `mcp_servers.hermes_mobile` is `enabled: false` and there are **zero** `hermes-mobile`
  processes on the box (#346). The Mac still runs its own copy.
  **The trap that outlives the correction: `config.yaml` takes effect PER PROCESS, and
  this box has THREE readers of it** — the gateway, the Hermes **Desktop app's own
  backend** (`hermes serve --host 127.0.0.1 --port 0`, a child of `Hermes.exe`), and the
  CLI. Disabling an MCP server bites the gateway on its next restart and the desktop
  backend only when the desktop app itself relaunches. Verify per process, never once.
- **OPS:** `Start-Service HermesMobileRelay` / `Start-Service TalariaModelsShim` need
  elevation (Owen pastes). **Updates: Owen runs bare `hermes update` — that is his actual
  practice and it's fine** (the `hermes-update-safe.ps1` script exists but he has never
  once used it; corrected 2026-08-04 on his word). Updates are safe BECAUSE we keep zero
  core edits. The real invariants: **restart the gateway after any update** (a running
  process serves stale imports forever), and **verify by process start time, not version
  string** — head `aec3318` shipped still calling itself 0.20.0, so `/health` version
  proves nothing about which code serves. An interrupted update can leave a half-install
  (git at head, `venv/bin/hermes` missing) — finish it with the venv's own
  `pip install -e ~/.hermes/hermes-agent`, don't reinstall. **Do NOT run
  `hermes gateway install` on Windows** (creates a conflicting login-only task).
- **⛔ DO NOT SET "API server model name" (Hermes desktop → Messaging → API server →
  Advanced) — it is a ROUTING SENTINEL, not a display label, and changing it on a host
  with existing sessions triggers #241 on every one of them.** Found 2026-08-09 from
  Owen's screenshot of that pane. **Leave it EMPTY** (it is currently unset, so the
  default applies and we are fine).
  - The UI describes it as *"Model name advertised on `/v1/models`… useful for
    multi-user setups with OpenWebUI"* — which reads purely cosmetic. **It is not.**
    Upstream's own docstring (`api_server.py:379`) says the advertised name is
    *"a stable virtual model … treat that alias as **use the gateway default**."*
  - **The chain:** `_resolve_model_name` (`:1644`) picks explicit override →
    profile name → `"hermes-agent"`, and caches it as `self._model_name`. Session
    creation persists it when the client sends no model —
    `model = body.get("model") or self._model_name` (`:3397`) — and Talaria's
    `createBareSession` posts an empty body, so **every session we create stores
    that literal string.** The routing gate then tests
    `if not route and model and model != self._model_name` (`:2345`): match ⇒
    `route_source: "global"` (the default, correct); **mismatch ⇒
    `route_source: "raw_request"` for a model literally named `hermes-agent`,
    which no provider has** ⇒ 404 ⇒ and per #241 that 404 reaches the client as
    **HTTP 200**. Seven further sites pass it as `virtual_model`.
  - **Why the hazard is real rather than theoretical:** the sentinel and the
    stored value are captured at different times. Rename the profile, set this
    field, or point the phone at a host whose name differs, and every
    previously-created session's stored `model` stops matching. Worse, the
    docstring notes **Hermes-native endpoints (session chat and `/v1/runs`) ALWAYS
    honour a bare `model` with no `provider`** — so there is no safety net on
    exactly the two planes Talaria uses.
  - **Live confirmation, and it was in plain sight all session:** every
    `hermes-ojamd` reply carried
    `runtime: {provider: "kimi-coding", model: "hermes-agent", route_source: "global",
    requested: {provider: "", model: ""}}`. Real provider, self-name as the model,
    `global` because the sentinel still matches. **We are safe only because nobody
    has changed that name.**
- **Diagnostic discipline:** verify OJAMD against live state — port listeners, DB rows,
  relay logs — never by text-matching a project-knowledge snapshot, which lags.
- **🚨 THE `hermes-ojamd` MCP CAN FABRICATE OUTPUT ON THE FAILURE PATH (found
  2026-08-09).** It is a real agent with a real shell, and commands that SUCCEED
  return real output — but a command that FAILS can come back as invented text
  instead of an honest error. Observed: asked for a git HEAD on that host it
  produced `1d0c7f8e…`, which GitHub rejected as a nonexistent commit; told that
  was fake, it produced `a1b2c3d4…`. **A confabulated answer is indistinguishable
  from a real one by shape alone.**
  - **So plant a canary in every probe.** Include something with a
    externally-checkable answer — `Get-Date -Format "yyyy-MM-dd HH:mm:ss"` is
    ideal, because a fabricating model does not keep a clock that tracks real
    elapsed time across two probes. Ask the load-bearing question **twice, in two
    phrasings**, and instruct it to answer **"CANNOT RUN"** rather than
    reconstruct. The shim StartType finding above survives exactly that test.
  - **Do not accept a host fact from this MCP as evidence without a canary**, and
    never accept one for a path or repo that may not exist on that box — that is
    the failure path where fabrication lives. Route anything load-bearing through
    Owen or a direct probe instead.
  - **Consequence for the 2026-08-09 sweep:** OJAMD's commit and its `:8642` route
    table are **UNVERIFIED**, not merely unchecked — and OJAMD is the host the
    phone actually talks to.
- **🔐 LIVE-INSTALL EXPERIMENTS NEED AN EXPLICIT PER-EXPERIMENT GO (Owen approved
  2026-08-06: "that's a good edition").** Anything that MODIFIES a live Hermes install —
  editing a loaded plugin file, adding a temporary event type or command, changing
  `config.yaml` — gets Owen's go for THAT experiment, even when it is temporary and
  reverted. **Read-only probes and throwaway loopback servers (`hermes serve --host
  127.0.0.1 --port <spare>`) do NOT** — those are free. Restarting the Mac gateway is
  routine (launchd-supervised, `kill` = clean respawn), but restarting it *to load
  experimental code* is part of the experiment and rides the same gate. Why: the
  2026-08-06 Escape-B probe put a temporary event type into the live `envelope.py` and
  bounced the gateway twice under a dispatch that announced-but-did-not-await Owen's go;
  cleanup verified clean, but the authorization was assumed rather than held.
  **Time-boxed exception, 2026-08-06 only: "you are cleared for modifications, especially
  if you're removing it afterwards."** That clearance expires with the day; the rule above
  is the standing state.
- **⛔ DO NOT HARDEN THE RELAY OR THE CONNECTOR (Owen, standing, 2026-08-02).**
  *"Every time we harden something on the connectors, it makes a new hoop to jump
  through to make it update. I beg not to harden, and it gets more and more every
  time. I would like to not harden additional things on the relay. We're trying to
  get rid of those extra things after all."* **Every hardening buys reliability in a
  component with a planned end-of-life (#223) and pays for it in permanent update
  friction** — the friction compounds and the benefit expires. The direction is
  DELETION, not robustness.
  - **Fix app-side instead, and this is not a consolation prize** — #133/#143's
    duplicate-push root cause was fixed entirely in the app (durable installation
    identity) with **zero relay change**, and the relay turned out never to have been
    at fault. That is the shape to reach for.
  - **Declined under this rule:** #188's watchdog half (per-component liveness
    probes), #133's partial unique index on active `apns_token`, and anything of that
    family. They stay FILED as findings — a declined fix is not a refuted one — but
    do not build them.
  - **Still allowed, because they are not hardening:** one-time data chores
    (deactivating junk rows, #144's shape — deactivate, never delete, keep a
    rollback), read-only measurement, and DELETING relay surface once the gateway
    or the app absorbs it.
  - **If a relay change ever looks unavoidable, raise it with Owen as a decision
    rather than building it** — the bar is "the user is harmed now and no app-side
    fix exists," not "this would be more correct."
- `HERMES_HOME` = `C:\Users\Owen\AppData\Local\hermes`; shim token at
  `C:\Users\Owen\.hermes\talaria_shim_token`; gateway launchers at
  `C:\Users\Owen\.hermes\scripts\`. Owen runs box-side commands in **PowerShell** (`curl`
  is an alias there — use `Invoke-RestMethod` or `curl.exe`).

## Auth

Shim accepts its dedicated token **or** the Hermes `API_SERVER_KEY` (dual-token, #14) — no
shim-token paste after a re-pair. **`API_SERVER_KEY` lives in HERMES_HOME's `.env`
(`C:\Users\Owen\AppData\Local\hermes\.env`, 64 chars) — `C:\Users\Owen\.hermes\.env` does
NOT exist** (corrected 2026-08-03 by an OJAMD-side session; `~/.hermes/` holds only
`talaria_shim_token`, `logs\`, `scripts\`, `desktop-attachments\`). Dual-token on OJAMD
works only because `run-shim.cmd` injects the key from HERMES_HOME's .env — `shim.py`'s
own `~/.hermes/config.yaml` fallback is dead on that box.

## Hard-won gotchas (do not relitigate)

- **`xcodegen generate` is mandatory** after adding/removing Swift files (explicit source
  listings, not synchronized folder groups).
- **NEVER claim a `:8642` route from a `web_server.py` grep — read
  `gateway/platforms/api_server.py`'s `_http_route_table()`, which is the whole list.**
  **This rule exists because it was learned the hard way on 2026-08-02** (the #21
  paragraph above and the two-web-apps memory were both written that day, at 04:22, by the
  investigation session that caught it — they did *not* predate the mistake): an
  `/api/files` + `/api/model/*` "discovery" was filed into three tracker items, a dispatch
  brief, and an external audit before live probes killed it. The dashboard app (`hermes_cli/web_server.py`,
  **:9119**, dashboard auth) and the api_server the phone speaks (**:8642**) are different
  apps with different route tables; the dashboard's 129 routes are not the gateway's.
  **OJAMD self-updated to Hermes v0.20.0 on 2026-08-03 ~19:52 — the table below was
  verified on 0.19.1; re-verify by live probe before any NEW route claim on 0.20.0**
  (0.20.0 probes so far: `/api/model/options` 200, `POST /api/sessions/{id}/model` exists,
  `/v1/models` returns the single `hermes-agent` entry, `/api/model/*` variants still 404 —
  findings §4, 2026-08-03). **The RUNS family is now live-verified on 0.20.0 (2026-08-07,
  #283 slice 3A), on the Mac end-to-end and route-probed on OJAMD — do not re-probe it:**
  `POST /v1/runs` (202 + `run_id`) · `GET /v1/runs/{id}/events` (SSE) ·
  `GET /v1/runs/{id}` (status + `output` + `usage`, 1h TTL) ·
  `POST /v1/runs/{id}/stop` (a REAL hard interrupt — device-proven, the host logged
  `exit_code 130` / `interrupted_by_user` — **and, on a run PARKED on an approval, a clean
  `deny`**: `is_interrupted()` inside the approval wait resolves it rather than hanging
  the window out — `tools/approval.py:3695-3703` at `3dcbe9001`; #304, 2026-08-09).
  **Three behaviours to know before designing
  against them:** the events stream's frames are `data: {json}` with the event name INSIDE
  the JSON — there are **no `event:` lines**, unlike `/chat/stream`; a run carrying an
  existing `session_id` **WRITES its turns into SessionDB but never READS them** (history
  must ride the request, and a missing history does NOT error — the agent answers
  plausibly from long-term memory instead); and a freshly created, never-used session
  returns **200 with an empty list** on `/api/sessions/{id}/messages`, not 404.
  **The APPROVAL family (`approval.request` on the events stream +
  `POST /v1/runs/{id}/approval`) has three behaviours of its own (#304, 2026-08-09 —
  code-read at `3dcbe9001`, wire-proven 2026-08-05 for the once/expiry arms):**
  the CHOICE SET rides each `approval.request` frame (`choices` is computed per request —
  four-choice, three-choice, and `smart_denied` two-choice arms all exist; **a hardcoded
  four-button card is wrong**); **`command` is not always a command** (MCP elicitation
  reuses the field for its consent MESSAGE — `pattern_key: "mcp_elicitation"`, no
  `allow_permanent`); and **the status object never carries the question** — a timed-out
  approval leaves `GET /v1/runs/{id}` reading `waiting_for_approval` for the rest of the
  run, so only a stream frame may raise a question and only a 409 `approval_not_pending`
  settles that the window closed. The ANSWER channel is stream-independent (a client that
  lost the stream can still POST a deny and it lands).
  **✅ RE-VERIFIED 2026-08-09 — THE TABLE BELOW IS CURRENT. The 0.20.0
  re-verify warning is DISCHARGED.** `_http_route_table()` is **byte-identical
  (37 rows)** between the commit serving on 2026-08-02 and upstream HEAD
  `62431364e`; all 37 routes were live-probed read-only and **not one 404'd**.
  No route added, removed, or changed. Full evidence:
  `planning/reports/2026-08-09-route-table-reverify.md`. Every dependent
  question settled the same way: **no `/api/config`** (so approval-mode
  SELECTION stays dashboard-only), **no `/api/files`**, `/api/model/options`
  still the only `/api/model/*`, `/v1/runs` unchanged, and
  `POST /api/sessions/{id}/model` present with the same shape.

  **⚠️ ONE THING THE TABLE HAS ALWAYS OMITTED: the `/p/{profile}` multiplex
  mirror.** Every route below is **dual-registered** under a profile prefix —
  live-confirmed, and undocumented here since 2026-07-16. Read the table as
  "each of these, plus its `/p/{profile}/…` twin."

  > **🔴 THE HAZARD THIS RE-VERIFY ACTUALLY EXPOSED — read it before trusting
  > any live probe.** On 2026-08-09 the Mac's `~/.hermes/hermes-agent`
  > **auto-updated at 01:21 while this session was running**, which is why two
  > agents read two different heads an hour apart and neither was wrong. The
  > reflog is the only honest record:
  > ```
  > ceebb21dd  2026-08-09 01:21  merge origin/main   ← checkout head
  > 3dcbe9001  2026-08-08 23:14  reset
  > d408fdbfc  2026-08-08 19:30  reset
  > 01a1037d1  2026-08-05 19:31  merge origin/main   ← what the LISTENER serves
  > ```
  > ~~**The running listener (PID from Aug 7, uptime >1d) serves `01a1037d1`
  > from Aug 5 — four days and three updates behind its own checkout.**~~
  > Routing does not diverge (identical table), but BEHAVIOUR does: the
  > running process still 400s `PATCH /api/sessions/{id}` with `pinned`, while
  > the installed head persists it. **Both report `0.20.0`, so the version
  > string cannot see any of this.**
  >
  > **✅ THAT SPECIFIC DRIFT IS CLOSED as of 2026-08-09 14:12** — the device
  > sitting restarted the Mac gateway, so the listener is now **PID 94227,
  > started 14:12:23, serving the checkout head (`ceebb21dd`)**. The Aug-5
  > behaviour described above is no longer what answers `:8642` here. **The
  > LESSON is unchanged and still load-bearing** — pin the running code by
  > reflog-vs-start-time, never by `git log -1` — only this instance of it is
  > discharged.
  >
  > **⚠️ AND THE RESTART ITSELF EXPOSED A NEW HAZARD, observed live the same
  > minute — a gateway restart can leave the box HEADLESS.** launchd respawned
  > **6 s** after the old API server released, the socket was not free yet, and
  > the host logged:
  > ```
  > 14:09:31  [Api_Server] API server stopped
  > 14:09:37  ERROR Could not bind 0.0.0.0:8642: [Errno 48] address already in use
  > 14:09:37  ✗ api_server failed to connect
  > ```
  > The gateway then ran on with a **healthy PID, a happy `agent.log`, and no
  > chat plane for two full minutes** until a second restart was issued. **This
  > is #264's ops rule happening rather than being predicted:** after ANY bounce,
  > verify the LISTENER (`lsof -nP -iTCP:8642 -sTCP:LISTEN`), never the process
  > — and a `kill`-then-respawn is NOT reliably self-healing, so budget a
  > verify-and-maybe-restart-again step into any procedure that bounces it
  > (`DEVICE-PASS-RUNNING-LIST.md` §Z8 does exactly this).
  >
  > **Pin the running code by REFLOG, not by `git log -1`:** match the
  > listener's start time (`ps -p $(lsof -nP -iTCP:8642 -sTCP:LISTEN -t) -o
  > lstart=`) against reflog timestamps. `git log -1` tells you what the NEXT
  > restart will serve, which is a different question and is the one people
  > answer by accident.
  >
  > **Also note `.git/shallow` is present** (log depth 31) — a reported "31
  > commits of drift" was that floor, not a measurement. Diff against a fresh
  > clone, never against this checkout's history.
  >
  > ~~**NOT verified: OJAMD's table** — and that is the host the phone actually
  > talks to. The read-only MCP has no route probe. Treat OJAMD parity as
  > ASSUMED until someone probes it directly.~~
  >
  > **✅ S3 — DISCHARGED 2026-08-10: OJAMD's table WAS probed directly**, from a
  > session running on the box (no MCP, so no fabrication caveat). All 37 rows
  > live-probed, plus the `/p/{profile}` mirror. **Parity is now MEASURED, not
  > assumed.**
  >
  > **⚠️ But OJAMD is on 0.20.1, not 0.20.0 — recorded 2026-08-15, and nothing
  > in this file or the tracker knew it.** Install head
  > `165c889e5b4277b56dadd42949a4112c1e6175a6`, `v0.20.1 (2026.8.13)`, pinned by
  > reflog-vs-start-time (head 14:14:22, listener 15:09:08 ⇒ no drift). **Any
  > note reasoning from "OJAMD is 0.20.0" describes a host that no longer
  > exists.**
  >
  > **`/v1/capabilities` is the cheap way to answer "is that route real?"** —
  > read live on 0.20.1, it self-describes the endpoint map and confirmed
  > `run_approval_response: true` (previously only INFERRED from source). It also
  > names **`POST /v1/runs/{run_id}/steer`, a route this table has never
  > listed** — so treat the list below as verified-but-not-exhaustive, and probe
  > `/v1/capabilities` before concluding a route is absent.
  > (`planning/reports/2026-08-15-ojamd-auth-probe-results.md`.)

  **The complete `:8642` table, verified 2026-08-02 against a
  fresh 0.19.1 process and RE-VERIFIED UNCHANGED 2026-08-09 against upstream
  HEAD `62431364e`:**
  `/health{,/detailed}` · `/v1/health` · `/v1/models` · **`/api/model/options` (the ONLY
  `/api/model/*` route — there is no `/info`, `/recommended-default`, `/auxiliary`, or
  `POST /api/model/set`)** · `/v1/capabilities` · `/v1/skills` · `/v1/toolsets` ·
  `/api/sessions*` (incl. `chat`, `chat/stream`, `fork`, `messages`, and
  `POST /api/sessions/{id}/model` = the session pin) · `/v1/chat/completions` ·
  `/v1/responses*` · `/api/jobs*` · **`/v1/runs*` incl. `POST /v1/runs/{id}/approval`
  and `/stop`** · `/api/platforms/{p}/events` · `/api/cron/fire`. **No `/api/files`, no
  `/api/fs`, no `/api/config`, no `/api/chat/image-upload` — those are dashboard-only.**
- **A stale gateway process is a REAL hazard, but it was NOT the cause of those 404s.**
  A long-lived `hermes gateway run` imports its modules at start, so updating Hermes leaves
  the old code serving until a restart — on 2026-08-02 the Mac listener was PID 28104 from
  **Jul 29** under a **0.19.1** install, 3d 14h uptime, which is worth knowing on its own.
  **But restarting it changed nothing**: the same routes 404'd from a 68-second-old 0.19.1
  process, because they were never on this plane. **Check the process when versions are in
  question — `ps -p $(lsof -nP -iTCP:8642 -sTCP:LISTEN -t) -o lstart=,etime=` — and check
  the route TABLE when routes are in question. Reaching for the first explanation that fit
  is what cost a day here.**
- `os_log` interpolations need `privacy:.public` or they redact in Console.app; emoji can
  also trigger redaction. Console.app's default view suppresses `.info` — use `.notice`+ for
  diagnostics that must be visible. `TalariaLog` gates verbose diagnostics behind
  `UserSettings.verboseLogging` (the Developer screen toggle).
- **iCloud Private Relay** intercepts HTTP to Tailscale IPs and blocks sensor delivery —
  disable it.
- **HealthKit** needs an explicit in-app `requestAuthorization()` on every
  `SensorUploadService.start()` — Settings grants alone don't suffice.
- `Restart-ScheduledTask` doesn't exist in PowerShell 5.1 — use `Start-ScheduledTask`.
- `mdfind -name` beats `find` for locating files on the Mac Mini.
- **#24f is DEAD — never cite it as a cause.** The relay is DB-backed
  (`O:\Hermes\Talaria\relay\hermes_mobile.db`); there is no JWT signing secret and no
  in-memory device registry, and the registry survives restarts (verified across 4+ relay
  restarts). The live transport concern is **#54** (connector WS reconnect / nonce).
- **ATS is already scoped, and `NSAllowsLocalNetworking` is a FALSIFIED "fix".**
  `NSAllowsArbitraryLoads` was removed by **#166b** (PR #138, commit `d3c962d`,
  2026-07-22) and replaced with
  a range-scoped `NSExceptionDomains` entry keyed by the Tailscale CGNAT CIDR
  `100.64.0.0/10` (`project.yml`). The CIDR-as-domain-key form looks invalid but was
  adopted only after a four-arm controlled experiment (`OPEN_ITEMS.md` #166b, 2026-07-22)
  run **inside the app test host on the shipping toolchain — sim, not device**, which is
  what makes it trustworthy: `URLSession` there obeys the real plist, whereas `curl` does
  not exercise ATS at all. Arms: no exception → tailnet HTTP blocked −1022;
  **`NSAllowsLocalNetworking` → still blocked, CGNAT is not "local" to ATS**; the CIDR
  form → both gateways allowed; an outside-range negative control (`1.1.1.1`) → still
  blocked, so the exception does not leak globally. **So do not "narrow to
  `NSAllowsLocalNetworking`" — that arm was tested and it breaks every tailnet
  connection the app makes.** Nothing here is owed
  before submission. Consequence to know: hosts outside `100.64.0.0/10` — LAN IPs,
  MagicDNS names — have **no** exception and are ATS-blocked app-wide. `README.md` and
  `SECURITY.md` carry the same evidence; this line was wrong from 2026-07-22 until
  2026-08-01 and its bad advice propagated into a device-pass note before an external
  audit caught it. **Read `project.yml`, not a summary of it** — and note that writing
  *this* correction still produced two wrong borrowed facts (a sim experiment called
  "on-device", and 07-23 for a change git dates 07-22), both caught only by going back to
  the artifact a second time. Dates come from `git log`, not from a tracker header.

## Build / tooling

- **Xcode-beta4** (`/Applications/Xcode-beta4.app`, Xcode 27.0 build 27A5228h) is the
  standard toolchain for iOS 27 targets (per Owen, 2026-07-20; verified same day — full suite
  931/84 green on its SDK); release Xcode can't build iOS 27.
  `DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer` in every shell.
  `Xcode-beta.app` and `Xcode-beta3.app` were **deleted 2026-07-24** — beta4 and release
  Xcode are the only copies on disk. Command Line Tools 27 beta 4 is installed and
  `xcode-select` points at beta4, but CLT ships no iOS SDK and no `xcodebuild`, so the
  `DEVELOPER_DIR` export is still mandatory. Sim runtimes kept: **iOS 27.0 (24A5390f)** and
  **iOS 26.5 (23F77)**; seeds 24A5355p / 24A5380g were deleted the same day. The pinned sim
  UDID survived both the beta-4 runtime rebind and the seed prune — no re-pin needed.
  Team `DNL25ZFSD2`. DerivedData for **this** repo is
  `Talaria-gzpowyfsuofejnbsytskngrskzkm` — corrected 2026-07-30. The long-documented
  `Talaria-bkmofmhhchhruzcdudrizbbblrae` belongs to the OLD `~/Documents/Claude/Talaria`
  checkout (verified via each dir's `info.plist` → `WorkspacePath`), so purging it to
  clear a stale build silently does nothing here. **Every worktree gets its own hash** —
  resolve it from `info.plist`, never from memory:
  `plutil -extract WorkspacePath raw ~/Library/Developer/Xcode/DerivedData/Talaria-*/info.plist`.
  **`test-without-building` will happily re-run a stale `.xctest`** and report a green
  suite at the OLD test count (this cost a bogus "verified green" on 2026-07-30) — after
  editing tests, confirm the reported count MOVED, and if it did not, purge
  `<dd>/Build/Intermediates.noindex` and run plain `test`.
- **THE GATE — run `scripts/mac/lane-gate.sh` before opening any PR.** One command;
  runs the Debug suite (units + XCUITest) **and a Release build**, and requires a
  POSITIVE success marker from each. `--release` / `--suite` narrow it. Release is in
  there because #218: `main` could not build in Release for two days and every check
  we had was Debug, so 1461 green tests proved nothing. **The gate is verified to
  fail** — the #218 bug was re-injected and it caught all three errors.
- **CLI compile check:** `xcodebuild -project Talaria.xcodeproj -scheme Talaria
  -configuration Debug -destination 'generic/platform=iOS Simulator' build
  CODE_SIGNING_ALLOWED=NO`. Long builds exceed the 4-min MCP cap — run backgrounded
  (`nohup … &`) and poll the log. The gate script is the same trap: it takes minutes,
  so background it and poll rather than blocking a tool call on it.
- **Device deploy:** Xcode MCP bridge `RunProject(tabIdentifier:"windowtab1")` builds +
  installs + launches on **whoGoesThere** (iPhone, iOS 27 beta). `GetConsoleOutput` reads
  device logs. The bridge can't drive physical-device UI. After `xcodegen` regen, RunProject
  may hit a "project modified on disk" modal — stop app / dismiss / retry.
- **OTA deploy over Tailscale (proven 2026-07-27)** — THE remote deploy path when the phone
  is not on the home LAN (Owen at work). `scripts/mac/ota-stage.sh <branch>` on the Mac
  Mini: worktree → headless archive → dev-signed export (`method: debugging`, automatic
  signing, unlocked login keychain) → stages ipa + manifest into
  `~/.talaria-ota/serve_root`. Phone installs from Safari at
  `https://owens-mac-mini.tail5663a6.ts.net` (itms-services; real TLS via
  `tailscale serve --bg 8477`, which persists in tailscaled state; the
  `com.talaria.ota-http` LaunchAgent keeps the local file server alive across reboots).
  Dev-signed **upgrade-install in place** — same bundle id, app data persists. Install-only:
  no debugger attach, no console. **Do not relitigate Xcode-native wireless over the
  tailnet:** connect-by-IP was removed from Xcode entirely (Apple DTS, forums thread
  805833), CoreDevice discovery needs LAN multicast Tailscale can't carry, and the phone's
  lockdown (62078) + RemotePairing ports do not listen on its Tailscale interface — so
  pymobiledevice3-over-tailnet is equally dead (verified 2026-07-27).
- **Desktop Commander** is the primary Mac Mini filesystem/shell/git tool. A persistent
  `zsh -l` (`start_process`) keeps state across `interact_with_process` calls. DC's
  `read_file`/`edit_block` UI tools have hung — prefer `cat`/`perl`/`python3` heredocs in
  the persistent shell for reads + edits.

## Design system

**Theme system (2026-07-03, `design/THEME_SYSTEM_PLAN.md`):** a THEME (Deep Field /
Solar Forge / Terminal / Paper Tape) owns the whole color environment; the ACCENT is one
of three persisted slots (`cyan`/`amber`/`violet` raw values — never rename) that each
theme re-interprets, slot `.cyan` always = the theme's hero hue (Cyan Arc / Forge Amber /
Phosphor Green / Tracker Red). **All color values live in
`Shared/ThemePaletteCore.swift`** (compiled into app + widget targets); `ThemeRuntime`
(theme/accent/glow/grid/reduce-motion) resolves them live. Deep Field × cyan is
byte-identical to the pre-theming app (guarded by `DesignThemeTests`). Paper Tape is
light: root `preferredColorScheme` follows `theme.isLight`, and `hudGlow` multiplies by
`palette.glowScale` (≈0.15 on paper). **Data-driven since #49 (2026-07-05):** palettes are
`ThemePaletteDefinition` entries in `ThemePaletteCatalog` (same file) — resolution is a
catalog lookup, Terminal's accent pin (#12) is `lockedAccentSlot` data, `AppearanceTheme`
is a thin id (names from `ThemeCatalog.displayName`, `isLight`/orb/texture from palette
data), and a new theme = one `ThemeID` case + one palette definition + one
`ThemeDefinition` (+ a `WidgetTheme` case for the widget edit sheet) — no switch-arm
edits. Xcode build + `DesignThemeTests` run still owed on the Mac (see the handoff doc).

Tokens in `Talaria/Core/Design.swift` — note the **two** namespaces:
- `Design.Brand.*` — `accent`/`accentBright`/`accentDeep` (theme-resolved; Deep Field
  cyan #54E6F0/#CDF8FB), **`forge`** warning (amber on Deep Field).
- `Design.Colors.*` — `foreground`/`foregroundBright`, `mutedForeground`, `dimForeground`,
  `danger`, `dangerBright`, `surface`, `hairline`/`strongBorder` (ex-`cyanHairline`/
  `cyanBorder`), `accentTint(_)`, `scrim`, `screenGradient`, `drawerGradient`.

HUD components in `Talaria/Core/HUD/`: `MonoLabel`, `StatusPip`, `GlowButton` (accent —
build tinted pills for forge/danger), `GhostButton`, `ReactorOrb`
(`.minimal`/`.standard`/`.onboarding`/`.voice`; drawing re-skins per theme),
`HUDScreenBackground` (gradient + `ThemeTextureView` + `GridOverlay`
lines/dots/rules), `SettingsScreenHeader`, `GlassCircleButton`; modifiers `.hudPanel` /
`.hudGlow` / `.continuousRotation`; `Color(hex:opacity:)` (defined in
`Shared/ThemePaletteCore.swift`). Widgets pick a theme per instance
(`WidgetTheme`, default Match App via `HermesWidgetData.appearanceTheme` — kept in
lockstep across BOTH `HermesWidgetData.swift` copies).

## Conventions

- SwiftUI + async/await; `@Observable` models, `@Bindable` in views; four-space indent;
  `PascalCase` types/files, `lowerCamelCase` members; no force-unwraps on network code
  (Hermes nests — `.session.id`).
- **Real data only** in UI — show `"—"` where a value isn't knowable; no mocked toggles.
- **Verification-first:** honest corrections over confident guesses; mid-session corrections
  are normal and valued. The **"Questions for Owen"** header surfaces decisions.
- Issues tracked in `OPEN_ITEMS.md` (dated update notes; closed items move verbatim to
  `OPEN_ITEMS-ARCHIVE.md` — see #261); session continuity in
  the local `handoffs/` notes (gitignored) + `CLEAN_CHAT_PATH.md`.
- **THE CLOSE-OUT RULE (2026-08-06, from the reconciliation audit; pending Owen's
  ratification but follow it meanwhile):** a lane does not close until every entry,
  doc, and CLAUDE.md line whose text its result FALSIFIES is corrected in the same
  commit — #218's promoted-clause discipline applied to prose. Corrections go
  UPSTREAM, to the stale claim's own home (a dated supersession note at minimum),
  never only downstream of it. Routing decisions and named-but-unstarted work get
  tracker numbers the day they are made — "a phase name is not a filing" (#268);
  a handoff is where a decision happened, not where it lives.

## Measurement discipline (#215 — the rule that cost the most to learn)

**A battery rate is a PRODUCTION rate only if the row was ROUTED.** Production
classifies every turn first (`routeNeedsDeviceTool`), and a turn routed toolless
gets **no belt at all**. An unrouted cell arms every trial by construction, so on
any prompt the router would send toolless it is measuring a configuration the app
never enters.

- The dozens of **grab rates and "I cannot…" rates across the #200-series are
  valid CELL CONTRASTS and are not production facts.** They are left un-annotated
  on purpose — the contrasts still hold, and rewriting them would obscure what was
  actually measured. Read them as "cell A vs cell B, armed," never as "the app
  does this."
- Measured 2026-08-01, run `F486F103`, same four prompts, same build: the unrouted
  control posted **6/10 grabs plus 4/10 disclaimer tics — zero clean composition
  turns.** The routed cell posted **10/10 clean, 0 grabs** (p = 1.08e-05). Creates
  were **10/10 in both** arms.
- **So routing is a no-op on device-request prompts and decisive on composition
  prompts.** Adding routing to a battery whose prompts are all device requests
  (read-tool, motion) will not move its numbers — don't spend a device run
  expecting it to.
- What routing does NOT excuse: **over-serving on turns it CORRECTLY arms**
  (tool chaining, the `lookupContact` spiral). Those numbers were never inflated
  by this and are the real remaining work.

`runActionBattery`'s `routed-production` cell is the routed arm. Every other
wrapper is still unrouted.

**Where it lives (#216, 2026-08-01):** the battery and the DEBUG instruments were
split out of `LocalChatBackend.swift` (5,727 → 1,826 lines) into
`LocalChatBackend+Battery.swift`, `+Harnesses.swift` and `+IntentRouting.swift`.
Pure code motion. Because Swift's `private` is FILE-scoped, the production
members those files reach are now `internal` and tagged **`// harness-visible`**
— that tag means "private in spirit, widened only for the harness"; grep it
before assuming a member is part of any real interface.

**Where the BARS live (convention change, recorded 2026-08-01):** lanes through
#214 pre-registered their bars in a `dispatch/` doc; `dispatch/OPUS-T27-214-scopedv2.md`
(2026-07-31) is the last one. Since then — #215, #216, #217, #217B — bars are
pre-registered **inside the OPEN_ITEMS entry**, before the run, and each of those
entries says "bars written first" in so many words. **The rule did not change; the
vehicle did.** Bars still go in writing before the run and a missed bar is still a
falsification, not a redefinition. Write them in the OPEN_ITEMS entry; a dispatch
doc is optional and mostly useful when handing a lane to another agent. Flagged by
the 2026-08-01 external audit (§4) as undocumented drift — not a discipline lapse,
just a convention the next lane could not have inferred.

**A promoted clause is PRODUCTION CODE (#218, 2026-08-01).** When a lane promotes
a string, it moves out of the harness file in the same commit. Three promoted
instruction clauses stayed declared inside `#if DEBUG` while production read them
every turn, and **`main` could not build in Release for two days** — invisible
because the suite, corded device installs and the CLI compile check are all Debug.
Corollary, and it applies to any `#if DEBUG` or gating edit: **verify with a
Release build**, because a green Debug suite cannot see a mis-set gate.

  ```bash
  DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer xcodebuild -project Talaria.xcodeproj -scheme Talaria -configuration Release -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
  ```

## Project history

Dated per-item history — every wave, lane, and PR previously transcribed here — lives in
the canonical tracker, which since #261 (2026-08-06) is TWO files: `OPEN_ITEMS.md` (the
live board — open/watch/decision items + the counting rules, which govern both files) and
`OPEN_ITEMS-ARCHIVE.md` (every closed item, moved verbatim, never summarized). Numbering
is one monotonic sequence across both; nothing is ever renumbered, and whole-project
counts run over the concatenation. `scripts/oi-split-verify.py` proves the split lost
nothing. The narrative duplicate that used to sit at the end of this file was pruned
2026-07-24: it had drifted badly, still describing merged work as "cloud-written, NOT
compiled" with next-session instructions for sessions long past. Read the tracker for
state; read this file for standing rules. Tracker item numbers are a **separate sequence**
from GitHub issue and PR numbers — always disambiguate which you mean.
