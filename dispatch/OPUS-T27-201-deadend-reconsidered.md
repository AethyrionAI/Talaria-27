# T27 #201 — the contact dead-end, reconsidered at n=20

**Owen routed this ("Agreed on U's reconsideration"). Corded, debugger attached,
classified by `scripts/classify-battery-run.py`. Bars written BEFORE the run.**

## Why #200V's withdrawal no longer holds

#200V withdrew #200U's fix on one clause: warm production showed **ZERO**
dead-end misses, so its 3/10 cold control looked like a cold-start artifact.
Three warm samples later that reading is dead:

| run | warm production dead-end misses (calendar) |
|---|---|
| #200V | 0/10 |
| #200W | 2/10 |
| #200Z | 3/10 |

The disease is present and, if anything, trending up. **#200V's zero was itself a
small-sample artifact** — the exact error it was written to catch, one level up.
That is worth stating plainly: the withdrawal was correct procedure on the
evidence available, and the evidence has since changed.

## What is being measured, and why n doubles

The fix is unchanged and still in the tree, defaulting off:
`ContactsTool.continuesAfterNoMatch` adds continuation to the not-found RESULT —
*"This does not block anything — if the name came from a request to create
something, continue with the name exactly as the user gave it."*

**The primary is a COUNT, not a rate.** At n=10 a 2-or-3 event count cannot
support a bar; #200W and #200Z both proved that a rate near its ceiling and a
count in single digits are the wrong instruments at that size. So **n=20**: 2
cells × 4 prompts × 20 = **160 counted trials + 4 discarded warm-up**, roughly
12 minutes at the observed ~4s/trial.

`deadendReconsiderBatteryCells = [.armedDeadend2, .armed]` — production **LAST**,
the standing convention and the conservative direction.

**Arm B is deliberately absent.** #200U's tool-removal probe caused the model to
flee into `searchConversations` six times on one query and get guillotined —
removing a read tool relocates the spiral rather than removing it. It is not a
production candidate and it is not worth 80 more trials.

## Bars

**PRIMARY — dead-end misses on the calendar prompt.**

- **Evaluability gate:** the control must show **≥ 4/20** dead-end misses. Pooled
  across the three warm runs production ran 5/30, so 4/20 is the honest floor.
  **If the control is below it, the lane is INCONCLUSIVE — the disease did not
  show up — and nothing promotes.** Declared in advance.
- **Pass:** treatment **≤ half** the control's count **AND ≤ 2/20**.

**SECONDARY (reported, not a win condition):** calendar create rate. Treatment
**≥ control − 2**; a fix that removes the ask by declining to create would be a
regression, and this is what would catch it.

**GUARDS:** remind **≥ 18/20** and alarm **≥ 18/20** in BOTH arms. Grabs
reported, not gated.

**PROMOTION CONDITION, pre-registered:** if the primary passes the evaluability
gate and the pass threshold, and no guard breaks, `continuesAfterNoMatch`
promotes to `true` with the flag-`false` rollback pinned. If the gate fails, the
lane files INCONCLUSIVE and the seam stays off — no third bite at the same
hypothesis without new evidence.

**Classification:** the run JSON through `scripts/classify-battery-run.py`. It
labels dead-end / card-narration / other from raw text, so the primary measure is
generated rather than eyeballed — and #200Z proved that matters: it caught my own
`currentLocation` miscount on its first real use.

**No Apple filing** — standing rule.
