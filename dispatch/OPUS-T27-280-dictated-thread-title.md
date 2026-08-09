# OPUS T27 #280 — a voice-only thread gets no on-device title, and the tracker names the wrong cause

**Tier that EXECUTES this lane: OPUS.** Written 2026-08-09 from a HEAD code read
(`t27-295-expiration-recovery`, `04af0a7`). No code was written for this brief.

**Goal:** a thread whose only user turns were SPOKEN gets a real on-device
generated title — routed through the existing local-brain card generator
(`LocalIntelligenceService.conversationCard`), per Owen's ruling 2026-08-09 —
instead of falling through to the placeholder and rendering its own preview
twice.

> **⚠️ READ §4 BEFORE §5.** #280's stated mechanism is not the cause. A lane
> that implements the entry as written ships a **no-op** and can honestly
> believe it fixed something. That is the single most important thing in this
> document.

---

## 1. What Owen ruled, and what this lane is not

**Owen, 2026-08-09:** the card should carry an **on-device GENERATED title**,
routed through the existing local-brain generator — not the raw first-user-message
heuristic, and not a won't-do.

That settles the product question #280 left open (*"should a voice thread's card
show the transcript text?"* — the entry says it "needs its own bar because the
display semantics … are a product question, not a mechanical one"). **The answer
is: generate, don't echo.** The ruling is dated and must be written into the
entry; right now the entry still reads as undecided.

This lane is **not** a rewrite of #61's card generator, **not** a change to
`degenerateCardReason`'s tuning, and **not** a change to what the connected-mode
drawer shows (that surface is server-fed and never touches `conversation.title` —
#61's own surface correction, still true at HEAD: `LocalChatBackend.swift:1973`
is the only builder that reads it).

---

## 2. Verified state

Everything below was read at HEAD. Line numbers are from
`t27-295-expiration-recovery` @ `04af0a7`; re-check them if the branch moves.

### VERIFIED

**The sender taxonomy**
- `Talaria/Models/MessageSender.swift:3-8` — five cases. A **dictated** user turn
  is `.voiceUser`; its reply is `.voiceHermes`. The file's own doc comment
  (`:10-11`) uses the word *"DICTATED"* for `.voiceUser`, which is what #280's
  "dictated" means.
- `Talaria/Models/MessageSender.swift:25-27` — `isUserAuthored` = `.user ||
  .voiceUser`, added by #275 after four sites matched `.user` alone.
- **There is no `isAgentAuthored` on `MessageSender`.** The only such predicate
  is `Talaria/Models/AgentAttachmentSidecar.swift:156-158`, deliberately
  `private` with the comment *"this question has exactly one asker."*

**Who produces `.voiceUser` / `.voiceHermes`**
- `Talaria/Stores/ChatStore.swift:1634-1653` — `voiceTranscriptMessages(from:)`
  is the **only** producer in the whole tree (grepped `Talaria/` + `Shared/`).
  It emits a `.system` banner `"[Voice session ended]"` first, then one row per
  finalized spoken turn.
- Composer **dictation** (`Talaria/Features/Chat/ChatInputBar.swift:193-213`,
  `:522-560`) merges the transcript into the composer's `text` and sends a normal
  `.user` message. **Those threads title correctly today** — they are not this
  defect.

**The trigger path**
- `Talaria/Stores/ChatStore.swift:1550-1596` — `appendVoiceTranscript(_:postToHermes:)`
  appends the transcript rows, saves the cache, fires `onConversationChanged`,
  syncs the journal, and optionally POSTs a context turn **whose reply is
  discarded** (`:1585-1587`). **It never calls `finalizeOnDeviceIntelligence()`.**
- `finalizeOnDeviceIntelligence()` (`ChatStore.swift:2485-2488`) has exactly
  **two** call sites: `:1073` (a streamed turn settling) and `:2474` (the #295
  reconcile settling). Grep confirms no third.

**The generator's own guards**
- `ChatStore.swift:2496-2506` — `generateConversationCardIfNeeded()` returns
  early unless it finds
  `first(where: { $0.sender == .hermes && $0.status == .delivered && !content.isEmpty })`.
  **`.voiceHermes` does not match `== .hermes`.**
- `ChatStore.swift:2512-2514` — the user side is
  `first(where: { $0.sender == .user }).map { normalizedRetryContent(for: $0) } ?? ""`.
  **`.voiceUser` does not match `== .user`**, so `firstUserText == ""`.
- `ChatStore.swift:2815-2821` — `normalizedRetryContent(for:)` maps the synthetic
  `"[N attachment(s)]"` placeholder to `""` and otherwise returns trimmed content.
  It is an instance method but touches **no instance state**.

**What an EMPTY user side actually does (this is the load-bearing one)**
- `Talaria/Services/Live/LocalIntelligenceService.swift:448-466` — `fallbackCard`:
  `firstMeaningfulLine(of: "")` is `nil`, so `titleSource = assistantLines.first ?? ""`
  and the preview deliberately steps to the reply's **second** meaningful line so
  the two never echo. The comment at `:453-458` says so explicitly and cites the
  2026-07-11 device-pass FAIL it was written for.
- `LocalIntelligenceService.swift:62-122` — the guided path prompts with both
  sides; an empty user side still yields a reply-derived title, and **every**
  failure branch funnels to `fallbackCardLoggingDegeneracy`. `conversationCard`
  cannot return an empty title unless the reply itself is empty.
- **So an empty `firstUserText` is a DESIGNED-FOR input that produces a
  reply-derived card.** `ChatStore.swift:2508-2511`'s comment says exactly this,
  and it is correct.

**What "blank" actually renders as**
- `Talaria/Models/Conversation.swift:7` — `defaultTitle = "Hermes"`.
- `Talaria/Services/Live/LocalChatBackend.swift:1976` — `title: conversation.title
  == Conversation.defaultTitle ? nil : conversation.title` → **nil**. Same at
  `:1991` for the stored `LocalSessionSummary` row.
- `LocalChatBackend.swift:1977` — `preview: conversation.generatedPreview ??
  conversation.lastMessage?.content` → for a voice-only thread that is the **last
  spoken assistant line** (non-empty).
- `Talaria/Features/Chat/ChatScreen.swift:555-557` — a nil title falls back to
  **the preview** as the row's title line; `:558-564` uses **the same preview** as
  the subtitle. So the drawer row shows **one string twice** — precisely the
  duplicate-card shape `fallbackCard`'s comment records as a device-pass FAIL.
  With no preview at all it reads `"Untitled session"`.
- `ChatScreen.swift:1489` — the header/`/title` readback shows the literal
  `"Hermes"`. Not blank; **wrong**.

**Persistence / eligibility**
- `ChatStore.swift:1088-1100` — `recordLocalOriginAfterSettledTurn` counts
  `$0.sender == .hermes`, so a voice-only thread never reaches `assistantTurns == 1`
  and is never "born local" by that route.
- `ChatStore.swift:1188-1193` — `persistDepartingLocalSession` still upserts it on
  walk-away whenever `isLocalSessionThread` is true (standalone = no host
  configured). **So the row does reach the drawer.**

**Testability**
- `ChatStore.swift:300` — `var localIntelligence: LocalIntelligenceService?` is a
  **concrete type**, not a protocol. There is **no seam to inject a fake
  generator.** `AppContainer.swift:1225` wires the real one.
- `TalariaTests/VoiceTranscriptTests.swift` already exercises
  `ChatStore.voiceTranscriptMessages` as a `nonisolated static` pure function —
  that is the house pattern this lane should follow.
- `TalariaTests/AppStoresTests.swift` has `pollUntil` for fire-and-forget
  assertions (used at `:1704`, `:1682`).

### ASSUMED — not settled by a code read, and the lane must not present these as facts

- **That the thread Owen means is a voice-SESSION-only thread.** #280 was filed
  from a #78 **code read**, not a device sighting; no log line or screenshot is
  quoted in the entry. The code read is fully consistent with the symptom, and
  `.voiceUser` is the only sender that fits the entry's own word "dictated" — but
  no device evidence exists. **Say so in the entry.**
- **Which surface Owen saw** — the drawer row (preview shown twice) or the chat
  header (literal `"Hermes"`). Both are wrong; they are wrong differently.
- **Whether an on-device model produces a GOOD title from a spoken transcript.**
  Never measured. Spoken text has no line structure, so `meaningfulLines` will
  see one long line — the guided path handles that, the truncation fallback
  produces a 48-char slice of the first spoken sentence. Acceptable, unmeasured.
- **Whether `promptInputBudget` short-circuits `trimmed()` for a typical spoken
  turn** (`LocalIntelligenceService.swift:254-258` skips the tokenizer when
  `text.utf8.count <= budget`). Matters only for the trap in §7.

---

## 3. The defect

**Three independent blockers stand between a voice-only thread and a title.
Ordered outermost first. Each one alone is sufficient to produce the symptom.**

**B1 — the generator is never invoked.** `appendVoiceTranscript`
(`ChatStore.swift:1550`) is the only path a voice-only thread takes, and it does
not call `finalizeOnDeviceIntelligence()`. Nothing else will: the `postToHermes`
context turn's reply is discarded (`:1585-1587`) and never enters the transcript,
so the two real call sites (`:1073`, `:2474`) are never reached. **The title stays
`Conversation.defaultTitle` forever.**

**B2 — the eligibility guard rejects the thread.**
`generateConversationCardIfNeeded` requires a `.hermes` reply
(`ChatStore.swift:2502`). A voice thread's replies are `.voiceHermes`. Even if B1
were fixed, the function would return at the guard.

**B3 — the user side is dropped.** `first(where: { $0.sender == .user })`
(`:2513`) misses `.voiceUser`, so `firstUserText == ""`. **This is the tracker's
stated cause and it is the least consequential of the three** — it degrades the
title's *quality* (reply-derived instead of exchange-derived), it does not
suppress the title.

**Downstream, once all three are cleared:** the title stops being `defaultTitle`,
so `LocalChatBackend.sessionInfo` stops mapping it to nil, so the drawer row stops
using its preview as its own title, so the row stops showing one string twice.

**Second-order, and worth fixing in the same lane:** on a MIXED thread (voice
first, then typed), B2/B3 make the card generate from the **typed** exchange while
the function's own doc comment promises *"the conversation's first completed
exchange"* (`:2490-2495`). The first exchange was spoken. Applying both predicates
makes the doc comment true again — which is a behavior change and therefore needs
a bar (280-C), not a silent side effect.

---

## 4. ⚠️ Tracker corrections

**These are the centrepiece of this brief. Every one of them must land in
`OPEN_ITEMS.md` #280 — upstream, at the stale claim's own home — in the SAME
commit as the fix, per THE CLOSE-OUT RULE.**

### 4.1 The stated mechanism is true as a fact and FALSE as a cause

> #280 as written: *"`ChatStore`'s title source uses `first(where: { $0.sender ==
> .user })`, which yields empty text when every user turn was dictated."*

The predicate does yield empty text. **Empty text is not what produces a blank
title.** `LocalIntelligenceService.fallbackCard` (`:448-466`) is explicitly built
for an empty user side — it borrows the reply's first line for the title and
steps the preview to the reply's second line so the two never echo — and
`ChatStore.swift:2508-2511` says so in a comment sitting three lines above the
line #280 blames. A thread that reached the generator with `firstUserText == ""`
would come back with a real, reply-derived title.

### 4.2 The real outermost cause is not in the entry at all

`appendVoiceTranscript` (`ChatStore.swift:1550-1596`) **never calls
`finalizeOnDeviceIntelligence()`**. The card generator is not reached on the voice
path by any route. This is B1 and it is invisible from the entry's text.

### 4.3 The second cause is not in the entry either

The `firstReply` guard at `ChatStore.swift:2502` matches `.hermes` only, so the
function early-returns on a voice-only thread even when invoked. This is B2.

### 4.4 THE NO-OP TRAP — the entry's suggested fix ships nothing

> #280 as written: *"Fix is presumably the same `isUserAuthored` predicate."*

**Applying `isUserAuthored` at `:2513` and nothing else changes no observable
behavior whatsoever**, because the function it lives in is never called for the
affected threads (B1) and would return at its own guard if it were (B2). A lane
that makes that one-line change, sees a green suite, and closes #280 has shipped a
no-op and can report it in good faith. **Task 2 below exists to make that
impossible to do accidentally.**

### 4.5 "Cosmetic" undersells it by one notch

The entry says *"Cosmetic."* It is minor and it is not a blocker — but the
rendered result is the drawer row printing **the same string as both its title and
its subtitle**, which is the exact failure mode #61's `fallbackCard` comment
records as a **device-pass FAIL** (2026-07-11, *"repeats the first line on both
lines"*). We fixed that shape once, deliberately, and this path reintroduces it
through a different door. Keep "minor"; drop "cosmetic".

### 4.6 The product question is answered and the entry does not know it

The entry says the display semantics are *"a product question, not a mechanical
one."* **Owen ruled on 2026-08-09:** generated, on-device, through the existing
generator. Record the ruling with its date in the entry; a decision that lives
only in a dispatch is not filed (#268).

### 4.7 A predicate promotion falsifies a comment upstream

`AgentAttachmentSidecar.swift:153-155` justifies keeping `isAgentAuthored` private
with *"#275's `isUserAuthored` exists because FOUR sites needed one answer; this
question has exactly one asker."* If Task 5 promotes the predicate to
`MessageSender`, **that comment becomes false in the same commit** and must be
corrected there, not only noted here.

### 4.8 A note for #61, not a correction to it

#61's surface correction (*"#61 can only be verified in standalone mode"*) is
**still true at HEAD** — `LocalChatBackend.swift:1973` is the sole reader of
`conversation.title`. No change owed. Named so the lane does not re-derive it.

---

## 5. Pre-registered bars — PROPOSED HERE, MUST BE WRITTEN INTO #280 BEFORE ANY CODE

**#280 currently carries the words "Bars pre-register here before any code" and no
bars.** Per CLAUDE.md's *"Where the BARS live"*, these go into the
`OPEN_ITEMS.md` #280 entry, in writing, in a commit that lands **before** the
first line of implementation. **This dispatch is not the filing.** Do not edit
`OPEN_ITEMS.md` from this brief's authority — the executing lane writes them,
with Owen's routing.

Numbers are proposals; refine the wording, not the strictness.

---

**280-A — a voice-only thread ends up with a real title.**
After `appendVoiceTranscript` settles a session carrying ≥1 spoken user turn and
≥1 spoken reply, `chatStore.conversation?.title != Conversation.defaultTitle`.

- *Evidence that settles it:* a unit test on the `ChatStore` path with the real
  `LocalIntelligenceService` wired, polling to a non-default title.
  **Assert non-default, never exact text** — the model either generates (device,
  nondeterministic) or throws to the truncation fallback (test host, Code 5000
  no-assets); both must pass the same bar.
- *Device needed:* **no.**
- *This is the bar that catches the no-op.* It is red under B1 alone.

**280-B — the title is derived from what was SPOKEN.**
The extracted input function returns the spoken user line as `userText` and the
spoken reply as `assistantText` for a voice-only conversation — not `("", reply)`.

- *Evidence:* pure-function unit test on
  `ChatStore.conversationCardInputs(for:)` (Task 1's extraction).
- *Device needed:* **no.**
- This is the bar `isUserAuthored` actually earns. Without it the predicate change
  is unmeasured.

**280-C — a mixed thread titles from its FIRST exchange, and a spoken exchange
counts as one.**
A conversation whose first exchange is spoken and whose second is typed yields
inputs from the **spoken** pair.

- *Evidence:* pure-function unit test.
- *Device needed:* **no.**
- Pre-registered because it is a **behavior change** on threads that title fine
  today. If Owen would rather a mixed thread keep titling from the typed turn,
  that is a legitimate call — but it has to be made before the code, not
  discovered after.

**280-D — typed threads do not move.**
A typed-only conversation yields the same inputs and the same title as before the
change, and a first user row carrying only the `"[N attachment(s)]"` placeholder
still normalizes to `""`.

- *Evidence:* new pure-function rows plus the existing suite staying green.
- *Device needed:* **no.**
- The attachment-placeholder row is the one that must **not** be "fixed" — it is
  deliberate (`ChatStore.swift:2508-2511`).

**280-E — the generator still never overwrites a human title, and still runs
once.**
A conversation retitled by hand before the voice append keeps its title; two
`appendVoiceTranscript` calls do not produce two generations.

- *Evidence:* unit test setting a title first; a second test asserting
  `isGeneratingConversationCard` re-entrancy still holds.
- *Device needed:* **no.**
- The async re-check at `ChatStore.swift:2527-2530` already guards this; the bar
  pins that the new call site does not route around it.

**280-F — the device confirmation, ROUTED not restated.**
`dispatch/DEVICE-PASS-RUNNING-LIST.md` **§F2** already carries a `#61` row
(*"Create local sessions, read the drawer — on-device titles + previews are
distinct, not near-identical. Must be standalone"*). **Add one clause to that
existing row**: *"…including a session whose only user turns were spoken — its
row must show a real title, and the title line must not be the same string as the
subtitle."*

- *Evidence:* the standalone drawer, phone in hand.
- *Device needed:* **yes — but it is not a blocker on the merge.** A–E are all
  unit-testable and are what the gate proves. F is confirmation on the real
  surface, and it rides an existing sitting.
- **Do NOT open a second device row.** #61's own rule: *"One queue — a check that
  lives in two places drifts."*

---

## 6. Task breakdown

Real paths, real names. TDD throughout; the RED steps are mandatory and each one
names the reason the test must fail.

### Task 0 — file the bars and the corrections (no code)

Write §5's bars and §4's corrections into `OPEN_ITEMS.md` #280, including Owen's
2026-08-09 ruling with its date. Commit alone:
`docs(#280): bars pre-registered + the tracker's mechanism corrected — the stated cause is not the cause`.
**No implementation commit may precede this one.**

### Task 1 — extract the inputs as a pure function, behavior UNCHANGED

`Talaria/Stores/ChatStore.swift`:

```swift
/// The `{userText, assistantText}` the card generator runs on, or nil when
/// the conversation has no completed exchange to label yet.
nonisolated static func conversationCardInputs(
    for conversation: Conversation
) -> (userText: String, assistantText: String)?
```

Reproduce **today's predicates exactly** (`.hermes` + `.delivered` + non-empty
reply; first `.user`; `normalizedRetryContent`). Promote `normalizedRetryContent`
to `nonisolated static` — it reads no instance state (`:2815-2821`) — and leave
its instance callers working through the static. Rewire
`generateConversationCardIfNeeded` to call it. **Pure code motion; the suite must
stay green with no test edits.**

New file `TalariaTests/ConversationCardInputTests.swift` — **characterization
tests written against the DEFECT, before the fix:**

- `voiceOnlyThreadYieldsNoCardInputs()` — a banner + `.voiceUser` + `.voiceHermes`
  conversation returns **nil**. **Passes today.** This is the honest fail-first
  artifact: it records the defect in executable form before anything changes,
  which is the shape the "test written after a defect" trap exists to force.
- `typedThreadYieldsUserAndReply()` — pins the working case.
- `attachmentPlaceholderNormalizesToEmptyUserText()` — pins 280-D's deliberate case.

**New Swift file ⇒ `xcodegen generate` is mandatory before the next build.**

### Task 2 — flip the predicates, and WITNESS THE RED

Add to `Talaria/Models/MessageSender.swift`, beside `isUserAuthored`:

```swift
/// The senders that represent a turn the ASSISTANT produced — streamed
/// (`.hermes`) and SPOKEN (`.voiceHermes`). #280: a voice-only thread's
/// replies are `.voiceHermes`, so a `== .hermes` eligibility test rejects
/// the whole thread.
var isAgentAuthored: Bool { self == .hermes || self == .voiceHermes }
```

Change `conversationCardInputs` to use `isAgentAuthored` for the reply and
`isUserAuthored` for the user side.

**In the same commit, INVERT the characterization test** into
`voiceOnlyThreadYieldsTheSpokenExchange()` (280-B), and add
`mixedThreadYieldsTheSpokenFirstExchange()` (280-C).

**Mandatory RED step, recorded in the commit message:** revert the two predicates
to `== .hermes` / `== .user`, run the suite, and confirm
`voiceOnlyThreadYieldsTheSpokenExchange` fails **because the function returns nil**
(not because a string mismatched, not because of a compile error). Restore. A RED
that fails for a different reason is not evidence.

### Task 3 — invoke the generator on the voice path (this is the actual fix)

`ChatStore.appendVoiceTranscript` (`:1550`): add `finalizeOnDeviceIntelligence()`
**after** the `if let conversation { … journal?.sync(…) }` block that closes at
`:1570`, and **before** `guard postToHermes else { return }` at `:1572` — so it
runs on both branches, and outside the `postToHermes` Task at `:1575`.

Test in `TalariaTests/ConversationCardInputTests.swift` (or a sibling; keep it in
the same new file to avoid a second `xcodegen` beat):

- `voiceOnlyThreadGetsAGeneratedTitle()` (280-A) — build a `ChatStore` with a real
  `LocalIntelligenceService`, call `appendVoiceTranscript(session, postToHermes:
  false)`, `pollUntil { store.conversation?.title != Conversation.defaultTitle }`.
  **Assert non-default only.**

**Mandatory RED step:** delete the `finalizeOnDeviceIntelligence()` call, run,
confirm the test fails on the poll timing out with the title still `"Hermes"`.
Restore.

### Task 4 — the guards that must survive

Same file:
- `manualTitleSurvivesAVoiceAppend()` (280-E) — `setConversationTitle("Trip notes")`
  before the append; assert it is untouched afterwards.
- `secondVoiceAppendDoesNotRegenerate()` (280-E) — two appends, one generation.

### Task 5 — the upstream comment correction (CLOSE-OUT RULE)

`Talaria/Models/AgentAttachmentSidecar.swift:153-158` — its private
`isAgentAuthored` now has a public twin. Either route the sidecar through
`MessageSender.isAgentAuthored` and delete the private copy, or leave it and
correct the *"exactly one asker"* comment to say why it stays local. **Do not
leave the comment standing unchanged; it is false the moment Task 2 lands.**

### Task 6 — device row + gate + PR

- Append 280-F's clause to §F2's existing `#61` row in
  `dispatch/DEVICE-PASS-RUNNING-LIST.md`. One row, not two.
- Run the gate (§8).
- PR title: `fix(#280): a voice-only thread gets a generated title — the generator was never invoked`.

---

## 7. Traps and interactions

**The no-op trap, restated because it is the one that will actually bite.**
`isUserAuthored` at `:2513` alone changes nothing. If the lane's diff touches only
that line, the lane is wrong no matter how green the suite is. 280-A is red under
B1; it is the bar that cannot be satisfied by the entry's suggested fix.

**`localIntelligence` is a concrete type — there is no fake.** `ChatStore.swift:300`.
Bars A and E ride the real `LocalIntelligenceService`, which behaves differently by
environment: on the test host `isAvailable` is true but generation throws
`Code=5000` (no assets) and the deterministic truncation fallback runs instantly;
on a device with assets, real guided generation runs and takes seconds. **Never
assert exact title text; give `pollUntil` a budget that tolerates a real
generation.** Introducing a protocol seam for the generator is a bigger change
than this lane wants — if you reach for it, raise it rather than smuggling it in.

**The `tokenCount()` device hazard.** `conversationCard` → `trimmed(_:toTokenBudget:)`
→ `measuredTokenCount` → `model.tokenCount(...)`
(`LocalIntelligenceService.swift:254-280`). `tokenCount()` concurrent with a live
FoundationModels streaming turn kills that turn on device
(`ModelManagerError 1001` → "error -1"). The two existing call sites all run
**after a turn settles**, which is why this has never bitten. Keep the new call on
the same side of that line: after the append and persist, **not** inside the
`postToHermes` Task, and never on a path that can run while the local brain is
mid-turn. Note `trimmed` short-circuits entirely when `text.utf8.count <= budget`
(`:257`), so ordinary spoken turns will usually not reach the tokenizer at all —
usually is not never.

**`finalizeOnDeviceIntelligence` also fires `condensePendingReasoning()`**
(`:2487`). On a voice thread there is no reasoning to condense, and the function
guards on `applicationState == .active` and a `.hermes` sender at `:2553-2560`
(note: **`.hermes`, not `isAgentAuthored`** — deliberately out of scope here;
condensing a spoken reply is a different question and does not belong in this
lane. If you touch it, it needs its own bar).

**A voice-only thread is not "born local."** `recordLocalOriginAfterSettledTurn`
(`:1088-1100`) counts `.hermes` turns, so the store-membership route never fires
for it. The row still reaches the drawer through `persistDepartingLocalSession`
(`:1188-1193`) in standalone. **This lane does not change that** — widening
`recordLocalOriginAfterSettledTurn`'s predicate would alter #190B's
born-local semantics and the paired-mode contamination rule it exists to prevent.
Leave it; if it looks wrong, file it, do not fix it here.

**Paired mode is a different surface.** With a host configured, the drawer is
server-fed (`SessionsHermesClient.listSessions`) and never reads
`conversation.title`. The generated title still improves the chat header, but the
drawer row will not change. Do not write a bar that expects it to.

**`xcodegen generate`** after adding `TalariaTests/ConversationCardInputTests.swift`
— `project.yml:64-74` lists directories, and XcodeGen bakes explicit file
references at generation time, so a new file on disk is invisible until you
regenerate.

**Do not re-tune `degenerateCardReason`.** #61 pinned its thresholds with four
tests and an explicit "no length condition on the new branch, deliberately." A
spoken title that trips the guard falls back to truncation, which is the designed
behavior, not a bug this lane found.

---

## 8. Close-out

**The gate.** `scripts/mac/lane-gate.sh` — Debug suite (units + XCUITest) **and** a
Release build, positive marker required from each. It takes minutes, so background
it and poll the log with an `until` loop; **never arm a Monitor and never wait on a
notification.**

```bash
cd /Users/owenjones/Documents/Claude/Talaria-27
nohup scripts/mac/lane-gate.sh > /tmp/lane-gate-280.log 2>&1 &
until grep -qE 'GATE: (PASS|FAIL)' /tmp/lane-gate-280.log; do :; done
grep -E 'GATE: (PASS|FAIL)' /tmp/lane-gate-280.log
```

The literal string `GATE: PASS` is the only acceptable result. Absence of failure
text is not success (`lane-gate.sh:18-25`).

**Confirm the test count MOVED.** New tests were added; if the reported count did
not change, `test-without-building` re-ran a stale `.xctest`. Purge
`<dd>/Build/Intermediates.noindex` and run plain `test`. Resolve the DerivedData
hash from `info.plist`, never from memory — this repo is
`Talaria-gzpowyfsuofejnbsytskngrskzkm`, and every worktree gets its own.

**Upstream text this lane's result FALSIFIES — all of it corrected in the same
commit, per THE CLOSE-OUT RULE:**

| Where | What becomes false | Correction owed |
|---|---|---|
| `OPEN_ITEMS.md` #280 body | *"`first(where: { $0.sender == .user })` … yields empty text"* named as the cause | Dated supersession: empty user text is a designed-for input; the real causes are B1 (`appendVoiceTranscript` never calls `finalizeOnDeviceIntelligence`) and B2 (the `.hermes` reply guard) |
| `OPEN_ITEMS.md` #280 body | *"Fix is presumably the same `isUserAuthored` predicate"* | That fix alone is a no-op; record why, so it is not re-suggested |
| `OPEN_ITEMS.md` #280 body | *"the display semantics … a product question"* | Owen ruled 2026-08-09: generated on-device title. Record the ruling and its date |
| `OPEN_ITEMS.md` #280 heading | *"Cosmetic"* | Minor, yes; but the render is #61's duplicate-card FAIL shape through a new door |
| `OPEN_ITEMS.md` #280 | no bars, despite *"Bars pre-register here"* | Task 0 |
| `AgentAttachmentSidecar.swift:153-155` | *"this question has exactly one asker"* | Task 5 |
| `dispatch/DEVICE-PASS-RUNNING-LIST.md` §F2 `#61` row | silent on spoken-only threads | One added clause (280-F) — **not** a new row |

**Nothing in `CLAUDE.md` is falsified by this lane.** Checked: its ChatStore,
FoundationModels and #61 material is all still accurate at HEAD.

**The PR.** Branch off `main`. Body states which bars are MET with the evidence
line for each, quotes the `GATE: PASS` line, names the two RED steps and what
each failed on, and says plainly that **280-F is owed on device and is not
claimed**. Owen routes the merge.
