# FABLE — T27 #93 / #101: continuity fabric close-out + durable-facts viability

**Label:** `FABLE`
**Items:** **#93** (P1 continuity fabric — journal primary, hop transplant, compose outbox) ·
**#101** (cross-chat memory / durable-facts layer)
**Read at:** working tree `35c6234` (branch `t27-295-expiration-recovery`; `OPEN_ITEMS.md` was
dirty under concurrent lanes while this was written — every tracker quote below is from the file
as read this session).
**Goal:** give both items an executable shape — a truthful, evidence-backed status for #93 with a
split recommendation, and a viability verdict for #101 against the lost #284 premise and the
8,192-token window, with candidate shapes whose token cost and cheapest falsifier are named.

**This brief writes no production code, edits no Swift, and edits no `OPEN_ITEMS.md`.** Bars below
are **PROPOSED** — per the post-#215 convention they belong in the OPEN_ITEMS entry, filed by the
orchestrator, before any run.

---

## 1. #93's true status

**Headline: #93 is BUILT, MERGED, and code-verified end to end. What remains is VERIFICATION, not
construction — plus one claim in the entry that the code has since falsified.** Every mechanism the
entry describes is present at HEAD and has been maintained by four later lanes (#97, #114/M-1,
#240, #283 3A), which is the strongest available evidence that it is load-bearing rather than dead.

| # | Sub-part | Shipped? | Evidence (file:line / commit) | Remainder |
|---|---|---|---|---|
| 1 | Journal = durable primary; entries re-derived from the settled transcript | ✅ | `Talaria/Models/ConversationJournal.swift` (141 ln); `Talaria/Stores/ConversationJournalStore.swift:50` `sync(with:lastExchangeViaActiveHop:)`; **8** sync call sites in `ChatStore.swift` (482, 559, 1067, 1211, 1569, 1812, 2141, 2472); built in `5a29941` | none |
| 2 | `apiSessionId` decoupled → per-hop handle + `seenEntryCount` waterline | ✅ | `ConversationJournal.swift:41,89,137`; `SessionsHermesClient.swift:1118` `ensureHopForTurn()`; `ConversationJournalStore.swift:77` `beginHop` | none |
| 3 | Hop persists across relaunch; 404 on a **reused** hop swaps + retries ONCE | ✅ **and extended** | sync path `SessionsHermesClient.swift:306-315`; stream path `:461-470`; `discardStaleHop()` `:332`; **runs plane** `SessionsHermesClient+RunsTransport.swift:355-375` (#283 3A carried it forward) | device-unverified |
| 4 | Transplant at every hop: condensed brief, verbatim-tail fallback, 1,500-tok budget by measurement | ✅ | `Talaria/Services/Support/ContextTransplanter.swift` (208 ln — binary-search tail fit `:97-118`, non-additive ratchet `:120-146`, `primingText` `:200`); `LocalIntelligenceService.swift:194` `condensedContextBrief` (guided gen, temp 0.2 `:49`) | **fidelity gate never RUN** (row 10) |
| 5 | Priming posts over SSE so `run.completed` usage is captured | ✅ | `SessionsHermesClient.swift:1178` `postPrimingTurn` | none |
| 6 | Local/PCC/voice turns leave the waterline behind → next Hermes turn re-hops | ✅ | `ConversationJournalStore.swift:62-67`; `ChatStore.swift:1067` (`lastExchangeViaActiveHop: finishedViaHermesHop`); voice `ChatStore.swift:1562-1569` | device-unverified (checklist **d**) |
| 7 | **"`switchModel` ends the hop — a model switch is a brain hop now"** | ❌ **REMOVED — the entry is now false** | `SessionsHermesClient` defines **no** `switchModel`; the protocol default returns nil (`HermesClientProtocol.swift:204`). Model choice rides **per-turn in the body** as the #223 Lane 5 lock (`ChatTurnBody` `provider`/`model`/`require_model_lock`, `SessionsHermesClient.swift:1906-1953`). `endHop()` has exactly **three** callers: `:311`, `:464`, `+RunsTransport.swift:369` (stale-hop 404) and `:774` (`clearConversation`) | **checklist item (c) is dead as written** — see §3-C2 |
| 8 | Offline compose outbox: `.unreachable` → `.queued` row + persisted outbox, FIFO drain on reachability | ✅ **and extended** | `Talaria/Models/ComposeOutboxState.swift`; enqueue `ChatStore.swift:959-975`; drain `:1966-2016`; reachability trigger `:1932-1935`; **#240** added the delivered-turn adoption predicate `:1990` | attachment turns still fail honestly (v1 limit, never revisited); checklist **e** |
| 9 | Priming cost in receipts: notice row, PRIMING line, cost estimate | ✅ | `Message.swift:121` `isContextPriming`; `StreamingUpdate.swift:47` `.contextPrimed`; totals `ChatStore.swift:183-205`; sync/voice receipt `ChatStore.swift:1582-1614`; StatusCard `StatusCardView.swift:97-109`; cost `TurnReceipts.swift:105-108` | checklist **f** |
| 10 | Identity-churn fix — merge preserves the LOCAL conversation UUID | ✅ | `ChatStore.swift:2578` `mergeConversationMetadata`, id-preservation branch at ~`:2695` ("the merged thread keeps the local id") | none |
| 11 | Tests — `ContinuityFabricTests` (deterministic) + `CondenserFidelityTests` (acceptance) | ✅ built | `TalariaTests/ContinuityFabricTests.swift` (670 ln, grown by #240 +5); `TalariaTests/CondenserFidelityTests.swift` (218 ln) | **`CondenserFidelityTests` has never RUN** — it self-gates on a real model-condensed probe (`:52-59`) and every gate run is on the simulator |
| 12 | "Next Mac session" steps 1–2 (merge order, `xcodegen`, CLI build, suite) | ✅ done 2026-07-13 | PR #61 merge `5ab3477`; regen `828ecf4`; post-merge fix `818d1be` — the 2026-07-13 audit blockquote already says so | **the stale checklist was never removed from the body** |
| 13 | "Next Mac session" step 4 — reconcile `primingText` with the probe's validated phrasing | ❌ never done | `talaria-probe/probe.py` lives on OJAMD (`C:\Users\Owen\talaria-probe\probe.py`), not in this repo; no note anywhere records a comparison | cheap, needs OJAMD access; may simply be closed as not-worth-doing |
| 14 | **Device checklist (a)–(f)** | ❌ **never run, not once** | `dispatch/DEVICE-PASS-RUNNING-LIST.md:663-691` Group 7, added 2026-08-06 (`fa982f1`); its own header says "genuinely never run once" | 5 of 6 items still valid; **(c) must be struck or rewritten** |

**Score: 11 of 14 sub-parts shipped and standing; 1 shipped-then-removed (row 7); 2 never started
(rows 13, 14).** No construction work remains inside #93's original scope.

### Recommendation: SPLIT (per #268 — named work gets a number the day the decision is made)

#93 as written is an 80%-shipped item wearing a 🔧 and a stale "Next Mac session" checklist. That
is a board problem: a reader who opens it is told to merge a branch that merged four weeks ago.
Proposed disposition — **Owen's call, not mine**:

- **#93 → ✅**, body corrected per the close-out rule (§3), closing note recording that every
  mechanism is code-verified at HEAD and maintained by #97/#114/#240/#283.
- **New successor A — "Continuity fabric device pass"**: Group 7 items **(a), (b), (d), (e), (f)**,
  batched with Group 6 (both need host-side gateway stop/restart). ~25–30 min. Item **(c)** struck
  or rewritten per §3-C2. This is the oldest owed verification on the board.
- **New successor B — "`CondenserFidelityTests` has never RUN"**: a **device** suite bar, not a Mac
  bar (§3-C4). Cheap once someone runs the suite on `whoGoesThere`.
- **New successor C (optional, low priority) — "compose outbox: attachment turns have no durable
  wire form"**: still true, deliberately deferred in v1, never re-examined.

If Owen prefers fewer numbers, the minimum honest alternative is: keep #93 open but **rewrite its
header and body to say "verification owed, build complete,"** delete the merge checklist, and strike
item (c). The one thing that must not happen is leaving row 7's falsified claim in place — the
device pass would then run a check that cannot pass and read the result as a regression.

---

## 2. Verified state

### VERIFIED — read at HEAD this session

- Every `file:line` in the §1 table.
- **The belt today is 15 installed tools** (12 read + 3 action, `DeviceToolBelt.swift:33-67`), of
  which **13 are offered on a non-image turn** — `ImageTextTool` and `BarcodeReaderTool` are
  `ImageDependentTool` and withheld by `offeredTools(from:hasImageInContext:)` `:88-91`. This
  matches the "13 tool(s)" in #228's archived measurement, so that measurement's belt shape is
  still current.
- **The window is read live, never hardcoded**: `LocalChatBackend.activeContextSize()` `:314-323`
  returns `model.contextSize` (8,192 on-device) or PCC's when the PCC tier is confirmed.
- **A routed-toolless turn costs 0 belt tokens** — `effectiveOfferedTools` returns `[]`, and the
  budget instrument reports `0` rather than "—" (`LocalChatBackend.swift:1004-1008`).
- **`tokenCount()` is already fenced away from live turns.** `recordSessionBudgetIfVerbose` captures
  values synchronously during the turn; the tokenizer round-trips run only in
  `flushSessionBudgetMeasurements()` **after** the turn ends (`:947-1017`), with the
  ModelManagerError-1001 hazard written into the comment. Any new measurement must use this queue,
  not a fresh call site.
- **The `fullBelt=` contrast line ships** (`sessionBudgetLogLine` `:1030-1051`) and its comment
  literally names **#101** as its purpose (`:981`, `:1046`).
- **One instruction seam, both branches.** `effectiveInstructionsText(hasImageInContext:)`
  `:1280-1304` is the single origin for armed and toolless instructions alike; `sessionBlueprint`
  `:1063-1138` is the single place anything is appended to it (today: `condensedMemoryPreamble` +
  condensed memory, capped at `condensedMemoryTokens = 1024`, `:95`).
- **Sessions are rebuilt when the offered tool set changes** (`preparedSession` `:873-887`), and the
  route flips per turn — so instructions are rebuilt often in practice, not once per conversation.
- **A durable multi-conversation local corpus EXISTS**: `SwiftDataLocalSessionStore` (#190),
  `Talaria/Services/Support/SwiftDataLocalSessionStore.swift` — `LocalSessionRecord` stores the
  **full encoded transcript** (`transcriptData`), `conversation(withID:)` returns it whole
  (`LocalSessionStoring.swift:34`). Wired at `AppContainer.swift:572` / `ChatStore.swift:271`.
- **A cross-chat retrieval tool EXISTS and is already armed**: `ConversationSearchTool`
  (`DeviceMediaTools.swift:272-367`), capability group `.conversations`
  (`CapabilityRegistry.swift:19`). **But its past-session corpus is titles + previews only**, drawn
  from the Spotlight donation cache (`AppContainer.swift:944-953`), and it is gated on
  `spotlightIndexingEnabled` — the tool says so honestly in its own no-match text (`:355-358`).
- **A fact extractor EXISTS**: `LocalIntelligenceService.condensedContextBrief` `:194-231` — guided
  generation into a facts list, with corrections-at-latest and prune-distractors already in its
  instructions, temp 0.2 / 1024 max tokens.
- **On the runs plane, history rides the request body** (`+RunsTransport.swift:50,102-123`, N4) —
  so anything injected into a Hermes turn there needs no server change.
- **#284 shipped its registry, not selective arming.** #284's own verdict note: gate MET at 100%,
  **dangerous MISSED at 4.76%** (5/105) against the pre-registered ≤2%, in-scope exact-set MISSED at
  37.5%; pre-registered response applied — stages 1–2 shipped, arming stays full-belt, "**Reclaim
  … n/a** — arming did not ship, nothing narrows."
- **#101's entry already carries the correction** (2026-08-08 close-out note): "no context is
  freed — the sequencing constraint's premise … did not materialize."

### ASSUMED — not re-measured here, flagged so nobody promotes it

- **~1,470 tok belt / ~1,859 tok starting transcript / ~4,863 free of 8,192.** These are #228's L0-C
  device numbers from 2026-08-03 (captured twice, identically, Release + verbose). The belt's
  **count** is unchanged (13 offered, verified above), but tool **descriptions** have been touched
  since by later lanes; I did not re-run the measurement. Treat as the right order of magnitude, not
  as a current reading. The `fullBelt=` line makes a fresh number free on any verbose device run.
- **The ~18% / ~41% framing.** Same provenance, same caveat, and #284's own scoping correction
  applies: it is an **armed-turn** cost, not an every-turn cost.
- **That the current OTA build on the phone matches HEAD.** The device queue's batch header says the
  phone needs a re-stage past OTA 2250; I did not verify what is installed.
- **That `CondenserFidelityTests` would PASS on device.** Its gate has never run. Its design is
  sound — it probes the real condensation path rather than trusting `isModelAvailable` — but a
  suite that has never executed is a suite of unknown colour.

---

## 3. ⚠️ Tracker corrections

Corrections go **upstream, to the stale claim's own home**, per the close-out rule. Seven, and the
first two are load-bearing.

**C1 — #93's body still tells the reader to merge a merged branch.** The "Next Mac session" block
(steps 1–2: merge order, `xcodegen`, CLI build) was completed on 2026-07-13 by PR #61 (`5ab3477`).
The 2026-07-13 audit blockquote at the top of the entry **says this in so many words** and the body
below it was never edited. Two contradictory instructions in one entry, thirteen months of reads
apart. Fix: delete or strike steps 1–2 and 3's preamble, keep step 3's checklist (it moved to the
device queue and is still owed), and resolve step 4 (§C7).

**C2 — "`switchModel` ends the hop … a model switch is a brain hop now" is FALSE at HEAD, and it
breaks a device check.** `SessionsHermesClient` has no `switchModel`; the protocol default returns
nil (`HermesClientProtocol.swift:204`); the model pick rides per-turn in the body as the #223 Lane 5
lock. `endHop()`'s only callers are the three stale-hop-404 sites and `clearConversation`.
**Consequence:** device checklist item **(c)** — "model switch mid-conversation → next turn hops
with notice, new model answers WITH context" — tests a mechanism that no longer exists. It cannot
pass, and a runner who does not know that will file a false regression.
`dispatch/DEVICE-PASS-RUNNING-LIST.md:678-680` quotes it verbatim and inherits the defect. Fix in
BOTH places. **Proposed rewrite of (c), which is falsifiable against the current mechanism:**

> **(c′)** Change the model pick mid-conversation, then send. **PASS:** the SAME hop is reused —
> **no** priming notice appears — and the reply is attributed to the newly picked model. (The pick
> is a per-turn body lock, not a hop; a priming notice here would be a REGRESSION, not a pass.)

**C3 — #101's ⛔ SEQUENCING CONSTRAINT still reads as live instruction.** The blockquote says "do
not open this lane before #284 … #284 exists to RECLAIM that space; this item would SPEND it," and
the correction that voids it sits *below* it as a separate note. A reader who stops at the ⛔ — and
the ⛔ is visually the loudest thing in the entry — gets an instruction whose premise is dead. Fix:
strike the ⛔ in place with a dated supersession line, rather than leaving the repair downstream.

**C4 — "the Mac run is the acceptance gate" (#93 body, twice; `CondenserFidelityTests.swift:18`) is
wrong, and it is why this gate has never run.** The suite self-enables only when a trial composition
is genuinely model-condensed (`onDeviceModelAvailable()` `:52-59`) — a deliberately honest probe,
since `isModelAvailable` is optimistic. The **simulator has no model**, and every gate run
(`scripts/mac/lane-gate.sh`) is a simulator run. So this is a **DEVICE** bar: a full-suite run on
`whoGoesThere` while corded. Naming it "the Mac run" has kept it un-runnable for four weeks by
pointing at a machine that cannot satisfy it. (Related standing fact: the test host reports
`isAvailable == true` and then fails generation with `UnifiedAssetFramework Code=5000` —
availability is not generability.)

**C5 — the code says `#90`; the tracker says `#93`.** 53 `#90` citations across `Talaria/` mark this
work (`ConversationJournalStore.swift:5`, `ContextTransplanter.swift:5`, `ChatStore.swift:959`,
`CondenserFidelityTests.swift:5,18`, and the build commit `5a29941`'s own subject line). Archived
**#90** is the `DEVELOPMENT_TEAM` placeholder (`OPEN_ITEMS-ARCHIVE.md:13255`). Anyone grepping the
tracker number out of the code lands on the wrong item. Low-risk comment sweep; worth a line in #93
even if the sweep is declined.

**C6 — #101's "a lightweight durable-facts store extending the condenser/journal" is architecturally
stale.** The journal is **single-conversation by construction**:
`ConversationJournalStore.sync` `:53-58` **resets the entire journal** the moment
`conversation.id` differs. It is not, and was never, a history store. The multi-conversation corpus
is `SwiftDataLocalSessionStore` (#190) — which did **not exist** when #101 was filed on 2026-07-11.
This is good news for #101 and it changes where the lane would start.

**C7 — two smaller ones.** (i) #101's "the local brain has no cross-chat memory at all" is too
strong: `ConversationSearchTool` already searches past sessions — but only their **titles and
previews**, and only with Spotlight indexing on. The accurate claim is "no cross-chat memory of
conversation **content**, and what exists is opt-in and thin." (ii) #93's step 4 (reconcile
`primingText` with `talaria-probe/probe.py`) has never been done and the probe is not in this repo;
it should either be routed as a 5-minute OJAMD check or explicitly closed as not-worth-doing —
either is fine, silence is not.

---

## 4. #101's viability verdict

**Verdict: VIABLE — local-brain only, and the direction of the answer is the inverse of the one the
task anticipated.** Not "not on-device, but yes for Hermes" — **on-device is the only place it is
worth building, and it is buildable today.** For Hermes-hosted chats the server already does it
(#101's own 3A-0 evidence: a run supplied no history answered `BANANA`, a marker from a probe two
days earlier, with the agent's reasoning visibly consulting memory summaries), so a client-side
duplicate there is the "redundant at best, conflicting at worst" case the re-scope already named.

**Three findings that change the shape from what the entry assumes:**

1. **The lost premise costs #101 nothing structural — it costs it the free space.** #284 shipped its
   registry and its budget contrast; selective arming did not ship (danger 4.76% vs ≤2%), so **no
   tokens were reclaimed.** What the entry feared — "land a broker that frees 15% and a memory layer
   that eats 20%" — cannot happen, because nothing was freed. The ⛔ gate is void (C3) and #101 can
   open whenever Owen wants. What remains true is the arithmetic it was protecting: on an armed turn
   there is roughly ~4,863 tok of headroom and a memory block spends from it. **The gate becomes a
   budget, and the budget must be measured — the instrument for that (`fullBelt=`,
   `tokenCount(for:)` fenced to between-turns) shipped with #284 and is the one thing #284 left
   behind that #101 directly inherits.**
2. **Both halves of the machine already exist and neither did when #101 was filed.** Corpus =
   `SwiftDataLocalSessionStore` (#190, full transcripts, durable, keyed). Extractor =
   `condensedContextBrief` (guided generation into a facts list, corrections-at-latest and
   prune-distractors already instructed). Injection seam = `effectiveInstructionsText` +
   `sessionBlueprint`, one place, feeding **both** the armed and toolless branches. Retrieval seam =
   `ConversationSearchTool`, already on the belt, already counted in the ~1,470. **#101 is
   substantially an integration lane, not a construction lane.**
3. **The router is the real gate, and it is not the window.** Production's router is one Bool, and
   the closest measured evidence we have is adverse: **"What can you do?" routes TOOLLESS on device**
   (#284's own same-day correction, build 2225, IN=500 = a beltless turn). A memory question is the
   same conversational shape. So a **retrieval** design can be starved by the router before it ever
   costs a token, and an **injected** design must sit in a block both branches carry — which the
   single instruction seam makes easy, and which nobody has to redesign anything to get.

**Is it buildable today?** Yes, with one qualification that deserves to be stated as "not until X":

- **The small, capped injected block (≤~120 tok) is buildable now.** It is ~1.5% of the window and
  ~8% of the armed belt — an honest cost against ~4,863 free.
- **The large injected layer — the full L0→L1→L2→L3 stack of the 2026-08-07 momentum note, injected
  — is NOT buildable at a size worth having, and X is: a shipped narrowing of the armed belt.**
  #284's verdict points at what that would be — a superset-tolerant, cover-the-needed-groups design
  with the trap-row danger solved — and explicitly says that is **new work under a new filing**, not
  a reopening. Until X, an L1/L2 layer has nowhere to live except the ~4,863, and every token it
  takes is a token of conversation it evicts. PCC's larger window is not X: it is
  entitlement-gated, user-consented and offered once per conversation (#30), so it cannot be the
  default a design assumes.
- **Any bar that requires the model to generate is a DEVICE bar.** The test host reports
  `isAvailable == true` and then fails with `UnifiedAssetFramework Code=5000`. Extraction bars,
  recall bars, routing bars, canary bars — all device. Only the renderer's token-cap bar and the
  store's persistence bars are unit-testable.

**One product precondition that is not an engineering question.** The corpus is full local
transcripts, and those transcripts contain the *output of HealthKit, location and contacts tools*.
#101's own 2026-08-07 note is right that a privacy class per item is load-bearing here, and it
should be **decided before an extractor is built**, not designed around afterward. That is Owen's
call (§8).

---

## 5. Candidate shapes

Two to build, one to decline explicitly so it is not silently rediscovered. Every token figure is
either measured, capped by construction, or marked as an estimate to be measured first.

### Shape A — Widen the corpus behind the tool that is already armed

**Mechanism.** `ConversationSearchTool` keeps its name, schema and description. Its past-session
lookup is repointed from the Spotlight title+preview cache (`AppContainer.swift:944-953`) to
`SwiftDataLocalSessionStore.conversation(withID:)` full transcripts, searched with the existing pure
`report(term:conversation:sessions:spotlightEnabled:)` shape and a hard output cap. The Spotlight
setting stops being the gate for *searching your own on-device history* (it remains the gate for
donating to the system index, which is a different consent).

**Token cost.** **Standing cost: 0.** The tool is already on the belt and already inside the ~1,470.
The only new spend is the tool's *result* inside the turn it fires — today bounded loosely
(`.suffix(6)` + `.prefix(5)`); this shape should bound it explicitly (proposed **≤300 tok**,
enforced by `measuredTokenCount` in the report builder, the ratchet pattern
`ContextTransplanter.fallbackPriming` already implements). Cost is paid only on turns that recall,
and never by turns that don't. **This is the cheapest memory in the design space, by a wide margin.**

**PROPOSED bars** (device unless noted):

- **A-1 ROUTING (the gate).** On a pinned set of 10 cross-chat-recall prompts ("what did we decide
  about the boat?", "what did I say my usual dose was?", "remind me what we called that project"),
  production's one-Bool router arms **≥90% of trials**, n=20. Scored off the router's own
  `router: turn routed …` log line, errors counted (a band with no error counter reports fail-safe
  noise as data).
- **A-2 RECALL.** With a planted fact in an older *stored* session and a fresh conversation, the
  answer contains the planted value in **≥90%** of trials, n=20, zero fabricated values tolerated
  (a wrong remembered fact is worse than none — 0 tolerated, like 297-C).
- **A-3 COST (reported + capped).** The turn's `session budget:` line shows the recall turn's
  transcript delta, and the report builder's cap is pinned by unit test at ≤300 tok. Unit half is
  sim-runnable; the device half is measurement, not a threshold.

**Cheapest falsifier: A-1 alone, and it needs no production code at all.** Add ~10 prompt rows to
the existing Developer-screen router battery and read the armed/toolless Bool. **If the router
routes cross-chat recall toolless, the tool never fires and Shape A is dead before any corpus work
begins.** One device battery run. This is the single highest-information, lowest-cost experiment in
this brief and it should run before anything else in #101.

### Shape B — L3 stable preferences only, injected, hard-capped

**Mechanism.** A small durable store of *stable* preferences (units, tone, recurring people/places,
standing constraints). Extracted by the existing `condensedContextBrief` guided generation **at
conversation end, never mid-turn** (the `tokenCount()`/generation-during-turn hazard is the same
class of constraint and the #228 flush queue is the established pattern). Each item carries
provenance (source session id + entry range → the user-facing "why does Talaria remember this?"
answer) and a privacy class (ordinary / sensitive / ephemeral). Rendered as ≤N short lines and
appended in `effectiveInstructionsText` so **both** the armed and toolless branches carry it; the
cap enforced by `measuredTokenCount` before the session is built.

**Token cost.** **Capped by construction — proposed 120 tok** (~8–10 short lines). ~1.5% of the
8,192 window; ~8% of the armed belt; ~2.5% of the ~4,863 free. Measured every build by the #228
line, which will show it as a transcript-token rise of exactly the block. **The cap is the design.**
An uncapped facts block is the wish this brief is written to prevent.

**PROPOSED bars** (device unless noted):

- **B-1 COST (unit + device).** The rendered block measures ≤120 tok for any store state, pinned by
  unit test on the renderer; on device the `session budget:` transcript figure rises by ≤120 against
  the control arm.
- **B-2 BENEFIT (device A/B).** On a pinned set of preference-dependent prompts, the treatment arm
  honours the stored preference in **≥90%** of trials, n=20, control run alongside. Both arms built
  from the **same builder** behind a flag — `instructionsText(includeDurableFacts:)` — never a
  copied string (#202D's one-builder rule; #297 is the worked example).
- **B-3 NO-HARM (device).** The two #196 toolless canaries (`LocalChatBackend+Battery.swift:158-159`
  — "What's 2+2?" and "Write a haiku about sledding") stay clean, **control-matched within 1 trial**;
  and across all treatment trials, **zero** claims of having performed a device action and **zero**
  tool-call syntax. This is literally 297-B/297-C reused, and reusing them is the point: a block
  naming what the assistant knows about you carries exactly the disclaimer-tic risk #297 was written
  to guard.

**Cheapest falsifier: build the renderer and the flag ONLY — no store, no extractor, no privacy
classifier — hand-seed 8 plausible preference lines, and run the #297-shaped A/B.** If 120 tokens of
hand-written preferences does not move B-2, or costs B-3, then the whole L1/L2/L3 stack is not worth
building and no corpus work was spent finding that out. **The expensive parts of Shape B are exactly
the parts its falsifier does not need.**

### Shape C — Transplant durable facts into Hermes at hop time — **DECLINE, do not build**

**Mechanism (for the record).** `ContextTransplanter.composePriming` already composes a fact brief at
every hop; the durable-facts block could ride the priming body, or on the runs plane ride
`conversation_history` (`+RunsTransport.swift:50,102-123`) where history rides the body by design.
Phone-side token cost: **0** — it spends the server's window, inside the 1,500-tok priming budget
that is already enforced by measurement.

**Why decline anyway.** Hermes already carries cross-chat memory server-side (the 3A-0 `BANANA`
evidence). Injecting a client-derived fact set into a session whose agent is *also* consulting its
own memory summaries is the conflict case #101's re-scope named — two memories, no arbitration, and
a correction the user makes on the phone silently contradicting one the server holds. Listed here
only so a future lane does not rediscover it as a free win. **If it is ever wanted, its first bar is
not a token bar — it is "do the two memories ever disagree, and who wins?"**

---

## 6. Overlap with #242 and #253 — named, not merged

- **#242 (LOCAL-ANSWER BRIDGE)** shares #101's premise that the phone knows things the server does
  not, and shares **one concrete mechanism: the router**. #242's open design question (1) — "the
  router must flag phone-only intents BEFORE the send" — is the same measurement as Shape A's A-1,
  run over different prompts. **Overlap is in the router and the explanation surface, nothing else.**
  Payloads differ in kind: #242 delivers *live sensor/device facts at query time*; #101 delivers
  *durable conversational facts*. **Do not merge.** Do share: if A-1 runs, its harness and scoring
  are directly reusable for #242's detection question, and saying so in both entries is cheaper than
  running it twice.
- **#253 (AUTO routing)** would consult the same per-message classifier, and its 2026-08-07 note —
  "transparency, not infrastructure; the route chip says WHY" — applies verbatim to a memory layer
  ("answered from a remembered preference," with #101's provenance behind it). **Overlap is the
  classifier and the honesty surface. Do not merge:** #253 selects a *transport*; #101 composes
  *context*. A memory layer that shipped would give #253 one more signal to route on, and #253's
  chip would give #101 its user-facing explanation for free — mutual, not subsuming.
- **#284 (registry / broker)** is the third adjacency and the ordering between it and #101 is now a
  *fact*, not a gate: nothing was freed, so #101 is unblocked, and if a superset-tolerant arming
  design ever files, Shape A's tool gets cheaper to arm and Shape B's block competes for whatever it
  frees. Record the relationship; do not restore the ⛔.

---

## 7. What is OWEN'S to decide

1. **Does #93 split?** Proposed: #93 → ✅ with three named successors (device pass; fidelity-gate
   device run; the attachment-outbox v1 limit). The minimum alternative is a body rewrite. Either
   way, **row 7's falsified claim must be corrected in the same commit** (close-out rule).
2. **Device checklist item (c): struck, or rewritten to (c′)?** §3-C2 proposes the rewrite. This is
   a bar-integrity call, not a wording call — a check that cannot pass will read as a regression.
3. **#93 step 4 (`primingText` vs `probe.py`):** run the 5-minute OJAMD comparison, or close it as
   not-worth-doing. Silence is the one option that is not available.
4. **Is #101 still wanted?** The re-scope's answer was yes-for-local-brain-only, and nothing in the
   lost premise touches that. But the sequencing that made it a *later* item is gone, so the
   question "is this what the next lane should be?" is now genuinely open. **Owen routes.**
5. **Which shape?** A (near-zero standing cost, gated on the router), B (capped injection, gated on
   whether 120 tokens buys anything), both, or neither. My recommendation is in §9.
6. **The privacy default — a product decision, before any extractor.** The corpus is full local
   transcripts containing HealthKit / location / contacts tool output. What is auto-extractable, what
   is session-only, what is never durable? Decide first; a classifier designed after the extractor
   is a classifier arguing with existing data.
7. **The `#90` → `#93` citation sweep** (53 comments): worth a commit, or leave it and just note it
   in #93?

---

## 8. Recommended sequencing

Ordered by information-per-cost. Steps 1 and 2 are free of device time and of production code.

1. **Tracker repair (no code, no device).** Apply C1–C7 in their own homes: #93's body (C1, C2, C4,
   C5, C7-ii), `DEVICE-PASS-RUNNING-LIST.md` Group 7 item (c) (C2), #101's ⛔ (C3, C6, C7-i). One
   commit. This is the close-out-rule debt from four lanes ago and it costs nothing but attention.
2. **Shape A's falsifier — A-1, the routing run.** ~10 new prompt rows in the existing router
   battery, one device run, errors counted. **This single run decides whether #101's cheapest shape
   exists at all,** and its numbers are reusable by #242 and #253 whatever the answer.
3. **#93's device pass — Group 7 (a), (b), (d), (e), (f)** with the rewritten (c′), batched with
   Group 6 (shared prerequisite: host-side gateway stop/restart). ~25–30 min. **The oldest owed
   verification on the board**, on a mechanism four later lanes now depend on.
4. **The fidelity gate** — a full-suite run on `whoGoesThere`; `CondenserFidelityTests` auto-enables
   there and needs no new code. Fold into whichever sitting has the phone corded.
5. **Only if Owen routes #101, and only after step 2's verdict:** Shape B's falsifier — renderer +
   flag + 8 hand-seeded lines, run through the #297 A/B harness shape. No store, no extractor, no
   classifier.
6. **Last, and only against a shape that survived its falsifier:** the corpus wiring, the extractor,
   the provenance chain, and the privacy classes — in that order, with the privacy default decided
   (§7.6) before the extractor is written.

**The through-line:** #93 needs verification, not construction, and the verification is ~30 minutes
that has been owed for four weeks. #101 needs one routing measurement before it needs a design.
Neither item's next step is a build.
