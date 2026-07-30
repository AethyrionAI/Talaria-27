# T27 #204 — the two promoted clauses, warm and within-run

**Owen routed this. Bars written BEFORE the run, and this one is deliberately
scoped as DIRECTIONAL rather than powered — stated up front so it cannot be
over-read later.**

## Why this run exists, and a correction

The 07-30 week plan lists item 4 as "**#200K / #200O warm re-verifications** — the
last two **promoted clauses** whose evidence predates the warm-up." **That
description is wrong and I repeated it.** Reading the verdicts:

- **#200K's datefix was NOT PROMOTED** — "remind ≥ pooled+15pts FAIL … **NOT
  PROMOTED**". The lane's own treatment was a clean negative (the interrogation
  relocated from dates to lists — "the stall is CONSERVED").
- **#200O's grabfix was NOT PROMOTED** — "**GRABFIX IS A CLEAN NEGATIVE**", grabs
  8/10 against a pooled control of 15/19, meta-grabs unmoved.

**Each of those lanes carried a promotion AND a negative under one item number**, and
the plan's shorthand collapsed them. The clauses actually in production are the
**card-narration clause** (`includeCardNarrationClause`, default `true`) and the
**dead-end carve-out** (`includeDeadEndCarveout`, default `true`); the datefix and
grabfix flags both still default `false`. **Item numbers carrying two verdicts is a
tracker hazard worth naming.**

## What is genuinely owed

Both promoted clauses were re-verified **cold** and **against cross-run historical
baselines**:

- #200K: card clause re-verified by pooling `armed` + `armed-cardfix` (byte-identical
  post-promotion) — an ABSOLUTE rate, no within-run control.
- #200O: carve-out re-verified as "16/20 (80%) against the 53% pre-promotion
  baseline" — a CROSS-RUN comparison, in the very lane that proved cross-run
  comparison worthless here ("its three cells landed on exactly 6/10 remind on three
  different texts").

**Under #202's finding that the router is production's warm-up, a COLD pass is
conservative** — production is structurally always warm, so the true numbers are ≥
what was measured. **Both promotions therefore stand a fortiori and this run cannot
demote them.** What it can do is replace two weak comparisons with within-run ones,
and produce the first full production scoreboard since the promotions accumulated.

## Design

| cell | seam | slot |
|---|---|---|
| **armed** | production, both clauses on | **cool** |
| **armed-cardrollback** | production MINUS the card clause | warm |
| **armed-carveoutrollback** | production MINUS the dead-end carve-out (**new**) | warm |

4 prompts × n=10 × 3 cells = **120 counted trials + 4 discarded warm-up ≈ 10 min**
at the ~4.6s/trial #201B measured.

**Production first**, per #201B — and here the thermal penalty lands on the arms that
must exhibit a **disease**, which is the conservative direction for both.

The carve-out rollback is pinned as "production with exactly one string removed", so
it cannot silently become a second seam.

## Bars

**THIS RUN IS DIRECTIONAL, NOT POWERED — pre-registered.** At n=10/prompt the
diseases in question (card narration ~15%, calendar dead-end ~17.5%) expect **1.5**
and **1.75** events. **No count bar can sit above that and mean anything** — that is
the mistake #201 made and #201B corrected, and it will not be made a fifth time.
**Nothing promotes or demotes from this run.**

**EVALUABILITY GATES (both set BELOW expectation, derived not guessed):**

- `armed-cardrollback` shows **≥1 card narration** across its 10 remind trials
  (expected 1.5).
- `armed-carveoutrollback` shows **≥1 dead-end miss** across its 10 calendar trials
  (expected 1.75).

**If a gate fails, that clause's re-verification is INCONCLUSIVE at this n** — not a
demotion, and not evidence the clause is unnecessary. Say so plainly and re-power if
it matters.

**DIRECTIONAL READS (reported, not gated):**

- production card narration should be **0** — it was 0/120 in #200K.
- production calendar creates ≥ carveout-rollback calendar creates.
- production remind creates ≥ cardrollback remind creates.

**GUARD:** alarm **≥9/10 in every cell**. Alarm has been 20/20 or 10/10 in every lane
since #200F; a drop there means the instrument moved, and it is read first.

**SCOREBOARD (the run's real product):** production rates across all four prompts,
warm, post-#202-promotion. Note that the action battery does **not** route, so
#202D's ctx-a promotion cannot affect these numbers — this is a clean read of the
instruction/schema stack alone.

**No Apple filing** — standing rule.
