# FABLE — Local-brain device run RESULTS, 2026-08-02 (night)

**Answering `FABLE-T27-LOCAL-BRAIN-DEVICE-RUN.md`.** Owen drove the phone; Fable
orchestrated and read the instrument live over USB (`idevicesyslog`). **Build 1843
(`7fd0dbc`, PR #246 branch — Release, verbose ON via the newly-reachable Developer
menu), production routing, fresh chat per trial, hand-launched, corded (on power),
foreground.**

**Config annotations, honest:**
- The dispatch said *standalone (unpaired)*; the phone was **paired (OJAMD
  linked/online) with the brain pinned on-device.** Consistent across all ten trials
  and both baselines, so every contrast holds; arguably the realer production shape.
- The 21:16 baseline was a **DEBUG** build (proven: its log carries a DEBUG-only
  line). Its 274s/overflow numbers are Debug-speed (#231).
- Trials ran on **build 1843**, which contains the #231 UI fix and the #228 revised
  (post-turn-flush) instrument. Trial 1 on build 1842 was INVALID — the original
  instrument's mid-turn measurement killed the turn (#228's L0-D falsification) —
  and was re-run on 1843.

## The per-trial table

| # | prompt | routed | wall | exec | refusals | outcome |
|---|---|---|---|---|---|---|
| 1 | weather Gulfport tomorrow | armed | **~2.5 min** | **12 (cap)** | **57** | honest decline after the refusal grind — no forecast |
| 2 | weather right now | armed | ~6s | 2 | 0 | ✅ correct conditions |
| 3 | remind me: call Shelley tomorrow at 4 | armed | ~1 min w/ confirm | 1 | 0 | reminder REAL but at **4:00 AM** (half-day default wrong) |
| 4 | what's 2 + 2 | toolless | ~1s | 0 | 0 | ✅ "4" |
| 5 | tell me about Greece | toolless | ~4s | 0 | 0 | ✅ accurate, substantive |
| 6 | 50-word Norway summary | toolless | ~3s | 0 | 0 | ✅ clean composition |
| 7 | what did I ask you to remember | armed | ~4s | 1 | 0 | wrong door (`readReminders`): true data, misread question |
| 8 | repeat my previous message | toolless | ~2s | 0 | 0 | wrong referent: echoed its OWN prior reply verbatim |
| 9 | what's on my calendar today | armed | <30s | 3 | 0 | ✅ correct — plus unrequested weather (over-serve leaked into the answer) |
| 10 | who is the president of France | toolless | ~2s | 0 | 0 | honest "I don't know" — likely FM political-figure guardrail (observation, unproven) |

Receipts ranged IN 0.5K–7.7K per turn. Token budget, measured every session build:
**armed = 3,257 tok before the user's first word (1,434 belt + 1,823 instructions/
memory) = 40% of the 8,192 window; toolless = 486 tok.**

## Bars (pre-registered in OPEN_ITEMS #225 before the run)

- **L1-A (≥8/10 non-empty reply): PASS — 10/10.** Correct-and-complete: 5. Honest
  declines: 2 (trials 1, 10). Defect answers: 3 (trials 3, 7, 8).
- **L1-B (median <30s AND no trial >90s): FAIL on the second clause.** Median ≈ 4s
  (vs the 274s Debug baseline); trial 1 ≈ 150s+.
- **L1-C (0/10 overflow): PASS.** Zero. The 21:16 overflow did not reproduce on
  Release — unexplained, open under #229.
- **L1-D (honesty): PASS.** No fabrication in any of the ten. (The verbose-off
  control's "tomorrow"-labeled forecast remains a SUSPECTED #199, outside the ten.)
- **L1-E (≤12 executed): PASS.** The #225 cap held everywhere, including at its
  exact boundary on trial 1.

**Stop condition (L1-A < 5/10): not approached.**

## Lane 2 / Lane 3 status

- **2.1 ANSWERED:** the armed belt consumes **40% of the window** before the first
  user token (measured repeatedly, model's own tokenizer).
- **2.3 COULD NOT RUN:** nothing overflowed in ten Release trials — itself a
  finding; the overflow class may be partly Debug-conditioned. #26's re-arm
  question stays open at reduced priority.
- **Lane 3 (#230) not run, per its own sequencing rule** — and trial 1 vs trial 2
  (~2.5 min vs 6s, same belt) is now its measured justification.

## The discovery of the night — #232, the refusal grind

Trial 1's minutes were NOT the executed calls: after the cap, the model burned
**57 refusal→re-infer cycles at ~2.4s each** — one full inference round per
refusal, each appending ~45 tokens of refusal text to the window. Executed calls
are bounded (#225); **refusals are bounded by nothing.** Watched live by the #228
instrument; invisible to every prior session because refusals emit no chip. Fix
direction filed in #232 (end the tool phase structurally — `ToolCallingMode`
demote — not rhetorically).

## Findings filed or annotated tonight

| where | what |
|---|---|
| **#232** (new) | the refusal grind, with trial 1 as pre-registered baseline |
| **#233** (new) | "tomorrow at 4" → 4:00 **AM**: half-day defaulting on reminder create; confirm card did not save it |
| #225 | over-serving on armed turns persists at small scale (trial 9: 3 calls for 1, weather leaked into the answer) |
| #176 family | trial 7 wrong-door (`readReminders` for conversation memory), trial 8 wrong referent on "repeat" |
| #229 | Release ran 10/10 with zero overflows where Debug died — the overflow class needs a config-aware re-look |
| #199 | control's "tomorrow"-relabeled forecast, SUSPECT only |
| observation | trial 10's president deflection — probable FM guardrail on political figures |

## The headline, as the dispatch demanded

**Can the on-device brain answer an ordinary question at all? YES — decisively.**
Median ~4 seconds, honest, no fabrication, the governor holding. The failures
cluster into a small number of NAMED mechanisms, each with a scoped fix already
filed.

**Is it shippable as the free tier today? Fable's recommendation: NO — but it is
one fix-lane away from re-judgeable.** The blocker is the unmeetable-demand class
(trial 1): any request the belt cannot satisfy costs the user minutes of silent
grinding, and real users hit unmeetable demands constantly. #232 (refusal cap /
structural tool-phase end) plus #230 (the weather-tomorrow trigger) convert that
class's worst specimen into the 6-second class. Run those two lanes, re-run this
battery's failed rows on the fixed build, and the tier question becomes live.
**The verdict is Owen's (#166c gates Phase 7).**
