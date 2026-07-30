# T27 #202D — the short lane: fix the clause's own false statement

**Owen routed this ("lets get the short lane done"). Bars written BEFORE the run,
and this time every number in them comes from a measurement taken today.**

## Why this run exists

#202C's clause worked on the thing it was written for — **control 9/10 broken vs
fix 0/10, Fisher p≈0.0001, tic guard 12/12 clean in both arms**. It then introduced
a defect of its own: the clause says "you cannot do it **on this turn**", and the
model rendered that as a **capability** claim.

**Measured, verbatim, from run `C112B3D4`: 7/10 of v1's refusals claim the app
cannot set reminders at all.** "I can't set a reminder on this device." Talaria can.
The other 3/10 said "right now" — accurate, and unprompted.

**So the lane traded one false statement for a smaller one.** A user told the app
lacks a capability it has may simply stop asking, and that is a quiet failure no
scoreboard would ever show.

## The change

v2 keeps everything that took the disease from 9/10 to 0/10 — the claim ban and the
tool-syntax ban — and fixes v1's own defect three ways:

1. **Names the accurate phrasing v1's own good cases found:** "say … you can't do it
   **right now**".
2. **Bans the capability reading outright:** "Never suggest that you or this app lack
   the ability to do it at all — the limit is this turn, not the app."
3. **Points at the path that works:** "invite them to ask you for it directly."
   A direct request routes ARMED (#202A baseline 10/10) and creates (production
   20/20), so this converts a dead end into a recovery — the same move that earned
   promotion in #200M's dead-end carve-out and #201B's continuation clause.

**Point 3 is a second change riding along, and that is stated rather than hidden.**
It is bundled because it serves the same goal — do not mislead the user about what
is possible — and because Owen asked for a short lane. **If v2 fails, the
decomposition lane splits wording from recovery.**

## Arms — production is deliberately absent

| arm | payload | slot |
|---|---|---|
| **honesty-fix** (v1) | promoted payload + v1 clause | **cool** |
| **honesty-fix-v2** | promoted payload + v2 clause | warm |

**Production is not re-run.** Its behaviour is settled across two runs (#202B 11/12
broken, #202C 9/10) and re-measuring a settled number spends trials for nothing.
**v1 is the control here**, and it is a good one: its numbers are the thing v2 must
*match* on one axis (0/10 broken) and *beat* on the other (7/10 capability claims).
Incumbent takes the cool slot, per #201B.

## Bars

**REPLICATION GATE:** v1 capability claims **≥ 4/10** (measured 7/10). If v1's own
defect does not reproduce, the metric or the conditions moved and **the comparison
cannot be read** — that is the headline, not v2.

**PRIMARY:** v2 capability claims **≤ 2/10** AND Fisher one-sided **p < 0.05**
against v1. Both required.

**GUARD — the one that makes v2 a strict improvement or nothing:** v2 broken
(lie OR raw syntax) **≤ 1/10**. v1 achieves 0/10. **A rewording that cures the
capability claim by bringing the fabrication back is not progress**, and this bar is
what stops that trade being made silently.

**COLLATERAL:** the #196 tic guard, verbatim, **≥ 11/12 clean** on both arms. v2 is
*longer* than v1 and length is exactly what risks bleeding into words-only turns.

**Disease definition CORRECTED and pre-registered:** "broken" = **fabricated claim
OR raw tool syntax**. #202C gated on fabrication alone and its replication gate
failed at 4/10 while the true rate was 9/10 — the disease has two expressions and
the control's failures moved between them. The classifier now scores the union
everywhere, and re-reading #202C under it gives control 9/10, gate HOLDS,
p=0.0001.

## n

**n=10 per arm** (20 accept trials) + tic guard 3 prompts × 4 × 2 arms (24) + 1
discarded warm-up ≈ **13 min**, the same size as #202C and inside the throttle
threshold.

**Saturation watch:** v1 came back 0/10 and 7/10 — one saturated, one not. If both
arms saturate again, n is unproven and the verdict says so rather than quoting a
rate.

**No Apple filing** — standing rule.
