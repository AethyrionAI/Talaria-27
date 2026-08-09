# FABLE — reconciliation: the 2026-08-02 zero-setup execution plan vs #251's plugin venture

**Label:** FABLE · **Items:** #223, #251, #268, #269, #270, #271 · adjacent #113/#188, #238, #242, #264, #283
**Written:** 2026-08-09. **Investigation only — no production code, no Swift edits, no `OPEN_ITEMS.md` edits, no live-install modification.**

**Goal in one sentence:** decide which parts of `dispatch/FABLE-T27-223-zero-setup-execution-plan.md` (2026-08-02) are still the plan after #238 and #251, and mark the rest DEAD or DONE so the doc stops reading as live work.

> **The headline finding.** The 08-02 plan does not know about #251 — but that is the *second* thing wrong with it. The **first** is that its centrepiece was killed a day earlier by **#238**, not by #251: Lanes 0–4 are the push-delivery arc, and notifications were removed from the app wholesale on 2026-08-03. #251 then absorbed Lanes 5–8. **Every one of the plan's nine lanes is DEAD or DONE. None survives as written.** The tracker already knows this in three separate places (#223's retirement blockquote, #251's decision 1, #268's contradiction 1); **the plan document itself carries no marker of any kind** — verified: one commit (`69d7306`), never amended, zero occurrences of "238", "251", "plugin", "superseded", or "retired" in its 712 lines.

---

## 1. VERIFIED STATE

Everything in this section was observed live on 2026-08-09 by read-only probe. Nothing on any live install was modified. The **ASSUMED** block at the end is separated deliberately.

### 1.1 The host-side footprint, measured

| Component | Mac Mini | OJAMD | How verified |
|---|---|---|---|
| **Gateway `:8642`** | **LIVE** — PID 19532, `hermes gateway run --replace` from the hermes venv, started **Fri Aug 7 07:20:41**, uptime 1d 17h | **LIVE** | `lsof -nP -iTCP:8642 -sTCP:LISTEN` + `ps -o lstart=`; `/health` → `{"status":"ok","version":"0.20.0"}` on **both** hosts |
| **Relay `:8000`** | **LIVE** — PID 1872, `uvicorn app.main:app`, **cwd = `/Users/owenjones/Documents/Claude/Talaria-27/relay`**, started **Fri Jul 24 20:12:25**, uptime **15 days** | **LIVE** | `lsof` + `ps`; `GET /v1/health` → **200** on both hosts (`/health` and `/health/detailed` are 404 — the live path is `/v1/health`) |
| **Shim `:8765`** | **STILL RUNNING** — PID 1880, `tools/models-shim/shim.py` under the hermes venv, started Jul 24, uptime 15 days; `GET /models` unauth → **401** | **DOWN** — `GET /models` → no answer (HTTP 000 / timeout), the documented no-listener drop shape on a process-firewalled Windows host | `lsof`/`ps` on the Mac; curl over the tailnet to both |
| **Connector** | **LIVE, and it is not a bat-launched process here** — `connector/.venv/bin/hermes-mobile-mcp` (PID 19542) running as an **MCP stdio child of the gateway**, supervised by `mcp_stdio_watchdog.py --ppid 19532`; registered in `~/.hermes/config.yaml:659-663` as MCP server `hermes_mobile` | not probed (see ASSUMED) | `ps aux`; `grep hermes_mobile ~/.hermes/config.yaml` |
| **`talaria` plugin** | **INSTALLED + ENABLED** — `~/.hermes/plugins/talaria`, local git head `fd5d7d1`; `hermes plugins list` → `talaria / enabled / 0.1.0 / git`; `config.yaml` carries `plugins.enabled: [honcho, talaria]` **and** `platforms.talaria.enabled: true` | **NOT INSTALLED** | see the discriminator below |
| **`talaria-push` hook** | **ON DISK, DISARMED** — `~/.hermes/hooks/talaria-push/` (HOOK.yaml, handler.py, watcher_core.py, config.json, `vendor/{h2,hpack,hyperframe}`), files dated 2026-08-03; **`~/.hermes/talaria/push/devices/` is EMPTY**, last touched Aug 3 18:57 — the designed OFF switch, still off | never deployed | `ls -laR ~/.hermes/hooks/`, `ls ~/.hermes/talaria/push/devices/` |

**The OJAMD plugin discriminator (this is the load-bearing new fact).** Unauthenticated `POST /api/platforms/{p}/events`:

| host | `p = talaria` | `p = zzznope` (control) | reading |
|---|---|---|---|
| Mac | **401** | 503 | adapter registered, fail-closed auth — plugin live |
| **OJAMD** | **503** | 503 | **indistinguishable from a platform that does not exist — the talaria adapter is NOT registered on OJAMD** |

That is a live confirmation of **#271 NOT STARTED**, obtained without touching the box.

**A collision worth knowing before anyone deletes the hook:** the retired hook and the live plugin share a directory root. `HERMES_HOME/talaria/push/devices/` is the hook's (empty). `HERMES_HOME/talaria/devices.json` is the **plugin's** device store — **modified 2026-08-09 00:19, minutes before this probe**, i.e. actively serving Owen's phone. Removing `~/.hermes/talaria/` wholesale to clean up the hook would destroy the live pairing store.

### 1.2 What has already shipped from the 08-02 plan

| Plan lane | State | Evidence |
|---|---|---|
| **Lane 1** (`talaria-push` hook) | **BUILT AND SMOKE-PROVEN, THEN DISARMED.** Branch `claude/t27-223-talaria-push`, tip `dd25e2d`; smoke commit `18dd02a` reads *"SMOKE PASSED — relay-free push proven end-to-end (2x status=200, both banners on device)"*. **Never merged** — `git ls-files host/` returns **0 files** on main; the working-tree `host/` holds only gitignored `__pycache__`. | `git ls-tree -r claude/t27-223-talaria-push -- host/`; `git branch --merged main` lists only the Lane-5 branch |
| **Lane 2** (app pilot flag) | **NEVER BUILT, AND NOW UNBUILDABLE** — it was written to gate `postPushWatch`, a symbol that no longer exists. | Main tree: **zero** hits for `postPushWatch`, `push/watch`, `push/register`, `UNUserNotificationCenter`, `hookPushPilotEnabled`; `aps-environment` and `remote-notification` **absent** from `project.yml`. (Hits survive only in the stale worktree `.claude/worktrees/claude+t27-176c-creative-suppressor` — ignore it.) |
| **Lane 3** (measured pilot, bars B1–B5) | **CANCELLED.** B1/B2 measure banners; there are none. | #238 (closed, all five bars met, 2026-08-03) |
| **Lane 4** (productionize push) | **DEAD.** | #251 filing decision 1: *"**Push stays DEAD.**"* |
| **Lane 5** (shim retirement) | **✅ COMPLETE, MERGED.** `claude/t27-223-lane5-shim-retirement` **is** in `git branch --merged main`. Bar L5-E met on device 2026-08-04 (build 1955). `ModelsShimClient` gone from the tree. | branch merge state + main-tree grep + #223's Lane-5 block |
| **Lane 6** (upstream contribution) | **DEAD-BY-POLICY and internally incoherent.** | #268 contradiction 2 (Owen's no-upstream-PR ruling, 2026-07-22, reaffirmed at #241: *"I don't want to do a PR, anxious"*); #223's own 2026-08-06 note: *"the two sources do not even agree on what Lane 6 IS… do not route Lane 6 as currently written"* |
| **Lane 7** (sensors → deposit model) | **SUPERSEDED.** | #251 decision 2: *"**Sensors ride #242**, not an ingestion pipeline — the report's Option-A sensor hole dissolves because the direction is already query-time."* The `talaria_phone_query` tool shipped in Phase 1 and passed device bars 2A-B/D/F. |
| **Lane 8** (pairing collapse) | **PARTLY ABSORBED, NOT DONE.** Plugin pairing shipped (auto-pair, 2A-A MET) — but the plan's own first move is untouched: **`BackendProfile.relayBaseURL` is still `String`, not `String?`** (`shimBaseURL` *is* optional). | `Talaria/Models/BackendProfile.swift:17,19,22` |
| **Lane 0** (preconditions) | **STALE ON EVERY LINE.** P1's `nohup … gateway run --replace` recipe would now start a **second** gateway beside the launchd-supervised one (see Traps). P2 asks for a push token from a Diagnostics row that #238 deleted. | `~/Library/LaunchAgents/ai.hermes.gateway.plist` per #268's correction; #238 scope |

### 1.3 What the relay is still actually carrying (app-side, counted)

The 08-02 plan names three relay tenants (push / sensors / pairing). The live app calls **eighteen** distinct relay paths across **seven** services (plus a `/health/detailed` probe):

- **pairing + auth** — `device/register`, `device/provisioning`, `auth/refresh`, `auth/revoke`, `session`, `phone-pairing/redeem`, `hosts/current`, `hosts/current/revoke`, `hosts/enrollment-codes` (`LiveSessionBootstrapService`, `LivePairingService`, `LiveHermesHostService`, `AppContainer`)
- **sensors** — `device/sensor/health`, `device/sensor/location`, `device/app-state` (`SensorUploadService`, `AppContainer`)
- **voice bootstrap** — `talk/session`, `talk/readiness` (`LiveVoiceSessionService`) — **named in neither #223's tenant list nor the 08-02 plan**
- **conversation/command feed** — `conversations/current`, `conversations/current/clear`, `messages`, `commands` (`LiveHermesClient`, `AppContainer`)
- **push** — **gone.** Zero hits.

#251's own errata already flagged this (*"relay also carries sensor ingestion, inbox fetch, voice bootstrap, files"*). The count above is the concrete version.

### 1.4 ASSUMED — explicitly not verified this session

- **OJAMD's connector, watchdog, and relay process shape.** I probed OJAMD's HTTP surfaces only. The `connector-watchdog.log` / `relay.log` state, the 493 MB unrotated log from #188, and whether the connector is running at all are **taken from the tracker, not observed.** Probing them needs box access I do not have read-only.
- **OJAMD's `platform_hints` block.** #271 records it as still unpasted since 2026-08-06. Not re-checked.
- **Whether OJAMD's relay still holds the APNs `.p8`.** #238 note (2) records the relay's push leg as already dead at APNs (6× `403 BadEnvironmentKeyInToken`) before removal. Not re-probed — and it does not matter, since nothing arms a watch.
- **The Mac shim's callers.** `:8765` answers 401, so it is alive; the app provably does not call it (`ModelsShimClient` deleted). Whether anything *else* on the Mac does was not checked.
- **#263(a)** (split hub singleton) remains a WATCH; I did not attempt to reproduce it.

---

## 2. THE TWO ARCHITECTURES, SIDE BY SIDE

| | **Plan D — zero-setup consolidation** (08-02 plan + #223) | **Plan C — the plugin venture** (#251) |
|---|---|---|
| **Written** | 2026-08-02 | 2026-08-05 (three days later) |
| **Goal** | "install Hermes, paste one key" — collapse the host footprint so setup stops being a power-user bar | identical goal, restated: *"replace relay + connector + MCP server + venv CLIs with ONE Hermes plugin"* |
| **Vehicle** | **N artifacts in `HERMES_HOME`** — a `gateway:startup` hook with vendored deps, `HERMES_HOME/scripts/` senders, skills, bootstrap turns | **ONE plugin directory** in its own repo, `~/.hermes/plugins/talaria`; the clone IS the install |
| **Inbound transport** | none — the phone polls the Sessions API; the host pushes via APNs | **`POST /api/platforms/talaria/events`** on the existing `:8642` listener — no new socket, no new port, no new process |
| **Delivery when the app is closed** | **APNs banner** from a resident in-process watcher | **durable outbox + fetch-on-connect.** "It's waiting when you open the app" *is* the delivery model |
| **Sensors** | **deposit model** — app uploads daily aggregates, a Hermes *skill* queries them | **query-time** (#242) — the agent asks the phone, no ingestion, no store. `talaria_phone_query` shipped in Phase 1 |
| **Pairing** | bootstrap turns + `relayBaseURL` made optional | `hermes talaria pair` + app auto-pair over the webhook; hashed device store at `HERMES_HOME/talaria/devices.json` |
| **Upstream Hermes** | Lane 6 asks for **two upstream PRs** (api_server hook emission + a managed-files mount) | **zero upstream PRs** — everything reaches in-process from plugin code (Escape B proved even *steering* needs no core edit) |
| **Relay endgame** | Phase 5 "relay retirement + pairing collapse" | Phase 4 "relay decommission", **gated on #271** |
| **Status** | #268: *"**Largely SUPERSEDED**"* | #268: *"**This is the one Owen means.**"* Phase 1 ✅, 2A ✅ (PR #272), 2B/2C/2D → #269/#270/#271, Phase 3 open as #283 |

### Where they genuinely conflict

1. **Push.** Plan D's Lanes 1–4 exist to deliver banners. Plan C decision 1 says *"Push stays DEAD"*, and #238 already removed the receiving half. **Not a disagreement between the plans — Plan D lost this to #238 before Plan C was written.** Plan C only declined to revive it.
2. **Sensors.** Deposit (upload-then-query) vs query-time (ask-the-phone). These are mutually exclusive designs for the same feature, and the query-time one has shipped and passed device bars.
3. **Upstream.** Plan D's Lane 6 is a prerequisite in its own text; Plan C treats upstream as off the table by Owen's standing ruling and routes around it. #268 contradiction 2 is right that this is **blocked-by-policy**, not blocked-by-acceptance.
4. **Relay retirement is one job under two numbers.** #223 Phase 5 and #251 Phase 4. #268 contradiction 3 already ruled: **#251's arc is the live vehicle; #223 is the tracker home. Do not run them as two lanes.**
5. **What "the host runs" means.** Plan D still ends with a shrunken relay ("Windows box then runs the gateway process, the relay (smaller), and the connector — no shim"). Plan C ends with **gateway only**. Plan D's end state is Plan C's *interim*.

### Where they agree, and it is worth saying

Both refuse to patch Hermes core. Both put resilience in the app, not the sidecars. Both treat `HERMES_HOME` artifacts as the update-survivable surface. Plan C is Plan D's goal reached through a door Plan D did not know existed — the plugin/platform-adapter API. The 08-02 plan is not *wrong-headed*; it is **pre-discovery**.

---

## 3. ⚠️ TRACKER CORRECTIONS

Each with the entry that owns it. Per the close-out rule, corrections go **upstream to the stale claim's own home**.

| # | Stale claim | Where it lives | Correction owed |
|---|---|---|---|
| **C1** | The entire 08-02 execution plan reads as live, routable work. It carries **no** supersession marker — verified, zero hits for 238/251/plugin/superseded/retired in 712 lines, one commit, never amended. | `dispatch/FABLE-T27-223-zero-setup-execution-plan.md` (the doc itself) | A header block: *"⚰️ SUPERSEDED 2026-08-03 (#238, push lanes) and 2026-08-05 (#251, everything else). Lane 5 SHIPPED. Kept as the archive of the resident-watcher design and the hook-contract findings. Do not route any lane from this document."* **This is the single highest-value correction in the list.** |
| **C2** | #223's **"THE PHASED PLAN"** paragraph still lists *"Phase 2 — push sender v1 (REVISED same day): the resident-watcher `gateway:startup` hook + APNs sender on OJAMD… Blocker: none technical."* | `OPEN_ITEMS.md` #223 | #268 already flagged this (*"the phased-plan paragraph further down was never updated to match"*) and **it is still unfixed.** The retirement blockquote at the top of #223 does not reach it; a reader who scrolls past the blockquote finds a live-looking Phase 2. |
| **C3** | #223's **"What still needs the relay"** list names three tenants: push, sensors, pairing. | `OPEN_ITEMS.md` #223 | Push is gone; **voice bootstrap** (`talk/session`, `talk/readiness`) and the **conversation/command feed** (`conversations/current`, `messages`, `commands`) are missing from the list. §1.3 above is the counted replacement. #251's errata says the same thing in prose; #223's own list was never updated. |
| **C4** | #223's **"End state"**: *"Windows box then runs the gateway process, the relay (smaller), and the connector — no shim."* | `OPEN_ITEMS.md` #223 | That is now the **interim**, not the end state. #251's end state is gateway-only. |
| **C5** | #223's **"Sequencing"** list — *"(1) verify routes on a CURRENT gateway; (2) shim-retirement lane; (3) file-fetch migration (#21); (4) then the relay is what remains."* | `OPEN_ITEMS.md` #223 | (1) and (2) are DONE. (3) is superseded — there is no file API on `:8642` (Falsification 1, same entry) and #21's home is now the Phase-3 plugin mirror / media pipeline. |
| **C6** | `CLAUDE.md`'s **OJAMD services** section describes the connector as *"a plain bat-launched process (`start-connector.bat`)"*. | `CLAUDE.md` | True for OJAMD; **false for the Mac**, where the connector runs as an **MCP stdio child of the gateway** under `mcp_stdio_watchdog.py --ppid 19532`, registered at `~/.hermes/config.yaml:659`. The two hosts have different connector process shapes and the file describes only one. Worth a clause, because #271 will rediscover it. |
| **C7** | `CLAUDE.md` Model switching: *"The OJAMD `TalariaModelsShim` service is stopped and disabled."* | `CLAUDE.md` | **Correct for OJAMD** (probe: no listener). But **the Mac shim is still running** — PID 1880, up 15 days, answering 401 on `:8765`. The sentence reads as "the shim is gone" and one of two hosts still has it live. Harmless (nothing calls it) but it is a stale fact in an always-loaded file, which is the exact shape the 08-06 audit was created to catch. |
| **C8** | Lane 3's bar B4 pins survival across **`hermes-update-safe.ps1`**. | the 08-02 plan (dies with C1) | `CLAUDE.md` already records that Owen has **never once used** that script — his practice is bare `hermes update`. A bar written against a script nobody runs could not have been met as written. Noted so the *shape* of the error is on record: bars must name the thing that actually happens. |
| **C9** | #223's Lane-6 line and #251's phase arc disagree on what Lane 6 is; #223 already carries a *"do not route Lane 6 as currently written"* note. | `OPEN_ITEMS.md` #223 | Nothing new owed — but note that **C1 makes it moot**: with the plan doc marked dead, Lane 6 has no home to be routed from. |

**One thing I checked and did NOT find stale:** #268 itself. Its four-plan map, its per-phase table, and all four contradictions hold against live state. It is the most accurate document in this set and this report is largely a confirmation of it plus host evidence it did not have.

---

## 4. THE VERDICT

### ⚰️ DEAD — superseded, stop citing

| Item | Killed by | Note |
|---|---|---|
| **Lane 1** — `talaria-push` hook | **#238** (2026-08-03), not #251 | Built, smoke-proven (2× `status=200`, banners on device), then disarmed. Branch `claude/t27-223-talaria-push` @ `dd25e2d` is the archive. **Do not merge it.** |
| **Lane 2** — `hookPushPilotEnabled` app flag | #238 | Written against `postPushWatch`, a symbol that no longer exists. Unbuildable as specified. |
| **Lane 3** — measured pilot, bars B1–B5 | #238 | B1/B2 measure banners. There are none. |
| **Lane 4** — productionize push | #251 decision 1 | *"lets not build a solution for an audience of 1 again"* — the `.p8` cannot be distributed to App Store users. |
| **Lane 6** — upstream contribution | Owen's no-upstream-PR ruling + #223's own incoherence note | Blocked-by-**policy**. Also unnecessary: Escape B proved plugin code reaches the live agent with zero core edits. |
| **Lane 7** — sensors deposit model | #251 decision 2 → #242 | Replaced by query-time `talaria_phone_query`, shipped and device-verified. |
| **CloudKit push** | the 08-02 investigation itself | Owen's provisional pick, falsified the same day (server-to-server keys are container-scoped and cannot reach private DBs). Already correctly recorded in #223. |
| **The whole 08-02 execution plan as a routable document** | #238 + #251 | Keep the file; mark it. Its *findings* (hook contract, `gateway:startup` unconditional emit, ES256 already in the venv, vendorable pure-Python h2) remain true and are worth the archive. |

### ✅ DONE — shipped, mark it

| Item | Evidence |
|---|---|
| **Lane 5 — shim retirement** | Branch merged into main; `ModelsShimClient` absent from the tree; L5-A..D met, **L5-E met on device 2026-08-04** (build 1955, OJAMD, deepseek pick applied and locked). OJAMD `:8765` confirmed dark by probe today. |
| **#251 Phase 1 — tools + admin plugin** | `hermes plugins list` → `talaria / enabled / 0.1.0 / git`; `plugins.enabled` + `platforms.talaria.enabled` both in `config.yaml`. |
| **#251 Phase 2 slice 2A — transport spine** | PR #272 (`3f3bdee`); bars 2A-A/C/D/E/F/G MET on device; **2A-B falsified as written** (32s vs ≤5s, bar mis-specified, instrumentation absorbed by #263). Live today: `HERMES_HOME/talaria/devices.json` mtime **2026-08-09 00:19**. |
| **The push cut (#238)** | Main tree zero-hits for the entire notification surface; `aps-environment` absent from `project.yml`. |

### 🟢 SURVIVES — still the plan, in its new home

| From the 08-02 plan | Where it lives now |
|---|---|
| **The zero-setup GOAL** — "install Hermes, paste one key" | Unchanged and correct. It is #251's goal verbatim; #269 (conversational installer) is the strongest form of it ever written — the user never touches a terminal at all. |
| **Never patch Hermes core; everything in `HERMES_HOME` or our repo** | Standing. The plugin honours it by construction (clone-is-the-install survives bare `hermes update`). |
| **Bars in writing before the run, in the OPEN_ITEMS entry** | Standing convention since #215. #269/#270/#271 each say "bars pre-register HERE". |
| **Payload/contract compatibility as a hard rule** | Survives re-pointed: slice 3A's safety story is that the runs decoder emits the **same `StreamingUpdate` contract**. Same discipline, different contract. |
| **Lane 8's pairing collapse** | Half-absorbed by plugin pairing; the app-side half is **still owed** (below). |
| **The App-Store push-tier gate** | Resolved, not survived: #251 decision 1 answered it — durable outbox + fetch-on-connect + Live Activities, no vendor sender, no BGTask-only tier. Record it as **DECIDED** rather than parked. |

### 🆕 NEWLY OWED — the gap neither document covers

These are real and are in no entry today.

1. **The relay's tenant list is wrong everywhere, and Phase 4 is scoped against it.** #223 names three tenants; the app calls **eighteen paths across seven services**, including **voice bootstrap** and a **conversation/command feed** that appear in no decommission plan. **A `POST /api/platforms/talaria/events`-based plugin does not currently carry voice.** Phase 4 cannot be scoped until each of the eighteen has a named destination (plugin / gateway / deleted / accepted-loss). *This is the largest unfiled gap found.*
2. **`BackendProfile.relayBaseURL` is still non-optional.** The app cannot express a gateway-only profile. Lane 8's first move was never made and no live item owns it. Until it is, "zero-setup" is unreachable app-side no matter what the host does — a new user must still type a relay URL.
3. **Two dead sidecar trees still ship in the repo:** `tools/models-shim/` (retired 2026-08-04) and `relay/` + `connector/` (scheduled for Phase 4). No item owns their deletion. Related: **#255**'s de-branding sweep touches the same trees; sequence them or do the work twice.
4. **The disarmed hook is still on disk on the Mac**, with a `vendor/` tree and `__pycache__` compiled against two Python versions. #238 said it would be "removed at the next natural gateway restart"; the gateway has restarted (Aug 7) and it is still there. **And the deletion is booby-trapped** — `HERMES_HOME/talaria/` is now the *plugin's* live device-store root (§1.1). One-line chore, one real footgun.
5. **The two hosts have different connector process shapes** (§1.1, C6). #271 assumes one shape.
6. **Nobody has decided where `#21` (agent-generated file delivery) lands.** #223 Sequencing step 3 is superseded, and the Phase-3 plan calls it an open question (webhook responses fine for small files, ugly for large; agent A's media pipeline is "the likely answer"). It is currently homeless.

---

## 5. PROPOSED RE-SEQUENCING

The arc as it should now read. **#251's arc is the spine; #223 is the tracker home for the final phase only.**

```
  ✅ #251 Phase 1 — tools + admin plugin ........................ SHIPPED 2026-08-05
  ✅ #251 Phase 2A — transport spine ............................ MERGED  PR #272
  ✅ #223 Lane 5 — shim retirement .............................. MERGED  2026-08-04
        │
        ├── #283  Phase 3 slice 3A — runs transport parity ....... OPEN (Owen routed 08-07)
        │     └── 3B approvals · 3C steer+queue · 3D artifacts · 3E cutover
        │
        ├── #271  Phase 2D — OJAMD rollout ....................... NOT STARTED  ◀ the gate
        │     ├── requires: #263(b) deployed  ·  #264 listener check
        │     └── requires: OJAMD platform_hint block pasted
        │
        ├── #269  Phase 2B — conversational installer ............ NOT STARTED
        └── #270  Phase 2C — desktop face v0 ..................... NOT STARTED
                    │
                    ▼
        #251 Phase 4 / #223 — RELAY DECOMMISSION ................. GATED
              blocked by ALL of:  #271 (plugin carries production)
                                  NEW-1 (eighteen tenants re-homed)
                                  NEW-2 (relayBaseURL optional)
```

**Does the decommission order still hold? YES — and it is stricter than either document states.**

The chain **#271 → Phase 4** is confirmed by three independent sources: #268's Phase-4 row (*"gated on #271 (2D) — the relay cannot go until the plugin carries the production host"*), #271's own scope (*"This slice is the gate on #251 Phase 4"*), and OJAMD's operational ask carried into #251 (*"don't retire the relay until the adapter's process story is settled"*). My probe **confirms the premise empirically**: the talaria adapter is not registered on OJAMD, so today the production host has **no plugin transport at all**.

**What breaks if it is done out of order** — name each, because they are different failures:

- **Relay off before #271** → OJAMD has neither relay nor plugin. Sensors, pairing, voice bootstrap, the conversation feed and the inbox all die at once on Owen's daily-driver host. **Total paired-tier outage.**
- **Relay off before NEW-1** → the four tenants nobody has re-homed die silently and specifically. **Voice is the sharp one** — `talk/session` + `talk/readiness` have no plugin equivalent and appear in no plan.
- **Relay off before NEW-2** → existing profiles still carry a required `relayBaseURL` pointing at a dead host. Best case, honest degradation; worst case, a boot path that assumes reachability.
- **#271 before #263(b)** → the two live transport defects propagate to a second host. #271's own text says this first.
- **#271 without #264's listener check** → the classic: healthy PID, no `:8642` bind, "why is it down" for five minutes. On OJAMD after the Phase-3 migration this kills chat *and* approvals *and* steering *and* phone-query at once — the migration **concentrates** the failure mode rather than adding one.

**One sequencing question the plans answer differently, and Owen has already been asked it.** Phase-3 plan §5 Q2 recommends 3A before B/C/D, with an honest counter-argument that **D is small and is what makes Owen's daily driver benefit from 2A at all**. Owen said "begin on phase 3" — which answered Q2 for 3A but **left #271 unscheduled**. Given #271 is the gate on the whole endgame, it is worth re-asking as a standalone (§6 Q1).

---

## 6. WHAT IS OWEN'S TO DECIDE

I am not deciding any of these. Each is stated with the evidence and, where honest, a lean.

**Q1. Schedule #271 (OJAMD rollout) now, or hold it behind more of Phase 3?**
"Begin on phase 3" routed 3A; it did not schedule 2D. #271 is the gate on Phase 4 and is small. The counter-argument is real: 3A may change what the transport is, and rolling a moving target onto the production host twice is worse than once. *Lean: after 3A merges and its device bars close — but before 3B — so the production host is on the shape everything else assumes.*

**Q2. What happens to the four un-re-homed relay tenants (NEW-1)?** Specifically **voice bootstrap** (`talk/session`, `talk/readiness`) and the **conversation/command feed**. Options: build them into the plugin; move them to gateway routes; accept the loss; or keep a minimal relay indefinitely for voice alone. **This decides whether Phase 4 is "decommission" or "shrink".** No lean — this is a product question about whether relay-hosted voice survives.

**Q3. Is `#223` still the right tracker home for Phase 4?** #268 ruled it is. But #223's own text is now ~90% falsified narrative, and the correction list in §3 is long. Alternative: close #223 with a pointer and open a clean Phase-4 entry. *Lean: keep #223 as home per #268, apply corrections C2–C5, and let the archive keep the history — renumbering costs more than it buys.*

**Q4. Delete the disarmed hook from the Mac, and delete `tools/models-shim/` + `host/` leftovers from the repo?** The hook deletion touches a live install (a `rm -rf ~/.hermes/hooks/talaria-push` and nothing else) and therefore needs the per-experiment go under the standing rule. **It is adjacent to the live plugin device store — see the footgun in §1.1.** The repo-side deletions need no go.

**Q5. Does the App-Store push-tier gate get formally marked DECIDED?** #251 decision 1 answered it, but #223's lane map still shows it "parked". Cheap, and it stops the question being re-opened.

**Q6. Sensors — the leaning is still a leaning.** #223 records Owen's *"I'm ok with ditching the sensors if i'm being honest… I'm not hard locked on keepin' em."* Three sensor paths are in the eighteen. If the answer is ditch, NEW-1 shrinks materially and Phase 4 gets simpler. Nothing builds or deletes on a leaning — but Q2 is easier to answer once this one is.

---

## 7. TRAPS

**⛔ THE BIG ONE — DO NOT HARDEN THE RELAY OR THE CONNECTOR (Owen, standing, 2026-08-02).**
Everything in this report points at a relay that is 15 days into an uninterrupted run and carrying more than anyone's tenant list says. **That is not an argument for making it more robust.** The rule exists precisely because this migration is pending: every hardening buys reliability in a component with a planned end-of-life and pays permanent update friction that compounds. **#188 is DECLINED, not refuted** — its per-component liveness probes and log rotation stay unbuilt. If NEW-1's discovery makes a relay change look unavoidable, **raise it with Owen as a decision rather than building it.** The bar is "the user is harmed now and no app-side fix exists." Still allowed: one-time chores (deactivate, never delete), read-only measurement, and **deleting** relay surface once the plugin or the gateway absorbs it.

**#264 — the gateway bind race.** After ANY gateway bounce, verify the **LISTENER** (`lsof -nP -iTCP:8642 -sTCP:LISTEN`), never the process. A respawn can lose the bind to the dying process's socket, never retry, and run headless with a healthy PID and healthy `launchctl`. After Phase 3 this state kills chat, approvals, steering and phone-query **simultaneously**, because they all come through that one listener. It is the first line of #271's runbook.

**#113 → #188 — the supervision gap is a DELETION argument, not a fix request.** #113 closed 2026-07-25 (its duplicate-connector premise refuted on the box); #188 is the half that survived and is declined. The 493 MB unrotated, timestamp-free `relay.log` is real and is **an argument for deleting the relay sooner**, not for rotation machinery. If disk pressure bites, truncate — a one-time chore, explicitly allowed.

**The launchd trap.** Lane 0 P1's `nohup … gateway run --replace &` recipe is **FALSE against live state** — the Mac gateway is launchd-supervised (`~/Library/LaunchAgents/ai.hermes.gateway.plist`, `KeepAlive` + `RunAtLoad`, since 2026-08-03). Running that recipe now starts a **second** gateway beside the supervised one. `kill` gives a clean ~20s respawn; `hermes gateway restart` is the polite form; a manual `hermes gateway run` from a shell now refuses (orphan-dispatcher guard). **OJAMD differs** — there the gateway is a user `pythonw` process, not a service, and `Start-Service HermesGateway` does not exist.

**The `HERMES_HOME/talaria/` collision.** The retired hook's device dir and the **live plugin's** device store share a root. `rm -rf ~/.hermes/talaria/` destroys Owen's pairing. Delete `~/.hermes/hooks/talaria-push/` only.

**🔐 Live-install experiments need an explicit per-experiment go.** Editing a loaded plugin file, adding a temporary event type, changing `config.yaml`, or restarting the gateway *to load experimental code* all ride the gate — even when temporary and reverted. Read-only probes and throwaway loopback servers are free. **Everything in this report was read-only.** The 2026-08-06 time-boxed clearance expired with that day.

**Two-of-everything, twice over.** Never claim a `:8642` route from a `web_server.py` grep — read `api_server.py`'s `_http_route_table()`. And verify plugin state with `hermes plugins list`, **never** the Hermes Desktop Settings → Plugins pane, which manages only desktop UI plugins and cannot show `talaria` by design. Owen burned two restarts on exactly this; it is what #270 exists to productize.

**A bar written against a script nobody runs cannot be met** (C8). And **a phase name is not a filing** (#268) — every NEWLY-OWED item in §4 should get a number the day Owen routes it, even if the entry is three lines pointing back here.

---

## 8. THE ONE-LINE VERDICT

**The 2026-08-02 plan is an archive, not a roadmap: its push arc (Lanes 0–4, 6) was killed by #238 before #251 existed, its sensors and pairing lanes (7, 8) were absorbed by #251, and its one shipped lane (5, the shim) is done — what survives is the goal, and the goal now lives in #251's arc, gated at the end on #271.**
