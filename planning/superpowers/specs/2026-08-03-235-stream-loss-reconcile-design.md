# #235 — dead streams reconcile, recovered answers land at the tail (design)

**Date:** 2026-08-03 · **OPEN_ITEMS #235** (CRITICAL; not GitHub #235)
**Decided with Owen the same morning he hit it.** His placement requirement,
verbatim in intent: the recovered answer goes **after the last message**, where
he is looking — never injected above.

## The two defects (evidence in the OPEN_ITEMS entry)

The recovery machinery already exists and is correct — `.interrupted` →
`PendingRun` → reconcile loop → `attemptReconcile` (fetch store, adopt reply,
receipts, clear pending, notify). Two end-states never reach it:

- **D1 — the false-success close (the 9:47 shape).** A stream that ends
  WITHOUT error and without `run.completed` falls into the
  `!finalMessageDelivered` fallback, which yields `.finished` with the
  assembled content — **empty** when the stream died before any answer delta.
  The app renders an empty assistant bubble carrying the streamed reasoning
  (the REASONING + SKILL_VIEW groups with no text), the turn reads as
  answered, and no recovery ever arms.
- **D2 — the retired reconcile (the 9:50 shape).** `.interrupted` fires, the
  loop polls correctly, but its budget is 120 s wall clock and an agent turn
  can run longer. On retirement `pendingRun` stays set and NOTHING ever looks
  again — no foreground-return attempt, no chat-appear attempt. The #38 relay
  push is the designed backstop and was down that morning.

## The fix — three parts

### F1: empty-close routes to `.interrupted` (client)

In `SessionsHermesClient`'s stream end path: when the run started, no
`run.completed` arrived, and the assembled content is EMPTY (whitespace-only),
yield `.interrupted(sessionId:runId:)` instead of the empty `.finished`
fallback. Non-empty assembled content keeps today's fallback (a partial answer
beats no answer; the store adoption would drop streamed-but-uncommitted text).
Consequence: the empty-bubble rendering ceases to exist; D1 turns arm the same
recovery as thrown errors.

Edge accepted, recorded: a run that GENUINELY produces an empty reply (never
observed; probes and the store always show text) would leave a pending run
that reconcile cannot resolve (its predicate requires non-empty content). The
⏱ state is honest and cheap; if this edge ever appears in practice it gets its
own item — do not pre-build for it.

### F2: budget expiry keeps the pending run; two single-shot re-arm triggers

- The reconcile loop's retirement no longer abandons the run: `pendingRun`
  stays set (it already does — the missing half is re-arming).
- **Trigger 1:** app-becomes-active (the existing `handleAppDidBecomeActive`
  chain) fires ONE `attemptReconcile` when `pendingRun != nil`.
- **Trigger 2:** chat-screen appear fires the same single attempt.
- A successful attempt resolves exactly as today (adopt, receipts, clear,
  notify). A failed attempt leaves the ⏱ state; no new loop is started —
  single shots only, so a dead host cannot resurrect #145's grind. Both
  triggers coalesce through the existing `reconcileInFlight` single-flight.

Out of scope, recorded as follow-ons: persisting `PendingRun` across app
relaunch (Owen's pattern is suspend/resume); any parallel polling during live
streams.

### F3: recovered answers land at the TAIL (Owen's placement rule)

In `attemptReconcile`, after adopting the server conversation:

- If the recovered reply is already the conversation's last message → nothing
  changes; rendering is byte-identical to a normal reply.
- If later exchanges exist below it → **move the recovered reply to the
  transcript tail** and stamp it: a new optional `Message.recoveredForPrompt:
  String?` carrying a prefix of the user message it answers (~60 chars). The
  bubble renders a small muted marker line above the content ("↩ RECOVERED
  REPLY — 'So what's the holdup?…'") so a late answer can never masquerade as
  a reply to the newest question (#180: degradation visible, stamped).
- Honest inconsistency, accepted and recorded: a later `openSession` refetch
  shows server-chronological order (the marker field is local). The tail
  placement serves the moment of recovery, which is where the user is looking.
- `Message` is tolerant-decoded; the new optional field is cache-compatible
  (absent key → nil).

### The timeout experiment (in-lane, evidence-gated)

`makeChatPlaneSession()` sets `timeoutIntervalForRequest = 20` on the shared
config while stream requests stamp `timeoutInterval = 300`. Which wins
on-device is unpinned, and if the config wins, every >20 s silent gap kills a
foregrounded stream. One controlled experiment (scratch harness: local server
that sends SSE headers then stalls 25 s, request stamped 300 on a config-20
session): if the stream survives to 25 s, the per-request stamp wins — record
the verdict in the entry and change nothing. If it dies at ~20 s, streams get
their own `URLSession` (config request-timeout 300, resource 3600) and a
structural test pins that both streaming call sites use it. The experiment is
a scratch run, not a permanent suite member; the verdict is recorded either
way.

## Bars — mirrored into the OPEN_ITEMS #235 entry before the lane runs

- **235-A (sim):** a started-run stream that ends cleanly with no
  `run.completed` and empty assembled content yields `.interrupted` (not
  `.finished`); the same close with NON-empty content keeps today's fallback.
- **235-B (sim):** reconcile-loop budget expiry leaves `pendingRun` set; a
  foreground-return or chat-appear trigger fires exactly one
  `attemptReconcile` (single-flight coalesced); resolution clears the pending
  run.
- **235-C (sim):** with later exchanges present, the recovered reply lands at
  the transcript tail carrying `recoveredForPrompt`; with none, placement and
  fields are byte-identical to today's adoption.
- **235-D (experiment, recorded):** the 20-vs-300 verdict, with the harness
  transcript; the split-session fix lands ONLY on a config-wins verdict, with
  its own structural test.
- **235-E (device, Owen's reproduction):** send a long agent turn from the
  phone, background into another app, return after the turn completes
  server-side → the answer APPEARS at the tail without reopening the session,
  with a receipt; the ⏱ clears.
- **235-F (device):** a turn whose stream dies while later messages pile up
  shows the recovered reply at the bottom with the marker naming its prompt.

## Testing

TDD with RED watched. Sim tests ride the existing stream/state harnesses
(`ReasoningChannelTests`' fixture-stream shape for F1; ChatStore's
harness-visible reconcile seams for F2/F3 — `reconcileWallClockBudget` /
`reconcilePollInterval` already shrink for tests). Device bars ride the next
OTA. Gate before PR.
