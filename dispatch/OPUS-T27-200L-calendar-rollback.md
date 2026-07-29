# T27 #200L — the calendar lane: is the promoted clause the cost, or is it Sam?

**Owen routed this after the #200K verdict. Off-LAN: OTA Debug staging,
classification from the run-JSON export.**

## Why this run exists

#200K's re-verify was a split decision. The promoted card clause is holding on
its own axis — **pooled remind 18/20 (90%), the best in the program's history,
alarm 20/20, and ZERO card narration in 120 trials** — but **pooled calendar
came in at 8/18 (44%)**, the worst recorded, and it failed its re-verify bar.

Two hypotheses, and they are cheap to separate in one run:

1. **The promoted clause costs calendar.** Post-promotion calendar is 22/37
   (59%); pre-promotion controls were 21/30 (70%). Fisher p≈0.4 — NOT
   significant, and swamped by a control that has read 7/10, 4/10, 10/10 across
   runs — but the direction is unfavorable and #200J's own A/B (control 10/10 vs
   treated 8/10) points the same way. A suspicion this cheap to test should not
   be carried on trend lines.
2. **Calendar is sick for its own reasons, and always was.** In #200K, **every
   single classified calendar miss across all three cells — 14 of 14 — was the
   "Sam" identity dead-end**: `lookupContact`/`searchConversations`/
   `searchPlaces` on "Sam", nothing found, then a question instead of a create.
   All three excluded trials were the same hunt, including the D4 malformed-args
   specimen (`{"term":"Sam"Sam"}<ctrl43>`).

## Cells

`calendarBatteryCells = [.armed, .armedCardrollback, .armedSpiralfix]` × 4
prompts × n=10 = **120 trials**. Diagnostics → "Calendar battery n=10 (120)".

- **`.armed`** — promoted production (destall + find-first + card clause).
- **`.armedCardrollback`** — NEW, and the first cell in this program that
  measures a promoted clause by REMOVING it. It is exactly the pinned rollback:
  production with `includeCardNarrationClause: false`, byte-identical to the
  pre-#200K text. Pinned by `cardrollbackCellIsExactlyThePinnedRollbackText`.
- **`.armedSpiralfix`** — the #200I event-scoped carve-out, unchanged and still
  flag-off in production. It cut hunt calls 56% and beat its control by +2 on
  calendar; #200K says the disease it targets is now responsible for 100% of
  calendar misses.

## Bars — K-guard form throughout

**On hypothesis 1 (rollback vs production):** if rollback calendar exceeds
production calendar by **more than 4/10**, the clause is implicated and the
rollback decision goes to Owen with the remind cost stated alongside (the clause
bought +3 remind in #200J and 90% pooled in #200K — a calendar win would have to
be weighed against that, NOT taken automatically). If the two are within 4, the
clause is exonerated and hypothesis 2 owns the calendar problem.

**On hypothesis 2 (spiralfix vs production):** promote the carve-out if calendar
≥ production + 3 **and** the Sam dead-end drops to ≤ half of production's count,
with remind not worse than production by more than 3, alarm 10/10, and grabs not
worse than production by more than 3 (#200I's bleed check, which the v2 reword
cleared once already).

**Watch, not a bar:** grabs are 75% pooled and rising (4/8 → 4/10 → 7/10 →
15/20) as remind improves. If any cell here shows grabs ≥9/10 again, the grab
lane stops being a stretch goal.

## Protocol

Unchanged: auto-accept gate, `[T27-battery]` marker, per-trial reap, 35s
guillotine, foreground + on power, hands off. Rates from RAW TEXT; a create =
`confirm=accepted` + its artifact; ERROR/TIMEOUT excluded and listed; reap
arithmetic exact (six consecutive runs).

Deploy: `scripts/mac/ota-stage.sh claude/t27-200l-calendar-rollback Debug`,
install from Safari at `https://owens-mac-mini.tail5663a6.ts.net`, export the
run JSON from Battery results.
