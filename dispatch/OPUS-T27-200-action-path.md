# OPUS-T27-200-ACTION-PATH — measure the action-SUCCESS path, then verify the permission flow

**Executor:** local Claude Code. **Drafted 2026-07-28 (Owen: "You can draft it") from the
OPEN_ITEMS #200 evidence.** Branch `claude/t27-200-action-instrument`, based on the merged
#196 stack (or stacked on #163 if the sweep hasn't happened yet — executor's call from
branch state).

## Why

The 2026-07-28 post-promotion spot check found the #196 confusion INVERTED on the armed
half: "Remind me to test talaria at 4:30pm" fired `readReminders` three times, never
`createReminder`, and the model escalated to flat capability denial that survived BOTH a
permission grant and its own offer to create ("Yes please" → no tool call). No battery has
ever measured this: the auto-decline contract made inappropriate grabs measurable, but
"does an APPROPRIATE create go through" has no denominator. Measurement before fixes —
that discipline is why #196 closed; #200 gets the same treatment.

## Part 1 — confirmation-gate auto-accept + confirmation capture

1. `ToolConfirmationCenter` gets `autoAcceptForBattery` alongside `autoDeclineForBattery`
   (DEBUG, mutually exclusive, both cleared at run end). Auto-accept means REAL EventKit
   writes during a battery — so every battery-created object must be tagged and reaped:
   action-tool titles created under auto-accept carry a `[T27-battery]` marker, and the
   run teardown deletes every matching reminder/event/alarm before "DONE" is emitted. The
   phone ends the run clean. If reaping proves flaky on 27b4, fall back to a dry-run seam
   (execute to the confirmation boundary, report a MARKED synthetic result) — but real
   create + reap is the fidelity default.
2. Confirmation outcomes become capture data: a `battery: confirm=accepted|declined|none`
   line per action-tool invocation via the existing `batteryTrialTag` path, and a matching
   field on `BatteryTrialRecord` (store version bump; old run JSONs must still decode —
   optional field). The results page shows it in the trial drill-down.

## Part 2 — the action-path battery

New DEBUG battery variant (own button, "Action battery n=20", sharing the batteryRunning
guard): **single-turn create prompts, armed production cell, auto-ACCEPT armed.**

- Prompt set (one cell each, n=20): `remind` = "Remind me to test Talaria at 4:30pm",
  `alarm` = "Set an alarm for 6:30", `calendar` = "Put lunch with Sam on my calendar
  Friday at noon". The reminder prompt is the observed failure; alarm/calendar establish
  whether the disease is reminder-specific or action-general (the router probe measured
  all three as correctly ROUTED — this measures what the armed session does next).
- Per-trial classification data: which tool(s) fired (wrong-tool `readReminders`
  substitution is a primary count), whether a confirmation was requested, the outcome,
  and the FULL reply text (honest-confirmation vs fabricated-action vs denial — #199's
  fabrication gets a real denominator out of this too).
- Protocol: run with Reminders/Calendar permissions GRANTED (the observed failure
  post-dates the grant; that is the state to reproduce). Single-turn only in this
  battery; the multi-turn absorbing state ("Yes please" after an offer) is a SECOND
  instrument, not built until single-turn numbers say where the failure concentrates.

## Part 3 — permission-flow verify (#31 check)

Read `ReminderReadTool` / `ReminderCreateTool` (+ calendar/alarm) EventKit authorization:
first use must REQUEST access contextually (#31), not report absence and stop — the spot
check's first turn reported missing permission with no iOS prompt. If the request call is
missing or 27b4 changed EventKit's full-access semantics, fix file-scoped WITH a pin.
Device-verify needs a permission reset (delete app or Settings toggle) — coordinate with
Owen, since it costs a re-pair.

## Rules

House rules apply: file-scoped commits, merge commits only, OPEN_ITEMS notes separate,
suite green with stated count, evidence scope + build ID in the PR, results classified
from RAW TEXT with rates (no single-shot verdicts), ERROR trials excluded and listed.
No fixes to tool descriptions or instructions in THIS lane — instrument, measure, file
the table in #200, and route treatments at the verdict desk. Deploy via
`ota-stage.sh <branch> Debug`; capture via the results page (battery → export → paste),
which the #196 endgame proved end to end.
