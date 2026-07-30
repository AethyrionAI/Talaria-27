# T27 #200W — warm-up by default, and the calendar location finding measured properly

**Owen routed this ("make the warm up the default for future batteries. and the
rest. Merge em and lets continue"). Corded, debugger attached, console-bridge
classification.**

## Part 1 — the warm-up becomes the default

#200V established the cold-start artifact with a within-run measurement: the same
production configuration scored **calendar 7/10 running first and cold** (#200T,
#200U) and **9/10 running last and warm**, with the "Sam" dead-end going **3/10 →
0/10**. The warm-up flattened the position gradient it was built to remove —
calendar by slot **9, 10, 9** against #200U's **7, 10, 10**.

So `warmup` flips to `true` by default. Every future battery pays the cold-start
cost outside its counts. The flag stays, so a run can still opt out and reproduce
a pre-#200V measurement exactly.

**Every pre-#200V control number is cold-biased and is to be read that way.**
That is filed in the #200V note; this lane makes the instrument match it.

## Part 2 — the calendar location finding, promoted from exploratory to measured

#200T found something big and, being post hoc, refused to claim it: making
`location` optional collapsed the location-lookup spiral —

- `currentLocation` on calendar trials: **9/10 → 2/9**
- `searchPlaces` on calendar trials: **6/10 → 0/9**

and it changed the ARTIFACTS. The control filled the required `location` field by
geolocating and stamping a place on a lunch the user never located — *"Saucier,
MS"*, and twice the home street address **"19200 Crestwick St"**. Treatment
creates carried none.

#200V then made this the live question: warm production's ONLY calendar miss was
card narration reading ***"Location: Not specified"*** — the required field
surfacing again, in the one remaining failure.

## Why the RATE cannot be the primary bar this time, stated up front

Warm production calendar is **~9/10**. A +2 bar would need 11/10, and the
ceiling clause ("10/10 with control ≤ 9/10") is only a **+1 delta at n=10** —
indistinguishable from noise. Pretending otherwise would be the #200P mistake
with extra steps.

So the rate is **reported, and explicitly NOT a promotion criterion here.** The
primary bars are the spiral and artifact counts, which have large effects, no
ceiling, and per-trial resolution.

## Cells

`calfixWarmBatteryCells = [.armedCalfix, .armed]` × 4 prompts × n=10 = **80
counted trials + 4 warm-up**. Production runs **LAST** — now the standing
convention, and the conservative direction: if any residual position advantage
survives the warm-up it accrues to the CONTROL, making it harder for the
treatment to win.

## Bars — pre-registered, spiral-first

**PRIMARY 1 — the location spiral.** On calendar trials:

- `currentLocation` calls: treatment **≤ 3/10** AND control **≥ 6/10**
- `searchPlaces` calls: treatment **≤ 1/10** AND control **≥ 3/10**

Both must hold. If the CONTROL does not spiral (below its floor), the lane is
**INCONCLUSIVE — no disease to fix** — declared in advance.

**PRIMARY 2 — invented locations in the artifacts.** Count creates whose reply
cites a location the prompt never supplied ("Put lunch with Sam on my calendar
Friday at noon" names none). Treatment **≤ 1/10**, control **≥ 4/10**.

**GUARDS:**

- calendar rate: treatment **≥ control − 2** (no regression; reported, not a win
  condition)
- remind **≥ 9/10** and alarm **≥ 9/10** in BOTH arms
- grabs reported, not gated

**PROMOTION CONDITION, pre-registered:** if PRIMARY 1 and PRIMARY 2 both hold and
no guard breaks, `CalendarEventTool`'s `durationMinutes`/`location` optionality
promotes to production — the #200T treatment struct becomes the shipping tool and
the required-field version becomes the pinned rollback cell, exactly as #200S did
for reminders. If either primary fails, no promotion and the reason is filed.

**REPRODUCTION:** #200V is the reason this bar exists at all. A pass here is a
first warm measurement of an effect first seen post hoc — so promotion also
requires that the effect be **large** (the bars above are set at roughly half the
#200T effect size), not merely directionally right.

## Not in this lane

The #200K card-narration clause and #200O dead-end carve-out are owed warm
re-verifications (#200V), and warm production's residual card-narration miss
belongs to that work. One variable at a time.

## Protocol

Pins RED first → full unit suite green WITH COUNT and the compiled path asserted
→ file-scoped commits, OPEN_ITEMS separate → PR, Owen merges → corded deploy with
the debugger attached → classify from RAW TEXT → exclusions listed AND
adjudicated → reap arithmetic exact, warm-up stated separately → verdict as a
dated OPEN_ITEMS note.

**No Apple filing** — standing rule.
