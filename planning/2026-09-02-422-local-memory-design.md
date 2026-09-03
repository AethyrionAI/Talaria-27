# 422 — Talaria's own LOCAL MEMORY: design, numbers, two scopes, bars

**Lane:** Fable design lane, 2026-09-02 evening (Owen: *"Now that Fable 5.1 has released, I bet we could revisit giving Talaria memory and the different methods for the internal memory."*). **Read-only + measurement — nothing in this doc is built.** Code read at `main @ 5a7fc255`. Tracker entry **#422** carries the summary and the bars verbatim; this file is canonical for the shape.

**Status of every number below:** each carries its provenance (Mac host / iOS simulator / device, date, build). The on-device model cannot generate on a simulator (#324/#402, re-measured), so every *behavioural* bar is device-only and says so. Nothing here is a production rate (#215); the retrieval-quality figures are a **smoke reading on a 16-item corpus** that sizes a bar, not a result.

---

## 1. The four rulings, restated as design constraints

| # | Owen's ruling (2026-09-02) | What it forbids | What it forces |
|---|---|---|---|
| 1 | **What earns a memory: RETRIEVAL over the user's own stored turns + EXPLICIT notes ("remember that…"). Nothing model-inferred.** Reason is measured: archived #417 — this brain fabricates 20/40 with nothing to say, 0/40 with something real. | No extraction, no summarisation, no "rolling digest", no paraphrase anywhere in the memory path (paraphrase *is* inference). No model call may author a stored memory. | The corpus is **verbatim user text**; injected text is verbatim or **head-truncated with a visible ellipsis** (truncation is not paraphrase — `LocalIntelligenceService.trimmed(_:toTokenBudget:)` at `:254` already does exactly this and only this). The explicit-note path must store the **user's own words**. Structural pin: no `LanguageModelSession` reachable from the memory module (378-D's source-scan shape). |
| 2 | **Visibility: a Memory screen listing every memory WITH ITS SOURCE (the turn, or "you told me on <date>"), edit/delete; plus a per-reply provenance chip on any reply that drew on memory (the #371 shape).** | No silent memory. No memory whose source cannot be resolved. No reply that used memory without saying so. | Every stored row carries a **resolvable source** (session id + message id, or "note, created <date>"). `Message` gains an optional `memoryProvenance` field (optional because of #42's silent-wipe rule — the same reasoning `ToolActivity.provenance` documents at `ToolActivity.swift:53`). A chip beside the existing brain tag (`MessageBubble.swift:303`). |
| 3 | **Two stores NEVER merged: local memory feeds the local brain; a host's memory (Honcho/Hindsight) feeds host turns; the app labels which store a reply drew on. No reconciliation.** | No local memory injected into a host turn. No host memory copied into the local store. No "unified" list. No guessing which store a host reply used. | Retrieval runs only on `ChatBackendRouter.Brain.onDevice / .privateCloud` turns. Host-turn labelling is **observation-only**: the memory plugins are Hermes TOOLS (`honcho_profile/search/reasoning/context/conclude`, `hindsight_retain/recall/reflect` — read in `~/.hermes/hermes-agent/plugins/memory/*/__init__.py`), so a host reply that called one shows `tool.started {tool_name}` on the runs stream and can be labelled from evidence. **Both plugins also inject via a prefetch / `system_prompt_block` path that is invisible on the wire** — a host reply that drew on memory that way gets NO chip, and the Memory screen says so (#180: never assert what cannot be measured). |
| 4 | **Schedule: design now; Owen rules pre- vs post-launch AFTER this doc, with numbers.** | This doc does not decide schedule. | §5 gives two scopes with effort; §3 names the hazards I consider decisive for that ruling. Sunday's post-launch ruling stands until Owen moves it. |

Three standing rules from CLAUDE.md that bind the shape as hard as the rulings: **naming** (outward identity is TALARIA; "Hermes" only where it means the host — so the host store's label is *Hermes memory* and the local one is *on-device memory*, mirroring `Brain.monoLabel`); **the SwiftData main-context trap** (a private `ModelContext`, never `mainContext`, exactly as `SwiftDataLocalSessionStore` does at `:96-108`); and **#215/#343/#398-A measurement discipline** (every rate carries routed-ness, governor state and OS build).

---

## 2. The SHAPE

### 2.1 Capture — when a turn becomes retrievable

**Per settled turn, in the foreground, at the point the app already treats a local turn as durable.** `ChatStore.recordLocalOriginAfterSettledTurn()` (`ChatStore.swift:1764` call site, `:1781` body) is the ONE place a local-origin thread is upserted into `SwiftDataLocalSessionStore` after an assistant turn settles. The memory indexer hangs off that same event: the settled exchange's **user-authored** messages (`sender == .user || .voiceUser`; never `.hermes`, `.voiceHermes`, `.system`, never `isContextPriming`) are chunked, embedded and upserted.

- **Cost per turn is milliseconds, so no background task is needed.** Measured: `NLEmbedding.sentenceEmbedding` 5.3 ms median per short turn on the iOS 27 simulator (24A5423a) and 4.3 ms on the M4 host; `NLContextualEmbedding` 8–20 ms on the host (see §4). A device is plausibly 2–4× slower; a model turn costs seconds of ANE/GPU. The embedding is <1% of the turn it follows.
- **#63's `BGAppRefreshTask` (GitHub #14) is deliberately NOT used.** It is discretionary — `earliestBeginDate = +15 min` at `BackgroundTaskService.swift:65`, "iOS decides when a pass runs (can be hours)". A memory that becomes retrievable hours after it was said is a memory the next turn cannot see. The only background-shaped work is the **one-off backfill** of sessions already in the store at upgrade time, and even that runs as a low-priority foreground `Task` with a resumable cursor (Owen's Mac host holds 836 user turns over 74 days — see §4 — so a backfill is ~10 s of CPU at 10 ms/turn, spread out).
- **Only local-origin threads.** Store membership IS local origin (#190B, the comment above `recordLocalOriginAfterSettledTurn`): a paired-mode Hermes thread never enters `SwiftDataLocalSessionStore`, so it never enters the index. That is ruling 3 enforced at capture, not filtered at retrieval.
- **Chunking is forced by the model, not chosen.** `NLContextualEmbedding.maximumSequenceLength` is **256 tokens** (measured; a 1,032-char turn came back `sequenceLength=256` — silently truncated). `sentenceEmbedding` has no documented limit but the probe shows quality collapsing on longer text (§4 table: the 55-word turn scores far below the 14-word one on the same query). Chunks of ~40–60 words on sentence boundaries; p90 user turn on the host (2,702 chars) is ~8 chunks; the median (131 chars) is one.
- **Idempotent** by `(messageID, chunkIndex)`, so the settle path can fire twice (it does — the same function handles first-turn membership and refreshes) without double rows.

### 2.2 Store — SwiftData, a SEPARATE container

A second named `ModelConfiguration` — `"TalariaMemory"` — not a third `@Model` in `TalariaLocalSessions`. `SwiftDataLocalSessionStore.make` (`:121`) already says *"Named store, not `default.store`, so any future SwiftData user in this app can't collide with it"*; taking that invitation keeps the session store's migration surface untouched and lets **Forget everything** be a container drop. Same construction discipline: `@MainActor` class, `ModelContext(container)` private context, explicit saves, `groupContainer: .none`, `cloudKitDatabase: .none`.

| entity | fields | notes |
|---|---|---|
| `MemoryNoteRecord` | `noteID`, `text` (verbatim user words minus the trigger prefix), `createdAt`, `editedAt?`, `sourceMessageID?`, `sourceSessionID?`, `embedderID`, `vector: Data` | The explicit store. Edit keeps `createdAt`, stamps `editedAt`; the screen shows both. |
| `MemoryTurnIndexRecord` | `entryID`, `sessionID`, `messageID`, `chunkIndex`, `text` (verbatim chunk), `sentAt`, `embedderID`, `vector: Data`, `isExcluded` | The retrieval corpus. `isExcluded` is the per-turn "don't use this" — the transcript is never touched. |
| `MemoryUseRecord` | `replyMessageID`, `store` (`local` / `host`), `entryIDs` / `noteIDs` or `observedToolNames`, `at` | What the Memory screen's RECENTLY USED section and the chip's tap-through read. Written at settle alongside the reply. |

- **Vector storage:** 512 × Float32 = **2,048 B/row** (Float16 halves it; a decision for the build lane — Accelerate's `vDSP` handles both). At Owen's measured rate (836 user turns / 74 days ≈ 11/day, ~1.5 chunks each) that is ~12 MB/year at Float32. Brute-force cosine over **20,000 × 512 Float32 ran in 5.7 ms on the M4** — no vector DB, no index structure, at any store size this user could reach in a decade.
- **Per-store labelling** is structural: the local container never holds a host row, and the `MemoryUseRecord.store` field is what the chip renders. There is no code path that writes `host` entries into `MemoryTurnIndexRecord`.
- **Deletion semantics** (the ones I am proposing; the retention ones are Owen's — §7):
  - delete a **note** → row deleted; in-memory Undo for the session.
  - **exclude** a turn → `isExcluded = true`; transcript untouched; reversible on the screen.
  - delete a **session** (existing Sessions screen) → cascade-delete its index rows in the same save: a memory must not outlive its source, or the Memory screen's source link dangles. Pinned (422-A).
  - **Forget everything** → drop both index and notes; the session transcripts remain (they are chat history, not memory).
  - **toggle OFF** → retrieval stops immediately; whether indexing continues is Owen's call (§7).
- **Embedder identity is a row attribute**, not an app constant: `embedderID` = `"nl.sentence.en.r1"` today. A row whose `embedderID` differs from the live embedder is **never compared** — it is re-embedded lazily or skipped. §4 shows why this is load-bearing: the embedder that is actually available differs between the Mac host and the simulator, and the device is unmeasured.

### 2.3 Retrieval — query, scoring, admission, budget

**Query** = the user's prompt text for this turn, as typed (the same string the router sees). **Retrieval does not run** on bare accepts and anaphors: `isShortAffirmative` (`LocalChatBackend+IntentRouting.swift:245`) and prompts under ~4 content tokens skip retrieval outright — "yes please", "another one", "say that again" defer their subject to the conversation, which is already in context; a memory hit on them would be noise at best and a #202D regression at worst (§3.5).

**Scoring — hybrid, because the measurement says neither half is enough on its own.** On the 16-turn / 12-query smoke corpus (§4, Mac host):

| scorer | top-1 | top-3 | mean gap (relevant − best irrelevant) | min gap |
|---|---|---|---|---|
| lexical token-overlap only | 9/12 | 11/12 | **+0.368** | 0.000 |
| `sentenceEmbedding` cosine only | 7/12 | 8/12 | **−0.003** | −0.309 |
| `NLContextualEmbedding` mean-pool cosine only | 9/12 | 10/12 | +0.014 | −0.043 |
| **hybrid 0.7·sentence + 0.3·lexical** | **10/12** | **12/12** | +0.140 | −0.131 |
| hybrid 0.7·contextual + 0.3·lexical | 11/12 | 12/12 | +0.122 | −0.014 |

The embedding alone is **worse than word overlap** on top-1 and has a negative mean gap; the hybrid is the only scorer that gets every relevant turn into the top 3. So: `score = 0.7 · cos(embedding) + 0.3 · lexicalOverlap`, where `lexicalOverlap` is the fraction of the query's content tokens present in the chunk (a stop-list, no stemming — this repo's #417 lesson is that a longer phrase list is not a rule).

**Admission — RELATIVE, never an absolute cosine floor.** Measured on the same corpus: `sentenceEmbedding` relevant-cosine min **0.060** vs irrelevant max **0.441**; contextual relevant min **0.785** vs irrelevant max **0.872**. **No absolute threshold separates relevant from irrelevant on either model.** The admission rule therefore is:

1. rank the corpus by hybrid score for this query;
2. admit a candidate only if `(score − mean) / sd ≥ z` over this query's own score distribution across the corpus **and** it has at least one lexical content-token in common with the query *or* its cosine is in the query's top-2% — the lexical anchor is what stops a purely-semantic "haiku about rain" from pulling in the dog's heart pill;
3. **top-k = 3**, de-duplicated by `(sessionID, adjacent chunkIndex)` so one long turn cannot fill all three slots;
4. the constants (`z`, the anchor rule) are **bar 422-R's to set** on a ≥100-turn / ≥40-query labelled corpus that includes no-answer queries — this doc only records that the shape must be relative and anchored, because the measurement rules the alternative out.

**The token budget — the arithmetic Owen asked for.** All figures from the artifacts named in §4.

| runtime | window | reply headroom (`responseHeadroomTokens`) | budget | instructions (armed 450 + belt ~1,470 / toolless 340) | left for history + prompt + memory |
|---|---|---|---|---|---|
| on-device, `whoGoesThere` (`24A5424a`, 08-28) | **8,192** | 1,024 | 7,168 | 1,920 / 340 | **5,248 / 6,828** |
| on-device, the 08-12 `iPad` reading (`24A5408d`) | 4,096 | 1,024 | 3,072 | 1,920 / 340 | 1,152 / 2,732 |
| PCC (`24A5424a`, 08-28) | **32,768** | 4,096 | 28,672 | 1,920 / 340 | 26,752 / 28,332 |

`sessionBlueprint` (`LocalChatBackend.swift:1363`) gives the verbatim history tail **half** of what remains after instructions (`verbatimSplitIndex`, `:2216`), and reserves the other half for the condensed block (cap **1,024** tokens, `:96`) plus the turn in flight. A memory block has to live in that second half beside the condensed block.

**Proposed cap: `memoryBlockTokens = clamp(contextSize / 10, 256 … 2,048)`** → **800 on 8,192**, 400 on a 4,096 window, 2,048 on PCC. Composition within the cap: the always-on explicit-notes set (≤ ~300 tokens — see below) + up to 3 retrieved chunks head-trimmed to **≤ 100 tokens each** via `trimmed()` + a ~40-token preamble. Worst case on the armed 8,192 path: `5,248 − 1,024 (condensed) − 800 (memory) = 3,424` tokens still available for history-tail + prompt — at the host's measured medians (user 131 chars ≈ 32 tokens, assistant 210 chars ≈ 51 tokens at the measured **4.1 chars/token**) that is ~40 exchanges of verbatim tail, which is more than today's median conversation (2 user turns) by an order of magnitude. On the 4,096 window the same arithmetic leaves 1,152 − 1,024 − 400 < 0 → the memory cap must yield to the condensed block there (`memoryBlockTokens` shrinks first; the block is dropped entirely before history is), which is why the cap is a function of the runtime window and not a constant.

**Latency cost is derived, not measured, and is a device bar.** #206's router measurement (comment at `LocalChatBackend+IntentRouting.swift:~170`): 4,073 chars of context routed in 1.47 s vs 0.66 s at 800 chars — **+3,273 chars (≈ +800 tokens) cost +0.81 s** on the on-device model ⇒ ~**1 ms per prefill token**. A full 800-token block therefore adds ~0.8 s to a turn; a typical hit turn (3 chunks ≈ 300 tokens + notes) ~0.5 s; a turn with no hits adds nothing. Bar 422-L measures this on the phone.

### 2.4 Injection — two blocks, two places, and why

The existing condensed block is appended to the **instructions** at `LocalChatBackend.swift:1432` (`baseInstructions + condensedMemoryPreamble + memory`). That is the right home for the part of memory that changes rarely, and the wrong home for the part that changes every turn — because **the live session is REUSED across turns** (`preparedSession`, `:1113`, returns the existing session whenever the tool set is unchanged and `fitsContext` holds), and a rebuild re-prefills the whole transcript at the ~1 ms/token above: a 4,000-token conversation rebuilt every turn is ~4 s per turn. So:

1. **Explicit notes → the INSTRUCTIONS block**, built in `sessionBlueprint` on **both** branches (armed and toolless go through the same blueprint; `effectiveInstructionsText` picks the base, the blueprint appends). Always-on up to a small cap (proposal: **≤ 8 notes / ≤ 300 tokens**; beyond that, notes join the retrieval pool and only hits ride — Owen's cap to set, §7). A new or edited note invalidates the session (`session = nil`, the existing pattern) and the ~seconds rebuild is paid **once per note**, which is the right economics. Preamble, in the same register as `condensedMemoryPreamble` (`:2232`):

   > `## Things the user asked you to remember` — each line `On <date> the user said: "<verbatim>"`. *Treat these as things the user told you, quoted; if two disagree, say which is newer and quote both.*

2. **Retrieved chunks → the PROMPT of the hit turn only**, through the ONE door (`makeTurnPrompt`, #390's invariant): `promptText = memoryPrefix + composePrompt(…)`. No session rebuild; the block's tokens are prefilled once and then sit in the live transcript as part of that prompt entry. Preamble:

   > `## From your earlier chats (quoted, may be out of date)` — each line `On <date> you said: "<verbatim chunk…>"`.

   The label is deliberately *"you said"* with a date and quotation marks, never *"fact:"* — the model is handed real text with its provenance, which is #417's protective shape.

   **The accounting this creates (a new hazard, §3.7):** `fitsContext` (`:1444`) estimates from OUR `Message` history, not the live transcript, so injected prefixes would be invisible to it and accumulate until the #26 overflow retry fires. The backend keeps `injectedMemoryTokensThisSession`, adds it in `fitsContext`, and forces a rebuild (which drops old prefixes, since they are not in `Message` history) once the sum passes a cap (proposal: **1,500 tokens**). Pinned offline (422-D).

3. **The "just saved" turn.** When the explicit-note parser fires (2.5), the note is stored **before the model runs**, and that turn's prompt prefix carries `The user just asked you to remember this and it HAS been saved: "<verbatim>"`. The model then relays a true fact instead of inventing an acknowledgement — again the fail-nodata shape #417 measured at 0/40.

4. **The honest-empty case.** #417's dangerous condition is the model having *nothing* to say. A memory-shaped question with no admitted hits — "what do you remember about my sister", "what did I tell you about X", "what do you know about me" — is exactly that condition. For those turns (a small deterministic detector, closed-vocabulary, pinned) the prefix carries the honest string `No saved memories match this question.` Ordinary turns with no hits get **no prefix at all** (the model answering from world knowledge is not the fabrication case, and every-turn noise would cost tokens for nothing).

5. **Reasoning stays a separate channel** (CLAUDE.md's SSE rule, restated for the local path): the memory prefix is input; nothing in it is ever surfaced as the reply.

### 2.5 The explicit-note path — deterministic in the minimal shape, a TOOL in the fuller one

**Minimal shape: `ExplicitMemoryIntent.parse(_:) -> String?` — no model in the loop.** A closed, pinned set of **declarative** trigger prefixes, case-insensitive, matched at the start of the message: `remember that`, `remember:`, `please remember that`, `don't forget that`, `note that`, `for future reference,`. The stored text is the message with only the trigger removed — **the user's words, verbatim**, which is what makes it satisfy ruling 1 with zero inference surface. Everything else about the turn is unchanged: it is still sent, still routed, still answered (with the just-saved prefix above).

- **`remember to …` and `remind me …` NEVER match.** Those are reminders (`createReminder`, the #200-series' whole territory). The discriminator is the complementiser: *that* introduces a fact, *to* introduces a task. Pinned by test with both forms.
- **Routing consequences under #215:** none for the retrieval path (the router sees the raw prompt, not the prefix — `routeTurn` is called with `nextPrompt` before any injection) and none for the deterministic note path (it does not depend on the route). That is the reason the minimal shape uses it: every one of its behaviours is sim-testable, and it adds no device-only string to `toolIntentRouterInstructions` (`:44`, a measured artifact pinned byte-for-byte).
- **Card treatment:** the #29 confirmation family (`ToolConfirmationCenter`) gates *this phone's writes* — reminder, event, alarm — and the approval modes (#224: manual / smart / off) describe exactly that blast radius in their copy. A note written into Talaria's own store by the user's own words is not that. **Proposal: no card in the minimal shape**; the reply's `SAVED TO MEMORY` chip and a one-tap Undo on the Memory screen are the visibility. Owen's call (§7).
- **What a miss looks like:** "keep in mind my sister moved to Denver" does not match, is an ordinary turn, and the model may answer *"Got it, I'll remember that"* — **a false claim about a memory that does not exist**. That is the same disease #202B measured on device actions (10/12 false completion claims) and it is why the minimal shape extends the **honesty guard** rather than the prompt: `ActionClaimDetector` (`:330-352`) gains a `memory` claim kind — artifact nouns `memory / note / notes`, verbs `remember / remembered / noted / saved / keep in mind / kept in mind` in the existing first-person and passive patterns — that fires when the turn **saved no note**, and `honestyGuardedReply` (`:1762`) appends a memory correction in the shape of `honestyCorrectionNotice` (`:1722`): *"⚠️ **Nothing was saved to memory.** Talaria only remembers what you ask it to with 'Remember that…' — the reply above is inaccurate."* The guard never rewrites the model's text (#338's rule). Specimen-tested per 417-D against replies recorded on device.

**Fuller shape: a `rememberNote` device tool** for the phrasings the closed set misses. It is model-mediated — the model authors the `note` argument, which is a paraphrase hazard under ruling 1 — so it **must** go through the confirmation card with the argument pre-filled and editable, exactly like `ReminderCreateTool`, and it needs: a `CapabilityRegistry` group (`.memory`, `displayPhrase` "things you've asked it to remember"), a router few-shot example (`"Remember that I'm allergic to shellfish" -> needsDeviceTool: true`), and an extension of `toollessHonestyClauseV2` (`:2305`) to cover "remember". Every one of those is a measured string — the #202D promotion procedure, on device, n≥10 per arm, with the current text as the pinned rollback. Approval-mode arms: manual → card; smart → the caution layer has nothing to flag on a note, so it auto-approves; off → auto-approves (no caution can trip). That is a post-launch lane on its own.

### 2.6 Provenance — the chip and the Memory screen's source field

- **`Message.memoryProvenance: MemoryProvenance?`** — `.local(entryIDs: [UUID], noteIDs: [UUID], savedNoteID: UUID?)` / `.host(observedTools: [String])`. **Optional, Codable, no custom `init(from:)`** — the #42 silent-wipe rule; pinned the way `legacyToolActivityJSONStillDecodes` pins `ToolActivity.provenance`.
- **The chip** renders in the bubble's tag row beside the brain tag (`MessageBubble.swift:303`), `MonoLabel` size 8 like its neighbour: `ON-DEVICE MEMORY` (local hits), `SAVED TO MEMORY` (a note was created on this turn), `HERMES MEMORY · honcho_search` (a host turn on which a memory tool event was observed). Tap → a sheet listing the entries with their source lines. **Accessibility label carries the same words** (#296/#371-E: the non-visual reader must not get the version without the claim). No chip means no memory was drawn on **as far as the app can see** — and the sheet copy says that for host turns.
- **The Memory screen** (title `MEMORY`, subtitle `WHAT TALARIA REMEMBERS` — Talaria-meaning strings say Talaria):
  1. **NOTES** — every explicit note, newest first: text · *"You told me on 3 Sep"* (+ *"edited 5 Sep"*) · Edit · Delete.
  2. **RECENTLY USED** — every turn retrieval has drawn on, from `MemoryUseRecord`: the verbatim chunk · *"From your chat on 28 Aug"* → tap opens the session at that message · **Don't use this** (sets `isExcluded`).
  3. **INDEX** — one honest line: *"Talaria can draw on the N messages you've sent in on-device chats"* (real count, `"—"` while unknown), the ON/OFF toggle, **Forget everything**. In the fuller shape this section gains a search box that runs the real scorer, so the user can see exactly what the model would be shown for any query — transparency and a debugging surface in one.
  4. A fixed line under the host label when a host is configured: *"Your Hermes host keeps its own memory (Honcho, Hindsight…). Talaria never reads or merges it; a Hermes reply is tagged only when the host reports a memory tool call."*
- **A source that no longer resolves** (session deleted out from under a `MemoryUseRecord`) renders *"source deleted"*, never a blank row and never a claim (378-B's four-states discipline).
- **Where the screen lives:** the minimal shape pushes it from **SESSIONS (07 · STORAGE & DATA)**, which owns local storage today, so the positional card numbering (#395-D2, pinned by `deckOrderIsTenAndStable` / `cardNumbersArePositionalAndContiguousOnBothDeviceShapes`) does not move. A top-level MEMORY tile would shift PRIVATE CLOUD off Owen's 08 — his call (§7).

### 2.7 Never-merged, made structural

| invariant | where it is enforced | how it is pinned |
|---|---|---|
| host-tier turns never enter the corpus | capture hangs off local-origin membership (#190B) | test: a `.hermes`-brain conversation upserted through the seam produces zero index rows |
| local memory never injected into a host turn | retrieval is called from `LocalChatBackend` only; `SessionsHermesClient` has no call site | source scan (378-D's shape): the memory module's symbols are unreferenced from `Talaria/Services/Live/SessionsHermesClient*.swift` |
| host memory never written locally | no writer for `store == .host` rows in `MemoryTurnIndexRecord` / `MemoryNoteRecord` | the `store` field exists only on `MemoryUseRecord` |
| the chip names the store | `MemoryProvenance` has two cases with two labels | string pins, both cases, plus the a11y label |
| a host chip needs evidence | `.host` is constructed only from an observed `tool.started` whose name is in the plugin tool set | test: a host turn with no memory tool event yields `memoryProvenance == nil` |

---

## 3. HAZARDS — each with the line that would show it

**3.1 Fabrication leakage — retrieved text quoted as fact when it was a question or a joke.** "Should I move to Denver?" retrieved for "where do I live" becomes *"You live in Denver"*. Mitigation is the preamble's framing (`On <date> you said: "…"`, quoted, dated, never "fact") and the model's measured disposition to relay framing faithfully (#417: 0/40 with an honest string). **The line:** bar 422-F's planted-question arm — n=40 memory-shaped questions against a store seeded with a QUESTION and a JOKE about the same subject; count replies asserting the planted content as fact (`assertedMemory`, one denominator, `unscorable` never folded — 417-C). Prediction written first: it will NOT be zero; the interesting number is how far from zero, and whether the date-quoted framing beats an unframed control arm.

**3.2 Stale memory.** A note from June and a chat from August disagree. No reconciliation is allowed (ruling 3's spirit applied within the local store: resolving is inference). Mitigation: every injected line carries its date; the notes preamble instructs *"if two disagree, say which is newer and quote both"*; the Memory screen shows `createdAt`/`editedAt`. **The line:** 422-F's contradiction arm — two dated notes with conflicting values; score replies that assert the OLDER value without its date.

**3.3 PCC disclosure.** A memory prefix injected into a `PrivateCloudComputeLanguageModel` session is data sent to Apple's servers. `docs/privacy.html:52-58` today says *"Your request leaves the device — including any images you attached to that message"* — silent on memory. **The line:** the PCC paragraph gains *"…and, if you have memory turned on, any notes you asked Talaria to remember and any earlier messages Talaria retrieves for that request"*; the PCC screen's own copy (#395) gains the same sentence; both pinned as strings. #385 is the precedent: the app told a PCC user its conversation never left the phone, and a device pass caught it. A memory feature that is not in the policy on the day it ships is a public claim that is false (#166's register).

**3.4 Background-work battery.** Small by measurement (§4: 5–14 ms per turn on the sim) and by design (no `BGTaskScheduler` work — §2.1). The real battery risk is the **per-turn prefill of the memory block on the on-device model** (~1 ms/token derived → ~0.5 s of model time on a hit turn). **The line:** 422-L on device — added wall-clock per hit turn, and the `#398`-style energy row before/after over a 20-turn run; plus the backfill's total CPU time logged once.

**3.5 The #202D anaphora / "another one" interplay.** The router keys on referent resolution (#334-N: an anaphor + a device-action referent ⇒ armed). Retrieval sees the same anaphor and would resolve it against the *corpus* instead — a hit on "another one" would inject an unrelated old turn into a turn whose referent is the previous assistant message. Mitigation: retrieval is skipped on `shortAffirmatives` and sub-4-token prompts (§2.3); the router never sees the memory prefix, so the #196 probe's 200/200 cannot move. **The line:** the existing router probe grid re-run unchanged (100/100 baseline must hold — it should by construction, and a construction claim is verified, not assumed), plus an offline pin that `routeTurn` receives `nextPrompt` unmodified when a prefix is present.

**3.6 The naming ruling.** New outward strings: `MEMORY`, `WHAT TALARIA REMEMBERS`, `ON-DEVICE MEMORY`, `SAVED TO MEMORY`, `HERMES MEMORY`, `Nothing was saved to memory. Talaria only remembers…`, `Talaria can draw on the N messages…`. All Talaria-meaning except `HERMES MEMORY`, which is host-meaning by the same reasoning `theHostBrainLabelStaysHermes` pins. **The line:** `NamingSweepTests` gains the new literals in both directions (the Talaria strings present; no `"Hermes remembers"` / `"Hermes Memory"` app-meaning literal anywhere).

**3.7 NEW — found by measurement, not by the brief.**
- **(a) The embedder you assumed is not the embedder you get.** `NLContextualEmbedding(.english)` loads and embeds on the Mac host; on the iOS 27 simulator runtime (24A5423a) it reports `hasAvailableAssets=false`, `requestAssets` returns `NLNaturalLanguageErrorDomain Code=8 "Failed to locate embedding model"`, and `load()` throws `Code=7 "Embedding model requires compilation"` — **not usable on a simulator, 3/3 runs**. `NLEmbedding.sentenceEmbedding(.english)` works on the simulator — **but returns `nil` if called before any `NLContextualEmbedding(language:)` has been constructed in the process (6/6 nil-first, 6/6 works-after)**; on the Mac host it works either way. Device availability of BOTH is **unmeasured** (the 08-31 probe was a Mac-host reading). **The line:** 422-C — the warm-up construction is pinned by a test that runs on the sim and asserts non-nil; the **lexical scorer is always present** so retrieval degrades to word overlap (9/12 top-1 on the smoke corpus) and never to nothing; `embedderID` on every row; and a device arm that records which embedders load on `whoGoesThere`, with build.
  **⟵ CORRECTED 2026-09-02 night (M1 build lane, Task 3 + a 3-arm in-bundle probe on sim 24A5423a, `CC-lane-1`): the "sentence embedder is nil unless an `NLContextualEmbedding` was constructed first" reading is a MIS-ATTRIBUTION.** Measured in the app test bundle: the FIRST `NLEmbedding.sentenceEmbedding(for: .english)` call in a process returns `nil` (NaturalLanguage logs `Unable to locate Asset for sentence embedding model for local en`) and the SECOND and every later call returns the 512-dim embedder (R1 nil, R2–R5 512, five identical plain calls, nothing else in the process). `probe3` interposed a contextual construction between call 1 and call 2 and never discriminated the two. In-bundle the contextual path is dead on the sim (`requestAssets` throws code 8, `load` code 7, no network) and is NOT needed. The shipped warm-up is a synchronous retry, not a construction. Untested: whether one retry suffices on the DEVICE from a cold asset — DE1 carries it.
- **(b) No absolute similarity threshold exists** (§2.3). The line is 422-R's no-answer queries: a scorer with an absolute floor would admit irrelevant hits on them at the measured rate; the relative rule must hold the false-admit rate ≤ 0.10.
- **(c) Prompt-prefix accumulation** is a new overflow path on the on-device tier (§2.4). The line: 422-D's synthetic 30-hit conversation — the #26 overflow retry must never fire from prefixes alone.
- **(d) The transplant primer.** #330 found the host path storing the condensed primer as an ordinary **`user`** row. Local-origin sessions never carry one (the primer is a host-plane artefact), and `isContextPriming` rows are excluded at capture regardless — but a future change that lets a host thread's rows into the local store would index a wall of condensed text as "something the user said". The 422-B pin over `.system` / `isContextPriming` / non-local threads is the guard.
- **(e) Voice turns are ASR output.** `.voiceUser` turns are real user content and are indexed, but a misheard word becomes a retrievable "memory". Not mitigated here beyond the visible source line and *Don't use this*; flagged for Owen (§7).

---

## 4. MEASURED NUMBERS, with provenance

### 4.1 The on-device model's window and what today's prompt already spends

| quantity | value | provenance |
|---|---|---|
| `SystemLanguageModel.contextSize`, on-device, the phone | **8,192** | `~/.talaria-instrument-runs/20260828T013221Z-pcc-surface/latest.json`, device `iPhone`, `24A5424a`, build `c421ba05`, 2026-08-28 (variant *"AFM 3 Core Advanced"*); same value on `24A5418b` (08-21) and on `24A5408d` iPhone (08-15 reference table) |
| `contextSize`, on-device, an `iPad` reading | 4,096 | `20260812T212657Z-tokencount-preflight`, `deviceModel: iPad`, `24A5408d`, 2026-08-12 — recorded because a 4,096 window exists in the fleet and the cap in §2.3 is derived from the runtime read, never hardcoded |
| `PrivateCloudComputeLanguageModel.contextSize` | **32,768** | same 08-28 pcc-surface run |
| reply headroom (`responseHeadroomTokens`) | 1,024 on-device / 4,096 PCC | `LocalChatBackend.swift:65`, code |
| armed instructions (belt-bearing) | **450 tokens** (1,841 chars → **4.09 chars/token**) | `planning/reports/2026-08-14-343-beta5-reference-table/artifacts/20260815T064138Z-condensation-fit.json`, device iPhone `24A5408d`; identical 450 on the 08-12 iPad run |
| production toolless instructions | **340 tokens** (1,314 chars, 3.86 chars/token) | same artifacts |
| armed belt (13 tools) | **~1,470 tokens** | #229's L0-C device measurement, quoted from the `rebuildForOverflowRetry` doc comment (`LocalChatBackend.swift:~1206`) — not re-measured here |
| router session payload (separate session, not in the chat window) | 367 tokens (instructions 190 + envelope 12 + 2-field schema 165) | 08-12 tokencount-preflight |
| condensed-memory caps today | 120 tokens/turn, 1,024/block | `LocalChatBackend.swift:94,96` |
| condensation on 8,192: a 12-turn / 9,932-token transcript | → 4,205 tokens post, 4 verbatim + 8 condensed, memory block 2,471 chars, ARMED+FITS 10/10 | 08-15 reference-table artifact |
| prefill cost, derived | **~1 ms/token** on-device (+3,273 chars ≈ +800 tokens ⇒ +0.81 s) | #206's router latency comment, `LocalChatBackend+IntentRouting.swift` (`routerContextLimit` doc); device, 2026-07-31 vintage |

**⚠️ `tokenCount()` concurrent with a live turn kills the turn (ModelManagerError 1001)** — every number above came from instruments that run with no turn in flight (#228/#335's rule), and the build lane's own measurements must too.

### 4.2 Embeddings on the shipping toolchain (Xcode-beta6 27A5252f, SDK 24A5422a)

**Mac host** (macOS 26.6.2 `25G83`, M4 Mac Mini, `swiftc -O -target arm64-apple-macos26.0`), 2026-09-02:

| | `NLContextualEmbedding(.english)` | `NLEmbedding.sentenceEmbedding(.english)` |
|---|---|---|
| dimension / revision | **512 / 1**, `modelIdentifier 5C45D94E-…`, 20 Latin-script languages | **512 / 1** |
| assets | `hasAvailableAssets = true`, loads | built-in |
| max sequence | **256 tokens** (a 1,032-char turn returned `sequenceLength = 256`) | not exposed |
| latency, 14-word turn | 8.3 ms median (20 reps) | 4.3 ms median |
| latency, 55-word turn | 10.4 ms | — |
| latency, 220-word turn (clamped to 256 tokens) | 19.9 ms | — |
| brute-force dot product, 20,000 × 512 Float32 | **5.7 ms** | — |
| storage per vector | 2,048 B Float32 / 1,024 B Float16 | same |

**iOS 27 simulator** (runtime **24A5423a**, `CC-lane-1`, binary built `-target arm64-apple-ios27.0-simulator`, run via `simctl spawn`), 2026-09-02:

| | contextual | sentence |
|---|---|---|
| availability | `hasAvailableAssets=false`; `requestAssets` → `Code=8 Failed to locate embedding model`; `load()` → `Code=7 Embedding model requires compilation` — **3/3 runs** | `nil` when called first in the process (**6/6**); `dim=512` after an `NLContextualEmbedding(language:)` construction (**6/6**) |
| latency, 14-word turn | — | **5.3–5.4 ms** median (three runs; 10.6 and 14.0 ms on the first run after boot) |
| cosine behaviour | — | identical to the Mac host to 3 decimals |

**Device (`whoGoesThere`, 24A5424a): UNMEASURED for both embedders.** The 08-31 tracker line (*"AVAILABLE dim=512 revision=1 hasAssets=true"*) matches the Mac-host reading above and nothing else: the simulator cannot load the model, and no device run is on record — so it is read here as a host reading, not a device fact. Bar 422-C's device arm is owed before anything ships.

### 4.3 Retrieval-quality smoke reading (Mac host; the sim ran the lexical row identically and had no embedder in that process order)

16 realistic user turns, 12 queries each with one labelled relevant turn — reproduced in Appendix B. Full table in §2.3. Headline: **lexical 9/12 top-1; sentence-embedding alone 7/12 with a negative mean gap; hybrid 0.7·sentence + 0.3·lexical 10/12 top-1, 12/12 top-3.** Absolute cosine cannot be a threshold on either model (relevant min 0.060 vs irrelevant max 0.441 for sentence; 0.785 vs 0.872 for contextual). **n=16/12 sizes a bar; it is not the bar.**

### 4.4 How many turns a real store holds — Owen's own host, read-only

`~/.hermes/state.db` on the Mac Mini (Owen's dev host — the closest real-user corpus this Mac holds; read with `sqlite3 -readonly`, nothing written), 2026-06-20 → 2026-09-02 (74 days):

| quantity | value |
|---|---|
| sessions / sessions with ≥1 user message | 435 / 288 (sources: acp 169, api_server 132, tui 80, desktop 51) |
| **user turns, total** | **836** (≈ 11 / day) |
| user turns per session | median **2**, p90 **6**, max 22 |
| user message length | median **131 chars**, p90 2,702, p99 162,406 (pasted logs) |
| assistant message length | median 210 chars, p90 2,268 |
| host memory file backend (`~/.hermes/memories/`) | `MEMORY.md` 6,567 B / 21 `§`-entries / 890 words; `USER.md` 667 B / 1 entry — a year of an agent's own curated memory is ~1.6 k tokens |

The app's own SwiftData stores on this Mac are gate-produced (CC-lane-1/2/3: 42/41/61 sessions, 252/242/362 messages, ~195 B of transcript JSON per message) and say nothing about a user; recorded so nobody mistakes them for one. **The phone's store was not read** (uncorded; and the question is answered by the host numbers).

**What the corpus size implies:** at 836 turns × ~1.5 chunks the index is ~1,250 vectors (2.5 MB); a decade at this rate is ~45,000 vectors — brute force at 5.7 ms / 20 k on the M4 is ~13 ms on the Mac and plausibly ~50 ms on a phone. **No vector index, no dependency, ever.** Top-k = 3 against a corpus whose sessions have a median of 2 user turns means a hit almost always comes from a *different* session — which is the whole point.

---

## 5. TWO SCOPES with honest effort

Effort is in this repo's units: a **lane** = one agent session ending in a gated PR (`lane-gate.sh`), and a **device evening** = Owen's schedule (mornings no device, evenings device, weekends open).

### 5.1 MINIMAL — pre-launch-shaped: retrieval + explicit notes + Memory screen + chip

| lane | contents | sim-testable? |
|---|---|---|
| **M1 store + capture** | `TalariaMemory` container, three `@Model`s, private context; chunker; `EmbeddingService` (sentence embedder with the warm-up construction, lexical scorer, `embedderID`); settle-hook indexing; resumable backfill; session-delete cascade | yes, fully |
| **M2 retrieval + corpus** | hybrid scorer, relative admission, top-k/de-dup, the memory-shaped-question detector; **the ≥100-turn / ≥40-query labelled corpus** (the slow part — it is authored, not generated); bar 422-R | yes (the Mac twin of the embedder is honest for cosine, §4.2) |
| **M3 injection + notes + honesty** | notes → instructions block; hits → prompt prefix through the one door; `fitsContext` accounting + rebuild cap; runtime-window cap; `ExplicitMemoryIntent.parse`; the just-saved prefix; honest-empty prefix; `ActionClaimDetector` memory kind + correction notice | offline for structure; **behaviour device-only** |
| **M4 surfaces + policy** | `Message.memoryProvenance`; chip + sheet + a11y; Memory screen under SESSIONS (notes / recently used / index line / toggle / forget-all); `docs/privacy.html` + PCC screen copy; `NamingSweepTests` pins; gate | yes |
| **Device evenings ×2** | 422-C availability arm; 422-F three-arm cell contrast (n=40 each, ~10 min of generation per arm at the #417 cadence); 422-H false-claim arm; 422-L latency + energy | — |

**Estimate: 4 lanes + 2 device evenings + the corpus-authoring time inside M2 — about one week at Owen's cadence, assuming no bar falsifies the shape.** The bar most likely to falsify: 422-C's device arm (if neither embedder loads on the phone the shape still ships on the lexical scorer — 9/12 top-1 on the smoke corpus — but that is a different product claim and Owen should know before, not after). Second most likely: 422-F's planted-question arm producing a rate Owen will not accept for launch.

### 5.2 FULLER — post-launch

Adds, each its own lane with its own bars:
- **the `rememberNote` tool** with card, approval-mode arms, router few-shot, honesty-clause extension — #202D's promotion procedure on device (1–2 lanes + 1–2 device evenings);
- **host-memory chip from observed tool events** (`honcho_*`, `hindsight_*` on the runs stream) and the Memory screen's host line — needs Owen's Honcho host live during the device pass (1 lane + 1 evening);
- **Memory screen INDEX search** running the real scorer (½ lane);
- **`NLContextualEmbedding` upgrade path** — only if its device availability (422-C) is measured true AND a labelled-corpus re-run beats the sentence hybrid (the smoke reading had it 11/12 vs 10/12 — inside noise); on-demand assets mean a network dependency the policy would have to name;
- **assistant-turn corpus** for episodic "what did we decide" queries — model-authored text as memory, which ruling 1 currently excludes; Owen's decision first;
- **retention and cross-profile rules** once Owen rules them (§7).

**Estimate: 4–5 further lanes + 3–4 device evenings, spread over the weeks after launch.**

### 5.3 The hazards I consider decisive for the schedule ruling

1. **Device availability of the embedders is unmeasured** (3.7a). It is a 10-minute measurement on a device evening and it decides whether the launch claim is "semantic memory" or "keyword memory". Do it before ruling.
2. **The fabrication-leakage rate is device-only** (3.1) and this brain's disposition to assert is measured (#417: 70% asserted with tools succeeding; 50% with nothing). A memory feature ships with a number on 3.1 or it ships as a hope.
3. **The privacy policy is a public claim in the submission** (3.3, #166). Adding memory to the PCC paragraph is a one-line change, but it is a change to the document the review-risk register is built on.
4. **Prompt-prefix accumulation is a new overflow path on the tier the default user runs** (3.7c). It is fully offline-pinnable, but it is the kind of seam that has bitten this project before (#26 → #210 → #229).

My recommendation, held loosely because it is Owen's: **post-launch, first thing** — the minimal shape is a week of careful work whose two decisive numbers (1 and 2 above) do not exist yet, and #166a+#166d are the only things between `main` and submission today.

---

## 6. PRE-REGISTERED BARS for the MINIMAL shape (ready to paste into #422)

**Written before any code, in the house style: RED-first pins, named mutation arms, offline vs device stated per bar, one denominator per rate, `unscorable` never folded, the gate names its runtime (398-C).**

- **422-A (STORE — offline).** A separate `TalariaMemory` SwiftData container with a **private `ModelContext`** (never `mainContext` — the beta-4 SIGTRAP), three `@Model`s, explicit saves, `groupContainer: .none`, `cloudKitDatabase: .none`. Upsert is idempotent by `(messageID, chunkIndex)` — RED-first: the double-upsert pin against a store with no uniqueness. **Deleting a session cascades its index rows in the same save** — RED-first; **mutation M-A:** remove the cascade ⇒ ONLY the dangling-source pin reds. `Message.memoryProvenance` is optional with no hand-written `init(from:)`: `legacyMessageJSONStillDecodes` green, watched RED with the field declared non-optional before it is trusted (296-E's procedure).
- **422-B (CAPTURE — offline).** Only `.user` / `.voiceUser` messages of **local-origin** threads are indexed; `.hermes`, `.voiceHermes`, `.system`, `isContextPriming == true`, and any message of a non-store-member thread produce **zero** rows — one test per exclusion, each RED-first against an unfiltered capture. Chunks ≤ 60 words on sentence boundaries; a 2,702-char turn (the host p90) yields ≥ 6 rows, a 131-char turn yields 1. Indexing fires from the settle seam and **never** from a keystroke or a streaming delta. Backfill is resumable: kill it mid-run (cursor at N), restart, rows == full run's rows, no duplicates.
- **422-C (EMBEDDER — offline + device).** *Offline, on the sim:* a test constructs `NLContextualEmbedding(language: .english)` first and asserts `NLEmbedding.sentenceEmbedding(for: .english) != nil` — the 6/6 order-dependence, pinned (the test is deleted the day a runtime makes it pass without the warm-up, and says so). With the embedder forced `nil`, retrieval still answers from the lexical scorer (top-1 ≥ 8/12 on Appendix B's corpus). Every row carries `embedderID`; a row whose id ≠ the live embedder's is never scored (RED-first: a mismatched row scored as if comparable). *Device arm:* on `whoGoesThere`, record for both embedders: constructible, `hasAvailableAssets`, `load()` result, `dimension`, per-turn latency (n=20) — with `osVersion` and build in the artifact. **No number in this lane is quoted without this row.**
- **422-R (RETRIEVAL QUALITY — offline).** A labelled corpus of **≥ 100 user turns and ≥ 40 queries, ≥ 10 of them no-answer queries**, checked into `planning/reports/` with the run. Bars on the hybrid + relative-admission scorer: **precision@1 ≥ 0.80** on answerable queries; **false-admit rate ≤ 0.10** on no-answer queries (an admit is any chunk passing the rule); top-3 recall ≥ 0.90. Reported over the same denominator, per query class. **Mutation M-R:** lexical-only must score strictly lower on ≥ 1 of the three; if it does not, the embedder buys nothing and is **deleted from the shape** — that is a legitimate outcome, recorded as one, not a bar rewritten.
- **422-D (BUDGET — offline).** `memoryBlockTokens(contextSize:)` returns 800 / 400 / 2,048 for 8,192 / 4,096 / 32,768 — pinned. The composed block never exceeds the cap (property test over random hit sets). Retrieved chunks are head-trimmed by `trimmed()` with a visible `…` — RED-first that the trimmed text is a **prefix** of the source (no paraphrase, structurally). **Source scan:** no `LanguageModelSession`, `respond(`, `streamResponse(` or `@Generable` token in `Talaria/Services/Live/Memory/` (378-D's shape). `fitsContext` includes `injectedMemoryTokensThisSession`; a synthetic 30-turn conversation with a 3-hit prefix on every turn triggers the accounting rebuild and **never** the #26 overflow retry — RED-first with the accounting removed. `routeTurn` receives `nextPrompt` byte-identical whether or not a prefix exists (3.5).
- **422-E (EXPLICIT NOTE — offline).** `ExplicitMemoryIntent.parse` matches exactly the pinned prefix set (each form, each case variant); **`remember to …` / `remind me …` / `set a reminder…` never match** — one pin per form; the stored text equals the message minus the trigger, whitespace-trimmed, byte-for-byte; the note exists **before** the turn's session is prepared (ordering pin); the just-saved prefix rides that turn's prompt; the reply carries `savedNoteID`; Undo removes the row and the chip; edit preserves `createdAt` and stamps `editedAt`.
- **422-H (HONESTY — offline + device).** *Offline:* `ActionClaimDetector` gains the `memory` claim kind; **positive control per 417-D**: it must FIRE on *"Got it, I'll remember that"*, *"I've noted that your sister lives in Austin"*, *"I'll keep that in mind"* and stay QUIET on *"I can't remember things between chats unless you ask me to"* and on any turn where a note WAS saved; the correction text pinned. *Device arm:* n ≥ 40 "remember"-shaped prompts that do **not** match the closed set (e.g. "keep in mind…", "FYI…", "just so you know…"): report `falseMemoryClaim / trials` before the guard and `uncorrectedFalseClaim / trials` after it, one denominator, `unscorable` separate. **Bar: uncorrected = 0/40.** The raw pre-guard rate is a finding, not a bar.
- **422-F (FABRICATION CELL CONTRAST — device; the decisive number).** Same four-prompt discipline as #417. Arms, n = 40 each, on `whoGoesThere`: **`empty`** (memory-shaped questions, empty store → the honest-empty prefix), **`planted-fact`** (store holds a dated declarative), **`planted-question`** (store holds a QUESTION and a JOKE about the same subject), **`contradiction`** (two dated notes disagreeing). Report `assertedMemory`, `honestRefusal`, `quotedWithDate`, `unscorable` over one denominator per arm; scorer's positive control is the `planted-fact` arm (must assert ≥ 30/40 — a near-zero there means the detector is blind, not the model honest). **Predictions, written first:** `empty` → 0/40 asserted (the #417 fail-nodata shape); `planted-question` → **> 0**, magnitude unknown; `contradiction` → the older value asserted without its date in > 0 replies. Thermal, build, `osVersion`, `routedToollessTrials` recorded (417-E). **This is a CELL CONTRAST, not a production rate (#215).**
- **422-P (PROVENANCE + SCREEN — offline).** Chip renders iff `memoryProvenance != nil`; `.local` and `.host` render distinct pinned labels and the a11y label carries the same words; the sheet lists every referenced entry with a resolvable source line, and a deleted source renders *"source deleted"* (RED-first against a blank row). Memory screen: every note appears with its date; every `MemoryUseRecord` appears under RECENTLY USED; *Don't use this* sets `isExcluded` and the next retrieval over the same query does not return it (RED-first); the index line shows the real count or `"—"`, never 0 while unknown; Forget everything empties both entities and the screen re-renders empty-honest, not blank.
- **422-N (NAMING + POLICY — offline).** `NamingSweepTests`: the new Talaria-meaning literals present, `HERMES MEMORY` present as host-meaning, no `"Hermes Memory"` / `"Hermes remembers"` app-meaning literal in shipping sources. `docs/privacy.html`'s PCC paragraph and the PCC screen's copy both name memory — string pins over the file and the view.
- **422-L (LATENCY + ENERGY — device).** Added wall-clock on a 3-hit turn vs a no-hit control, n = 10 each, same prompt family (prediction ≤ 1.0 s from the ~1 ms/token derivation); per-turn embed latency (prediction ≤ 30 ms); the #398-style energy row over a 20-turn run with and without memory; backfill total CPU time logged once. Numbers with `osVersion`, thermal, build.
- **422-GATE.** `scripts/mac/lane-gate.sh` PASS with the test count moved, runtime named on the verdict line, Release build clean (#218), `TALARIA_SIM_NAME` from the fixed pool, ≤ 3 booted.

---

## 7. NOT decided here — Owen's

1. **Retention.** Nothing here expires. Do index rows age out (e.g. 1 year)? Do notes ever? Default in this doc: never, with Forget-everything as the only reset.
2. **Cross-profile / host tier.** Does a host-configured install still get **local** memory injected into **local** turns (yes in this doc — ruling 3 is about not crossing stores, not about disabling one), and does a host turn ever get the local block (no)?
3. **Assistant turns in the corpus.** Excluded here (model-authored text as memory). Episodic "what did we decide" retrieval needs them; that is a ruling-1 question.
4. **Voice turns.** Indexed here (they are user content); ASR errors become retrievable text (3.7e).
5. **The Memory screen's home.** Under SESSIONS (no positional shift) vs a top-level MEMORY tile (PRIVATE CLOUD leaves 08).
6. **Always-on notes cap** (≤ 8 notes / ≤ 300 tokens proposed) and **note length cap** (500 chars proposed; over-length → save the first 500 with a visible notice, or refuse and ask to shorten).
7. **Card on the deterministic note path.** None proposed; the fuller shape's tool always cards.
8. **Toggle-OFF semantics.** Stop retrieving only, or stop indexing too. (Stop-both proposed; the index is kept until Forget-everything.)
9. **PCC tier.** Inject memory on PCC at all (yes proposed, with the policy line) or on-device only.
10. **422-F's acceptance number** for the planted-question arm — 0/40 is not a realistic bar for this brain; what rate does Owen accept, and does a non-zero rate gate launch?
11. **Pre- vs post-launch.** §5.3.
12. **Whether the labelled corpus (422-R) may contain Owen's real host turns** (read-only, on the Mac) or must be synthetic — real text is a better corpus and a privacy question.

---

## Appendix A — the probe files (throwaway; not merged; reproducible from here)

Both built with `DEVELOPER_DIR=/Applications/Xcode-beta6.app/Contents/Developer`:
- Mac host: `xcrun swiftc -O -target arm64-apple-macos26.0 probe.swift -o probe-mac && ./probe-mac`
- Simulator runtime (no Xcode project, no xcodegen): `xcrun -sdk iphonesimulator swiftc -O -target arm64-apple-ios27.0-simulator probe.swift -o probe-sim`, then `xcrun simctl boot <CC-lane UDID>` and `xcrun simctl spawn <UDID> ./probe-sim`; `simctl shutdown` afterwards (the pool was left at 0 booted, as found).

`probe.swift` (latency / availability): constructs `NLContextualEmbedding(language: .english)`, prints `dimension`, `revision`, `hasAvailableAssets`, `maximumSequenceLength`, `modelIdentifier`; calls `requestAssets` if assets are absent; `load()`; mean-pools `embeddingResult(for:language:)` token vectors over 20 repetitions of a 14-word, a 55-word and a 220-word turn; then `NLEmbedding.sentenceEmbedding(for: .english)` `vector(for:)` over the same; cosines against five queries; a 20,000 × 512 Float32 brute-force dot loop timed with `Date()`.

`probe3.swift` (order dependence): `sentenceEmbedding` before any contextual construction → print nil/dim; construct `NLContextualEmbedding`; `sentenceEmbedding` again → print.
  **⟵ `probe3`'s reading is superseded — see §3.7(a)'s 2026-09-02 correction: the dependence is on the CALL COUNT, not on the contextual construction.**

## Appendix B — the smoke corpus (`probe2.swift`), so 422-R can start from it rather than from nothing

Corpus (index: text): 0 *Remember that my sister Shelley lives in Austin and her birthday is in March.* · 1 *I'm allergic to shellfish, so never suggest seafood places.* · 2 *My dentist is Dr. Patel on Lamar, appointments are usually Tuesday mornings.* · 3 *We decided to go with the blue paint for the hallway, not the grey.* · 4 *The dog's name is Biscuit and he takes his heart pill at 8pm.* · 5 *Write me a haiku about rain on a tin roof.* · 6 *How many steps did I take yesterday?* · 7 *My wifi password at home is on the fridge, I keep forgetting it.* · 8 *I usually run on Saturday mornings along the river trail.* · 9 *Summarize the French Revolution in fifty words.* · 10 *The Thai place on South Congress that Shelley likes is called Thai Fresh.* · 11 *My car is due for an oil change at 42,000 miles.* · 12 *I prefer window seats and always book the aisle for my wife.* · 13 *What's fifteen percent of eighty?* · 14 *Our anniversary is October 14th, we got married in 2015.* · 15 *Set an alarm for 6:30 tomorrow.*

Queries → relevant index: *where does my sister live* → 0 · *when is Shelley's birthday* → 0 · *do I have any food allergies* → 1 · *who is my dentist* → 2 · *which colour did we pick for the hallway* → 3 · *when does the dog get his medicine* → 4 · *what's the name of that Thai restaurant* → 10 · *when is my car's next service* → 11 · *what seat does my wife like on planes* → 12 · *when is our anniversary* → 14 · *when do I usually go running* → 8 · *what's my dog called* → 4.

Lexical scorer: fraction of the query's content tokens (lower-cased, > 2 chars, a 40-word stop-list) present in the chunk. Hybrid: `0.7·cos + 0.3·lexical`. Results in §2.3 / §4.3.
