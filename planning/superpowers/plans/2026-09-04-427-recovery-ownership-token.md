# 427 — A Late Run-Recovery Response Lands Only In The Thread That Owns It Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A recovery pass that awaited `GET /v1/runs/{id}` for conversation A can never write its answer, its failure notice, its settlement, its cache save, its journal sync, or its held-turn release into conversation B — whichever thread the user has since opened. Today `attemptRunStatusReconcile` (`ChatStore.swift:4207-4215`) awaits `resolveDroppedRun` and then calls `adoptRecoveredRun`, which reads the store's LIVE `conversation` (`:4252-4254`) with no check that it is still the thread the run belongs to; `openSession` → `abandonPendingRun` (`:3806`, `:1965-1971`) cancels the polling LOOP but never the single-flight pass (`reconcileInFlight`, `:4082-4092`, cancelled nowhere in the tree). The fix is an ownership token captured BEFORE the await and validated before EVERY mutation, plus invalidation of both recovery paths on walk-away.

**Architecture:** One value type (`RecoveryOwnership`: conversation id + session id + run id + a `recoveryGeneration`), captured at the top of both recovery legs (`attemptRunStatusReconcile`, `attemptSessionReconcile`) and checked by one predicate (`recoveryStillOwned(_:)`) immediately after each await and before each write. A stale token returns a new `ReconcilePassOutcome.superseded` — nothing adopted, nothing settled, nothing journaled, nothing fired — and logs one `.notice`. Every walk-away door (`abandonPendingRun`, `abandonReconcileWindowOnStop`, the clear/reset teardown) bumps the generation AND cancels `reconcileInFlight`. The persisted `PendingRunRecord` already carries `conversationID` (`PendingRunRecord.swift:22`) and the cold-load restore already refuses a record for another thread (`:1042`); the in-memory `PendingRun` is the half that never learned the thread, and this plan teaches it.

**Tech Stack:** Swift 6.4 / `ChatStore` (`@MainActor @Observable`) / Swift Testing with `HermesClientProtocol` doubles (`RunStatusRecoveryTests.RunRecoveryClient` is the fixture this plan extends) / `scripts/mac/lane-gate.sh`.

**Why this is the shape:** the house already knows this pattern three times over — `#293(a)`'s `reconcileGeneration`/`pollingGeneration` (`ChatStore.swift:69-75`), `#322-D`'s `finalStatusReadGeneration` with its own words at `:1969-1975` (*"a walk-away taken while a cancel's final status read is still in flight must not let that read land on the arriving thread's gauge. Cancelling AND bumping the generation covers both orderings — the task may already be past its cancellation check"*), and `PendingRunRecord.conversationID`'s doc comment (*"adoption into the wrong thread is #307's corruption arriving through a new door"*). The recovery pass is the one await-then-write in the reconcile family that applies none of them. The token is that pattern with the thread identity added, because here the hazard is not a stale gauge but a stale DESTINATION.

## Global Constraints

- **Every write after the await goes through the predicate.** The writes are enumerated (Task 2's list); a new one added later without the guard is the defect returning — a source-witness pin counts them.
- **Drop, do not redirect.** A late answer for A while B is current is DROPPED with a `.notice`, never written into A's cache behind its back (decision 1). A's answer is not lost: the run WROTE its turn into A's server session (the runs contract), so reopening A fetches it — the same fact #321 recorded (*"a run that completes anyway still arrives through the ordinary transcript merge on a later fetch"*).
- **B's own pending run is never touched by A's verdict.** A stale token skips `settlePendingRun` entirely — no `pendingRun = nil`, no `onRunResolved`, no `resolveHeldTurn`, no restored-row settle — because every one of those would now act on B's state.
- **`resolvedRunIDs.insert(runID)` still happens for a superseded verdict**: A's run did resolve on the host, and a late duplicate interrupt for it is noise (#237) whatever thread is showing.
- **The legacy leg gets the same guard** (`attemptSessionReconcile`, `:4332-4420`) — it merges whole-conversation metadata into whatever is current and is reachable by any run-id-less pending run.
- **Cold-launch recovery rides the same code** (`restorePendingRunFromRecordIfPossible` → `startReconcileLoopIfNeeded` → `attemptReconcile`, `:1042-1064`): the token covers "opened another session during a cold-launch recovery" with no extra branch — one test says so.
- **No behaviour change on the happy path.** All 23 existing `reconcilePendingRuns()` call sites stay green and byte-untouched; the existing 3E-B/3E-C/3E-D pins are the positive control.
- **Gate + merge protocol:** worktree isolation; RED-first with the mutation named per bar; `TALARIA_SIM_NAME=CC-lane-N scripts/mac/lane-gate.sh`, ≤ 3 booted, kill only your recorded PID; positive `GATE: PASS`; merge on green; RESULT block in entry 427.
- **Plan-authored code is unreviewed code.** The token's field set is an interface; Task 0 confirms the fixture can actually hold the pass open and that the "switch" lands on B (a mock whose `openSession` defaults to `loadConversation()` returns A again and makes the whole bar vacuous).

## Decisions for Owen (one AskUserQuestion round — recommended arm first)

> **✅ BALLOT RULED 2026-09-04 (Owen, AskUserQuestion, the same night the plan was written):** 1 = **drop it, one `.notice` line** (the host keeps it; reopening A fetches it) · 2 = **cancel `reconcileInFlight` AND bump the generation** on walk-away · 3 = **Stop gets the same protection** (`abandonReconcileWindowOnStop` cancels + bumps) · 4 = **`Conversation.id` is the thread identity**. Every recommended arm below is now a ruling; the lane builds them without re-asking.

1. **A late answer for a thread you left is DROPPED with a log line (recommended).** The host has it; reopening A shows it. Alternative: write it into A's cached conversation behind the scenes — rejected by default: A's cache may be stale or mid-edit by a later open, and #90's journal (`lastExchangeViaActiveHop`) would be asked to describe a thread that is not the active hop.
2. **Walk-away CANCELS the in-flight pass as well as bumping the generation (recommended):** `reconcileInFlight?.cancel()` joins `reconcileTask?.cancel()` in `abandonPendingRun`. Alternative: token only — correct but wasteful (the read completes and is discarded).
3. **Stop gets the same protection (recommended):** `abandonReconcileWindowOnStop` (#321) bumps the generation too, so a status read that was in flight when the user tapped Stop cannot adopt after the window closed. Alternative: leave Stop as is — #321's ruling says the window ENDS on Stop; a late adoption would contradict it.
4. **The token names the thread by `Conversation.id` (recommended)** — the same identity `PendingRunRecord.conversationID` and the cold-load guard already use. Alternative: session id only — insufficient: the local-brain and host threads can share a session id across a backend switch, and A/B here may be two local threads with no session at all.

## Session contract

1. Read `OPEN_ITEMS.md` entry 427 (the audit's A2 evidence), entry 368's 3E bars (the recovery collapse — `RunStatusRecoveryTests` is its file), entry 322's bar 322-D (the generation-on-walk-away precedent), entry 321 (Stop abandons the window), entry 329 (cold-launch recovery), and `OPEN_ITEMS-ARCHIVE.md` #184 (the three teardowns) and #226 (`reconcileInFlight`'s origin). Pre-register bars 427-A..GATE in entry 427 BEFORE Task 0.
2. Task 0 alone first (fixture feasibility — one hour, no production code).
3. One worktree lane (Opus): Tasks 1–3, RED-first, mutations named, gate, merge on green, RESULT block. Fable only for a falsified bar.
4. No device evening is REQUIRED — the defect is a pure ordering the unit fixture reproduces deterministically. One optional §01 card (Task 3) records the live shape for the runbook; it is not a bar.

## File structure

**Modify:**
- `Talaria/Stores/ChatStore.swift`
  - `:69-75` — a sibling counter `private var recoveryGeneration = 0` beside `reconcileGeneration`.
  - `:663-677` — `PendingRun` gains `let conversationID: UUID?` (nil only for the legacy path's oldest arm; every current arm has `conversation?.id` when it arms — the didSet at `:686-700` already reads it).
  - `:1965-1995` `abandonPendingRun` — `reconcileInFlight?.cancel(); reconcileInFlight = nil; recoveryGeneration &+= 1` beside the existing `reconcileTask?.cancel()` (decision 2).
  - `:2463-2475` `abandonReconcileWindowOnStop` — the same two lines (decision 3).
  - `:4160-4175` `ReconcilePassOutcome` gains `case superseded` (doc: *the thread moved on underneath the read; nothing adopted, nothing settled, this pass stops*). Both loops already break on anything but `.keepPolling`, so no caller changes.
  - `:4207-4230` `attemptRunStatusReconcile` — capture `let token = ownership(for: pending)` BEFORE the await; `guard recoveryStillOwned(token) else { resolvedRunIDs.insert(runID); log; return .superseded }` immediately AFTER it, before the `switch`.
  - `:4252-4290` `adoptRecoveredRun` and `:4240-4247` `appendRunFailureNotice` — take the token and re-check it before their `guard var conv = conversation` (belt: they are called only from the guarded arm today, but a future caller must not be able to skip it).
  - `:4293-4315` `settlePendingRun` — takes the token; a stale token returns without touching `pendingRun`, `onRunResolved`, the cache, the journal, or `resolveHeldTurn`.
  - `:4332-4420` `attemptSessionReconcile` — the same capture/guard around its `await hermesClient.reconcileFromServer()`, before `conversation = mergeConversationMetadata(...)`.
- `Talaria/Stores/ChatStore.swift` (new members):

```swift
/// #427: who a recovery pass is allowed to write for. Captured BEFORE the
/// status read, checked before EVERY mutation after it. A cancellation
/// request alone is insufficient — the task may already be past its check.
private struct RecoveryOwnership: Equatable {
    let conversationID: UUID?
    let sessionID: String
    let runID: String?
    let generation: Int
}

private func ownership(for pending: PendingRun) -> RecoveryOwnership {
    RecoveryOwnership(conversationID: conversation?.id, sessionID: pending.sessionId,
                      runID: pending.runId, generation: recoveryGeneration)
}

/// True only while the thread, the pending run and the generation are all
/// still the ones the pass was armed for.
private func recoveryStillOwned(_ token: RecoveryOwnership) -> Bool {
    guard !Task.isCancelled, recoveryGeneration == token.generation else { return false }
    guard conversation?.id == token.conversationID else { return false }
    guard let pending = pendingRun, pending.sessionId == token.sessionID, pending.runId == token.runID else { return false }
    return true
}
```

**Create (tests):**
- `TalariaTests/RecoveryOwnershipTests.swift` — bars 427-A..F; its fixture `GatedRecoveryClient` is `RunRecoveryClient` (`RunStatusRecoveryTests.swift:346-449`) plus a bounded polling gate in `resolveDroppedRun`/`reconcileFromServer`, an `openSession(_:)` that returns a DIFFERENT conversation, and per-run answers keyed by `runID`.

## Bars (paste into entry 427 as a dated block BEFORE Task 0)

- **427-A — a late answer never lands in B (unit).** Arm A's run (`sendMessage` → the fixture's `.interrupted(sessionId:"A-session", runId:"run-A")`), start `reconcilePendingRuns()` in a Task, wait until the fixture is INSIDE `resolveDroppedRun`, `await store.openSession("B")` (the fixture returns conversation B — a different `Conversation.id`, one hermes row `"B's own history"`), assert `store.conversation?.id == B.id` (the switch really happened), release the gate, await the pass. Then: B's messages are exactly its one row (no `"A's late answer"`), `persistence.loadConversationCache()` carries no `"A's late answer"`, `store.pendingRunSessionId == nil` stays nil for the right reason (walk-away cleared it; the pass did not re-clear B's), `onRunResolved` was fired ONCE for `"A-session"` (by walk-away) and never again after the release. Mutation: remove the post-await `recoveryStillOwned` guard → `"A's late answer"` appears in B → RED.
- **427-B — B's own run is untouched by A's verdict (unit).** As 427-A, but after opening B the test sends `"b question"` and the fixture interrupts it as `run-B`; release A's gate → B's `pendingRunSessionId == "B-session"` still armed, B's `"b question"` row still `.working`, no `"A's late answer"`; then release B's gate → `"B's answer"` lands at B's tail and B settles. Mutation: make `settlePendingRun` skip the token check → B's pending run is cleared by A's verdict → RED on the still-armed assertion.
- **427-C — positive control (unit).** No switch: A's answer lands in A at the tail, `pendingRunSessionId == nil`, cache updated — the 3E-B shape, restated in the new file so the fixture's gate is proven to release.
- **427-D — walk-away cancels the in-flight pass (unit, decision 2).** After `openSession("B")` during a parked pass: a second `reconcilePendingRuns()` returns without awaiting the stale task (bounded: < 100 ms with the gate still closed), and the fixture's `resolveCallCount` for `run-A` does not increase. Mutation: drop `reconcileInFlight?.cancel()` from `abandonPendingRun` → the second call parks on the stale task → RED on the bound.
- **427-E — the legacy leg (unit).** A run-id-less pending run (Task 0 names the arming route) parked in `reconcileFromServer`; switch to B; release → B's messages unchanged, no `mergeConversationMetadata` write (B's `title`/`latestUsage` unchanged), no `placingRecoveredReply` reorder. Mutation: remove the guard in `attemptSessionReconcile` → RED. If Task 0 finds no test-reachable arming route, this bar becomes a source-witness pin (`RepoSourceWitness.functionBody(from: "private func attemptSessionReconcile", in: chatStorePath)` contains `recoveryStillOwned(`) and the entry says so in as many words.
- **427-F — Stop's window stays closed (unit, decision 3).** A parked pass; `store.cancelStreaming(hardStopHost: false)` runs `abandonReconcileWindowOnStop`; release → nothing adopted into the (same) conversation, the user row stays `.delivered` as #321 ruled. Mutation: drop the generation bump from `abandonReconcileWindowOnStop` → the late answer lands after Stop → RED.
- **427-W — the writes are enumerated (source witness).** `RepoSourceWitness.functionBody(from: "private func attemptRunStatusReconcile", in: "Talaria/Stores/ChatStore.swift")` contains `recoveryStillOwned(` at least once; the bodies of `adoptRecoveredRun`, `appendRunFailureNotice`, `settlePendingRun`, `attemptSessionReconcile` each contain it. A new write path added without the guard reds this pin.
- **427-GATE** — positive `GATE: PASS`, count moved by exactly the tests this lane adds.

## Task 0: Fixture feasibility (no production code; ~1 hour)

**Files:** read only — `TalariaTests/RunStatusRecoveryTests.swift`, `TalariaTests/AppStoresTests.swift:700-800`, `TalariaTests/MessageQueueTerminalsTests.swift:80-130`, `TalariaTests/ColdLaunchRunRecoveryTests.swift`; `Talaria/Services/Protocols/HermesClientProtocol.swift:360-395` (the defaults).

- [ ] **Step 1 — which of the 23 call sites hosts the suspended-mock shape?** Answer from the reads: `RunStatusRecoveryTests.RunRecoveryClient` is the one whose `sendStreaming` yields `.interrupted(sessionId:runId:)` and whose `resolveDroppedRun` is a plain method (`:444-448`) — gate it there. `AppStoresTests.LateInterruptClient` (`:742`) and `MessageQueueTerminalsTests` (`:101`) are stubs shaped for other bars; leave them. Record the answer in the entry.
- [ ] **Step 2 — the switch must be REAL.** `HermesClientProtocol.openSession` DEFAULTS to `await loadConversation()` (`:364`), which returns `currentConversation` — i.e. A again. A fixture that forgets to implement `openSession(_:)` produces a test where "open B" reopens A and every 427 assertion passes vacuously. The fixture's `openSession` returns `Conversation(id: bID, title: "B", messages: [Message(sender: .hermes, content: "B's own history", status: .delivered)])` and every test asserts `store.conversation?.id == bID` BEFORE releasing the gate. Write this down in the entry as the fixture's founding pin.
- [ ] **Step 3 — the legacy arming route (bar 427-E).** Read how a `PendingRun` with `runId == nil` is armed today (grep `PendingRun(` in `ChatStore.swift`; the background-expiration arm and any `.interrupted` with a nil run id). If a test can arm one through `sendStreaming`'s `.interrupted(sessionId:, runId: nil)` (check `StreamingUpdate.interrupted`'s signature), 427-E is behavioural; if not, it is the source-witness form. Record which.
- [ ] **Step 4 — confirm `openSession` completes while a pass is parked.** `openSession` awaits `hermesClient.openSession(id)` (a different await than the parked `resolveDroppedRun`) — yes by reading; note it so the fixture's gate is not mistaken for a deadlock.
- [ ] **File** the four answers in entry 427 as `427-T0`; adjust 427-E's form if needed BEFORE Task 1.

## Task 1: The token and the guard on the run-status leg (bars 427-A, 427-B, 427-C)

**Files:** modify `ChatStore.swift` (`:69-75`, `:663-677`, `:4160-4175`, `:4207-4315`); create `TalariaTests/RecoveryOwnershipTests.swift`.

- [ ] **Step 1 — RED tests** (the fixture first, then A/B/C):

```swift
@MainActor
private final class GatedRecoveryClient: HermesClientProtocol {
    struct Gate { var entered = false; var released = false }
    var connectionStatus: ConnectionStatus = .connected
    var currentConversation: Conversation?
    let bID = UUID()
    var gates: [String: Gate] = [:]                     // keyed by run id
    var answers: [String: DroppedRunResolution] = [:]   // keyed by run id
    private(set) var resolveCalls: [String] = []
    var nextRunID = "run-A"; var nextSessionID = "A-session"

    func isInside(_ runID: String) -> Bool { gates[runID]?.entered == true && gates[runID]?.released != true }
    func release(_ runID: String) { gates[runID, default: Gate()].released = true }

    func sendStreaming(message: String, attachments: [PendingAttachment] = [], clientMessageID: UUID) -> AsyncStream<StreamingUpdate> {
        let (runID, sessionID) = (nextRunID, nextSessionID)
        return AsyncStream { c in Task { @MainActor in c.yield(.interrupted(sessionId: sessionID, runId: runID)); c.finish() } }
    }
    func openSession(_ id: String) async throws -> Conversation {
        Conversation(id: bID, title: "B", messages: [Message(sender: .hermes, content: "B's own history", status: .delivered)])
    }
    func resolveDroppedRun(runID: String, sessionID: String) async -> DroppedRunResolution? {
        resolveCalls.append(runID)
        gates[runID, default: Gate()].entered = true
        for _ in 0..<400 where gates[runID]?.released != true { try? await Task.sleep(for: .milliseconds(10)) }   // bounded park
        return answers[runID]
    }
    // connect/disconnect/send/loadConversation/clearConversation/reconcileFromServer/activeRunID:
    // copy RunRecoveryClient's bodies (RunStatusRecoveryTests.swift:381-441).
}

@Suite("427 recovery ownership")
@MainActor
struct RecoveryOwnershipTests {
    @Test func aLateAnswerForTheThreadYouLeftNeverLandsInTheThreadYouOpened() async throws {   // 427-A
        let client = GatedRecoveryClient()
        client.answers["run-A"] = .answered(content: "A's late answer", usage: nil)
        let store = makeStore(client: client)
        var resolved: [String] = []; store.onRunResolved = { resolved.append($0) }

        await store.sendMessage("a question")                   // arms run-A on A
        let pass = Task { await store.reconcilePendingRuns() }
        for _ in 0..<200 where !client.isInside("run-A") { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(client.isInside("run-A"), "the pass never parked — every assertion below is vacuous")

        await store.openSession("B")                            // the walk-away
        #expect(store.conversation?.id == client.bID, "the switch must be REAL (openSession default returns A)")
        #expect(resolved == ["A-session"], "walk-away fires onRunResolved for A exactly once")

        client.release("run-A"); await pass.value

        #expect(store.conversation?.messages.map(\.content) == ["B's own history"])
        #expect(!(store.conversation?.messages.contains { $0.content == "A's late answer" } ?? true))
        #expect(resolved == ["A-session"], "the superseded pass fires nothing")
        let cached = try #require(persistenceFor(store).loadConversationCache())
        #expect(!cached.messages.contains { $0.content == "A's late answer" })
    }
    // 427-B: after openSession("B"): client.nextRunID = "run-B"; nextSessionID = "B-session";
    //   client.answers["run-B"] = .answered(content: "B's answer", usage: nil); await store.sendMessage("b question");
    //   release("run-A") → assert pendingRunSessionId == "B-session", no "A's late answer", "b question" still .working;
    //   release("run-B") → "B's answer" at the tail, pendingRunSessionId == nil.
    // 427-C: no openSession → "A's late answer" at A's tail, pendingRunSessionId == nil.
}
```

- [ ] **Step 2 — RED:** run `-only-testing:TalariaTests/RecoveryOwnershipTests`. Expected: 427-A fails on `"A's late answer"` present in B (and in the cache); 427-B fails on B's pending run cleared; 427-C passes (control).
- [ ] **Step 3 — implement** the interface block above; thread `token` through the four functions; add `.superseded`; log `chatLog.notice("run recovery: verdict for \(runID, privacy: .public) arrived after the thread changed — dropped, the host still has it (#427)")`.
- [ ] **Step 4 — GREEN + mutations** (named per bar above; each restored before the next). Run `RunStatusRecoveryTests`, `AppStoresTests`, `MessageQueueTerminalsTests`, `ColdLaunchRunRecoveryTests` targeted — all byte-untouched, all green. **Commit:** `427-A/B/C: RecoveryOwnership — captured before the status read, checked before every write; a late verdict for a departed thread is dropped (RED-first)`.

## Task 2: Walk-away and Stop invalidate the in-flight pass; the legacy leg (bars 427-D, 427-E, 427-F, 427-W)

**Files:** modify `ChatStore.swift` (`:1965-1995`, `:2463-2475`, `:4332-4420`); extend `RecoveryOwnershipTests.swift`.

- [ ] **Step 1 — RED tests:** 427-D (a second `reconcilePendingRuns()` after the switch returns within 100 ms while `run-A`'s gate is still closed; `client.resolveCalls.filter { $0 == "run-A" }.count == 1`), 427-F (`store.cancelStreaming(hardStopHost: false)` while parked, release, no adoption, user row `.delivered`), 427-E in whichever form Task 0 ruled, and 427-W (five `RepoSourceWitness.functionBody` reads, each `contains("recoveryStillOwned(")`).
- [ ] **Step 2 — RED. Step 3 — implement:** the two lines in `abandonPendingRun`; the two lines in `abandonReconcileWindowOnStop`; the token capture/guard in `attemptSessionReconcile` before `conversation = mergeConversationMetadata(...)` and again before the `placingRecoveredReply` reorder (two awaits? — no: one await, at `:4333`; the guard sits once, right after it, and the rest of the function is synchronous — verify by reading, and if any `await` remains between the guard and a write, guard again after it).
- [ ] **Step 4 — GREEN + mutations** as named. **Commit:** `427-D/E/F/W: walk-away and Stop cancel the in-flight pass and bump the generation; the legacy leg carries the same token; the writes are enumerated by a witness`.

## Task 3: Gate, PR, RESULT block, the close-out corrections

- [ ] `TALARIA_SIM_NAME=CC-lane-N scripts/mac/lane-gate.sh` (background, poll by your PID); positive `GATE: PASS`; count moved by exactly this lane's tests.
- [ ] PR; merge on green; RESULT block in entry 427 with RED + mutation outputs per bar and Task 0's four answers.
- [ ] **Close-out rule (upstream corrections in the same commit):** entry 184's archive block (the three teardowns) gets an append-only dated pointer — a FOURTH cleanup that the three did not do (`reconcileInFlight`); entry 226's archive note (*"the reconcile-leg single-flight … stays"*) gets a dated pointer that the single-flight now also cancels on walk-away; entry 321's Stop ruling gets a dated line that the window now stays closed against an in-flight read; `openSession`'s #184 comment at `:3799-3805` is extended with one sentence naming the in-flight pass.
- [ ] **Optional §01 runbook card (not a bar):** on a slow host (the Mac gateway with `runRecoveryPollInterval` default), send on thread A, kill the stream (airplane mode 2 s), open thread B within the recovery window, wait, reopen A — A shows its answer via the transcript fetch, B shows nothing foreign. It records the live shape for Owen's eyes; the unit fixture is the evidence.

## Out of scope, and why

- **#430 (A5) — the recovery asks the ACTIVE host, not the run's host.** Same function, different defect (the endpoint, not the destination). Its lane comes after the P1s; the token this plan adds gives it a natural home for `profileID` if that lane wants one, but nothing here resolves endpoints.
- Deleting the legacy `attemptSessionReconcile` — #368 routed around it deliberately and kept it for run-id-less arms; this plan guards it, it does not remove it.
- The `mergeConversationMetadata` non-merge rule at `openSession` — untouched and pinned elsewhere.

## Self-review (2026-09-04, at plan-writing time)

- Every line number was read tonight: the await→adopt at `:4207-4215`; `guard var conv = conversation` at `:4252`; `settlePendingRun`'s seven effects at `:4293-4315`; `reconcileInFlight` at `:719` and `:4082-4092` with zero `.cancel()` calls anywhere (grep confirmed); `abandonPendingRun` at `:1965-1995` (cancels `reconcileTask` and `finalStatusReadTask`, never `reconcileInFlight`); `abandonReconcileWindowOnStop` at `:2463-2475`; the `PendingRun` struct at `:663-677` with no conversation id; the didSet at `:686-700` writing `conversation?.id` into the durable record; the cold-load guard `conv.id == record.conversationID` at `:1042`; the protocol's `openSession` default at `HermesClientProtocol.swift:364`.
- The fixture's founding hazard (a default `openSession` that returns A) was found by reading the protocol, not by imagining it — it is the vacuous-green shape memory `xcodebuild-beta4-stale-incrementals` catalogues, and it is why 427-A asserts the switch before releasing the gate.
- What this plan does NOT claim: that the ordering has been seen on device (the audit says *"timing reproduction needed"*; the unit fixture reproduces it deterministically, which is the stronger evidence for an ordering defect), or that A's late answer is preserved anywhere but on the host.
- Type consistency: `RecoveryOwnership(conversationID:sessionID:runID:generation:)`; `ownership(for:)`; `recoveryStillOwned(_:)`; `recoveryGeneration`; `ReconcilePassOutcome.superseded`; `PendingRun.conversationID`; `adoptRecoveredRun(_:runID:content:usage:token:)`, `appendRunFailureNotice(_:token:)`, `settlePendingRun(_:runID:adopted:token:)` — the `token:` label is the one every call site carries.
