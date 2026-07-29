# T27 #200O — promote the v3 carve-out, and take the grab disease

**Owen routed the merge of #179 and this lane. Off-LAN: OTA Debug staging,
run-JSON export.**

## Part 1 — the promotion

The v3 dead-end carve-out has now been measured against production twice:

| | #200M | #200N | pooled |
|---|---|---|---|
| calendar (v3) | 8/10 | 9/10 | **17/20 (85%)** |
| calendar (production) | 5/10 | 5/9 | **10/19 (53%)** |
| remind (v3) | 8/10 | 10/10 | 18/20 |
| remind (production) | 10/10 | 9/10 | 19/20 |

**Calendar +32 points, same direction and size both runs. Remind level.** Sam
dead-end misses fell 5→~0 and 4→1 while hunt calls barely moved (23→16, 16→15),
so the mechanism is confirmed: the win comes from **licensing the create**, not
from forbidding the search — which is exactly what separates v3 from v2, and v2
was retired for resurrecting find-first.

`includeDeadEndCarveout` flips to **default TRUE**, explicit `false` is the
pinned byte-identical rollback. Production instructions are now base + destall
(#200D) + find-first (#200G) + card clause (#200K) + dead-end carve-out (#200O).

Four seam pins moved with it and were watched **behaviorally RED** before the
flip — the card promotion pin, the card rollback seam, the cardrollback CELL
pin, and the dayDefault seam all ended at `"When a tool reports"`, which the
promoted sentence now sits in front of.

## Part 2 — grabfix, the disease that has been getting worse

Grabs are the only number in this program that has moved the wrong way while
everything else improved: **4/8 → 4/10 → 7/10 → 15/20 → 9/10 → 9/10**. That is
not a coincidence. Six lanes have spent their words raising create-pressure
("create it right away", "make the call", "create the event with the name as
given"), and the haiku prompt gets swept up in it. The specimen is the
**meta-grab** — a reminder whose title is the request itself, "Write a haiku
about sledding" — and in #200N one trial produced **both** a reminder and a
calendar event for a poem.

The armed paragraph already says composing "needs no tool". That is
*permission*, and permission has never been enough here — #200J proved exactly
this about the confirmation card, where the model knew the card existed and
impersonated it anyway. So the clause names the artifact instead:

> When the user asks you to write something, the writing itself is the answer —
> never also create a reminder, event, or alarm about writing it.

`includeCompositionAnswerClause`, default FALSE, seated after the promoted
carve-out.

## The battery — one run, both jobs (the #200K shape)

`grabfixBatteryCells = [.armed, .armedDeadendfix, .armedGrabfix]` × 4 prompts ×
n=10 = **120 trials**. Diagnostics → "Grabfix battery n=10 (120)".

`armed` and `armed-deadendfix` are identical post-promotion, so they **pool as
the production re-verify at n=20/prompt** — confirming the calendar promotion at
a real sample size — while `armed-grabfix` measures the new treatment against
that pooled control.

## Bars

**Re-verify half (pooled n=20):** calendar **≥14/20** (the 85% claim, against a
53% pre-promotion baseline), remind **≥17/20**, alarm **20/20**, Sam dead-end
misses **≤2**.

**Grabfix half (vs the pooled control):** grabs **≤ half** the pooled control
rate, meta-grabs **≤1**, and no collateral — remind not worse than pooled by
more than 2, calendar not worse by more than 3, alarm 10/10.

Grab rate is the noisiest number in the program (production has read 4/10 and
9/10 in consecutive runs), so "≤ half" is deliberately a large effect: anything
smaller cannot be distinguished from that swing at n=10 and should not be
promoted on one run.

## Protocol

Unchanged: auto-accept gate, `[T27-battery]` marker, per-trial reap, 35s
guillotine, foreground + on power, hands off. Rates from RAW TEXT; a create =
`confirm=accepted` + its artifact; exclusions listed AND adjudicated
instrument-vs-disease; reap arithmetic exact (nine consecutive runs).

Deploy: `scripts/mac/ota-stage.sh claude/t27-200o-promote-v3-grabfix Debug`,
install from Safari at `https://owens-mac-mini.tail5663a6.ts.net`.
