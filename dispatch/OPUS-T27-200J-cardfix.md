# T27 #200J — the narrated confirmation card

**The #200I follow-up. Off-LAN lane: OTA Debug staging, classification from
the run-JSON export.**

## The specimen

#200I's largest single failure bucket, across BOTH cells, was 10 trials that
called NO tool at all and instead typed the confirmation card out in prose:

> Here's the confirmation for your reminder:
> - **Title:** Test Talaria
> - **Due:** 2026-07-30T16:30 (4:30 PM)
> - **List:** Default list
>
> Would you like to proceed?

Nine of those ten were the remind misses (4 control, 5 treatment); the tenth
was a calendar miss ("Shall I proceed?"). It is cell-independent — the spiral
carve-out neither caused it nor touched it — and it accounts for **9 of the 19
non-creates** in the run.

The irony is the point: Talaria SHOWS a real confirmation card on every action
tool, and the production instructions already say so — "Every action tool shows
the user a confirmation card first; if they decline, accept it gracefully." The
model knows the card exists and reproduces it in text anyway. Knowing about the
card is not the same as being told not to impersonate it. The existing sentence
describes; it never forbids.

## Treatment

One sentence, flag-gated (`includeCardNarrationClause`, default FALSE), seated
after the (off) spiral carve-out and before honesty-and-recovery:

> The confirmation card is shown automatically when you call an action tool —
> never write the card out, list the details back for approval, or ask whether
> to proceed; make the call and let the card do the asking.

It names the three observed forms of the impersonation (writing the card,
listing details back, asking to proceed) and ends by naming the tool call as
the way to ask — the destination-shaped phrasing that made the #200D and #200G
clauses work.

## Cells and battery

`cardfixBatteryCells = [.armed, .armedCardfix]` × 4 prompts × n=10 = **80
trials**. Diagnostics → "Cardfix battery n=10 (80)". Belt is production
identity; the sole seam is the instructions.

## The bar — DELTA-based, and this is the #200I lesson

#200I set absolute bars and they were unreachable for a reason that had nothing
to do with the treatment: the control's own calendar rate swung 7/10 → 4/10
between runs on byte-identical production text, a bigger move than the effect
under test. Both runs showed the treatment beating its own control by exactly
+2 on calendar. **From here every bar is stated against the SAME RUN's control.**

Promote only if all of:

- remind creates **≥ control + 3**
- zero-tool narration trials in the treatment cell **≤ half** the control cell's
- alarm **10/10** (the ceiling has never regressed; a regression here kills it)
- calendar **≥ control** and grabs **≤ control + 1** (no bleed, the #200H lesson)

Miss any one → no promotion, verdict filed, next lane.

## Protocol

Auto-accept gate, `[T27-battery]` marker, per-trial reap, 35s guillotine,
foreground + on power, hands off. Rates from RAW TEXT; a create =
`confirm=accepted` + its artifact; ERROR/TIMEOUT excluded and listed; reap
arithmetic exact (four consecutive runs now).

Deploy: `scripts/mac/ota-stage.sh claude/t27-200j-cardfix Debug` (Debug is
mandatory — the battery surface is `#if DEBUG`), install from Safari at
`https://owens-mac-mini.tail5663a6.ts.net`. Export: Battery results → the run →
"Copy raw run" (or share the run JSON, which is what #200I was classified from).
