# FABLE — Local-brain device run: **is the free tier usable at all?**

**Written 2026-08-02 by the Opus session that just failed to answer "what's the
weather tomorrow" in four and a half minutes.** Owen drives the phone; Fable
orchestrates, reads logs, records verdicts. **Owen routes every merge.**

---

## Why this run exists — read this first, it reframes the whole local-brain backlog

**Measured tonight, production build, on-device brain, standalone, hand-launched.**
Prompt: *"What's the weather going to be like in Gulfport, Ms tomorrow"*

```
21:16:57  routed to on-device
21:17:00  armed — 13 tools registered
21:19:07  context window exceeded — condensing and retrying once (#26)   ← 2m07s
21:19:07  session rebuilt — 13 tools registered AGAIN
21:21:31  run finished [stream-ended]                                     ← 4m34s
```

**Outcome: `PROVIDED 8,218 TOKENS, BUT THE MAXIMUM ALLOWED IS 8,192` and a Retry
button. No answer, ever.** For the weather in the nearest city.

### The three things that make this a re-frame, not another bug

1. **#26's condense-and-retry FIRED and did not help.** #210's fix works — the guard
   caught the overflow, condensed, rebuilt. It then **re-armed all 13 tools** into the
   same 8,192-token window and overflowed again. **A retry that restores the condition
   that caused the failure is not a retry.**
2. **The ceiling is the window, not the call count.** The on-device model has
   **8,192 tokens**. Thirteen tool schemas, the memory injection, restored history and
   every tool *result* share it. It missed by **26 tokens**. #225's spiral is a
   *symptom of pressure inside a window too small for the belt it is carrying.*
3. **#225's cap (built today, per-turn 12 / same-tool 4) did not save the turn** —
   its pre-registered bar **B2 (the turn produces text) FAILED**. The cap is correct
   and stays; it was never sufficient. **Its refusal strings are themselves ~45 tokens
   each into the window it is trying to protect** — a real defect in that design,
   named by the author.

**The question this run answers is therefore not "which local-brain bug is next."
It is: _can the on-device brain answer an ordinary question at all, and what does it
cost?_** Everything else on the local-brain backlog is downstream of that answer.

---

## Global constraints (from `CLAUDE.md` — inherited by every task)

- **`DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer`** in every shell.
- **`xcodegen generate`** after adding/removing Swift files.
- **`scripts/mac/lane-gate.sh` before any PR** — Debug suite **and** Release. Background
  it (`run_in_background: true` alone, never wrapped in `nohup … &`) and poll.
- **Bars are pre-registered in the OPEN_ITEMS entry BEFORE the run.** A missed bar is a
  falsification, not a redefinition.
- **Do NOT harden the relay or connector** (standing rule, 2026-08-02) — irrelevant
  here, but it forecloses "fix it server-side" as an option.
- **Read the count before the marker.** `-only-testing` NAME filters matched nothing
  three times on 2026-08-02 and printed `Test run with 0 tests … TEST SUCCEEDED`.
  **Filter at SUITE level.**
- Owen runs box-side commands in **PowerShell**; `curl` is an alias there.

---

## Lane 0 — PREREQUISITE: we cannot currently measure the thing we are fixing

**There is no production instrument for tool calls.** The relay's per-call logging is
`#if DEBUG` **and** gated on `batteryTrialTag`, which only the battery sets. Tonight
Owen counted tool chips **by eye** and the log could not corroborate it.

**Task 0.1 — a verbose-gated tool-call line.** Emit tool name + running per-turn count
from `ToolEventRelay.started`, behind `UserSettings.verboseLogging` (the Developer
screen toggle), **not** behind `#if DEBUG` — a Release build must be able to produce it,
because Release is what a user runs and #218's whole lesson is that an all-Debug stack
is blind. Also log the governor's refusals (#225) so a refused call is visible even
though it deliberately emits no chip.

**Task 0.2 — a token-budget line at session build.** `LocalChatBackend` already knows
the tool set it arms. Log, once per session build: **tool count, and the token cost of
the tool schemas + instructions**, against the 8,192 ceiling. **This is the number
nobody has ever seen, and tonight's failure is unreadable without it.**

**Bar for Lane 0:** on a verbose Release build, a single turn's log yields the exact
tool-call sequence, the refusal count, and the session's starting token cost.
**Without this, Lanes 1–3 produce anecdotes.**

---

## Lane 1 — THE HEADLINE MEASUREMENT: ordinary questions, ordinary user

**Config, fixed for every trial and stated because #215 exists:** on-device brain,
**STANDALONE (unpaired)**, hand-launched, phone on power, foreground. **Production
routing** — no battery arming, no harness. This is the `routed-production` shape, and
**an unrouted or armed cell measures a configuration the app never enters.**

**Ten prompts a real person would type.** Run each in a **fresh chat** (history is
context pressure and confounds the measurement):

| # | prompt | why it is on the list |
|---|---|---|
| 1 | What's the weather going to be like in Gulfport tomorrow | **tonight's failure, verbatim.** The control |
| 2 | What's the weather right now | the tool CAN answer this — isolates "unmeetable demand" from "weather at all" |
| 3 | Remind me to call Shelley tomorrow at 4 | #225 bar **B4** — a normal multi-tool turn must still complete |
| 4 | What's 2 + 2 | #176's recorded failure: it fired `searchConversations` on the literal string |
| 5 | Tell me about Greece | #176: it declined to state facts it plainly knows |
| 6 | Write a 50-word summary about Norway | #197's specimen — a spurious WeatherTool grab killed the turn |
| 7 | What did I ask you to remember | #176: routed to `readReminders` |
| 8 | Repeat my previous message word for word | #176: routed to `readReminders` |
| 9 | What's on my calendar today | a genuinely armed, genuinely meetable request |
| 10 | Who is the president of France | pure knowledge, no tool can help |

**Record for EVERY trial** (Lane 0's instrument makes this cheap):
**wall time** · **tool calls (executed)** · **refusals (#225)** · **answered? Y/N** ·
**fabricated? Y/N** · **overflowed? Y/N**

### Bars — PRE-REGISTER THESE IN OPEN_ITEMS #225 (and a new item for the window) BEFORE RUNNING

- **L1-A — it answers.** **≥ 8/10 produce non-empty reply text.** *(Tonight: 0/1.)*
- **L1-B — it is not slow.** **Median wall time < 30s**, and **no trial > 90s.**
  *(Tonight: 274s.)*
- **L1-C — no overflow.** **0/10** end in a context-window error. *(Tonight: 1/1.)*
- **L1-D — honesty.** Where it cannot answer (1, 5, 10 may be unmeetable), it **says so**
  and does not invent. **Any fabricated fact is a #199 finding and is reported
  separately, not averaged away.**
- **L1-E — no spiral.** No trial exceeds **12** executed tool calls (#225's cap should
  make this structural; a breach means the cap is not wired on the tested path).

**If L1-A comes back below 5/10, STOP and report.** That is not a bug list, that is a
verdict on the tier, and it is Owen's call what happens next — not a lane's.

---

## Lane 2 — the window itself (gated on Lane 0.2's number)

**Hypothesis to test, not assume:** the armed belt consumes so much of 8,192 that
ordinary turns start close to the ceiling.

- **2.1** With Lane 0.2's instrument: what fraction of 8,192 do 13 tool schemas +
  instructions + memory injection consume **before the user's first token**?
- **2.2** Re-run Lane 1's prompt 1 with a **deliberately narrowed belt** (the #216
  mechanism — narrowing moves pressure, so watch where it goes). Does it answer?
- **2.3** **The #26 re-arm question.** On overflow the guard condenses and rebuilds
  **with all 13 tools again** (observed tonight, 21:19:07). **Should the retry re-arm at
  all, or retry toolless?** A toolless retry cannot spiral and cannot overflow on tool
  schemas — and #215 already measured that a toolless turn composes cleanly. **This is
  the single highest-value experiment in this document.**

**Bar 2.3:** on the same prompt, a **toolless retry** produces text where the armed
retry produced an overflow. If it does, that is a one-line change to #26's guard with a
measured justification.

---

## Lane 3 — the trigger, and it is small

**`currentWeather`'s contract is "live conditions and TODAY'S forecast."** "Tomorrow" is
unmeetable by the whole belt, and the unmet demand is what displaced into
`searchConversations` (#216's substitution mechanism).

**Task 3.1 — extend the weather tool to WeatherKit's daily forecast.** The Opus session
deferred this as *"removes the trigger, not the class"* — **that judgement was wrong on
tonight's evidence and is recorded as such.** The class fix (the #225 cap) demonstrably
does not save the turn; the trigger fix ends the question at call 2.

**Bar 3.1:** prompt 1 answers with a real forecast in **< 15s** and **≤ 3 tool calls**.

**Scope discipline:** this is a tool contract change plus its tests. It is **not** a
licence to add tools — the belt's size is Lane 2's suspect, and adding to it while
measuring it would confound both.

---

## What NOT to do

- **Do not re-run the #200-series batteries.** They measure cell contrasts on an armed
  path; this run measures whether the product works. Different questions (#215).
- **Do not fix Lane 1 failures mid-run.** Record all ten, then decide. A run that fixes
  as it goes produces a verdict about a build that no longer exists.
- **Do not widen.** If Lane 1 turns up ten findings, file them and fix the two that
  block the tier.
- **Do not claim a device verdict from the simulator.** The on-device model does not
  exist there — `CondenserFidelityTests` skips for exactly this reason, and the gate now
  prints `NOTE 2 test(s) SKIPPED` so that stays visible.

---

## Deliverable

A verdict on **L1-A through L1-E** with the per-trial table, Lane 2.3's answer, and —
if Lane 3 runs — prompt 1 answered in under 15 seconds. **Plus an honest headline:
is the on-device brain shippable as the free tier today, yes or no?** #166c makes it
the reviewable product, so that answer gates Phase 7.
