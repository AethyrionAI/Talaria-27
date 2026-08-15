# FABLE — #257's next lever: the conversational bar after the instruction-clause mechanism was falsified

**Label:** FABLE (Fable executes the lane Owen picks). **Item:** OPEN_ITEMS #257
(conversational bar), successor to the falsified #297. **Written 2026-08-09**,
the morning after device run `A04154D7`.

**Goal in one sentence:** give Owen 2–4 genuinely distinct, falsifiable ways to
make a fresh "What can you do?" produce a COMPLETE and honest answer, now that
putting the family list in the toolless instructions has been measured and ruled
out.

**This document proposes bars. It files nothing.** Bars live in the OPEN_ITEMS
entry and the orchestrator writes them there before any run (#215 convention).
No production code, no Swift edits, no tracker edits were made producing this.

---

## 2. What is settled — a fresh reader must not re-propose the dead lever

### 2.1 The ARMED half is FIXED and is not the problem

#284 (merged, 2026-08-08) replaced the hand-written capability blurb with a
registry-generated enumeration. `LocalChatBackend.swift:1921` now interpolates
`armedEnumeration(families:hasImageTools:)` →
`CapabilityRegistry.armedCapabilityEnumeration(families:)`
(`CapabilityRegistry.swift:92`), so the armed persona's list is generated FROM
the belt and structurally cannot go stale. #257's original root cause — a
hand-written prose list that drifted — is dead. **A new tool now appears in the
armed blurb automatically.**

### 2.2 The question does not reach that fix

Production's router is a single Bool (`ToolIntentRoute`,
`LocalChatBackend+IntentRouting.swift:421`). It routes "What can you do?"
**TOOLLESS** — verified on device, build 2225, fresh chat: the reply named zero
capability families, IN=500 tokens, a beltless turn. A routed-toolless turn
registers no belt at all (`effectiveOfferedTools`, `LocalChatBackend.swift:1246`)
and speaks the toolless-lic2 payload (`effectiveInstructionsText`, `:1284`). The
armed enumeration is never in context on this question.

> **Correction already filed and load-bearing:** #284's verdict originally
> inferred from its META rows that "what can you do?" routes ARMED. That was the
> VECTOR schema's routing, and the vector never shipped. The inference is
> WITHDRAWN in the tracker. **Production's one-Bool router is the operative
> one.** Do not resurrect the withdrawn claim from the #284 verdict text.

### 2.3 The obvious mechanism is RULED OUT — measured, not merely untried

Device run **`A04154D7`**, OTA build 2271 (merged `main` `11aaeb2`), iOS 27.0
(24A5390f), 2 arms × 3 prompts × n=20 = 120 generations, **`scored=20/20` on all
six rows** — zero timeouts, zero errors, so every denominator is a real examined
count.

| bar | pre-registered | measured | |
|---|---|---|---|
| **297-A** | ≥18/20 (≥90%) name ≥8 of 10 families | **7/20 (35%)** | **MISSED** |
| 297-B | canaries control-matched | 0 denials, transcripts clean, both arms | MET |
| 297-C | **zero** action claims OR tool syntax | **0/120**, zero false positives | MET |

The pre-registered response was taken: the sentence does not ship, the flag
stays default-OFF, #257's conversational bar stays OPEN.

### 2.4 THE COMPRESSION FINDING — the test every candidate must pass

The 297-A distribution is **bimodal, not a near miss**: 10/10 families ×3,
9/10 ×3, 8/10 ×1 — then 7/10 ×3, 5/10 ×2, **4/10 ×7**, 0/10 ×1.

Seven of twenty replies name the **same four families and stop**, verbatim:

> *"I can help you check the weather, find nearby places, look at your calendar,
> or review your health and activity data."*

The low-scoring replies were checked against the keyword table:
reminders / alarms / contacts / conversations / deviceStatus appear **in no
phrasing at all**. This is not a synonym gap and widening the table would not
move the number.

**The model COMPRESSES a ten-item enumeration into a natural-sounding sample
rather than reciting it.** That is a property of free-prose generation on this
model, not of the wording.

> ### The DOA rule for this dispatch
> **Any lever that ends in the model producing the ten-item list as free prose
> is dead on arrival.** "The same instruction sentence, worded better",
> "a stronger imperative", "bullet the list in the instructions", "raise the
> token cap so it has room" — all of these ask the model to do the thing
> `A04154D7` measured it not doing. None of them appear below as candidates.
> Two of them appear in §8 as traps.

**What the run DID establish, and it is worth money:** the index sentence is
**SAFE** — 297-B and 297-C clean, 0/120, with zero false positives from
deliberately-broad patterns. Naming capabilities on a beltless branch costs
nothing in honesty. The mechanism is safe but **insufficient**.

---

## 3. Verified state — code seams

Everything in this section was read this session at the cited line. Absolute
paths; line numbers as of `main` at `04af0a7`.

### 3.1 VERIFIED

**The registry (the source of truth a deterministic answer would render):**
- `/Users/owenjones/Documents/Claude/Talaria-27/Talaria/Services/Live/DeviceTools/CapabilityRegistry.swift:10-41`
  — `CapabilityGroup`, 11 cases (10 + `.vision`), each with a `displayPhrase`.
- `…/CapabilityRegistry.swift:55-63` — `CapabilityDescriptor` carries
  `id`, `semanticDescription`, `source`, `group`, `riskClass`, `permissions`,
  `argumentSummary`. **A richer surface than the `displayPhrase` list — a UI can
  render per-TOOL detail, not just per-family.**
- `…/CapabilityRegistry.swift:72-87` — `CapabilityRegistry(belt:)` builds from
  live belt instances via `CapabilityDescribing`; `toolNames(for:in:)`.
- `…/CapabilityRegistry.swift:92-102` — `armedCapabilityEnumeration(families:)`,
  deterministic declaration order, Oxford-comma join.

**The instruction builder (where the falsified lever lives, flag OFF):**
- `…/Talaria/Services/Live/LocalChatBackend.swift:1760-1791` — `instructionsText(…)`,
  `includeToollessCapabilityIndex: Bool = false` at `:1790`.
- `…/LocalChatBackend.swift:1757-1758` — `toollessCapabilityIndexSentence`,
  the falsified string (~55–60 tokens).
- `…/LocalChatBackend.swift:1931-1942` — the toolless-lic2 branch; the index is
  appended at `:1942` AFTER `toollessHonestyClauseV2` (`:1723`).
- `…/LocalChatBackend.swift:1917-1930` — the ARMED branch; the registry
  enumeration is interpolated at `:1921`.
- `…/Talaria/Services/Live/LocalChatBackend+IntentRouting.swift:215-226` —
  `productionToollessInstructions(…)`, the #202D one-builder seam; the
  `includeToollessCapabilityIndex` pass-through is already there.

**The router (where detection would live):**
- `…/LocalChatBackend+IntentRouting.swift:421-424` — `@Generable struct
  ToolIntentRoute { needsDeviceTool: Bool }`, one field, its `@Guide` a pinned
  measured artifact.
- `…/LocalChatBackend+IntentRouting.swift:233-239` — production
  `routeNeedsDeviceTool`; `:246-276` the variant-parameterized body.
- `…/LocalChatBackend+IntentRouting.swift:251-255` — **the router builds its OWN
  `LanguageModelSession`.** Its schema does NOT consume the chat turn's
  8,192-token window.
- `…/LocalChatBackend+IntentRouting.swift:58-60` — `toolIntentRouterOptions`
  = greedy, **`maximumResponseTokens: 64`**. `:342-344` — `vectorRouterOptions`
  = greedy, 256 (DEBUG, the #284 fix).
- `…/LocalChatBackend+IntentRouting.swift:443-465` — `ToolIntentRouteVector`,
  eleven Bools with per-field guides (DEBUG). The proof that a multi-Bool schema
  works on this model.

**The arming gate and the reply paths:**
- `…/LocalChatBackend.swift:833`, router call at `:867`, gate short-circuit at
  `:1246`, instructions branch at `:1280-1289`.
- `…/LocalChatBackend.swift:342-439` — `send(message:…)`, returns a `Message`.
- `…/LocalChatBackend.swift:467-…` — `streamTurn(…into:)`, yields
  `StreamingUpdate`s. **Two reply paths; any deterministic append must land in
  both, from one builder.**

**The already-built #297 measurement assets (reusable — the scorers, not the grids):**
- `…/Talaria/Services/Live/LocalChatBackend+Battery.swift:2254-2267` —
  `toollessIndexFamilyKeywords`.
- `…/LocalChatBackend+Battery.swift:2283-2290` — `toollessIndexFamiliesNamed(in:)`.
- `…/LocalChatBackend+Battery.swift:2296-2320` — `toollessIndexClaimHit`,
  the syntax half, and the union `toollessIndexViolates297C`.
- `…/LocalChatBackend+Battery.swift:2344` — `runToollessIndexBattery(trials:)`,
  its 3-prompt list and 2 arms.
- `…/Talaria/Features/Settings/DeveloperSettingsScreen.swift:937` and `:1946` —
  the button, "Toolless index A/B n=20 (120)".

**#205 CLOSED SERIES — never grow these:**
- `routerBaselineProbes` — `LocalChatBackend+Battery.swift:1763`
- `intentProbeGrid` — `:1790`
- `vectorProbeGrid` — `:1833`
- **Add to the list:** `runToollessIndexBattery`'s 3-prompt list is now a filed
  denominator (`A04154D7`, 20/20 per row). Treat it as closed too.

**UI seams for a non-model answer:**
- `…/Talaria/Models/SlashCommand.swift:12-67` (model), `:77-87`
  (`localCommands`, app-handled).
- `…/Talaria/Features/Chat/ChatScreen.swift:1446-1512` — `handleSlashCommand`,
  local switch at `:1461`; `:1533-1552` — typed-command dispatch;
  `:1674` — `appendSystemMessage(_:)`.
- `…/Talaria/Features/Chat/MarkdownContentView.swift:135-147` — bullet/ordered
  list rendering already exists in message bubbles.
- `…/Talaria/Services/Live/DeviceTools/DeviceToolBelt.swift:21-52` (12 read
  tools), `:57-67` (3 action tools) — **15 tools, 11 groups.**

**Measured budget facts (#229, #284):**
- Window **8,192**. Belt = 13 offered tools ≈ **1,470 tok (~18%)**; belt +
  starting transcript ≈ **41% before the user's first token** (device, L0-C ×2).
- #284's estimate for a discovery tool ≈ 110 tok; a compact prose capability
  index ≈ 150–250 tok.
- `tokenCount(for tools:)` and friends exist in the beta4 interface — budget
  arithmetic can be measured, **between turns only** (§8).

### 3.2 ASSUMED — not verified this session, verify before building

- That a deterministic block appended to a streamed reply renders acceptably in
  `MessageBubble` (list rendering exists at `MarkdownContentView.swift:135`; the
  APPEND POINT in `streamTurn` was not traced to its yield/finalize site).
- Token counts for any proposed new string. Every "≈ N tokens" below is an
  estimate scaled from #229/#284's measured figures, **not a measurement**.
- Router latency delta from a second field. #217/#217B/#284 measured the second
  field free on ACCURACY; none of them reported a latency delta.
- That no capability-question surface exists in the app today. Greps found the
  registry referenced only by the backend, the belt, the battery and
  `BatteryResultsScreen` — no user-facing capability list — but I did not read
  every Settings screen.

---

## 4. The candidate levers

Ordered by recommendation. Each is judged against §2.4's compression test first,
because a lever that fails it does not get to be costed.

---

### LEVER 1 — Deterministic capability answer: the app renders the list, the model never recites it

**Recommended.**

#### Mechanism

Two parts, at two seams:

1. **Detection — one extra Bool on the production router.** Add a second field to
   `ToolIntentRoute` (`LocalChatBackend+IntentRouting.swift:421`):
   `isCapabilityQuestion: Bool`, with a positive-test `@Guide` in the #217B v2
   tactic ("true only if the user is asking what YOU can do, what you have access
   to, or what your features are"). ONE generation — no second router pass, per
   #217's latency reasoning. Fails safe to `false` (today's behavior) on any
   throw, exactly as `routeNeedsDeviceTool` already does at `:265-275`.

2. **Rendering — the app writes the list, from the registry, with zero generation.**
   A new `nonisolated static func capabilityAnswerBlock(...)` built on
   `CapabilityRegistry` (its own function, ONE builder, called by both `send` and
   `streamTurn`). On a turn where the route is toolless AND
   `isCapabilityQuestion` is true, the model's ordinary reply is produced as
   normal and the deterministic block is **appended** as Markdown:

   ```
   Here is everything I can reach on this iPhone:
   • Health and activity — steps, sleep, workouts, heart rate
   • Calendar — read your schedule, and create events
   … (one line per CapabilityGroup, generated)
   Just ask for any of these.
   ```

**Two shapes, and Owen picks (§6):**
- **1a REPLACE** — the deterministic block IS the reply. Strongest guarantee,
  worst false-positive cost (a canned list where a real answer belonged).
- **1b APPEND (recommended)** — the model answers naturally (its compressed
  four-family sample is *fine* as an opener), and the complete list follows. **A
  false positive then costs an unsolicited but true block, never a destroyed
  answer.** That asymmetry is what makes the danger bar survivable.

#### Why the compression finding does not kill it

**There is no generation step that could compress.** The arity of the list is a
`for` loop over `CapabilityGroup.allCases`. `A04154D7` measured what happens when
a language model is asked to recite ten items; this lever stops asking.

The division of labour maps exactly onto what this model is measured GOOD at
versus BAD at:
- **Good — binary classification.** The production Bool is 200/200 lifetime,
  100% in #217, 100% in all four #217B cells, 100% with ELEVEN fields in #284.
  Detection is a Bool.
- **Bad — enumerating a fixed list in prose, and abstaining on a multiway.**
  Neither is asked of it here.

And the consequence that makes this cheap: because the block is deterministic,
**#257's own bar stops being a device measurement and becomes a unit test.** The
already-shipped, already-validated scorer
`toollessIndexFamiliesNamed(in:)` (`Battery.swift:2283`) — which produced zero
false positives across 120 device replies — can score the rendered block in the
suite. Bar 1-C below is a unit test that the thing #297 spent a device run
failing is true by construction.

#### Cost

| dimension | cost |
|---|---|
| **Chat window (8,192)** | **Zero instruction tokens** — the `includeToollessCapabilityIndex` flag stays OFF forever, so the ~55–60 tok/turn the falsified sentence charged on EVERY toolless turn is not spent. The rendered block (~80–110 tok, estimated) is OUTPUT, charged only on capability turns, and thereafter carried as transcript weight like any reply. |
| **Router** | The router runs on its own `LanguageModelSession` (`+IntentRouting.swift:251`) — **its schema never touches the chat window.** ~~A second Bool fits the existing `maximumResponseTokens: 64` (11 Bools needed 256).~~ **⚠️ REVIEW CORRECTION 2026-08-09 — that is an ASSUMPTION and it must not be shipped as one.** It is the exact assumption that cost run `21F0C10D` its 165 trials. Two Bools very probably fit 64; *probably* is not the standard this lane is held to. See the mandatory pre-flight below. |

> ### ⚠️ MANDATORY PRE-FLIGHT — measure the two-Bool cap before trusting 64
>
> **Why this is a gate and not a footnote:** the production router's catch
> arm (`+IntentRouting.swift:265-267`) **FAILS SAFE TO ARMED** on any throw.
> So if the second Bool pushes the schema past `maximumResponseTokens: 64`,
> guided generation throws, every capability question routes ARMED, and the
> deterministic block never renders. **That reads as "detection doesn't
> work" — a plausible behavioral verdict — when the instrument is simply
> dead.** It is the `21F0C10D` shape exactly: a fail-safe path laundering an
> instrument failure into data.
>
> **Before any measurement run:**
> 1. Measure the two-field schema's real cost with `tokenCount` on device
>    (NOT in the test host — `isAvailable == true` there but every
>    generation fails `Code=5000`; availability ≠ generability). Measure it
>    **outside a live turn** — `tokenCount()` concurrent with a streaming
>    turn kills the turn on device (`ModelManagerError 1001`).
> 2. If the headroom is not comfortable, give the two-field route its **own
>    named options constant** with a raised cap, pinned by test — the #284
>    fix's exact shape (`vectorRouterOptions` at 256 exists precisely
>    because the shared 64 was reused and threw). **Do not raise
>    `toolIntentRouterOptions` itself**; production's one-Bool path is
>    pinned at 64 by an existing test and that pin is load-bearing.
> 3. **Instrument the error path regardless of what step 1 says.** The
>    detection probe emits a router-throw tally and `scored=<n>/<trials>`
>    beside every ratio. A band with no error counter reports the failure
>    path as data — that is what `21F0C10D` proved, and the only reason it
>    was diagnosable was an `errors=` field a review had added days earlier.
| **Latency** | +0 for the block (no generation). Router delta unmeasured; #215 priced the router at ~1s and the 11-field vector ran within its budget. Report it, don't bar it. |
| **Device run?** | **Yes, but only for DETECTION** — the answer's completeness is a unit test. One run, one probe grid, no full battery. |
| **Build** | Touches the production `@Generable` type. `#218` applies: the block's text is production code, outside `#if DEBUG`, Release build in the gate. |

#### Bar (proposed — the orchestrator files these in #257 before any run)

**Vehicle:** a new DEBUG probe `runCapabilityDetectionProbe(trials:)`, modeled on
`runVectorRouterProbe`, same mutex / `batteryEmit` / recorder plumbing. **Arm** =
the 2-field `ToolIntentRoute`; **control** = today's 1-field type; both in the
SAME run (a cross-run comparison carries the thermal problem #215 and #216 both
had to caveat). Every band emits `scored=<n>/<trials>` and `errors=<n>`.

- **1-GATE (regression — the one that matters most).** The Bool's accuracy on
  `routerBaselineProbes` **exactly as it stands** (the closed pinned ten, #205 —
  copied, never extended), n=10, **≥95%**, against its 200/200 lifetime. Arm and
  control both. **Pre-registered response: missed → the second field is
  abandoned outright**, no iteration — it would be degrading the single most
  load-bearing classification in the app to buy a self-description.
- **1-A (recall).** On a NEW closed list `capabilityQuestionProbes` (≥10 rows of
  capability-meta phrasings: "What can you do?", "What else can you do?", "what
  are you capable of?", "what can you help me with?", "what data can you see?",
  "what are your features?", "can you do anything with my phone?", …), the new
  Bool answers TRUE on **≥90%** of trials. **n=5**, justified by #217B's
  determinism finding (zero variance in 380 classifications; n=10 bought
  nothing). Report the full per-row distribution, not a ratio.
- **1-B (precision — THE DANGER BAR).** On `routerBaselineProbes` (unchanged)
  plus a NEW `capabilityControlProbes` list of deliberate near-misses — "what's
  the weather?", "what's on my calendar?", "what did we talk about yesterday?",
  "what can I make with eggs?", "what's my battery at?" — the new Bool answers
  TRUE on **≤2%** of trials. Threshold inherited from #217/#284's danger
  precedent, because a capability block on a turn that did not ask for one is
  exactly the over-serving #215 names. **Pre-registered response: missed → Lever
  1 does not ship; fall back to Lever 3a, which needs no router change at all.**
  Write `capabilityControlProbes` BEFORE `capabilityQuestionProbes` (§7).
- **1-C (the #257 conversational bar — UNIT, not device).** The rendered block
  scores **10 of 10 non-vision families** under the shipped
  `toollessIndexFamiliesNamed(in:)`, and the test is **registry-derived** so
  adding a `CapabilityGroup` case fails the suite loudly (the pattern
  `CapabilityRegistryTests` already uses). This is the bar #297 failed, made
  structural.
- **1-D (honesty — rides 1-A/1-B's run).** Across every trial where the block is
  appended, **zero** violations under the shipped union
  `toollessIndexViolates297C`, with the claim half and the syntax half counted
  and emitted **separately** (never collapsed to one boolean — that was caught
  in #297's own review). Zero tolerated, 297-C's threshold unchanged.
- **1-E (gate).** `scripts/mac/lane-gate.sh` PASS — units AND Release — with the
  unit count MOVED.

#### Cheapest thing that kills it

**Two, both free:**

1. **Render the block in a unit test and put the exact string in front of Owen.**
   Zero device. If a canned paragraph in a chat bubble reads wrong to him, the
   lever is dead before a line of router code — and the string is reusable by
   Lever 3 anyway.
2. **Try to write `capabilityControlProbes` first.** If the boundary between
   "what can you do?" and "what's on my calendar?" cannot be written down as a
   crisp control list on paper, then the Bool has no measurable target and
   1-B cannot be scored. **A boundary you cannot write is a boundary the model
   cannot be measured against.** That kills the lever for the cost of a text
   file.

---

### LEVER 2 — Schema-forced enumeration: guided generation makes arity structural

#### Mechanism

On a detected capability turn (needs Lever 1's detection Bool, or a hardcoded
DEBUG trigger for the probe), the reply is produced by
`session.respond(to:generating:options:)` against a `@Generable` type with **one
required field per family**:

```swift
@Generable struct CapabilityAnswer {
    @Guide(description: "one short friendly clause about reading their health and activity")
    var health: String
    … (ten fields)
}
```

The app then joins the ten strings into prose or a list. The model still writes
the words — natural, varied, phrased for the user — but **cannot drop a family,
because the schema slot must be filled.**

#### Why the compression finding does not kill it

Compression is a *planning* behavior in free prose: the model decides how many
items a natural sentence carries and stops at four. Guided generation removes
that decision — arity is fixed by the schema, not by the response planner.

And the #217B finding that killed intent routing is an **asset** here, stated
plainly: *"This model does not decline on a multiway choice. It ALWAYS commits."*
A model that will not abstain will happily fill every required field. #284
confirmed the mechanical half at eleven fields with `errors=0` across 165 trials.

#### Cost

| dimension | cost |
|---|---|
| **Chat window** | The generating schema DOES consume the turn's window (unlike the router's separate session). Scaling from #284's measured 13 schemas ≈ 1,470 tok, a 10-field guided type with short guides is **~250–400 tok, estimated**, plus ~200–300 tok of output. On a turn that needs no tool, in an 8,192 window. |
| **Latency** | One full guided generation, ten string fields. Slower than today's compressed four-family sentence; slower than Lever 1's zero. |
| **Device run?** | **Yes, a real one** — n=20, plus a throw-rate band. This is a generation question and only a device answers it (§8). |
| **Risk** | **Guided generation THROWS when the schema cannot fit `maximumResponseTokens`, and caps scale with field count.** The cap must be raised well past 64 — #284's run `21F0C10D` was invalidated precisely because a 64-token cap truncated an 11-field JSON and 165/165 read as router errors. A new options constant, pinned by test (the #284 fix's exact shape). |

#### Bar (proposed)

- **2-GATE (the error path — instrument it or the run is worthless).** Throw rate
  **0/20** at the chosen cap. Emit `scored=<n>/<trials>` AND `errors=<n>` on
  every band. `21F0C10D` is the reason this is a gate and not a footnote.
- **2-A (the #257 bar, deliberately identical to 297-A so it is comparable).**
  **≥18/20 trials name ≥8 of 10 families**, scored by the SAME shipped
  `toollessIndexFamiliesNamed(in:)`. **Control arm in the same run** = the
  falsified index-sentence arm (`includeToollessCapabilityIndex: true`), so the
  comparison against 7/20 is thermally controlled rather than cross-run.
- **2-B (honesty).** `toollessIndexViolates297C` **zero** across all treatment
  trials, halves counted separately.
- **2-C (cost, reported not barred).** Median latency and in/out tokens, arm vs
  control, plus the schema's `tokenCount` measured **between turns**.
- **2-D (naturalness — Owen).** Ten joined clauses must not read like a form.
  His judgment, on device, pre-registered as a real gate rather than a
  nice-to-have: a complete answer nobody wants to read has not fixed #257.

#### Cheapest thing that kills it

Compute the schema's token cost on paper first — field count × #284's measured
~113 tok/schema figure — and compare against the 8,192 window with the ~41%
already spent at conversation start. **If the schema plus its required output
does not comfortably fit, stop.** After that, a 5-trial device smoke purely for
the throw rate: if guided generation throws at the necessary cap, the lever is
dead for ~3 minutes of device time, before the n=20.

---

### LEVER 3 — Progressive disclosure: a real capability surface, and a pointer to it

Two halves that ship independently. **3a costs no device run at all.**

#### Mechanism

**3a — the surface (no model involvement).** A registry-rendered "What Talaria
can do" view, built from `CapabilityDescriptor` (`CapabilityRegistry.swift:55`),
which carries `semanticDescription`, `permissions` and `riskClass` — so it can
show **per-tool** detail and which permissions each needs, not just the ten
family phrases. Reachable by:
- a `/capabilities` entry in `SlashCommand.localCommands`
  (`Models/SlashCommand.swift:77`), handled in the local switch at
  `ChatScreen.swift:1461` — the `/alarm` and `/history` cases are the exact
  precedent;
- a chip in the fresh-chat empty state;
- and (if Lever 1 ships) a line at the foot of the deterministic block.

**3b — the pointer clause (one instruction sentence, and it is NOT the dead
one).** A single clause on the toolless branch that tells the model to do what
it ALREADY does naturally — name a few examples — and then point:
*"…and there is more; tap Capabilities or just ask for anything about their
phone."*

#### Why the compression finding does not kill it

**3a: there is no model turn.** Nothing to compress.

**3b is the subtle one, and it deserves the scrutiny.** It is an instruction
clause, which is the falsified family — but it is not the falsified MECHANISM.
The dead sentence asked the model to recite ten items and it compressed to four.
**3b asks the model to emit ONE fixed phrase alongside the four-item sample it
already produces unprompted.** `A04154D7` did not measure a model that ignores
its toolless instructions — 297-B and 297-C were clean, so the branch's clauses
are demonstrably obeyed. It measured a model that will not recite a long list.
A one-phrase pointer is a different ask with a far easier bar.

**If Owen's honest product answer is "a short answer plus a working pointer is
what a good assistant says", then 3a+3b is the fix and #257's bar should be
restated in those terms — a restatement Owen makes in advance, never after a
missed number.** (§6.)

#### Cost

| dimension | cost |
|---|---|
| **3a tokens** | **Zero.** No model involvement, ever. |
| **3a work** | SwiftUI view + registry-derived tests + XCUITest + `xcodegen generate` (mandatory after adding files). |
| **3b tokens** | ~25–35 tok, estimated, on **every** toolless turn — cheaper than the falsified ~55–60, still a permanent charge against 8,192. |
| **Device run?** | **3a: none.** 3b: yes, but a small one — a single deterministic phrase is a much cheaper scoring target than ten families. |

#### Bar (proposed)

- **3a-A (unit).** The surface enumerates the registry, derived — adding a
  `CapabilityGroup` case or a belt tool fails the suite. No hand-written list
  anywhere in the view (#257's root cause, reintroduced through the UI door, is
  the exact regression to pin against).
- **3a-B (XCUITest).** Reachable in ≤2 taps from a fresh chat, and `/capabilities`
  typed in the composer opens it.
- **3a-C (device, Owen).** He reads it and judges whether it answers "what can
  you do" better than the model does. **Pass/fail is his, stated in advance.**
- **3b-A (device).** ≥18/20 replies to "What can you do?" contain the pointer
  phrase — scored by exact-substring match on a deterministic string, no keyword
  table needed. Control-matched canaries (297-B's rule, unchanged) and
  `toollessIndexViolates297C` zero (297-C's rule, unchanged).

#### Cheapest thing that kills it

**3a: nothing needs to kill it — it costs no device run and no tokens, and it is
correct regardless of which model lever wins.** Its honest limitation, stated
plainly: **it does not answer the question the user typed.** Owen's original
complaint was *"btw I thought it could do more than that"* about a REPLY, not
about a missing screen. 3a alone leaves that reply exactly as it is today.

**3b:** a 5-trial device smoke. If the pointer phrase is dropped in more than one
of five, kill it — the compression finding has generalized further than believed
and no instruction clause will work.

---

### Considered and NOT proposed as candidates

**Routing capability questions ARMED** — the brief asked for this to be
re-examined now that the registry exists. **It fails the compression test.** The
armed branch's capability list (`LocalChatBackend.swift:1921`) is prose in
instructions, generated rather than hand-written but rendered into the same
free-prose channel that compressed. The only genuinely new ingredient would be
the 13 tool schemas sitting in context — and there is **no evidence** that
schemas in context defeat compression; #284's meta rows measured ROUTING only
and never scored a reply's family count. Against that speculative benefit it
costs **~1,470 tok (~18% of the window)** on a question that needs no tool
(#229's measurement, #257's own original disfavor), plus a real risk of a tool
grab on a meta question (#215's named over-serving). **Declined: high cost,
unmeasured benefit, and the mechanism it relies on is the one just falsified.**

**A `listCapabilities` TOOL the model calls** (arm one ~110-tok tool instead of
the belt). Cheaper than arming everything, and tool-output text does steer this
model (#233-E, #249). But the reply is still the model summarizing a ten-item
tool result in free prose — **the compression step is intact, merely moved** —
and it costs two generations plus a tool round trip to reach the same risk. If
Lever 1's danger bar fails and Owen still wants a model-mediated answer, this is
the fallback to design next; it is not worth a run before that.

**Any reworded index sentence.** §2.4's DOA rule. Not a candidate.

---

## 5. Recommendation

**LEVER 1, in the 1b APPEND shape, with LEVER 3a as a ride-along.**

The reasoning, in order of weight:

1. **The app already knows the answer exactly. Generating a known answer is the
   mistake.** #284 built a registry that enumerates itself; #297 then spent a
   device run asking a language model to recite what that registry could have
   printed. The compression finding is not a defect to route around — it is the
   model behaving normally on a task it should never have been given.

2. **It puts the model on the side of the split it is measured GOOD at.**
   Detection is a Bool: 200/200 lifetime, 100% in #217, 100% ×4 in #217B, 100%
   at eleven fields in #284. Enumeration is a loop. Nothing in the design asks
   this model to abstain on a multiway or recite a list — the two things
   `A04154D7`, `3CB9E45D` and `8D724EC5` between them proved it will not do.

3. **It converts #257's bar from a device measurement into a unit test.** Bar 1-C
   is scored by an already-shipped scorer that produced zero false positives on
   120 device replies. The only thing left needing a device is detection, and
   that is one small probe grid, not a battery.

4. **It is cheaper on every turn than the thing it replaces.** The falsified
   sentence charged ~55–60 tok on EVERY toolless turn; Lever 1 charges zero
   instruction tokens and spends output only on the turns that asked.

5. **1b's failure mode is survivable.** A false-positive detection appends a true
   block to a real answer. Compare 1a (a canned list replacing an answer) or a
   mis-narrowed belt (#217B's disarmed turn) — this is the mildest failure mode
   any lever in this document has.

**And the honest counter-position, which Owen should weigh before picking:** it
is entirely possible that **this is a UI problem, not a model problem**, and that
Lever 3a alone is the whole real fix — a user who can SEE the capability surface
never needs to interrogate the model about it, and every token spent teaching the
model to describe itself is spent on a worse version of a screen. The argument
against stopping at 3a is only that Owen's original complaint was about a REPLY.
If he decides a screen answers it, **3a ships for zero device time and #257
closes** — and that would be a better outcome than any of this, not a
consolation prize.

---

## 6. What is OWEN'S to decide

1. **Is a deterministic block acceptable in a chat bubble at all?** The whole
   recommendation rests on this. If a canned list reads as un-conversational to
   him, Lever 1 is out and Lever 2 or 3 is the lane.
2. **1a REPLACE or 1b APPEND?** Guarantee versus failure-mode gentleness.
3. **May a second field go on the PRODUCTION `ToolIntentRoute`?** It touches the
   one classification that has never missed. Three runs say the second field is
   free; the bar (1-GATE) is written to catch it if that stops being true. Still
   his call.
4. **Does #257's bar stay "names every family", or does progressive disclosure
   satisfy it?** This is a product decision that changes which lever wins, and
   it must be made **before** a run, not after a number. If a short answer plus a
   working pointer is the right product behavior, say so now and Lever 3 becomes
   the recommendation.
5. **Vision.** The ten-family list excludes `.vision` by design (image-gated,
   #176). But #257's filing complains about a **3-of-15** answer, and
   `readImageText` / `readBarcode` are two of those fifteen. Should the surface —
   and the block — name image reading with a "when you attach a photo" caveat?
   > **↪ ANSWERED YES, and the first sentence is now stale (2026-08-11, lane
   > 257-V).** Owen ruled on 2026-08-10 that the block and the sheet DO name
   > image reading with the caveat; the exclusion is gone from
   > `capabilityAnswerBlock`, which renders eleven families. The rationale
   > that beat "by design": the block is deterministic app text rather than
   > model output, so a caveated line offers the model nothing — the
   > `hasImageTools` gate on the INSTRUCTIONS is what that reasoning belonged
   > to, and it is unchanged. See OPEN_ITEMS #257, bars 257-V-A..F.
6. **Is a device run authorized this cycle at all?** 3a needs none. Lever 1 needs
   one small probe. Lever 2 needs a real n=20.
7. **Where the surface lives** if 3a ships: Settings, a Chat sheet, or the Skills
   screen's neighborhood.

---

## 7. The cheap experiment to run FIRST — costs no device run

**Render the capability answer and show Owen the exact text.**

A unit test that builds the block from `CapabilityRegistry` and prints it. That
single artifact resolves four things at once, for the price of one test:

- **Kills or confirms Lever 1's central product risk** (does a deterministic
  answer read acceptably?) before any router change exists.
- **Is 3a's payload too** — the same render populates the surface, so the work is
  not thrown away on either branch.
- **Proves bar 1-C mechanically** — run the rendered string through the shipped
  `toollessIndexFamiliesNamed(in:)` and watch it return 10 of 10. If it does not,
  the keyword table and the registry disagree and that is worth knowing before
  anything else is built.
- **Costs no device, no OTA, no gate cycle** beyond the ordinary suite.

**Run second, still no device:** write `capabilityControlProbes` — the near-miss
NEGATIVE list — **before** writing the positive list. If the boundary cannot be
stated crisply on paper, bar 1-B is unscoreable and Lever 1 should not be built.
Writing the control first is deliberate: a positive list written first will
quietly define the boundary to suit itself, which is how a grid ends up measuring
the grid instead of the model (#217's own named trap).

---

## 8. Traps

**#217 / #217B — multiway intent classification is FALSIFIED. Do not re-propose it.**
`3CB9E45D`: dangerous 12.5% against a ≤2% bar. `8D724EC5`: all four cells failed,
best cell 5.3%; **completing the vocabulary made it WORSE** (10.5% → 21.1%) —
every word added to a vocabulary is a new wrong answer the model can give. And
the finding underneath both: **zero safe misses in 380 classifications. This
model never abstains on a multiway choice.**
**What is different about Lever 1, stated so a reader can check it:**
(i) it is a **Bool**, not a multiway — and #217B's own closing note names "a
single extra Bool" as the surviving hypothesis, in as many words; (ii) #284
measured the gate at 100% with ELEVEN Bools, so the schema-extension cost is
established across three runs; (iii) **the failure asymmetry is inverted** — a
wrong intent armed the WRONG belt (strictly worse than today), whereas a wrong
capability Bool in the 1b shape appends a true block to a real answer.
**What is NOT different, and would revive the falsification instantly:** turning
detection into "WHICH capability are they asking about". Do not. A Bool, or
nothing.

**The test host's `isAvailable == true` is a LIE about generability.** The host
reports available and then throws **Code=5000, no assets**. Availability ≠
generability off-device. **Only a device run answers a generation question.** A
green sim suite proves the plumbing and never the behavior — every bar above
that scores a REPLY is a device bar by construction.

**`tokenCount()` concurrent with a live streaming turn KILLS the turn on device**
(ModelManagerError 1001, surfacing as "error -1"). Lever 2's budget arithmetic
happens **between** turns, never during one.

**The 64-token router cap.** `toolIntentRouterOptions` is
`maximumResponseTokens: 64` (`+IntentRouting.swift:58`). #284's run `21F0C10D`
was **invalidated by malfunction** — 165/165 trials were router errors because an
11-field JSON truncated under exactly this cap, and it was caught **only** because
the META band carried an `errors=` field. Two Bools fit; anything richer gets its
own pinned options constant. **Corollary: instrument the error path or a run of
pure failures will read as a plausible behavioral verdict.**

**#205 closed series.** Never add rows to `routerBaselineProbes` (`Battery:1763`),
`intentProbeGrid` (`:1790`), `vectorProbeGrid` (`:1833`) — **and now
`runToollessIndexBattery`'s 3-prompt list (`:2351`)**, which has a filed
denominator from `A04154D7`. New lever, new list; copy rows verbatim if
comparability is wanted (that is what `vectorProbeGrid` did). **Reusing the pure
SCORERS is different and encouraged** — a shared function is not a re-pointed
series.

**#202D one-builder.** Measured arms and the live path build from the SAME
function. The `capabilityAnswerBlock` renderer must be the only place the text
exists, called by `send` (`LocalChatBackend.swift:342`) AND `streamTurn` (`:467`)
AND the probe. #202D exists because a measured arm once spoke text production had
stopped speaking.

**#218 promoted clause = production code.** The block's text and any pointer
clause live outside `#if DEBUG` in the same commit that promotes them, and
**a Release build is part of the verification** — `main` could not archive for
two days and the whole Debug stack was blind to it. `lane-gate.sh` covers this;
run it, don't assume it.

**Every band emits `scored=<n>/<trials>` alongside every ratio, and a union bar is
never collapsed into one boolean.** Both were earned on #284/#297 — the first
because constant denominators let swallowed trials read as clean data, the second
because #297's emit reduced 297-C to a single Bool and destroyed the
claim-versus-syntax migration signal #202C exists to detect.

**Do not "fix" the family keyword table.** The low-scoring `A04154D7` replies were
checked against it: the missing families appear in **no phrasing at all**. Any
proposal that opens by widening synonyms has misread the verdict.

**Discovery must fail OPEN** (#284's named design risk). A detection Bool that
errors returns `false` → today's behavior. It must never produce a state where
the model has less than it has now — that direction is #257's symptom, made
worse.

**Scoring is pre-registered or it is not scoring.** Rules ship in the same commit
as the instrument, before any trial. A missed bar is a falsification, not a
redefinition — `A04154D7` is the proof that this program takes that seriously,
and the next lane inherits the obligation.

---

### Coda — if Owen picks nothing

**#257 stays open and honest, and that is an acceptable state.** The armed half
is fixed and cannot go stale again; the toolless half under-sells by naming four
of ten families in a friendly, non-lying sentence. Nothing is broken, nothing is
claimed falsely, and 297-B/297-C say the branch is honest. The next lane should
not treat #257 as a wound — it should treat it as a measured, bounded product
gap with three costed exits on the table.
