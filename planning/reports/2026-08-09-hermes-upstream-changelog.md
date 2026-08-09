# Hermes upstream reconnaissance — 2026-08-09

**Upstream repo:** `https://github.com/NousResearch/hermes-agent` — **PUBLIC**, default branch `main`.
Reachable authenticated via `gh` (account `ChronoRixun`, scopes `gist, read:org, repo, workflow`).

**Method:** the live Mac install at `~/.hermes/hermes-agent` is a shallow clone and was read
**read-only only** (`git log`, `rev-parse`, `cat .git/config`). Nothing was fetched, pulled, or
unshallowed. All history claims below come from a **fresh full clone** made in the session
scratchpad (`scratchpad/upstream-hermes`, 21,454 commits), never from the shallow install.

---

## 1. The three heads

### ✅ VERIFIED

| | Commit | Date (committer) | Subject |
|---|---|---|---|
| **Mac install** (`~/.hermes/hermes-agent`) | `ceebb21dd7cb7391a58e4b1d345951e5218860c5` | **2026-08-08 23:00:10 -0700** | `fix: suppress pydantic serializer warnings leaking to the terminal` |
| **Upstream HEAD** (`origin/main`) | `62431364e35aa10ea17a197a344f9b9f774c1a8e` | **2026-08-09 01:24:08 -0500** | `Merge pull request #82233 from kerpopule/fix/desktop-hud-composer-clipping` |

**Measured distance, Mac → upstream: 3 commits. Zero commits ahead.**
`ceebb21` is a verified **ancestor** of `origin/main` (`git merge-base --is-ancestor` → true).

```
f2731da4a | 2026-08-08 | fix(desktop): keep HUD composer within window
bb8280b75 | 2026-08-08 | revert(desktop): roll Electron back to 40.10.2
62431364e | 2026-08-09 | Merge pull request #82233 ... fix/desktop-hud-composer-clipping
```

All three are **desktop-app (Electron) only**. **Nothing on the `:8642` chat plane.**
The Mac install is, for Talaria's purposes, current.

### ❌ UNVERIFIED — OJAMD

**OJAMD's head could not be established.** The read-only `hermes-ojamd` MCP was asked twice
for `git -C C:\Users\Owen\.hermes\hermes-agent log -1`. **Both replies were fabricated.**

| Attempt | SHA returned | Disposition |
|---|---|---|
| 1 | `1d0c7f8e9a2b4c5d6e7f8a9b0c1d2e3f4a5b6c7d` | GitHub API → **HTTP 422, "No commit found for SHA"** |
| 2 | `a1b2c3d4e5f6789012345678901234567890abcd` | Patterned filler; returned *after* being told attempt 1 was fabricated |

Both are visibly synthetic (ascending nibble runs). Attempt 1 also restated CLAUDE.md's
"v0.20.0 / 2026-08-03" almost verbatim — the tell that it was reciting project documentation,
not running a command. Attempt 2 invented a plausible-looking `v0.20.1-hotfix` that does not
exist upstream.

> **⚠️ Standing caution: the `hermes-ojamd` MCP confabulates shell output.**
> It answered a direct, narrowly-scoped, read-only command with invented data twice, including
> once after an explicit correction and an explicit "I cannot run this is a correct answer"
> escape hatch. **Do not treat any factual host claim from that MCP as evidence.** OJAMD state
> must be established by Owen pasting real terminal output, or not claimed at all.

**ASSUMED (not evidence):** OJAMD was last recorded self-updating on 2026-08-03. Whether it has
updated since is **unknown**. Given upstream's cadence, assume OJAMD is stale until proven.

---

## 2. ⚠️ Corrections

### 2a. "OJAMD self-updated to Hermes v0.20.0 on 2026-08-03" — needs a supersession note
**Home:** `CLAUDE.md`, "Hard-won gotchas" → the route-table bullet.

The claim is not falsified (it was true when written), but it is now **misleading as a currency
signal**. The *Mac* install is at 2026-08-08 23:00, roughly **878 commits past** the
`v0.20.0` release tag. Anyone reading that line today would infer our installs sit near the
0.20.0 release. They do not — at least the Mac does not, and OJAMD is unverified.

### 2b. The version string is now provably useless — CLAUDE.md understates this
**Home:** `CLAUDE.md`, OJAMD services → "verify by process start time, not version string".

CLAUDE.md cites head `aec3318` still calling itself 0.20.0. **Confirmed and much larger than
recorded:** `pyproject.toml` at upstream HEAD (2026-08-09, ~878 commits past the release tag)
**still reads `version = "0.20.0"`.** The version string has been frozen at 0.20.0 since
2026-08-03 across the entire window. The existing rule is right; its magnitude was understated.

### 2c. Upstream releases are date-tagged, not semver — undocumented anywhere
Upstream tags are `v2026.8.3`, `v2026.7.30`, `v2026.7.20`, … The `v2026.8.3` tag points at
`3c27eb623 chore: release v0.20.0 (2026.8.3)` — so `0.20.0` **is** `2026.8.3`. Our docs discuss
"0.19.1"/"0.20.0" with no mention that the release channel is date-based. This is a
documentation gap, not an error.

### 2d. The `/p/<profile>/` multiplex route mirror is undocumented
`_http_route_table()`'s own docstring refers to "`/p/<profile>/` mirrors". When
`gateway.multiplex_profiles` is enabled, a `profile_prefix_middleware` mirrors **every** route
under `/p/<profile>/…`. Added **2026-07-16** (`7aa21e336`, `6ff65c4d2`) — it **predates** our
2026-08-02 route verification, so it is not new, but CLAUDE.md's "complete `:8642` table" never
mentions it. Not currently a hazard (off unless configured), but the table is not "the whole
list" while this is unrecorded.

### 2e. ✅ NOT a correction — the route table is confirmed still accurate
Route literal sets extracted from `gateway/platforms/api_server.py` at the `v2026.8.3` tag and
at upstream HEAD are **identical (30 literals, `diff` clean)**, and the set matches CLAUDE.md's
documented table exactly. **Still no `/api/files`, no `/api/fs`, no `/api/config`.** CLAUDE.md's
table survives this window unchanged.

---

## 3. The changelog

**Window:** `3c27eb623` (`v2026.8.3` = the "0.20.0" release, 2026-08-03) → `62431364e`
(upstream HEAD, 2026-08-09). Chosen because it is the window over which our tracker's
behavioural assessments silently went stale.

- **878 commits total** (incl. merges) · **786 non-merge**

### By area (non-merge commit counts, top-level path)

| Commits | Area |
|---|---|
| 458 | `tests/` |
| 145 | `apps/` (Electron desktop app) |
| 141 | `agent/` |
| 133 | `hermes_cli/` |
| 123 | `tools/` |
| 90 | `website/` |
| **77** | **`gateway/`** ← our plane |
| 43 | `plugins/` |
| 36 | `tui_gateway/` |
| 34 | `cron/` · 34 `contributors/` |
| 31 | `skills/` |
| 30 | `hermes_state.py` |

### By commit type

`fix` 433 · `feat` 106 · `test` 60 · `chore` 49 · `refactor` 39 · `docs` 31 · `perf` 22 · `fmt` 17

### Busiest scopes

`fix(desktop)` 71 · `fix(gateway)` 44 · `fix(agent)` 26 · `feat(desktop)` 25 · `fix(cron)` 14 ·
`fix(tools)` 12 · `fix(cli)` 12 · `test(gateway)` 11 · `feat(skills)` 11

**Read:** the overwhelming majority of upstream motion is the **Electron desktop app, the CLI,
the TUI and the test suite** — surfaces Talaria does not touch. Gateway work is 77/786 (~10%),
and the subset landing on the HTTP API server is **12 commits** (§4).

The full list — hash, date, subject, areas touched — is appended in §7.

---

## 4. Areas that touch us

### 4.1 `gateway/platforms/api_server.py` — 12 commits ⚠️ **the one to read**

```
7098862de | 2026-08-04 | perf(gateway): replace SSE poll loop with call_soon_threadsafe-fed asyncio.Queue
7a1f2e3a6 | 2026-08-04 | refactor(gateway): extract _sse_frame() helper, dedup 5 inline SSE encode call sites
1a09b0725 | 2026-08-04 | refactor(gateway): route all three SSE writers through _sse_frame()
221afc0cb | 2026-08-04 | refactor(gateway): route session event stream through _sse_frame (ensure_ascii=False)
cef7d1a1e | 2026-08-06 | fix(api): persist session pins instead of 400ing them
45f23205d | 2026-08-06 | fix(desktop): show every pinned session, however many there are
51fa7db46 | 2026-08-07 | fix(gateway): interrupt api server runs on shutdown timeout
d9ddfb23d | 2026-08-07 | fix(gateway): interrupt every in-flight API turn on shutdown, not just /v1/runs
f346458f2 | 2026-08-07 | fix(cron): surface initial scheduler registration failures
c750d5354 | 2026-08-08 | fix(sessions): prevent oversized transcripts from exhausting memory
a51a4cb09 | 2026-08-08 | fix(api-server): mark replayed tool calls completed in Responses output items
93964fda3 | 2026-08-08 | fix(api-server): resolve reasoning for the request's model, not model.default
```

**Highest relevance to the live #295 branch (`t27-295-expiration-recovery`):**
`d9ddfb23d` + `51fa7db46` change **what the server does to in-flight turns on shutdown** —
previously only `/v1/runs` turns were interrupted; now *every* in-flight API turn is. #295 is
built on assumptions about how a turn dies and whether it is later recoverable. **This is the
single commit pair worth reading in full before #295 closes.**

**SSE encoding (4 commits, 2026-08-04):** all SSE writers now go through one `_sse_frame()`
helper with `ensure_ascii=False`. Our SSE taxonomy notes and any byte-level frame assumptions
(especially the documented "`/v1/runs` events have no `event:` lines, unlike `/chat/stream`")
should be **re-verified by probe**, not assumed — this refactor touched all three writers.

**`c750d5354`** caps oversized transcripts — relevant to long Talaria sessions.

### 4.2 Session/model pinning + model-id/provider path
- **`POST /api/sessions/{id}/model` is UNCHANGED.** `-S'_handle_session_model_lock'` over the
  window returns **zero** commits. The route and its handler survive intact.
- **⚠️ Naming trap:** `cef7d1a1e "fix(api): persist session pins"` is **NOT** the model pin. It
  extends **`PATCH /api/sessions/{id}`** to accept `pinned`/`archived` **booleans** (a UI
  "keep this chat at the top" flag) and adds both to the serialized session. Two different
  things share the word "pin" — do not conflate them when reading upstream commits.
- **Model-switch work did land, off our plane:** `0569c001d`, `0c97a883a` (provider key reads
  through the per-profile secret scope), `b79e83827` (surface candidates on ambiguous alias),
  `21bc9ba34` (date-stamp vs version sort). Plus `e0c3caf3b fix(model-picker): serve cached
  custom-provider catalog on no-probe opens`. These touch the **picker/catalog** path that
  feeds `/api/model/options` — relevant to #223 Lane 5, worth a look if the catalog ever
  looks wrong.
- `93964fda3` resolves reasoning config for **the request's model rather than `model.default`** —
  a real behavioural change for per-request model selection, which is exactly what our
  client-side per-turn lock does.

### 4.3 `/v1/runs` family + approvals
No commit changes the `/v1/runs` **route set or handler signatures** (`-S'_handle_runs'`,
`-S'_handle_run_approval'` → zero hits). All five routes (`POST /v1/runs`, `GET /v1/runs/{id}`,
`/events`, `/approval`, `/stop`) are present and unchanged at HEAD. The only runs-adjacent
behaviour change is the shutdown-interrupt pair in §4.1.

### 4.4 `:8642` bind behaviour on restart
**No commits found** that change bind/listen/port behaviour. The nearest neighbours are the
two shutdown-interrupt commits (§4.1) and `38cd1999c`/`643910afe` (worker-start guard: fail
open and release the admission slot when a history-lookup worker cannot start). **Nothing
suggests the restart/bind story changed.**

### 4.5 Vision / image routing (`agent/image_routing.py`)
**ZERO commits in the window.** Last touched **2026-07-23** (`6bd02ae1a feat(image_routing):
accept vision alias for custom provider models`) — comfortably before our baseline. **Vision
routing is unchanged**; any of our conclusions there remain as valid as they were.

### 4.6 Release-named commits
Only `3c27eb623 chore: release v0.20.0 (2026.8.3)` — the window's own base. **No 0.20.1, no
0.21, no codename.** The `v0.20.1-hotfix` that the OJAMD MCP invented **does not exist**.

---

## 5. Cadence + releases

Two different measurements, both correct, reported with definitions because they disagree
and the gap is fully accounted for:

| Measure | Count | Definition |
|---|---|---|
| **A** | **1,341** | Commits reachable from `main` with **committer date** in the last 7 days (`--since=2026-08-02`) |
| **B** | **878** | Commits **added to `main`** since the `v2026.8.3` tag (topological range) |
| C | 486 | Reachable from the tag *with* a recent committer date — i.e. rebased/merged-late work |

A − B = 463, explained by C (486, less 23 window commits carrying older committer dates). **No
mystery; A counts recently-*committed* work including rebases, B counts newly-*landed* work.**

**Non-merge commits per day:**

```
2026-08-03 :  30
2026-08-04 :  90
2026-08-05 :  73
2026-08-06 :  71
2026-08-07 : 164
2026-08-08 : 344   ← peak
2026-08-09 :   2   (partial day)
```

**Owen's "hundreds of commits in the last few days" is confirmed** — 344 landed on 2026-08-08
alone. First-parent `main` alone saw 1,129 in 7 days.

**Releases/tags to track:** 30 tags, date-scheme `vYYYY.M.D`. Most recent **`v2026.8.3`**
(2026-08-03) = "0.20.0". **Cadence ≈ one tagged release every 1–2 weeks**
(`v2026.7.1`, `v2026.7.7`, `v2026.7.7.2`, `v2026.7.20`, `v2026.7.30`, `v2026.8.3`). A new tag
is **overdue** relative to that rhythm — expect one imminently, and note that `hermes update`
tracks `main`, not tags, so we run far ahead of the last tag at all times.

---

## 6. What this does NOT tell us

Explicit limits. Each of these is a real gap, not a hedge:

1. **OJAMD's actual commit is unknown.** Its MCP fabricated twice. Everything about OJAMD's
   currency in this report is assumption. **The production host the phone talks to is the one
   we could not measure.** This is the biggest gap here.
2. **Commit subjects are not behaviour.** Every §4 claim is "what the diff touches," established
   by path and `-S` pickaxe. **Nothing here was probed against a running gateway.** A commit that
   does not touch `api_server.py` can still change what `:8642` returns, via `agent/`,
   `gateway/` internals, or a plugin — 141 `agent/` and 77 `gateway/` commits landed.
3. **No tracker cross-reference was performed.** The task was reconnaissance. **I did not check
   which OPEN_ITEMS entries these commits fix or falsify** — that is the obvious follow-up, and
   §4.1's shutdown pair vs #295 is the one place I looked far enough to raise a flag.
4. **`-S` pickaxe is a weak negative.** "Zero hits for `_handle_session_model_lock`" means the
   *count of that string* did not change; a same-size edit inside the handler would not appear.
   The route-table diff (§2e) is strong evidence; the handler-level "unchanged" claims are
   moderate evidence only.
5. **The Mac install's *code* was not compared to `ceebb21`.** I verified which commit it
   reports. `hermes update` history, local edits, or a half-install would not show up here.
   CLAUDE.md warns a half-install is possible.
6. **Nothing was verified about the running process.** A gateway started before 2026-08-08 is
   still serving pre-`ceebb21` imports regardless of what the checkout says. **Per CLAUDE.md,
   check process start time.** I did not.
7. **The 3-commit Mac→upstream distance is a snapshot** taken 2026-08-09 against a repo landing
   ~344 commits/day. It is stale within hours.
8. **Vision "unchanged" covers `agent/image_routing.py` only** — not the model catalog or
   provider capability data that feeds it, which did move (§4.2).

---

## 7. Full commit list

786 non-merge commits, `3c27eb623` → `62431364e`, oldest first.
Format: `hash | date | subject | areas touched`

```
dc4714b1e | 2026-07-29 | feat(observability): report model and provider usage | docs/, hermes_cli/, scripts/, tests/
a0476b360 | 2026-07-29 | fix(observability): preserve configured model attribution | hermes_cli/, tests/
8b0c3da8c | 2026-07-29 | feat(observability): aggregate bounded tool metrics | agent/, docs/, hermes_cli/, model_tools.py, scripts/, tests/, tools/
4ad78a98f | 2026-07-29 | fix(observability): derive tool metrics from runtime metadata | docs/, hermes_cli/, tests/
8502e464a | 2026-07-29 | fix(observability): harden tool lifecycle metrics | hermes_cli/, tests/, tools/
f1fd678e4 | 2026-07-29 | feat(observability): add Relay skill metrics | agent/, cron/, docs/, hermes_cli/, scripts/, tests/, tools/
5607d09e0 | 2026-07-29 | feat(observability): add Relay client resource metrics | docs/, hermes_cli/, scripts/, tests/
46bae7504 | 2026-07-29 | feat(observability): add Relay active install metrics | docs/, hermes_cli/, scripts/, tests/
dfb8c1bd4 | 2026-07-29 | fix(observability): preserve shared metrics compatibility | docs/, hermes_cli/, scripts/, tests/
43d29a37c | 2026-07-31 | fix(observability): include auxiliary model routes | agent/, hermes_cli/, tests/
a0c364f8f | 2026-07-31 | test(observability): assert strict client resources | tests/
3b767d890 | 2026-08-02 | exempt android installs from nemo-relay | pyproject.toml
55b3e1ee5 | 2026-08-03 | chore: sync uv.lock with nemo-relay android marker | uv.lock
376370691 | 2026-08-03 | chore: add contributor email mapping for Ahmett101 | contributors/
d1c6c6b58 | 2026-08-03 | perf(moa): cache resolved preset + per-slot runtime to cut cold-start latency (#66793) | agent/, tests/
e6f1d613b | 2026-08-03 | fix(discord): leave voice channels before cancelling the bot task | plugins/, tests/
c0b0cc392 | 2026-08-03 | feat(image): parallelize image_generate batches | agent/, tests/
952d86b79 | 2026-08-03 | fix(file-sync): serialize concurrent sync cycles | tests/, tools/, website/
a7ad713f4 | 2026-08-03 | fix(tool-executor): unpack 5-tuple runnable_calls in _max_workers_for_tool_batch | agent/
9267c7823 | 2026-08-03 | fix: exponential backoff for rate-limit fallback cooldown | agent/
df9dbba2b | 2026-08-03 | fix(backoff): keep 60s first-hit cooldown, escalate only on consecutive rate-limits | agent/, tests/
861ca18c6 | 2026-08-03 | fix(catalog): wire api_key auth headers for http MCP servers | hermes_cli/, tests/
f8f475569 | 2026-08-03 | perf(compressor): release allocator pages after successful compaction | agent/, tests/
00475e1b2 | 2026-08-03 | fix(catalog): validate http+api_key manifests declare the header's env key | hermes_cli/, tests/
23f8ae32c | 2026-08-03 | fix(agent): cap auxiliary LLM concurrency per task | agent/, cli-config.yaml.example, tests/, website/
ddae511ab | 2026-08-03 | fix: thread extra_headers through the call_llm split | agent/
7eefb0931 | 2026-08-03 | fix(nix): tie devShell's HERMES_PYTHON to the venv actually on PATH | nix/
9b9cbdd7e | 2026-08-03 | fix(system_prompt): move skills index to the volatile band | agent/, tests/
9555525a7 | 2026-08-03 | docs(system_prompt): fix stale reconstruct_static_prefix docstring example | agent/
efbfe0842 | 2026-08-03 | fix(prompt_size): search volatile tier for skills block after the stable->volatile move | hermes_cli/
164c3d60b | 2026-08-03 | chore: add contributor email mapping for zabih-sudo | contributors/
f40d63d5d | 2026-08-03 | chore: add contributor email mapping for HAOWANG116 | contributors/
aad8f7412 | 2026-08-03 | fix(backup): serialize and atomically publish snapshots | hermes_cli/, tests/
827bb0dd1 | 2026-08-04 | chore: add contributor email mapping for ElSnacko | scripts/
0845232d7 | 2026-08-04 | fix: prefer explicit anthropic api key | agent/, tests/
a991dfc25 | 2026-08-03 | docs: document /personality none|default|neutral reset across personality docs | website/
9a9b670e2 | 2026-08-03 | fix(relay): avoid concurrent turn scope corruption | agent/, run_agent.py, tests/
704baa5c3 | 2026-08-03 | fix(relay): preserve legacy turn shims | run_agent.py
a2a08fe14 | 2026-08-03 | fix(relay): gate skipped turn metrics | agent/, hermes_cli/, tests/
2e65b0c60 | 2026-08-03 | test(relay): enforce LIFO in overlap regression | tests/
e1caa611b | 2026-08-03 | fix(relay): preserve skipped turn context | agent/, tests/
dac4bbea0 | 2026-08-03 | fix comment about relay workaround | pyproject.toml
3c3ae7428 | 2026-08-03 | feat(models): add qwen3.8-max to Nous portal + OpenRouter catalogs, replacing qwen3.7-max | agent/, hermes_cli/, tests/, website/
91937a6dc | 2026-08-03 | test: swap context-switch-guard fixture off qwen3.8-max-preview | tests/
3a0a29510 | 2026-08-04 | fix(agent): keep context_length pin for named custom providers | agent/
942ff91f2 | 2026-08-04 | test(gateway): cover named-custom context pin on session-info banner | tests/
60c721ada | 2026-08-04 | fix(model_metadata): read llama.cpp context from meta.n_ctx + accept sole model | agent/, tests/
f66d62582 | 2026-08-04 | chore: add contributor email mapping for johnrazmus | contributors/
3b0bb3b8b | 2026-08-04 | fix(gateway): keep event loop alive during /compress and Relay drain | gateway/, tests/
9c88625e2 | 2026-08-04 | fix(gateway): bound go_dormant ws.close with teardown timeout | gateway/
e623432b8 | 2026-08-04 | fix: close the Codex app-server session on agent teardown | run_agent.py, tests/
ba9068c8b | 2026-08-04 | fix(agent): discard bare tool-call marker before fallback/persistence (#78148) | agent/, tests/
70d7e4cbd | 2026-08-04 | fix(agent): repair sessions already contaminated with stale tool-call markers (#78148) | hermes_state.py, tests/
e1a273969 | 2026-08-04 | feat(cli): add sessions clean-markers to permanently purge stale tool-call markers (#78148) | hermes_cli/, hermes_state.py, tests/
e18c040c3 | 2026-08-04 | fix(cli): back up state.db before clean-markers writes by default | hermes_cli/, hermes_state.py, tests/
15d51bb88 | 2026-08-04 | refactor: dedup stale-marker regex — use compiled _STALE_MARKER_RE in conversation_loop | agent/
9938d2050 | 2026-08-04 | fix(conversation_loop): compress messages on output-cap retry path (#55546) | CHANGELOG.md, agent/, docs/, tests/
04098e2b5 | 2026-08-04 | fix(conversation_loop): prune dead vision-strip fallback; harden output-cap retry tests | CHANGELOG.md, agent/, docs/, tests/
78c8bcd12 | 2026-08-04 | chore: drop CHANGELOG.md and docs/reports/ — not shipped with salvage PRs | CHANGELOG.md, docs/
9fc892697 | 2026-08-04 | perf: reuse request_input_estimate instead of recomputing estimate_request_tokens_rough | agent/
743dc94ab | 2026-08-04 | chore: AUTHOR_MAP — add BobClawblaw for PR #77870 salvage | scripts/
9ce917f8a | 2026-08-04 | chore(ci): rerun checks | 
bdc82e39e | 2026-08-04 | perf(gateway): prewarm /model picker cache on TUI startup | tui_gateway/
5c078b987 | 2026-08-04 | test(tui): pin picker-cache prewarm wiring in entry.main() | tests/
dbafb5922 | 2026-08-04 | perf(cli): check local auth.json/config before slow provider registry sweep | hermes_cli/
8f52040dd | 2026-08-04 | test(cli): regression tests pinning auth-first ordering skips registry sweep | tests/
9a20d7f68 | 2026-08-04 | perf(desktop): keep spinner frames out of React commits | apps/
be54f28b1 | 2026-08-04 | test(desktop): cover minimized/hidden window-state + visibilitychange pause for GlyphSpinner | apps/
9076adaca | 2026-08-04 | fmt(js): `npm run fix` on merge (#78271) | apps/, ui-tui/
7098862de | 2026-08-04 | perf(gateway): replace SSE poll loop with call_soon_threadsafe-fed asyncio.Queue | gateway/, tests/
7a1f2e3a6 | 2026-08-04 | refactor(gateway): extract _sse_frame() helper, dedup 5 inline SSE encode call sites | gateway/
1a09b0725 | 2026-08-04 | refactor(gateway): route all three SSE writers through _sse_frame() | gateway/, tests/
221afc0cb | 2026-08-04 | refactor(gateway): route session event stream through _sse_frame (ensure_ascii=False) | gateway/, tests/
fc8e3936a | 2026-08-04 | test: add cross-thread put_threadsafe + long-reasoning tail tests | tests/, ui-tui/
98165daac | 2026-08-04 | fix: reconstruct fused test after conflict resolution | tests/
64882bc68 | 2026-08-04 | perf(tui): bound reasoning-clean input to the displayed tail | ui-tui/
7e344dc0d | 2026-08-04 | test: exercise the production _loop_ref path in put_threadsafe tests | tests/
fb4e17b1e | 2026-08-04 | fix(test): feed the SSE writers an asyncio queue, not queue.Queue | tests/
db0bd4211 | 2026-08-04 | fix(credential-pool): re-select in acquire_lease after a deferred refresh | agent/, tests/
4075c8fd5 | 2026-08-04 | fix(credential-pool): lock the quarantine read-modify-write of _entries | agent/, tests/
cb3e8e9fb | 2026-08-04 | perf(file-ops): eliminate redundant subprocess calls in write_file and V4A patch path | tests/, tools/
eb78ab235 | 2026-08-04 | fix(file-ops): decouple BOM detection from pre_content, add V4A backward compat | pyproject.toml, tests/, tools/
fcae5ad49 | 2026-08-04 | fix(file-ops): surrogatepass in bytes_written encode (review finding) | tools/
8c19e2925 | 2026-08-04 | refactor(file-ops): fold simplify-pass findings | tests/, tools/
622b9a9f9 | 2026-08-04 | chore: update uv.lock for tomli dependency (rebase fix) | uv.lock
1709f82c1 | 2026-08-04 | chore: remove dead tomli dependency declaration | pyproject.toml, tools/, uv.lock
e05eba26a | 2026-08-04 | fix(telegram+sqlite): resolve polling conflict loop + misleading WAL warning | hermes_state.py, plugins/, tests/
e9a8b70fc | 2026-08-04 | chore: map jun@junho.co to junhohong | contributors/
cab8673ea | 2026-08-04 | fix(dashboard): reload loopback tabs after stale session-token closes | apps/, web/
19e697d9c | 2026-08-04 | fix: update ChatPage test import for react-router v7 | web/
b8b17b8ce | 2026-08-04 | fix: wire HermesConsoleModal WS into stale-token reload guard | web/
d2772b420 | 2026-08-04 | fix(xai): honor configured web search backend on Responses path | agent/
29eba9cb0 | 2026-08-04 | test(xai): cover Firecrawl vs native web_search on Responses | tests/
f5be9236e | 2026-08-04 | refactor(xai): simplify _xai_prefers_native_web_search to use registry | agent/, tests/
80c7ccf4a | 2026-08-04 | fix(relay): gate skipped task completion | run_agent.py, tests/
f66319097 | 2026-08-04 | fix(model-switch): treat models dict as metadata, not allowlist | hermes_cli/
e6977f41b | 2026-08-04 | test(model-switch): cover Ollama context_length models dict probing | tests/
91337e578 | 2026-08-04 | fix(desktop): ⌘1 / ⌃Tab return to the chat from a full-page view | apps/
5d24594ab | 2026-08-04 | feat(desktop): expose native OS notifications to plugins via ctx.notifyNative | apps/, skills/, website/
1ed702be7 | 2026-08-04 | refactor(desktop): share render weight between the two transcript budgets | apps/
a538b1c98 | 2026-08-04 | fix(desktop): bound the transcript reaching assistant-ui by render cost (#55191) | apps/
62012a536 | 2026-08-04 | feat(desktop): Show earlier pages the DOM, then pulls older history from the store | apps/
e8ccb4a2e | 2026-08-04 | feat(desktop): ctx.os — the curated OS door for plugins | apps/, skills/, website/
fe859a1f5 | 2026-08-04 | fix(credential-pool): clear exhaustion state on key rotation (#22622) | agent/, scripts/, tests/
2d70f5632 | 2026-08-04 | fix(agent): adopt .env credential/base-url edits at the turn boundary (#67843) | agent/, contributors/, run_agent.py, tests/
97641a820 | 2026-08-04 | fix(debug): say where a client-side log lives instead of "(file not found)" (#78687) | hermes_cli/, tests/
dcd750434 | 2026-08-04 | fix(credential-pool): short cooldown for sole credential on transient throttle | agent/, tests/
d1eb08fcf | 2026-08-04 | fix: thread sole_credential into next_available_at sibling site | agent/, tests/
9cd033868 | 2026-08-04 | fix(credential-pool): bench a billing 403 fully, even as the sole key | agent/, tests/
9712b8f0c | 2026-08-04 | test: teach the hand-rolled fake pools the failure_reason kwarg | tests/
d1196750c | 2026-08-04 | feat(profiles): REST export/import + extra_files overlay hook | hermes_cli/
bde8c4e10 | 2026-08-04 | feat(cli): /export and /import slash commands for profile sharing | cli.py, hermes_cli/
6e7eafc7e | 2026-08-04 | feat(desktop): share a profile as a portable bundle - theme, layout, skills | apps/
b3e45a3d4 | 2026-08-04 | Discord drops an empty outbound message instead of sending it (#78815) | contributors/, plugins/, tests/
ec0c8d9c2 | 2026-08-04 | feat(state): sessions carry read/unread state | hermes_state.py, hermes_state_common.py, tests/
cc8e97499 | 2026-08-04 | feat(desktop): the layout tree moves a tab block as one unit | apps/
33c1d1f26 | 2026-08-04 | feat(desktop): shift-click and opt-click select tabs to drag together | apps/
28b3b0dd1 | 2026-08-04 | feat(gateway): session.workspace.move — re-home a stored session's workspace | hermes_state.py, tui_gateway/
edae3eed1 | 2026-08-04 | feat(desktop): move a session to another project from its row menu | apps/
1d6606d2c | 2026-08-04 | fix(profiles): exported archives open in Finder (GNU tar, not PAX) | hermes_cli/
43717123c | 2026-08-04 | fix(models): a model id missing its vendor prefix says so instead of 404ing (#78856) | agent/, hermes_cli/, tests/
fdc342c08 | 2026-08-04 | fix(models): a model id missing its vendor prefix says so instead of 404ing (#78909) | 
9621f9032 | 2026-08-04 | fix(install): resolve 8.3 profile aliases so a built desktop app stops reporting failure | scripts/
dae7e5477 | 2026-08-04 | test(install): exercise 8.3 normalization by running install.ps1, not by parsing it | scripts/
34833303f | 2026-08-04 | ci(install): actually run the PowerShell installer tests | .github/, scripts/, tests/
84874c58a | 2026-08-04 | feat(dev-sandbox): support fake installer / fake main / git clones | hermes_cli/, nix/, scripts/
3d9ec4d62 | 2026-08-04 | test(install): prove updating from a release reaches this commit | .gitignore, tests/
36cb5ae55 | 2026-08-04 | ci: test updating from sampled release tags, on tag + every 12h | .github/
334c02b77 | 2026-08-04 | test(observability): exercise the active worktree in metrics smoke | scripts/
535a59c5c | 2026-08-04 | docs(observability): clarify active profile identity | docs/
42e92c9c0 | 2026-08-04 | fix(git): kill the whole probe process tree on timeout (port of openai/codex#36793) | hermes_cli/, tests/
aec331899 | 2026-08-04 | chore: suppress windows-footgun false positive on gated killpg | hermes_cli/
652ebc589 | 2026-08-05 | fix(console): handle string SystemExit code in _capture_output | hermes_cli/, tests/
649ce1f81 | 2026-08-05 | fix(cli): make profile.yaml and skin writes atomic to stop silent field loss | hermes_cli/, tests/
63c0bb694 | 2026-08-05 | fix(cli): correct the skin_cmd fallback comment to match the actual read path | hermes_cli/, tests/
a6e1e270b | 2026-08-05 | refactor: trim verbose comments + drop redundant default_flow_style kwarg | hermes_cli/
530d8148a | 2026-08-05 | fix(desktop): scope restored navigation by profile (#67709) | apps/
222101071 | 2026-08-05 | fmt(js): `npm run fix` on merge (#79155) | apps/
34c3f06f9 | 2026-08-05 | fix(cache): scope prompt_cache_key by session to stop cross-session bucket sharing | agent/, plugins/, tests/
c4f3d5a31 | 2026-08-05 | fix(agent): prevent historical steer replay | agent/, tests/
82c6acae6 | 2026-08-05 | chore: add contributor mapping for burak33bb | contributors/
84e93ffef | 2026-08-05 | fix(state): stop delegate/tool children corrupting compression lineage | hermes_state.py, tests/
d55bc063f | 2026-08-05 | fix(delegation): keep subagents alive during slow model waits | agent/, tests/, tools/
62800ddad | 2026-08-05 | docs(delegation): note in-flight model waits count as progress | website/
1be70d635 | 2026-08-05 | fix: join heartbeat thread in finally + add error-path test | agent/, tests/
49d8a155c | 2026-08-05 | fix(terminal): skip binary content on the referenced-script remote-read fallback (#77703) | cron/, tests/, tools/
949babd08 | 2026-08-05 | ci: add detailed logging to live comment poller | scripts/
1d7d0e41a | 2026-08-05 | ci: poll review statuses from artifacts every cycle | .github/, scripts/, tests/
ee7c614ee | 2026-08-05 | fix(ci): follow artifact download redirect without auth | scripts/, tests/
b846f0c00 | 2026-08-05 | fix(desktop): stop dialogs clipping popovers opened inside them | apps/
b818c427c | 2026-08-05 | fix(desktop): mount one worktree dialog instead of one per composer | apps/
cb7f594be | 2026-08-05 | feat(desktop): let convert-a-branch reach remote branches too | apps/
b879df27f | 2026-08-05 | fix(desktop): worktree dialog names the project, not the branch | apps/
eea604409 | 2026-08-05 | feat(desktop): register a Linux launcher entry for `hermes desktop` | hermes_cli/, tests/
b27cdc382 | 2026-08-05 | feat(nix): desktop app icon | nix/
acb590fc4 | 2026-08-05 | fix(nix): fix electron headers sha | nix/
b4312f92c | 2026-08-05 | docs: state the /goal vs Kanban boundary on both pages | website/
abaa43ed7 | 2026-08-05 | docs: add 'Which File Does What?' - one-page map of SOUL/USER/MEMORY/AGENTS | website/
8cc4ff249 | 2026-08-05 | docs: add per-plan subscription billing table to providers page | website/
e20cfd35e | 2026-08-05 | docs: four small accuracy fixes | website/
6cd0aca48 | 2026-08-05 | docs: surface existing answers users can't find (migration, prompt-size, tool-call parsing, Desktop label) | website/
8618eba7c | 2026-08-05 | docs: add security-posture guide for running Hermes on a personal or work machine | website/
a5ab9b2e5 | 2026-08-05 | docs: add troubleshooting checklist for perceived agent-quality regressions | website/
f8aed15cb | 2026-08-05 | docs: warn against pointing two agents at one Hermes home (memory, profiles, FAQ) | website/
7ce6f9794 | 2026-08-05 | docs: explain the slow silent first turn (prefill) on local hardware | website/
2183ed392 | 2026-08-05 | docs: fix stale PATH location in windows-native common pitfalls | website/
cc245e84d | 2026-08-05 | fix: correct cron mid-run restart claim in salvaged docs | website/
105fbf6b7 | 2026-08-05 | feat(wake): client-capture wake word for remote desktop | apps/, hermes_cli/, tests/, tools/, tui_gateway/, website/
d401c27ed | 2026-08-05 | fix(wake): address review on client-capture re-arm and feed queue | apps/, tests/, tui_gateway/
60808dcf7 | 2026-08-05 | fix(wake): auto capture keeps the backend mic when one exists | tests/, tools/
6df3912e0 | 2026-08-05 | perf(desktop): coalesce wake.feed frames | apps/, tui_gateway/
dfc1cbebb | 2026-08-05 | docs(config): document wake_word.capture in cli-config.yaml.example | cli-config.yaml.example
069551d19 | 2026-08-05 | fix(desktop): preview remote HTML over SSH (#76008) | apps/
17a5a9587 | 2026-08-05 | fix(desktop): open remote file rows in the in-app preview | apps/
7c33b806a | 2026-08-05 | chore: fix import order, map contributor email | apps/, contributors/
18ed612e5 | 2026-08-05 | fmt(js): `npm run fix` on merge (#79496) | apps/
c8648278c | 2026-08-05 | In-app browser and previews are real layout-tree tabs (#77705) | apps/
c6fe31a9b | 2026-08-05 | test(desktop): expect client_capture in wake.start/status params | apps/
c8fdc5174 | 2026-08-05 | fix(desktop): render remote PDFs in preview rail | apps/
9e9b3fc66 | 2026-08-05 | fmt(js): `npm run fix` on merge (#79505) | apps/
950b55d4d | 2026-08-05 | feat(update): emit an action-scoped terminal receipt from hermes update | hermes_cli/, tests/
eb68ffbe4 | 2026-08-05 | fix(desktop): make remote backend updates terminal-state driven | apps/
64646dda5 | 2026-08-05 | Hermes can read the in-app browser (#79482) | agent/, apps/, run_agent.py, tests/, tools/, toolsets.py, tui_gateway/, website/
25c7827ec | 2026-08-05 | fmt(js): `npm run fix` on merge (#79521) | apps/
fb402106f | 2026-08-05 | fix(dashboard): auto-reconnect the events WebSocket with backoff (supersedes #47876, #47921, #24315) (#79524) | web/
ced8e3021 | 2026-08-05 | feat(scripts): reproducible core-toolset A/B eval harness (toolperf_abeval) | scripts/
bf6a210ab | 2026-08-06 | fix(cache): make proactive pruning durable and cache-aware | agent/, hermes_cli/, hermes_state.py, tests/
565b2c42e | 2026-08-06 | refactor(state): extract shared model_config merge helper | hermes_state.py
241605d1e | 2026-08-06 | fix(compression): durable-sync the prune runway on model switch + fast no-op for incapable stores | agent/, tests/
a9acb400b | 2026-08-05 | feat(providers): add Actual Computer inference provider | agent/, hermes_cli/, plugins/, run_agent.py, tests/
b6d55a790 | 2026-08-05 | fix: adapt Actual provider salvage to current main | hermes_cli/, plugins/, tests/
e79f16cab | 2026-08-05 | feat(providers): env-var metadata, config-driven local no-auth, reasoning-effort clamp for Actual | agent/, hermes_cli/, tests/
5aa798fec | 2026-08-05 | feat(skills): actual-setup optional skill + provider docs | optional-skills/, tests/, website/
d1f9e7775 | 2026-08-05 | chore: map justin@actual.computer to somewheresy for #26491 salvage | contributors/
c46027b04 | 2026-08-06 | fix(gateway): stop payload-less split delivery from swallowing finals | gateway/
a2ca5c2a7 | 2026-08-06 | test(gateway): cover payload-less split-delivery final-send swallow | tests/
392e3a8c5 | 2026-08-06 | fix(gateway): finish the split-delivery bug class so the fix cannot duplicate or still swallow | gateway/, tests/
68ebb198c | 2026-08-06 | fix(gateway): don't claim deleted head chunks as delivered in the empty-fallback recovery | gateway/, tests/
80f37e36e | 2026-08-06 | fix(cron): don't let a cron job inherit a kanban worker's dispatcher identity | agent/, cron/, model_tools.py, tests/, tools/
145e77731 | 2026-08-06 | test(cron): close a blind spot in the kanban env drift guard | tests/
7112fbcbc | 2026-08-05 | fix(nix): update electron sha | nix/
5d83400f8 | 2026-08-06 | fix(agent): bound the concurrent start-order gate wait | agent/
042a2cf3d | 2026-08-06 | fix(agent): keep the start-order gate under the batch deadline and abort abandoned workers | agent/, tests/
9ea01979d | 2026-08-06 | chore: map contributor email for @sylbae | contributors/
1d2dabce5 | 2026-08-06 | fix(sessions): escape LIKE wildcards in prune/archive substring filters | hermes_state.py, tests/
b37de0192 | 2026-08-06 | fix(sessions): escape LIKE wildcards in the cwd-prefix clause | hermes_state.py, tests/
4bab91944 | 2026-08-06 | refactor(sessions): use _escape_like in _cwd_prefix_clause | hermes_state.py
55e70f570 | 2026-08-06 | test(sessions): guard the Windows backslash child arm of _cwd_prefix_clause | tests/
52a5fc004 | 2026-08-06 | refactor(state): consolidate SQL LIKE escaping onto one shared helper | hermes_state.py, hermes_state_common.py, hermes_state_search.py
67827dd99 | 2026-08-06 | fix(cli): route the remaining destructive user-file rewrites through atomic writes | hermes_cli/, tests/
c005546cb | 2026-08-06 | test(cli): skip the permission-preservation cases on Windows | tests/
4541d3018 | 2026-08-06 | fix(cli): keep newly created SOUL.md and distribution.yaml at 0644 | hermes_cli/, tests/
3556728a5 | 2026-08-06 | refactor(utils): move mode+owner preservation into atomic_write_text | hermes_cli/, tests/, utils.py
43fc86562 | 2026-08-06 | fix(utils): tighten create_mode semantics and close the yaml 0600 transit window | tests/, utils.py
c0d974b19 | 2026-08-06 | fix(gateway): escalate the session-hygiene compaction cooldown on repeat failures | agent/, gateway/, tests/
ca120413f | 2026-08-05 | fix(tests): forward HERMES_TEST_* knobs through the hermetic runner | scripts/
03dc4aad5 | 2026-08-06 | fix: hide memory tool from cron agents | cron/, tests/
5c5f1a6b7 | 2026-08-06 | chore: AUTHOR_MAP for @dromai (PR #42700 salvage) | contributors/
9a9cf6ae8 | 2026-08-05 | fix(cron): tolerate NUL bytes in referenced-script paths at os.open | tests/
71f1b371c | 2026-08-06 | perf(ci): 12 test slices — cut the merge-gate critical path ~33% | .github/
7c6f9affd | 2026-08-06 | fix(file): align grep fallback regex behavior | tests/, tools/
9baf92b7f | 2026-08-06 | test(search): update grep command mirrors to -rnHE for fidelity with production | tests/
b2598b41e | 2026-08-05 | feat(read_file): widen document extraction to PDF/legacy Office/ODF/RTF/EPUB via optional anydoc | tests/, tools/, uv.lock
be1740d11 | 2026-08-05 | chore: revert incidental uv.lock churn (no dependency changes) | uv.lock
169758d42 | 2026-08-06 | perf(tests): cut test_hermes_state.py 52s -> 10s — kill sleep throttle + per-row seeding | tests/
0afeaaa0a | 2026-08-05 | fix(gemini): prevent user message merge into adjacent function response | agent/, tests/
4e7e103ba | 2026-08-05 | fix(gemini): interpose placeholder model turn between tool result and user text | agent/, tests/
01a1037d1 | 2026-08-05 | chore: map contributor email for rille111 | contributors/
997a913a5 | 2026-08-05 | fix(read_extract): retry anydoc init after failure instead of sticky disable | tests/, tools/
ffdbc883e | 2026-08-05 | fix(read_extract): cap anydoc input size before conversion | tests/, tools/
ff3793fdf | 2026-08-05 | fix(read_file): stop promising anydoc conversion in the tool schema | tools/
6e041d524 | 2026-08-05 | feat(goals): quality gates — deterministic commands that must pass before /goal completes | gateway/, hermes_cli/, tests/, website/
6518aa184 | 2026-08-05 | feat: /heartbeat — recurring session re-entry prompt fired when idle | agent/, cli.py, gateway/, hermes_cli/, tests/, website/
8f2712725 | 2026-08-05 | feat: /refine — run the memory/skill self-improvement review on demand | agent/, cli.py, gateway/, hermes_cli/, run_agent.py, tests/, website/
aaf968851 | 2026-08-06 | refactor(gateway): extract the hygiene recovery gate and forward the failure reason | gateway/, tests/, website/
3305cfd2b | 2026-08-06 | fix(agent): measure batch-deadline exclusion at the human wait, not authorization-gate residency | agent/, tests/, tools/
10fb01e72 | 2026-08-06 | fix: harden human-wait tracker from review findings | agent/, tests/, tools/
ea0d54db1 | 2026-08-06 | refactor: fold /simplify-code findings | agent/, tests/, tools/
c8d48b8b1 | 2026-08-06 | fix(cron): make the lifecycle guard total — sanitize at ingestion, not per-syscall | cron/, tests/, tools/
c135b88d2 | 2026-08-06 | fix: address 4-angle review findings on the guard-total change | cron/, tools/
863e31318 | 2026-08-06 | fix: close simplify-pass findings — scheduler sibling site + home-unresolvable totality | cron/, tests/, tools/
70de95892 | 2026-08-06 | fix(cron): lifecycle guard — never crash on binary referenced paths, stop matching lifecycle words inside SQL/text | cron/, tests/
c4aea3231 | 2026-08-06 | fix(db): never downgrade journal mode on a database with concurrent openers | hermes_state.py, tests/
19fc9c103 | 2026-08-06 | fix(tests): fail hard when pytest resolves the production state.db (live-DB isolation guard) | gateway/, hermes_state.py, tests/
6e9cae6ac | 2026-08-06 | fix(tests): resolve guard's production root via expanduser, immune to Path.home monkeypatches | hermes_state.py
60e1f7517 | 2026-08-06 | fix(delegation): surface a child's undelivered steer instead of dropping it | tests/, tools/, tui_gateway/, website/
a94ebf5f5 | 2026-08-06 | fix(delegation): harden steer lifecycle ownership | tests/, tools/, tui_gateway/, website/
9d4ef04ed | 2026-08-06 | fix(delegation): bind steering to session generation | tests/, tools/, tui_gateway/
0957277f2 | 2026-08-06 | refactor(skills): move polymarket to optional-skills/finance | optional-skills/, website/
a1e4c905f | 2026-08-07 | fix(launchd): stop stranding gateway label on plist reload | hermes_cli/, tests/
65b7151db | 2026-08-07 | fix(launchd): require a supervised PID to call a reload successful | hermes_cli/, tests/
9d213918e | 2026-08-07 | chore: map rjhilgefort@gmail.com -> rjhilgefort in contributor directory | contributors/
fe3a1cad6 | 2026-08-07 | fix: align helper PID check with Python parser + dedupe drain-wait | hermes_cli/
7ad9ace2c | 2026-08-06 | fix(agent): the desktop's tools reach it on remote and cloud backends too | tests/, tools/, toolsets.py, tui_gateway/
ac745a0b0 | 2026-08-06 | docs(agents): surface capability belongs to the session, not the process env | AGENTS.md, apps/
f88f6f8e6 | 2026-08-06 | docs(reference): document the desktop_ui toolset | website/
226b095a5 | 2026-08-07 | Fireworks user agent (#80422) | plugins/, tests/
cef7d1a1e | 2026-08-06 | fix(api): persist session pins instead of 400ing them | gateway/, tests/
fd9fc50dd | 2026-08-06 | fix(desktop): stop dropping pinned sessions past the page limit | apps/
daeedf67c | 2026-08-06 | fix(desktop): hold the pin write guard until a page confirms it | apps/
256aac54d | 2026-08-06 | fix(desktop): show a pinned session once, and keep its drag order | apps/
03b759db8 | 2026-08-06 | fix(desktop): rank dragged sessions inside their date group | apps/
7eb461d69 | 2026-08-06 | refactor(desktop): share how a tool row renders | apps/
31459ef0c | 2026-08-06 | feat(desktop): price a turn by what it paints | apps/
75717d29e | 2026-08-06 | feat(desktop): stop hiding a session behind Show earlier | apps/
0265797b8 | 2026-08-06 | fix(desktop): keep elapsed status text from overlapping | apps/
45f23205d | 2026-08-06 | fix(desktop): show every pinned session, however many there are | apps/, gateway/
eb8421ba9 | 2026-08-07 | fmt(js): `npm run fix` on merge (#80725) | apps/
0f8366180 | 2026-08-06 | fix(reasoning): keep gpt-5.x summary parts as separate blocks on the chat wire | agent/, tests/
6bb630ef7 | 2026-08-06 | fix(codex): split reasoning summary parts on summary_index | agent/, tests/
a5cddcd8d | 2026-08-06 | fix(desktop): render already-glued reasoning as separate blocks | apps/
6f1072c83 | 2026-08-06 | fix(desktop): drop the gateway-pill dogfood plugin | apps/
fc05247be | 2026-08-06 | fix: preserve session history when a turn crashes | agent/, tests/, tools/, tui_gateway/
bdee48928 | 2026-08-07 | fix(dashboard): derive the stale-schema read probe from SCHEMA_SQL | hermes_cli/, hermes_state_schema.py, tests/
eb1e63090 | 2026-08-06 | fix(skills): align hermes-agent-skill-authoring with hardline authoring standards | skills/, website/
32e7fb07a | 2026-08-06 | feat(/learn): expansive knowledge-base skills for books and large corpora | agent/, tests/, website/
7ab42dda6 | 2026-08-06 | fix: dispatch cronjob(action='run') to the background like delegate_task | tests/, tools/
3671c9f18 | 2026-08-06 | fix: share in-flight cron dedupe between ticker and manual runs | cron/, tests/, tools/
7a5fe0024 | 2026-08-06 | fix(cron): deliver manual runs on gateway loop | tests/, tools/
fa9641999 | 2026-08-06 | test(cron): add _build_job_prompt extra_prompt regression tests | tests/
66c60f81b | 2026-08-06 | fix(cron): thread per-run prompt through cronjob(action='run') (#57331) | cron/, tests/, tools/
358d55051 | 2026-08-06 | fix(plugins): use asyncio.wait_for instead of ClientTimeout in Matrix standalone send | plugins/
71dc211b9 | 2026-08-06 | docs(cron): document async manual runs and per-run prompt context | website/
988f2baaf | 2026-08-07 | fix(sessions): recover compression parents without continuations | agent/, hermes_state.py, tests/
95a7058e4 | 2026-08-07 | fix(sessions): fence expired orphan recovery leases | hermes_state.py, tests/
a0801b878 | 2026-08-07 | fix: bind continuation-marker exclusions to the queried parent (fail-open fix) | agent/, hermes_state.py, tests/
98408f713 | 2026-08-07 | fix(teams): lazy-install SDK via registry check_fn | plugins/, tests/
042c309ec | 2026-08-07 | docs(teams): native gateway start and Hermes-venv dependency install | website/
0d32607c6 | 2026-08-07 | fix(gateway): split check_fn (passive probe) from ensure_deps_fn (active installer) | gateway/, hermes_cli/, plugins/, tests/, website/
a658dfe50 | 2026-08-07 | fix: address self-review findings on the check_fn/ensure_deps_fn split | gateway/, hermes_cli/, plugins/, tests/, website/
f5784617e | 2026-08-07 | refactor: fold simplify-code review findings | plugins/, tests/, website/
99237a444 | 2026-08-07 | refactor: derive teams install hint via feature_install_command(venv_pip=True) | plugins/, tests/, tools/
a1e5ccb32 | 2026-08-07 | fix(cron): bound TERMINAL_CWD lock acquire with timeout (#79768) | cron/
65de109ef | 2026-08-07 | fix: notify_all on lock timeout to wake blocked readers | cron/
56fbac6b3 | 2026-08-07 | fix(gateway): preserve archived compaction history on /retry | gateway/, tests/
30c1421ac | 2026-08-07 | fix(gateway): make retry archive preservation fail-safe | gateway/, tests/
2d9b809ff | 2026-08-07 | fix(yuanbao): preserve archived history on recall redaction | gateway/
51fa7db46 | 2026-08-07 | fix(gateway): interrupt api server runs on shutdown timeout | gateway/, tests/
d9ddfb23d | 2026-08-07 | fix(gateway): interrupt every in-flight API turn on shutdown, not just /v1/runs | gateway/, tests/
416d2a015 | 2026-08-07 | fix(gateway): re-signal interrupts when work is still live at settle-window exit | gateway/, tests/
788b8ab49 | 2026-08-07 | fix(compress): preserve in-flight tool chain across context compression (#79278) | agent/, tests/
c4c2265f0 | 2026-08-07 | chore: map craig@shotflame.local -> Shotflame in contributor directory | contributors/
03beb662e | 2026-08-07 | fix: cover the partial multi-call batch in the in-flight exemption | agent/, tests/
1fe53bd1a | 2026-08-07 | docs: comment accuracy — pending-ness is a presumption, not a construction guarantee | agent/
dacdae014 | 2026-08-07 | chore: map contributor cwt@users.noreply.github.com → Wintle | contributors/
e245a9878 | 2026-08-07 | fix(matrix): propagate sender MXID + reply context to MessageEvent | gateway/, plugins/, tests/
e8511efe7 | 2026-08-07 | fix(matrix): propagate sender + reply context to media MessageEvents too | plugins/, tests/
6ab7528c3 | 2026-08-07 | refactor(matrix): extract _strip_reply_fallback to deduplicate text+media handlers | plugins/
d4a753ea4 | 2026-08-07 | fix(voice): drop playback-phase barge transcripts that echo Hermes' own TTS | cli.py, tests/, tools/
b7bff6f2d | 2026-08-07 | fix(voice): catch short echoed fragments of longer multi-sentence TTS replies | tests/, tools/
979bf0cc4 | 2026-08-07 | fix(voice): require minimum evidence for fragment echo matching, use char windows | tests/, tools/
20e01f935 | 2026-08-07 | fix(voice): early-exit sliding window on match, clear barge phase in finally, fix test helper | cli.py, tests/, tools/
ee6d79648 | 2026-08-07 | fix(state): finish the #80216 bug class — archive-preserving rewrites at the two remaining sibling sites | acp_adapter/, hermes_state.py, tests/, tui_gateway/
cb066a971 | 2026-08-07 | fix(cron): bound the inline non-streaming call with a stale watchdog | agent/, tests/
d7fb503c2 | 2026-08-07 | docs: note that the non-stream stale budget covers cron and subagents | website/
1e5b50744 | 2026-08-07 | fix(cron): move watchdog state under the request lock; fail closed on resolver errors | agent/, tests/
a82910c37 | 2026-08-07 | test: fold review findings — plain fixture, call-shaped probe guard, public-API row counting | tests/
293e67328 | 2026-08-07 | fix(agent): preserve auto-routed provider identity | agent/, tests/
c95a1b717 | 2026-08-07 | fix(auxiliary): widen effective provider to relay, logging, and endpoint detection | agent/
8b6dd27cd | 2026-08-07 | test(auxiliary): update _resolve_auto patch to _resolve_auto_route | tests/
e60ca1c6c | 2026-08-07 | fix(agent): stop the send-path repair from rewriting persisted history | agent/, tests/
cd152d9da | 2026-08-07 | chore: map ahmetsonersancak@anadolu.edu.tr -> 0xGr1mm for attribution | contributors/
c18e19c3c | 2026-08-07 | fix(agent): make the send-path copy structural — close the write-through class | agent/, tests/
1a02e8a79 | 2026-08-07 | fix(agent): preserve destroyed tool-call argument bytes in the WARNING log | agent/
83902620c | 2026-08-07 | chore: map soheil.fakour@gmail.com -> thatssoheil for attribution | contributors/
cf755f5c4 | 2026-08-07 | fix: redact .env terminal output via detection instead of known-env-var list | agent/, tests/
15d7103aa | 2026-08-07 | fix: harden .env-read detection — review follow-ups for #61352 | agent/, tests/
8563fe343 | 2026-08-07 | fix(redact): close emission gaps - env suffix keys, control-char splits, process(list) (#77484) | agent/, tests/, tools/
5444f6853 | 2026-08-07 | test(redact): harden new #77484 tests - assert fragments, opaque values (review) | tests/
e9d1551e6 | 2026-08-07 | fix(redact): strip control chars from mask_secret display (#55319, #55321) | agent/, tests/
8969ebac1 | 2026-08-07 | fix(secrets): redact command in process checkpoint file (#77484) | tests/, tools/
aecb9ca89 | 2026-08-07 | fix(redact): don't join across controls when a fragment already matches | agent/, tests/
4d84aa2a6 | 2026-08-07 | fix(cron): preserve concurrent creates when saving jobs.json | cron/
5511ec623 | 2026-08-07 | test(cron): cover jobs.json shrink-merge against concurrent creates | tests/
261aef526 | 2026-08-07 | perf(cron): stat-stamp fast path for the shrink-merge; no caller-list mutation | cron/, tests/
f346458f2 | 2026-08-07 | fix(cron): surface initial scheduler registration failures | cron/, gateway/, hermes_cli/, plugins/, tests/, tools/
afb46fdab | 2026-08-07 | refactor(cron): polish registration partial-failure surfaces | cron/, hermes_cli/, tests/, tools/
9377c5a53 | 2026-08-07 | fix(redact): narrow control-split join guard to line-crossing spans | agent/, tests/
72b730526 | 2026-08-07 | polish: document newline residual, reuse span local, cheap check first | agent/
f73457803 | 2026-08-07 | fix(streaming): flag empty tool-call args on clean stream end (#80498) | agent/, tests/
e6f31b07c | 2026-08-07 | test(streaming): cover mixed tool-call and retry-exhaustion paths for #80498 | tests/
458ce7b2b | 2026-08-07 | fix(streaming): close the same mid-tool-call drop gap on the Anthropic path | agent/, tests/
69cf06a82 | 2026-08-07 | chore: map texasich commit email to GitHub login | contributors/
11ce6419c | 2026-08-07 | fix(cron): fail closed when the TERMINAL_CWD lock times out (#79768) | cron/
5fcca432f | 2026-08-07 | test(cron): cover bounded TERMINAL_CWD lock acquisition | tests/
30679b876 | 2026-08-07 | test(cron): pin fail-closed TERMINAL_CWD lock timeout behavior | tests/
bf2e193a0 | 2026-08-07 | fix(cron): review follow-ups for the fail-closed cwd-lock timeout | cron/
c24ff38c5 | 2026-08-07 | fix(gateway): make a history-dropping submit prove it meant to | apps/, tests/, tui_gateway/
2ef294f02 | 2026-08-07 | docs: spell out the rewind contract on prompt.submit | website/
29af112cd | 2026-08-07 | fix(gateway): fail closed when session turn lease times out | gateway/, tests/
b2b681fef | 2026-08-07 | fix(gateway): harden turn-lease timeout rejection | gateway/, tests/, website/
b3e9e9170 | 2026-08-07 | fix(gateway): configure turn lease timeout via yaml | cli-config.yaml.example, gateway/, hermes_cli/, tests/, website/
3a3aed3c1 | 2026-08-07 | fix(gateway): keep pending turn lease acquires registered | gateway/, tests/
2a0d0bc69 | 2026-08-07 | refactor(gateway): drop dead degraded token field; de-churn salvage diff | gateway/, tests/
dfa0de92c | 2026-08-07 | chore: add contributor email mappings for dombejar + toprakeker | contributors/
7141a6dc3 | 2026-08-07 | fix(gateway): queue reconnect before fatal disconnect wedges (#80598) | gateway/, plugins/
95e78556f | 2026-08-07 | test(gateway): cover fatal-handler queue-before-disconnect (#80598) | tests/
e5e96e8bb | 2026-08-07 | fix: harden _await_disconnect_step against outer cancellation + add claim keys | gateway/, plugins/
025fc7e74 | 2026-08-07 | fix(slack): dedupe thread-qualified channel lookups (#80668) | gateway/, tests/
f3ec2f36f | 2026-08-07 | perf(slack): parallelize conversations.info lookups with asyncio.gather | gateway/
23dce021a | 2026-08-07 | perf(fts): drain trash tables with a high-water marker instead of re-scanning | hermes_state_search.py, tests/
b7eb97a83 | 2026-08-07 | fix(vision): stream image and video downloads with chunk-by-chunk size cap | tests/, tools/
5c6aff143 | 2026-08-07 | fix(desktop): keep the chat in front of the terminal in Focus layout (#81019) | apps/
a683ef95d | 2026-08-07 | feat(stt): pre-upload silence trim for cloud providers | cli-config.yaml.example, hermes_cli/, tests/, tools/, website/
3277eb887 | 2026-08-07 | refactor(stt): fold review findings into the cloud silence trim | tests/, tools/
5cff192b3 | 2026-08-07 | docs(stt): document the 12s short-clip gate for the cloud trim | cli-config.yaml.example, website/
7b006ea6e | 2026-08-07 | feat(stt): idle unload for local whisper model | cli-config.yaml.example, hermes_cli/, tests/, tools/, website/
72c63aa58 | 2026-08-07 | fix(stt): close idle-unload races — strong model ref, single long-lived watcher | tests/, tools/
e7667e56d | 2026-08-07 | docs(stt): honest memory-behavior wording for idle unload | cli-config.yaml.example, hermes_cli/, website/
6d89b1065 | 2026-08-07 | fix(agent): project real usage in preflight defer instead of fixed growth tolerance | agent/, tests/
3737bb1ad | 2026-08-07 | docs(compression): correct the projection's safety claims (review findings) | agent/
6d3ff6eda | 2026-08-07 | fix(agent): stop reference-only compaction handoff from becoming the active turn | agent/, run_agent.py, tui_gateway/
b9636b104 | 2026-08-07 | test(agent): cover reference-only handoff sole-active-turn regression | tests/
4eabb595f | 2026-08-07 | fix(agent): finish the #80622 bug class — sibling predicates, refund ordering, prompt carve-out, honest skip response | agent/, cli.py, gateway/, hermes_cli/, tui_gateway/
fecba5afc | 2026-08-07 | refactor(agent): fold simplify findings — DB picker parity, single scan, canonical strip delegation | agent/, hermes_state_search.py, tests/
79625e3c0 | 2026-08-07 | tui_gateway: session.resume abandons the profile SessionDB it opens | tests/, tui_gateway/
be14a4bee | 2026-08-07 | tui_gateway: close dedicated profile SessionDB handles at teardown too | agent/, run_agent.py, tests/, tui_gateway/
813793db2 | 2026-08-07 | test(tui_gateway): pin the raising-close swallow + no-retry contract | tests/
4a3942d94 | 2026-08-07 | fix: show explicit member spend cap message instead of 'no credits' | agent/, hermes_cli/, tests/
a4b235c4b | 2026-08-07 | fix(desktop): virtualize git file-tree to cap DOM nodes (#77257) | apps/
48e2dcd7a | 2026-08-07 | fmt(js): `npm run fix` on merge (#81102) | apps/
5ded99af4 | 2026-08-07 | chore: add prashantjain25 to AUTHOR_MAP | scripts/
6bbe55dd0 | 2026-08-07 | fix(gateway): bound the agent cache by memory, not just count and age | gateway/, hermes_cli/, tests/
2d0c2682c | 2026-08-07 | docs: document the gateway agent cache memory budget | docs/, website/
83bad5cdd | 2026-08-07 | fix: follow-ups for salvaged PR #80795 | gateway/, tests/
fb435aae9 | 2026-08-07 | perf(model): disk-cache custom-provider /v1/models probes | hermes_cli/, tests/
7cf71c32b | 2026-08-07 | fix: follow-ups for salvaged PR #80740 | acp_adapter/, hermes_cli/, tests/
563f0a6fd | 2026-08-07 | feat(cli): add `hermes approvals test` — dry-run approval verdict CLI | hermes_cli/, tests/
6dff2109a | 2026-08-07 | feat(cron): monitor-mode jobs — hash-suppressed change detection | cron/, hermes_cli/, tests/, tools/
04e8a661f | 2026-08-07 | feat(cron): per-job durable notepad — KV scratchpad surviving scheduled runs | cron/, hermes_cli/, tests/
ed903f953 | 2026-08-07 | feat(cron): pre-dispatch configuration validation (blocked_config + alert-once) | cron/, hermes_cli/, tests/, website/
94bc3194b | 2026-08-07 | feat(delegation): validate batch task quality before spawning children | tests/, tools/
d7635e43b | 2026-08-07 | feat(delegation): surface per-delegation cost in the result entry | tests/, tools/
5396da844 | 2026-08-07 | docs: DX sweep — 7 verified-absent documentation items | website/
5db1b72b1 | 2026-08-07 | feat(cli): global emergency stop — `hermes pause` / `hermes resume` | agent/, cron/, gateway/, hermes_cli/, tests/
9fad45fcd | 2026-08-07 | feat(kanban,mcp): orphaned-card reconciliation + per-server MCP identity header | gateway/, hermes_cli/, tests/, tools/, website/
37cc99992 | 2026-08-07 | feat(mcp): collapse const-only anyOf/oneOf unions to property enums | tests/, tools/
c8369e37f | 2026-08-07 | feat(mcp): trust-tier gating for write-capable MCP tools via readOnlyHint | tests/, tools/, website/
fe66596df | 2026-08-07 | feat(security): protected agent-instruction files always require write approval | hermes_cli/, tests/, tools/
e166159f2 | 2026-08-07 | feat(vision): optional region zoom crop on vision_analyze | tests/, tools/
d6ee58b58 | 2026-08-07 | feat(delegation): optional structured-output schema on delegate_task | tests/, tools/
0ebaa490b | 2026-08-07 | test: use valid 2-task batches in schema-rejection tests | tests/
1006faa6f | 2026-08-07 | feat(doctor): add opt-in `hermes doctor --live` real-call backend probes | hermes_cli/, tests/
c228d1c55 | 2026-08-07 | fix(dashboard): fold one-field doctor category into general tab | hermes_cli/
5c29566e8 | 2026-08-07 | feat(terminal): graceful degradation for remote backend connection failures | cli.py, gateway/, hermes_cli/, tests/, tools/
bc80a0be5 | 2026-08-07 | test: stub EnvironmentConnectionError in environments.base module stub | tests/
6e87d43a5 | 2026-08-07 | fix(tools): lazily bring up sandbox for vision_analyze reads | tests/, tools/
920eaf2fc | 2026-08-07 | chore(relay): require 0.7.1 | pyproject.toml, uv.lock
c5117655b | 2026-08-07 | feat(plugins): validate portable agent packages | docs/, hermes_cli/, tests/
ca78c6d7a | 2026-08-07 | feat(plugins): load portable agent components | hermes_cli/, tests/, tools/, website/
e288d93fc | 2026-08-07 | fix(review): harden portable plugin boundaries | docs/, hermes_cli/, tests/, tools/, tui_gateway/, website/
6575fb0f8 | 2026-08-07 | fix(plugins): preserve opaque stdio commands | hermes_cli/, tests/
8cb066404 | 2026-08-07 | fix(plugins): address portable MCP review feedback | docs/, hermes_cli/, tests/
47a35d63c | 2026-08-07 | Port from superagent-ai/grok-cli: verify subsystem (run-recipe detection + environment manifest + hermes verify smoke runner) | agent/, hermes_cli/, tests/
cc1acfb22 | 2026-08-07 | fix: Windows-safe process-group teardown in verify runner (footgun CI) | agent/
fa1a5c048 | 2026-08-07 | Integrate verify subsystem with the existing verification stack | agent/, hermes_cli/, tests/
a62eaaf31 | 2026-08-07 | fix(desktop): self-retry transient boundary errors, reactive edit composer context | apps/
0405c2664 | 2026-08-07 | fix(desktop): recover root boundary from tapClientLookup races | apps/
bb9434d30 | 2026-08-07 | fix(desktop): match current assistant-ui lookup errors | apps/
24b7ca725 | 2026-08-07 | fix(desktop): preserve root recovery through StrictMode replay | apps/
c015663b2 | 2026-08-07 | fix(models): corrupt-at cache rows degrade to live fetch in cached_provider_model_ids | hermes_cli/, tests/
ff2fa40b1 | 2026-08-07 | feat(skills): add document-to-action-items | skills/
7b8d0d800 | 2026-08-07 | chore(skills/document-to-action-items): tighten to hardline standards, move to optional | optional-skills/, skills/, tests/, website/
78bc9acdf | 2026-08-07 | chore(skills/document-to-action-items): promote to bundled tier | skills/, tests/, website/
aaa4299a2 | 2026-08-07 | fix(gateway): normalize common repo root separators in the git probe | tui_gateway/
4cefba3ec | 2026-08-07 | fix(desktop): stop rendering a repo's main checkout as a duplicate sidebar lane | tests/, tui_gateway/
690dc87a8 | 2026-08-07 | chore: map contributor email | contributors/
ae6eb578b | 2026-08-07 | fix(desktop): add workspace-cwd ownership so switches are atomic | apps/
416e025c4 | 2026-08-07 | fix(desktop): rebind the Files pane cwd when switching sessions | apps/
9cdbeceda | 2026-08-07 | fix(desktop): don't let a named session.info rehome a fresh draft | apps/
6ff052479 | 2026-08-07 | fix(tui_gateway): report a lazy session's own cwd, not the launch dir | tests/, tui_gateway/
cdc10cd78 | 2026-08-07 | test(desktop): cover the Files-pane cwd desync bug class | apps/
fab99e828 | 2026-08-07 | refactor(desktop): one resolver for stale runtime-session recovery | apps/
3c4f5c521 | 2026-08-07 | fix(desktop): recover image/file attach and /compress after a stale session drop | apps/
c1305b645 | 2026-08-07 | fix(desktop): recover checkpoint restore and tile actions after a stale session drop | apps/
37aaecf48 | 2026-08-07 | test(desktop): cover the stale-session recovery bug class | apps/
8370141f1 | 2026-08-07 | fmt(js): `npm run fix` on merge (#81259) | apps/
eaeba6474 | 2026-08-08 | feat(agent): add skip_background_review flag to AIAgent constructor | agent/, run_agent.py, tests/
d3e3c6234 | 2026-08-08 | feat(cron): set skip_background_review=True; doc title-generation non-presence | cron/
15927c1d2 | 2026-08-08 | feat(cron): add usage_audit.jsonl logger for cron token leak instrumentation | cron/, tests/
7307f8899 | 2026-08-08 | fix: follow-up for salvaged PR #18255 | contributors/, cron/, tests/
005421d88 | 2026-08-07 | fmt(js): `npm run fix` on merge (#81276) | apps/
099eb7373 | 2026-08-08 | fix(terminal): isolate local background executors in their own systemd cgroup (#70716) | tests/, tools/
7cfa90d90 | 2026-08-08 | fix(terminal): address review gaps — PTY isolation, unit-name kill, --quiet (#70716) | tests/, tools/
21de22a4e | 2026-08-08 | fix(terminal): fully-qualified .scope unit name, exit-code check, already_exited cleanup (#70716) | tests/, tools/
6774760b6 | 2026-08-08 | fix(gateway): recover exact turns after unclean exits | gateway/, tests/
59a128c6f | 2026-08-08 | fix(gateway): harden active turn marker lifecycle | gateway/, tests/
69397937d | 2026-08-08 | fix(terminal): serialize systemd scope capability probe | tests/, tools/
0690fd77c | 2026-08-08 | fix(terminal): make systemd cleanup gateway-safe | tests/, tools/
5f9308322 | 2026-08-08 | fix(terminal): bound isolated worker memory | tests/, tools/
b0346ba42 | 2026-08-08 | fix(terminal): align worker limit with local guard | tests/, tools/
5ff328cc7 | 2026-08-08 | fix(gateway): make active turn markers failure-atomic | gateway/, tests/
46b531422 | 2026-08-08 | fix(terminal): harden scope fallback and memory override | tests/, tools/
c5e032c80 | 2026-08-08 | fix(gateway): close ambiguous recovery cleanup gaps | gateway/, tests/, tools/
b5c211678 | 2026-08-08 | fix: defer O(n) fallback_data construction to failure path in _save_entry | gateway/
a8c50eb1d | 2026-08-08 | fix: relax start_new_session assertion for systemd scope path | tests/
b3aa561fa | 2026-08-07 | add Hermes headers to Fireworks provider (#81321) | plugins/, tests/
9c69d9886 | 2026-08-07 | fix(terminal): preserve SSH remote home cwd | gateway/, hermes_cli/, tests/, tools/, tui_gateway/
0db11f995 | 2026-08-08 | fix(desktop): keep the transcript whole when resuming a running session | apps/
8560dc6b9 | 2026-08-08 | feat(desktop): let a composer draft move between windows | apps/
7b0dbd224 | 2026-08-08 | feat(desktop): HUD mode window and its session handoff | apps/
e8b83f37c | 2026-08-08 | feat(desktop): the HUD surface — Spotlight bar with a fading chat band | apps/
6a01b429d | 2026-08-08 | feat(desktop): reach HUD mode from the titlebar and a keybind | apps/
f9860b050 | 2026-08-08 | fix(desktop): size the HUD band to its transcript | apps/
d57927f3b | 2026-08-08 | fix(desktop): stop the composer's two collapse stages landing together | apps/
6ada733f9 | 2026-08-08 | fix(desktop): HUD sizing — empty band, stranded exit chip, early stacking | apps/
ba4456ab0 | 2026-08-08 | fix(desktop): don't flip the HUD's fade when the bar parks at the top | apps/
0e260b3c8 | 2026-08-08 | fix(desktop): grow the HUD band smoothly, and flip on the visible panel | apps/
f99d29124 | 2026-08-08 | fix(mcp): let a server that 401s at startup come back after re-login | tests/, tools/
a3d57f18c | 2026-08-08 | fix(desktop): open HUD mode on the tab you're looking at | apps/
e6b168855 | 2026-08-08 | fix(gateway): keep auto vision preprocess concise | contributors/, gateway/, tests/
52c9aee3b | 2026-08-08 | fix(gateway): move _profile_scope and config I/O off the event loop in async handlers | hermes_cli/, tests/
965a54878 | 2026-08-08 | fix(gateway): serialize config mutations and finish the router off-loop sweep | hermes_cli/, tests/
4ecdee38a | 2026-08-08 | fix(dashboard): close config-RMW gaps left by the off-loop sweep | hermes_cli/
c360333a3 | 2026-08-08 | test(dashboard): deterministic lock gating + plugin-providers RMW regression | tests/
e52acf76a | 2026-08-08 | fix(gateway): keep media history reads off event loop | gateway/, tests/
271867f6f | 2026-08-08 | fix(gateway): bound media history workers | gateway/, tests/
38cd1999c | 2026-08-08 | fix(gateway): fail open + release admission slot when history-lookup worker cannot start | gateway/
0d312126a | 2026-08-08 | test(gateway): de-flake history-lookup timing tests; add worker-start-failure regression | tests/
643910afe | 2026-08-08 | refactor(gateway): narrow worker-start guard to Exception | gateway/
c750d5354 | 2026-08-08 | fix(sessions): prevent oversized transcripts from exhausting memory | apps/, gateway/, hermes_cli/, hermes_state.py, tests/, tui_gateway/, web/, website/
f0794640f | 2026-08-08 | feat(sessions): config-gate transcript safety limits | hermes_cli/, hermes_state.py, tests/, tui_gateway/
2607dc9a8 | 2026-08-08 | fix(desktop): forward pagination params through the remote session interceptor | apps/
5b4b9bbf7 | 2026-08-08 | fix(sessions): tip-only resume guard on the CLI mid-setup path; fail open on guard errors | hermes_cli/, tests/, tui_gateway/
e8b05dc6c | 2026-08-08 | perf(dashboard): keyset pagination for streaming session export | hermes_cli/, hermes_state.py, tests/
ad59bd92c | 2026-08-08 | test(desktop): align renamed message-fetch mocks; brace query-param guards | apps/
edf2cb4bf | 2026-08-08 | perf(sessions): skip counting entirely when transcript guards are disabled | hermes_state.py, tests/
a8ccd5212 | 2026-08-08 | refactor(sessions): accurate scope wording for tip-only resume rejections | hermes_cli/, hermes_state.py
2d5e93161 | 2026-08-08 | fmt(js): `npm run fix` on merge (#81589) | apps/
c7a5de7d6 | 2026-08-08 | fix(cron): make pause authoritative against half-paused records | cron/, hermes_cli/, tests/, tools/
2ddd24ec1 | 2026-08-08 | fix: use is_job_runnable/effective_job_state in remaining pause-check sites | hermes_cli/, tools/
e3be3b048 | 2026-08-08 | fix(wake-word): capture at native input rate | tests/, tools/
5077665b8 | 2026-08-08 | test(wake-word): verify resampled audio values | tests/
2e18e2972 | 2026-08-08 | fix(gateway): self-reacquire scoped lock by PID alone | gateway/
e54ba2ade | 2026-08-08 | test(gateway): cover null start_time scoped-lock self-reacquire | tests/
077e6170a | 2026-08-08 | test(gateway): cover same-PID differing non-null start_time self-reacquire | tests/
3a04d9c4d | 2026-08-08 | fix(simplex): use structured /_send for DM text messages to prevent silent drops | plugins/, tests/
eb048772f | 2026-08-08 | fix(simplex): use structured /_send for standalone DM text sends | plugins/, tests/
0041fc694 | 2026-08-08 | refactor(simplex): hoist json.dumps above branch in _standalone_send | plugins/
9f582aca1 | 2026-08-08 | fix(agent): read Telegram rich_messages config from correct path | agent/, tests/
95520b812 | 2026-08-08 | fix(agent): fail open on malformed telegram extra config | agent/, tests/
a4af26263 | 2026-08-08 | fix: revert except ImportError back to except Exception | agent/
367dda813 | 2026-08-08 | fix: print transform_llm_output appended content after CLI streaming | agent/, cli.py
1f5a22264 | 2026-08-08 | fix: add model and provider to agent:end hook payload | gateway/
b68a53229 | 2026-08-08 | fix: handle replacement transforms after CLI streaming | cli.py, gateway/, tests/, website/
ff7af1cba | 2026-08-08 | chore: map kweiner contributor email | scripts/
063f6941e | 2026-08-08 | fix: drop redundant None-guard on agent_result in agent:end payload | gateway/
2a9f5b347 | 2026-08-08 | fix(agent): classify session-persistence failures so lock contention is not misdiagnosed as disk-full | agent/, cron/, run_agent.py, tests/
01bc8a875 | 2026-08-08 | fix(gateway): honest recovery message for session-persistence failures instead of 'unknown error' | gateway/, tests/
64c342c1c | 2026-08-08 | feat(doctor): state.db health stats — size, WAL, FTS shape, holders, growth warnings | hermes_cli/, hermes_state.py, tests/
a24cbaf42 | 2026-08-08 | review: tracked ro-connection for stats, single WAL warning, hedged locked-cause wording | hermes_cli/, hermes_state.py, run_agent.py, tests/
1005a057f | 2026-08-08 | review follow-ups: canonical classifier in hermes_state, compression-busy=locked, hedged gateway wording, drop dead constant | cron/, gateway/, hermes_cli/, hermes_state.py, run_agent.py, tests/
f444e0c5e | 2026-08-08 | feat(desktop): point an open HUD at the tab you toggle from | apps/
10c153059 | 2026-08-08 | refactor(desktop): put the HUD toggle beside the layout editor | apps/
4500b4391 | 2026-08-08 | feat(desktop): frost the HUD band and fade it in three states | apps/
c5332b2f8 | 2026-08-08 | fix(desktop): stop the HUD going click-through under its own dialogs | apps/
aed114a69 | 2026-08-08 | fix(agent): treat max-iteration nudge as synthetic during compaction | agent/, tests/
98e96e1a6 | 2026-08-08 | refactor(agent): drop the run_agent classify_persistence_error delegating wrapper | agent/, run_agent.py, tests/
d6511aecb | 2026-08-08 | fix(compression): preserve clarify responses | agent/, tests/
6433d5723 | 2026-08-08 | fix(compression): make clarify summaries UTF-8 safe | agent/, tests/
cf1863c87 | 2026-08-08 | test(compression): cover clarify persistence path | tests/
3090e9e87 | 2026-08-08 | fix: reject forged clarify summaries | agent/, tests/
39056e8de | 2026-08-08 | fix(compression): filter clarify non-response sentinels; share prune floor constant | agent/, tests/
d81f2f49e | 2026-08-08 | refactor(compression): fold simplify findings — dedup floor constant, drift-guard test | agent/, tests/
6ea01262f | 2026-08-08 | fix(honcho): recover memory from mid-session oauth 401s and tell the user once | plugins/, tests/
ecfc427b2 | 2026-08-08 | fix(honcho): skip memory calls while the oauth grant is dead | plugins/, tests/
b1414baa0 | 2026-08-08 | fix(honcho): stop classifying bare '401' digits as auth errors; redact session-side auth logs | plugins/, tests/
da1f8779e | 2026-08-08 | style(honcho): trim auth recovery comments to one line each | plugins/
864035b24 | 2026-08-08 | fix(honcho): route every authenticated sdk call through one 401-recovery helper | plugins/, tests/
086dc8b88 | 2026-08-08 | fix(honcho): surface the auth notice when session init itself fails | plugins/, tests/
edfe4f513 | 2026-08-08 | refactor(honcho): dedupe refresh-failure handling; harden exchange budget, dogpile cooldown, and rebuild race | plugins/, tests/
520a1e781 | 2026-08-08 | fix(honcho): keep _pop_auth_notice tolerant of minimal fake managers; make fast-path test binding | plugins/, tests/
b35cacf8b | 2026-08-08 | fix(opencode-go): route gpt-* models to /v1/responses (codex_responses) | hermes_cli/, tests/
b3344502f | 2026-08-08 | chore: map Axmr1 email + update stale Go routing docstring | contributors/, plugins/
e3698fd8d | 2026-08-08 | chore: AUTHOR_MAP for WolftacDigital (PR #49945 salvage) | contributors/
2181d2e7c | 2026-08-08 | fix(tools): bound tool error bodies at the dispatch boundary | tests/, tools/
84bc43007 | 2026-08-08 | fix(tools): bound the truncation log so it stops re-dumping the full body | tests/, tools/
ad59d5533 | 2026-08-08 | fix(tools): bound the exception text dispatch writes into its own log line | tests/, tools/
206531a1e | 2026-08-08 | feat(tools): detect git mutations targeting the running source checkout | tests/, tools/
ecbe6ef0d | 2026-08-08 | feat(tools): hard-block self-repo git mutations in terminal_tool | tests/, tools/
a9f94022b | 2026-08-08 | fix(agent): bind finalize_turn at import time | agent/
f0a3ef8bd | 2026-08-08 | fix(tools): harden live source checkout guard | agent/, tests/, tools/
886092bc5 | 2026-08-08 | fix(tools): block worktree removal and moves of the running source root | tests/, tools/
658329708 | 2026-08-08 | feat(doctor): report per-database journal mode with WAL-reset exposure | hermes_cli/, tests/
a96a4621f | 2026-08-08 | feat(doctor): show database size and the repair command for exposed databases | hermes_cli/, tests/
c5c040cb3 | 2026-08-08 | fix(agent): clean up the session tail when the continuation ceiling is exhausted | agent/, tests/
c8cf8bfdb | 2026-08-08 | fix(agent): strip length-continuation marks from outgoing api messages | agent/, tests/
4cc3ea01f | 2026-08-08 | fix(agent): separate continuation fragments so joined text does not glue | agent/, tests/
bb311b395 | 2026-08-08 | fix(tools): parse bash option grammar before extracting the -c script | tests/, tools/
cd869f26f | 2026-08-08 | perf(tools): stop safe git commands spawning alias-lookup subprocesses | tools/
daa139c9e | 2026-08-08 | fix(tools): classify git bisect as a worktree mutation | tests/, tools/
39db9d111 | 2026-08-08 | refactor(tools): unify the tool-error cap on one constant | model_tools.py
df0a5c3ee | 2026-08-08 | refactor(doctor): reuse backup's size formatter for database listings | hermes_cli/, tests/
c8e558c72 | 2026-08-08 | fix(tools): keep non-bash -c invocations covered by the shell guard | tests/, tools/
4af8fb214 | 2026-08-08 | fix(ssl_guard): tolerate truststore SSLContext.get_ca_certs() NotImplementedError on Windows | agent/, tests/
728989849 | 2026-08-08 | refactor: consolidate five duplicate byte formatters into hermes_cli.sizefmt | agent/, hermes_cli/, tests/
973c14b57 | 2026-08-08 | refactor: fold simplify findings — 6th copy in update_cmd, drop dead wrapper + speculative kwarg, behavior-contract tests | agent/, hermes_cli/, tests/
52920747e | 2026-08-08 | perf(ci): build only en locale in docs-site-checks | .github/, website/
a978f769b | 2026-08-08 | Inspired by Cursor: MCP config context variables (${userHome}, ${workspaceFolder}, ...) | tests/, tools/, website/
f2e936dad | 2026-08-08 | fix(video): read analyze inputs through terminal backend | tests/, tools/
9eb3ac50f | 2026-08-08 | fix(video): route terminal-backend reads through the shared media resolver | tests/, tools/
f46636bfe | 2026-08-08 | fix(vision): retry container exec-read for Docker cold-start, surface stderr (#76566) | tests/, tools/
c5f5fa40c | 2026-08-08 | feat: --resume latest keyword and --in DIR launch flag | hermes_cli/, tests/, website/
ebb242d81 | 2026-08-08 | feat(skills): add email-inbox-triage | skills/
90badaa28 | 2026-08-08 | chore(skills/email-inbox-triage): tighten to hardline standards | skills/, tests/, website/
2a743e5f4 | 2026-08-08 | fix(image_gen): confine generation source images to the terminal backend | tests/, tools/
72eda946b | 2026-08-08 | fix(security): redact terminal exception results and ACP stderr logs (#77484) | acp_adapter/, tests/, tools/
89c14aeb9 | 2026-08-08 | fix(read_file): warn when PDF pages yield no text (scanned-image coverage gap) | skills/, tests/, tools/
530d37820 | 2026-08-08 | fix(terminal-tool): redact terminal error result fields | tests/, tools/
1405d330e | 2026-08-08 | Port from superagent-ai/grok-cli: description-aware slash-menu fuzzy scoring | tests/, tui_gateway/, ui-tui/
2e2fcc09f | 2026-08-08 | Port from superagent-ai/grok-cli: directory-chain AGENTS.md loading | agent/, tests/, website/
70c6cf8e7 | 2026-08-08 | feat: add new FAL video families and image models | plugins/, tests/, tools/
1dee73400 | 2026-08-08 | Inspired by Cursor: fail-closed hook semantics + exit-code-2 blocking | agent/, hermes_cli/, tests/, website/
57ca5995c | 2026-08-08 | fix(learn): extend existing skills during relearning | agent/, tests/
fb4664f79 | 2026-08-08 | fix(learn): process large sources incrementally | agent/, tests/
8de3ddb9e | 2026-08-08 | fix(tools): preserve document extraction boundaries | tests/, tools/
765940df7 | 2026-08-08 | fix(read_extract): keep scanned-PDF coverage warning on the backend bytes path | tests/
c5f71f9a5 | 2026-08-08 | docs: document read_file document extraction and the scanned-PDF coverage warning | website/
5dc0fa388 | 2026-08-08 | fix: post-merge audit follow-ups for #81138/#81139/#81141/#81148 | agent/, cron/, gateway/, hermes_cli/, tests/, tools/
a51a4cb09 | 2026-08-08 | fix(api-server): mark replayed tool calls completed in Responses output items | gateway/, tests/, website/
29783634b | 2026-08-08 | feat(skills): add github-issue-to-pr | skills/
ef9d5f8c0 | 2026-08-08 | chore(skills/github-issue-to-pr): de-router, fold in maintainer issue-to-PR discipline | skills/, tests/, website/
2b16a6b03 | 2026-08-08 | feat(image_gen): add FAL Nano Banana 2 model | plugins/, tests/, tools/
cd9fbf9f1 | 2026-08-08 | test: convert NB2 catalog snapshot test to invariants; live-verified t2i+edit | contributors/, tests/
cbb8cee47 | 2026-08-08 | fix(read_file): surface document extraction failures instead of the generic binary-file error | tests/, tools/
464e7e4e5 | 2026-08-08 | fix(docker): read attached binary files in backend (#76577) | agent/, apps/, tests/, tools/, tui_gateway/
fe54ab4f9 | 2026-08-08 | fix(docker): close the cold-container and multi-backend gaps in attachment delivery | package-lock.json, tests/, tools/
7c2bc87f8 | 2026-08-08 | feat(read_extract): label each unreadable PDF gap with its preceding section text | tests/, tools/, website/
d3fca90fa | 2026-08-08 | test(tests): stabilize write_json concurrent serialization flake | tests/
7c02bfce8 | 2026-08-08 | fix(slack): insert resolved display names literally when humanizing mentions | plugins/, tests/
9e2d37250 | 2026-08-08 | feat(skills): add google-workspace-daily-brief | skills/
ac662c3f7 | 2026-08-08 | chore(skills/google-workspace): fold daily-brief into references/, not a sibling skill | skills/, tests/, website/
d135f64b5 | 2026-08-08 | fix(curator): protect cron skills referenced by absolute path | cron/, tests/
3d7dda4cf | 2026-08-08 | fix(docs): retain prior builds' hashed assets across Pages deploys | .github/
2389564d8 | 2026-08-08 | fmt(js): `npm run fix` on merge (#81849) | apps/, ui-tui/
8dcebded5 | 2026-08-08 | feat(skills): add meeting-action-items | skills/
a6ede70c2 | 2026-08-08 | chore(skills/meeting-action-items): tighten to hardline standards | skills/, tests/, website/
406501fd9 | 2026-08-08 | feat(agent): read_window_below tool — which OS window is underneath the desktop app | agent/, run_agent.py, tests/, tools/, toolsets.py, tui_gateway/
f22ae7292 | 2026-08-08 | feat(desktop): answer window.read.request with the window below | apps/
f463a7e8e | 2026-08-08 | build(desktop): stage get-windows like node-pty | apps/, package-lock.json
beda5149d | 2026-08-08 | test: pin read_window_below into the toolset + post-hook contracts, appease eslint | apps/, tests/
0c2cdcccc | 2026-08-08 | fix(build): win32 get-windows staging must skip the tarball's bundled darwin binding | apps/, tools/, website/
73997c41b | 2026-08-08 | fix(tts): split long speech by provider and platform limits | cli.py, gateway/, hermes_cli/, tests/, tools/, website/
843c3abcc | 2026-08-08 | fix(desktop): an empty HUD thread shouldn't paint a blank panel | apps/
a7dd88543 | 2026-08-08 | fix(gateway): support Docker /workspace media paths in gateway delivery | gateway/, tests/
238351a60 | 2026-08-08 | fix(gateway): widen container->host media translation to home, cache, and in-process gateways | gateway/, tests/
d7072ab91 | 2026-08-08 | feat: add DCP context engine | agent/, tests/, website/
9841a6c65 | 2026-08-08 | fix: rewire DCP context engine to current main architecture | agent/, hermes_cli/, tests/
206f74baa | 2026-08-08 | Revert "feat: add DCP context engine" | agent/, tests/, website/
0647bf988 | 2026-08-08 | Revert "fix: rewire DCP context engine to current main architecture" | agent/, hermes_cli/
2b48ba024 | 2026-08-08 | fix: clean up SkillEvaluator Tier 1 security findings in bundled skills | optional-skills/, skills/
51570f4da | 2026-08-08 | feat: replace Anthropic office document skills with clean-room MIT implementations | skills/, tests/, website/
fad88cf13 | 2026-08-08 | feat: extend clean-room office skills toward full parity | skills/
f03fc4684 | 2026-08-08 | fix(desktop): don't frost the HUD window the sheet isn't covering | apps/
edb27240e | 2026-08-08 | fmt(js): `npm run fix` on merge (#81914) | apps/
fce314eab | 2026-08-08 | feat(skills): advisory SKILL.md convention linter on create | tests/, tools/
092ff2b9a | 2026-08-08 | fix: suppress windows-footgun false positives in linter pattern list | tools/
93964fda3 | 2026-08-08 | fix(api-server): resolve reasoning for the request's model, not model.default | gateway/, tests/
60942fc78 | 2026-08-08 | feat(docs): replace local lunr search with Algolia DocSearch | website/
56d9e75db | 2026-08-08 | feat(skills): add product-price-monitor | skills/
20fece3b4 | 2026-08-08 | chore(skills/product-price-monitor): cron-recipe shape + price-watch blueprint | cron/, skills/, tests/, website/
50f742f8e | 2026-08-08 | fix(skills): pin text-mode file I/O to UTF-8 in comfyui and pdf skill scripts | skills/, tests/
36f73df13 | 2026-08-08 | fix(skills): widen BOM-tolerant reads to all comfyui workflow-JSON call paths | contributors/, skills/, tests/
5e1b50115 | 2026-08-08 | feat(compression): native OpenAI Responses server-side compaction for gpt-5.6 | agent/, cli-config.yaml.example, hermes_cli/, tests/, website/
6eaea9c70 | 2026-08-08 | feat(skills): add weekly-review-planning | skills/
99fa93035 | 2026-08-08 | chore(skills/weekly-review-planning): hardline polish + wire task blueprints to their skills | cron/, skills/, tests/, website/
da6f0030a | 2026-08-08 | feat(config): resolve ephemeral prompt from display.personality | hermes_cli/
a0d406dcd | 2026-08-08 | fix(personality): stop writing personality into agent.system_prompt | cli.py, gateway/, hermes_cli/, tui_gateway/
fe9e4d177 | 2026-08-08 | test(personality): regression coverage for #81791 | tests/
5cc4c2d30 | 2026-08-08 | feat(skills): add social-media-content-calendar | skills/
91a545ab1 | 2026-08-08 | chore(skills/social-media-content-calendar): tighten to hardline standards, ship optional | optional-skills/, tests/, website/
c55f50a5b | 2026-08-08 | fix: ensure utf-8 encoding in jobs.json | cron/
4af7f0550 | 2026-08-08 | fix(gateway): write cron delivery output files as UTF-8 | tests/
f1c13377a | 2026-08-08 | test(cron): regression coverage for Windows encoding cluster | tests/
4b4b607e5 | 2026-08-08 | chore: contributor mapping for zcj1122-rgb | contributors/
0ac32cf82 | 2026-08-08 | fix: restore corrupted warning emoji in batch_runner checkpoint handler | batch_runner.py
5b50a582e | 2026-08-08 | fix(batch): normalize checkpoint warning emoji spacing (salvage follow-up for #32982/#66680) | batch_runner.py
022d196f3 | 2026-08-08 | fix(telegram): honor UTF-16 entity offsets | plugins/, tests/
1bb261251 | 2026-08-08 | fix(gateway): tolerate invalid UTF-8 update output | gateway/, tests/
70957591f | 2026-08-08 | fix(update): handle UnicodeDecodeError in interactive update prompts | hermes_cli/, tests/
0b73330f7 | 2026-08-08 | test(update): strengthen UnicodeDecodeError regression to assert_not_called() | tests/
65f407184 | 2026-08-08 | fix(email): never let unknown or malformed charsets abort the IMAP fetch | plugins/, tests/
a024ccd66 | 2026-08-08 | test(gateway): regression tests for UTF-16 chunk limits at the Telegram boundary (#55844) | tests/
d871cda17 | 2026-08-08 | chore: contributor email mapping for salvaged commits | contributors/
c5a1a5d7b | 2026-08-08 | fix(environments): surrogateescape-safe stdin piping, always close stdin (#79178) | tests/, tools/
b0594118a | 2026-08-08 | fix(environments): surface stdin write failures as stdin_error (#79178) | tests/, tools/
d6eda8d9c | 2026-08-08 | fix(file_operations): reject unencodable surrogates early, hash with surrogateescape (#79178) | tests/, tools/
73cbc5e73 | 2026-08-08 | test(file_operations): pin early surrogate rejection over the backstop (#79178) | tests/
45aa902c1 | 2026-08-08 | fix(process_registry): surrogateescape-safe PTY stdin writes (#79178) | tests/, tools/
8b799fa77 | 2026-08-08 | fix(cli): scrub lone surrogates before oneshot stdout write | hermes_cli/, tests/
566b5b16a | 2026-08-08 | fix(agent,gateway): class-level lone-surrogate chokepoints (#80366 #55143 #55309 #50959 #19819) | agent/, contributors/, gateway/, tests/
aa1fac980 | 2026-08-08 | fix(cli): read .env as utf-8-sig so a BOM doesn't drop the first key | hermes_cli/, tests/
b76498ba0 | 2026-08-08 | fix(cli): strip UTF-8 BOM on latin-1 .env fallback path | hermes_cli/, tests/
ece678db9 | 2026-08-08 | fix(cli): apply BOM-safe .env decoding to hermes send's private loader | hermes_cli/, tests/
762f1c588 | 2026-08-08 | fix(auth): read auth stores as UTF-8 to prevent credential loss on Windows | hermes_cli/, tests/
2fda6a384 | 2026-08-08 | fix(auth): cover remaining auth.json readers across modules | agent/, hermes_cli/, tests/, tools/
b11627b5d | 2026-08-08 | test(auth): cover the two remaining Windows-encoding readers | tests/
2e227d74f | 2026-08-08 | fix(gateway): read auth.json as UTF-8 in _read_nous_provider_state | tests/, tools/
f2feb6f37 | 2026-08-08 | fix(tools): make json_parse tolerate UTF-8 BOM (salvage #57870) | tools/
3fee5c291 | 2026-08-08 | test(tools): cover UTF-8 BOM input in json_parse sandbox helper | tests/
7fef76a6c | 2026-08-08 | fix(auth): read .env as utf-8-sig in the dotenv-vs-shell detector | agent/, tests/
9e6cfcda5 | 2026-08-08 | fix: finish the missing-encoding sweep — BOM-tolerant reads for user-edited stores | agent/, contributors/, gateway/, hermes_cli/, tests/, tools/
9bbd7f97c | 2026-08-08 | test: pin module-level _AUTH_JSON_PATH to tmp store in salvaged windows-encoding test | tests/
7b1f02377 | 2026-08-08 | feat(lint): close the fdopen + chained-call gaps in the encoding footgun gate | scripts/
5945929d4 | 2026-08-08 | fix(tests): read and write test files as UTF-8 so the suite runs on Windows | tests/
298ef0645 | 2026-08-08 | fix(tests): Windows-aware path-list split and UTF-8 progress output in parallel runner | scripts/, tests/
967157a7c | 2026-08-08 | fix(windows-tests): address parallel runner encoding and symlink privilege errors (Fixes #39480) | tests/
45ff81438 | 2026-08-08 | fix(testing): tolerate legacy console encodings | tests/
a61961673 | 2026-08-08 | fix(test): read add_contributor.py with explicit UTF-8 encoding | tests/
4c9e1e822 | 2026-08-08 | fix(test): make desktop ui tests locale-agnostic | apps/
ad82fc9bd | 2026-08-08 | chore: contributor email mappings for salvaged Windows-encoding PRs | contributors/
e40315d53 | 2026-08-08 | fix(file-ops): classify binary files at the byte layer, not on transport-lossy text | tests/, tools/
93be7f011 | 2026-08-08 | test(file-ops): end-to-end regression suite for the UTF-8-flagged-as-binary class | contributors/, tests/
9dcce84c3 | 2026-08-08 | fix(clipboard): use base64 encoding for PowerShell read path to prevent ANSI codepage corruption | ui-tui/
26eeb8568 | 2026-08-08 | fix(tools): decode git output as UTF-8 in working_diff on Windows | tests/, tools/
5b5b5e8da | 2026-08-08 | fix(goals): decode quality-gate output as UTF-8 instead of the process codepage | hermes_cli/, tests/
372b3b7bb | 2026-08-08 | fix(cli): decode cua-driver autostart PowerShell output as UTF-8 | hermes_cli/
6dda0c91d | 2026-08-08 | fix(desktop): stop new chats inheriting the focused session's folder | apps/
7ff9d7db9 | 2026-08-08 | fix(desktop): match a project to its cwd across Windows path spellings | apps/
9050913e6 | 2026-08-08 | fix(desktop): remember the workspace you picked, not the one you looked at | apps/
48c05e0c6 | 2026-08-08 | fix(desktop): reveal main window after missed ready event | apps/
81413f007 | 2026-08-08 | docs: explain model refusal attribution | website/
bd39673b8 | 2026-08-08 | refactor(desktop): one path-comparison helper instead of two | apps/
c96b978d5 | 2026-08-08 | fix(desktop): drop a stale comment describing the removed inheritance step | apps/
2382f50f5 | 2026-08-08 | fix(dashboard): bound WS ticket minting on the events + PTY sockets (supersedes #81931) (#81978) | web/
e0c3caf3b | 2026-08-08 | fix(model-picker): serve cached custom-provider catalog on no-probe opens (supersedes #81665, #81556) (#81973) | hermes_cli/, tests/
a726a4aee | 2026-08-08 | fmt(js): `npm run fix` on merge (#81997) | apps/, ui-tui/
3da72f1fd | 2026-08-08 | fmt(js): `npm run fix` on merge (#82000) | apps/
2c94e3fb6 | 2026-08-08 | refactor(gateway): one helper for prefixing per-turn notes onto model input | tui_gateway/
e24bac49f | 2026-08-08 | feat(desktop): tell the agent when it is floating in HUD mode | agent/, apps/, tests/, tui_gateway/
48d672e49 | 2026-08-08 | fix(desktop): the HUD only takes the mouse where the HUD actually is | apps/
717b49c08 | 2026-08-08 | fix(desktop): read "is the cursor over the HUD" off the tree, not off a list | apps/
7537de9e7 | 2026-08-08 | fix(deps): patch 31 known CVEs across Python and npm lockfiles | .npmrc, apps/, package-lock.json, package.json, plugins/, pyproject.toml, scripts/, ui-tui/, uv.lock, website/
45f31de4e | 2026-08-08 | fix(deps): mirror aiohttp 3.14.3 pin into lazy_deps feature specs | tools/
a1e4fee33 | 2026-08-08 | fix(deps): enforce 14-day aging + exact pins on all bumped versions | package-lock.json, package.json, website/
bdfdd2773 | 2026-08-08 | chore(deps): reconcile website lock after Algolia search migration rebase | website/
5f4a7e99f | 2026-08-08 | fix: explain provider DNS failures as possible offline state | run_agent.py, tests/
309c9bbbe | 2026-08-08 | feat(skills): add competitor-news-monitor | skills/
65710ca18 | 2026-08-08 | chore(skills/competitor-news-monitor): cron-recipe shape + competitor-watch blueprint | cron/, skills/, tests/, website/
adf9549cd | 2026-08-08 | fix(compression): prune stale codex_reasoning_items during compaction (#71058) | agent/
e00965a7e | 2026-08-08 | fix(compression): correct prune boundary + exempt native compaction checkpoints | agent/, tests/
0665cd4b5 | 2026-08-08 | style(hud): tighten the surface-note comments and test helper | agent/, apps/, tui_gateway/
b70c5cadb | 2026-08-08 | fix(desktop): stop the session status going idle while the turn is running | apps/
302ee80b6 | 2026-08-08 | refactor(desktop): give the status dot one source of truth and a quieter look | apps/
f04ad5a82 | 2026-08-08 | style(desktop): drop the pulsing glow behind the status dot | apps/
b07ee44f1 | 2026-08-08 | refactor(desktop): let the sidebar row read its own status | apps/
137960c9a | 2026-08-08 | feat(media): opt-in upscale pass for image_generate and video_generate across FAL and Krea | agent/, plugins/, tests/, tools/, website/
66ea4e686 | 2026-08-08 | feat(media): default-on upscaling for sub-2MP image models (FAL + Krea) | plugins/, tests/, tools/, website/
615a435b7 | 2026-08-08 | perf(desktop): stop a settling turn from repainting the whole sidebar | apps/
041cbff5e | 2026-08-08 | fix(desktop): keep the Playwright reveal path off the production fallback | apps/
41ae3db42 | 2026-08-08 | fix(desktop): reveal every window after a missed ready event, not just the main one | apps/
5566379f5 | 2026-08-08 | fix(sessions): give titles provenance so they stop overwriting themselves | agent/, hermes_state.py, hermes_state_common.py, tests/
e358eaf44 | 2026-08-08 | perf(sessions): resolve the titling model from the provider's live catalog | agent/, plugins/, providers/, tests/
f726090d4 | 2026-08-08 | feat(sessions): name a session the moment it starts | acp_adapter/, agent/, cli.py, gateway/, hermes_cli/, tests/, tui_gateway/
a60b492e0 | 2026-08-08 | feat(gateway): key-addressed plugins.manage rows + portable MCP toolset fold-in | hermes_cli/, tui_gateway/
c86da8397 | 2026-08-08 | feat(desktop): agent plugins in Settings → Plugins | apps/
1c9433897 | 2026-08-08 | chore(skills): standards sweep — bring 42 bundled/optional skills up to hardline | optional-skills/, skills/, website/
ed9eee5dc | 2026-08-08 | fix(gateway): report bundled auto-loading plugins as enabled | hermes_cli/, tui_gateway/
44790bc9c | 2026-08-08 | feat(desktop): plugin descriptions + open the agent plugins folder | apps/
55982159d | 2026-08-08 | feat(tests): CI-enforce skill authoring standards; clear all remaining debt | optional-skills/, skills/, tests/, website/
3e6a081d6 | 2026-08-08 | fmt(js): `npm run fix` on merge (#82055) | apps/
67518a2ad | 2026-08-08 | fix(desktop): repaint peer windows when the appearance changes | apps/
50e0640d1 | 2026-08-08 | fix(desktop): drop the "Edit message" tooltip from user bubbles | apps/
0db278833 | 2026-08-08 | fix(desktop): keep the composer focused while reading the HUD band | apps/
dd11b8e8e | 2026-08-08 | fix(desktop): drag the HUD by holding the composer | apps/
4424a5a60 | 2026-08-08 | fix(desktop): stop the HUD painting sheet over empty space | apps/
048907fb6 | 2026-08-08 | feat(desktop): show work and focus on the HUD bar itself | apps/
7e3deea0a | 2026-08-08 | fix(desktop): make the HUD band a real box so it scrolls | apps/
eee38db82 | 2026-08-08 | fix(desktop): let the HUD band fade while a turn is still running | apps/
c5494dddd | 2026-08-08 | chore(desktop): satisfy eslint on the HUD drag additions | apps/
bed3960e9 | 2026-08-08 | fix(desktop): give the HUD band a real glanceable stage before it goes | apps/
d2dc0ce70 | 2026-08-08 | fix(desktop): hold the HUD band when the window loses focus | apps/
706540741 | 2026-08-08 | Add more FAL models to nous portal (#82019) | plugins/, tests/, tools/
0f2272716 | 2026-08-08 | fix(gateway): omit expect_edits on finalized draft sends | gateway/, tests/
70d165222 | 2026-08-08 | fix(gateway): cover all finalized stream sends | gateway/, tests/
05330e804 | 2026-08-08 | fix(video): bind managed SeedVR to source request | plugins/, tests/
5a16635f4 | 2026-08-08 | feat(cli): show session titles in status bars | cli.py, tests/, ui-tui/, website/
5ff506896 | 2026-08-08 | feat(desktop): sit the HUD band back when a completion list opens | apps/
051a7fb1e | 2026-08-08 | fix(desktop): open the HUD completion list where there is room for it | apps/
3d5f17344 | 2026-08-08 | feat(desktop): lift the HUD bar off what it lies over | apps/
1040cfe28 | 2026-08-08 | fix(desktop): shorten the HUD band's glanceable hold to 1.75s | apps/
99d1f1837 | 2026-08-09 | fmt(js): `npm run fix` on merge (#82099) | apps/
05c5a337f | 2026-08-08 | fix(desktop): settle the HUD band's glanceable hold at 1.1s | apps/
9e1993177 | 2026-08-08 | docs(telegram): explain rich draft final delivery | website/
86b50c6a2 | 2026-08-08 | fix(desktop): keep earlier HUD windows in scope for the turn | agent/
d91f08a39 | 2026-08-08 | fix(desktop): keep tool rows and notices out of the HUD band | apps/
67927808b | 2026-08-08 | feat(desktop): support multiple cron delivery targets | apps/
3a8d95a93 | 2026-08-08 | fix(desktop): give the delivery-target group an accessible name | apps/
f2d03c1f2 | 2026-08-08 | fix(state,cli,tui-gateway): keep reasoning fields intact across forks and branches | hermes_cli/, hermes_state.py, tests/, tui_gateway/
212e84176 | 2026-08-08 | fix(compression): charge stale thinking to the tail budget only on the newest assistant turn (#73624) | agent/, tests/
628372de4 | 2026-08-08 | fix(otlp): span exporter now inherits configured resource_attributes | agent/, tests/
21bc9ba34 | 2026-08-08 | fix(model-switch): split YYYYMMDD date stamps from version tuple in _model_sort_key | contributors/, hermes_cli/, tests/
b79e83827 | 2026-08-08 | fix(model-switch): surface candidates on ambiguous alias instead of guessing | hermes_cli/, tests/
0b33ee88e | 2026-08-08 | fix(update): don't truncate cmdlines in the venv-blocker scan — it broke the gateway exemption | hermes_cli/, tests/
bf7c71664 | 2026-08-08 | fix(agent): rebind pool entry id after env credential refresh | agent/, run_agent.py, tests/
0c97a883a | 2026-08-08 | fix(model-switch): read picker key_env through the per-profile secret scope | hermes_cli/, tests/
0569c001d | 2026-08-08 | fix(model-switch): route switch_model user-provider key reads through the secret scope | hermes_cli/, tests/
c595dcb95 | 2026-08-08 | fix(search): strip the FTS5 special characters the sanitizer was missing | hermes_state_search.py, tests/
90311ee75 | 2026-08-08 | fix(search): strip % from non-CJK FTS5 queries | hermes_state_search.py, tests/
d220f1fdc | 2026-08-08 | test(gateway): freeze queued follow-up media delivery | tests/
808c8570a | 2026-08-08 | fix(gateway): preserve queued follow-up media delivery | gateway/, tests/
4da0d06db | 2026-08-08 | test(gateway): use allowed media root in queued follow-up test | tests/
1648ab3a9 | 2026-08-08 | fix(gateway): keep protected MEDIA tokens on queued resend | gateway/, tests/
e22167900 | 2026-08-08 | test(gateway): preserve queued bare path text | tests/
b0b7f9c77 | 2026-08-08 | test(gateway): preserve queued media routing metadata | tests/
a52dd17d9 | 2026-08-08 | fix(gateway): preserve queued media continuity | gateway/
0b17b691d | 2026-08-08 | fix(gateway): skip attachment upload for failed first turns in queued delivery | gateway/, tests/
54641186f | 2026-08-08 | fix(cli): drain late OSC 11 replies after TCSAFLUSH to prevent input leak | cli.py, tests/
851f23ebc | 2026-08-08 | fix(cli): fence OSC 11 background query with DA1 so late replies can't leak into the prompt | cli.py, tests/
7210db564 | 2026-08-08 | fix(build): allow get-windows install script, refresh stale allowScripts pins | package.json, website/
2cd9e1777 | 2026-08-08 | fix(desktop): rebuild get-windows when its win32 binding is missing | apps/
a692393da | 2026-08-08 | test(build): hold allowScripts in sync with the lockfile | tests-js/
a09124cea | 2026-08-08 | fix(install): stop managed runtime child trees on Windows | scripts/, tests/
826bf9b6d | 2026-08-08 | fix(update): reap orphaned Desktop backends instead of dead-ending the venv-holder guard | hermes_cli/, tests/
da3a0a852 | 2026-08-08 | fix(update): make orphan-backend reap tree-aware + drain Desktop update trees without pre-signalling | apps/, hermes_cli/, tests/
d73bc7f17 | 2026-08-08 | fix(desktop): persist window geometry on Linux | apps/
da933bf27 | 2026-08-08 | fix(desktop): keep the HUD clickable on Linux | apps/
04afc8d48 | 2026-08-08 | fix(desktop): say why read_window_below cannot see the windows | apps/, tools/
9eec86923 | 2026-08-08 | docs: align Ollama tool-calling guidance | website/
1792e756e | 2026-08-09 | fmt(js): `npm run fix` on merge (#82209) | apps/
f2731da4a | 2026-08-08 | fix(desktop): keep HUD composer within window | apps/
3dcbe9001 | 2026-08-08 | fix(update): refresh the installer's bootstrap-cache scripts on every update | hermes_cli/, tests/
3a915c46d | 2026-08-08 | fix(update): scope bootstrap-cache refresh to the update-target ref, match installer pin rules | hermes_cli/, tests/
1d45e62f3 | 2026-08-08 | fix(install): replay npm's debug log into the bootstrap stream on failure | scripts/
ceebb21dd | 2026-08-08 | fix: suppress pydantic serializer warnings leaking to the terminal | agent/, run_agent.py, tests/
bb8280b75 | 2026-08-08 | revert(desktop): roll Electron back to 40.10.2 | apps/, package-lock.json, package.json
```
