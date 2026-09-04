# 2026-09-04 — The difficulty sweep: what is parked because it is hard, and the plans for it

Owen, 2026-09-03 night: *"take a look at the things that are holding on difficulty. If there's something that could use your touch, please take a look at it, and develop plans for execution, like we did for the memory plan."*

Method: every live entry on `OPEN_ITEMS.md` (31), every card on the Desk Board (§01 decisions, §02 external, §03 watches, §04 parked), and the sweep-14 closing blocks were read for the shape *stalled because hard* — as opposed to external, awaiting a device evening, awaiting Owen's word, or ruled parked. Three read-only survey agents pulled each candidate's latest dated blocks and code locations; the plans below were written from those reads plus the 422-S/T/U lane's own evidence, in the memory plan's shape (design rationale + global constraints + decisions with recommended defaults + pre-registered bars + RED-first tasks + a device evening).

## Plans written (each starts a NEW session; each opens with one AskUserQuestion round on its defaults)

| plan | the difficulty | the touch | first step |
|---|---|---|---|
| `planning/superpowers/plans/2026-09-04-340-due-date-from-user-words.md` | ~55% of reminders still dateless on the promoted guide text; every prose and schema route falsified; route (a) app-side is correct but sees only the model's argument, which is usually empty | resolve the date from the USER'S OWN WORDS when the argument is empty — `NSDataDetector` + the existing bare-clock parser, through the per-turn relay seam the backend already calls; deterministic, no model, inside every ruling on the entry | Task 0 measures `NSDataDetector` on the instrument's prompts before any bar is pinned |
| `planning/superpowers/plans/2026-09-04-219-deterministic-gate.md` | the XCUITest swallowed-tap flake taxes every lane 30–40 min (six reds one night, three across the memory lanes, one on tonight's gate), the classifier tells the operator the opposite of the protocol, and the evidence the entry wants has never been captured (the xcresult hangs) | make the failure path self-describing in the LOG (tonight's log already shows XCUITest computing hit point `{-1, -1}` after scroll-to-visible — new); a `known-flake` verdict and an automated single UI-target re-roll that keeps both logs; a measured baseline, one untried tap strategy, a measured re-run | file tonight's evidence into #219; Task 0 and Task 1 are independent lanes |
| `planning/superpowers/plans/2026-09-04-422-memory-instruments.md` | 422-F — the number that decides whether memory is safe — can only be measured by hand (40 questions × 4 arms); both instruments the runbook names are unbuilt and there is no seeding path that does not touch the user's real store | per-arm harness backends with in-memory stores (the user's memory is never written, read, or emptied by a measurement); a phrase scorer with its own positive control and a Python twin; DE1 as re-cut under 422-U | Task 0 probes that a harness backend generates on device with a store attached |
| `planning/superpowers/plans/2026-09-04-392-calendar-decline-wording.md` | the calendar decline is misattributed to the calendar 1 in 5 (p = 0.0018 vs reminders/alarms 0/58) and the route was measure-only; the measurement is now significant and nothing has been elected | elect one treatment — the tool result names the actor — and measure it on the existing instrument at the trial count that clears n ≥ 30 scorable; a null result is a finding | Owen's election (decision 1) |

## Looked at, not planned — and why

- **#332-c (iPad-only `AttachmentDownscaleTests` reds).** Three tests red on Shelley's iPad, green on phone and sim; the probable mechanism is a 2× vs 3× scale fixture; bar 1 is "tell the two apart" and needs the iPad in hand. A measurement, not a difficulty — it is one device evening on the iPad and the entry already carries its bars.
- **#396 row 12 (local-engine cut-off — Apple's finalizer vs our 1.35 s watchdog).** The discriminator line ships and has never fired in any archive because no captured session ever ran the local pipeline; the runbook card `396r12` is runnable and names the dichotomy's third arm (the watchdog gated out during a reply). It is holding on a *measurement*. The product option the entry names for the local engine's sensitivity — push-to-talk — is a real "touch" candidate but a product decision first; it goes on the Desk Board as a question, not into a plan.
- **#314 (durable attachment turns in the compose outbox).** Owen's ruling: a v1 limit, re-examine only if he wants images queueable. Scope, not difficulty.
- **#379 (Projects introspection surface).** Owen's ruling 08-18: parked post-launch, do not re-raise before launch.
- **#324-W2 (HTMLArtifactSandbox 5 s budget).** Two occurrences, both under ≥ 3 concurrent builds; the entry's own rule is "only if it recurs on a QUIET box." The #219 plan's baseline runs on a quiet box and will say.
- **#236 (MessageIdentity render flake).** Eight occurrences, cause never named, the transcript dump ships; the rule is "name the cause before touching the timeout." Folded into the #219 plan as an evidence-discipline task (DET-F), no code.
- **The #422 chip question (Q1) and spoken "Remember that…" (Q2).** Both are on the Desk Board with recommendations; Q2's lane is Task 6 of the instruments plan if Owen answers "wire".
- **`candidates()` as a whole-table fetch per retrieving turn.** The scaling risk the memory lane named; DE1's 422-L row measures it first. A plan before the number would be a guess.

## What the four plans have in common (so a session can hold them to it)

1. A Task 0 that measures the plan's own premise before the bars are pinned — the 422 review found that both real findings were premises the plan's author wrote, not code the lane wrote.
2. Bars pre-registered in the tracker entry before code; a missed bar is a falsification, never a redefinition.
3. Isolating mutations named per bar; the gate on final bytes; merge on green; RESULT block.
4. Every device number carries build, `osVersion`, thermal, routed-ness; every instrument calls `beginTurn()` per trial.
5. The decisions Owen has not made are listed with a recommended default, and the session opens with one AskUserQuestion round on them — as the memory plan did.
