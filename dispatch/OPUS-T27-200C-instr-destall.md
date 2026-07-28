# OPUS-T27-200C-INSTR-DESTALL — the de-stall clause moves upstream to instructions

**Executor:** local Claude Code. **Drafted 2026-07-28 night from the FILED #200B verdict
(PR #166 merged `0056baa`), routed by Owen ("Go for it").** Branch
`claude/t27-200c-instr-destall`.

## Why

#200B falsified the tool-text seam: de-stalled @Guide and description texts left the
remind clarify-stall at 0/10, 0/10, 0/10, 1/10 — the "which list?" question fires at
RESPONSE PLANNING, before the model engages any tool schema. The next seam upstream is
the SESSION INSTRUCTIONS — the same `instructionsText` clause mechanism that carried
every #196 instruction treatment (composition licensing, lic2). Supporting hint from
#200B: the bothfix cell's calendar creates rose 4/10 vs 0-1 elsewhere — schema texts
ride in the instructions context, so instruction-level language plausibly reaches what
tool-level language cannot.

## The cell

- `armed` — production control (re-baselines in-run).
- `armed-instrfix` — production belt UNTOUCHED; instructions = production armed text
  plus ONE clause (measured artifact, pinned):
  "When the user asks for a reminder, alarm, or calendar event and says what and when,
  create it right away — never ask which list, which calendar, or for other optional
  details first; leave optional fields empty and the defaults apply."
  Placement: inside the `hasTools` capabilities paragraph, after the confirmation-card
  sentence — the action-sentence cluster. The flag defaults OFF and the flag-off text
  is BYTE-IDENTICAL to production (pinned by test, #196 discipline).

## Protocol

2 cells × 4 prompts (remind / alarm / calendar / haiku grab canary) × n=10 = 80 trials
(~20–30 min), auto-accept, reap, mutex — the #200/#200B instrument unchanged. Button:
"Instrfix battery n=10 (80)". Success = remind moves off 0/10 in armed-instrfix at
tolerable haiku-grab cost (control baseline 8/10 — the canary now also watches whether
the clause pushes grabs UP, its main risk: "create it right away" is grab-flavored
language gated only by the "asks for a reminder" antecedent).

## Rules

House rules as ever. Classification from RAW TEXT with rates; ERROR trials excluded
and listed. NOTHING promotes without the verdict — a winning clause promotes into
production `instructionsText` in a follow-up with pins, #163-style. Out of scope:
multi-turn instrument, remfix scoping, calendar contact de-fixation.
