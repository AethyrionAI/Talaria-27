# T27 #200V — confirm #200U by reversing the order it might be an artifact of

**Owen routed this ("do the order reversed confirmation lane with bars first").
Corded, WITH DEBUGGER ATTACHED, classified live from the console bridge.**

## Why this run exists

#200U passed both its pre-registered bars: calendar **7/10 → 10/10**, dead-end
misses **3 → 0**, guards untouched, and the promotable one-string fix landed
exactly on the tool-absent ceiling. It is the best calendar number in the
program.

It is also the exact shape that has fooled this program twice (#200P's perfect
stall cell, #200Q's grab collapse — both evaporated on re-run), and there is now
a second, sharper reason for doubt. **Cells execute sequentially, control first,
and in three consecutive runs the FIRST cell posted the lowest calendar number:**

| run | slot 1 | slot 2 | slot 3 |
|---|---|---|---|
| #200S | armed (pooled 75%) | schemafix (pooled 75%) | schemarollback 9/10 |
| #200T | armed 7/10 | calfix 8/10 | — |
| #200U | armed 7/10 | deadend2 **10/10** | nocontact **10/10** |

That is consistent with real treatment effects **and** with a cold-start /
warm-up / thermal artifact, and the instrument as built cannot tell them apart.
Position cannot easily explain the *qualitative* switch — an identical failed
lookup producing "may I proceed?" in one arm and a create in another — but it can
inflate the size of the win, and the win is what a promotion rests on.

## The two changes, and why they don't confound each other

**1. REVERSED CELL ORDER:** `[.armedNocontact, .armedDeadend2, .armed]`.
Production runs **LAST**. Same three cells as #200U, same n — the only change is
position, which is exactly the variable under test.

**2. A DISCARDED WARM-UP PRELUDE** (Owen's call, and the right one): the prompt
list runs once through the first cell's belt *before* the recorded run begins,
tagged `shape=warmup t=0`, reaped per trial like any other trial, and **excluded
from every count**.

These do not confound each other, because **every bar in this program is a
within-run delta** (#200O). A warm-up shifts all three arms equally — it removes
a systematic advantage that later slots were getting — while the reversal tests
position directly. What the warm-up cannot do is manufacture a difference
*between* arms in the same run.

Implementation note that makes the warm-up safe: it runs before
`batteryRecorder.beginRun(...)`, and every recorder mutator guards on
`run != nil`, so warm-up trials are **recorder-inert** — the recorded run and the
results page are byte-identical to a warm-up-free run. Pinned as such.

## Bars — pre-registered, and this time a PROMOTION condition too

**CO-PRIMARY DISCRIMINATOR — the one that settles the confound.** The control
arm now runs LAST, warm. It must still show **≥ 2 dead-end misses** (#200U's
control showed 3).

- **If control-last shows ZERO dead-end misses, #200U's result is WITHDRAWN** —
  its control's 3 dead-ends were a cold-start artifact, not a disease, and the
  fix does not promote. Written down in advance so it cannot be re-framed later.

**PRIMARY — the effect must survive the reversal.** Fix arm calendar
**≥ control + 2**, OR the control shows ≥ 2 dead-end misses while the fix arm
shows **zero**. The count clause matters because if the warm-up lifts the control
to 9–10/10 the rate has no headroom, and the count still discriminates.

**REPLICATION — the fix arm must show ZERO dead-end misses again**, as it did in
#200U.

**GUARDS:** remind ≥ 9/10 and alarm ≥ 9/10 in **all three** arms. `nocontact`
now runs first, so it absorbs any residual cold-start cost — a remind or alarm
dip in slot 1 is read as instrument, not disease, and is stated as such.

**REPORTED BY POSITION, NOT ONLY BY ARM:** calendar and dead-end counts get
tabulated by slot (1/2/3) as well as by cell, so the position effect stays
visible whichever way it falls.

**PROMOTION CONDITION, PRE-REGISTERED:** if the discriminator, the primary, and
the replication all hold, `ContactsTool.continuesAfterNoMatch` promotes to
`true` in a follow-up commit, with the flag-`false` rollback pinned exactly as
#200S pinned its struct. If any one fails, no promotion and the reason is filed.

Grabs: reported, not gated (#200O's router probe went 200/200). The two
wrong-artifact grabs in #200U — a **calendar event** created for "write a haiku
about sledding", once in the control and once in the fix arm — get counted again
here, since that class is uglier than the grab rate itself.

## Protocol

Unchanged: pins RED before implementation → full unit suite green WITH COUNT and
the compiled path asserted → file-scoped commits, OPEN_ITEMS note separate → PR,
Owen merges → corded deploy **with the debugger attached** → classify from RAW
TEXT → exclusions listed AND adjudicated instrument-vs-disease → reap arithmetic
exact, **with warm-up artifacts stated separately** so the counted-trial
arithmetic still balances → verdict as a dated OPEN_ITEMS note.

**No Apple filing** — standing rule; nothing here is an Apple defect.
