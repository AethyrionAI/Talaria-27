# FABLE T27-134 — DEBUG forced-trip harness (free-tier launch gate: #102 / #110 device verify)

**OPEN_ITEMS:** #134 (this harness). Verifies the ALREADY-MERGED #102 (Lane H
breaker) and #110 (read-aloud retraction) on device.
**Branch prefix:** `claude/t27-134-`
**Collision:** `LocalChatBackend.swift` + `DiagnosticsSettingsScreen.swift`
(new DEBUG panel) + possibly a thin `ChatStore.swift` DEBUG method + the test
file `TalariaTests/LocalChatBackendTests.swift`. Everything additive and
`#if DEBUG`-guarded. **Collision check before dispatch:** #120 (chat hygiene →
ChatStore) and #118–119 (voice residuals → Diagnostics voice panel) touch the
same files — land after those if either is in flight; conflicts should be
trivial (new panel / new method, no shared lines).

## DO NOT re-implement shipped work (staleness guard)

The breaker (#102, PR #83) and read-aloud retraction (#110, PR #86) are MERGED
and unit-tested. This lane adds ONLY a `#if DEBUG` harness that drives a
SYNTHETIC degenerate stream through the EXISTING production path so the breaker
and speech-retraction can finally be observed tripping on a real device — the
deterministic model repro is defeated by the base model's own guardrails (it
refuses verbatim-repeat and declines long-form), so we cannot make the live
model loop on command. Touch NONE of the breaker/retraction logic.

## Why (the gate)

Free-tier standalone = a new install with no Hermes. The runaway/overheat risk
lives entirely on the on-device chat path. The token cap
(`chatGenerationOptions`) is device-proven; the breaker + read-aloud retraction
are unit-tested but have NEVER tripped organically on device. This harness lets
one device session verify: breaker arms→escalates→abandons→collapses, thermal
recovers, read-aloud does not drone the loop, and the next message still works.

## Seams (verified in tree 2026-07-18)

- `LocalChatBackend.streamTurn(message:attachments:clientMessageID:into:)` — the
  `while true` loop; `for try await snapshot in stream`; breaker call
  `repetitionBreaker.shouldAbandon(afterObserving: degenerateTailRepetitionRun(in: latestFull))`;
  on trip: `logger.notice("streamTurn: degenerate tail repetition escalated …")`,
  `latestFull = collapsingDegenerateTail(latestFull)`, `break`, then
  `session = nil`, `.finished(reply, usage, nil)`.
- Breaker constants: min unit 8, `repetitionMinimumRepeats` 6 (arms),
  `repetitionEscalationRepeats` 12 (floor), span 192, scan window 2048.
- Downstream that MUST run UNCHANGED: `.textDelta` → ChatStore
  `speechOutput?.enqueueStreamChunk(delta,…)` (~:413); `.finished` → ChatStore
  `speechOutput?.finishStream(…)` + `#110 shouldRetractSpeech` (~:548).
- Home for the trigger: `Talaria/Features/Settings/DiagnosticsSettingsScreen.swift`
  — SwiftUI screen with `@Environment(AppContainer.self) private var container`,
  composed of per-subsystem panels (`voicePanel`, `sensorPanel`, …) using
  `MonoLabel` + `.hudPanel` + `Design.*` tokens. Add a new panel matching that
  pattern.

## Change (all `#if DEBUG`)

1. **Synthetic snapshot generator** — nonisolated static
   `debugDegenerateSnapshots(copies:) -> [String]`: a benign preamble, then a
   qualifying loop unit (≥8 chars, passes `repetitionUnitQualifies`, e.g.
   `"The signal repeats. "`) appended ONE copy per snapshot up to `copies`
   (default 16 → span 320 ≥ 192, clears the 12 escalation floor with margin).
   Cumulative snapshots mirroring FM's stream shape.
2. **Forced-trip turn** — a `#if DEBUG` entry that reuses the REAL downstream:
   per synthetic snapshot `streamDelta` → `.textDelta`; feed `latestFull` to a
   real `RepetitionBreaker`; on trip emit the SAME `logger.notice`, collapse via
   `collapsingDegenerateTail`, `appendAssistantMessage`, `session = nil`,
   `.finished`. **It MUST flow through ChatStore's EXISTING streaming-update
   consumer** (the one that calls `enqueueStreamChunk`/`finishStream`) — reuse
   the normal on-device send, do NOT build a parallel consumer, or the #110
   retraction is not exercised. Implementation latitude: either set a
   `#if DEBUG` flag on `LocalChatBackend` and issue a normal on-device send that
   takes the synthetic branch, or add a thin `#if DEBUG`
   `ChatStore.debugRunForcedTrip(copies:)` that reuses the same consumer.
3. **Trigger UI** — a `#if DEBUG`-guarded panel in `DiagnosticsSettingsScreen`
   (`// Local brain — #102`), mirroring `voicePanel`/`sensorPanel`
   (MonoLabel + `.hudPanel` + `Design.*`), with a **"Force repetition trip"**
   button that invokes (2) via `container`. A one-line hint: "Turn on read-aloud
   first to verify #110." Optional second button **"Force trip (live SDK)"** —
   nice-to-have: starts a real `liveSession` generation to keep an SDK stream in
   flight, suppresses its output, yields the synthetic loop, cancels on trip →
   proves abandoning a LIVE SDK stream doesn't wedge the next turn. Ship only if
   cheap; the primary button already proves post-trip send via `session = nil`.
4. **Release-inert by construction** — the generator, the forced-trip entry, and
   the Diagnostics panel are all `#if DEBUG`; none exist in a Release build. No
   parser, no magic string.

## Acceptance (device, one session)

Open **Settings → Diagnostics → Local brain → Force repetition trip**:
- **D2 (#102):** reply collapses to ONE copy of the unit; console shows the
  breaker `notice` line; `deviceStatus` thermal stays ≤ fair and recovers.
- **#110:** with auto-read-aloud ON, speech does NOT drone the looped tail;
  queued loop chunks are retracted at finish; speech ends clean.
- **D3:** immediately send a normal chat message → it streams a real reply
  (session rebuilt after `session = nil`), no "still working" wedge.

## Tests (Swift Testing, add to existing `LocalChatBackendTests.swift` — NO new file, NO xcodegen)

- `debugDegenerateSnapshots` produces a sequence that arms the breaker at 6 and
  trips it by the default copy count; the final snapshot's tail is a degenerate
  run (`hasDegenerateTailRepetition` true).
- `collapsingDegenerateTail` on the last snapshot yields exactly one unit copy.

## Discipline

- OPEN_ITEMS #134 edit is a SEPARATE surgical commit (Claude's) — do NOT fold it
  into the feature commit.
- File-scoped commits; merge commit only. Branch `claude/t27-134-…`.
- No new source file → `xcodegen generate` NOT required. If a new file becomes
  unavoidable, regen and re-verify `aps-environment: development`, WeatherKit,
  and the app-group entitlement all survived.
