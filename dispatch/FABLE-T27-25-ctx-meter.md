# FABLE T27-25 — CTX meter reads 0 / absent on resumed sessions

**Repo:** `AethyrionAI/Talaria-27` · **Branch prefix:** `claude/t27-25-*`
**Dispatch date:** 2026-07-16 · **Tracks:** OPEN_ITEMS #25, GitHub issue #90
**Size:** small PR. **PROBE ANSWERED 2026-07-16 — GATE LIFTED, READY TO SEND.**
The verdict changed the fix: see "Probe results" below. Read that section before
anything else — the obvious implementation is a trap that ships a permanent 0%.

**Merged-PR check done 2026-07-16:** no CTX/meter/denominator PR exists in 106
PRs; the 07-13 audit's own search of MAIN_LOG found zero commits touching it.
Live bug, and the item's cited "fix" evidence (GitHub #4 / PR #21) was already
debunked by that audit as unrelated — `#4` is an internal shorthand tag in this
codebase, NOT a GitHub link. Don't re-follow that trail.

## Symptom (device verify 2026-07-05: FAILED)

CTX shows **0 on some sessions**, **absent entirely on older sessions**, and
occasionally flashes in before reading wrong. Header's old "denominator ~1.4x
high" line describes a superseded 2026-06-27 state — the real current symptom
set is the one above.

## Root cause for the "0 / absent on resumed sessions" half — CONFIRMED at HEAD

Re-verified in source 2026-07-16 (the 07-13 audit's mechanism still holds):

- `SessionsHermesClient.swift:1523` `private struct SessionMessagesResponse:
  Decodable` → `struct StoredMessage` decodes **`role`, `content`,
  `timestamp`, `toolCalls` — and no usage field of any kind.**
- `fetchSessionConversation` (used by `openSession`) builds `Conversation` from
  that response → `latestUsage` is therefore **always nil** for any resumed or
  older session.
- `ChatScreen.swift:569` `contextProgress` → `guard let usedTokens =
  currentContextTokens, let maxCtx = effectiveContextWindow, maxCtx > 0 else
  { return 0 }` → returns 0 → `contextGauge` renders "CTX 0%".

That is exactly "0 / absent on older sessions", mechanically, with no
speculation. A live session that has received a `run.completed` has usage and
reads fine — which is why this looks intermittent rather than structural.

## Probe results — run 2026-07-16 against OJAMD `:8642` (Bearer API_SERVER_KEY)

Ran live against production. Three endpoints, 25 sessions, all four sources
(`api_server` / `cron` / `desktop` / `tui`). Verdict: **outcome (c)** — with a
trap the original three-way framing missed.

**1. `GET /api/sessions/{id}/messages` — the endpoint the app resumes from.**
Per-message keys: `id, session_id, role, content, tool_call_id, tool_calls,
tool_name, timestamp, token_count, finish_reason, reasoning, reasoning_content`.
No top-level usage object.

> **THE TRAP: `token_count` exists on every row and is `null` on every row.**
> Verified 100% null across an 8-message `api_server` session (Talaria's own
> source), a 10-message `api_server` session, and a 33-message `cron` session.
> Decoding `token_count` LOOKS like the one-line fix, compiles, passes a naive
> test with a hand-made fixture, and renders 0% forever on real data. Do not.

**2. `GET /api/sessions` (list) and `GET /api/sessions/{id}` (detail) — usage
EXISTS here:** `input_tokens`, `output_tokens`, `cache_read_tokens`,
`cache_write_tokens`, `reasoning_tokens`, `api_call_count`, plus
`has_system_prompt` / `has_model_config`. (`/runs` and `/usage` → 404; they
don't exist.)

**3. But session-level usage is CUMULATIVE, not context occupancy — do not
divide it by the context window.** `input_tokens` sums the prompt of every API
call in the session, and each turn re-sends the whole history, so it grows
superlinearly against actual context. Measured on live sessions:

| session | msgs | api_calls | input_tokens | naive % of 128k |
|---|---|---|---|---|
| `api_1783825106_6e2766ab` | 10 | 5 | 114,754 | **90%** ← nonsense |
| `api_1784251978_398321fc` | 12 | 6 | 70,271 | 55% |
| `api_1784251993_19bf66c6` | 8 | 4 | 14,333 | 11% |

A 10-message chat does not fill 90% of a 128k window. Cumulative/last-run
≈ 1.5× for a 2-call session and worsens from there — **which is very likely the
origin of this item's historical "denominator ~1.4× high" note.** That note was
probably never a denominator bug at all; it was this over-count measured on a
short session. Record that in the PR.

## Therefore: the fix (no endpoint can tell us, so stop asking one)

Nothing on the wire exposes "tokens occupied by the last run's prompt" for a
resumed session. So:

1. **Cache it app-side.** When a live `run.completed` arrives (the app already
   parses its usage — that path works and is why live sessions read correctly),
   persist that usage keyed by session id. On resume, read the cache.
2. **Unknown → honestly absent.** No cached value (session from another device,
   or pre-dating this feature) → HIDE the gauge. Do not render "CTX 0%". A wrong
   number is worse than no number — that is the entire complaint in this item.
3. **Never** derive the numerator from cumulative `input_tokens`. If a future
   reader wants a session-cost surface, that field is perfect for it — it is
   simply not a context meter. Say so in a comment so nobody re-tries it.
4. `SessionMessagesResponse` decode stays as-is; adding `token_count` buys
   nothing while the server sends null. (If Hermes later populates it, a summed
   count + system-prompt allowance becomes viable — note as a future path.)

## Bonus finding (not this lane — file/cross-ref, don't build)

Stored messages carry **`reasoning` and `reasoning_content` per row**. OI #60
established real reasoning lives in `run.completed.reasoning_content` for live
turns; this means resumed sessions could restore their reasoning panes too,
which the app does not do today. Cross-ref #60; do not scope-creep into it here.

## The second half — "flashes in before reading wrong"

Separate from the resume path and NOT covered by the decode fix. Likely the
gauge rendering a transient/partial usage during streaming before
`run.completed` lands with the authoritative numbers. Investigate the
`currentContextTokens` source during a live stream; if it's an interim
estimate, either suppress the gauge until authoritative or mark it as
provisional. Cross-ref #46, which independently reaffirmed the denominator
question is still open. Scope this half to the PR only if it stays cheap;
otherwise split and say so.

## Constraints (house)

- File-scoped commits; no `OPEN_ITEMS.md` edits. Tolerant decoding — a missing
  or malformed usage field must degrade to "unknown", never to a wrong number
  and never to a throw (the #58 inbox lesson: `toolCalls` in this very struct
  already models the tolerant pattern at `:1534-1536` — follow it).
- `xcodegen generate` only if files add/remove (a test file likely will —
  separate regen commit, verify `aps-environment` survives).
- Toolchain **Xcode-beta3**. Baseline **691 tests / 58 suites**.

## Acceptance

- PR body restates the probe verdict (wire shape = permanent knowledge, not a
  thing we re-discover in September), including why `token_count` is a trap and
  why cumulative `input_tokens` is not a context meter.
- Decode/fallback per the probe's verdict, tolerant.
- Tests: resumed-session-with-usage → gauge reads it; resumed-session-without
  → gauge honestly absent, NOT 0%; malformed usage → absent, no throw.
- Device check (Owen's): open an OLD session — gauge shows a real number or is
  honestly absent. Then send a message — it becomes live and correct.
