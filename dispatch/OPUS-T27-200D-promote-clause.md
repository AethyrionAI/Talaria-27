# OPUS-T27-200D-PROMOTE-CLAUSE — the de-stall clause ships to production

**Executor:** local Claude Code. **Drafted 2026-07-28 night from the FILED #200C verdict
(PR #167 merged `28551c7`), routed by Owen ("yup, merge and start on the next").**
Branch `claude/t27-200-promote-clause`.

## Why (the verdict this promotes)

#200C instrfix battery, run `FFC92E35` on `6f8da47`, sealed clean, reap arithmetic
exact: the identical clause that did NOTHING from inside the tool schema (#200B:
remind 0/10-0/10-1/10 across guide/description/both) moves all three action prompts
when spoken from `instructionsText` —

| cell | remind | alarm | calendar | haiku GRABS |
|---|---|---|---|---|
| armed (control) | 0/10 | 8/10 | 0/9 | 9/10 |
| armed-instrfix | 2/10 | 10/10 | 8/10 | 3/9 |

Calendar 0/9 → 8/10 (contact-fixation de-licensed from upstream: lookupContact 8/9
control trials → 2/10 treated). Remind off zero for the first time against a 0/40
lifetime control. The feared grab risk INVERTED (9/10 → 3/9): the asks-for antecedent
sharpens creation licensing in both directions. Known collateral, accepted with eyes
open: occasional cant=true refusal of the creative task itself (4/9 treated haiku
trials vs 1/10 control) and one garbage create. Dispatch success bar ("remind off
0/10 at tolerable haiku-grab cost") met with margin.

## The change (#163-style promotion)

- `includeActionDestallClause` DEFAULT flips `false` → `true` in
  `LocalChatBackend.instructionsText`. One edit; every production path flips by
  construction: the Release call, the DEBUG `armedRouted` default shape, every
  structural cell documented as "production text verbatim," and the batteries'
  control cells. The toolless branches are `hasTools: false` — the clause lives
  inside the `hasTools` capabilities paragraph and cannot appear there.
- The flag STAYS as the rollback/re-measure seam: `includeActionDestallClause:
  false` reproduces the pre-promotion text byte-identically (pinned).
- The `armed-instrfix` cell becomes identity with control (both speak promoted
  production). The Diagnostics "Instrfix battery n=10 (80)" button is thereby the
  RE-VERIFY instrument: 2× replication of promoted production, 20 trials/prompt
  including the grab canary, zero new code.
- Pins: `actionDestallClauseIsAdditiveAndOffByDefault` inverts to
  production-default-and-removable (clause present in default, adjacency pinned on
  both seams, explicit-true is identity, explicit-false removes exactly the clause).
  Every other instructions pin is relative (control == production) and flips with
  the default untouched.

## Protocol

Suite green with stated count → file-scoped commits → PR → OTA stage Debug →
Owen installs and taps "Instrfix battery n=10 (80)" on the promoted build →
classify from RAW TEXT with rates (ERROR trials excluded and listed, reap
arithmetic cross-check) → re-verify verdict files to OPEN_ITEMS (separate commit)
and the PR. Expected if promotion holds: both cells replicate the #200C treated
rates (remind ~2/10, alarm ~10/10, calendar ~8/10, grabs ≤3/10 per cell).

## Rules

House rules as ever. The promotion is REVERSIBLE (one-line default flip back; the
rollback text stays pinned). Out of scope: the multi-turn offer→denial instrument,
remfix scoping, any tool-description change, the battery artifact-contamination fix
(per-trial unique titles) — all queued behind the re-verify verdict.
