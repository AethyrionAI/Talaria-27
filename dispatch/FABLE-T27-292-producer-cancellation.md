# FABLE-T27-292 — the runs producer Task is never cancelled

**Tier that EXECUTES this lane: FABLE.** (Written by Opus; Fable does the work.)
**Item:** OPEN_ITEMS `#292`.
**Goal:** make consumer walk-away actually stop the client's producer, so an abandoned
runs turn stops issuing `GET /v1/runs/{id}` polls — without touching the host run, and
without disturbing the recovery #295 shipped on 2026-08-08.

**Verified at HEAD `35c6234` (branch `t27-295-expiration-recovery`), 2026-08-09.**
Everything below with a `file:line` was read at that commit. Line numbers move; re-verify
before editing, but the SHAPES are what matter and they were all confirmed.

**BARS FIRST.** 292-A/B/C are already pre-registered in the `#292` entry
(`OPEN_ITEMS.md:5542-5548`). §6 below reproduces them in full with the refinements this
brief adds. **The refined observation mechanism for 292-A must be written into the `#292`
entry BEFORE any code is written** — bars live in the entry, not in a dispatch doc
(convention recorded 2026-08-01). This document does not edit `OPEN_ITEMS.md` and neither
should Fable until the bar text is settled.

---

## 1. Header

| | |
|---|---|
| Item | #292 |
| Branch | `t27-292-producer-cancellation` off `main` (see §9 — HEAD is currently on the #295 branch) |
| Files in scope | `Talaria/Services/Live/SessionsHermesClient.swift`, `Talaria/Services/Live/SessionsHermesClient+RunsTransport.swift`, `TalariaTests/RunsPlaneTransportTests.swift` |
| Gate | `scripts/mac/lane-gate.sh` — Debug suite + XCUITest + **Release** build, literal `GATE: PASS` |
| Device | 292-C only |

---

## 2. Verified state

### VERIFIED — the defect site

`Talaria/Services/Live/SessionsHermesClient.swift:346-379` — `sendStreaming`:

```swift
    func sendStreaming(
        message content: String,
        attachments: [PendingAttachment] = [],
        clientMessageID: UUID
    ) -> AsyncStream<StreamingUpdate> {
        AsyncStream { continuation in                 // :351
            Task { @MainActor [weak self] in          // :352  ← unstructured, un-held, never cancelled
                ...
                continuation.finish()                 // :376
            }
        }
    }
```

- The `Task` at `:352` is **not bound to a `let`**, so nothing can cancel it.
- There is **no `continuation.onTermination`** anywhere in `sendStreaming`.
- The producer body is `streamTurnViaRuns` (`+RunsTransport.swift:274`) or `streamTurn`
  (`SessionsHermesClient.swift:434`), selected once at `:363`.

### VERIFIED — the `stallGuardedLines` FALSE POSITIVE (read this before you grep)

`SessionsHermesClient.swift:427` **does** contain
`continuation.onTermination = { _ in pump.cancel(); watchdog.cancel() }`. A grep for
`onTermination` in this file returns exactly one hit and it looks like the fix already
landed. **It has not.**

That hook belongs to `nonisolated static func stallGuardedLines<S>(_:threshold:)`
(`:398`), which builds a **different stream** — an `AsyncThrowingStream<String, Error>`
opened at `:402` that wraps a byte-line sequence for #246's stall guard. Its `pump` and
`watchdog` are the two tasks *inside that helper*, not the turn producer. The helper is
consumed at `+RunsTransport.swift:443` and `SessionsHermesClient.swift:641`, i.e. **inside**
the producer — cancelling it does not cancel the producer, it is the producer that would
have to be cancelled to cancel it.

Two independent streams, ~50 lines apart, one hook. The distinction:

| | `sendStreaming` (the defect) | `stallGuardedLines` (the false positive) |
|---|---|---|
| declared | `:346` | `:398` |
| stream | `AsyncStream<StreamingUpdate>` `:351` | `AsyncThrowingStream<String, Error>` `:402` |
| owns | the whole turn (submit, events, poll) | one line iterator + a watchdog timer |
| `onTermination` | **absent** | present, `:427-430` |

*(The `#292` entry and the task brief both refer to this helper as "`withStallWatchdog`".
No such symbol exists at HEAD; the name is `stallGuardedLines`. See §4.)*

### VERIFIED — the consumer chain, and that the hook is the ONLY missing link

1. `ChatStore.sendMessage` holds the consumer: `streamingTask` (`ChatStore.swift:85`,
   assigned `:653`), iterating `for await update in stream` (`:654`). It never `break`s
   early on a terminal update — the only loop-level `break` is `if Task.isCancelled`
   (`:656`); the `break` at `:929` is a `switch`-case break inside `case .interrupted`.
   `NativeVoicePipelineService.swift:502` is the same shape (its `break`s at `:508`, `:518`,
   … are all switch-case breaks). **So the consumer only ever detaches by cancellation.**
2. `ChatBackendRouter.sendStreaming` (`:413`) wraps upstream in its own `AsyncStream`
   (`:434`) with `let pump = Task {…}` (`:435`) **and the hook** (`:460-461`
   `continuation.onTermination = { _ in pump.cancel() }`, filed as #192).
3. `ResilientHermesClient.sendStreaming` (`:47-49`) returns `primary.sendStreaming(...)`
   verbatim — a pure pass-through, no wrapper, no hook needed.

So `ChatStore.streamingTask.cancel()` → router pump released → router `onTermination` →
`pump.cancel()` → the router's `for await update in upstream` ends → **the client's
`AsyncStream` is released with no hook** → the producer Task runs on with
`Task.isCancelled == false`. The router already proves the exact fix shape works in this
codebase, and `ChatBackendRouterTests.consumerWalkAwayAloneReleasesTheRoutingLock`
(`:437-462`) already pins that a consumer cancel reaches an `onTermination` here.

### VERIFIED — what the orphaned producer then does

- `+RunsTransport.swift:444` `if Task.isCancelled { break }` — inside the events `for try
  await`. Unreachable from a consumer walk-away.
- `+RunsTransport.swift:799` `if Task.isCancelled { return nil }` — top of
  `pollRunToTerminal`'s loop (`:788`). Unreachable. `:833`'s `catch { return nil // cancelled
  mid-wait }` on `Task.sleep` — likewise unreachable.
- Knobs: `runsPollInterval = .seconds(2)` (`SessionsHermesClient.swift:54`),
  `runsPollBudget = .seconds(120)` (`:71`). **~60 authenticated `GET /v1/runs/{id}` over
  2 minutes**, confirming the entry's arithmetic.
- Sessions plane is affected too, more mildly: `streamTurn`'s byte read holds until
  `streamStallThreshold = .seconds(60)` (`:45`) trips the stall guard. The fix releases it
  promptly. Bonus, not a bar.

### VERIFIED — the three interaction surfaces (details in §5)

- `armPendingRunRecovery` — `ChatStore.swift:1115-1134`. Called from `:938` (the
  `.interrupted` arm) and `:1331` (the #295 expiration arm).
- `PendingRun` — `ChatStore.swift:324-333`; `runId` is `String?`.
- `activeStreamRun` — `ChatStore.swift:120`, **a session id `String?`, not a run id**;
  doc `:105-119` records that the `runId` half was deliberately dropped in #295's review as
  provably always nil.
- `hardStopActiveRun` (the ONLY `/stop` sender) — `+RunsTransport.swift:1014-1042`.
- `deliverPolledTerminal` — `+RunsTransport.swift:882-961`, incl. the usage write at `:931`.
- The producer's `defer` — `+RunsTransport.swift:310-316`
  (`clearActiveRunContext` + `consumeSelfStopped` + `continuation.finish()`).

### ASSUMED — carry these as assumptions, not facts

- **`AsyncStream` fires `onTermination` when the iterating task is cancelled.** Not
  re-derived from the stdlib here. Evidence it holds in this codebase: the router's #192
  hook is load-bearing in production and pinned by
  `consumerWalkAwayAloneReleasesTheRoutingLock`. 292-A will re-prove it for the client's
  stream directly; if it turns out not to hold, 292-A goes RED for a reason other than the
  defect and Fable must say so rather than weakening the test.
- **Cancelling the producer aborts the in-flight `URLSession` request promptly.** Expected
  (`session.bytes`/`session.data` are cancellation-aware), but the test asserts the *poll
  count freezing*, which does not depend on how fast the in-flight request unwinds.
- **`Task.cancel()` still lets the `defer` at `+RunsTransport.swift:310` run.** Standard
  unwinding. If it did not, `activeRunContext` would leak — 292-A's fixture will show it.

---

## 3. The defect

`AsyncStream`'s producer closure receives a continuation and is expected to register a
teardown hook. `sendStreaming` registers none, and additionally does not retain the
producer Task in a `let`, so there is no handle to cancel even if a hook were added later
by hand.

An **unstructured** `Task` inherits actor isolation, priority and task-locals from its
creation context — **not cancellation**. It is not a child of the consumer, so releasing
the consumer's iterator cannot propagate anything to it. It ends only when its body ends.

For the runs plane the body's tail is a **bounded poll loop**, which is what escalates this
from wasted-liveness to wasted-work:

1. Consumer walks away → `ChatStore.streamingTask.cancel()` (`ChatStore.swift:1276`, or
   `:1162` inside `abandonPendingRun`).
2. Router pump cancelled via its hook (`ChatBackendRouter.swift:460`); the client's
   `AsyncStream` is released.
3. The producer notices nothing. Its events read eventually fails or the stall guard trips
   (`+RunsTransport.swift:443`), landing in the `catch` at `:536`.
4. `runSubmitted` is true and `runID` is non-nil, so it calls `deliverPolledTerminal`
   (`:550`) → `pollRunToTerminal` (`:788`).
5. `Task.isCancelled` at `:799` is **false**, so the loop runs to its own budget:
   `runsPollBudget / runsPollInterval` = 120s / 2s ≈ **60 authenticated GETs** for a turn
   nobody is watching.
6. Every terminal yield it eventually produces (`.finished`, `.interrupted`, `.failed`)
   goes into a terminated continuation and is discarded.

The comment at `+RunsTransport.swift:546-547` states the opposite invariant in so many
words:

```
                // waiting for may already exist (3A-B). `Task.isCancelled`
                // makes the poll a no-op, so a stopped consumer costs nothing.
```

A stopped consumer costs ~60 requests. `pollRunToTerminal`'s doc repeats the claim at
`:777` ("or on cancellation") and `:780-781` ("`Task.isCancelled` exits silently: the
consumer stopped, so there is nothing left to deliver an answer to"). All three are true
*after* the fix and false today — which is the honest way to read them: they document the
intended contract, and the contract was never wired.

**The fix, in one shape:**

```swift
        AsyncStream { continuation in
            let producer = Task { @MainActor [weak self] in
                ...
            }
            continuation.onTermination = { _ in producer.cancel() }
        }
```

Identical to `ChatBackendRouter.swift:434-462`. Deliberately mirror it, including the
comment style, so the two cannot drift.

---

## 4. ⚠️ Tracker corrections

Corrections go **upstream**, to the stale claim's own home, in the same commit as the
result that falsifies them (the close-out rule). These are the ones this brief found.
**Fable applies them; this document does not edit `OPEN_ITEMS.md`.**

1. **`#292`: "`SessionsHermesClient.swift:322-350`" is stale.** The producer is
   `:346-379` at HEAD; the `Task` is `:352`. (`:322-350` at HEAD is `postSyncTurn` /
   `discardStaleHop` / `postSyncChat` — an unrelated region.)
2. **`#292`: "`RunsTransport.swift:535-536`" — wrong file name AND wrong lines.** There is
   no file named `RunsTransport.swift` in the repo (`find` returns nothing). The file is
   `Talaria/Services/Live/SessionsHermesClient+RunsTransport.swift` and the comment is at
   **`:546-547`**. `:535-536` at HEAD is the tail of the events loop plus the `} catch {`.
3. **`#292` under-counts the comment sites.** It names one; there are **three**, all in
   `+RunsTransport.swift`: `:546-547`, `:777`, `:780-781`. 292-B must cover all three (§6).
4. **The task brief's "`withStallWatchdog`" does not exist.** The helper is
   `stallGuardedLines` (`SessionsHermesClient.swift:398`). Not a tracker line — recorded
   here so the next reader searching for that symbol does not conclude the code moved.
5. **`#292`: "`streamTurnViaRuns` (`:434`)" and "`pollRunToTerminal` (`:780`, `:814`)".**
   At HEAD: `streamTurnViaRuns`'s check is `:444`; `pollRunToTerminal` has **one**
   `Task.isCancelled` (`:799`) plus a cancellation-shaped `catch` on its sleep (`:833`).
   `:780` is a doc line, not a check. Same conclusion, better citations.
6. **`#295`'s Owen ruling names a runs-plane mechanism that did not ship.** The ruling
   (`OPEN_ITEMS.md:5337`) reads: "Runs plane: the status poll (the answer is durably
   fetchable for ~1h)." What shipped arms **one** route on both planes —
   `armPendingRunRecovery` → `reconcileFromServer()` → the *Sessions* messages GET
   (`SessionsHermesClient.swift:734-742`). No `GET /v1/runs/{id}` is armed by the
   expiration path. This is **not a bug** (it works — a run carrying a `session_id` writes
   its turns into SessionDB, live-verified in #283 slice 3A), but the entry should say what
   shipped. Add a dated supersession note to `#295`. See Ruling 3.

---

## 5. The three interaction rulings

### Ruling 1 — #295's recovery is INDEPENDENT of the producer. **PROCEED.** *(Mine. Not Owen's.)*

`#292`'s entry flags the interaction; `#295`'s entry says "the producer keeps running on
that path regardless." Both are right, and the recovery does not depend on it.

**Evidence.**

- `cancelStreaming` **already** cancels the consumer before it arms anything:
  `ChatStore.swift:1276` `streamingTask?.cancel()` runs at statement two; the arm is at
  `:1331`. Today that cancel already tears down the router pump and releases the client's
  stream. **The fix changes exactly one thing about that moment: the producer Task also
  stops.** Nothing between `:1276` and `:1331` reads the producer.
- The arm's inputs are all **store-side**: `armPendingRunRecovery(placeholderID:sessionId:
  runId:userMessageID:)` (`:1115`) takes `streamingMessageID`, `streamingUserMessageID`,
  and `activeStreamRun ?? activeSessionID` — the last being the shared journal's active hop
  (`SessionsHermesClient.ensureHopForTurn()` records it before the turn's POST goes out).
  `runId` is passed **`nil`** (`:1334`).
- The recovery *fetch* is a **different call on the client**, not work inside the producer:
  `startReconcileLoopIfNeeded()` (`:2359`) owns `reconcileTask`, whose attempts call
  `hermesClient.reconcileFromServer()` → `SessionsHermesClient.reconcileFromServer()`
  (`:734`) → `journal.activeHop` → `fetchSessionConversation(...)`. A fresh request.
- The producer cannot damage `journal.activeHop` on cancellation: the only `endHop()` it
  reaches is `discardStaleHop()` (`SessionsHermesClient.swift:331`), on the 404 stale-hop
  retry, which a cancelled task does not enter.
- #295's ordering pin
  (`expirationGateReadsRecoverabilityBeforeAbandonActiveRunClearsIt`) constrains the read
  of `currentRunIsServerRecoverable` relative to `streamingTask?.cancel()` and
  `abandonActiveRun()`. **Do not move that read.** The fix adds no statement to
  `cancelStreaming` at all, so the pin stays satisfied — but the test must stay green, and
  if it goes red, the fix moved something it shouldn't have.

**One real cost, and Fable must name it in the PR.** `deliverPolledTerminal` writes
`usageIndex?.record(sessionID:usage:)` at `+RunsTransport.swift:931`. Post-fix, an
abandoned runs turn's tokens are never recorded. This does **not** self-heal: the stored
transcript carries no usage at all (`SessionsHermesClient.swift:946-955`, #25's 2026-07-16
probe), and `reconcileFromServer` deliberately does not stamp `latestUsage`. Effect: the
CTX gauge for that session shows the *previous* run's occupancy instead of the abandoned
one's. **Recommend accepting it** — the alternative is ~60 authenticated requests to keep a
gauge current on a turn the user left — and it degrades honestly (stale, never zero, never
a hidden gauge). *Owen may overturn; it is small, and it is the only behavior the fix
takes away.*

### Ruling 2 — cancelling the producer does NOT stop the host run. **PROCEED.** *(Mine. Proven from the code, per #283's ruling.)*

#283's whole-branch review found that `abandonActiveRun` is the **walk-away** teardown
primitive (thread switch, new chat, `reset`, continued-send expiration) and that wiring
`/stop` onto it "would have silently killed host runs"
(`OPEN_ITEMS.md:6450-6457`). The ruling: **only an explicit Stop reaches the network.** So
the question this fix must answer is whether cancelling the client producer becomes a back
door to the same harm.

**It does not, and here is the closed enumeration rather than an argument.**

- `POST /v1/runs/{id}/stop` is issued at exactly **one** place:
  `hardStopActiveRun()` (`+RunsTransport.swift:1014-1042`, the request built at `:1024`).
- Its callers, exhaustively (`grep hardStopActiveRun` across `Talaria/`):
  `ChatStore.swift:1279` — **inside `if hardStopHost`**; `ChatBackendRouter.swift:519-521`
  — forward to the running backend; `ResilientHermesClient.swift:79-80` — forward to
  `primary`; `HermesClientProtocol.swift:213` — a no-op default. **None is reachable from
  `sendStreaming`'s producer or anything it calls.**
- The producer's cancellation path is network-free: cancel → the events read throws →
  `catch` (`:536`) → `deliverPolledTerminal` (`:550`) → `pollRunToTerminal` (`:788`) →
  `Task.isCancelled` (`:799`) → `return nil` **before any request is built** →
  `finishedYielded == false` → `.interrupted` yielded into a dead continuation.
- The `defer` (`:310-316`) runs `clearActiveRunContext(matchingRunID:)`
  (`SessionsHermesClient.swift:143`, a local nil-out), `consumeSelfStopped` (`:161`, an
  array removal), and `continuation.finish()` (a no-op on a terminated stream). All local.
- Device-proven from the other side: #283 3A-C half 2 walked away instead of tapping Stop
  and **no `/stop` request was sent at all**; the host finished
  `reason=text_response(finish_reason=stop)` with the answer waiting
  (`OPEN_ITEMS.md:6524-6527`). The fix does not add a call to that path.

**A positive side effect worth recording rather than hiding.** Today the `defer` runs when
the poll budget expires — up to 120s after walk-away — so `activeRunContext` (a **single
slot**, `SessionsHermesClient.swift:101`; #283 records the contention as a known
limitation) keeps naming a run nobody is watching for two minutes. Post-fix it clears at
walk-away. That *shrinks* the wrong-run-stop window. It also means a Stop tapped in that
window no longer reaches a stale run — which is the correct behavior, and 292-B's comment
rewrite should not claim more than that.

### Ruling 3 — the `run_id` is lost, but it was never held. **PROCEED as scoped. The durable-`run_id` upgrade is OWEN'S CALL and belongs in #295, not here.**

The premise to test: "the runs plane's status object survives ~1h and #295's ruling routes
runs-plane recovery through the status poll — does cancelling the producer lose the
`run_id` needed for that poll?"

**The `run_id`'s complete residency at HEAD:**

| holder | lifetime |
|---|---|
| `var runID: String?` local to `streamTurnViaRuns` (`+RunsTransport.swift:292`) | the producer Task |
| `activeRunContext.runID` (`SessionsHermesClient.swift:101`, set `:398`) | cleared by the producer's own `defer` (`:310`) |
| `.interrupted(sessionId:runId:)` (`StreamingUpdate.swift:63`) | the yield itself |
| `PendingRun.runId` (`ChatStore.swift:326`) | until reconcile |
| `activeStreamRun` (`ChatStore.swift:120`) | **holds no run id — it is a session id** |

So yes: cancelling the producer destroys the only live copy. **But the shipped #295
recovery never asks for it.**

- `cancelStreaming` passes `runId: nil` (`ChatStore.swift:1334`), with the doc at
  `:1329-1330` stating plainly that `runId` has no channel on that path.
- `PendingRun.runId` is consumed at **exactly one** site: `ChatStore.swift:2461-2462`
  `resolvedRunIDs.insert(runId)` — #237's duplicate-interrupt suppression. It is **never**
  used to address `GET /v1/runs/{id}`.
- The reconcile fetch is keyed by **session**, not run:
  `reconcileFromServer()` → `fetchSessionConversation(hop.apiSessionId, ...)`
  (`SessionsHermesClient.swift:734-742`).
- The ~1h status object is polled **only** by the producer (`deliverPolledTerminal` →
  `pollRunToTerminal`). On a walk-away its output lands in a dead continuation.

⇒ **The fix removes wasted work, not a recovery route.** Nothing that exists today loses a
capability.

**What is genuinely open, and it is Owen's.** His #295 ruling literally named the status
poll as the runs-plane recovery. What shipped is the sessions-messages GET on both planes —
correct in outcome (runs write into SessionDB), but not the named mechanism, and it has a
different failure profile (it recovers the *text* from the transcript; it does not recover
`usage`, per Ruling 1's cost). If he wants the literal ruling, a durable `run_id` must be
surfaced out of the producer — a new `StreamingUpdate` case, or a `runStarted` surfacing
that `ChatStore` can capture the way `activeStreamRun` captures the session id — and #292's
fix makes that **more** necessary, not less, because post-fix the producer is guaranteed
not to be around to poll.

**Recommendation: do not build it in #292.** File it against #295 as a follow-up with the
correction from §4 item 6, present both to Owen, and let him route. #292 ships the
cancellation and nothing else.

---

## 6. Pre-registered bars

Reproduced in full. **These must be in the `#292` entry, with 292-A's refinement, before
any code.**

> **(292-A)** cancelling the consumer stops the producer — assert the poll count stops
> advancing after the consumer's stream is released (the suite's 800ms budget hides this
> today, so the test must assert the producer, not the collector).
>
> **(292-B)** `RunsTransport.swift:535-536`'s comment describes what the code does.
>
> **(292-C)** device arm: walk away from a runs turn, kill the network past 60s, and
> confirm the host log shows NO further `GET /v1/runs/{id}` polls.

### 292-A — the observation mechanism, spelled out

**The bar's teeth, restated:** `makeClient` sets `runsPollBudget = .milliseconds(800)`
(`RunsPlaneTransportTests.swift:350`) suite-wide. A test that cancels the collector and then
observes "no more updates" proves nothing — the collector stopped receiving because *it*
was cancelled, and the producer would have stopped within 800ms anyway. **A test that
cannot fail on the defect is worse than no test.**

**Observe the producer through the counting stub, not the collector.**
`RunsStubURLProtocol` (`:50`) already records every request in an
`OSAllocatedUnfairLock<[RecordedRequest]>` (`:73`) written from `startLoading()` (`:117`),
with `static func count(_ path:)` at `:100`. That log lives **outside** the collector, is
written on URLSession's loader queues, and is exactly "did the producer issue a request."
Existing precedent: `killedStreamRecoversFinalAnswerViaStatusPollExactlyOnce` (`:763`) and
`pollBudgetExpiryYieldsInterruptedNotFailed` (`:832`) both assert on
`count("/v1/runs/run-r1")`.

**Do not** use an injected clock (the poll's `deadline` is `ContinuousClock`-based inside
the client with no seam) or an actor-isolated tally in the client (that would be new
production surface for a test). The stub is already the right instrument.

**Test:** `TalariaTests/RunsPlaneTransportTests.swift`, new
`@Test @MainActor func consumerWalkAwayCancelsTheProducerAndStopsThePolling()`.

Shape — the fixture is `killedStreamRecoversFinalAnswerViaStatusPollExactlyOnce`'s, with
the status route stuck on `running` forever so the loop cannot self-terminate:

1. `RunsStubURLProtocol.script = Self.script(sseBody: Self.runsSSE([one delta]),
   statusBodies: [Self.runningStatus], failEventsAfterBody: .networkConnectionLost)`.
   The stream opens, dies, and the catch path enters `pollRunToTerminal`, which will never
   see a terminal status.
2. `let client = makeClient(label: "walk-away-stops-polling")`, then **override the suite
   default so the budget cannot be the thing that stops it**:
   `client.runsPollBudget = .seconds(30)` and `client.runsPollInterval = .milliseconds(40)`.
   *This override is the bar's teeth — without it the 800ms default ends the poll on its
   own and the test passes on the defect.* Put that sentence in the test as a comment.
3. Start a collector **inline**, not via `collect(from:)` (that helper awaits
   `collector.value` to completion and owns its own 10s belt):
   ```swift
   let collector = Task { @MainActor in
       for await _ in client.sendStreaming(message: "hi", attachments: [], clientMessageID: UUID()) {}
   }
   ```
4. **Wait for the poll to be live**, bounded by scheduler turns, not wall clock:
   spin `await Task.yield()` / `try await Task.sleep(for: .milliseconds(10))` until
   `RunsStubURLProtocol.count("/v1/runs/run-r1") >= 2`, with a bounded iteration cap that
   `#expect`-fails with a message if it is never reached. Two, not one, so the *loop* is
   proven live rather than a single opportunistic read.
5. `collector.cancel(); _ = await collector.value` — the walk-away.
6. `let atWalkAway = RunsStubURLProtocol.count("/v1/runs/run-r1")`.
7. Sleep **at least 10 poll intervals** (`.milliseconds(500)` against a 40ms interval) —
   long enough that a live producer would issue ~12 more requests, and far short of the
   30s budget.
8. `#expect(RunsStubURLProtocol.count("/v1/runs/run-r1") == atWalkAway, "the producer kept
   polling after the consumer walked away — #292")`.

Allow **at most one** in-flight request to land after the cancel if step 8 proves flaky in
practice (`<= atWalkAway + 1`) — but only after seeing it flake, and record why in the
test. Do not start there: an off-by-one tolerance written up front is how a bar gets
softened before it has been earned.

**RED evidence is mandatory and specific.** Run the test on HEAD *before* the fix and record
the actual numbers (expect roughly `atWalkAway + 12`). "It failed" is not the evidence;
`atWalkAway = 3, final = 15` is. Then apply the fix and re-run. A green-on-first-write test
here is a *failed* bar — it means the budget or the interval override did not take.

**Second assertion in the same test (cheap, catches the `defer`-doesn't-run hazard from §2's
ASSUMED list):** after the walk-away settles, `#expect(client.activeRunContext == nil)`.
`activeRunContext` is `private(set)` internal (`SessionsHermesClient.swift:101`) so the test
target can read it.

**Third test, sessions-plane parity** —
`@Test @MainActor func consumerWalkAwayCancelsTheSessionsPlaneProducerToo()`: the same fix
covers `streamTurn`. `StreamLossClassificationTests` has the sessions-plane stub
(`DroppingSSEProtocol`, referenced at `RunsPlaneTransportTests.swift:47`). Optional — add it
only if it can be written without new stub infrastructure. **Not a bar.**

### 292-B — the comment. **Three sites, not one.**

`Talaria/Services/Live/SessionsHermesClient+RunsTransport.swift`:

- **`:546-547`** — the site `#292` names (at its corrected location):
  ``// waiting for may already exist (3A-B). `Task.isCancelled` / // makes the poll a no-op,
  so a stopped consumer costs nothing.``
- **`:777`** — `pollRunToTerminal`'s doc: "…when reads keep failing, **or on cancellation**."
- **`:780-781`** — `` `Task.isCancelled` exits silently: the consumer stopped, so there is
  nothing left to deliver an answer to. ``

All three become TRUE with the fix. **Do not delete them — that would lose the invariant.**
Rewrite each so it names the mechanism that makes it true, in the house style: point at
`sendStreaming`'s `onTermination` and at `#292`, so a future reader who deletes the hook
finds the three comments that depend on it. Add a matching note at
`SessionsHermesClient.swift:346`'s hook explaining that these three checks are its
customers.

Bar 292-B is met when: the three comments describe shipped behavior, **and** a repo-wide
grep for "costs nothing" / "exits silently" / "makes the poll a no-op" surfaces no
remaining claim the code does not walk. Report the grep in the close-out, the way #295-C
did.

### 292-C — **needs a device.** Runs switch ON.

`whoGoesThere` (iPhone, iOS 27 beta), Developer-screen runs-transport switch ON, host =
OJAMD. Deploy by Xcode bridge on LAN or `scripts/mac/ota-stage.sh` if Owen is remote.

Procedure: send a long-running runs turn; once the stream is clearly live, **walk away
without tapping Stop** (switch threads, or background the app — both reach
`streamingTask.cancel()`, via `abandonPendingRun` `ChatStore.swift:1162` and
`cancelStreaming` `:1276` respectively); then kill the network and hold past 60s.

**PASS =** the host log shows **no** `GET /v1/runs/{id}` after the walk-away, **and** no
`POST /v1/runs/{id}/stop` at all (that second half is Ruling 2's device proof — the walk-away
must remain network-free, exactly as #283 3A-C half 2 measured). The turn should still
resolve on return via the reconcile path.

**Instrument the error path.** Record the poll count *before* the walk-away too, so a run
where the producer never got into the poll loop reads as **inconclusive**, not as a pass. A
zero-after with no non-zero-before proves nothing.

Queue it in `dispatch/DEVICE-PASS-RUNNING-LIST.md` rather than blocking the merge on it, if
Owen's device time is scarce — but 292-C is a bar, so the lane is not closed until it runs.

---

## 7. Task breakdown

TDD. RED evidence at every step, in the commit message.

**Task 1 — RED.** Write `consumerWalkAwayCancelsTheProducerAndStopsThePolling` per §6 in
`TalariaTests/RunsPlaneTransportTests.swift`. Run it. **Record the two counts.** Do not
touch production code in this commit.
Commit: `test(#292): RED — the producer keeps polling after the consumer walks away`.

**Task 2 — GREEN.** `SessionsHermesClient.swift:351-378`: bind the producer to a `let`, add
`continuation.onTermination = { _ in producer.cancel() }`. Mirror
`ChatBackendRouter.swift:434-462`, comment included. Re-run Task 1's test; confirm the
count freezes. Re-run the whole `RunsPlaneTransportTests` suite (32 tests as of #295's
close-out) — **`streamCompletionSuppressesThePollPath` (`:801`) and
`killedStreamRecoversFinalAnswerViaStatusPollExactlyOnce` (`:763`) are the two most likely
to move**, because they both depend on a still-attached consumer. If either moves, stop:
that is a real regression, not a fixture to adjust.
Commit: `fix(#292): cancel the runs producer when the consumer walks away`.

**Task 3 — the #295 interaction, pinned rather than asserted.** Run `AppStoresTests`
(118/118 at #295's close-out) and specifically
`expirationPathArmsTheRealRecovery`, `expirationPathSettlesTheUserRowWorking`,
`explicitStopStillSettlesTheUserRowDelivered`,
`explicitStopMintsNoPendingRunAndArmsNoReconcileLoop`,
`localBrainExpirationArmsNoRecoveryAndPreservesThePartial`,
`expirationGateReadsRecoverabilityBeforeAbandonActiveRunClearsIt`,
`expirationArmsRecoveryEvenWithZeroStreamingUpdatesProcessed`. All must stay green
**without edits**. If any needs an edit, Ruling 1 is falsified — stop and report; do not
adapt the test.
Also run `ChatBackendRouterTests.consumerWalkAwayAloneReleasesTheRoutingLock` and
`hardStopActiveRunForwardsToTheRunningBackendWithoutTouchingTheLock` (`:402`) — Ruling 2's
unit-level guards.
No commit unless something moved.

**Task 4 — 292-B.** Rewrite the three comments (§6). Add the reciprocal note at the hook.
Run the grep. Commit: `docs(#292): the three cancellation comments now describe shipped behavior`.

**Task 5 — tracker corrections.** Apply §4 items 1-6 to `OPEN_ITEMS.md` (`#292`'s citations;
a dated supersession note on `#295` for item 6). Same commit as the result that falsifies
them, per the close-out rule.

**Task 6 — the gate.** §9.

**Task 7 — 292-C.** Device. §6.

---

## 8. Traps and interactions

1. **The `stallGuardedLines` false positive.** §2. One `onTermination` in the file; it is
   not the one. Costs a full session if taken at face value.
2. **The 800ms suite budget.** `makeClient` (`:349-350`) shortens both knobs suite-wide so
   loss tests don't park on a belt. A 292-A that inherits it passes on the defect. **The
   per-test override is the bar.**
3. **`collect(from:)` is the wrong helper.** `RunsPlaneTransportTests.swift:370-392` runs the
   collector to completion under its own 10s belt. 292-A needs to cancel mid-flight and
   keep observing afterward — inline the collector.
4. **Do not reorder anything in `cancelStreaming`.** `ChatStore.swift:1275`'s read of
   `currentRunIsServerRecoverable` must stay the FIRST statement; #295 shipped a test
   (`expirationGateReadsRecoverabilityBeforeAbandonActiveRunClearsIt`) that goes red if it
   moves below `abandonActiveRun()`. #292 needs no change in this file at all.
5. **Do not wire the producer cancel to `/stop`.** That is #283's ruling and it is Owen's
   one-line flip to make, not a lane's. Ruling 2.
6. **`weak self` in the new closure is wrong.** `onTermination` must capture the Task
   strongly — it is a value type handle, and a weak capture of `self` is not what cancels
   anything. Copy the router's shape exactly.
7. **Release build.** #218: the suite is Debug and cannot see a broken Release build. The
   gate covers it; do not skip the Release half.
8. **`xcodegen generate` is NOT needed** — no files added or removed, only edits.
9. **DerivedData for this repo is `Talaria-gzpowyfsuofejnbsytskngrskzkm`.** Resolve it from
   `info.plist`, never memory. If the test count does not MOVE after adding 292-A's test,
   you are running a stale `.xctest` — purge `Build/Intermediates.noindex` and run plain
   `test`, not `test-without-building`.
10. **Background waiter hygiene.** The gate takes minutes: `nohup … &` and poll the log with
    an `until grep` loop for the literal `GATE: PASS`. Kill the waiter the moment the answer
    arrives another way. **Never arm a Monitor; never wait for a notification.**

---

## 9. Close-out

**Branch.** HEAD is `t27-295-expiration-recovery`, clean. Branch #292 off `main` **after**
#295 merges, or off the #295 branch if it has not merged yet — but say which in the PR,
because #292's tests exercise code #295 wrote and a reviewer needs to know the base.

**Gate.**
```bash
nohup scripts/mac/lane-gate.sh > /tmp/292-gate.log 2>&1 &
# then poll: until grep -q "GATE: PASS" /tmp/292-gate.log; do sleep 20; done
```
Debug suite (units + XCUITest) **and** a Release build; a positive `GATE: PASS` marker from
each. Report the suite counts, and confirm `RunsPlaneTransportTests` moved from 32 to 33
(or 34 with the optional sessions-plane parity test) — a count that did not move means the
old binary ran.

**Upstream text this result falsifies** (close-out rule — same commit as the result):
- `+RunsTransport.swift:546-547`, `:777`, `:780-781` — 292-B.
- `OPEN_ITEMS.md` `#292` — the five stale citations, §4 items 1-3 and 5.
- `OPEN_ITEMS.md` `#295` — a dated supersession note for §4 item 6 (the ruling named the
  runs status poll; the sessions-messages GET shipped on both planes), plus a line
  resolving the "interaction with #292 noted, not blocking" note now that it is resolved:
  **the recovery is independent of the producer; the fix does not disturb it.**
- `OPEN_ITEMS.md` `#283` — its recorded "~3 min worst case" silence window and its
  `activeRunContext` single-slot limitation both shift slightly (the wrong-run-stop window
  shrinks from ≤120s to ~0). A dated note, not a rewrite.
- **`CLAUDE.md` — nothing.** No standing rule this brief touched is falsified by #292. Say
  so explicitly in the close-out rather than leaving it unstated.

**PR.** Title: `fix(#292): cancel the runs producer when the consumer walks away`. Body must
carry, in this order: the three rulings with their evidence; 292-A's RED numbers (before and
after counts, not "it failed"); the usage-index cost from Ruling 1 called out as a
deliberate, Owen-overturnable trade; 292-C's status (run, or queued in
`dispatch/DEVICE-PASS-RUNNING-LIST.md`); and the gate result. **Do not submit anything
outward-facing without Owen's read of the exact text and an explicit go.**

**Open for Owen, both from Ruling 3 — present together, do not build either in this lane:**
1. Should the runs plane get the literal status-poll recovery his #295 ruling named
   (requires surfacing a durable `run_id` out of the producer)?
2. Accept the abandoned-turn usage-index gap, or is a single final status read on
   cancellation worth it?
