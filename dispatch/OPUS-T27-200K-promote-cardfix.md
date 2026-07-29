# T27 #200K — promote the card clause, and take the next remind disease

**Two things in one build, because one run can measure both. Owen routed this
("build the promotion and move into the next"). Off-LAN: OTA Debug staging,
classification from the run-JSON export.**

## Part 1 — the promotion

#200J's clause killed its specimen outright: card narration occurred **3× in
control and ZERO times anywhere in the treatment cell's 40 trials**, and remind
went **5/10 → 8/10**, the largest single-seam gain since the #200D promotion.
Four of five delta-bars passed; the fifth (calendar ≥ control) failed 8 vs 10
against a control that hit its ceiling, and BOTH treatment calendar misses were
the untreated "Sam" lookup spiral — a named different disease, not the clause.

`includeCardNarrationClause` flips to **default TRUE**. Explicit `false` is the
pinned byte-identical rollback
(`cardNarrationClauseIsProductionDefaultAndRemovable`). Production instructions
are now: base + destall (#200D) + find-first carve-out (#200G) + card clause
(#200K).

Three neighbouring pins move with it, because the promoted clause now sits
between the find-first carve-out and honesty-and-recovery: the find-first
production seam, its rollback seam, and #200H's spiral seam. Each was watched
RED before the flip.

## Part 2 — datefix, the residual remind disease

#200J's two remaining treatment remind misses were both zero-tool date
interrogations:

> Could you clarify the due date for this reminder?
> I can set a reminder for that. Would you like to choose a specific date or
> keep it open for today?

This is NOT card narration and NOT the optional-field stall the #200D clause
already licenses: that clause covers empty OPTIONAL fields, while a bare clock
time ("4:30pm") reads to the planner as an AMBIGUOUS REQUIRED one. So the
treatment names the resolution rather than the permission:

> A time with no day means the next time that clock time comes around — never
> ask which day.

`includeDayDefaultClause`, default FALSE, seated after the promoted card clause.

## The battery — one run, both jobs

`datefixBatteryCells = [.armed, .armedCardfix, .armedDatefix]` × 4 prompts ×
n=10 = **120 trials**. Diagnostics → "Datefix battery n=10 (120)".

- `armed` and `armed-cardfix` are now IDENTICAL (the cell passes the promoted
  flag explicitly — the #200G findfix precedent), so they **pool as the
  production re-verify at n=20/prompt**. That is what settles #200J's calendar
  guard: control calendar has read 7/10, 4/10, 10/10 across three runs, and
  n=20 is the best estimate this program can buy.
- `armed-datefix` measures the new treatment against that pooled control in the
  same run.

## Bars

**Re-verify half (pooled n=20):** remind ≥ 12/20 (the #200J treatment rate held),
alarm 20/20, calendar ≥ 12/20 (i.e. the 8-vs-10 guard trip does NOT reproduce as
a real deficit), zero card-narration specimens in 40 trials.

**Datefix half (vs the pooled control):** remind ≥ pooled control rate + 15
points with zero-tool date interrogations at half or fewer; alarm 10/10;
calendar and grabs not worse than pooled control by more than 3 (the K-guard
form — #200J proved a bare "≥ control" has no headroom against a ceiling).

## Protocol

Unchanged: auto-accept gate, `[T27-battery]` marker, per-trial reap, 35s
guillotine, foreground + on power, hands off. Rates from RAW TEXT; a create =
`confirm=accepted` + its artifact; ERROR/TIMEOUT excluded and listed; reap
arithmetic exact (five consecutive runs).

Deploy: `scripts/mac/ota-stage.sh claude/t27-200k-promote-cardfix Debug`,
install from Safari at `https://owens-mac-mini.tail5663a6.ts.net`. Export the
run JSON from Battery results.

**Stacking note:** this branch is stacked on `claude/t27-200j-cardfix` (PR #175),
which carries the cell and the verdict. Merge #175 first, then this one.
