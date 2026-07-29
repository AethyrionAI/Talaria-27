# OPUS-T27-200F-COMMUNITY-DESTALL — the survey-derived treatments, aimed at launch percentage

**Executor:** local Claude Code. **Drafted 2026-07-29 from the FILED #200E verdict
(PR #169 merged `6c22fe5`) and the FM SDK seam survey
(`planning/FM-SDK-SEAM-SURVEY-2026-07-28.md`), routed by Owen ("Go for merge. Then
lets write the handoff and dispatch for going into the community driven stuff that
may actually get us to an acceptable launch percentage").** Branch
`claude/t27-200f-community-destall`.

## Why

The remind create rate is the launch blocker: 0/50 pre-clause, 2/19 promoted, 5/10
under `.required` (a floor — see confound below), and `.required` itself is DEAD as a
path: 20/20 deterministic decoder errors on alarm/calendar
(`ifpInvalidExpertPickPosition` @1763/@1764). **Owen's routing: NO Apple filing** —
the last "Apple bug" was our own oversight; treat the crash as an unresolved
environmental constraint (possibly our DynamicProfile usage) and route around it.
What remains are the survey's community/Apple-corpus candidates, none yet measured:
Apple recommends 3–5 active tools per request (our belt is 10); Apple's own CATALOG
planner documents find-first-on-ambiguity (the read-substitution's likely training
origin) and an explicit reminders-vs-calendar preference rule; #200E proved the
forced first call is `readReminders` 10/10 — the model WANTS to read before
creating. Attack that directly: remove the read, or license skipping it.

## Part 0 — instrument fixes (REQUIRED before the cells; pins for each)

- **Per-trial reap.** #200E's treatment cell lost 4 of 10 remind trials to
  already-exists reads of REAL artifacts created by the control cell minutes
  earlier. Sweep `[T27-battery]` reminders/events after EVERY trial (alarms stay
  end-of-run tracked-ID; end-of-run full reap stays as backstop). Reap counts in
  the export become per-trial sums; keep the REAP line grammar stable.
- **Unmarked-title echo.** armed/haiku/t5 (#200E) leaked "[T27-battery] ," into a
  reply — the tool result echoes the FINAL (marked) title back to the model. Tool
  success responses must echo the model-requested title; the marker rides only the
  store write.

## Part 1 — the cells (4 × 4 prompts × n=10 = 160 trials, ~50 min)

- `armed` — promoted production control.
- `armed-scoped` — per-intent belt of 3–5 tools, reads INCLUDED (remind →
  createReminder/readReminders/readCalendar; alarm → scheduleAlarm(+readCalendar);
  calendar → createCalendarEvent/readCalendar/currentLocation). Apple's tool-count
  guidance, isolated.
- `armed-createonly` — per-intent belt WITHOUT same-domain read tools (remind →
  createReminder(+readCalendar); calendar → createCalendarEvent/currentLocation).
  Kills the read-substitution structurally: no readReminders to flee into.
- `armed-findfix` — full production belt; instructions gain the planner-corpus
  carve-out, one sentence each (measured artifact, pinned, flag-off byte-identical):
  "'Remind me' means create the reminder — do not search existing reminders first."
  and "Reminders and calendar events are different tools — prefer a reminder when
  the user asks to be reminded."
- Haiku trials in the scoped/createonly cells ride the REMIND scope — the
  worst-case misroute, which is what the canary exists to measure.
- Belt scoping is cell machinery (DEBUG), selected per prompt tag; production
  scoping would be router-driven and is a PROMOTION question, not this lane's.

## Success bar

Remind creates ≥8/10 in at least one cell, with alarm/calendar holding ceiling in
that cell, grabs ≤ control, and no new corruption. Verdict discipline as ever —
rates from RAW TEXT, ERROR/TIMEOUT excluded and listed, reap arithmetic exact (now
per-trial). A winning cell promotes via its own #163-style follow-up (clause →
instructionsText flag; scoping → router integration design first).

## Rules

House rules. Nothing promotes without the verdict. Corded deploy preferred while
Owen is home (detach main checkout → RunProject → restore main + discard scheme
churn — the #200E flow). Out of scope: the cap cell (D4), the DynamicProfile
adoption bundle, Hermes-as-provider, any `.required` rerun, tool-description edits.
