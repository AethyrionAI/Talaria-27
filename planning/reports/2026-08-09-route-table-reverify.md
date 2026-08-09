# `:8642` route-table re-verification — 2026-08-09

**Verdict: CLAUDE.md's route table is STILL ACCURATE. Zero routes added, removed, or changed
since the 2026-08-02 verification.** The `_http_route_table()` function body is **byte-identical**
between the commit serving on 2026-08-02 and current upstream HEAD — 37 rows in both.

The premise that prompted this lane ("upstream may have moved hundreds of commits since") is
true of the repo and false of this function. The table did not move. What *did* move is
behaviour behind three of the routes, and there is a real running-process/source divergence
(§6) — but it is not a routing divergence.

Method: fresh full clone + installed-source read + live read-only probe. **No `web_server.py`
grep was used to support any `:8642` claim.** Every route assertion below traces to
`gateway/platforms/api_server.py::_http_route_table()` or to a live probe against `:8642`.

---

## 1. The three sources (plus the running process)

| # | Source | Commit | Date | `_http_route_table()` |
|---|---|---|---|---|
| 1 | **CLAUDE.md's recorded table** | in-repo prose | stamped "verified 2026-08-02 … 0.19.1" | 14 glob entries |
| 2 | **Installed head** (`~/.hermes/hermes-agent`, read-only) | `ceebb21dd` | 2026-08-08 23:14 −0700 | **37 rows** |
| 3 | **Upstream HEAD** (fresh clone) | `62431364e` | 2026-08-09 01:24 −0500 | **37 rows** |
| — | **Running Mac process** (PID 19532) | `01a1037d1` | started 2026-08-07 07:20, uptime 1d 18h | **37 rows** |

**Provenance checks performed, because each of these could have silently lied:**

- The scratchpad clone **pre-existed** my `git clone` (it errored "already exists"). I did not
  trust it: `git ls-remote origin HEAD` returns `62431364e35aa10…`, which **matches the clone's
  HEAD exactly**, and `.git/shallow` is absent with 21,454 commits of history. It is a genuine,
  current, full clone.
- **Installed head is only 3 commits behind upstream HEAD**, and
  `git diff ceebb21dd..HEAD -- gateway/platforms/api_server.py` is **empty**. Sources 2 and 3 are
  the same file. They collapse into one.
- **The running process was pinned via reflog, not assumed.** The listener started
  2026-08-07 07:20; the install's reflog shows checkouts at 2026-08-05 19:31 (`01a1037d1`) and
  next at 2026-08-08 19:30. So the process imported `01a1037d1`. Its route table is **identical
  to HEAD's** (verified by extracting the function from that exact commit).

⚠️ **One methodology note against myself.** My first attempt at the source-to-source diff printed
a confident "IDENTICAL" that was **worthless**: zsh applied its `:g` history modifier to
`$REF:gateway/...`, so both extracts were empty files and `diff` trivially succeeded. I caught it
because I printed a row count alongside — it read `0`. The re-run with `${REF}` and a non-empty
guard is the result reported above (37 vs 37). This is the `cmd | grep || echo "absent"` failure
shape from the memory note, reproduced live; **any future run of this check must assert the row
count is non-zero before believing an empty diff.**

---

## 2. The diff

**Against upstream: nothing.** `_http_route_table()` at `75901a295` (the commit serving on
2026-08-02, the day CLAUDE.md was stamped) versus HEAD:

| Change | Routes |
|---|---|
| **Added** | *(none)* |
| **Removed** | *(none)* |
| **Changed** | *(none)* |

Confirmed two independent ways: (a) exact `diff` of the extracted function body, 37 rows vs
37 rows, no output; (b) `git diff 75901a295..HEAD` filtered to route-tuple lines — zero `+`/`-`
hits.

**Against CLAUDE.md: no contradictions, four unrecorded facts.** CLAUDE.md writes the table in
globs (`/api/sessions*`, `/v1/responses*`, `/api/jobs*`, `/v1/runs*`), and every glob is
faithful. But the globs hide detail that dependent work has already had to rediscover:

| # | Unrecorded in CLAUDE.md | Fact | Since |
|---|---|---|---|
| U1 | **`/p/{profile}` multiplex mirror** | **Every one of the 37 routes is registered TWICE** — once bare, once at `/p/{profile}{path}` (`api_server.py:7187-7188`). Live-confirmed: `GET /p/default/health` → 200, `GET /p/default/api/model/options` → 401. | 2026-07-16 (`7aa21e336`) — predates the 08-02 stamp; never recorded |
| U2 | `PATCH` + `DELETE /api/sessions/{id}` | Real rows, covered only by the `/api/sessions*` glob | ≤ 08-02 |
| U3 | `GET` + `DELETE /v1/responses/{id}` | Real rows, covered only by the `/v1/responses*` glob | ≤ 08-02 |
| U4 | `/api/cron/fire` is **conditional** | Appended only `if _CRON_AVAILABLE`. CLAUDE.md lists it unconditionally. Live on the Mac (405 to a GET). | ≤ 08-02 |

U1 is the one that matters: a profile-prefixed request plane the app has never used and the
docs have never mentioned.

### The 37 rows, verbatim (`api_server.py:2041-2092`)

```
GET    /health                                POST   /api/sessions/{id}/chat
GET    /health/detailed                       POST   /api/sessions/{id}/chat/stream
GET    /v1/health                             POST   /api/sessions/{id}/model
GET    /v1/models                             POST   /v1/chat/completions
GET    /api/model/options                     POST   /v1/responses
GET    /v1/capabilities                       GET    /v1/responses/{response_id}
GET    /v1/skills                             DELETE /v1/responses/{response_id}
GET    /v1/toolsets                           POST   /api/platforms/{platform}/events
GET    /api/sessions                          GET    /api/jobs
POST   /api/sessions                          POST   /api/jobs
GET    /api/sessions/{session_id}             GET    /api/jobs/{job_id}
PATCH  /api/sessions/{session_id}             PATCH  /api/jobs/{job_id}
DELETE /api/sessions/{session_id}             DELETE /api/jobs/{job_id}
GET    /api/sessions/{session_id}/messages    POST   /api/jobs/{job_id}/pause
POST   /api/sessions/{session_id}/fork        POST   /api/jobs/{job_id}/resume
                                              POST   /api/jobs/{job_id}/run
POST   /v1/runs                               GET    /v1/runs/{run_id}
GET    /v1/runs/{run_id}/events               POST   /v1/runs/{run_id}/approval
POST   /v1/runs/{run_id}/stop                 POST   /api/cron/fire   [if _CRON_AVAILABLE]
```

---

## 3. ⚠️ Corrections owed

**None of tonight's dispatches are falsified. The two I checked closely are correct** — see C4.

| # | Home | Stale claim | Correction |
|---|---|---|---|
| **C1** | **`OPEN_ITEMS.md` #173**, blockquote "AMENDED same day", dated 2026-07-23 (≈ line 4229) | "the gateway serves a native model API on `:8642` — `GET /api/model/info` / `/api/model/options` / `/api/model/recommended-default` / `/api/model/auxiliary` and `POST /api/model/set`" | **Four of those five do not exist and never did on this plane.** Live: `/api/model/info` 404, `/api/model/recommended-default` 404, `/api/model/auxiliary` 404, `/api/model/set` 404. Only `/api/model/options` is real (401 unauth = registered). **CLAUDE.md already carries this correction; #173 does not.** This is a downstream-corrected/upstream-stale split — the exact shape the close-out rule exists to prevent. Owed: a dated supersession note **inside #173**. |
| **C2** | **`CLAUDE.md`**, route-table paragraph | "**OJAMD self-updated to Hermes v0.20.0 on 2026-08-03 — the table below was verified on 0.19.1; re-verify by live probe before any NEW route claim on 0.20.0**" | **This warning is now discharged.** Re-verified 2026-08-09 against upstream `62431364e`, installed `ceebb21dd`, and a live probe of all 37 routes. Owed: replace the warning with a dated "re-verified 2026-08-09, unchanged since 2026-08-02" stamp — **keeping the standing rule** (`_http_route_table()` is the whole list) intact. |
| **C3** | **`CLAUDE.md`**, same paragraph | Table omits U1–U4 | Add the `/p/{profile}` mirror (U1) at minimum; it is a whole second addressing scheme. U2–U4 are glob-covered and lower priority. |
| **C4** | **`CLAUDE.md`**, same paragraph | Calls `POST /api/sessions/{id}/model` "**the session pin**" | Terminology is now genuinely ambiguous: as of `cef7d1a1e` (2026-08-06) `pinned` is a **real and different** session field (sidebar keep-flag, set via `PATCH /api/sessions/{id}`). Call the model route **"the session model lock"** — which is what its handler and its response object (`hermes.session.model_lock`) call it. I nearly conflated these two myself mid-lane. |
| **C5** | **`OPEN_ITEMS.md` #170b** | "`model` is absent from both the create body and the PATCH whitelist **on 0.19.0**" | **Conclusion still holds on 0.20.0 head** — but the whitelist it cites has since changed, so the supporting detail is stale even though the finding is not. Owed: a dated 0.20.0 re-confirmation (evidence in §4 Q5). |

**Checked and found CORRECT — no correction owed:**

- **`dispatch/FABLE-T27-283-3B-approvals.md`** (tonight's slice 3B dispatch). Its §2.1 states
  "There is no `/api/config` anywhere in that table … Re-verified today, at the current head."
  **Confirmed.** Every line citation it makes is exact: runs family at `:2082-2086`, capability
  flags at `:3122`/`:3124`/`:3151`, `_handle_run_approval` at `:6929`. This lane **corroborates**
  that dispatch rather than falsifying it; its scope ruling stands.
- **`planning/superpowers/research/251-phase3-gap/D-tui-gateway-dossier.md`** — cites the
  `/api/files` family but explicitly attributes it to the **dashboard app** ("because
  `tui_gateway` is served *by the dashboard app*") with `web_server.py` line numbers. Honours the
  two-apps rule correctly.
- **`.../E-feature-menu.md`** — tags `/api/config` as **DASH**. Correct.

---

## 4. The five dependent questions

### Q1 — Is there any `/api/config` or config-mutation route on `:8642`? **NO.**
- **Source:** `grep -nE '/api/(config|files|fs)' gateway/platforms/api_server.py` → **no matches.**
- **Live:** `GET /api/config` → **404**.
- **Attribution:** `/api/config` lives in `hermes_cli/web_server.py`, `hermes_cli/web_routers/mcp.py`,
  `hermes_cli/dashboard_auth/public_paths.py` — **dashboard app only**.
- **Consequence:** mode/config **SELECTION remains dashboard-only**. Slice 3B's scope ruling is
  unchanged and correct.

### Q2 — Has the `/v1/runs` family changed? **Routes: no. Behaviour: yes, twice.**
- **Routes** identical since 2026-08-02: `POST /v1/runs` `:2082`, `GET /v1/runs/{id}` `:2083`,
  `GET …/events` `:2084`, `POST …/approval` `:2085`, `POST …/stop` `:2086`.
- **Live** (GET-probe → 405 proves registration without mutating): `/v1/runs` 405,
  `…/approval` 405, `…/stop` 405; `GET /v1/runs/{id}` and `…/events` → 401 (registered, auth-gated).
- **Behaviour deltas since 08-02** — route-invisible, and relevant to #283/#295/#296:
  - `d9ddfb23d` (08-07) **"interrupt every in-flight API turn on shutdown, not just `/v1/runs`"**
  - `51fa7db46` (08-07) "interrupt api server runs on shutdown timeout"
  - `93964fda3` (08-08) "resolve reasoning for the request's model, not `model.default`"
  - SSE plumbing rewritten 08-04 (`7098862de` poll-loop → `asyncio.Queue`; `1a09b0725`/`7a1f2e3a6`
    all writers through `_sse_frame()`, **`ensure_ascii=False`** — this changes wire bytes for
    non-ASCII payloads).
  - `c750d5354` (08-08) "prevent oversized transcripts from exhausting memory".
  **The `/v1/runs` contract is stable; the machinery under it was substantially reworked this week.**

### Q3 — Any `/api/files` family on `:8642` yet? **NO. CLAUDE.md's dashboard-only record is correct.**
- **Source:** no `/api/files` or `/api/fs` string in `api_server.py`.
- **Live:** `GET /api/files` → **404**, `GET /api/fs` → **404**.
- **#21 Tier 2 is unchanged**: no core file endpoint on the chat plane. Note the standing
  strike-through in the tracker (the "SUPERSEDE WATCH 2026-08-02" block) was **correctly
  retracted** — the family it found is real but is the dashboard's.

### Q4 — Any new `/api/model/*` beyond `/api/model/options`? **NO. #173's four phantoms confirmed still absent.**
- **Source:** the only `/api/model/*` literal in `api_server.py` is `"/api/model/options"`
  (`:2052` table, `:3145` capability advert).
- **Live:** `options` → **401** (registered); `info`, `set`, `recommended-default`, `auxiliary`
  → **404 each**. See correction **C1**.

### Q5 — `POST /api/sessions/{id}/model` — still there, same shape? **YES, present and unchanged.**
- **Route:** `("POST", "/api/sessions/{session_id}/model", self._handle_session_model_lock)`. Live
  GET-probe → **405** (registered).
- **Shape** (`_handle_session_model_lock`): auth → 404 if session unknown → JSON body →
  `_session_runtime_request_from_body` → forces `require_model_lock=True` → **409
  `model_lock_unavailable` if the pick cannot be routed (explicitly refusing silent global
  fallback)** → 500 `model_lock_persistence_failed` → 200 `{object:"hermes.session.model_lock",
  session_id, runtime}`.
- **⚠️ Scope note the question's framing missed:** **#170b as written in the tracker is about
  cron JOBS, not sessions** ("no model picker… `model` absent from the create body and the PATCH
  whitelist", `TaskDetailScreen`). Answering the jobs question directly:
  `_UPDATE_ALLOWED_FIELDS = {"name","schedule","prompt","deliver","skills","skill","repeat","enabled"}`
  (`:5543`) — **`model` and `provider` are still absent. #170b's conclusion holds on 0.20.0.**
- Separately, `PATCH /api/sessions/{id}` **did** change: whitelist `{title, end_reason}` →
  `{title, end_reason, pinned, archived}` (`cef7d1a1e`, 08-06, `:3506`). Different object from the
  model lock — see **C4**.

---

## 5. #148's disposition — **CLOSE it, and replace it with a standing practice**

**Read:** #148 is "Hermes 0.19 'Quicksilver' impact assessment — wire, shim, and behavior deltas
vs Talaria (investigation umbrella)", logged 2026-07-20, structured HIGH/MEDIUM/WATCH against a
changelog.

**Recommendation: close #148 as an umbrella; harvest its live sub-questions into numbered items;
stand up a re-verification *practice* in its place.** Reasoning:

1. **Its subject no longer exists.** It assesses 0.19. Both hosts now report 0.20.0, and the
   version string is not even a reliable identifier — CLAUDE.md's own rule is that head `aec3318`
   shipped calling itself 0.20.0, so "impact of version X" is not a well-formed question here.
2. **The treadmill is measurable, not rhetorical.** The install's reflog shows **~20 updates
   between 2026-07-26 and 2026-08-09** — roughly one per day, several days with 2-3. A one-off
   impact assessment against that cadence is stale before it is written. **Yes: this is exactly
   the treadmill the brief anticipated, and I would say so unprompted.**
3. **Most of it is already resolved and its open remainder is misfiled.** The shim comparison
   resolved via #223 Lane 5 (shim retired from the model path). The reasoning-shape risk resolved
   (`_thinking` is a separate channel, verified). What is genuinely live — the `*_snapshot`
   regression (2026-07-23 note, with an unrun "cheap discriminator") — is a **concrete testable
   defect** that deserves its own number, not burial under a version umbrella. Per #268, a
   version name is not a filing.
4. **The umbrella framing is the actual defect.** "Assess version N" produces a document; "does
   the contract we depend on still hold?" produces a check you can re-run. Tonight took roughly
   one command's worth of real work to answer definitively for the route table — because the
   question was contract-shaped, not version-shaped.

### Proposed practice — "wire contract re-verify", trigger-based, not calendar-based

**Trigger:** before any lane that *designs against the wire* (new route claim, SSE shape
dependency, request/response contract) — **not** on a schedule, and not on `hermes update`.

**Check in a golden copy so the diff is mechanical.** Commit the extracted
`_http_route_table()` body to the repo (e.g. `reference/hermes-route-table.txt`) with its
upstream commit stamp. The check becomes three cheap steps:

1. **Contract diff** — extract `_http_route_table()` from the installed source, `diff` against
   the golden copy. **Assert the row count is non-zero before believing an empty diff** (§1).
2. **Identify what is actually serving** — listener start time
   (`ps -p $(lsof -nP -iTCP:8642 -sTCP:LISTEN -t) -o lstart=,etime=`) cross-referenced against
   `git reflog --date=iso` in the install. This is what turns "the source says X" into "the
   process serving my phone says X".
3. **Liveness sweep, read-only** — GET every route; **405 = registered POST-only, 401 =
   registered and auth-gated, 404 = absent.** No mutation, no session creation, no auth needed.
   This is the technique that let tonight's lane verify all 37 routes including every POST route
   without creating a single object, and it should be written down as the house method.

**Escalate to a full assessment only when step 1 shows a diff.** Then the question is scoped to
what actually moved, and it gets its own tracker number.

---

## 6. Running process vs source — stated separately

**These are the same for routing and different for behaviour. Both statements are load-bearing.**

**ROUTING — no divergence.**
The running Mac process (PID 19532, started 2026-08-07 07:20, serving `01a1037d1` from the
2026-08-05 checkout) carries a `_http_route_table()` **byte-identical to upstream HEAD's**. Every
one of the 37 routes probed live answered 200/401/405 — **not one 404**. So for the route table
specifically, "what the running process does" and "what the next restart will do" **coincide**,
and they coincide for a robust reason: the function has not changed since 2026-08-02, which is
before the running process's checkout.

**BEHAVIOUR — real divergence, at least one instance.**
The running process **predates `cef7d1a1e`** (2026-08-06, "persist session pins instead of 400ing
them") — verified with `git merge-base --is-ancestor cef7d1a1e 01a1037d1` → **false**. So:

| | `PATCH /api/sessions/{id}` with `pinned` |
|---|---|
| **Running Mac process** (`01a1037d1`) | **400** — whitelist is `{title, end_reason}` |
| **Installed head / next restart** (`ceebb21dd`) | **200, persisted** — whitelist is `{title, end_reason, pinned, archived}` |

The running process also predates the 08-07 shutdown-interrupt fixes and the 08-08 reasoning-
resolution fix. **A restart of the Mac gateway changes behaviour on these paths without changing
a single route.** Anything measuring these against the Mac must record the listener start time,
not the version string — both report `0.20.0`.

---

## 7. What I could NOT verify

1. **OJAMD's route table was not probed.** The brief restricts OJAMD to the read-only
   `mcp__hermes-ojamd` MCP, which exposes only health/chat/session tools — no route probe. I
   honoured that and did **not** curl OJAMD. All I can state: it answers, and reports `0.20.0`
   (which, per CLAUDE.md's own rule, proves nothing about which code serves). **OJAMD's running
   process is unpinned — I could not read its reflog or listener start time.** Since OJAMD is the
   host the phone actually talks to, this is the most significant gap here.
2. **`PATCH` and `DELETE` methods were not exercised live.** Verified from source only, because
   sending them is mutation-class. `GET /api/sessions/{id}` → 401 proves the *path* is registered;
   it does not prove the method set. Source is authoritative and unambiguous.
3. **No authenticated probe.** Reading the Mac's `API_SERVER_KEY` was **blocked by the Bash
   permission classifier**, and I did not work around it. Consequence: I could not read
   `/v1/capabilities`' live JSON to confirm the *running* process advertises
   `run_approval_response: true`. Source shows it at `:3122`/`:3124`/`:3151` and the running
   commit contains those lines, so the inference is sound — but it is an inference, not a wire
   observation. If Owen wants it observed, one authenticated `GET /v1/capabilities` closes it.
4. **Response *bodies* were not compared**, only status codes and source. A route can keep its
   path and change its payload shape; §4 Q2 lists five such behaviour commits this week. **The
   route table being stable is not evidence that the wire contract is stable** — that is a
   separate, larger check I did not run.
5. **The 3 commits between installed head and upstream HEAD** were confirmed not to touch
   `api_server.py`; I did not review them for effects elsewhere.
