# T27 #200M — carve-out v3: say only what the mechanism earned

**Owen routed the iteration over promoting v2 ("Lets iterate"). Off-LAN: OTA
Debug staging, run-JSON export.**

## What #200L actually showed

The v2 carve-out took calendar to 8/8 (8/10 counting hunt casualties) against
production's 5/10 and zeroed the Sam dead-end — 5 misses in production, 0 in the
treated cell. But the mechanism is narrower than the sentence:

- identity-hunt calls fell only **23 → 16 (−30%)**. The hunting continues.
- one treated trial ran away to **20 tool calls, 17 consecutive
  `searchConversations`**, and timed out. The runaway is not prevented.
- what went to zero is the **dead END** — "I couldn't find a contact named Sam,
  could you clarify?" instead of creating.

**v2 converts hunt→ask into hunt→create.** It does not stop the search, and
nothing in it bounds the search.

Meanwhile the bleed is measured twice and consistent (#200I + #200L pooled,
each against its own same-run control): calendar **+33 points**, remind
**−20**, grabs **−15 worse**. Remind at 90% is the program's hardest-won
number; paying 20 points of it for calendar is a trade, not a win.

## v3 — one sentence, and only the part that earned its place

> If you can't identify a person named in an event, that's fine — create the
> event with the name exactly as the user gave it.

Two things v2 carried are deliberately DROPPED, and the drop is pinned:

1. **The search prohibition** ("never search contacts, conversations, or places
   to identify them before creating the event"). It is the part that plausibly
   moved the reminder path's weight, and #200L shows it isn't what produces the
   win — the hunts happen anyway.
2. **The location sentence** ("only include an event location the user
   themselves gave"). Unearned: across #200J, #200K and #200L **every** accepted
   event was a bare title with no location bound at all. There is no misbinding
   left for it to prevent.

`deadEndCarveoutIsOffByDefaultAndSaysOnlyWhatItMeasured` pins both absences, so
a future edit cannot quietly smuggle them back and turn this into a re-run of
v2 wearing a new name.

## Cells

`deadendBatteryCells = [.armed, .armedDeadendfix, .armedSpiralfix]` × 4 prompts
× n=10 = **120 trials**. Diagnostics → "Deadend battery n=10 (120)".

v2 runs IN THIS RUN rather than being compared to a remembered number — the
#200I lesson about between-run drift, applied to treatments instead of controls.

## Bars — K-guard form, set before the data exists

v3 promotes only if **all** hold:

- calendar **≥ production + 3**, counting hunt casualties as failures (the
  #200L exclusion refinement — a TIMEOUT mid-spiral is the disease, not the
  instrument, and only instrument errors are excluded)
- Sam dead-end misses **≤ half** production's
- remind **within 1 of production** — this is the entire point of v3; v2's −3
  is the thing being fixed, so "not much worse" is not good enough
- grabs **not worse than production by more than 2**
- alarm **10/10**
- **vs v2 in the same run:** remind strictly greater than v2's, and calendar
  no more than 2 below v2's

If v3 clears and v2 doesn't, promote v3. If both clear, promote v3 (fewer
words, same win). If neither clears, the calendar/remind trade goes back to
Owen with two runs of evidence behind it and nothing is promoted on hope.

## Protocol

Unchanged: auto-accept gate, `[T27-battery]` marker, per-trial reap, 35s
guillotine, foreground + on power, hands off. Rates from RAW TEXT; a create =
`confirm=accepted` + its artifact; ERROR/TIMEOUT listed AND adjudicated
instrument-vs-disease; reap arithmetic exact (seven consecutive runs).

Deploy: `scripts/mac/ota-stage.sh claude/t27-200m-deadend-v3 Debug`, install
from Safari at `https://owens-mac-mini.tail5663a6.ts.net`.

**Stacking note:** branched from `claude/t27-200l-calendar-rollback` (PR #177).
Merge #177 first, then this.
