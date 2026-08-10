# OPUS T27 #282 — scope the content-claim tier's DEMAND side to the in-flight turn

> **⚠️ SEQUENCING BANNER, 2026-08-10 (Owen's ruling at the 2026-08-09 decision
> pass): THIS LANE IS HELD BEHIND #299.** The halt this dispatch's own STOP
> condition produced was ruled on: `dispatch/FABLE-T27-299-adoption-identity.md`
> runs FIRST (adoption-time identity), then this lane resumes — and bars
> 282-D/282-E must be RE-READ against the fixed merge before running (their
> PREDICTED-RED was written against the duplicating merge). Nothing else in
> this dispatch changes.

> **📅 2026-08-10, LATER THE SAME DAY — THE HOLD IS RELEASED: #299 LANDED**
> (lane `claude/t27-299-adoption-identity`, `ChatStore.serverIdentityAdoptions`
> — turn-anchored adoption; the claim tier byte-untouched). Corrections to
> this dispatch's text, per the close-out rule:
> - **A2 (§ ASSUMED) was CONFIRMED and is now FIXED.** Assistant rows still
>   have no claim TIER — they are confirmed by #299's adoption pass instead,
>   which consumes no claims, so the ruled guard cannot re-open #299.
> - **282-B's baseline now reads the CLEAN array `["Q1","A1","Q2","A2"]`**
>   (that test doubles as bar 299-A) — the STOP condition can no longer fire
>   from assistant rows.
> - Every `ChatStore.swift` line anchor in this dispatch (`:2737`, `:2751`,
>   etc.) has churned; re-verify at HEAD.
> - 282-D/E's USER-row predictions are unaffected; the #299 author's read on
>   both — including the id-less ASSISTANT sibling #299 quietly bounded — is
>   recorded in OPEN_ITEMS #282's entry, dated 2026-08-10.

**Goal:** execute Owen's 2026-08-09 ruling — only a local user row where
`!localRow.status.isSettled` may consume a content claim — and MEASURE, with
bars written first, exactly which of the claim tier's jobs that scope drops on
the floor.

**Written BEFORE any code.** Bars below are PROPOSED; per CLAUDE.md ("Where the
BARS live") they must be pasted into `OPEN_ITEMS.md` #282 **before the first
line of code is written**. This dispatch is not their home.

**Verified against the working tree at `35c6234`** (branch `main`,
2026-08-09). #282 and #281 were written 2026-08-07; five lanes have merged
since. Every line number below was read at `35c6234`.

> **Owen's ruling, 2026-08-09 — settled, not to be re-litigated here.**
> In-flight rows only. Deleting the tier outright was explicitly refused (it
> re-opens #248 while the gateway transcript carries no `clientMessageID`).
> This dispatch executes that scope. §4 corrects one factual claim the entry
> makes *in support* of the ruling; §6 names what the code says the ruling
> breaks. Neither is an argument against it — they are the things the lane must
> measure instead of assume.

> **Number collision.** Tracker #282 is NOT GitHub PR #282 (see `OPEN_ITEMS.md`
> #297's header: *"merge PR #282 now"*). Say "tracker #282" everywhere.

---

## 1. Verified state

### VERIFIED (read at `35c6234`)

| what | where | fact |
|---|---|---|
| the whole tier | `Talaria/Stores/ChatStore.swift:2737-2760` | `nonisolated static func unconfirmedLocalMessages(local:refreshed:)` |
| the SUPPLY side (#281's fix, one line) | `:2744-2747` | `for row in refreshed where row.sender == .user && row.clientMessageID == nil && !localIDs.contains(row.id)` → `claimableUserContent[trimmed, default: 0] += 1` |
| **the DEMAND side — the predicate this lane changes** | **`:2751`** | `if localRow.sender == .user {` … `:2752-2756` dequeues one claim and returns `false` (i.e. filters the local row OUT of the merge) |
| the two tiers above it | `:2749` (exact id) and `:2750` (echoed `clientMessageID`) | tier 1 `return false` **without** decrementing — the asymmetry #281 was about |
| what "unconfirmed" does | `:2684-2687` | the survivors are **`append`ed to the END** of the refreshed transcript — not reinserted in place |
| the final sweep | `:2709` → `Talaria/Models/Conversation.swift:50-60` | `dedupingAdoptedEchoes` keys on `sender \| trimmed content \| timestamp.timeIntervalSince1970`; empty-content rows additionally on activity labels |
| the predicate the ruling names | `Talaria/Models/MessageStatus.swift:19-24` | `isSettled`: `.sending`/`.working`/`.queued` → **false**; `.sent`/`.delivered`/`.failed` → **true**. Exhaustive `switch`, so a new status must answer it. |
| **`.sent` is the DEFAULT** | `Talaria/Models/Message.swift:138` | `status: MessageStatus = .sent` — any fixture row built without an explicit status is SETTLED. Every bar below must state its statuses explicitly. |
| case (b)'s source | `Talaria/Services/Live/SessionsHermesClient.swift:1029-1035` | `let stableID = m.id.map { Self.stableMessageID(...) }` … `id: stableID ?? UUID()`, `status: .delivered` |
| case (b)'s second fallback | `SessionsHermesClient.swift:1000` | `let ts = m.timestamp.map { Date(timeIntervalSince1970: $0) } ?? .now` — **a row with no timestamp gets a fresh one per fetch** |
| both fields really are optional | `SessionsHermesClient.swift:2090` (`let id: Int?`), `:2093` (`let timestamp: Double?`), decoded tolerantly at `:2113-2117` | |
| where server rows meet the merge | `ChatStore.swift:2420` (`attemptReconcile` → `reconcileFromServer`), `:1041` (polling fallback), `:2263` (2s poll tick), `:545` (cold load), `:886` (post-stream, base = `hermesClient.currentConversation`) | five call sites |
| where they DON'T | `ChatStore.swift:2092-2125` `openSession` | a straight assignment, deliberately not merged (`:2112-2119`) |
| the Hermes mirror is a fetch cache | `SessionsHermesClient.swift:723-728` (`loadConversation`), `:734-743` (`reconcileFromServer`), `:766-768` (`adoptTruncatedConversation`) | a sent turn never enters it — pinned by 281-C |
| the four #248 pins | `TalariaTests/AppStoresTests.swift:1202` (`.working`), `:1215` (`.working` + `.sending`), `:1228` (`.working`, confirmed at tier 2), `:1239` (`.sending`) | **every local row in all four is in-flight — the entry's claim that they already satisfy the guard is TRUE** |
| the #281 pin | `AppStoresTests.swift:1253-1264` | local = `.delivered` historical (tier-1 confirmed) + `.sending` fresh; refreshed = the historical row |
| the store-level #281 pin and its fixture | `TalariaTests/ChatStorePersistenceTests.swift:826` (`aRepeatedPromptsRegenerateKeepsItsFreshUserRow`), fixture `:495-507` (`repeatedPromptServerHistory`), shape switch `:345-358` | `.hermesFetchCache` stamps no `clientMessageID` and does not append the sent turn |

### ASSUMED (inference from code read, NOT proven by execution)

- **A1.** That the ruled guard leaves a settled local user row unconfirmed on
  the `attemptReconcile` merge, producing a duplicate at the tail. The chain
  is closed on paper (§6, T-2) but has not been run. **282-D exists to settle
  it and is expected RED.**
- **A2.** That `.hermes` rows of prior in-app turns may ALREADY re-append on
  the same merge (they have no claim tier at all — `:2751` restricts it to
  `.user`). If 282-B's characterization shows it, that is a NEW finding with
  its own number, not this lane's to fix.
- **A3.** How often the live gateway omits `id`/`timestamp` on
  `GET /api/sessions/{id}/messages`. Unmeasured. #237 built stable ids from
  server row ids, so the normal path has both; case (b) is the tolerance path.
  **Do not probe OJAMD for this** — 282-E is a unit bar and does not need it.

---

## 2. The defect (as scoped by the ruling)

`:2748-2759` filters local rows against three confirmation tiers. Tiers 1 and
2 are identity. Tier 3 is a whole-transcript, order-free content map: **any**
local `.user` row whose trimmed content matches an available claim is
confirmed and dropped, and the winner is whichever comes FIRST in local order —
not the row the refreshed row actually corresponds to.

#281's framing, kept because it is the honest one:

> *"a whole-transcript, order-free content map is solving a problem that is one
> row wide and a few seconds long"*

**Case (a), the ruling's target.** A `.failed` user row the host never stored
sits above a later identical prompt that succeeded. The server echoes ONE
copy of the successful turn; it mints one claim (`:2745` — its stable id is not
in `localIDs`); the `.failed` row is first in local order, eats it, and is
filtered out of the merge. The row the user can see failed, and can retry,
silently leaves the transcript.

**The ruled fix:** `:2751` becomes
`if localRow.sender == .user, !localRow.status.isSettled {`. `.failed` is
settled (`MessageStatus.swift:22`), so it can no longer consume, and the
`.sending`/`.working` successor — the row the echo actually corresponds to —
takes the claim instead.

**Case (b), which the ruling does NOT reach — say this plainly.** A stored row
with no `id` gets `UUID()` (`SessionsHermesClient.swift:1031`). A fresh UUID is
**never** in `localIDs`, so #281's supply gate at `:2745` can never bind for
it: it mints a claim on every single fetch, forever, exactly as the entry says.
The guard is a demand-side change and touches none of that. Worse — see §6,
T-1 — under the guard the claim now has no eligible consumer, because that
row's previously-adopted local twin is stamped `.delivered`
(`SessionsHermesClient.swift:1035`) and therefore settled. **Case (b) survives
the ruling and inverts: what was a silent swallow becomes a duplicate.**

---

## 3. What the guard does to every pinned case (traced, not assumed)

| pin | local statuses | outcome under the guard |
|---|---|---|
| 248-A `AppStoresTests.swift:1202` | `.working` | unchanged — consumes, empty result |
| 248-B `:1215` | `.working`, `.sending` | unchanged — one survives |
| 248-C `:1228` | `.working`, but confirmed at tier 2 (`:2750`) | never reaches the claim |
| 248-D `:1239` | `.sending`, empty refresh | never reaches the claim |
| 281-A `:1253` | `.delivered` (tier-1 confirmed) + `.sending` fresh | unchanged — the fresh row still consumes… **which is the correction in §4** |

All five stay green. That is the entry's "all four #248 pins already satisfy
it", verified. It is also the reason the suite will NOT catch T-1/T-2 on its
own — the new bars have to be written for them.

---

## 4. ⚠️ Tracker corrections

Corrections go UPSTREAM to each claim's own home, in the same commit (THE
CLOSE-OUT RULE). The orchestrator files them; do not edit `OPEN_ITEMS.md` or
`OPEN_ITEMS-ARCHIVE.md` from this dispatch.

### 4.1 — THE LOAD-BEARING ONE. *"would have made #281 impossible by construction"* is FALSE.

The sentence appears **four** times: `OPEN_ITEMS-ARCHIVE.md` #281's in-lane
closing note; #281's final closure paragraph; `OPEN_ITEMS.md` #282's body,
where it is quoted forward as one of the two facts that *"make this
attractive"*; and — added 2026-08-09, after this dispatch's read began —
inside **Owen's ruling block itself** in `OPEN_ITEMS.md` #282, as the stated
justification (*"This is the scope #281 itself recommended: it 'would have
made #281 impossible by construction'"*). All four are the same borrowed
claim, propagating exactly the way the ATS lines and the model-switching
section did.

The parenthetical explains itself as *"a `.delivered` historical row could
never eat anything."* **In #281 the historical row did not eat anything. It
MINTED.** #281 was a SUPPLY-side bug; the in-flight guard is a DEMAND-side
change; they do not intersect.

Traced against 281-A's own fixture (`AppStoresTests.swift:1253-1264`), with the
in-flight guard applied and #281's `&& !localIDs.contains(row.id)` removed:

- refreshed `[Hist(id: historyID, .user, "How many are left")]`, `clientMessageID == nil` → mints claim `{"How many are left": 1}`.
- local `Hist(id: historyID, .delivered)` → tier 1 matches (`:2749`) → `return false`, **no decrement**. The guard is never consulted.
- local `Fresh(id: freshID, clientMessageID: freshID, .sending)` → not id-confirmed, cmid not echoed, **`.sending` is NOT settled** → passes the new guard → consumes the surplus claim → filtered out.
- result: `[]` — 281-A's pre-fix RED, verbatim (*"`unconfirmed.map(\.id) → []` where `[freshID]` was wanted"*).

**So the in-flight guard would NOT have prevented #281.** One of the two
stated arguments for the ruling does not hold. The other one — *all four #248
pins already satisfy it* — is **VERIFIED TRUE** (§3). Owen's ruling stands on
its own merits and on case (a); this correction removes a false support, not
the decision.

### 4.2 — the scope sentence is right about the statuses, and the entry should add the trap.

*"`!localRow.status.isSettled`, the predicate #278 already added, covering
exactly `.sending`/`.working`/`.queued`"* — verified,
`MessageStatus.swift:19-24`. What the entry does not say, and what will bite
whoever writes the tests: **`Message.status` defaults to `.sent`**
(`Message.swift:138`), which is settled. A fixture row written
`Message(sender: .user, content: "X")` is silently ineligible to consume.
Several existing pins get away with it only because they set statuses
explicitly.

### 4.3 — case (b)'s severity is understated.

The entry files (b) as a supply-side annoyance (*"mints a fresh claim on EVERY
fetch, forever"*). It is also the **only** confirmation an id-less row's local
twin has, so the ruled guard converts it from a swallow into a duplicate, and
the last line of defence (`dedupingAdoptedEchoes`) only holds when the server
supplied a *timestamp* — because `SessionsHermesClient.swift:1000` falls back
to `.now`, and a per-fetch timestamp defeats the sweep's key. §6 T-1.

### 4.4 — #248's superseded-note pointer chain is correct at HEAD.

`OPEN_ITEMS-ARCHIVE.md` #248's two update notes point at #281 "in THIS file"
and forward the scope question to #282 on the live board. Verified accurate —
recorded here so the next reader does not re-check it.

---

## 5. Pre-registered bars — PROPOSED

**Paste into `OPEN_ITEMS.md` #282 before any code.** Two of these are
**predicted RED under the ruled change** and that is deliberate: a bar written
to be failed by the ruling is how this lane produces a decision instead of a
regression.

- **282-A (unit, fails today — the ruling's target, case (a)):** local =
  `[Failed(id: F, clientMessageID: F, .user, "X", status: .failed),
  Success(id: S, clientMessageID: S, .user, "X", status: .sending)]`;
  refreshed = `[Server(id: R, .user, "X", clientMessageID: nil)]` with
  `R ∉ {F, S}`. Assert `unconfirmedLocalMessages(...)` returns **`[Failed]`** —
  the failed row survives the merge and the in-flight successor is the one
  confirmed. Today it returns `[Success]` (the failed row is eaten). Evidence:
  `unconfirmed.map(\.id)`, quoted verbatim from both sides. No device.

- **282-B (unit, characterization — written and GREEN *before* the fix, and
  re-run after):** a store-level merge on the `.hermesFetchCache` shape
  (`ChatStorePersistenceTests.swift:341-465`, `makeMirroredStore(shape:)`
  `:470`) with a two-turn in-app history reconciled against a server transcript
  that carries stable ids for both turns. Assert TODAY's
  `messages.map(\.content)` verbatim. **This is the baseline every other bar is
  read against** — if the pre-change transcript already contains duplicates,
  A2 is real and gets its own number before this lane goes further. No device.

- **282-C (unit, regression, must stay GREEN):** the five existing pins —
  `AppStoresTests.swift:1202`, `:1215`, `:1228`, `:1239`, `:1253` — pass
  **byte-unmodified**. If the change forces an edit to any of them, the change
  is wrong (281-D's condition, re-applied). Evidence: the diff on
  `AppStoresTests.swift` in the #248/#281 region is purely additive. No device.

- **282-D (unit, PREDICTED RED under the ruling — the settled-historical
  hole):** local = `[U1(id: A, .user, "Q1", status: .delivered),
  R1(id: B, .hermes, "A1", status: .delivered),
  U2(id: C, clientMessageID: C, .user, "Q2", status: .working)]` — a thread
  whose first turn settled in-app and never met the server, and whose second
  turn is mid-recovery. refreshed = the server's view with **stable ids for
  all three rows and no `clientMessageID` anywhere**, timestamps differing
  from the local ones (server clock). Assert: **no user row's content appears
  twice** in the merged transcript. Today's tier 3 confirms `U1` by content and
  the count is right; under the guard `U1` is settled, survives, and is
  appended at `:2684` — a second "Q1" bubble at the tail, which is #248's
  reported symptom (*"one at the top where I started, and one below the
  response"*) restored for settled rows. Evidence: the merged
  `map(\.content)`. No device.

- **282-E (unit, PREDICTED RED under the ruling — case (b), and it must be
  written whatever the outcome):** refreshed rows built the way
  `mapStoredMessage` builds an id-less, timestamp-less row — fresh `UUID()`,
  `status: .delivered`, a fresh timestamp — merged **twice in succession**
  against a local transcript that already adopted the first fetch's copy.
  Assert the user-row count does not grow between fetch 1 and fetch 2. Today
  the claim tier holds it flat; under the guard nothing does, and
  `dedupingAdoptedEchoes` (`Conversation.swift:50-60`) cannot collapse rows
  whose timestamps differ. Evidence: the two counts. No device.

- **282-F (unit, placement — settled whichever way 282-D lands):** when a
  `.failed` row DOES survive the merge (282-A's shape), assert where it ends
  up. `:2684` appends survivors at the tail, so the row the user watched fail
  in position 3 comes back at position N. **Pin the answer the lane decides
  is correct** — either "tail placement is accepted and documented" or "the
  survivor is reinserted in place". A bar that does not state which is not a
  bar. No device.

- **282-G (device, Owen — ONLY if 282-D and 282-E come back GREEN):** send a
  prompt, let it fail, retry the same text, let it succeed. Leave the thread
  and return. **The failed bubble is still there, with its retry affordance,
  above the successful one — and the successful turn appears exactly once.**
  Expected RED before the lane lands. If 282-D/E are RED, **this run is not
  requested** — do not spend a device pass on a build whose own units predict
  a duplicate.

**Falsification, stated in advance.**
- If **282-A goes green and 282-D/282-E go RED**, the ruling is correct for
  case (a) and insufficient as a whole change: the tier's demand side cannot be
  scoped by a status predicate alone. **STOP. Report to Owen with the RED text
  and the two options in §7. Do NOT widen the scope, and do NOT redefine
  282-D/E — a missed bar is a falsification, not a redefinition.**
- If **282-D and 282-E come back GREEN**, A1 and T-1 are wrong, the code read
  in §6 is wrong, and the ruling ships as written — which is worth knowing
  precisely because it was predicted otherwise.
- If **282-B's baseline already shows duplicates**, the lane pauses and files
  A2 before touching `:2751`.

---

## 6. Task breakdown (TDD, watched RED)

Repo root `/Users/owenjones/Documents/Claude/Talaria-27`. Branch
`claude/t27-282-claim-demand-scope`, off **`main` after tracker #279 has
merged** (§8).

**Task 1 — baseline first (282-B).** In
`TalariaTests/ChatStorePersistenceTests.swift`, beside the #281 section
(`:791`), write `theHermesReconcileMergeBaselineBeforeScopingTheClaim`. Use
`makeMirroredStore(history:shape: .hermesFetchCache)` (`:470`) and drive a
merge with a server-shaped refresh. Run it GREEN and **quote the transcript
array in the tracker entry**. Nothing is changed in production yet.

**Task 2 — watch 282-A go RED.** In `TalariaTests/AppStoresTests.swift`,
in the `// MARK: - #248` block (`:1190`), add
`aFailedRowNoLongerEatsALaterIdenticalPromptsClaim`. Statuses **explicit** on
every fixture row (correction 4.2). Run against unmodified production; record
the failure text verbatim.

**Task 3 — write 282-D and 282-E and run them BEFORE the fix.** They should be
GREEN pre-change (today's tier 3 does this job). Record that they are green —
that is what makes their post-change RED a measurement rather than a bug in the
test.

**Task 4 — the change, one predicate.** `Talaria/Stores/ChatStore.swift:2751`:

```swift
// #282 (Owen's ruling, 2026-08-09): only an IN-FLIGHT local row may consume
// a content claim. A settled row — `.failed` above all — is not the turn the
// server's echo corresponds to, and eating its claim silently removed it.
if localRow.sender == .user, !localRow.status.isSettled {
```

Extend the doc comment at `:2713-2736` with the scope and with what it does
NOT reach (case (b), `SessionsHermesClient.swift:1029-1031`). **One production
line changes. Nothing else.**

**Task 5 — run everything.** 282-A green. 282-C (the five pins) green and the
diff on their region purely additive. **282-D and 282-E: record the result
verbatim, whatever it is.**

**Task 6 — prove the tests are not pinned to text the change never touched.**
Restore the bug (drop `, !localRow.status.isSettled`) and confirm 282-A goes
RED *for the stated reason* — `unconfirmed.map(\.id)` returning the successor
instead of the failed row, not a compile error and not a different assertion.
Restore the fix; confirm GREEN. If 282-D/E went RED in Task 5, do the mirror
of this: with the guard removed they must go GREEN again, which proves the RED
belongs to the guard and not to the fixture.

**Task 7 — the gate**, backgrounded and polled; never arm a Monitor, never
wait on a notification:

```bash
cd /Users/owenjones/Documents/Claude/Talaria-27
TALARIA_GATE_LOGDIR=/tmp/gate-282 nohup scripts/mac/lane-gate.sh > /tmp/gate-282.log 2>&1 &
```

then `until grep -qE 'GATE: (PASS|FAIL)' /tmp/gate-282.log; do sleep 30; done; tail -40 /tmp/gate-282.log`.
Debug suite + XCUITest + **Release build**, literal `GATE: PASS`
(`scripts/mac/lane-gate.sh:192-200`, `:268-277`). **Confirm the unit count
MOVED**; a stale `.xctest` re-reports the old number and reads as green.

**Task 8 — the decision, not a patch.** If 282-D/E are RED: write the result
into `OPEN_ITEMS.md` #282 with both RED texts and the options in §7, open the
PR as **a measurement PR that does not merge**, and hand it to Owen. That is
the deliverable. Building a companion fix without his go is out of scope for
this lane.

---

## 7. Traps and interactions

**The three things the code says the ruling breaks.** Named here as required;
none is an argument to change the scope.

- **T-1 — case (b) survives AND inverts.** `SessionsHermesClient.swift:1031`
  gives an id-less stored row a fresh `UUID()` per fetch, so `:2745`'s
  `!localIDs.contains(row.id)` can never bind and the claim is minted forever.
  Its previously-adopted local twin is `.delivered` (`:1035`) → settled → under
  the guard it can no longer be confirmed → it survives and is appended
  (`:2684`). `dedupingAdoptedEchoes` collapses the pair only if both carry the
  **same** timestamp; `:1000`'s `?? .now` means a row without a server
  timestamp gets a new one every fetch, so the sweep cannot. **A duplicate per
  fetch, unbounded — #237's 32→128 shape.** Bar 282-E.
- **T-2 — settled local rows lose their only confirmation tier.** A user row
  born in-app carries a client UUID; its server twin carries
  `stableMessageID` and no `clientMessageID` (the gateway echoes none), so
  tiers 1 and 2 both fail and tier 3 is all it has. `attemptReconcile`
  (`:2390-2420`) merges the **whole** server transcript, including the settled
  turns that preceded the stalled one. Under the guard those rows are settled
  and re-append at the tail. **This is #248's exact reported symptom, restored
  for a population its four pins do not cover** (all four use `.working`/
  `.sending`). Bar 282-D.
- **T-3 — surviving rows are relocated, not restored in place.** `:2684`
  appends. So even in the success case, the `.failed` row the ruling saves
  comes back at the BOTTOM of the transcript rather than above the retry.
  Bar 282-F forces the lane to state which of those is the intended product
  behaviour instead of discovering it on device.
- **T-4 — the #56 cold-load `.failed` row.** `finalizeStaleSendsFromCache`
  (`ChatStore.swift:502-511`) flips cached `.sending` rows to `.failed` with
  the explicit caveat (`:496-499`) that *the run may in fact have completed
  server-side*. Such a row has a real server twin. Today the claim absorbs it;
  under the guard both render — the same text twice, one with a retry button.
  This is the intended consequence of "a failed row stops silently vanishing",
  but it is user-visible and belongs in the entry, not in a device report.

**Options for Owen, if T-1/T-2 measure RED. Do not build either without a
per-change go.**
1. **Rank the consumers instead of banning them:** in-flight rows first (the
   ruling's intent), settled rows as a fallback only when no in-flight row
   wants the claim. Keeps #248 closed; does **not** fix case (a) outside the
   in-flight window (the `.failed` row is still first in local order among
   settled candidates), so it is a partial.
2. **Remove case (b) at its source:** give `mapStoredMessage` a deterministic
   fallback id — a hash over `(sessionId, index, role, content)` in the shape
   of `stableMessageID` (`SessionsHermesClient.swift:1045-1049`) — so an
   id-less row is stable across fetches and confirms at tier 1, no claim
   needed. Small and local, but it is a second file and a different lane's
   surface. Caveat to state if proposed: index-derived identity assumes the
   server transcript is append-only in a stable order.

**Other items this touches.**
- **#248** — the reason the tier exists. Its four pins are the regression bar
  (282-C). Do not edit them.
- **#281** — the supply-side fix at `:2745`. Untouched by this lane; §4.1
  corrects its closure text, which is a docs change, not a code change.
- **#278** — donated `isSettled` (`MessageStatus.swift:19-24`) and
  `isTranscriptBusy` (`ChatStore.swift:139`). This lane reuses the predicate
  in a second place; if a new `MessageStatus` case is ever added, the
  exhaustive switch now governs merge behaviour too. Note it in the doc
  comment.
- **#237** — `dedupingAdoptedEchoes` is the last line of defence in T-1/T-2 and
  its key (`Conversation.swift:54`) is why it does not hold. Do NOT loosen that
  key to rescue this lane: `:47-49` records that a genuinely repeated user
  message differs only in timestamp, so a timestamp-free key would delete real
  rows.
- **#277** — `openSession` (`:2092`) deliberately bypasses this merge
  (`:2112-2119`). Nothing here changes that; do not "unify" the two paths.
- **tracker #279** — changes what the local-brain mirror CONTAINS. Land it
  first (§8) so 282-B's baseline is measured against a mirror that no longer
  resurrects.
- **#223** — the whole tier exists because the gateway echoes no
  `clientMessageID`, and that plane is on the deletion path. Worth one
  sentence in the entry; not a reason to defer.
- **#283 (runs transport)** — `/v1/runs` WRITES turns into SessionDB but never
  READS them, and `fetchSessionConversation` is the shared history read
  (`SessionsHermesClient.swift:963-969`). A runs-path history pre-fetch flows
  through the same `mapStoredMessage`, so T-1 applies there too. Check with
  #283's owner before assuming the runs lane is unaffected.

---

## 8. Close-out

**Gate:** `scripts/mac/lane-gate.sh`, backgrounded and polled, literal
`GATE: PASS`, unit count MOVED.

**Upstream text this result falsifies** — correct at each claim's own home, in
the same commit (THE CLOSE-OUT RULE):
- `OPEN_ITEMS-ARCHIVE.md` **#281**, both places it says the in-flight scope
  *"would have made #281 impossible by construction"* — dated supersession
  note with §4.1's trace. This is the correction that most needs to go
  upstream: it is quoted forward into #282 as a reason.
- `OPEN_ITEMS.md` **#282** — TWO places: the entry body's quotation of the
  claim, **and Owen's 2026-08-09 ruling block, which repeats it as the
  ruling's justification.** The ruling is unaffected (it stands on case (a)
  and on the #248-pins fact, which is true); the justification sentence is
  not. Plus corrections 4.2/4.3 and the measured bars.
- `OPEN_ITEMS-ARCHIVE.md` **#248** — if 282-D lands RED, its closure
  (*"the dupe this item existed to kill really is dead"*) needs a note saying
  the kill is scoped to in-flight rows and what the settled population does.
- `Talaria/Stores/ChatStore.swift:2713-2736` — the tier's doc comment must
  state the new scope and name what it does not reach.

**PR:** one PR, `fix(#282): only an in-flight row may consume a content claim`.
Body carries: 282-A's watched RED verbatim; 282-B's baseline transcript;
282-C's five pins byte-unmodified; **282-D and 282-E's results in full, RED or
GREEN**; and either `GATE: PASS` + a request for 282-G, or an explicit
**"MEASUREMENT PR — do not merge, decision owed"**. Disambiguate tracker #282
from GitHub PR #282 in the first line.

**Can this share a PR with tracker #279? No.** They touch one file and one
seam, which is the reason to keep them apart, not to combine them: this lane
may come back RED-by-design and sit awaiting Owen, and #279 is a contained fix
with a cheap device bar that should not be held hostage to that.
**Recommended order: #279 first, merged; then #282 branched off the result.**

---

## 9. House rules

`OPEN_ITEMS.md` is the tracker; Owen routes every merge and every promotion.
Bars go in the ENTRY before the code, not in this file. A missed bar is a
falsification, never a redefinition. Real data only. No Apple bug filing, ever.
