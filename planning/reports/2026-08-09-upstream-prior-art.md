# Upstream prior art — #241 · #264 · #132 · #170b · #224 · #187

**Date:** 2026-08-09 · **Upstream:** `NousResearch/hermes-agent` (public, MIT, default `main`)
**Method:** `gh search` / `gh api` **GET** only, plus code reads against the existing full clone at
upstream HEAD `62431364e`.

> **Nothing was written to GitHub.** No issue, PR, comment, review, reaction, label, star, fork,
> or branch push. Every call was a read. **No live Hermes install was modified** — the clone in the
> session scratchpad was read-only and was not fetched or unshallowed.
>
> **This document recommends no filing.** It is a reading list. Where an item has no prior art,
> it says so and stops.

---

## 1. The reading list

| Our item | Upstream issue / PR | State | Match | Why |
|---|---|---|---|---|
| **#241** (half A — self-name persisted as the session model) | **[#79101](https://github.com/NousResearch/hermes-agent/issues/79101)** "[Bug]: API server session stores virtual model alias as real model, breaking gateway default" | **open** issue | **EXACT** | Same line, same repro, names the same blame commit `f7527b0fdb` |
| **#241** (half A) | **[#72739](https://github.com/NousResearch/hermes-agent/pull/72739)** "fix(api-server): stop persisting the virtual model alias as a session's model" | **open** PR, maintainer-reviewed | **EXACT** | Quotes `model = body.get("model") or self._model_name` verbatim; the designated fix |
| **#241** (half A) | [#79824](https://github.com/NousResearch/hermes-agent/pull/79824) "recovery net must never recover the advertised virtual alias" | **open** PR | **EXACT** (2nd channel) | A *separate* poison vector we had not found: `_last_resolved_model` |
| **#241** (half A) | [#79102](https://github.com/NousResearch/hermes-agent/pull/79102) · [#76077](https://github.com/NousResearch/hermes-agent/pull/76077) | **closed** (dups of #72739) | EXACT | Two more independent discoverers, both self-closed in favour of #72739 |
| **#241** (half B — HTTP 200 on a non-retryable failure) | **[#78485](https://github.com/NousResearch/hermes-agent/pull/78485)** "fix(api): return 502 for failed responses runs" | **open** PR | **PARTIAL** | Identical defect shape and argument — but on `/v1/responses`, **not** `/api/sessions/{id}/chat` |
| **#264** (bind race, no retry) | **[#65665](https://github.com/NousResearch/hermes-agent/pull/65665)** "mark port conflict as non-retryable to stop infinite reconnect loop" | **MERGED** 2026-07-16 | **EXACT — but as intent** | This *is* our #264. Upstream chose it deliberately and documented why |
| **#264** (2nd cause — weak/unverifiable key) | **[#69838](https://github.com/NousResearch/hermes-agent/pull/69838)** "fail closed when API_SERVER_KEY strength can't be verified" | **MERGED** 2026-07-23 | **EXACT — but as intent** | Confirms §4.3 of the re-check, in upstream's own words |
| **#132** (Sessions lane has no vision fallback) | [#23733](https://github.com/NousResearch/hermes-agent/issues/23733) "image routing bypassed on api_server /v1/chat/completions" | **closed** (completed) | **PARTIAL** | Same mechanism, **different lane** — chat-completions, not Sessions |
| **#132** | [#18597](https://github.com/NousResearch/hermes-agent/pull/18597) "wire decide_image_input_mode into chat completions" | **closed** (stale, unmerged) | **PARTIAL** | Exactly the fix shape we identified; author closed it as stale |
| **#170b** (no `model` on the job whitelist) | [#70050](https://github.com/NousResearch/hermes-agent/issues/70050) "no supported repin path" (+ tracked #68380, #24258, #27530, #19615) | **open** issue | **PARTIAL** | Same *capability* gap, on CLI + dashboard. The `:8642` whitelist is not mentioned |
| **#224** (approval mode not on `:8642`) | [#61946](https://github.com/NousResearch/hermes-agent/pull/61946) "per-session model override and **yolo toggle** via PATCH /api/sessions" | **open** PR | **PARTIAL** | Nearest thing to remote approval control; per-session bypass, not mode selection |
| **#224** | [#19076](https://github.com/NousResearch/hermes-agent/pull/19076) · [#23328](https://github.com/NousResearch/hermes-agent/pull/23328) · [#66495](https://github.com/NousResearch/hermes-agent/pull/66495) | **open** PRs | **PARTIAL** | Three separate proposals to add a config surface to `:8642`. None carries `approvals` |
| **#187** (`min_messages` / `order` absent) | — | — | **NONE** | No upstream report of this gap on any surface |
| **#187** (bonus — a blocker) | **[#45236](https://github.com/NousResearch/hermes-agent/issues/45236)** "sessions.message_count column not maintained for api_server and tui sources" | **open** issue | (not a match — a **finding**) | `message_count` is NULL for `source=api_server`. **35 api_server sessions measured, 0 had `message_count >= 1`** |

**Two rows are NONE-adjacent and should be read that way:** #187 has no prior art at all, and #264
has prior art only in the sense that upstream built the behaviour on purpose — nobody has reported
its consequence as a defect.

---

## 2. Per item detail — what was searched

`gh search issues`/`prs` (the CLI) turned out to wrap every query in **quotes**, making it an
exact-phrase search — the first batch returned false negatives for that reason. Everything below
was re-run through `gh api -X GET search/issues --raw-field q=…`, which does normal AND-of-terms.
**If you extend this, use the raw API form.**

### #241 — self-name model id + HTTP 200 on error

Searched: `in:title virtual alias model` · `in:title api_server model` · `model_not_found` ·
`session model precedence` · `resolve_effective_model` · `provider error returned as chat message
instead of error status` · `in:title 502 api` · `api/sessions/{id}/chat error http status 200` ·
`in:title status code error api_server` (0 results).

**Half A is the most-reported thing on this list — four independent discoverers.** Timeline:

- `f7527b0fdb` (2026-05-20) introduces the persistence. Still unfixed at HEAD — verified:
  `gateway/platforms/api_server.py:3397` is still `model = body.get("model") or self._model_name`.
- **#72739** (2026-07-27, `loafoe`) — write-site fix, 177 additions, 3 files, tests for create /
  provider-prefixed alias / sync chat / streaming chat. Labels `type/bug, comp/gateway, P2,
  area/sessions`. **teknium1 reviewed it 2026-07-30 (COMMENTED); the author answered the same day
  and merged main to clear a conflict. No activity since — 10 days idle, not merged.**
- **#76077** (2026-08-01, `gvlope`) — read-site fix; observed on `openai-codex`, where it surfaces
  as `HTTP 400 "The 'hermes-agent' model is not supported…"`. Auto-triaged as a duplicate of
  #72739 within hours; teknium1 confirmed the defect is present on main; author self-closed.
- **#79101** (2026-08-05, `blazzbyte`) — the issue. Carries a **production confirmation** from
  `k0rnacki` running a fleet pinned at `f5be9236e` against a named custom provider, plus an
  addendum that widens it: *after* a read-side guard heals a poisoned session, the completion
  writes the real dispatched model back, and the next turn's session-persisted branch loses the
  named provider's `base_url` — configured model against the wrong host → 404 → fallback.
- **#79824** (2026-08-06, `k0rnacki`) — **a channel we had not identified.** The #35314
  empty-dispatch recovery net caches the last resolved model in
  `APIServerAdapter._last_resolved_model` and will happily recover the alias back out. Independent
  of the session row: fixing the write site does not close it. `_last_resolved_model` appears 6×
  in `api_server.py` at HEAD.

Also worth a look: **#75807** (open) *"api_server accepts arbitrary unknown model ids — session +
registry rows created before any validation"*, labelled `needs-decision` — the general case.

**Half B has no report against our handler.** `_handle_session_chat` still ends with an
unconditional `web.json_response({… "message": {"role":"assistant","content": final_response} …})`
at `:3755–3763`. The closest is **#78485** (2026-08-04, `takolab`), which makes precisely our
argument — *"the endpoint returns HTTP 200 with `status: "completed"`, so API clients cannot
distinguish a provider or agent failure from valid assistant output"* — and returns 502 with an
OpenAI-style `server_error` envelope. It is scoped to non-streaming `/v1/responses`. Adjacent:
#37735 (closed) "redact provider errors at HTTP boundary"; #55323, #55096, #5435 all concern the
*wording/classification* of provider errors, not the status code.

### #264 — bind race, non-retryable

Searched: `in:title port in use` · `in:title api_server port` · `api_server_port_in_use` ·
`in:title EADDRINUSE` · `in:title non-retryable` · `in:title fatal error platform` ·
`in:title platform resume` · `in:title API_SERVER_KEY` · `gateway restarted api server not
listening 8642`.

**Both causes are merged, deliberate, and authored by the maintainer as salvages of external work.**

- **#65665** (merged 2026-07-16, teknium1) — re-implementation of **#52132 by `msalles1`** against
  the direct-bind path. The rationale is the one the re-check found in the code comment, stated as
  a production trace: *"4 profiles defaulting to the same port produced 1568+ reconnect attempts
  over 5 days, thousands of duplicate errors.log lines, and 2 leaked ResponseStore fds per retry."*
  Recovery is named as `/platform resume api_server`, explicitly modelled on weixin/whatsapp_cloud
  config-error handling.
- **#69838** (merged 2026-07-23, teknium1) — salvage of **#69510 by `Drexuxux`**. Confirms the
  second cause exactly: `_api_key_passes_startup_guard` wrapped its strength check in
  `try/except ImportError: pass`; `hermes_cli.auth` imports `httpx` at module scope, so a trimmed
  or partial install silently dropped the check. The fix moves it outside the `try` and refuses to
  start on **any** import failure — which is what turns a good 64-char key into a fatal error on a
  half-finished update.
- The pattern is being extended, not reconsidered: **#65739** (open) does the same for the webhook
  adapter.

**Nobody has filed the consequence** — "gateway process healthy, chat plane absent, no automatic
recovery" — as a bug. The nearest neighbours are about a *different* failure class: **#74494**
(closed) / **#69112**, **#69007** — the gateway never queues a platform for reconnection after a
**retryable** fatal error because `disconnect()` cancels the task running the fatal handler; and
**#81335** (open) is the Telegram instance of that zombie. **#38432** (open, 2026-06-03,
unmerged for two months) clears stale platform fatal errors from `gateway_state.json` on startup —
adjacent to our proposed ops rule, and it reads the same state file.

### #132 — no vision fallback on the Sessions lane

Searched: `in:title image_routing` · `in:title api_server image` · `in:title vision api server` ·
`in:title sessions image` · `in:title multimodal sessions` (0) ·
`api/sessions chat image non-vision model dropped` (0) · `image_routing api_server sessions
endpoint` (0).

**The mechanism has been reported and fixed-attempted repeatedly — always on a different lane.**

- **#23733** (2026-05-11, P1) is our mechanism stated precisely, for `/v1/chat/completions`: the
  non-vision fallback runs on the legacy branch but not the provider-profile branch, and it names
  `gateway/run.py → _decide_image_input_mode → _enrich_message_with_vision` as the path that *does*
  handle it correctly. **Closed as completed** on the claim that PR #25925 fixed it — but #25925 is
  titled *"fix(agent): keep image tool results from poisoning text-only sessions"*, which is not
  obviously the same fix, and the close was made by a triage participant, not the reporter.
- **#18597** (2026-05-02) is the fix shape we independently arrived at — add
  `_enrich_api_content_with_vision()` to `APIServerAdapter` and wire `decide_image_input_mode()`
  into the handler. **The author closed it 2026-07-18 as stale:** *"api_server has been
  substantially refactored in main since this was opened, so the approach here no longer lines up
  and would need a rewrite rather than a rebase."*
- Others on neighbouring lanes: #23743, #27238, #12329 (all closed), #7140 (open, `/v1/runs`
  media_urls).

**Verified at HEAD, and it sharpens our filing:** `api_server.py` contains **zero** references to
`image_routing` or `decide_image_input_mode`, yet 39 references to `image` — it parses and
validates image parts thoroughly (`_IMAGE_PART_TYPES`, `invalid_image_url`,
`unsupported_content_type`). The Sessions-lane drop happens in `_normalize_chat_content`
(`api_server.py:477`), and upstream's own comment on line **521** says it out loud:

```python
# Silently skip image_url / other non-text parts
```

Also relevant to **#21**, not #132: **#14959** (open) *"api_server: no delivery mechanism for
generated images (image_generate output unreachable from HTTP clients / Open WebUI)."*

### #170b — no `model` on the job whitelist

Searched: `in:title cron model` (108 hits) · `in:title job model` (53) · `in:title jobs api` ·
`api/jobs model field create` · `in:title cron model` variants.

**The capability gap is well-known upstream; the `:8642` surface is not mentioned anywhere.**
`#70050` (open, `bgexpert`) is the umbrella and helpfully lists its own siblings — *"Tracked issues
(do not duplicate): #68380 (cronjob update drops `model`), #24258 (Dashboard missing model/provider
edit), #27530 (`cron edit` cannot reset model to default), #19615 (global vs pinned distinction)."*
teknium1 posted a status update there: **PR #73532 on main added `hermes cron edit --model …
--provider …` and dashboard pin editing.** So upstream is actively closing the CLI and dashboard
halves — and has left the API-server half untouched.

**Confirmed in the clone, and this narrows #170b usefully:** cron jobs carry `model` all the way
down (`cron/jobs.py:1743` writes `"model": normalized_model`; `:1913` handles
`{"provider","model","base_url","no_agent"}` in updates; `cron/scheduler.py:2980` reads
`job.get("model")`). **The field exists everywhere except the api_server whitelist** —
`api_server.py:5543` `_UPDATE_ALLOWED_FIELDS = {"name","schedule","prompt","deliver","skills",
"skill","repeat","enabled"}`. #170b is a whitelist omission, not a missing capability.

Precedent for that exact shape: **#66786** (open) *"Cron Job Definition Missing `description` Field
in UI and API Schema."* Also #63327 (open) adds per-job reasoning effort "across all surfaces".

### #224 — approval mode not selectable on `:8642`

Searched: `in:title approval mode` (68 hits) · `in:title api/config` (189) · `in:title approvals
api` · `in:title yolo toggle` · `approvals mode api_server endpoint expose` · `set approval mode via
REST api_server client`.

**No one has asked for `approvals.mode` on `:8642`.** What exists:

- **#61946** (open, 2026-07-10, `MrB0req`) extends `PATCH /api/sessions/{id}` with `model` and
  **`yolo`** — per-session auto-approval via the existing `enable_session_yolo`/
  `disable_session_yolo` storage, surfaced in GET/PATCH responses. Its motivation is ours verbatim:
  *"the only setters are slash commands on messaging platforms. External clients of the API server
  platform … currently have no way to switch a session's model or enable yolo over REST."* This is
  a per-session **bypass**, not Manual/Smart/Off mode selection — but it is the nearest existing
  proposal, and it would also serve #241's model half.
- Three independent attempts to give `:8642` a config surface: **#19076** (`/api/config/persona` +
  `/api/config/toolsets`), **#23328** (`/api/config/model` GET + PUT), **#66495**
  (`GET /v1/agent/config` for remote config discovery). All open, none merged, none touches
  `approvals`.
- Approval-mode work upstream is config-file- and CLI-shaped: #76428 (`approvals.
  noninteractive_mode`), #32906 (per-kanban-board mode override), #80993 (per-tool allow/ask/deny),
  #53021 (session-scoped allowlist mode).
- **Read the `/api/config` search hits carefully.** #80945, #67587, #67944 are all the **dashboard**
  (`:9119`) route, exactly as CLAUDE.md's two-web-apps rule predicts. They are not `:8642`.

### #187 — `min_messages` / `order` absent from `GET /api/sessions`

Searched: `in:title min_messages` (**0 results**) · `min_messages api sessions list` ·
`in:title list sessions` (92) · `in:title sessions order` · `in:title zero-message sessions` ·
`api/sessions empty sessions filter order` · `api server GET /api/sessions min_messages order
parameter`.

**No prior art for the gap itself.** Analogous filtering wants exist on every *other* surface —
**#82131** (open, filed 2026-08-09, the same day as this report) *"fix(tui-gateway): filter ghost
zero-message sessions from session.list"*; **#53368** (desktop sidebar drops empty drafts,
compression intermediates and delegate children with no toggle); #69806 / #75496 (CLI `--sort` and
list options); #53811 (stable tiebreaker for `list_sessions_rich` ordering). Nobody has asked for
either knob on the HTTP API.

**The find that matters here is #45236**, and it is not a match — it is a blocker we did not know
about. `sessions.message_count` **is never maintained for `source=api_server`**: the reporter
measured *"150 TUI sessions: only 3 had `message_count >= 1`; **35 api_server sessions: 0 had
`message_count >= 1`**"*, and observes that the Desktop sidebar queries `min_messages=1` and
therefore hides nearly everything. **Exposing `min_messages` on `:8642` would, on today's schema,
filter out every one of Talaria's own sessions.** Open since 2026-06-12, `P3`, with two competing
partial fixes (#45345 backfills NULL rows, #45475 only initializes new ones) noted in AI triage.

---

## 3. Contribution posture

### Does this project accept external contributions? — **Emphatically yes, at enormous volume.**

| Measure | Value |
|---|---|
| Stars / forks / licence | 227,624 · 44,640 · MIT |
| `CONTRIBUTING.md` | **1,009 lines**, plus a Spanish translation |
| PR template · issue templates | `.github/PULL_REQUEST_TEMPLATE.md` · **4** forms (`bug_report`, `feature_request`, `setup_help`, `config`) |
| Code of conduct | **absent** |
| PRs: total / merged / open / closed-unmerged | 61,512 / **10,183 (16.6%)** / 19,947 / 31,382 |
| Open issues | 29,852 |
| **Distinct commit authors, last 30 days** | **857** |
| Commits carrying `Co-authored-by`, last 30 days | 915 |
| `contributors/emails/` mappings in tree | 463 |

CONTRIBUTING.md opens with an explicit priority order — **"1. Bug fixes — crashes, incorrect
behavior, data loss. Always top priority."** — and a *"Before You Start: Search First"* section that
literally prints the `gh search issues --repo NousResearch/hermes-agent` command and warns
*"duplicates are common here."* It also states two standing refusals worth knowing: **no new memory
providers** and **no third-party product integrations** in-tree (both must ship as standalone
plugins) — neither touches any of our six.

**The distinctive mechanic is salvage.** Maintainers routinely re-implement an external PR against
current `main` and merge it with authorship preserved, rather than merging the original branch.
All three of the most relevant merged PRs here are salvages: **#65665** re-implements #52132 by
`msalles1`; **#69838** salvages #69510 by `Drexuxux`; **#70931** salvages #57947 by `FvanW` with a
resolution idea from #59941 by `kaishi00`. That is why the raw merged-author distribution
(kshitijk4poor 200, teknium1 115, OutThisLife 38 of the last ~400) **understates** external
contribution badly — the 857 distinct 30-day commit authors is the truer number.

The queue is nonetheless very deep: ~20,000 open PRs, and a 16.6% lifetime merge rate. #72739 —
reviewed by the lead maintainer and answered by its author — has sat unmerged for 10 days; #18597
sat 11 weeks and was closed as stale by its own author when `api_server` was refactored underneath
it. **Landing a fix upstream is plausible; landing it promptly is not the base case.**

### Discussions / changelog / release notes to watch instead

- **No Discussions board** (`has_discussions: false`).
- **GitHub Releases is the real changelog.** Date-scheme tags `vYYYY.M.D`; the last six are
  `v2026.8.3` (2026-08-03, **57.8 KB body**), `v2026.7.30` (1.1 KB), `v2026.7.20` (52.5 KB),
  `v2026.7.7.2`, `v2026.7.7`, `v2026.7.1`. The large bodies are substantive notes; the small ones
  are point releases. **Cadence ≈ one tag every 1–2 weeks, and `hermes update` tracks `main`, not
  tags** — so we always run far ahead of the newest release notes.
- **In-tree `CHANGELOG.md` is gone on purpose** — commit `78c8bcd12`, *"chore: drop CHANGELOG.md and
  docs/reports/ — not shipped with salvage PRs."* Do not look for one.
- Community lives in the **Nous Research Discord** (`#plugins-skills-and-skins` named in
  CONTRIBUTING). Not searchable from here.

### Response latency

Sampled the 40 issues created **2026-07-30 → 2026-08-01** (a settled window; the newest issues are
hours old and mostly uncommented).

- **39 of 40 received at least one comment.**
- **Median time to first comment: 0.3 h (~18 minutes).** Mean 3.4 h, max 33.7 h.
- First-commenter distribution: **teknium1 (maintainer) 8**, GottZ 7, alt-glitch 7, edcsalter 4,
  then a long tail.

**Caveat, and it matters:** this measures *any* first comment. GottZ and alt-glitch post AI triage
(their comments are prefixed *"This was generated by AI during triage"*), and an automated
`hermes-sweeper` bot applies risk labels (`sweeper:risk-session-state`,
`sweeper:blast-moderate`, …) and duplicate detection. **Time-to-first-*maintainer*-comment was not
measured separately** — teknium1 was first commenter on 21% of the sample, so the maintainer figure
is necessarily slower than 18 minutes. What the number does establish is that **nothing lands in
silence**: triage is fast, thorough, and labels aggressively.

---

## 4. What this changes for us

| Item | Verdict | Detail |
|---|---|---|
| **#241 half A** | **TRACK** | **#72739 is the one to watch** — it is the accepted fix for exactly our mechanism, reviewed by the lead maintainer, awaiting merge. Watch **#79824** alongside it: the recovery-net channel is independent, and #72739 alone does not close it. If both land, half A goes away for us without any action. |
| **#241 half B** | **STILL OURS** | No report touches `_handle_session_chat`'s unconditional 200. #78485 establishes that upstream finds this argument persuasive on a sibling endpoint — it is a shape precedent, not coverage. |
| **#241 overall** | **park calculus unchanged** | Half A is already reported by four people; there is nothing we could add to it. Half B is genuinely unreported. Neither fact creates a question for Owen — the park stands on its own terms, as before. |
| **#264** | **STILL OURS — and reframed** | Not a defect awaiting a fix: **a merged, deliberate design decision with a published rationale** (#65665), plus a second merged decision producing the identical symptom (#69838). Nothing to track for a fix; the pattern is being *extended* (#65739). **What remains ours is entirely the ops/observability side** — which is what the re-check's `gateway_state.json` rule already targets. Cite #65665's own numbers (1568 retries / 5 days / 2 fds per retry) in the entry: they explain why "just retry the bind" is not on the table. |
| **#132** | **STILL OURS** | The Sessions lane has never been reported. Two useful updates: our proposed fix shape is *upstream's own* (#18597), and it died of `api_server` refactor churn — a warning about anything we build against that file. #23733's "fixed by #25925" close deserves scepticism; the cited PR's title does not match, and `image_routing` has zero references in `api_server.py` at HEAD. |
| **#170b** | **STILL OURS — but smaller than filed** | The data layer already carries `model` end-to-end; only `_UPDATE_ALLOWED_FIELDS` and `_handle_create_job` omit it. Upstream is actively fixing the CLI and dashboard halves (PR #73532 per teknium1 on #70050), which means **the surrounding capability is getting better while our surface stays flat** — worth re-reading #70050 before any #170b work. |
| **#224** | **STILL OURS** | Nobody wants `approvals.mode` on `:8642`. **TRACK #61946** as a partial: if it merges, `PATCH /api/sessions` gains a per-session `yolo` toggle over REST, which is not Manual/Smart/Off but is the first remote approval control of any kind — and it carries a `model` field that would also serve #241's session half. Three separate config-surface proposals (#19076/#23328/#66495) have all sat open, which is itself a signal about how upstream feels about config mutation on that plane. |
| **#187** | **STILL OURS — and materially harder** | Closed correctly, and no prior art. **But #45236 changes the cost estimate:** `sessions.message_count` is NULL for `source=api_server`, measured at 0-of-35. Adding `min_messages` to `:8642` would filter out *all* of Talaria's sessions until that column is maintained. **This belongs in #187's entry as a dated note** — it converts "one kwarg upstream" into "one kwarg plus a schema-maintenance fix upstream." Also note **#82131**, filed today, doing the zero-message filter for the TUI. |

**Nothing here is ALREADY-FIXED-AND-WE-MISSED-IT.** Verified at HEAD `62431364e`:
`api_server.py:3397` still reads `body.get("model") or self._model_name`; `:3755–3763` still
returns 200 unconditionally; `image_routing` refs = 0; `_UPDATE_ALLOWED_FIELDS` unchanged;
no `approvals` string; `_handle_list_sessions` still takes four params. **All six stand.**

---

## 5. What I could NOT determine

Explicit gaps, each a real limit rather than a hedge.

1. **Whether #72739 will merge, or when.** Reviewed 2026-07-30, answered same day, silent since.
   Its `mergeable`/`mergeStateStatus` both report `UNKNOWN` from the API. Ten days idle in a repo
   landing ~300 commits/day is not obviously good or bad — I have no base rate for
   maintainer-reviewed P2 PRs.
2. **Whether #23733's close was correct.** It was closed "fixed by PR #25925," but that PR's title
   describes a different change, the closer was a triage participant rather than the reporter, and
   nothing resembling the fix is visible in `api_server.py` today. I did not read #25925's diff.
3. **Time-to-first-*maintainer* comment.** I measured any-commenter (median 18 min, n=39, one
   2-day window). Bot and AI-triage comments are included. The maintainer-only figure is slower and
   unmeasured, and a single window may not generalize.
4. **Absence of a hit is weak evidence.** These are keyword searches over 61,512 PRs and 29,852
   open issues. GitHub's search API also caps at 1,000 results per query. **A NONE in the table
   means "not found by these terms," not "does not exist"** — the terms used are listed in §2 so
   the next person can extend rather than repeat them.
5. **The Nous Research Discord was not searched** and cannot be from here. CONTRIBUTING points
   community discussion there, so an item could be actively discussed with no GitHub trace.
6. **I did not enumerate closed-as-wontfix by label.** I saw `duplicate`, `needs-decision`,
   `type/bug`, `P1`–`P3` and the `sweeper:*` family in results, but ran no label-scoped sweep, so
   an explicit wontfix ruling on any of the six could exist unseen.
7. **No behavioural probe was run against any gateway.** Everything upstream-side is issue/PR text
   plus a code read at HEAD. In particular, #45236's "0 of 35 api_server sessions" is *the
   reporter's* measurement on *their* install — I did not verify it against ours, and it is the
   single most consequential borrowed fact in this report.
8. **OJAMD remains unpinned**, unchanged from the re-check. Nothing here depends on it, but no
   claim here is verified against the host the phone actually talks to.

---

## 6. Bottom line

**Four of the six have real prior art; one has none; one is not a bug at all.**

The single most valuable find is **#79824** — the `_last_resolved_model` recovery net is a second,
independent channel for #241's alias poisoning that our own analysis missed entirely, and it
survives the fix we would have considered sufficient. Second most valuable is **#45236**, which
raises #187's true cost. Third is the confirmation that **#264 is intended behaviour with a
published rationale**, which retires the question of whether to expect an upstream fix.

**The decision to file anything, and the exact text if it ever happens, is Owen's alone. Nothing in
this document should be read as a recommendation to submit.**
