# #240 — Pre-`run.started` parking fix (dupe + armed auto-resend) — Design

**Date:** 2026-08-03 (night) · **Approved by Owen:** both fixes, same evening.
Found by 238-D trial 2 on build 1908 (the question duped with a queued clock glyph;
the answer proved the run was live server-side).

## Root cause (read, cited in the OPEN_ITEMS #240 entry)

`SessionsHermesClient.streamTurn`'s catch branch routes to `.unreachable` (→ #90
durable `.queued` parking + auto-resend on drain) whenever `runStarted == false` and
the error is unreachable-family. A fast background kills the SSE in the window where
the server has ACCEPTED the run (HTTP 2xx received) but the client has not yet parsed
`run.started` — the teardown surfaces as `URLError.notConnectedToInternet`-family, so
a live run is misread as "never reached the API." #235 covered every window after
`run.started`; this is the same hole one event earlier.

## Fix 1 — `responseReceived` guard (SessionsHermesClient)

- New local `var responseReceived = false` beside `runStarted`; set `true`
  immediately after the existing 2xx status guard passes on
  `session.bytes(for: request)`.
- Catch branch condition becomes `if runStarted || responseReceived` →
  `.interrupted(sessionId: capturedSessionId, runId: runId)` (runId is already
  `String?`; nil before `run.started`). `PendingRun.runId` is optional and
  `attemptReconcile` resolves positionally, so recovery works unchanged; the
  `resolvedRunIDs` idempotence record is simply skipped for nil runIds (existing
  behavior).
- `.unreachable` (queued parking) is now reachable ONLY when the request provably
  never got a response — the honest meaning of "never reached the API."

## Fix 2 — drain-time adoption guard (ChatStore.drainComposeOutboxIfPossible)

- At drain start (once, before the loop), fetch the active session's message
  history via the same client call `attemptReconcile` uses. On fetch failure,
  proceed exactly as today (the guard is an optimization, not a gate — offline
  drains must still work).
- For each queued turn: if the history contains a `.user` message whose trimmed
  content equals the turn's trimmed text with timestamp ≥ `composedAt − 60s`
  (clock-skew slack), DROP the outbox copy without sending — mirroring the
  existing "duplicated a pending row — dropped" branch, with its own log line
  ("compose outbox: turn already delivered server-side — adopted, not re-sent
  (#240)"). The transcript merge already carries the server copy.
- This heals rows parked BEFORE the fix, including the live one on Owen's phone.

## Out of scope

The visible-order cosmetics of an already-parked row (fix 2 removes the row at
drain; no separate re-ordering pass). The deepseek-flash server-side stall
(evidence collection belongs to the OJAMD session).

## Bars — pre-registered in the #240 entry BEFORE the run

- **240-A (sim, mechanical):** a fixture stream that returns 2xx then throws an
  unreachable-family URLError BEFORE any `run.started` event yields
  `.interrupted` (session id set, runId nil) and parks nothing; the same fixture
  throwing BEFORE the response yields `.unreachable` and parks (the honest case
  keeps working). Watched RED first.
- **240-B (sim, mechanical):** a queued turn whose text exists in fetched history
  at/after `composedAt − 60s` is dropped with no `sendMessage` call; a queued
  turn absent from history still re-sends; a failed history fetch drains as
  today. Watched RED first.
- **240-C (device, Owen, opportunistic):** the currently parked Steam-question
  row drains WITHOUT Hermes answering it a second time.
- Gate (Debug suite + Release) before PR; suite delta counted before the
  verification run.

## Testing strategy

TDD on both fixes with the existing fixture idioms (LateInterruptClient family for
the stream; injected history for the drain guard). No UI change, no settings, no
migration — `ComposeOutboxState` is untouched.
