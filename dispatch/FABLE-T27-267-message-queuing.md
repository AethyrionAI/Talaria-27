# FABLE — T27 #267: message QUEUING while a turn streams

> ## 🔢 NUMBER REASSIGNMENT 2026-08-09 — READ BEFORE FILING ANYTHING
>
> This dispatch proposes filing as **#300** (the queuing lane) and **#301** (the
> pre-existing defect where the compose outbox can drain mid-reconcile).
> **Both numbers were consumed during the Opus marathon and now belong to
> unrelated items:** #300 is `lane-gate.sh`'s misleading failure advice; #301 is
> a libdispatch main-queue assertion in the native voice path.
>
> **Use #306 for the lane and #307 for the outbox defect.** Confirmed
> 2026-08-09 that the outbox-mid-reconcile defect is **still unfiled anywhere**,
> so #307 is a genuine first filing, not a duplicate. Highest filed is **#303** —
> re-check before filing:
> ```bash
> grep -oE '^## [0-9]+' OPEN_ITEMS.md OPEN_ITEMS-ARCHIVE.md | grep -oE '[0-9]+$' | sort -n | tail -1
> ```
> **Numbers are never reused and never renumbered (#261).**


## 1. Header

**Label:** `FABLE` (streaming state machine × transcript identity — the two areas with this
project's worst defect density: #237, #246, #248, #275, #276, #278, #281, #282, #291, #294, #295)
**Item:** OPEN_ITEMS **#267** · **Proposed new number for the lane: #300** (see §9)
**Parent arc:** #251 → Plan C Phase 3 · **Plan of record:** `design/PHASE3-RUNS-MIGRATION-PLAN-2026-08-07.md`
**Repo base:** `main` @ `35c6234` · **Proposed branch:** `claude/t27-300-message-queuing`
**Written:** 2026-08-09. Every `file:line` below was read at that HEAD, not transcribed.

**Goal, one sentence:** let the user compose and commit the next message while a turn is still
running, hold it durably against the *thread*, and send it exactly once — and only when the turn
ended in a way that makes a follow-up meaningful.

**Sibling lane running in parallel:** `dispatch/FABLE-T27-283-3B-approvals.md` (slice 3B) proposes
**#298** and files **#299**. This dispatch therefore proposes **#300** and **#301**. Highest live
number at HEAD is **#297**.

---

## 2. THE ROUTING VERDICT

### Verdict: **STANDALONE — buildable now, and it should be built now.** But the decision is formally Owen's, and this dispatch does not pretend otherwise.

The plan's §2.6 says, verbatim, *"This is why #267 should be built inside slice 3C rather than
before it."* That sentence is real and I am not waving it away. Two things about its status matter:

1. **It is a recommendation on an OPEN question, not a ruling.** The plan itself puts this exact
   choice to Owen as **§5 Q7** — *"#267 queuing — build it inside 3C, or ship it standalone first
   (it needs nothing from the host)?"* — with "Inside 3C" as the recommendation. **#283's header
   records that only Q2 has been answered:** *"Q2 of the plan's §5 answered; the other eight
   questions stand as recommended/pending."* Q7 is one of the eight. So the routing is live, and
   this section is evidence for a decision Owen still has to make — not a decision I am making
   for him.
2. **#267's own entry pre-dates the plan and reaches the same place from the other side**, calling
   queuing *"the half that needs nothing upstream."* Both documents agree on the facts; they
   differ only on sequencing.

### Evidence FOR standalone

**(a) The dependency runs one way, and it runs the wrong way for "inside 3C."**
§2.6's four-row composer table gives the prose phase to *"app-held queue, fires on `run.completed`."*
That row **is** #267. 3C consumes the queue; the queue consumes nothing from 3C. Building #267
first does not duplicate 3C — it *delivers one of 3C's four doors early*, and leaves 3C with the
steer handler, the tool-boundary gate and the never-trust-`queued` pin, which is what 3C is
actually about.

**(b) 3C's blockers are real, and not one of them touches the queue.**
Plan §3's slice table gives 3C `depends on: 3A + a plugin deploy`. Unpacked at HEAD:
- **3A is done** — #283's device pass, 2026-08-07 evening, all four device bars MET with host-log
  evidence. So that half is clear.
- **The plugin deploy is not.** It is a live-install experiment under the standing rule (plan
  §4.5), needing Owen's per-slice go — which is **§5 Q6, also unanswered**. And for Owen's actual
  production host it needs **#271** (*"install the talaria plugin on the production host"*), whose
  header reads **NOT STARTED — no lane, no bars**.
- **#267 needs no host change of any kind.** No route, no plugin, no gateway bounce, no live-install
  go. It is `ChatStore` and the composer.

**(c) On the shipping default configuration, the steer door does not exist — so the queue door is
the only door.** Steering was proven on the wire (S1: BANANA→PLUM), but only via the plugin's
in-process reach into `APIServerAdapter._active_run_agents`, on the **runs** plane.
`UserSettings.swift:446` ships `useRunsTransport: Bool = false`, and `:410` documents it as the
Developer switch with *"Default OFF — the sessions path"* remaining default until 3E. So today,
and for every user until the 3E cutover, **every mid-turn send takes the queue door.** Shipping the
door that is always taken, before the door that is currently unreachable, is the right order.

**(d) The hard parts are disjoint.** The queue's difficulty is entirely in `ChatStore`: five
terminal arms, identity minting, durable thread-scoped persistence, and a nasty interaction with
`attemptReconcile`. Steer's difficulty is entirely host-side and stream-shaped: the plugin RPC, the
tool-result-boundary read, and the false-positive `{"status":"queued"}` ACK. The genuine overlap is
the composer's **door-naming vocabulary** — UI-layer, and small.

### The plan's counter-argument, honored rather than dismissed

§2.6's stated risk is *"designing the composer twice and unlearning the wording."* That risk is
**wording and shape, not state** — and it is neutralized only if the lane is bound to three
constraints. **If the lane cannot hold all three, the plan's recommendation wins and #267 waits
for 3C.** They are not optional; they are the price of the standalone verdict.

- **C1 — the composer names the door from day one.** A `ComposerDoor` enum ships in v1 with
  `.queued` implemented and `.steered` / `.interrupted` present as cases every switch must handle.
  The word **"sent"** never appears for a message that has not been posted. 3C then *fills in two
  cases*; it does not rewrite a boolean into an enum.
- **C2 — the readiness gate is `isTranscriptBusy`, never `isStreaming`.** 3C's tool-in-flight read
  refines *which* door is offered; it never changes *whether* a door is needed. Getting this wrong
  is #278 verbatim (`ChatStore.swift:124-139`).
- **C3 — a queued message mints no transcript row until it actually sends.** A steer produces no
  user row either — it is an injection, not a turn — so a queue that mints rows early would have to
  be torn out for 3C. Chip-not-row is the shape both doors share. This is also the identity ruling
  (§6), reached independently.

### What this verdict does NOT claim

It does not claim #267 completes the composer. **3C still owns two of §2.6's four rows** — the
tool-in-flight steer door and the interrupt-and-resend door. Interrupt-and-resend is deliberately
*out* of this lane: it is only honest on the runs plane, where `POST /v1/runs/{id}/stop` is a real
interrupt (3A-C, device-proven, `exit_code 130`). On the default sessions plane Stop is cosmetic
(S24), so an "Interrupt and resend" button there would promise something it cannot do. **v1 ships
one door and says so.**

---

## 3. VERIFIED STATE — what gates the composer today

### VERIFIED (read at `35c6234`)

**The text field is not locked. It never was.** `ChatInputBar`'s `TextEditor`
(`Talaria/Features/Chat/ChatInputBar.swift:121` region) has **no** `.disabled(isStreaming)`. The
user can already type a full message mid-turn. What is actually withheld is the **commit
affordance**, in exactly two places:

| # | site | what it does |
|---|---|---|
| 1 | `ChatInputBar.swift:452` — `actionButton`'s `if isStreaming` | The send arrow is **replaced** by the Stop button. There is no send control on screen at all during a turn. |
| 2 | `ChatInputBar.swift:131` — `guard !isStreaming, canSend else { return .ignored }` | The hardware-keyboard Return path refuses to fire while streaming. |

Three secondary affordances also hide on `isStreaming`: paste-image (`:176`), dictation (`:194`),
Talk mode (`:219`). Those are UX choices, not gates on sending.

**So #267 is not "unlock the composer" — the composer is already unlocked. It is "give the
composed text somewhere to go."** That reframing matters: it means no text-entry surgery, and it
means the feature is entirely about *what the commit gesture does*.

**Wiring:** `ChatScreen.swift:278-284` passes `isStreaming: chatStore.isStreaming` and
`onStop: { chatStore.cancelStreaming() }`; `ChatScreen.swift:1408` is `sendMessage()`, which clears
`messageText`/`pendingAttachments` and calls `chatStore.sendMessage(content, attachments:)` at
`:1423`.

**The two predicates, and why only one is correct here:**
- `ChatStore.swift:122` — `var isStreaming: Bool { streamingMessageID != nil }`
- `ChatStore.swift:139` — `var isTranscriptBusy: Bool { streamingMessageID != nil || pendingRun != nil }`
- `:124-135` documents exactly why the second exists: a dropped stream sets `streamingMessageID = nil`
  while `pendingRun` stays live and the reconcile loop keeps running, *"so for the whole reconcile
  window (minutes) `isStreaming` reads false while the run is very much alive."* That is #278, and
  it is the single most important line in this dispatch.

**A compose outbox already exists, and it is the right home — with one structural change.**
- `Talaria/Models/ComposeOutboxState.swift` — `PendingTurn { id, text, composedAt }`, text-only by
  design, persisted via `AppPersistenceStoreProtocol.swift:53-55` →
  `UserDefaultsAppPersistenceStore.swift:355-367`.
- **It is populated by exactly one terminal:** `ChatStore.swift:958` `.unreachable`, text-only arm
  → `composeOutbox.enqueue(id: clientMessageID, text: trimmedContent)` at `:971`, transcript row
  flipped to `.queued` at `:969`.
- **Its `id` IS the transcript row's `clientMessageID`** (`ComposeOutboxState.swift:12-14`: *"The
  transcript row's `clientMessageID`, so the drain can replace the queued bubble with the live
  re-send"*). That identity fusion is safe today **only because the row already exists** when the
  entry is minted. For a mid-turn queue no row exists yet — so the two ids must be separated. See §6.
- `drainComposeOutboxIfPossible()` (`:1966`) drains FIFO through the normal `sendMessage` pipeline,
  removing the transcript row **before** the re-send (`:1982`) so `hasPendingDuplicateMessage` does
  not swallow it, and re-orders a re-queue back to the front (`:2003-2016`). **That removal-first
  sequence is the precedent v1 must copy.**
- **Its trigger is reachability, not a run terminal:** `refreshDirectHealth()` (`:1925`) →
  `drainComposeOutboxIfPossible()` at `:1935`, run by the chat screen on appear and ~every 10s
  (`:1932-1933`).

**The five terminal arms of a turn**, all inside `sendMessage`'s `for await` (`ChatStore.swift:653-1023`):

| arm | line | what it leaves behind |
|---|---|---|
| `.finished` | ~`:899` | user row `.delivered` (`:881-885`), `streamingMessageID = nil`, `activeStreamRun = nil` |
| `.interrupted` — late duplicate | `:918` | `resolvedRunIDs` hit; placeholder removed, torn down quietly |
| `.interrupted` — real | `:938` | `armPendingRunRecovery` → `pendingRun` minted, reconcile armed, user row `.working` (`:945`) |
| `.unreachable` | `:958` | text-only → `.queued` + outbox entry; with attachments → `.failed` + system row |
| `.failed` | `:993` | `acceptedJobID == nil` → `.failed` + `onSendFailed()`; else `.sending` + `needsPollingFallback` |

Plus two paths that do **not** come through the loop:
- `cancelStreaming(hardStopHost: true)` (`:1267`) — the Stop tap. `settleStoppedUserMessage(as: .delivered)`
  at `:1391`, no `PendingRun`, no reconcile (this is #295 bar 295-B, shipped).
- `cancelStreaming(hardStopHost: false)` (`:641`, the continued-send expiration hook) — **splits**
  at `:1308`: if `hermesClient.currentRunIsServerRecoverable` (`ChatBackendRouter.swift:507`,
  `runningBrain == .hermes`) it arms recovery and settles `.working`; otherwise it settles
  `.delivered` exactly like a Stop (`:1338-1368`, `:1391`).

**Two blanket sweeps that a compose-time transcript row would walk into:**
- `restartPendingPollingIfNeeded()`'s exhaustion branch, `:2285-2295` — *every* `.sending` user row
  → `.failed`, plus `onSendFailed()` (an error haptic). Not targeted. Contrast
  `settleStoppedUserMessage` (`:1410+`), which #291 deliberately made targeted.
- `finalizeStaleSendsFromCache()`, `:502-539` — cold load flips every `.sending` user row to
  `.failed` (`:506-510`); `.queued` rows survive **only** if a matching outbox entry exists
  (`:517-524`).

**#292 is open at HEAD** (no fix note in the entry; `SessionsHermesClient.swift`'s producer is
still an unstructured `Task`). `activeRunContext` is a **single slot** —
`SessionsHermesClient.swift:101` declares it, `:136` overwrites unconditionally, `:144` clears only
when the run id matches.

### ASSUMED (stated as assumptions, not findings)

- **A1.** That the `.finished` arm is the only terminal where an unprompted follow-up is
  unambiguously wanted. This is a *product* judgement I am proposing, not something the code
  decides. §5 and §9 put it to Owen explicitly.
- **A2.** That depth 1 ("a next message, not a mailbox", #267's own words) is right for v1. Not
  measured; nobody has used the feature yet.
- **A3.** That the queued-message affordance belongs on the composer rather than in the transcript.
  Argued from identity in §6, but it is a design call with no precedent in this app.
- **A4.** That attachments stay out of v1, matching `ComposeOutboxState`'s existing text-only
  ruling (*"attachments have no durable wire-ready form to park here"*, `ComposeOutboxState.swift:8-9`).
  Unverified whether that constraint still binds after #283's `RunsTurnInput` reshape.

---

## 4. ⚠️ Tracker corrections

**T1 — #267's scope sketch describes a one-terminal feature, and three of the terminals it does not
mention shipped AFTER it was filed.** The entry says *"post it when `run.completed` lands"* and
lists edge cases as a parenthetical. Since 2026-08-06 the terminal landscape has been rewritten by
three landed lanes: **#291** (Stop now settles the user row `.delivered`), **#294** (Stop before the
first token removes the empty placeholder rather than making it terminal), and **#295** (expiration
arms real recovery, but **only** when `currentRunIsServerRecoverable`). *Recommended note:* "The
terminal set this entry assumed is stale — #291/#294/#295 landed after filing. The matrix in
`dispatch/FABLE-T27-267-message-queuing.md` §5 supersedes the parenthetical edge-case list."

**T2 — #267's "an app-held queue" understates the scope by one axis.** The queue must be held
against the **thread**, not the app: `abandonPendingRun(stopSpeech:)` (`ChatStore.swift:1154`) is
the teardown for thread switch / new chat / reset, and a message queued in thread A must not fire
into thread B. *Recommended note:* "thread-scoped and durable, not merely app-held."

**T3 — the plan's §2.6 row 3 is right about the door and wrong about the timing.** It reads
`stream lost, run still live | queue | "queued"`. Queuing is correct; **firing** there is a
corruption path (§10, trap 2). *Recommended supersession note in `design/PHASE3-RUNS-MIGRATION-PLAN-2026-08-07.md`
§2.6:* "row 3's queue is HELD until the pending run resolves — firing into a live `pendingRun` lets
`attemptReconcile` adopt the queued turn's reply as the dropped run's answer."

**T4 — NEW DEFECT, pre-existing, live on `main`, independent of this lane. Recommend filing as
#301.** `drainComposeOutboxIfPossible()` guards on `!isStreaming` (`ChatStore.swift:1967`) and its
trigger `refreshDirectHealth()` guards on `!isStreaming` (`:1926`) — **neither uses
`isTranscriptBusy`.** So during the reconcile window (`streamingMessageID == nil`,
`pendingRun != nil` — precisely the state `:127-135` documents) the offline outbox **can drain into
a live run**. `attemptReconcile` (`:2389`) then selects *the last Hermes message with
`timestamp > pending.sentAt`* (`:2391-2395`) — which is the **drained turn's** reply — and:
re-attaches the dropped run's `partialReasoning` to it (`:2424-2430`), stamps a `turnDuration`
measured from the **old** turn's `sentAt` (`:2439`), and re-pairs it with the **old** prompt via
`placingRecoveredReply(reply.id, prompt: promptText)` (`:2417-2418`, `:2456`). Reachable sequence:
turn 1 unreachable → turn 2 committed but its stream drops → health probe reports connected → drain
fires turn 1 → turn 1's answer is adopted as turn 2's. **This is the #278 shape in the one place
#278 did not sweep.** It is one guard line, and #300's lane changes that exact line — so *fix it
inside #300 and cite #301 in the commit*, rather than leaving it an unnumbered drive-by (#268).

**T5 — CLAUDE.md: nothing falsified by this lane.** Its SSE-taxonomy and `:8642` route sections are
consistent with HEAD (checked: `run.completed` carries usage; the runs stream's frames have no
`event:` lines and it already says so). No correction owed. Recorded because the close-out rule
requires the check, not just the corrections.

---

## 5. THE TERMINAL MATRIX

Read `HOLD` as: the message stays queued, visible, editable and cancellable; nothing is posted.
Read `FIRE` as: `sendMessage` runs, minting the row and the `clientMessageID` at that moment (§6).
Read `SURFACE` as: the chip changes wording to say the turn it was waiting on did not produce an
answer, and offers **Send now** / **Edit** / **Discard** — the #180 visible-degradation rule.

| # | how the turn ended | code site | queue action | why |
|---|---|---|---|---|
| 1 | **Completed** (`.finished`) | `ChatStore.swift:899` | **FIRE**, once, as soon as `!isTranscriptBusy` | The feature. The user's follow-up was composed against an answer that arrived. |
| 2 | **User pressed Stop** | `cancelStreaming(hardStopHost: true)`, `:1267` → `.delivered` at `:1391` | **HOLD + SURFACE. Never auto-fire.** | **The headline ruling.** Stop is "not this, stop spending." Auto-sending the next message immediately after would start a *new* run the user did not ask for, one gesture after they killed one. On the runs plane Stop is a real host interrupt (3A-C: `exit_code 130`), so firing would also re-engage a host the user just interrupted. Recommendation: **restore the text to the composer** rather than discard — Stop means "not that answer", not "forget what I typed". |
| 3 | **Stream dropped, run committed** (`.interrupted`, real arm) | `:938` `armPendingRunRecovery` → `pendingRun` live, user row `.working` | **HOLD** until `pendingRun == nil` — i.e. until `attemptReconcile` resolves (`:2464`) or the reconcile budget expires | Firing here is the corruption path of §4-T4: `attemptReconcile`'s `timestamp > pending.sentAt` filter (`:2391-2395`) would adopt the *queued* turn's reply as the dropped run's answer. `isTranscriptBusy` is exactly this gate. On budget expiry with no adoption → **SURFACE**, do not silently fire. |
| 4 | **Late-duplicate interrupt** | `:918`, `resolvedRunIDs` hit | **no-op** — whatever the queue was doing, it keeps doing | That run already adopted; this frame is noise (#237). The `isTranscriptBusy` gate handles it with no special case, which is the point. |
| 5 | **Unreachable** (host never got it) | `:958` | **DEMOTE into the same outbox, behind the failed turn, order preserved.** Never fire; never vanish. | The session is unreachable — firing is impossible and dropping is #180's exact prohibition. **This is why the mid-turn queue and the offline outbox must be ONE store** (§8, Task 1): two stores means two competing orders the moment this arm runs. If the turn carried attachments it takes the honest `.failed` dead-end instead (`:976-983`) — the queued message then **SURFACEs**. |
| 6 | **Failed outright** (`acceptedJobID == nil`) | `:993`, `:1013` `.failed`, `onSendFailed()` | **HOLD + SURFACE** | The follow-up was composed against an answer that never came. Auto-firing sends a non-sequitur into a session whose last turn errored. |
| 7 | **Failed after accept** (`acceptedJobID != nil`) | `:1013` `.sending`, `:1016` `needsPollingFallback` | **HOLD** — the turn is not over | Row stays `.sending` and the poll loop owns it. Resolve to row 1 or row 8. |
| 8 | **Poll exhaustion** | `:2285-2295`, blanket `.sending` → `.failed` + `onSendFailed()` | **HOLD + SURFACE** | Same reasoning as row 6. **Also the reason the queue mints no early `.sending` row** — this sweep is not targeted and would eat it (§6). |
| 9 | **Background budget expired, recoverable** | `cancelStreaming(hardStopHost: false)` + `currentRunIsServerRecoverable` → `:1308`, row `.working` | **HOLD** — identical to row 3 | #295's ruling: a real reconcile is watching. Same `pendingRun`, same corruption risk. |
| 10 | **Background budget expired, NOT recoverable** (local brain) | `:1338` else-branch → `.delivered`, `:1391` | **HOLD + SURFACE** | #295 is explicit that nothing is coming. `.delivered` here means "settled", not "answered" — so it must not be read as row 1. **This is the sharpest trap in the matrix: rows 2, 10 and 1 can all leave the user row `.delivered`.** The queue must therefore branch on the *terminal it observed*, never on the row's final status. |
| 11 | **Walk-away** (thread switch, new chat, reset) | `abandonPendingRun(stopSpeech:)`, `:1154` | **Queue travels with the departing thread; never fires into the arriving one** | The queue is thread-scoped (§4-T2). `abandonPendingRun` is the one teardown primitive every walk-away path calls (`:1136-1144`) — the clear/park belongs there, not hand-rolled per path. |
| 12 | **Process death mid-turn** | cold load → `finalizeStaleSendsFromCache()`, `:502` | **Survives relaunch; SURFACEs; never auto-fires on launch** | The turn it was waiting on is now `.failed` (`:506-510`). Auto-sending on cold launch would post a message the user has no memory of composing. |

**The one-line rule the matrix encodes: the queue auto-fires on exactly ONE terminal — a turn that
actually completed. Everything else holds and says why.** That is A1, and it is Owen's to confirm
(§9, O1).

---

## 6. IDENTITY RULING

### Ruling: the `clientMessageID` is minted at **SEND** time, inside `sendMessage` (`ChatStore.swift:578`), exactly as it is today. The queue entry carries its **own, separate** id and **no transcript row exists until the send fires.**

The queued message renders as a **composer-attached chip**, not as a transcript bubble.

### Why compose-time minting is wrong — four concrete failures, all at HEAD

1. **The poll-exhaustion sweep would eat it.** `:2285-2295` flips *every* `.sending` user row to
   `.failed` and fires `onSendFailed()`. A compose-time `.sending` row for a message that has not
   been sent would be failed — with an error haptic — by the *previous* turn's poll exhaustion.
   That is #291 wearing a new hat, and #291 was fixed precisely by making settlement **targeted**
   (`settleStoppedUserMessage`, `:1410+`).
2. **Cold load would fail it too.** `finalizeStaleSendsFromCache` `:506-510` runs the same blanket
   flip. A `.queued`-status row would survive (`:517-524`) — but only by matching an outbox entry
   by `clientMessageID`, which re-fuses the two identities this ruling separates.
3. **The duplicate guard would swallow the queue's own fire.** `hasPendingDuplicateMessage`
   (`:2211-2218`) matches `.sending` **or** `.queued` user rows by normalized content. A
   compose-time row would make the queued message a duplicate of itself, and `sendMessage` would
   return `false` at `:576`. The existing drain only works because it removes the row *first*
   (`:1982`) — a workaround, not a design.
4. **`attemptReconcile` would mis-time it.** It stamps `turnDuration` from `pending.sentAt`
   (`:2439`) and recovers the prompt by `pending.userMessageID` (`:2417-2418`). A row whose
   timestamp is "when the user typed it" rather than "when it was posted" corrupts both — silently,
   in the receipts.

### The counter-argument, and why it loses

Compose-time minting gives the queued message a stable identity for edit/cancel, and the project's
identity defects (#248, #275, #276, #278, #281, #282) are exactly the family that punishes unstable
ids. **The resolution is that both are satisfiable at once, because a queue entry is not a
transcript row.** Give the entry its own durable `queueEntryID` — stable from the moment the user
commits it, through edits, through relaunch — and let `sendMessage` mint the `clientMessageID` when
it posts. Two ids, two jobs.

Today `ComposeOutboxState.PendingTurn.id` fuses them, and `:12-14` says why: the row already
existed. **For a mid-turn queue it does not, and the fusion must be broken.** Concretely:
`PendingTurn` grows a distinct entry id and its existing `id` field becomes an *optional*
`transcriptRowID` — populated only for `.unreachable`-parked turns (which do have a row), nil for
mid-turn-queued ones. Every existing reader keyed on the old `id` (`:517`, `:1979`, `:1982`,
`:2007-2011`, and `historyAdoptsQueuedTurn` at `:1948`) must be audited in the same commit.

### The content-claim tier (#282)

**The chip-not-row ruling sidesteps it entirely, and that is the strongest argument for the chip.**
#282's defect is on the DEMAND side: a `.failed` user row can eat a claim minted by a *later*
identical prompt, because the demand is unbounded and order-keyed. A queued message that exists as
a row would be a second identical-content row sitting in the transcript for the whole duration of a
turn — a claim-eater by construction, and the exact ordering hazard #282 describes. **With no row,
there is nothing to claim and nothing to eat.** The claim is minted once, at send, by the one row
that has ever existed for that text. Bar **300-F** pins this.

### Ordering

FIFO, **depth 1** for v1 (#267's own "a next message, not a mailbox"). Depth 1 makes the ordering
question nearly vacuous *within* the mid-turn queue — but **not** across the store, because row 5
demotes a mid-turn entry into an outbox that may already hold offline-parked turns. **One store,
one order, oldest-first** (the existing drain's semantics, `:1978`), with the re-queue front-restore
at `:2003-2016` preserved. A second store would create two orders that meet for the first time
during a network outage, which is the worst possible time to discover the ambiguity.

---

## 7. PROPOSED BARS

Pre-registered here for the orchestrator to file **verbatim into the #300 entry before any code**
(#215 convention). Each states its **RED condition** — the concrete state of the tree in which the
test must fail — because a test written after the fix is pinned to the wrong thing (the tell being
a fix commit that never touches the test file). **Every unit bar must be demonstrated RED by
restoring the pre-fix behavior, and the lane records which line was reverted for each.**

| bar | claim | RED condition | test home | needs |
|---|---|---|---|---|
| **300-A** | The composer accepts a commit gesture while a turn is streaming, and the committed text is held — not posted. `sendMessage` is **not** called; `hermesClient.sendStreaming` call count is unchanged. | Fails on `main` today: `ChatInputBar.swift:452` offers no send control while `isStreaming`, so there is no gesture to make and no hold to observe. | `TalariaTests/MessageQueueTerminalsTests.swift` (new) | unit |
| **300-B** | **FIRE-ONCE on completion.** A held message posts exactly once after `.finished`, with exactly one new user row and one `clientMessageID`. Assert the **send count**, not the transcript's final appearance. | Revert the fire-on-terminal wiring → the message is held forever (count 0). Separately, remove the `!isTranscriptBusy` guard and drive `.finished` twice → count 2. Both arms must be shown RED; the double-fire arm is the #237 shape and is the one that will actually regress. | same file | unit |
| **300-C** | **STOP DOES NOT FIRE.** After `cancelStreaming(hardStopHost: true)` the held message is still held, `sendStreaming` was never re-invoked, and the text is restored to the composer. | Wire the fire to "any terminal" instead of the matrix → the Stop arm posts. This bar is the feature's single most important negative. | same file | unit |
| **300-D** | **The three `.delivered` terminals are distinguished.** Three arms — completion (row 1), Stop (row 2), non-recoverable expiration (row 10) — all leave the user row `.delivered`, and **only** the first fires. Assert on the observed terminal, never on `status`. | Implement the fire condition as `status == .delivered` → arms 2 and 3 both post. This is the trap most likely to be built by accident. | same file | unit, three arms |
| **300-E** | **A live `pendingRun` blocks the fire.** With `pendingRun` non-nil and `streamingMessageID` nil (the #278 window), the queue does not post; it posts only after `attemptReconcile` clears it. And: the reply adopted by `attemptReconcile` is the **dropped run's**, never the queued turn's. | Gate on `!isStreaming` instead of `!isTranscriptBusy` → the message posts mid-reconcile and the adoption assertion fails (this is §4-T4's mechanism, so the same test covers **#301**). | same file | unit |
| **300-F** | **No transcript row exists before the send.** Through hold, edit, cancel and relaunch, the transcript contains **zero** rows for the queued text; exactly one appears at fire, and its `clientMessageID` was minted by `sendMessage`. Corollary asserted in the same test: a poll-exhaustion sweep (`:2285`) and a cold-load scrub (`:502`) running while a message is held touch nothing. | Mint the row at compose time → both sweeps flip it `.failed` and `onSendFailed()` fires. | same file + `TalariaTests/ChatStorePersistenceTests.swift` | unit |
| **300-G** | **Unreachable demotes, preserving order.** A mid-turn-held message whose turn ends `.unreachable` lands in the **same** outbox behind the parked turn; the subsequent drain posts them oldest-first; neither is lost. | Keep a separate mid-turn store → the drain posts only the outbox's own entries and the held message is stranded (or posts out of order). | `TalariaTests/ContinuityFabricTests.swift` (extend — the existing outbox suite lives there, `:331-632`) | unit |
| **300-H** | **Thread-scoped.** A message held in thread A is not posted, not visible, and not fired when `abandonPendingRun` runs and thread B opens; returning to A restores it. | Store the queue on the store rather than keyed to the thread → it appears in B, and fires there. | `TalariaTests/ContinuityFabricTests.swift` | unit |
| **300-I** | **Survives relaunch without auto-firing.** Held → simulated process death → cold load: the message is present, the chip SURFACEs (the turn it waited on is `.failed`), and **nothing was posted during launch**. | Drive the fire off cold-load reconciliation → a post occurs at launch. | `TalariaTests/ChatStorePersistenceTests.swift` | unit |
| **300-J** | **The composer names the door and never says "sent."** The `ComposerDoor` switch is exhaustive over `.queued` / `.steered` / `.interrupted`; the rendered string for a held message contains no form of "sent"; and a held message renders a **cancel** affordance whose tap removes it with nothing posted. | Delete the enum for a `Bool` → the exhaustiveness assertion cannot compile against the 3C cases. Hardcode "Message sent" → the string assertion fails. This is constraint **C1** made testable. | `TalariaUITests/MessageIdentityUITests.swift` (extend) + unit for the enum | unit + XCUITest |
| **300-K** | **THE GATE.** `scripts/mac/lane-gate.sh` → literal **`GATE: PASS`**: Debug units **and** XCUITest **and** a green **Release** build, with the unit count **MOVED** from the baseline measured on this lane's own base head. | A no-op branch cannot satisfy a moved count. **Measure the baseline by running the gate on the base commit first — do not inherit a number from the tracker.** (Most recent recorded: 1839 Swift Testing + 12 XCUITest, #286's lane, 2026-08-08 — a reference point, not the baseline.) | the gate log | Mac |
| **300-L** | **DEVICE, Owen.** One real remote conversation: (i) compose mid-turn and watch it fire after the answer lands; (ii) compose mid-turn, press **Stop**, and confirm **nothing is posted** and the text is back in the composer; (iii) compose mid-turn, background the app past the stall guard so recovery arms, and confirm the message waits for the reconcile rather than posting into it. Evidence for (ii) and (iii) is the **host's `agent.log`** — no `POST` for the held message — not the phone's screen. | n/a (device bar) | `dispatch/DEVICE-PASS-RUNNING-LIST.md` | **device** |

**300-A through 300-K need no device and no host change.** Build and land them first; 300-L queues
behind the existing device-pass list.

---

## 8. TASK BREAKDOWN

TDD throughout: the RED condition in each bar is written and observed **before** the implementing
edit. **`xcodegen generate` after adding any Swift file.**
`DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer` in every shell.

**T0 — file #300 (and #301).** The orchestrator files §7's bars verbatim, §5's matrix, §6's ruling,
and §9's open questions into `OPEN_ITEMS.md` **before any code**. Also files §4-T4 as **#301** and
records that #300's lane fixes it. Also lands the §4 T1/T2/T3 supersession notes upstream (into
#267 and the plan's §2.6) — close-out rule, same docs commit.

**T1 — one store, two triggers.** `Talaria/Models/ComposeOutboxState.swift`: break the id fusion
(§6) — add a durable entry id and a `reason` discriminator (`.unreachable` / `.heldDuringTurn`);
demote the existing `id` to an optional `transcriptRowID`. **Audit every reader in the same commit:**
`ChatStore.swift:517`, `:971`, `:1735` (`retryMessage`'s `composeOutbox.remove`), `:1948`
(`historyAdoptsQueuedTurn`), `:1979`, `:1982`, `:2007-2011`. Persistence needs no protocol change
(`AppPersistenceStoreProtocol.swift:53-55` already round-trips the type) but the decode path must
tolerate old payloads — `UserDefaultsAppPersistenceStore.swift:355` returns a default on failure,
so a schema break silently empties a real user's outbox. **Add a decode-compatibility test.**
→ bars 300-G, 300-I.

**T2 — the hold.** `Talaria/Stores/ChatStore.swift`: `func holdComposedTurn(_ text: String) ->
Bool`, thread-scoped, depth 1, persisted immediately (the `sendMessage` precedent at `:598-608` —
persist before anything can die). **Mints no transcript row.** → 300-A, 300-F, 300-H.

**T3 — the terminal matrix.** `ChatStore.swift`: a single `ComposerDoor`-adjacent resolution point
that each terminal arm reports its outcome to — **not** twelve scattered edits, and **not** a read
of the row's final `status` (300-D exists to forbid that). Wire: `:899`, `:918`, `:938`, `:958`,
`:993`, `:1267`'s two branches, `:1154`, `:2285`. Clear/park in `abandonPendingRun` (`:1154`), which
`:1136-1144` documents as *the* teardown primitive for exactly this reason. → 300-B/C/D/E.

**T4 — the fire.** Gate strictly on `!isTranscriptBusy && !isDrainingComposeOutbox`, reusing the
drain's remove-row-then-send discipline (`:1978-1994`) so `hasPendingDuplicateMessage` never
swallows the fire. **Fold in #301: tighten `drainComposeOutboxIfPossible`'s `!isStreaming`
(`:1967`) and `refreshDirectHealth`'s (`:1926`) to `!isTranscriptBusy`** — one line each, covered
by 300-E. → 300-B, 300-E.

**T5 — the composer.** `Talaria/Features/Chat/ChatInputBar.swift`: `actionButton` (`:452`) gains a
third state — during a turn, offer **both** Stop and a queue-commit control (the send arrow with
queue affordance), not one replacing the other. Lift the `isStreaming` guard on the hardware-Return
path (`:131`) to route to the hold. Add the chip: text, **Edit**, **Cancel**, and the door name.
`Talaria/Features/Chat/ChatScreen.swift:278-284` and `:1408-1427` wire it. **C1 lives here** — the
`ComposerDoor` enum with `.steered` / `.interrupted` present and unimplemented. → 300-A, 300-J.

**T6 — RED verification pass.** For every unit bar, restore the pre-fix line named in its RED
column, run the single test, record the failure, restore. **Record the reverted line per bar in the
#300 entry.** A bar whose RED was never observed does not count as met.

**T7 — the gate.** Measure the baseline on the base head first, then
`scripts/mac/lane-gate.sh`. It takes minutes — **background it and poll the log with an `until`
loop; never arm a Monitor and never wait for a notification.** Requires literal `GATE: PASS`,
Release green, count MOVED. → 300-K.

**T8 — close-out.** T0's upstream notes land as *dated supersessions in the stale claims' own homes*.
#300's entry records each bar's evidence and its observed RED. 300-L is appended to
`dispatch/DEVICE-PASS-RUNNING-LIST.md`.

---

## 9. WHAT IS OWEN'S TO DECIDE

- **O1 — THE ROUTING (blocking, and it is literally his open question).** Plan §5 **Q7** asked
  standalone-vs-3C and is unanswered. §2 recommends **standalone, under constraints C1/C2/C3**,
  against the plan's own "inside 3C". Both readings are on the table with their evidence. **No code
  before this.**
- **O2 — the Stop ruling (blocking; A1).** §5 row 2 says a queued message **never** auto-sends after
  Stop, and the text returns to the composer. The alternative — auto-send, treating Stop as "end
  this turn, start mine" — is coherent and is what some chat clients do. I recommend against it
  (Stop on the runs plane is a real host interrupt; re-engaging one gesture later is hostile), but
  it is a product call and it is the feature's defining behavior.
- **O3 — the SURFACE terminals (A1's tail).** Rows 6/8/10/12 hold-and-surface rather than auto-fire.
  Is "the turn before it failed, so I did not send this — Send now?" the right answer, or should a
  failed turn auto-retry the follow-up? I recommend surface: a non-sequitur into a broken session
  is worse than one extra tap.
- **O4 — depth (A2).** Depth 1 per #267's own sketch. Confirm, or ask for a real mailbox.
- **O5 — attachments (A4).** v1 is text-only, inheriting `ComposeOutboxState`'s ruling
  (`ComposeOutboxState.swift:8-9`). Worth re-checking against #283's `RunsTurnInput` reshape if he
  wants images queueable.
- **O6 — the chip, not a bubble (A3).** §6 argues it from identity and from #282. It is still a
  visible design change to the composer and he should see it before it ships.
- **O7 — file #301 separately, or fold it silently?** §4-T4 is a real pre-existing defect in a line
  this lane edits. I recommend filing it and fixing it here, per #268 ("a phase name is not a
  filing").
- **O8 — walk-away semantics (row 11).** A held message travels with its thread. Confirm the
  alternative (discard on thread switch) is not preferred.

**No live-install go is needed for any part of this lane.** That is worth stating plainly: unlike
3B's 298-H/I and unlike 3C, nothing here touches a host.

---

## 10. TRAPS AND INTERACTIONS

**Trap 1 — #292's producer is still running when the queue fires.** #292 is **open** at HEAD (no fix
note; the producer is still an unstructured `Task` with no cancellation inheritance). On the runs
plane an abandoned turn's producer keeps polling for up to `runsPollBudget` (120s). A queued send
firing at terminal therefore overlaps a live producer. Consequences, traced:
`activeRunContext` is a **single slot** (`SessionsHermesClient.swift:101`); the new run overwrites
it at `:136`; the old producer's late `clearActiveRunContext(matchingRunID:)` is run-id-guarded
(`:144`) so it correctly no-ops. **So the queue does not make #292 worse** — but #283's disclosed
limitation stands: with two runs in flight, **Stop can address the wrong one**. Do not "fix" #292
inside this lane; do note the overlap in #300's entry so the next reader does not rediscover it.

**Trap 2 — `attemptReconcile` will adopt the wrong reply if the queue fires early.** Fully traced in
§4-T4 and pinned by bar 300-E. It is the single most expensive mistake available in this lane,
because it produces a *plausible* transcript — the right answer attached to the wrong prompt, with
somebody else's reasoning and a fabricated duration. Nothing errors.

**Trap 3 — three terminals leave the user row `.delivered`.** Completion (`:881-885`), Stop
(`:1391`), and non-recoverable expiration (`:1391` again). **Any fire condition written as
`status == .delivered` ships bug #2 and bug #10 on day one.** Bar 300-D exists solely for this.

**Trap 4 — the content-claim tier (#282).** Its DEMAND side is unbounded and order-keyed, so a
`.failed` row can eat a later identical prompt's claim. A queued message rendered as a transcript
row would sit in the transcript with identical content for a whole turn — exactly the ordering
hazard. The chip-not-row ruling (§6) removes the hazard rather than working around it. **Do not
"improve" the design by giving the queued message a bubble.**

**Trap 5 — #93's outbox is the right home, and its `id` fusion is the one thing that must change.**
`ComposeOutboxState.swift:12-14` fuses the entry id with the transcript row's `clientMessageID`, and
that is *correct* for its current sole producer (`:958` `.unreachable`, where the row already
exists). It is *wrong* for a mid-turn hold, where no row exists. Breaking the fusion touches
`historyAdoptsQueuedTurn` (`:1948` — #240's already-delivered guard), the cold-load stranded-row
scrub (`:517-524`), `retryMessage`'s removal (`:1735`), and the drain's front-restore
(`:2007-2011`). **All four in the same commit** — a partial migration here is silent.

**Trap 6 — `hasPendingDuplicateMessage` will swallow the fire.** `:2211-2218` matches `.sending` or
`.queued` by normalized content and `sendMessage` returns `false` at `:576`. The existing drain
survives only by removing the row first (`:1982`). Copy that order exactly. Note that
`drainComposeOutboxIfPossible` treats a swallowed send as a successful dedupe (`:1995-2001`) — the
mid-turn fire must **not** inherit that leniency silently; a swallowed fire is a bar-300-B failure,
not a no-op.

**Trap 7 — the queued text and the composer's live text can diverge.** `ChatScreen.sendMessage()`
clears `messageText` at `:1412` before the async send. If Stop restores the held text (row 2) while
the user has since typed something new, one of them is lost. Decide and test it; do not let the
last writer win.

**Trap 8 — `retryMessage` (#279) already removes an outbox entry** (`:1735`
`composeOutbox.remove(id:)`). With one store and two reasons, retrying a failed turn must not
silently delete a *held* message that happens to collide. Audit in T1.

**Trap 9 — the gate is the only check that sees Release.** #218: three promoted clauses sat inside
`#if DEBUG` while production read them, and `main` could not build in Release for two days behind
1461 green Debug tests. Any `#if DEBUG` or gating edit in this lane must be Release-verified —
300-K is not a formality.

**Trap 10 — stale test binaries.** `test-without-building` will happily re-run an old `.xctest` and
report green at the OLD count. After adding tests, confirm the reported count **MOVED**; if it did
not, purge `<dd>/Build/Intermediates.noindex` and run plain `test`. This repo's DerivedData hash is
per-worktree — resolve it from `info.plist`, never from memory.

---

## 11. CLOSE-OUT

The lane does not close until all of the following are true in the **same** commit series:

1. **#300's entry carries every bar's evidence and its observed RED**, including which line was
   reverted to produce each RED. A bar whose RED was never observed is not met.
2. **The §4 corrections have landed UPSTREAM, in their own homes** — a dated supersession note on
   **#267** (T1, T2), and one in `design/PHASE3-RUNS-MIGRATION-PLAN-2026-08-07.md` **§2.6** (T3).
   Not only downstream in #300.
3. **§5's matrix is copied into #300's entry**, not left only in this dispatch. A dispatch is where
   a decision was argued; the tracker is where it lives (#268).
4. **#301 is filed and its fix is recorded against it**, with the #300 commit cited.
5. **The plan's §5 Q7 is marked answered** with Owen's actual ruling — whichever way it goes. Q7
   currently reads as pending and must not stay that way after a lane has acted on it.
6. **300-K's gate log is quoted** — literal `GATE: PASS`, Release green, the baseline number, the
   new number, and the delta.
7. **300-L is appended to `dispatch/DEVICE-PASS-RUNNING-LIST.md`** with its three arms and their
   host-log evidence requirement spelled out.
8. **If 3C later lands steer, `ComposerDoor`'s `.steered` case is filled in — not replaced.** If a
   future lane finds itself deleting the enum, constraint C1 failed and this dispatch's routing
   verdict was wrong; say so in writing rather than quietly rebuilding.
