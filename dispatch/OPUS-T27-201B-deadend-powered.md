# T27 #201B — the contact dead-end at n=40, with a gate derived from arithmetic

**Owen routed this ("Lets do n=40"). Corded, debugger attached, classified by
`scripts/classify-battery-run.py`. Bars written BEFORE the run — and this time the
numbers in them come from a power calculation, not from judgement.**

## Why this run exists

#201 filed **INCONCLUSIVE** at n=20: treatment calendar **20/20 with zero
dead-ends** against production **17/20 with 3**, both comparisons **p≈0.23**. The
evaluability gate demanded ≥4/20 control dead-ends and got 3.

**The gate was mis-specified and that was my error.** Production's warm dead-end
rate pooled **5/30 ≈ 16.7%**; over 20 trials that predicts **3.3 events**, so a ≥4
gate required the disease to show up above its own expected rate. Third floor in
three lanes to land one short. This dispatch fixes the method, not the hypothesis.

## The arithmetic the bars come from

Base rate **≈16.7%** dead-end misses on the calendar prompt in warm production.

| n per arm | expected control events | 0-vs-k Fisher p if treatment stays 0 |
|---|---|---|
| 20 | 3.3 | ≈0.23 — cannot conclude (this is #201) |
| **40** | **6.7** | **≈0.02** — conclusive at the usual threshold |

So **n=40**: 2 cells × 4 prompts × 40 = **320 counted trials + 4 discarded
warm-up**, ~25 minutes at the observed ~4s/trial.

## Bars

**EVALUABILITY GATE (derived, not guessed):** the control must show **≥3
dead-end misses out of 40**. Expected is 6.7; a floor of 3 is comfortably below
expectation, so this gate can only fail if the disease genuinely is not present at
the rate three prior runs measured. **If it fails, the hypothesis CLOSES** — that
would be four warm samples disagreeing with the first three, which is real evidence
and not an arithmetic accident.

**PRIMARY (pre-registered as a test, not a threshold):** Fisher exact on dead-end
counts, treatment vs control, **one-sided, α=0.05**. Report the p-value whatever it
is. **Pass = p < 0.05 AND treatment count ≤ 1/40.**

**SECONDARY (reported, not a win condition):** calendar create rate. Treatment
**≥ control − 2** — a "fix" that removes the ask by declining to create would be a
regression, and this is what catches it.

**GUARDS:** remind **≥ 36/40** and alarm **≥ 36/40** in BOTH arms (90%). Grabs
reported, not gated.

## The confound this run introduces, stated in advance

**320 trials is long enough for thermal drift to matter, and it now works AGAINST
production** — production runs LAST, so a hot device penalises the control and
could manufacture a treatment win. That is the opposite direction from #200V's
cold-start bias, which is why it needs saying out loud.

Two mitigations, both in this lane:

1. **Thermal state is now EMITTED at every cell boundary** (`battery: THERMAL …`),
   so drift is measurable rather than assumed. If the control's cell starts at
   `serious` or `critical` while the treatment's started at `nominal`, the
   comparison is compromised and the verdict says so.
2. **PRE-REGISTERED: a pass here requires an order-REVERSED confirmation** before
   promotion — production first, treatment last — exactly as #200V tested the
   position confound. One clean run does not promote.

## Promotion condition

If the gate holds, the primary passes, the guards hold, **and** thermal state is
comparable across cells, then `ContactsTool.continuesAfterNoMatch` earns the
order-reversed confirmation run — **not** the promotion itself. Promotion follows a
second clean run, as it did for every seam that shipped.

**No Apple filing** — standing rule.
