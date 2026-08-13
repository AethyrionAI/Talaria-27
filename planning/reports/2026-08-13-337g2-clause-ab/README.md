# 337-G-2 — the card-clause A/B, run as two separate launches

2026-08-13, `whoGoesThere` (iPhone 17 Pro Max, iOS 27.0 24A5408d). Owen unlocked
the phone and stood by; both launches ran `unattended: true` through
`scripts/mac/run-instrument.sh`, which is what the artifacts record.

Two launches, not two cells in one run — 337-G's Correction 2 established that
the governor's refusal budget is monotonic across a run, so any between-cell
contrast inside one battery is order-confounded. Separate launches give each arm
a fresh budget. Owen's instruction, and the reason #341 exists.

| file | what |
|---|---|
| `armA-clause-on-0DF68940.json` | arm A — `armed` (production, `includeCardNarrationClause` true), 40 trials |
| `armB-cardrollback-AC147007.json` | arm B — `armed-cardrollback` (`includeCardNarrationClause: false`, `LocalChatBackend+Battery.swift:922-930`), 40 trials |
| `*-run.log` | the harness's own log for each launch |
| `score-337g2.py` | the classifier, reproduced below |

## Result

| arm | `Confirmation card:` | #200J's grep | executed | **fabricated** | offered | empty |
|---|---|---|---|---|---|---|
| A — clause ON | **0/40** | 5/40 | 9 | **3** | 6 | 11 |
| B — clause OFF | **0/40** | 2/40 | 10 | **3** | 2 | 14 |

Both artifacts' `cells` field names exactly one cell, so #341's selection applied
and neither launch fell back to the full battery.

- The bar as written is met: clause-ON narration is 0/40, reproducing #200J.
- The A/B is a null — the clause-removed arm also scored 0/40, so nothing here
  can see the clause. At a ~5% base rate n=40/arm has almost no power.
- Fabrication is identical across arms (3 per 30 action turns, p = 1.0). The
  promoted prose does not touch the class that harms users.
- Thermal was NOT matched: arm A ran nominal→nominal, arm B started `fair`
  because it followed arm A by two minutes. Arm B still executed more tool calls
  (10 vs 9). The next two-launch A/B should space the runs or alternate order.

Full write-up, with the withdrawal of 337-G's "the clause does not hold on
beta5", is at `OPEN_ITEMS.md` #337 under the 337-G-2 bar.

## The classifier, and why two counts are reported

`STRICT` is the literal `Confirmation card:` specimen (337-G's count). `200J` is
the archived three-pattern grep (`confirmation card` | `would you like to
proceed` | `shall I proceed`), which is wider and also catches a plain offer.
Collapsing them would silently pick an era.

The scorer was validated against 337-G's own run before being pointed at these:
it reproduces that entry's independently-recorded 2 specimens and its
`armed/remind` 2-executed / 3-fabricated / 5-offered exactly.

**Its first draft scored fabrication at 0/10 where the truth was 3/10** — the
model writes `I've` with a curly apostrophe and the regex used a straight one. A
fabrication counter that silently reads zero is #300's failure shape.
