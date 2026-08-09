# OPUS — OPTIONS BRIEF: the unrouted tail (#242, #253, #149, #150, #222)

**Label:** OPUS · **Written:** 2026-08-09 · **Branch at read time:** `t27-295-expiration-recovery` @ `35c6234`
**Items:** #242 · #253 · #149 · #150 · #222
**Goal:** make each of the five decidable in one reading — what it would take, what it depends on,
and whether it routes now, parks with a reason, or is already done.

**No production code was written, no Swift file edited, no `OPEN_ITEMS.md` edit made.** Bars below
are PROPOSED for the one ROUTE NOW item; the orchestrator files them in the entry per the
post-#215 convention.

---

## 1. The register

| item | one-line shape | depends on | cost class | **disposition** |
|---|---|---|---|---|
| **#149** | MCP server so Claude talks to Hermes directly | nothing — built, registered, live | zero | **✅ ALREADY SATISFIED** — verified live this session; close/archive |
| **#242** | remote chats get phone-only facts at query time | #251 Phase 2 transport (shipped) | zero for the shipped half | **PARK — SUBSTANTIALLY DELIVERED** as #251 slice 2A; header is stale; one residual + one Owen decision |
| **#222** | true image input to the on-device model, unused | beta4 FM SDK (verified present) | **small, no phone** for the owed slice | **ROUTE NOW (the narrow slice only)** — compile probe + two doc corrections; device arm opportunistic |
| **#253** | per-message on-device/server brain routing | a router that fails safe (does not exist for this decision) | medium–large | **PARK WITH REASON** — mechanism is *not* the falsified one, but the failure asymmetry inverts and the deterministic 80% needs no model at all |
| **#150** | Talaria as an MCP client | #284's capability broker (did **not** ship) | large | **PARK WITH REASON** — post-launch by design, and now blocked on an unsolved 8k-window problem |

Nothing here is a CUT. Four of the five are either done, mostly done, or deliberately post-launch;
one has a cheap owed slice.

---

## 2. Verified state

### VERIFIED (checked at HEAD this session)

- **#149 is live.** `mcp__hermes-mac__hermes_gateway_health` → `{"status":"ok","platform":"hermes-agent","version":"0.20.0","base_url":"http://127.0.0.1:8642"}`;
  `mcp__hermes-ojamd__hermes_gateway_health` → same, `base_url":"http://100.110.102.59:8642"`.
  Both hosts answer. The tool surface exposed to this session is exactly the five the entry
  describes (`hermes_gateway_health`, `hermes_list_sessions`, `hermes_create_session`,
  `hermes_chat`, `hermes_read_messages`), under the two named servers `hermes-mac` /
  `hermes-ojamd`. **#149 is satisfied and has been since 2026-07-20.**
- **#242's core mechanism SHIPPED, in a different and better form than the entry proposes.**
  Server side: `~/.hermes/plugins/talaria/tools.py` registers `talaria_phone_query` (toolset
  `talaria`) with a seven-kind catalog — `location, health, motion, weather, calendar, reminders,
  deviceStatus` — a 40 s timeout, `check_fn=_transport_available` so the model never sees a dead
  transport, and hand-written honest-failure prose for unpaired / app-closed / declined.
  App side: `/Users/owenjones/Documents/Claude/Talaria-27/Talaria/Services/Live/PhoneQueryResponder.swift`
  answers each kind by calling **the same statics the #28 belt tools call** —
  `LocationTool.performLocationRead`, `DeviceHealthTool.performRead`, `MotionTool.performMotionRead`,
  `WeatherTool.performLookup`, `CalendarReadTool.performRead`, `ReminderReadTool.performRead`,
  `DeviceStatusTool.statusReport()` — behind a re-read-per-answer settings gate
  (`deniedGate(kind:settings:)`), with the gate checked *before* the read so a denial never touches
  HealthKit on its way to saying no.
- **#222's item 1 is DONE and the fix is in the tree.**
  `Talaria/Services/Live/LocalChatBackend+Battery.swift:1883-1895` now reads
  *"That is a design CHOICE, not a property of the model (#222)"* and cites the 2026-08-02 device
  confirmation. The comment the entry was filed against no longer exists.
- **`ImageAttachment` / `ImageReference` remain 0-use in production.** Repo-wide grep over
  `Talaria/` + `Shared/` returns exactly two hits, both inside that corrected comment.
- **The image surface is really in the beta4 SDK** — read from
  `/Applications/Xcode-beta4.app/…/iPhoneOS.sdk/…/FoundationModels.swiftmodule/arm64e-apple-ios.swiftinterface`:
  `Transcript.Segment.image` (:2338), `Transcript.ImageAttachment` (:2345), `ImageAttachmentContent`
  (:2779), `ImageReference` (:2955, `: Generable`). The **construction** path is
  `extension Attachment where Content == ImageAttachmentContent` (:2784) with four inits
  (`CGImage`/`CIImage`/`CVPixelBuffer`/`imageURL`, each with optional `orientation`), and
  **`Attachment : PromptRepresentable, InstructionsRepresentable` (:2769)** — so an attachment goes
  straight into a `Prompt`. `_Vision_FoundationModels.framework` is present in the same SDK
  (the cross-import overlay; a grep of either framework alone will not see its tools).
- **The Bool router is production and cheap.** `LocalChatBackend+IntentRouting.swift:233` —
  greedy, `maximumResponseTokens: 64`, ~0.6 s measured on device, 200/200 lifetime, **fails safe to
  ARMED** on any throw. Its call site is `LocalChatBackend.swift:867` — i.e. **the local backend
  only**. Remote turns do not touch FoundationModels today.
- **Multiway intent classification is falsified, twice, and the Bool shape is not.** #217 (run
  `3CB9E45D`, dangerous 12.5% vs a ≤2% bar) and #217B (run `8D724EC5`, all four cells fail,
  best 5.3%) — ABANDONED. #284's vector probe (run `0AF5A6D8`, 2026-08-08) then showed **eleven
  Bool fields cost the gate nothing (100%)** while the danger bar still missed at 4.76% on one
  deterministic trap row.
- **#284's selective arming did NOT ship** — stages 1–2 only. Nothing narrows the belt today.
- **Plan C phase state** (#268's map, cross-checked against the plugin install): Phase 1 ✅,
  Phase 2 slice 2A ✅ merged (PR #272), slices 2B/2C/2D = #269/#270/#271 NOT STARTED,
  Phase 3 slice 3A shipped 2026-08-08, **Phase 4 = relay decommission = #223**.
  The install at `~/.hermes/plugins/talaria/` now carries `platform_adapter.py`, `transport.py`,
  `outbox.py`, `envelope.py` — Phase 2's spine, not just Phase 1's tools.

### ASSUMED (recorded as tracker/handoff testimony, NOT re-verified today)

- Owen's 2026-08-06 device pass for slice 2A: the natural-language query returned his real address
  to an agent on another machine; the health leg returned `"Steps today: 4275"`; the denied leg
  returned the designed prose verbatim. **I did not re-run any of this.** No device was used in
  producing this brief.
- The 2A-B latency falsification (32 s end-to-end vs a ≤5 s bar, the bar mis-specified; the
  transport leg alone is still unmeasured) — taken from #251/#263.
- #229's token numbers (belt ≈1,470 tok ≈18% of 8,192; belt + starting transcript ≈41%) — archived
  device measurements from #228's L0-C, not re-measured.
- Any claim about **on-device generation behaviour**. The test host reports `isAvailable == true`
  and then fails every generation with `UnifiedAssetFramework Code=5000`. **Nothing below asserts
  what the model will do with an attached image** — that is exactly what bar 222-C is for.

---

## 3. ⚠️ Tracker corrections

1. **#242's header is stale.** It reads *"FILED 2026-08-03 late night, UNROUTED (idea, no design
   yet)"*. Its core — remote chats obtaining phone-only facts at query time, no ingestion, no
   host-side store — **shipped on 2026-08-05/06 as #251 slice 2A and was device-proven 2026-08-06**.
   The entry body has never been updated. Recommended supersession note in #242 itself (upstream, per
   THE CLOSE-OUT RULE): *"SUBSTANTIALLY DELIVERED by #251 slice 2A (PR #272) — as a server-side tool
   the agent calls, not as an FM-belt dispatch. Residual scope: free-form phone reasoning; the
   gating-semantics decision; async host-side history analysis (still not covered, as predicted)."*

2. **#222's section title is now false for its own remaining contents.** The section is titled
   *"Owed — cheap, no phone, and NOT a promotion."* Item 1 (cheap, no phone) is **done**. What is
   left in it is item 2, which the same section says *"needs a code experiment + device run,"* and
   item 3, which is Owen's call. **Only a sub-slice of item 2 is still cheap and phone-free** (§6).
   A reader skimming the heading would conclude a no-phone deliverable is sitting there; it is not,
   unless the slice in §6 is the thing meant.

3. **#222's API description is imprecise, and precision is the point of that entry.** It says
   *"`Transcript.ImageAttachment` — inits from `CGImage`, `CIImage`, `CVPixelBuffer`, `imageURL`,
   with `orientation`."* In the beta4 interface, `Transcript.ImageAttachment` (:2345) declares **no
   public init** — only accessors (`url`, `cgImage`, `ciImage`, `pixelBuffer(resolution:pixelFormat:)`).
   Those four inits are on **`Attachment where Content == ImageAttachmentContent`** (:2784). This
   matters for anyone costing item 2: the usable path is `Attachment(cgImage) → Prompt` (because
   `Attachment` is `PromptRepresentable`), not "construct a `Transcript.ImageAttachment`."

4. **#149's "Owed: first in-anger use" is the entry's only residue** and it is not a deliverable.
   The bridge has been live and healthy on both hosts for nineteen days; this session used it
   read-only. Nothing is blocked on it.

5. **#253's entry says the interaction is with "#251 Phase 3 (runs migration)."** Phase 3 slice 3A
   shipped 2026-08-08, so that interaction is now with **shipped** transport, not planned. Minor,
   but the sentence reads as forward-looking when it is not.

6. **No correction found for #150.** Its 2026-08-06 reconciliation note ("READY TO SEND since
   2026-07-20, recorded as deliberate, not a dropped item") is accurate and current.

---

## 4. #242 in depth — the strategically significant one

### 4.1 It is not a prerequisite, and not unrelated. It is the enabler, and it already landed.

#223's sensor question named exactly **one** real loss from ditching the sensor plane: *"the REMOTE
Hermes agent's view of phone health/sensor history."* #242 was filed the same night as the avenue
that would dissolve that loss. **That avenue is built.**

- **Not a prerequisite** — nothing in the decommission is waiting on #242 to be designed. The work
  it named was absorbed into Plan C Phase 1/2 and merged.
- **Not an alternative in the "either/or" sense** — it is not competing with the decommission; it
  is the thing that makes the decommission cheap on the sensor axis.
- **Correct framing: #242 is the DELIVERED precondition.** The interactive half of the sensor
  plane's value now exists without ingestion, without a store, without the relay. What the phone
  answers is byte-identical to what the local belt would answer, because `PhoneQueryResponder` calls
  the same statics.

**What is still lost, exactly as #242 predicted and to its credit:** host-side **asynchronous**
analysis of phone history — "analyse my sleep trends while I'm away." The tool's own failure prose
proves the shape of the loss: *"Phone unreachable: the paired phone is not connected right now (the
app is probably closed). Do not retry this turn."* Query-time means the phone must be awake. No
history, no backfill, no cron. **Say this out loud when #223's sensor question is finally called** —
it is the whole residual cost.

**What still gates Phase 4 (relay decommission) is therefore NOT sensors.** Per #251's own errata
the relay also carries voice WebRTC bootstrap and #21's file delivery, and `SensorUploadService.swift`
is still in the tree. Sensors are the tenant #242 evicted; the other two are unrouted.

### 4.2 The 8,192-token price — and the shipped design pays none of it

The brief asked to price #242 against #229's window. The honest answer is that **the shipped shape
sidesteps the window entirely**, and that is the strongest argument for it over the filed idea.

| shape | who decides the phone is needed | on-device tokens spent | latency added |
|---|---|---|---|
| **#242 as filed** (dispatch the FM belt at query time) | a client-side classifier, before the send | belt ≈1,470 tok + instructions + question inside 8,192 — #229's ≈18% floor, per dispatched question | router ≈0.6 s + a full local tool-using turn, **serially before** the remote request |
| **#251-2A as shipped** | the **server** model's own tool choice | **zero** — no `LanguageModelSession` is constructed; `PhoneQueryResponder` is a direct tool read | the phone leg only (unmeasured; the 32 s figure is a whole remote turn, not this) |

Three consequences worth stating plainly:

1. **The filed shape's headline cost is not tokens, it is the classifier.** Detection was #242's own
   open question (1) — "the router must flag phone-only intents BEFORE the send." The shipped design
   **deletes that question** by letting the host model choose a tool it can see. That is the same
   escape #217B proved we cannot classify our way into.
2. **The window would have bound the ANSWER, not just the question.** A dispatched FM turn must fit
   belt + instructions + transcript + the phone data in 8,192 — and #229 measured 41% consumed before
   the user's first token on a short conversation. A multi-read synthesis ("this week vs last") is
   precisely the case that would not fit.
3. **The one thing the filed shape buys that the shipped one does not** is *reasoning over phone data
   on the phone*. The catalog returns seven fixed kinds; there is no "ask the phone's brain a
   question." Everything below is about whether that gap is worth anything.

### 4.3 Three candidate shapes for the residual, each with a cheap falsifier

**Shape A — Do nothing. Declare #242 delivered and close it.**
Claim: the seven-kind catalog plus the host model's own reasoning covers every phone-only question a
user actually asks; local synthesis adds nothing the host cannot do with the returned strings.
*Cheap falsifier (no phone, ~20 min):* take the last N real phone-only prompts from the device-pass
record and the #200-series grids, and check how many are answerable by **composing** catalog kinds.
If ≥1 in 10 needs data the catalog cannot express (e.g. a week-over-week comparison, a metric outside
`steps|calories|heartRate|sleep|summary`), Shape A is falsified and the gap is real.

**Shape B — Widen the catalog, not the brain.** Add parameters (date ranges, more metrics) so the
host model composes across richer reads. No FM dispatch, no window cost, no classifier.
*Cheap falsifier (no phone, ~30 min):* read `DeviceHealthTool.performRead`'s actual parameter surface.
If the belt tools themselves cannot express a range query, Shape B is not a plugin-side change at all
— it is belt work, and its cost should be re-quoted before anyone calls it cheap.

**Shape C — the filed shape, narrowed to synthesis only.** A single new kind, `ask`, whose handler
runs one FM turn on the phone over data the belt already fetched. Only reached when the host model
chooses it.
*Cheap falsifier (device, but small):* one turn — attach nothing, ask a two-read comparison question,
and instrument the session budget line. If belt + instructions + the two reads + the question do not
leave working room inside 8,192 on a *short* conversation, Shape C is dead on #229's numbers and no
further design is owed. **Must be a device run** — the test host's `Code=5000` means a green sim
result would prove nothing.

**Recommendation:** run Shape A's falsifier first. It is free, it is off-device, and it is the only
one of the three that can retire the residual outright.

---

## 5. #253's viability — measured against #217/#217B

**#253's shape does NOT require a multiway decision, so it is not automatically dead.** The
falsified mechanism is a multiway *intent* classification (`calendar|health|reminder|weather|other`),
falsified twice: #217 at 12.5% dangerous and #217B at 5.3% in its best of four cells, against a ≤2%
bar, with the pre-registered response "abandon, not iterate" taken. What #253 needs is a **Bool**
("does this turn need the server?"), and the Bool is the shape this model demonstrably handles:
200/200 lifetime in production, 100% gate in every cell of #217B, 100% gate again in #284 with
**eleven** Bool fields.

**But three things falsify the naive port, and they are why this stays parked.**

1. **The failure asymmetry INVERTS, and that asymmetry is the entire safety case for the existing
   router.** `routeNeedsDeviceTool` fails safe to ARMED — a wrong answer costs tokens and lands on
   today's behaviour. A brain route has **no free default**. Fail to server: a turn the user believed
   was private left the phone — for a product whose pitch is a self-contained local brain, that is the
   worst available failure. Fail to local: an image turn or a long-context turn hits the 8,192-token
   wall (#229) or a capability the local brain lacks. **Any #253 lane must state its fail-safe
   direction before it writes a line of code, and there is no obviously correct answer** — which makes
   it Owen's call, not a design detail.
2. **#284's trap row is the exact predicted failure, at production scale.** "How long will it take me
   to drive to the airport?" armed a confidently wrong set **5/5** — deterministic, so it fires on
   100% of such requests. Zero variance across 380 (#217B) and 165 (#284) classifications is the
   established behaviour of this model: it does not sometimes guess wrong, it has a fixed wrong
   mapping. A brain-routing classifier will have trap rows too, and each one leaks or starves
   *every* instance of that phrasing.
3. **It puts a FoundationModels generation in front of every REMOTE turn, where none exists today.**
   Verified: `routeNeedsDeviceTool` is called only from `LocalChatBackend`. A paired user's remote
   turn currently never touches FM. AUTO makes ~0.6 s of local classification the mandatory first
   leg of every server turn — a latency regression paid by exactly the users who chose the server.

**The finding that should shape any future lane: most of AUTO's value needs no classifier at all.**
Four of the routing signals are deterministic and knowable before any model runs — an image is
attached; the assembled context exceeds the local window (and `tokenCount(for:)` exists per #284, so
this is *measurable*, not estimated); the host is unreachable; the local brain is unavailable. Those
cover the capability cases outright. The one genuinely judgment-shaped case — "this needs phone-only
data" — **is already solved on the server side by `talaria_phone_query`** and needs no client
classifier at all. What is left for a model to decide is a narrow residue, and it is not obviously
worth a generation per turn.

**Also worth keeping if it ever routes:** the #253 entry's own 2026-08-07 note — borrow *transparency*
from `diegosouzapw/OmniRoute`, a route chip that says WHY. A deterministic router can explain itself
honestly ("Hermes — image attached, ~11k context exceeds local window"); a model-based one can only
report its own opinion. That is an argument for the deterministic design, not merely a UI nicety.

**Disposition: PARK.** Judged against the default hostless user, AUTO is a no-op — a hostless user
has one brain. It is a paired-tier convenience with a privacy-shaped failure mode, competing against
launch work.

---

## 6. #222's owed work, stated precisely enough to execute

**What the entry asks for, item by item, at HEAD:**

| # | the entry's ask | state |
|---|---|---|
| 1 | *"Correct the comment first."* | **DONE 2026-08-04** — verified in the tree at `LocalChatBackend+Battery.swift:1883-1895` |
| 2 | *"Prove the model actually sees an attached image — attach one, ask something only a viewer could answer (dominant colour, object count), on device."* | **OWED. Needs a device run** — so it is not the "no phone" work the heading advertises |
| 3 | *"Only then: re-open #205/#207's routing question."* | **OWED, and it is Owen's call**, gated on 2 |

**So the concrete deliverable is item 2 — and it splits into a cheap no-phone half and a device
half. The no-phone half is what should be routed now.**

**The no-phone half (≈1 hour, scratch file, no production code, no promotion):** prove the
construction shape **compiles** against the beta4 iOS SDK before anyone spends a device slot on it.
Concretely: a scratch Swift file that imports `FoundationModels`, builds
`Attachment(someCGImage, orientation: .up)`, passes it into a `Prompt` (legal because
`Attachment : PromptRepresentable`, interface :2769), and hands that to
`LanguageModelSession.respond(to:)` — type-checked with
`DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer swiftc -typecheck -sdk <iPhoneOS.sdk> -target arm64-apple-ios27.0`.
Per the never-blame-Apple-first rule, this is the *"`let x: Int = someMethod` prints the real
signature"* move: it settles availability-vs-usability without a phone and without guessing.
**A compile failure is a real, publishable finding** — it would mean the surface exists but is not
reachable from our integration, which closes item 2 negatively and saves the device run.

**The device half (only if the compile passes):** the entry already specifies it — attach an image,
ask a viewer-only question. **It cannot be shortcut on the sim or the test host**: `isAvailable`
returns true there and every generation dies `Code=5000`, so a green off-device run would be a false
negative dressed as evidence.

**It is emphatically not a promotion.** Nothing in this touches the router, the belt, or `#205`/`#207`.
The entry's own warning applies with full force: *"Do not re-derive router design on an unexercised
API — that is the mistake this entry exists to correct, and repeating it in the other direction
would be worse."* Item 3 stays closed until Owen opens it.

---

## 7. What is OWEN's to decide

One answerable question per line.

1. **#149:** close it and move it to the archive — the bridge is live on both hosts and the only
   open line is a nice-to-have "first in-anger use"? (yes / keep open)
2. **#242:** accept the supersession — rewrite the header to "SUBSTANTIALLY DELIVERED by #251 slice
   2A," keeping only the residual? (yes / no)
3. **#242 residual:** run Shape A's off-device falsifier (does any real phone-only prompt need data
   the seven-kind catalog cannot express?) before deciding whether local synthesis is worth anything?
   (run it / drop the residual outright / keep it filed unexamined)
4. **#242 gating (already raised at the 2A device pass, still unanswered):** one switch for all
   sensor egress, relabelled to say so — or split gates, where streaming governs upload and query
   answers ride the per-sensor toggles plus iOS permission? (a / b)
5. **#223 sensors:** with the interactive half now delivered, is the residual loss — host-side
   *asynchronous* analysis of phone history, which query-time cannot provide — acceptable? (yes,
   ditch sensors / no, keep them)
6. **#222:** route the no-phone compile slice now, with bars 222-A/B below? (yes / no)
7. **#222 device arm:** if the compile passes, does the viewer-only image trial go on the device
   list as opportunistic, or does it wait for a decision on item 3? (opportunistic / wait)
8. **#253:** park it as filed, or re-file it as the **deterministic** router (no model call, chip
   explains itself) which is a different and much smaller thing? (park / re-file / cut)
9. **#253 fail-safe, only if it ever routes:** when the auto-router is unsure, does the turn go
   local (private, may fail on capability) or server (capable, but the turn left the phone)?
10. **#150:** does it stay parked until a capability-narrowing mechanism exists, given #284's arming
    did **not** ship and 50+ MCP schemas will not fit 8,192 tokens? (stay parked / route anyway /
    cut)

---

## 8. Proposed bars — ROUTE NOW items only

**Only #222's no-phone slice is recommended for routing.** Bars pre-register in the #222 entry
before any code, per the post-#215 convention. A missed bar is a falsification, not a redefinition.

- **222-A (compile, no phone).** A scratch file constructing
  `Attachment(cgImage, orientation:)`, passing it into a `Prompt`, and calling
  `LanguageModelSession.respond(to:)` **type-checks clean** against the beta4 iOS SDK
  (`swiftc -typecheck`, target `arm64-apple-ios27.0`, `DEVELOPER_DIR` = Xcode-beta4). The exact
  invocation and its full output are recorded in the entry. **A compile FAILURE is a passing
  outcome of this lane's question and closes item 2 negatively** — record the diagnostic verbatim
  and stop; do not iterate toward a shape the SDK does not offer.
- **222-B (documentation truth, no phone).** The entry's API paragraph is corrected in place against
  the interface: `Transcript.ImageAttachment` (:2345) has **no public init** — construction runs
  through `extension Attachment where Content == ImageAttachmentContent` (:2784), and `Attachment`
  is `PromptRepresentable` (:2769). Correction lands in **#222 itself**, not only downstream, per
  THE CLOSE-OUT RULE. Same commit corrects the section heading, which no longer describes its own
  remaining contents (§3.2).
- **222-C (device, opportunistic — armed only if 222-A passes).** On device, a session handed an
  attached image answers a **viewer-only** question (dominant colour, or object count) correctly on
  **≥4 of 5 trials**, with a same-image control proving the answer was not derivable from OCR text.
  Explicitly **not runnable on the sim or the test host** (`Code=5000`); a green off-device result
  does not count and must not be reported as one. A miss falsifies *"the SDK's image surface is
  usable from our integration"* — it does not license a re-derivation of `#205`/`#207` in either
  direction, which stays item 3 and stays Owen's.

**No bars proposed for #242, #253, #150 or #149** — nothing is being routed for them. If Owen picks
option 3 in §7, #242's Shape-A falsifier gets its own bar written into #242 before it runs.

---

## Appendix — what this brief did NOT do

No device was used. No battery, probe, or generation was run. No Swift file, `OPEN_ITEMS.md` entry,
or plugin file was edited. The two Hermes calls made were read-only health checks against already-
running gateways (free under the live-install rule — no install was modified). Every claim in
§2 VERIFIED was read from the tree, the plugin install, or the beta4 `swiftinterface` at the paths
cited; everything taken on testimony is in §2 ASSUMED.
