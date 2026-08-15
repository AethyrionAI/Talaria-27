# FABLE T27 — voice triage: #302 (mic behind the lock) · #303 (no engine upgrade path) · #301 (libdispatch kill on sim)

**Items:** OPEN_ITEMS **#302**, **#303**, **#301** — all filed 2026-08-09 from
#254's device logs, all "observed in passing, never investigated."
**Difficulty: FABLE** — instrumentation design on the audio-capture chain, an
engine-router change constrained by #221's gate, and an unattributed crash.
Three INDEPENDENT lanes sharing one log corpus; run them in this order.
Written 2026-08-10.

## Lane 1 — #302: is the microphone live behind App Lock? (privacy; first)

**Verified state (entry, build 2330, two trials):** a Control Center voice
launch on a locked app logs `voice session starting` **~653 ms before** AppLock
sees `.active`, ~1.16 s before unlock succeeds. The `audio deactivated by app`
line 103 ms later is *consistent with* benign but **proves nothing** — it's a
general-purpose teardown line (the entry warns against reading it as an
answer). Three candidate readings (a) benign-wait / (b) briefly-hot mic /
(c) benign-only-because-unlock-was-fast.

**Bars 302-A/B/C are already pre-registered in the entry.** This dispatch adds
execution notes only:

- **302-A (measure, don't infer):** instrument the capture chain state between
  `voice session starting` and unlock resolution. The honest instrument reads
  the ENGINE's own state (`AVAudioEngine.isRunning` / input-node tap
  installed), not our wrapper's flags — a wrapper flag is the thing under
  suspicion. `.notice`-level, always-on lines (Console redaction gotcha:
  `privacy: .public`).
- **302-B fixture is STALE and must be re-arranged before running:** the entry
  says the cancelled-unlock interval is *"trivially arranged while #272 is
  unfixed"* — **#272 was FIXED and CLOSED 2026-08-09 (PR #289).** The locked
  interval is now held open legitimately: Cancel leaves the sheet down with
  the in-app UNLOCK button waiting (the fixed behaviour). Same interval,
  different arrangement; note it in the entry when running.
- **302-C is OWEN'S and comes BEFORE any fix:** refuse / defer-until-unlock /
  proceed-as-now. Do not build past the measurement without his written
  contract in the entry.
- **Pre-registered response stands:** both-cold ⇒ closes NOT A DEFECT with the
  ordering documented.

## Lane 2 — #303: the router's missing upgrade path

**Verified state (entry, from source):** `VoiceEngineRouter.swift:238`'s
"last line of defence" re-check fires in ONE direction (realtime→native
downgrade). A cold Control Center launch reads the brain 35 ms before the
sticky-default restores `hermes` and starts native 283 ms later. **Cost
UNMEASURED** — on the host it was found on, realtime wasn't configured, so
behaviour was identical to correct.

**Bars 303-A/B/C are already pre-registered in the entry.** Execution notes:

- **303-A/B need a realtime-configured host** — that is the OJAMD sitting
  (`handoffs/HANDOFF-2026-08-09-OJAMD-SESSION.md` §11 pairs it with R6/#138;
  one voice sitting covers all three). **Do not build the fix before 303-A
  runs** — if the cold path reaches realtime there, the defect reading is
  wrong and the entry's fail-safe reading wins.
- **303-C is the constraint that makes this FABLE:** any upgrade path keeps
  the downgrade direction intact — #221's gate (never ship mic audio to the
  host's provider against the brain setting) must be provably un-weakened.
  The fix wants a re-route at `startSession` entry (both directions evaluated
  from CURRENT brain), not a relaxation of the guard.
- **#320 interacts** (filed 2026-08-09): the realtime indicator must track
  whatever engine actually starts — if this lane changes cold-start routing,
  #320's lane needs to know. Cross-reference, don't build #320 here.

## Lane 3 — #301: the sim libdispatch assertion

**Verified state (entry):** `BUG IN CLIENT OF LIBDISPATCH … expected to
execute on queue [com.apple.main-thread]` on `CC-272-iPhone-Air` (Debug) after
granting mic+speech, entering native voice. The known trap
(MainActor-formed completion on a framework's private queue) is recorded as
**device-only** — a sim hit either widens the trap or is a second defect.
Explicitly NOT #254's change (`onDisappear` never ran).

**Owed (per entry) — investigation before any code:**

- **301-A:** reproduction attempt — fresh sim, grant mic+speech, native voice
  path. Record rate (n≥5 attempts) — flaky-or-deterministic changes the
  debugging approach.
- **301-B:** name the site — which framework completion, formed where,
  dispatched where. Symbolicated crash + the enqueuing frame. The known trap's
  family suggests speech/audio callbacks
  (`SFSpeechRecognizer`/`AVAudioEngine` taps); confirm, don't assume.
- **301-C:** only then a fix, specific to the named site — **the entry's own
  warning: no blind `@Sendable` sweep.**
- If it does NOT reproduce in 301-A, record the attempt count and park the
  item as a watch — a sim ghost with no repro gets no code.

## Shared traps

- One log corpus (#254's archive) serves all three — do not re-run #254's
  arms to regenerate evidence that already exists.
- The engine-ambiguity rule (#220): every voice verdict quotes the
  `voice session starting on engine …` line. All three lanes inherit it.
- #302 composes with the FIXED #272 — if the lock behaviour looks different
  from the entry's description, that's the fix, not a new bug.

## Owen's to decide

- **302-C — the locked-launch contract** (refuse / defer / proceed): before
  any #302 fix.
- Whether Lane 2's device half rides the OJAMD sitting (recommended — it's
  already queued there) or waits.
