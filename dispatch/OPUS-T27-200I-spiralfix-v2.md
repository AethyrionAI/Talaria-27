# T27 #200I — spiralfix v2, event-scoped (the #200H follow-up)

**Lane 1 of `planning/WEEK-PLAN-2026-07-29.md`. Owen is off-LAN (at work),
so this one deploys OTA, not corded — no console, classification comes from
the results page export.**

## What #200H proved, and the one word that cost it

The lookup-spiral carve-out worked on the disease it was aimed at:

| cell | remind | alarm | calendar | grabs |
|---|---|---|---|---|
| armed (control) | 6/10 | 10/10 | 7/10 | 4/8 |
| **armedSpiralfix (v1)** | 4/10 | 10/10 | **9/10** | 8/10 |

Calendar 9/10 with zero casualties is the best calendar number the program
has ever recorded, and the identity hunts that produced every excluded
trial in #200F/#200G ended in creates instead of spirals. But the same
sentence moved two intents it was never aimed at: grabs doubled and remind
sagged below its band. The v1 text named reminders —

> "A person's name in an event **or reminder** is just part of the title …"

— and a sentence that names reminders reads, to the planner, as guidance
about reminders. That is the hypothesis: the bleed is the scope of the
noun, not the idea.

## Treatment

Reword sentence 1 event-scoped; sentence 2 unchanged. The flag is off by
default and unpromoted, so the text is free to change — the pin moves with
it (`lookupSpiralCarveoutIsOffByDefaultAndSitsAfterTheFindFirstCarveout`).

- v2 sentence 1: "A person's name in an event title is just part of the
  title — never search contacts, conversations, or places to identify them
  before creating the event."
- unchanged sentence 2: "Only include an event location the user
  themselves gave; a place search result is never the location."

"before creating the event" also states the create as the destination
rather than only forbidding the search — the same shape that made the
#200D destall clause and the #200G find-first carve-out work.

## Cells and battery

`spiralfixBatteryCells = [.armed, .armedSpiralfix]` × 4 prompts × n=10 =
**80 trials**. Diagnostics → "Spiralfix battery n=10 (80)".

Strikefix is PARKED, not dropped: #200H never produced a same-tool repeat
in-cell (no third strike ever came due) and its `@SessionProperty`
dictionary emits were anomalous (doubled at #1, never #2). Re-running it
would spend a third of the trials on a treatment that cannot engage. It
comes back only behind the instrument probe (week plan Lane 3), and the
3-cell `runSpiralBattery` stays on the picker for that.

## The bar (set BEFORE the run, per protocol)

The treatment promotes only if it keeps its win and gives back the bleed:

- calendar **≥8/10 with zero casualties** (keeps the v1 win)
- remind **≥6/10** (back in band — v1's 4/10 is the sag being fixed)
- grabs **≤ control** (v1's 8/10 vs 4/8 is the bleed being fixed)
- misbind-clean creates **> control** (no Sam's Club, no own-address
  locations — the second sentence's job)

Miss any one → no promotion, verdict filed, next lane.

## Protocol (unchanged except the deploy)

Auto-accept gate, `[T27-battery]` marker, per-trial reap, 35s guillotine,
foreground + corded-to-power, hands off (backgrounding kills the run).
Rates from RAW TEXT; a create = `confirm=accepted` + its artifact;
ERROR/TIMEOUT excluded and listed; reap arithmetic exact.

**Off-LAN deploy:** `scripts/mac/ota-stage.sh claude/t27-200i-spiralfix-v2
Debug` (Debug is mandatory — the whole battery surface is `#if DEBUG`),
install from Safari at `https://owens-mac-mini.tail5663a6.ts.net`.

**Off-LAN classification:** Diagnostics → Battery results → the run →
"Copy raw run" → paste. That export carries route/tool/`confirm=`/raw text
per trial and the run's REAP summary, which is everything classification
needs; the per-trial REAP-TRIAL lines live in the capture log ("Share
capture log") if the arithmetic needs a second source.
