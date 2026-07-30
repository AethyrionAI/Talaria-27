# T27 #202A — is the router context-blind, and can context cure it?

**Owen routed this ("Lets continue"; the 07-30 handoff names #202 as the highest-value
measurement left). Bars written BEFORE any code. Classified from the run JSON.**

## Why this run exists

#202 was filed from a code read, not a measurement. The chain — verified line-by-line
in `LocalChatBackend.swift`, and re-verified today at `9bb9cdc`:

1. `routeNeedsDeviceTool(prompt:)` (L2205) builds a **fresh** session and prompts
   `Prompt("Request: \(prompt)")` — the raw current turn, **no history**.
2. `ToolIntentRoute`'s pinned `@Guide` says false for "Writing, poems, summaries,
   math, facts, and **conversation**". **"Yes please" is conversation.**
3. `effectiveOfferedTools` (L944): `if turnRoutedToolless { return [] }` — a
   routed-toolless turn registers **no belt at all**.

So the flat capability denial on "Yes please" is *correct behaviour for a session with
no tools*. **Every existing instrument is single-turn and cannot see this.**

**One thing the filing did not know, established today:** `rebuildSession` (L730)
replays `transcriptTurns` from the stored conversation into the fresh session. So on
turn 2 the model **does** see the offer — it is not amnesia, it is disarmament. That
narrows the fix to the router and rules out "give it history" at the session level.

## What this run is NOT

**Nothing promotes from #202A.** It is a cheap, high-n probe that measures the
mechanism and *selects* a candidate for #202B, the expensive two-turn end-to-end run.
Separating them is deliberate: probes cost ~0.6s and no side effects, two-turn trials
cost ~30s and write real artifacts. Measure mechanism cheap, confirm consequence dear.

## The grid

13 rows, each a `(context, prompt, expected)` triple. `expected` is the route that is
actually right for that turn.

**Offer → accept (expected ARMED) — the disease, 6 rows:** "Would you like me to set a
reminder for that?" / "Yes please"; and five more accept forms (yes, sure, go ahead,
please do, yeah).

**Words-only after context (expected TOOLLESS) — the collateral, 5 rows:** another
haiku; "Thanks!" after a completed create; summarize-that; **"No thanks" after an
offer**; a follow-up percentage question.

**Device-explicit after context (expected ARMED) — regression, 2 rows.**

Run against **three router variants** plus the untouched **#196 no-context grid**
(10 rows) as the baseline:

| variant | seam |
|---|---|
| **control** | production `routeNeedsDeviceTool` — ignores context by construction |
| **ctxA** | same pinned instructions; prompt envelope gains one line: `Assistant just said: "…"` |
| **ctxB** | ctxA's envelope **plus** one added few-shot example showing offer→yes |
| **lenrule** | pure code: short-affirmative → inherit previous route. No generation. |

ctxA and ctxB are two framings of one seam, measured in parallel because probes are
nearly free. #196 chose its own framing exactly this way (guide-only and
flipped-polarity both lost on a grid before few-shot won). **Instruction text stays
pinned in ctxA** — the envelope is the only change — because the pinned text is a
measured artifact and changing it and the envelope together would be two seams.

**Cost:** 13 + 10 rows × 3 generating variants × n=15 ≈ 10 min. `lenrule` is free.
Under the ~15–20 min throttle threshold established by #201B (lesson 5).

## Bars

**MECHANISM — CONFIRMED** if the control routes the 6 bare affirmatives TOOLLESS in
**≥ 68/90** pooled (75%).

**MECHANISM — REFUTED if < 20%.** Then the filing is wrong, #202's write-up is
corrected from evidence, and the lane re-derives from what the run shows. *Stated in
advance so a null result is a finding and not a disappointment.*

**BASELINE REGRESSION GATE:** the control must hold the #196 no-context grid at
**≥ 143/150 (95%)**. That grid measured 200/200 twice. If it has drifted, every other
number in this run is suspect and the verdict reports that **first**.

**CANDIDATE PASS — all three required**, for ctxA or ctxB independently:

1. **Accepts fixed:** ≥ **81/90** (90%) of offer→accept rows route ARMED.
2. **No collateral:** words-only-after-context rows stay TOOLLESS at ≥ **71/75** (95%).
3. **Device rows hold:** ≥ **29/30** ARMED.

**Bar 2 is the one that matters.** A router that fixes accepts by routing *everything*
armed is not a fix — it re-opens #196, whose entire disease was the disclaimer tic on
words-only turns, cured by withholding the belt. #200H's spiralfix died of exactly this
shape: best-ever calendar, sagging remind, cross-intent bleed, not promotable. Naming
the degenerate outcome in advance is what stops it being rationalized later.

**LENRULE is REPORTED, NOT GATED.** Its classification is deterministic and pinned by
unit tests. Its real cost is that it *inherits* — and inheritance can only be measured
in a two-turn run, because a wrong inherited route persists for the rest of the
conversation. **It cannot be selected from this instrument.**

## What #202B gets from this

The winning variant, and an n sized from the measured accept rate rather than guessed
— #201's mis-specified gate (a floor above the disease's own expected rate) is the
error this program has now made three times, and the correction is to derive n from a
base rate this run supplies.

## Confounds stated in advance

- **Probe order is fixed**, so a thermal gradient would fall on later variants. Variant
  order is therefore **control → ctxA → ctxB**, putting the *incumbent* in the coolest
  slot: any candidate win is then won from the penalised position. #201B's inversion
  logic, applied before the fact rather than after.
- **Off-distribution framing:** the pinned instructions' few-shot examples are all bare
  one-line requests. A two-line envelope is off that distribution, and ctxA may fail for
  that reason rather than because context is useless. That is exactly what ctxB
  separates — if ctxA fails and ctxB passes, the answer is "context works, it needed an
  example", not "context does not work".

**No Apple filing** — standing rule.
