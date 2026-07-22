# FABLE-T27-156D — Insights: session usage and cost, on the only numbers that exist

**Item:** OPEN_ITEMS #156d (final buildable lane of #156), sized by #158, corrected by #159/#161,
semantics settled by #25, source + live-host pass 2026-07-22 ·
**Repo:** AethyrionAI/Talaria-27 · **Base:** main (after #136 / 156b) · **Branch:**
`claude/t27-156d-insights` · **Size:** small-medium, one PR
**Staleness check:** re-run at start (`gh pr list`, `git log --grep t27-156d`). OPEN_ITEMS ≠ GitHub numbers.

## Mission

A read-only usage panel: what the agent has been doing and roughly what it costs, per session and
in aggregate. Joins the drawer as the third agent surface (TASKS → SKILLS → INSIGHTS). **Zero new
infrastructure** (#161): one existing gateway list endpoint plus per-turn usage the app already
captures.

This lane's defining constraint is **honesty about what the numbers mean.** Read the next section
twice before writing any UI copy.

## The semantics rules — #25 is settled law here

The repo's own verdict lives in `Talaria/Models/SessionUsageIndex.swift`'s doc comment; the spec
restates it as binding:

1. **Per-message token counts DO NOT EXIST.** `messages.token_count` is null on 100% of rows
   (0/7595 empirically, #158) — the column is never written upstream. Do not fetch messages, do
   not render a per-message timeline, do not leave a TODO implying one is coming. NOT-POSSIBLE is
   the settled verdict.
2. **Session `input_tokens` is cumulative BILLING, never context occupancy.** Every API call
   re-sends the whole history, so the field grows superlinearly — a 10-message session measured
   90% of a 128k window in the #25 probe. Present it only as cost/volume ("tokens billed"),
   NEVER as a context meter, NEVER divided by a context window. The CTX gauge is a separate,
   already-correct surface (`SessionUsageIndexStore`) — do not touch it, do not duplicate it,
   do not let Insights and the gauge appear to disagree by labeling them the same thing.
3. **Honest absence over rendered zeros.** `SessionUsage.isEmpty` → nil → no row of zeros. Cost
   fields specifically: `estimated_cost_usd` is 0.0 on real sessions here and `actual_cost_usd`
   is null — show cost only when a value is present and nonzero; otherwise omit the element
   entirely (the established "hides rather than lies" posture).

## Verified surface

**`GET /api/sessions`** on `:8642` (Bearer `API_SERVER_KEY`) — handler at `api_server.py:2246`:
`limit` (default 50, **max 200**), `offset`, optional `source` filter,
`include_children` (default false — leave it false; fork children would double-count),
ordered by last-active. Returns `{object, data, limit, offset, has_more}`, each row the same rich
shape as the single-session read: `id, source, model, title, started_at, ended_at, message_count,
tool_call_count, api_call_count, input_tokens, output_tokens, cache_read_tokens,
cache_write_tokens, reasoning_tokens, estimated_cost_usd, actual_cost_usd, parent_session_id, …`

**No aggregate/stats endpoint exists** (route table checked) — aggregation is client-side, over
an explicitly labeled window (see D3).

**Per-turn usage** — `run.completed` carries exactly `{input_tokens, output_tokens, total_tokens}`
(built at `api_server.py:3306`; no per-turn cache/reasoning split — those are session-cumulative
only). The app **already parses and persists this** (`SessionUsageIndexStore`, #25). Insights may
read that store for a "this device, recent turns" strip; it must not re-parse the stream.

## Already built — extend, do not duplicate

- `SessionUsage` (`Talaria/Services/Support/TurnReceipts.swift:~225`) tolerantly decodes **all
  nine stat fields** with the honest-absence rule, and `SessionsHermesClient.swift:1603` already
  applies it to session rows. The decode layer for this lane exists. If the existing sessions-list
  call already surfaces everything D1 needs, D1 collapses to a thin fetch wrapper — check its
  call path first and prefer reuse.
- `SessionUsageIndexStore` — the per-turn cache. Read-only from this lane.
- Drawer pattern — `tasksRow` / `skillsRow` in `SessionsDrawer.swift`; add `insightsRow`
  (suggested glyph: `chart.bar.xaxis`), route `.insights`, unconditional presence.

## Deliverables

### D1 — Stats fetch

Paged fetch over `GET /api/sessions` on the `CronJobService`/`SkillsService` seam (provider
closures, same typed errors). Fetch up to **3 pages of 200** (600 sessions), stopping early when
`has_more` is false; surface "showing the N most recent sessions" when truncated. Reuse the
existing `SessionUsage.decodeIfPresent` — **do not write a second decoder.**

### D2 — Aggregation model

Pure value-type math, fully unit-testable: totals (tokens in/out, cache read/write, reasoning,
api calls, tool calls, sessions, messages), split by `source` and by `model`, over the fetched
window. Cost totals computed only from rows where cost is present and nonzero, and labeled
"estimated" — never sum nulls into a confident-looking figure. Sessions with `SessionUsage == nil`
count toward session/message tallies but contribute nothing to token math.

### D3 — `Talaria/Features/Insights/InsightsScreen.swift`

Match the Tasks/Skills design language (`MonoLabel`, `Design.*`, hudPanel), same content-state
grammar (loading / error+retry / empty / loaded, errors never replace shown content,
pull-to-refresh). Layout, top to bottom:

- **Window banner** — "LAST N SESSIONS · <host>" so the scope of every number is on screen, not
  implied.
- **Totals strip** — tokens in/out (formatted 1.2M-style), tool calls, api calls; cost appended
  only under rule 3.
- **By-source and by-model breakdowns** — compact rows with counts and token shares. Numeric
  first: plain text rows, with at most a proportional bar rendered via the **existing #100
  ChartCanvas pipeline if and only if it drops in trivially** — the chart contract is Path B and
  "no second chart impl" is standing law; a new charting dependency is an automatic scope
  violation. Numbers-only is a fully acceptable ship.
- **Per-session list** — title (or id prefix), model, source badge, tokens in/out, tool calls,
  relative last-active. Tapping expands in place (duration, cache/reasoning tokens, message
  count, cost if present). No navigation into chat, no detail screen.

Wording rule for every label: this is **activity and billing volume**. The words "context",
"window", "capacity", and any percentage-of-limit framing are banned from this screen.

### D4 — Drawer row + route

`insightsRow` below `skillsRow`, `.insights` route case, container wiring on the active profile's
gateway — mechanical, mirror 156b's D4 commit.

### D5 — Tests

Swift Testing. The aggregation model is the test surface: totals math, source/model splits,
nil-usage sessions counted-but-not-summed, cost-presence gating (0.0 and null both suppress),
truncation banner trigger, number formatting. Plus fetch-layer pagination (stops at `has_more`
false, caps at 3 pages) against fixtures. Baseline to beat: **1051 tests / 92 suites** (post-#136).

## Explicitly out of scope

- Anything per-message — settled NOT-POSSIBLE (#25/#158)
- Any context-occupancy framing — the CTX gauge owns that and stays untouched
- Charts beyond a trivial ChartCanvas reuse; any new chart implementation or dependency
- Time-bucketed history ("tokens this week") — `started_at` supports it in principle, but the
  fetched-window cap makes the buckets misleading at the edges; park it, note it in OPEN_ITEMS
  if tempted
- Cross-host aggregation — active profile only, like Tasks and Skills
- Polling/auto-refresh; caching beyond in-memory

## Conventions — non-negotiable

Identical to 156A/156B: merge commits only; file-scoped commits; **OPEN_ITEMS.md in its own
commit**; `xcodegen generate` (new files) with regen in a separate commit and the
`aps-environment: development` entitlements check after; `export
DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer`; pinned sim
`47F68496-24F9-45D9-93D3-1C778DB6B557`, `CODE_SIGNING_ALLOWED=NO`; read the Swift Testing
`Test run with N tests in M suites passed` line, not `Executed N tests`. Strict-concurrency
DO-NOT-COPY list stands (#160). Known flake: `testDisconnectReturnsToStandaloneChat` may fail on
the warm bundle run (#164) — solo-rerun to confirm, and say so in the handoff rather than
silently rerunning.

## Provenance

hermex (MIT) reviewed as design reference only; their Insights targets a different server's
richer stats surface, so only the presentation instinct (numbers-first, source badges) carries
over. No source used or adapted; if that changes, stop and update `THIRD_PARTY_LICENSES.md`
first.
