# FABLE T27-25 — CTX meter reads 0 / absent on resumed sessions

**Repo:** `AethyrionAI/Talaria-27` · **Branch prefix:** `claude/t27-25-*`
**Dispatch date:** 2026-07-16 · **Tracks:** OPEN_ITEMS #25, GitHub issue #90
**Size:** small PR — **but see the wire probe gate below. Do not start the
decode work until the probe answers.**

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

## GATE: the wire probe (blocks the fix, not the analysis)

The fix depends on a fact nobody has established: **does the Sessions API
return usage on the stored-messages endpoint at all?**

    GET /api/sessions/{id}/messages   (Bearer API_SERVER_KEY, :8642)

Three outcomes, three different lanes:

- **(a) usage present per stored message** → decode it; smallest possible fix.
- **(b) usage present at the session/response level** (not per message) →
  decode there, carry onto `Conversation.latestUsage`.
- **(c) no usage anywhere on the endpoint** → the decode approach is DEAD.
  Fallback shapes, in preference order: reconstruct from the last
  `run.completed` if the session has one cached locally; or persist usage
  app-side keyed by session id when we DO see it live, so a resumed session
  reads its own last-known value; or make the gauge honestly absent (hide, not
  "0%") when usage is genuinely unknown.

**Never render a confident 0% for unknown.** A wrong number is worse than no
number — that's the whole complaint in this item.

Owen or Claude Desktop runs the probe against OJAMD (`100.110.102.59:8642`) or
the Mac Mini gateway; Fable cannot reach either. **Do not build (a) on
assumption** — this item has already burned one cycle on unverified fix
evidence.

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

- Probe answered and RECORDED in the PR body (the wire shape becomes permanent
  knowledge, not a thing we re-discover in September).
- Decode/fallback per the probe's verdict, tolerant.
- Tests: resumed-session-with-usage → gauge reads it; resumed-session-without
  → gauge honestly absent, NOT 0%; malformed usage → absent, no throw.
- Device check (Owen's): open an OLD session — gauge shows a real number or is
  honestly absent. Then send a message — it becomes live and correct.
