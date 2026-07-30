# T27 #200Z — the calendar promotion against its own rollback

**Owen routed this ("load it on my phone and i'll run the test"). Corded,
debugger attached. Bars written BEFORE the run, as always.**

## What this settles

#200X promoted `CalendarEventTool`'s `durationMinutes`/`location` to optional on
evidence that was strong but not clean: #200W's `searchPlaces` clause was
**unevaluable** (control fired it 1/10, below the pre-registered ≥3/10 floor), so
the gate as written was not met and the promotion went through on Owen's routing
with that stated.

This run judges the promoted tool against **the exact thing it replaced**, in one
run — the #200S re-verify shape, which is what made the reminder promotion
convincing.

`calRollbackVerifyBatteryCells = [.armedCalrollback, .armed]` × 4 prompts × n=10
= **80 counted trials + 4 discarded warm-up**. Production runs **LAST**: any
residual position advantage that survives the warm-up accrues to production,
which makes it harder — not easier — to claim the promotion won.

Both arms differ in **exactly two field types**. Same name, same description,
same `@Guide` texts, same create engine.

## Bars

**PRIMARY — invented locations, the measure that carries the product harm.** The
prompt ("Put lunch with Sam on my calendar Friday at noon") names no place, so any
location in a create's reply was invented by the model.

- production (optional fields): **≤ 1/10**
- rollback (required fields): **≥ 4/10**

Both must hold. #200W measured 0 and 5 respectively; #200T measured 0 and (by
reply text) several. **If the ROLLBACK does not invent locations, the promotion's
premise is wrong and #200X should be reverted** — declared here, in advance.

**PRIMARY 2 — the spiral.** `currentLocation` on calendar trials: production
**≤ 3/10** AND rollback **≥ 6/10** (#200W: 0 vs 7). `searchPlaces` is **reported
only** this run — it has now been 6/10, 1/10 and 1/10 across three runs, so at
n=10 it cannot carry a bar, and pretending otherwise is what #200W got wrong.

**GUARDS:**

- calendar creates: production **≥ rollback − 2** (no regression; the rate is
  reported, not a win condition — production sits near its 9/10 ceiling)
- remind **≥ 9/10** and alarm **≥ 9/10** in BOTH arms
- **dead-end misses are counted in both arms** and read as disease, not noise:
  #200W showed them warm in both arms (production 2/10, rollback-side 1/10),
  which corrected #200V's zero. This run is a third warm sample of that count.
- grabs reported, not gated

**WEDGE WATCH:** this is the first run with `DeviceToolTimeout` live. If a
`searchConversations` wedge occurs, the expected signature is the tool's own
"timed out after 12s" text in the reply and the trial COMPLETING — not a silent
2.5-minute stall. A stall recurring anyway means the timeout is on the wrong
await and that gets filed as such.

**CLASSIFICATION:** `scripts/classify-battery-run.py` on the exported run JSON —
counts generated, not hand-tallied. The console is a convenience; the run JSON is
the system of record (#200W's lesson).

**REVERT CONDITION, pre-registered:** if the rollback arm does NOT invent
locations and does NOT spiral, #200X's premise fails and the promotion is
reverted rather than defended.
