# FIX REPORT — #291 / #294 / #293(a)(b)(c)

Branch `claude/t27-291-stop-settles`, off `main` @ `3fb900d`. TDD: the two
user-visible defects (#291, #294) got failing tests first; #293 is a latent
shape + a doc/code truth repair and rides a behaviour-pinning test.

**Toolchain:** `DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer`,
sim `iPhone 17 Pro Max` = `47F68496-24F9-45D9-93D3-1C778DB6B557`. Plain `test`,
suite-level `-only-testing` only, never `CODE_SIGNING_ALLOWED=NO`.

---

## FIX 1 — #291: Stop leaves the user's row unsettled

### What changed

`Talaria/Stores/ChatStore.swift`

- New tracked identity `streamingUserMessageID` (private), set in
  `sendMessage` on the same line block as `streamingMessageID = placeholderID`
  — the placeholder and the user row it answers are one turn. Cleared at the
  end of `sendMessage` (guarded by `== clientMessageID`, so a later turn's
  handle is never stolen), in `cancelStreaming`, and in `abandonPendingRun`
  (the #184 walk-away primitive).
- New `settleStoppedUserMessage()`, called from `cancelStreaming` right after
  the placeholder block: flips that one row from `.sending` to `.delivered`.

**Targeted, not a blanket sweep — and why.** The brief asked for the choice to
be stated. I settle exactly `streamingUserMessageID`'s row and require it to
still be `.sending`. A blanket sweep of every `.sending` user row would also
settle a second send in flight, or a compose-outbox turn mid-drain — rows this
Stop has no authority over. Settling somebody else's row is the same class of
lie as leaving this one unsettled, pointed the other way. The `.sending`
requirement also means a row already settled by its own terminal (`.working`
after `.interrupted`, `.queued` offline) is left exactly as its own path left
it.

**Both paths, deliberately.** `cancelStreaming(hardStopHost:)` is entered by
the explicit Stop tap AND by the continued-send expiration handler (system
revoked the background budget, #283 Task 7). The settle is unconditional
because a user row's status is about DELIVERY, and the host received the turn
on both paths. Consequence worth knowing, recorded rather than hidden: with the
row no longer `.sending`, `hasPendingMessages` goes false, so the 2s poll loop
breaks on its next tick on both paths. That loop's only remaining behaviour on
those paths was the false-failure tail this fix removes, so nothing that worked
was lost — but the expiration path does give up ~60s of opportunistic merging
it used to do before lying. Flagging it rather than burying it.

### RED evidence (before the fix)

```
DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer xcodebuild test \
  -project Talaria.xcodeproj -scheme Talaria \
  -destination "platform=iOS Simulator,id=47F68496-24F9-45D9-93D3-1C778DB6B557" \
  -only-testing:TalariaTests/AppStoresTests \
  -only-testing:TalariaTests/ChatStorePersistenceTests \
  -only-testing:TalariaTests/RunsPlaneTransportTests \
  -only-testing:TalariaTests/StreamLossClassificationTests
```

```
✘ Test stopSettlesTheUserRowOfTheTurnItStopped() recorded an issue at AppStoresTests.swift:1570:9: Expectation failed: userRows.first?.status == .delivered
✘ Test stopSettlesTheUserRowOfTheTurnItStopped() recorded an issue at AppStoresTests.swift:1574:9: Expectation failed: chatStore.conversation?.messages.contains { $0.sender == .user && $0.status == .sending } == false
✘ Test stopSettlesTheUserRowOfTheTurnItStopped() failed after 0.033 seconds with 2 issues.
✘ Test stoppedTurnSurvivesRelaunchWithoutTurningFailed() recorded an issue at AppStoresTests.swift:1610:9: Expectation failed: restored.first(where: { $0.sender == .user })?.status == .delivered
✘ Test run with 171 tests in 4 suites failed after 15.154 seconds with 6 issues.
** TEST FAILED **
```

### GREEN evidence

Same command: `✔ Test run with 172 tests in 4 suites passed after 15.105 seconds.` / `** TEST SUCCEEDED **`
(172 vs 171 = the #293(c) test added after the RED run — the count MOVED, so this
is not a stale `.xctest`.)

### Bars

- **291-A MET** — `stopSettlesTheUserRowOfTheTurnItStopped` asserts `.delivered`
  AND asserts the exact poll predicate (no user row left `.sending`).
- **291-B MET** — same test pins `onSendFailed` at 0 fires. Asserted structurally
  (the failure branch's precondition is now unreachable) rather than by sleeping
  out the 60s window.
- **291-C MET** — `stoppedTurnSurvivesRelaunchWithoutTurningFailed` builds a
  fresh `ChatStore` over the same persistence and runs
  `loadConversationIfNeeded()`, i.e. the real cold-load scrubber that turns
  `.sending` into `.failed`. The row comes back `.delivered`.
- **291-D NOT MET — device arm, owed.** Stop a turn, keep the chat screen up
  90s, confirm no buzz / no Retry / no "failed". Nothing on a simulator can
  settle this bar.

---

## FIX 2 — #294: an early Stop persists an empty assistant bubble

### What changed

`Talaria/Stores/ChatStore.swift` — `cancelStreaming`'s placeholder block now
branches: if `Self.stoppedPlaceholderHasNothingToShow(...)` the row is REMOVED;
otherwise it is finalized exactly as before (`isStreaming = false`,
`status = .delivered`, tool chips resolved).

**Reuse, per the anti-drift instruction.** `SessionsHermesClient.cleanCloseArmsRecovery`
IS reachable from `ChatStore` (same module, `nonisolated static`), so the prose
half calls it rather than restating it — the same reuse `deliverPolledTerminal`
makes, so the third producer of terminal assistant rows cannot drift from the
other two.

**The predicate is additive and STRICTER than the cold-load scrubber's.**
Scrubber: `content.isEmpty && toolActivities.isEmpty`. Mine also requires
`attachments.isEmpty` and no non-blank `reasoning`. Two reasons, both from this
repo's own rules:

- **#277 is explicit** that "stopping a run does not un-write the file the agent
  already produced" — `recordAgentAttachments()` is called three lines later in
  this very function. A row carrying an `.artifactProduced` chip and no prose is
  NOT empty, and removing it would delete the chip #277 exists to keep.
- **#4.15** renders `reasoning` on a non-streaming bubble, and the server
  transcript filters `_thinking`, so a reasoning-only row removed here is
  reasoning lost forever.

Noted asymmetry: the cold-load scrubber would still remove a `.sending`
reasoning-only placeholder left by a crash. That path is untouched by this lane
and is a separate (much rarer) shape.

### RED evidence

```
✘ Test stopBeforeTheFirstTokenLeavesNoEmptyAssistantRow() recorded an issue at AppStoresTests.swift:1641:9: Expectation failed: chatStore.conversation?.messages.contains { $0.sender == .hermes } == false
✘ Test stopBeforeTheFirstTokenLeavesNoEmptyAssistantRow() recorded an issue at AppStoresTests.swift:1646:9: Expectation failed: cached.contains { $0.sender == .hermes } == false
✘ Test stoppedTurnSurvivesRelaunchWithoutTurningFailed() recorded an issue at AppStoresTests.swift:1614:9: Expectation failed: restored.contains { $0.sender == .hermes } == false
```

The two 294-B guard tests (`stopWithPartialContentKeepsThatContent`,
`stopDuringAToolCallKeepsTheActivityRow`) passed in the RED run **by design** —
they pin behaviour the fix must not break, so they are green on both sides. That
is what makes them a trap-detector rather than decoration.

### GREEN evidence

Same run as FIX 1: 172/172, `** TEST SUCCEEDED **`.

### Bars

- **294-A MET** — `stopBeforeTheFirstTokenLeavesNoEmptyAssistantRow` asserts no
  assistant row in memory AND none in the conversation cache.
- **294-B MET (the trap)** — `stopWithPartialContentKeepsThatContent` asserts the
  exact partial string survives, terminal and non-streaming;
  `stopDuringAToolCallKeepsTheActivityRow` asserts a prose-less tool row stays
  with its chip resolved. Attachments and reasoning are additionally protected
  by the predicate (argued above, not separately tested — flagged as a
  read-verified extension, not a measured one).
- **294-C MET** — the relaunch test asserts no assistant row after a cold load
  from the cache the Stop wrote.

---

## FIX 3 — #293(a): token-less loop teardowns

`Talaria/Stores/ChatStore.swift`. Two new generation counters,
`pollingGeneration` / `reconcileGeneration`, bumped where each loop is armed;
each loop clears its handle only while its generation is still current.

- `restartPendingPollingIfNeeded` — `if self.pollingTask?.isCancelled == false`
  → `if self.pollingGeneration == generation`. The old test was true precisely
  when a NEWER task had replaced this one, so a finishing loop could nil its
  successor's handle and strand the live task.
- `startReconcileLoopIfNeeded` — the unconditional `self.reconcileTask = nil`
  is now generation-guarded.

Idiomatic to the codebase by instruction: the same shape as
`ChatBackendRouter.finishRun(_:)`, `SessionsHermesClient.clearActiveRunContext(matchingRunID:)`,
and `AppContainer.bootstrapGeneration` (which is a counter, hence a counter
here). No new test: this is a latent shape (auditor ~35% reachable, one
main-actor hop), and a test that could observe it would have to manufacture that
hop. Covered indirectly by the whole suite, which exercises both loops.

---

## FIX 4 — #293(c): the doc promised a bound the code stopped enforcing

**Chose the preferred option: made the CODE true, not the comment weaker.**

`Talaria/Services/Live/SessionsHermesClient.swift`

- `selfStoppedRunIDs: Set<String>` → `[String]`, an insertion-ordered list, plus
  `static let selfStoppedRunIDLimit = 8` ("a handful", stated as a number).
- `markSelfStopped` — de-dupes, appends, evicts oldest-first past the limit.
- `consumeSelfStopped` — same check-and-remove-once contract, now index-based.
- The doc comment rewritten to explain WHY the bound has to be enforced rather
  than asserted: the #279 review fix moved the insert to after the `/stop` POST
  returns, so an insert can land past the driver's last drain with nothing left
  to remove it.

Behaviour deliberately unchanged: ids are server-unique so a stale flag never
silenced a foreign run, and the consume-once semantics are identical. New test
`selfStoppedRunIDsStayBoundedWhenNothingEverDrainsThem`
(`TalariaTests/RunsPlaneTransportTests.swift`) marks 24 ids with zero drains and
asserts the list stays at 8, evicts oldest-first, still consumes a live id
exactly once, still returns false for an unknown id, and does not double-count a
re-mark.

---

## ALSO — #293(b): instrumentation only, NO behaviour change

`ChatStore.attemptReconcile`'s `guard let reply else { return false }` now logs
once per candidate-less pass, at `.notice`, with `privacy: .public`:
`sentAt` (client clock), the newest server Hermes row's timestamp (host clock),
their delta, and the Hermes row count. **No slack was added** — the strict `>`
comparison is byte-for-byte what it was. The comment states explicitly that
adding slack would be a behaviour change pending measurement, and that this line
exists to produce that measurement from a device log.

---

## Out of scope, untouched as instructed

**#292** (producer Task never cancelled) and **#293(d)**
(`mergeAttachments`' same-index fallback reading `localAttachments`) — neither
touched.

---

## Verification

Required four suites, ONE invocation, plain `test`:

```
✔ Test run with 172 tests in 4 suites passed after 15.105 seconds.
** TEST SUCCEEDED **
```

Full gate (`scripts/mac/lane-gate.sh`) — the whole Debug suite AND the #218
Release build:

```
-- Debug suite (units + XCUITest) on iPhone 17 Pro Max
   xcodebuild exit=0
  PASS  Test run reported TEST SUCCEEDED
  PASS  Swift Testing tests run — 1804
  PASS  XCUITest tests run — 12
  NOTE  2 test(s) SKIPPED  (CondenserFidelityTests, needs Apple Intelligence hardware — expected, #93)
-- Release build (the #218 check)
   xcodebuild exit=0
  PASS  Release build succeeded
GATE: PASS
```

1804 = the 1798 recorded at `d4f9740` plus this lane's 6 new tests. The count
MOVED, so the stale-`.xctest` trap did not fire.

No files were added, so no `xcodegen generate` was needed and
`Talaria.xcodeproj` is untouched (the gate's own preflight confirms: "PASS
project.pbxproj has no uncommitted drift").

## Concerns / owed

1. **291-D is a device bar and is NOT met.** Stop a turn, keep the chat screen
   up 90s: no buzz, no Retry, no "failed". It is also the auditor's own disproof
   test, so running it settles #291 either way.
2. **The expiration path gives up its opportunistic 60s of polling** (argued
   under FIX 1). If that merging turns out to matter, the fix is to keep the
   loop alive on a predicate other than `.sending` — not to un-settle the row.
3. **#294's attachment/reasoning protection is read-verified, not tested.** The
   two 294-B cases the filing names (prose, tool activity) are tested; the two I
   added on #277/#4.15 grounds are argued from those items' own rules.
