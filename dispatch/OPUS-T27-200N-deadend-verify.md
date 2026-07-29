# T27 #200N — the v3 confirmation A/B

**Owen routed the merge of #177/#178 and this run. Off-LAN: OTA Debug staging,
run-JSON export.**

## Why a second run instead of a promotion

#200M's v3 carve-out passed **5 of its 6 pre-set bars** and missed one — remind
"within 1 of production" — by a **single trial** (8/10 vs 10/10). Everything
about that miss argues it is noise:

- both misses are the **conserved stall** ("Should it have a due date?", "a
  specific date and time… also a specific list?"), the hydra #200K documented,
  not anything the carve-out introduced;
- **8/10 is inside production's own historical range** (production remind has
  read 8/10, 10/10, 10/10, 10/10 across recent runs);
- v3's calendar win came with its two misses being **non-Sam** failures, while
  production's five were all Sam dead-ends.

And that is exactly why it gets a second run rather than a judgement call. The
bar was set at "within 1" before the data existed precisely so this decision
would not be made by eyeball afterwards. One more measurement costs 80 trials
and buys a promotion resting on two independent runs.

**The baseline has finally held still**: production calendar read 5/10 in both
#200L and #200M, so a repeat measurement means something for once — unlike
#200J, where the control landed on its ceiling and made the guard unreachable.

## Cells

`deadendVerifyBatteryCells = [.armed, .armedDeadendfix]` × 4 prompts × n=10 =
**80 trials**. Diagnostics → "Deadend verify n=10 (80)".

**v2 is deliberately absent.** #200M found it resurrects find-first — three of
its four remind misses called `readReminders` first, including the read-for-
create substitution ("I don't see any existing reminders") that #200G killed.
It is retired, not re-measured.

## Bars — promote v3 if ALL hold

- remind **≥ 9/10** (the bar it missed; production is at ceiling, so this is the
  real question)
- calendar **≥ production + 3** (it was +3 in #200M against the same 5/10)
- Sam dead-end misses **≤ half** production's
- grabs **not worse than production by more than 2**
- alarm **10/10**
- disease-attributable TIMEOUTs count as failures; only instrument errors are
  excluded (the #200L refinement)

If all hold, promote v3 the way #200D/#200G/#200K went: default TRUE, pinned
byte-identical rollback, pins flipped RED-first, and the promoted cell becomes
the pooled re-verify for the run after. If remind misses again, the carve-out
does cost reminders and the calendar/remind trade goes back to Owen with two
runs behind it.

## Protocol

Unchanged: auto-accept gate, `[T27-battery]` marker, per-trial reap, 35s
guillotine, foreground + on power, hands off. Rates from RAW TEXT; a create =
`confirm=accepted` + its artifact; exclusions listed AND adjudicated; reap
arithmetic exact (eight consecutive runs).

Deploy: `scripts/mac/ota-stage.sh claude/t27-200n-deadend-verify Debug`,
install from Safari at `https://owens-mac-mini.tail5663a6.ts.net`.
