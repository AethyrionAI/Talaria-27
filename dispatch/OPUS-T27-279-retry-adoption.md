# OPUS T27 #279 — `retryMessage` removes the failed row without telling the mirror

> **⚠️ STALENESS + SEQUENCING BANNER, 2026-08-10.** Verified at `35c6234`;
> PRs #288–#294 merged since — including #306's ChatStore lane — and
> `ChatStore.swift:1999`'s doc comment now carries a "corrected #279,
> 2026-08-09" note from a later review fix (see #293(b), which is residue OF
> that fix). **Re-verify every anchor and the entry's premises at lane start.**
> And this item is in the claim/adoption FAMILY: the #299 fix
> (`dispatch/FABLE-T27-299-adoption-identity.md`) and #282's ruled guard both
> change what a `.failed` user row does in the merge. **Preferred order:
> #299 → #282 → this lane** — if run earlier, re-derive this dispatch's RED
> against whatever has landed, and expect the fix to shrink.

**Goal:** make a retry's removal of the failed user row reach the backend's
mirror, so the retried turn cannot be resurrected below the new one — the
`truncateTranscript` guarantee (#78), applied to the one history-mutating path
that lane deliberately did not touch.

**Written BEFORE any code.** Bars below are PROPOSED; per CLAUDE.md ("Where the
BARS live") they must be pasted into `OPEN_ITEMS.md` #279 **before the first
line of code is written**. This dispatch is not their home.

**Verified against the working tree at `35c6234`** (branch `main`,
2026-08-09). Every line number below was read at that commit, not copied from
the tracker.

> **Number collision, read this first.** Tracker item #279 is NOT GitHub PR
> #279 (which was #283's runs-transport PR — see `OPEN_ITEMS.md` #290's header,
> *"PR #279's independent review"*). Two live sequences share these digits.
> Say "tracker #279" in every commit message and PR body.

---

## 1. Verified state

### VERIFIED (read at `35c6234`)

| what | where | fact |
|---|---|---|
| the defect site | `Talaria/Stores/ChatStore.swift:1739` | `conversation?.messages.removeAll { $0.id == message.id }` — a bare array mutation inside `retryMessage(_:)` (`:1732`) |
| the primitive it bypasses | `Talaria/Stores/ChatStore.swift:1778` | `truncateTranscript(from:reason:)` — removes `index...`, then calls `adoptLocalTranscript()` (`:1784`) |
| what adoption actually does | `Talaria/Stores/ChatStore.swift:1807-1814` | `persistence.saveConversationCache` → `onConversationChanged?()` → `journal?.sync` → **`hermesClient.adoptTruncatedConversation(conversation)`**. That last call is the whole point: it is the only thing that edits the backend's mirror. |
| the local brain writes the user row before generating | `Talaria/Services/Live/LocalChatBackend.swift:525` (streaming) and `:353` (sync) call `appendUserMessage` (`:1318`) | the mirrored row is `Message(id: clientMessageID, clientMessageID: clientMessageID, sender: .user, status: .delivered)` |
| the local brain never un-writes it | `LocalChatBackend.swift` — grep for `removeAll`/`removeLast`/`popLast` returns **one** hit, `:1554`, a `String.dropLast` in the repetition breaker | no failure path pops a mirrored user row |
| the failure that leaves the row mirrored | `LocalChatBackend.swift:646` — `continuation.yield(.failed(failureMessageForActiveTier(error)))`, inside the generation loop's `catch`, i.e. **after** `:525` | generation errors mirror the row |
| the failure that does NOT | `LocalChatBackend.swift:493-497` — the availability gate yields `.failed` and `return`s **before** `:525` | an unavailable-brain refusal never mirrors anything |
| the merge that resurrects it | `ChatStore.swift:886-889` | post-stream: `mergeConversationMetadata(from: conversation, into: hermesClient.currentConversation)` — the mirror is the refresh BASE |
| what a `.failed` turn looks like on screen | `ChatStore.swift:993-1014` | with `acceptedJobID == nil` the streaming placeholder is **replaced** by a `.system` row (`:996-1000`) and the user row is set `.failed` (`:1012-1013`). So the failed user row is followed by a system error row. |
| retry is offered on ANY failed row | `Talaria/Features/Chat/MessageBubble.swift:211` and `:319`, wired at `Talaria/Features/Chat/ChatScreen.swift:1026` | the affordance is `if message.status == .failed` — no "is it the last row" condition |
| a `.failed` row can sit mid-transcript | `ChatStore.swift:502-524` `finalizeStaleSendsFromCache` flips every cached `.sending` user row to `.failed` on cold load; `:2285-2292` does the same on poll exhaustion | so "the failed row is the tail" is not an invariant |
| the re-send can be swallowed | `ChatStore.swift:1757` calls `await sendMessage(...)` and **discards** the `Bool`; `sendMessage` is `@discardableResult` (`:568`) and returns `false` from the empty guard (`:575`) or `hasPendingDuplicateMessage` (`:576`, defined `:2211-2218`) | a swallowed retry deletes the row with nothing sent |
| the restore primitive that exists for exactly that | `ChatStore.swift:1794` `restoreTruncatedRows(_:at:)` — private, id-deduped, re-adopts; used by `regenerateReply` at `:1858-1864` | `retryMessage` does not use it |
| the Hermes mirror is only a fetch cache | `Talaria/Services/Live/SessionsHermesClient.swift:766-768` — `adoptTruncatedConversation` assigns `currentConversation` and nothing else | the gateway session is untouched; `regenerateReply`'s own doc says so (`ChatStore.swift:1823-1829`) |
| the existing retry tests | `TalariaTests/ChatStorePersistenceTests.swift:686` `retryUsesADictatedProducingTurnAsItsSource` (275-C); `TalariaTests/AppStoresTests.swift:2519` (attachment restore) | **neither asserts anything about the mirror.** 275-C asserts only `client.sentPrompts`. |
| the double | `TalariaTests/ChatStorePersistenceTests.swift:341` `MirroringReplyClient` (+ `MirrorShape` `:345`, `mirror()` `:422`, `interruptsInsteadOfFinishing` `:375`, `adoptedMessageCounts` `:370`), built by `makeMirroredStore` `:470` | it can interrupt a turn but **cannot fail one**, and `mirror()` always appends BOTH the user row and the reply |

### ASSUMED (not proven by execution in this pass)

- **A1.** That a real device reproduces the duplicate. The mechanism is
  closed by construction above, but no device run has been done; 279-E exists
  to settle it.
- **A2.** That the `.hermes` reply rows of prior settled turns do *not* also
  re-append on the same merge. They have no content-claim tier at all
  (`unconfirmedLocalMessages` restricts it to `sender == .user`,
  `ChatStore.swift:2751`), so they may already double on server-sourced
  merges. **Out of scope here** — but if 279-A's baseline shows it, file it
  rather than fixing it in this lane.
  *(2026-08-10: A2's suspicion was REAL — #282's lane measured it, filed it
  as tracker #299, and #299's lane fixed it the next day:
  `ChatStore.serverIdentityAdoptions`, turn-anchored adoption at the merge.
  Assistant rows still have no claim TIER; they are confirmed by adoption
  instead. See OPEN_ITEMS #299.)*
- **A3.** Which `.failed` sub-path Owen actually hit. The tracker filing
  doesn't say. The bars are written for the generation-failure path
  (`LocalChatBackend.swift:646`), which is the one that mirrors.

---

## 2. The defect

`retryMessage` is the last history-mutating path in `ChatStore` that mutates
`conversation.messages` directly. #78 established that this is only half of a
removal:

> *"every backend keeps its OWN mirror of the thread, and this store treats
> that mirror as an authoritative refresh source … A truncation that never
> reaches the mirror is undone within one tick"* — `ChatStore.swift:1764-1771`

The sequence, all verified above:

1. A local-brain turn fails after generation starts. `appendUserMessage`
   (`LocalChatBackend.swift:525`) has already put the user row in
   `currentConversation` with `id == clientMessageID` and `status: .delivered`.
   ChatStore sets its own copy `.failed` (`ChatStore.swift:1012-1013`).
2. The user taps retry. `retryMessage` removes the row from
   `conversation` only (`:1739`). **`adoptTruncatedConversation` is never
   called, so the mirror still holds the row.**
3. `sendMessage` re-sends the same text with a **new** `clientMessageID`
   (`:578`). The local brain appends a *second* user row to the mirror.
4. The turn finishes; `:886-889` merges with the mirror as the BASE. The
   mirror's rows are the base rows, so the removed turn is back — and this
   time below nothing, above everything, exactly where it was, with the
   retried copy beneath it. Two identical user bubbles.

The tier-3 content claim cannot absorb it: the mirrored rows carry
`clientMessageID`, so both are confirmed at tier 2 (`:2750`) and both are
BASE rows — the claim tier only decides which *local* rows get re-appended, and
these are not local-only rows.

**Second defect in the same eight lines, not in the tracker filing.** The
removal at `:1739` is unconditional; the re-send at `:1757` can be swallowed by
the duplicate guard (`:2211`) — a byte-identical turn still `.sending` or
`.queued` elsewhere in the thread. When that happens the failed row is deleted
and nothing is sent. That is the precise residual `regenerateReply` was given
`restoreTruncatedRows` for (`:1858-1864`) and `retryMessage` never got.

---

## 3. ⚠️ Tracker corrections

Corrections go UPSTREAM, into `OPEN_ITEMS.md` #279 itself, in the same commit
as the fix (THE CLOSE-OUT RULE). The orchestrator files them; do not edit
`OPEN_ITEMS.md` from this dispatch.

1. **"The user row of a failed turn IS in the local brain's mirror
   (`appendUserMessage` runs before generation)" is true for ONE of the two
   failure paths.** `LocalChatBackend.swift:493-497` — the availability gate —
   yields `.failed` and returns *before* `appendUserMessage` at `:525`. A
   refusal-to-run failure leaves nothing in the mirror and cannot resurrect.
   The claim holds for generation failures (`:646`). The entry should say
   which.

2. **"Fix shape: route it through the primitive like `/retry` and `/undo` now
   are" is not literally implementable.** `truncateTranscript(from:)` removes
   `index...` — *to the end of the transcript*. `retryMessage` removes ONE row
   and is reachable on any `.failed` row anywhere in the thread
   (`MessageBubble.swift:211`, and `finalizeStaleSendsFromCache`
   `ChatStore.swift:502-511` manufactures mid-transcript `.failed` rows on
   every cold load after a mid-stream death). Literal routing would delete
   every turn below the retried one. **The correct reading is "reach the
   mirror", not "truncate to the end"** — see Task 2.

3. **The entry omits the swallowed-re-send hole** (§2, second defect). It is
   in the same function, has the same #78 lineage, and is cheaper to fix now
   than to re-open. Bar 279-C covers it.

4. **The entry does not scope the Hermes path.** `SessionsHermesClient`'s
   mirror is a fetch cache (`SessionsHermesClient.swift:766-768`); the gateway
   session still holds the turn. On that path this fix stops the *cache* from
   re-serving the row and nothing more — the documented `/retry` caveat
   (`ChatStore.swift:1823-1829`) applies unchanged. Say so, or the next reader
   will read 279-B as a promise the code cannot keep.

---

## 4. Pre-registered bars — PROPOSED

**Paste into `OPEN_ITEMS.md` #279 before any code.** Each is falsifiable and
names what settles it.

- **279-A (unit, characterization — must be written and GREEN *before* the
  fix, and must stay green after).** On a `.localBrain`-shaped mirroring
  double, drive a turn to `.failed` *after* the user row has been mirrored,
  then `retryMessage` that row, then let the retried turn finish. Assert the
  merged transcript's user-row count. **This bar records TODAY'S number
  first** — if the pre-fix number is not 2, the mechanism in §2 is wrong and
  the lane stops and re-diagnoses rather than proceeding. Evidence: the
  asserted count, quoted verbatim in the entry, from both sides of the fix.
  No device.

- **279-B (unit, fails today — the defect):** same setup as 279-A; after the
  retried turn settles, exactly **one** user row carrying the retried text
  survives, and it is the row minted by the retry (its `id` is not the failed
  row's `id`). Evidence: `messages.filter { $0.sender == .user }.count == 1`
  plus the id inequality. Expected RED before the fix with the count at 2. No
  device.

- **279-C (unit, fails today — the swallowed re-send):** arrange a retry whose
  `sendMessage` returns `false` via `hasPendingDuplicateMessage`
  (`ChatStore.swift:2211`) — a byte-identical `.queued` or `.sending` user row
  elsewhere in the thread. Assert the failed row is **still present** and the
  backend was not asked to send (`client.sentPrompts` unchanged). Today the
  row is gone and nothing was sent. Evidence: both assertions. No device.

- **279-D (unit, no over-reach — the mid-transcript case):** a thread whose
  `.failed` user row sits at index 0 with two later *successful* exchanges
  below it. After `retryMessage` on that row, **every row below it survives**
  (count and contents pinned explicitly). This is the bar that fails if anyone
  implements correction #2 literally. Evidence: the full
  `messages.map(\.content)` array. No device.

- **279-E (unit, fixture fidelity — 281-C's lesson, applied before it costs a
  day again):** the double used by 279-A/B must reproduce what
  `LocalChatBackend` does on a generation failure and not an invented shape:
  (i) the user row is mirrored with `id == clientMessageID` **and**
  `clientMessageID` set, matching `LocalChatBackend.swift:1318-1338`; (ii) on
  a failed turn the reply is **not** mirrored (nothing reaches
  `appendAssistantMessage`); (iii) the double records every
  `adoptTruncatedConversation` call so 279-B can prove the mirror was told,
  not merely that the count came out right. Evidence: the three assertions,
  green on both sides of the fix (a fidelity pin should be — recorded honestly
  as such, per 281-C). No device.

- **279-F (device, Owen):** on the LOCAL BRAIN, force a turn to fail after it
  starts generating (Airplane mode will not do it — that is the
  `.unreachable` path; use a prompt that trips a generation error, or the
  Developer forced-trip harness). Tap retry on the failed bubble. **The
  question appears exactly once**, with the retry-time bubble, and stays that
  way after leaving the thread and returning. Expected RED until this lands.

**Falsification stated in advance.** If 279-A's pre-fix count is 1, the mirror
is not the resurrection source and §2 is wrong — the lane reports that and
stops. If 279-B goes green but 279-F still shows two bubbles on device, the
duplicate has a second source (the server transcript on the Hermes path, or
A2's assistant-row hole) and the fix is incomplete, not wrong.

---

## 5. Task breakdown (TDD, watched RED)

All paths absolute-from-repo-root; the repo is
`/Users/owenjones/Documents/Claude/Talaria-27`.

**Task 0 — branch.** `claude/t27-279-retry-adoption` off `main` at `35c6234`.

**Task 1 — the fixture, first (279-E).**
`TalariaTests/ChatStorePersistenceTests.swift`, in `MirroringReplyClient`
(`:341`):
- add `var failsAfterMirroringTheUserRow = false` beside
  `interruptsInsteadOfFinishing` (`:375`);
- when set, `sendStreaming` mirrors **only the user row** (the existing
  `mirror()` at `:422` appends both — split it, or add a `replyMirrored: Bool`
  parameter) and then yields `.failed("generation failed")`
  (`StreamingUpdate.failed` — `Talaria/Models/StreamingUpdate.swift:54`);
- `adoptedMessageCounts` (`:370`) already records the adopt calls — keep it and
  assert on it in 279-B.
Write `theFailingLocalBrainMirrorMatchesTheRealAppendLog` (279-E). Run it. It
must be green immediately — record that it is a fidelity pin whose RED was
"the capability did not exist", the way 281-C is recorded.

**Task 2 — 279-A, the baseline, BEFORE touching production.** Write
`aRetriedFailedTurnLeavesTheMirrorHoldingTheOldRow` asserting the *current*
count (expected 2). Run it green. **Quote the number in the tracker entry.**
This is the step that makes 279-B's RED mean something.

**Task 3 — watch 279-B/C/D go RED.** Write all three
(`aRetryLeavesExactlyOneUserRowForTheRetriedText`,
`aSwallowedRetryPutsTheFailedRowBack`,
`retryingAMidTranscriptFailedRowKeepsEverythingBelowIt`) against unmodified
production. Run them. **Record the failure text verbatim** — the count, the
id, the `sentPrompts` array. A bar with no quoted RED is not a watched RED.

**Task 4 — the fix, in `Talaria/Stores/ChatStore.swift`.** Smallest correct
shape, per correction #2:
- give `retryMessage` an index (`firstIndex(where:)`) instead of
  `removeAll(where:)`, remove the single row, and then **route the adoption
  through the same tail as the truncation primitive** — i.e. call
  `adoptLocalTranscript()` (`:1807`). If the reviewer prefers one named
  entry point, add a sibling to `truncateTranscript` (e.g.
  `removeRow(at:reason:) -> Message?`) that does removal + `adoptLocalTranscript()`
  + the same `chatLog.notice` shape, and have `retryMessage` call it. Do NOT
  call `truncateTranscript(from:)` — 279-D is the bar that kills that.
- capture the removed row and its index; if `await sendMessage(...)` returns
  `false`, put it back with `restoreTruncatedRows([removed], at: idx)`
  (`:1794`, already private-in-type and id-deduped) and log the same way
  `regenerateReply` does at `:1863`.
- comment every changed line with `#279` and the reason, matching the density
  of the surrounding code.

**Task 5 — confirm GREEN, then prove the test is not pinned to the wrong
text.** Run 279-A..E green. Then **restore the bug** (revert only the
`adoptLocalTranscript()` call, keeping the index refactor) and confirm 279-B
goes RED *for the stated reason* — user-row count 2, not a crash or a
different assertion. Restore the fix; confirm GREEN. Do the same for the
restore half: delete the `restoreTruncatedRows` branch, watch 279-C go RED,
put it back. **Record both RED texts in the entry.** (This step exists because
a post-fix test is usually pinned to text the fix never touched.)

**Task 6 — the gate.** Background it and poll; never arm a Monitor, never wait
on a notification:

```bash
cd /Users/owenjones/Documents/Claude/Talaria-27
TALARIA_GATE_LOGDIR=/tmp/gate-279 nohup scripts/mac/lane-gate.sh > /tmp/gate-279.log 2>&1 &
```

then poll with a bounded loop, e.g.
`until grep -qE 'GATE: (PASS|FAIL)' /tmp/gate-279.log; do sleep 30; done; tail -40 /tmp/gate-279.log`.
The gate runs the Debug suite (units + XCUITest) **and a Release build** and
requires a positive marker from each (`scripts/mac/lane-gate.sh:47-52`,
`:192-200`, `:268-277`). **Confirm the reported unit count MOVED** — a
`test-without-building` style stale `.xctest` will happily re-report the old
number.

---

## 6. Traps and interactions

- **#78** — this lane extends #78's invariant to the one path it left out. Do
  not weaken `truncateTranscript`; add beside it.
- **#275** — `retryMessage`'s source selection (`ChatStore.swift:1745-1750`)
  uses `isUserAuthored`. Do not touch it; 275-C
  (`ChatStorePersistenceTests.swift:686`) must stay byte-unmodified. If the
  fix forces an edit to 275-C, the fix is wrong.
- **#90 (compose outbox)** — `retryMessage` opens with
  `composeOutbox.remove(id:)` + `persistComposeOutbox()` (`:1735-1736`).
  Adoption calls `journal?.sync` (`:1812`), which clamps the waterline. Order
  matters: keep the outbox removal FIRST, then the row removal + adopt, then
  the send. 279-C's `.queued` fixture is the one that will notice if this is
  reordered.
- **#282 (the very next lane)** — it changes `unconfirmedLocalMessages`
  (`:2737`), the function that decides which local rows the merge re-appends.
  **#279 changes what the mirror CONTAINS; #282 changes how local rows are
  matched against it.** They are independent mechanisms in one seam. Land #279
  first (see §7).
- **#248 / #281** — untouched here, but 279-B's assertion runs through
  `mergeConversationMetadata`, so a regression in the claim tier will surface
  as a 279-B failure. If 279-B fails for a *claim* reason rather than a
  *mirror* reason, that is #282's territory — report, do not patch across.
- **#56** — `finalizeStaleSendsFromCache` (`:502`) is what makes 279-D's
  mid-transcript fixture a production shape rather than a contrived one. Cite
  it in the test's doc comment.
- **#197** — the local brain marks a turn non-retryable once it has emitted
  observable activity (`LocalChatBackend.swift:530-535`). That is the
  BACKEND's retry, not this one; don't conflate them in the commit message.
- **#223** — the Hermes half of this fix is bounded by the gateway echoing no
  `clientMessageID` and keeping every turn. Both are on the deletion path.
  Note it; do not build around it.
- **A2 (assistant rows)** — if 279-A's baseline shows prior `.hermes` rows
  doubling too, that is a NEW finding. File it for a number; do not absorb it.

---

## 7. Close-out

**Gate:** `scripts/mac/lane-gate.sh`, backgrounded and polled, literal
`GATE: PASS` required, unit count MOVED.

**Upstream text this result falsifies** (correct in the SAME commit, at the
claim's own home — CLAUDE.md, THE CLOSE-OUT RULE):
- `OPEN_ITEMS.md` **#279** — corrections 1–4 of §3, plus the measured bars.
- `TalariaTests/ChatStorePersistenceTests.swift:684-687` — 275-C's doc comment
  describes `retryMessage` without mentioning that its removal never reached
  the mirror. Add the pointer once #279 lands.
- `ChatStore.swift:1762-1776` — `truncateTranscript`'s doc says it is
  *"**The one way** to remove rows from the rendered transcript"* and that was
  **false at the time it was written**: `retryMessage:1739` removed rows and
  never came through here. Correct that sentence in the same commit, whichever
  fix shape wins.

**PR:** one PR, title `fix(#279): a retry's removal reaches the backend mirror`.
Body must state (a) the pre-fix 279-A count, (b) both watched-RED texts, (c)
that the Hermes path is bounded to the fetch cache, (d) `GATE: PASS` with the
unit count before → after. **Disambiguate tracker #279 from GitHub PR #279 in
the first line.**

**Can this share a PR with #282? No — and the recommended order is #279
first.** They touch one file and one seam, which is exactly why they should
not ride together: #282's ruled change has a live chance of coming back RED on
its own regression bars (see that dispatch, §6) and going back to Owen, and a
shared PR would drag this contained, device-verifiable fix into that hold.
Land #279, merge it, then branch #282 off the result — #282's bars then measure
against a mirror that no longer lies.

---

## 8. House rules

`OPEN_ITEMS.md` is the tracker; Owen routes every merge. Bars go in the ENTRY
before the code, not in this file. Real data only. No Apple bug filing, ever.
