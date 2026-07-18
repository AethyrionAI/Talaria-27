# FABLE T27-134 — DEBUG forced-trip harness (free-tier launch gate: #102 / #110 device verify)

**OPEN_ITEMS:** #134 (this harness). Verifies the ALREADY-MERGED #102 (Lane H
breaker) and #110 (read-aloud retraction) on device.
**Branch prefix:** `claude/t27-134-`
**Collision:** `Talaria/Services/Live/LocalChatBackend.swift` + its test file
`TalariaTests/LocalChatBackendTests.swift` ONLY. No ChatStore / SpeechOutput /
composer edits. Independent of every open lane.

## DO NOT re-implement shipped work (staleness guard)

The breaker (#102, PR #83) and read-aloud retraction (#110, PR #86) are MERGED
and unit-tested. This lane adds ONLY a `#if DEBUG` harness that drives a
synthetic degenerate stream through the EXISTING production path so the breaker
and the speech-retraction can finally be observed tripping on a real device —
the deterministic model repro is defeated by the base model's own guardrails
(it refuses verbatim-repeat and declines long-form), so we cannot make the live
model loop on command. Touch NONE of the breaker/retraction logic.

## Why (the gate)

Free-tier standalone = a new install with no Hermes. The runaway/overheat risk
lives entirely on the on-device chat path. The token cap
(`chatGenerationOptions`) is device-proven; the breaker + read-aloud retraction
are unit-tested but have NEVER tripped organically on device. This harness lets
one device session verify: breaker arms→escalates→abandons→collapses, thermal
recovers, read-aloud does not drone the loop, and the next message still works.

## Seams (verified in tree 2026-07-18)

- `streamTurn(message:attachments:clientMessageID:into:)` — the `while true`
  loop; `for try await snapshot in stream`; breaker call
  `repetitionBreaker.shouldAbandon(afterObserving: degenerateTailRepetitionRun(in: latestFull))`;
  on trip: `logger.notice("streamTurn: degenerate tail repetition escalated …")`,
  `latestFull = collapsingDegenerateTail(latestFull)`, `break`, then
  `session = nil`, `continuation.yield(.finished(reply, usage, nil))`.
- Breaker constants: min unit 8, `repetitionMinimumRepeats` 6 (arms),
  `repetitionEscalationRepeats` 12 (floor), span 192, scan window 2048.
- Downstream that must be exercised UNCHANGED: `.textDelta(delta)` →
  ChatStore `speechOutput?.enqueueStreamChunk(delta,…)`; `.finished` →
  ChatStore `speechOutput?.finishStream(…)` + `#110 shouldRetractSpeech`.

## Change (all `#if DEBUG`)

1. **Trigger parser** — `debugForcedTripMode(for message: String) -> DebugTripMode?`
   recognising a trimmed, case-insensitive `/forceloop` (optionally `/forceloop N`
   to set copies). Returns nil in RELEASE (whole symbol under `#if DEBUG`), so a
   Release build sends `/forceloop` to the model as ordinary text.
2. **Synthetic snapshot generator** — nonisolated static
   `debugDegenerateSnapshots(copies:) -> [String]`: a benign preamble, then a
   qualifying loop unit (≥8 chars, passes `repetitionUnitQualifies`, e.g.
   `"The signal repeats. "`) appended ONE copy per snapshot up to `copies`
   (default 16 → span 320 ≥ 192, clears the 12 escalation floor with margin).
   Cumulative snapshots, mirroring FM's stream shape.
3. **Early branch in `streamTurn`** — right after `prompt` is composed, guarded
   `#if DEBUG`: if `debugForcedTripMode(for: message)` is non-nil, run a
   `debugForcedTripTurn(...)` that reuses the REAL downstream — for each
   synthetic snapshot: `streamDelta` → `.textDelta`; feed `latestFull` to a real
   `RepetitionBreaker`; on trip emit the SAME `logger.notice`, collapse via
   `collapsingDegenerateTail`, `appendAssistantMessage`, `session = nil`,
   `.finished`. Return. Production path below is untouched.
4. **(Optional, nice-to-have) `-live` mode** — `/forceloop-live` additionally
   starts a real `liveSession.streamResponse` on a long benign prompt to keep an
   SDK generation in flight, suppresses its output, yields the synthetic loop
   instead, and cancels the live task on trip — proving abandoning a LIVE SDK
   stream does not wedge the next turn. Primary mode already proves the
   user-visible post-trip send via the `session = nil` rebuild; ship `-live`
   only if it's cheap.

## Acceptance (device, one session)

- **D2 (#102):** `/forceloop` → reply collapses to ONE copy of the unit; console
  shows the breaker `notice` line; `deviceStatus` thermal stays ≤ fair and
  recovers (no sustained climb).
- **#110:** with auto-read-aloud ON, `/forceloop` → speech does NOT drone the
  looped tail; queued loop chunks are retracted at finish; speech ends clean.
- **D3:** immediately send a normal message → it streams a real reply (session
  rebuilt after `session = nil`), no "still working" wedge.
- **Release-inert:** a Release build treats `/forceloop` as a normal message.

## Tests (Swift Testing, add to existing `LocalChatBackendTests.swift` — NO new file, NO xcodegen)

- `debugDegenerateSnapshots` produces a sequence that arms the breaker at 6 and
  trips it by the default copy count; final snapshot's tail is a degenerate run.
- `collapsingDegenerateTail` on the last snapshot yields exactly one unit copy.
- Trigger parser: accepts `/forceloop`, `/forceloop 20`; rejects `forceloop`,
  `/force`, and a normal sentence.

## Discipline

- OPEN_ITEMS #134 edit is a SEPARATE surgical commit (Claude's) — do NOT fold it
  into the feature commit.
- File-scoped commits; merge commit only. Branch `claude/t27-134-…`.
- No new source file → `xcodegen generate` NOT required. If a new file becomes
  unavoidable, regen and re-verify `aps-environment: development`, WeatherKit,
  and the app-group entitlement all survived.
