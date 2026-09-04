# 392 — The Calendar Decline Is Reported As The Calendar Refusing It: Elect And Measure The Wording Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the user cancels a calendar-event confirmation card, the on-device brain answers *"Looks like the calendar didn't create the event"* one time in five — a false statement about the user's calendar, on the calendar surface ONLY (5/25 scorable vs 0/58 pooled across reminders and alarms, p = 0.0018, build 3147, 2026-09-01). Owen's route was *"instrument and measure, elect nothing"*; the measurement now exists and is significant. This plan elects ONE treatment — the wording of the tool result the model reads — and measures it on the instrument that already exists, at the trial count that clears the bar the last run missed.

**Architecture:** No new mechanism. `CalendarEventTool.performCreate` returns a string on decline (`DeviceActionTools.swift:981`, *"The user declined — no event was created."*); the reminder and alarm tools return strings of the same shape (`:491`, `:1213`) and are never misattributed. The treatment is a DEBUG cell carrying a different decline string for the calendar tool; the `decline` instrument (`InstrumentRegistry.swift:564-570`, `.autoDecline`) runs control and treatment; `DeclineAttributionScorer` + `score-decline-attribution.py` score them. One string changes in production only after the A/B.

**Tech Stack:** Swift 6.4 / FoundationModels tool results / `InstrumentConductor` / `DeclineAttributionScorer` / Swift Testing.

**Why this is the shape:** the three decline strings differ in one place — the calendar's says *"no event was created"*, and *"the calendar didn't create the event"* is that clause with the calendar as the actor. The reminder's *"no reminder was created"* is never re-read as *"Reminders didn't create it"* (0/32) — a reminder has no obvious agent; a calendar does. The hypothesis is that naming the ACTOR in the tool result removes the ambiguity the model resolves wrongly. It is a hypothesis; the instrument decides, and the entry's own words apply: *"a missed bar is a falsification, not a redefinition."*

## Global Constraints

- **Owen's route stands until he elects.** Decision 1 below is the election; nothing ships to production before the A/B and his read of the number.
- **Tool output states facts; it never instructs the model.** The treatment string names who declined and what did not happen — it does not say "tell the user…" (a tool result that steers prose is a prompt, and #338's guard lives on the other side of that line).
- **The three decline strings stay parallel** after promotion: whichever wording wins on the calendar is applied to reminders and alarms ONLY if their own instrument rows stay 0/n (a change that fixes one surface and moves another is two changes).
- **Denominators are trials AND scorable** (the entry's rule): the bar is on scorable declines, and the trial count is chosen from the measured ~50% conversion.
- **Measurement discipline (#215/#343/#398-A):** `beginTurn()` per trial (the shared loop already does); build, `osVersion`, thermal recorded; the #416-G `--start/--end` window when scoring from an archive (cell names are not unique across instruments).

## Decisions for Owen (one AskUserQuestion round)

1. **Elect the treatment (recommended):** run the A/B below. Alternative: keep measuring only — the finding is filed and significant; the alternative is choosing not to act on it.
2. **The treatment wording (recommended T1):** `"The user cancelled the confirmation card — no event was created and the calendar was never changed."` Alternative T2, parity with the reminder string: `"The user declined — no calendar event was created."` Both can ride one run as two cells if Owen wants the comparison (cost: +60 trials).
3. **Trial count:** 60 per arm on the calendar surface only (recommended — at ~50% scorable conversion that clears n ≥ 30 scorable; the reminder/alarm surfaces are untouched by the treatment and are re-run at 20 as a no-change control). Alternative: the full four-surface instrument at 60 (≈ 4× the phone time).

## Session contract

1. Read `OPEN_ITEMS.md` entry 392 in full: the 08-22 route, the 08-23 instrument (PR #353), the 08-27 and 09-01 runs, the "I didn't decline anything, I was hands off" correction. Pre-register bars 392-T-A..C before Task 1.
2. One short worktree lane (Opus): the cell + tests + gate + merge; then the device run (a §05 runbook card, Debug build, unattended, ~20 min); then the promotion PR if the bar is met, holding for Owen's read of the string that ships.

## File structure

**Modify:**
- `Talaria/Services/Live/DeviceTools/DeviceActionTools.swift` — `CalendarEventTool.performCreate` takes the decline string from a `static let declineResult` (production) and, `#if DEBUG`, from a cell-selected override the same way #196/#200B cells select description text ("two structs, one engine" — the override is a STRING parameter, never a second copy of `performCreate`).
- `Talaria/Services/Live/InstrumentRegistry.swift` + `LocalChatBackend+Battery.swift` — cells `decline-cal-control`, `decline-cal-t1` (and `-t2` if elected), calendar surface only, 60 trials; the existing `decline` instrument unchanged.
- `Talaria/Services/Support/DeclineAttributionScorer.swift` — unchanged unless the treatment wording introduces a phrase the scorer must not read as tool-attribution (Task 1's fixture check).

**Test:** `TalariaTests/CalendarDeclineWordingTests.swift` — the production string is byte-pinned; the cells select the override; the override cannot reach production (Release grep pin).

## Bars (paste into entry 392 before Task 1)

- **392-T-A — the cells (offline).** Control and treatment cells resolve; the calendar tool returns the cell's string on decline; production's string is unchanged and pinned; the treatment strings score `unscorable`-free and user-attributed under `DeclineAttributionScorer` (a treatment wording the scorer itself misreads would poison the run). Mutation: point the treatment cell at the control string → the cell-selection test reds.
- **392-T-B — the number (device).** Calendar surface, 60 trials per cell: control misattribution replicates (≥ 3 of ≥ 30 scorable); treatment ≤ 1 of ≥ 30 scorable; Fisher p < 0.05 treatment vs control; scorable conversion reported per cell. Prediction written first: T1 ≤ 1/30.
- **392-T-C — no collateral (device).** Reminders and alarms at 20 trials each on the promoted wording stay 0/n misattributed; `unscorable` rate within ±10 points of the 09-01 run.
- **392-GATE.**

## Task 1: The cell and the pinned strings (bar 392-T-A)

- [ ] RED tests: production string byte-pinned; cells listed and dispatchable; the override reaches `performCreate` through a parameter with a production default; Release grep pin; the treatment strings run through `DeclineAttributionScorer.verdict` → `.user`.
- [ ] RED → implement → GREEN → mutation → commit → gate → merge.

## Task 2: The run (bars 392-T-B/C)

- [ ] `ota-stage.sh main Debug`; §05 card: `run-instrument.sh --device whoGoesThere --instrument decline-cal --cells decline-cal-control,decline-cal-t1 --trials 60`; same-day collect; `score-decline-attribution.py --start/--end` per cell; the four buckets over one denominator each.

## Task 3: Promotion (only on a met bar)

- [ ] The winning string becomes `declineResult`; the cell is deleted (a cell with no call sites is the trap the deleted `Bareclock` copy fell into); the reminder/alarm strings are left as they are unless 392-T-C says otherwise; PR held for Owen's read of the one sentence that ships.

## Self-review (2026-09-04)

- The three decline strings and their line numbers were read, not recalled (`:491`, `:981`, `:1213`); the calendar-only asymmetry is the entry's own finding across two runs.
- The instrument and scorer exist and were used twice; this plan adds cells, not instruments.
- What this plan does NOT claim: that wording is the cause. It is the cheapest discriminating experiment; a null result (T1 ≈ control) is a real finding that moves the cause off the tool result and onto the model's calendar prior.
