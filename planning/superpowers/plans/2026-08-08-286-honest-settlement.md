# #286 Honest Platform-Link Settlement Implementation Plan

> **OUTCOME 2026-08-08:** all 4 tasks executed, bars 286-A..F met, merged same day as GitHub PR #283 (merge `eca58b3`).

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A failed ACK or `query_result` POST is never reported `.delivered` — settlement
failures classify honestly, engage the existing backoff ladder, and a failed query answer
retries once inside the agent's 40s window.

**Architecture:** Everything is app-side in `TalariaPlatformLink.swift` (Owen's ruling
2026-08-08: NO plugin TTL/attempt-cap — honest app settlement is the fix; never patch
Hermes core). `ack`/`answer` return success, `drain` folds any settlement failure into
`.failed` (the loop's existing `.failed` arm IS the backoff — no new outcome case), and
`answer` gets one bounded in-turn retry because queries are consumed-once host-side.
Design source: the #286 entry (fix shape + the 2026-08-07 protocol read + Owen's rulings)
— bars 286-A..F are pre-registered THERE.

**Tech Stack:** Swift 6, swift-testing, the existing `StubURLProtocol` harness in
`TalariaTests/TalariaPlatformLinkTests.swift` (real link, real URLSession, per-request
handler).

## Global Constraints

- `DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer` in every xcodebuild shell.
- Branch: `t27-286-honest-settlement` (worktree). Trailer
  `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` at commit time.
- Test runs: sim id `47F68496-24F9-45D9-93D3-1C778DB6B557`, suite-level
  `-only-testing:TalariaTests/TalariaPlatformLinkTests`, read the executed count and
  confirm it moved.
- **No plugin/relay/connector changes.** The ⛔ no-harden rule covers relay/connector;
  Owen's #286 ruling additionally forecloses plugin changes this lane.
- **Protocol facts that bind the design** (verified 2026-08-07 from plugin source, in the
  entry): duplicate ACK is a safe idempotent no-op; a missed ACK means redelivery (dedupe
  by `platformID` keeps it invisible); queries are consumed-once (`take_queries` pops) and
  the agent tool times out at 40s — **any query retry must complete well inside 40s**;
  `query_result` is exactly-once by `query_id`, recompute is safe; a wrong-device
  `query_result` returns `{"ok": false}` WITHOUT popping.
- **#285's turn discipline is inviolable:** every new await point in a turn respects the
  epoch checkpoints (`isCurrent(context)`); settlement retries must not do new work on a
  superseded turn.
- Lane gate (`scripts/mac/lane-gate.sh`, backgrounded + polled) before the PR.

---

### Task 1: Typed settlement results + honest drain classification (bars 286-A/B/C/D)

**Files:**
- Modify: `Talaria/Services/Live/TalariaPlatformLink.swift` (`drain` ~:185-252, `ack`
  ~:254-262, `answer` ~:264-296 — locate by content)
- Test: `TalariaTests/TalariaPlatformLinkTests.swift` (extend; reuse its `StubURLProtocol`
  + link construction verbatim)

**Interfaces:**
- Produces: `ack(...) async -> Bool`, `answer(...) async -> Bool` (true ⇔ HTTP 200),
  and `drain` returning `.failed` whenever any settlement POST failed. Task 2 wraps
  `answer`'s call site; Task 3 pins 401; Task 4 pins the loop interaction.

- [ ] **Step 1: Write the failing tests** (model construction/handler EXACTLY on the
  file's existing tests — same `makeLink`-style setup, same handler recording):

```swift
    @Test func ackServerErrorClassifiesTheDrainFailed() async {
        // Drain 200 with one item; ack POST answers 500.
        // Bars 286-A + 286-D's dedupe half: the item still reaches the app
        // (rows delivered before ack — the redelivery/dedupe design), but the
        // TURN classifies .failed so the ladder engages and the next drain
        // re-acks.
        // handler: first request (drain) -> 200 + one-item payload;
        //          second request (ack) -> 500, empty body.
        // #expect(outcome == .failed)
        // #expect(receivedItems.count == 1)
    }

    @Test func ackTransportFailureClassifiesTheDrainFailed() async {
        // Bar 286-B: ack request fails at transport (handler returns error
        // IMMEDIATELY — no response first; the URLProtocol stub delivers a
        // clean didFailWithError). #expect(outcome == .failed)
    }

    @Test func queryResultServerErrorClassifiesTheDrainFailed() async {
        // Bar 286-C: drain 200 with one query; both query_result attempts 500
        // (Task 2 adds a retry — this test's handler answers 500 to every
        // query_result POST so it stays valid before AND after Task 2).
        // #expect(outcome == .failed)
    }

    @Test func happyPathSettlementStaysDelivered() async {
        // Bar 286-D: drain 200 + item + query; ack 200; query_result 200.
        // #expect(outcome == .delivered)
    }
```

Write them as real tests against the real seam — the sketch above names the shape; the
file's existing tests are the authority for construction, handler wiring, and how
`drainOnce(wait:)` is invoked and its `DrainOutcome` asserted. `receivedItems` comes from
the `onItemsReceived` closure the existing tests already capture.

- [ ] **Step 2: Run to verify failure.** `ackServerErrorClassifiesTheDrainFailed` and
  `queryResultServerErrorClassifiesTheDrainFailed` FAIL (outcome is `.delivered` today);
  the happy-path test passes (it pins current behavior against regression).

- [ ] **Step 3: Implement.**

```swift
    /// #286: settlement success is part of the turn's outcome. True ⇔ HTTP
    /// 200. A failed ack needs NO in-turn retry — the outbox redelivers
    /// un-acked items and `mark_delivered` is idempotent (protocol read,
    /// 2026-08-07); the honest `.failed` classification is what re-arms the
    /// backoff that the false `.delivered` used to reset.
    private func ack(itemIDs: [String], context: TurnContext, token: String, deviceID: String) async -> Bool {
        let body: [String: Any] = [
            "type": "ack",
            "auth": token,
            "device_id": deviceID,
            "item_ids": itemIDs,
        ]
        guard let (status, data) = await post(body, context: context, bearer: token) else {
            logEnvelopeError(status: nil, data: nil, verb: "ack")
            return false
        }
        if status != 200 { logEnvelopeError(status: status, data: data, verb: "ack") }
        return status == 200
    }
```

(`logEnvelopeError` currently takes non-optional `status: Int` — check its signature and
either overload or pass a sentinel the existing signature accepts; match the file's own
idiom.) `answer` gets the same shape: capture `(status, data)` from its final `post`,
log non-200, `return status == 200` (transport nil → log + false). In `drain`:

```swift
        var didWork = false
        var settlementFailed = false
        if !drained.items.isEmpty {
            onItemsReceived(drained.items)
            if !(await ack(itemIDs: drained.items.map(\.id), context: context, token: token, deviceID: deviceID)) {
                settlementFailed = true
            }
            didWork = true
        }
        for query in drained.queries {
            guard isCurrent(context) else { return .superseded }
            if !(await answer(query, context: context, token: token, deviceID: deviceID)) {
                settlementFailed = true
            }
            didWork = true
        }
        // #286: a turn whose settlement failed is not a delivered turn —
        // `.failed` feeds the existing ladder (bars 286-A/B/C), and the next
        // drain redelivers + re-acks (idempotent upstream). The rows the app
        // already showed stay shown; `platformID` dedupe keeps redelivery
        // invisible (bar 286-D).
        if settlementFailed { return .failed }
        return didWork ? .delivered : .idle
```

- [ ] **Step 4: Run tests to verify pass** (executed count moved by 4).
- [ ] **Step 5: Commit** (`feat(#286): settlement failures classify the drain honestly — ack/answer return success, .delivered means delivered`).

---

### Task 2: One bounded in-turn retry for `answer` (the 40s window)

**Files:**
- Modify: `Talaria/Services/Live/TalariaPlatformLink.swift` (the `answer` call site in
  `drain`, or `answer` itself — implementer's choice, stated in the report)
- Test: `TalariaTests/TalariaPlatformLinkTests.swift`

**Interfaces:**
- Consumes: Task 1's `answer(...) -> Bool`.
- Produces: a failed `query_result` POST is retried ONCE after a short pause, inside the
  same turn, epoch-checked; both-fail still classifies `.failed`.

- [ ] **Step 1: Failing tests:**

```swift
    @Test func queryAnswerRetriesOnceAndRecovers() async {
        // query_result POST #1 -> 500, POST #2 -> 200: outcome .delivered,
        // exactly 2 query_result requests recorded, recomputation allowed
        // (the two bodies need not be byte-identical — exactly-once is by
        // query_id host-side).
    }

    @Test func queryAnswerRetryIsEpochChecked() async {
        // Between POST #1 (500) and the retry, stop() bumps the epoch (drive
        // it from the handler exactly the way ProfileSwitchAtomicityTests
        // drives mid-turn stops). Outcome .superseded; exactly 1
        // query_result request recorded.
    }
```

- [ ] **Step 2: Verify failure** (today: single attempt, `.failed` after Task 1).
- [ ] **Step 3: Implement.** At the query loop:

```swift
            // #286: queries are consumed-once host-side and the agent tool
            // gives up at 40s — this in-turn retry is the ONLY second chance
            // an answer gets. One retry, short pause, epoch-checked; total
            // added worst case (pause + one request timeout) stays well
            // inside the 40s window. Bounded by construction — never a loop.
            var answered = await answer(query, context: context, token: token, deviceID: deviceID)
            if !answered {
                try? await Task.sleep(for: .seconds(2))
                guard isCurrent(context) else { return .superseded }
                answered = await answer(query, context: context, token: token, deviceID: deviceID)
            }
            if !answered { settlementFailed = true }
```

Verify the arithmetic in the comment against `Self.requestTimeout`'s actual value
(2s pause + one timeout must sit well under 40s; if `requestTimeout` is 20s the worst
case is ~22s — state the real number in the comment).

> **⚠️ CORRECTION 2026-08-08 (close-out, Task 4):** this section's own snippet
> is wrong about the number it tells the implementer to verify. The plan
> drafted above says the added worst case "stays well inside the 40s
> window" — but `Self.requestTimeout` is **40s, not 20s**, so the real added
> worst case (2s pause + one full request timeout) is **~42s, PAST the 40s
> window**, not comfortably inside it. The shipped code comment
> (`TalariaPlatformLink.swift`, the query loop in `drain`) states the real
> number and the reason it's still harmless rather than a defect: the
> agent tool's `discard_query` pops the query's future at 40s, so a retry
> POST that lands after the host has given up is a guaranteed no-op, not a
> late-delivered wrong answer. The retry is aimed at the common failure
> mode — a fast 500 or connection-refused — not a genuine 40s hang. This
> plan snippet is left as-drafted above for the historical record; the code
> and `OPEN_ITEMS.md` #286's bars-met note carry the corrected number.

- [ ] **Step 4: Verify pass.** Also confirm Task 1's
  `queryResultServerErrorClassifiesTheDrainFailed` still passes (its handler 500s every
  attempt — now two requests recorded).
- [ ] **Step 5: Commit** (`feat(#286): one epoch-checked in-turn retry for query answers — the 40s consumed-once window`).

---

### Task 3: 401 on settlement is defined, not accidental (bar 286-E)

**Files:**
- Modify: `Talaria/Services/Live/TalariaPlatformLink.swift` (doc comments on `ack`/`answer`)
- Test: `TalariaTests/TalariaPlatformLinkTests.swift`

**Interfaces:** none new — this pins semantics.

- [ ] **Step 1: Failing/pinning tests:**

```swift
    @Test func settlementUnauthorizedClassifiesFailedWithoutTouchingThePair() async {
        // Drain 200 + item; ack -> 401. Outcome .failed; the stored
        // token/deviceID keys are UNTOUCHED (assert via the secure-store
        // double the existing tests use) and exactly zero pair POSTs were
        // made — the 401-repair machinery is drain-owned and settlement
        // must not trigger it (a settlement 401 on a token that just
        // drained 200 is transient skew; a truly stale pair fails the NEXT
        // drain, which owns the repair).
    }
```

- [ ] **Step 2-4: Verify failure mode, implement (doc comment stating the above on both
  functions; behavior is already "non-200 → false" from Task 1 — this task exists to make
  401 EXPLICIT and pinned), verify pass.**
- [ ] **Step 5: Commit** (`test(#286): 401 on settlement pinned — failed, no repair, pair untouched (bar 286-E)`).

---

### Task 4: Ladder interaction pin (bar 286-F) + close-out

**Files:**
- Test: `TalariaTests/TalariaPlatformLinkTests.swift`
- Modify: `OPEN_ITEMS.md` (#286 — bars-met note), the plan/spec outcome lines

- [ ] **Step 1: Pinning test** — a settlement-failed turn feeds the existing ladder:

```swift
    @Test func settlementFailureEngagesTheBackoffLadderNotAHotLoop() async {
        // Pure pin, no loop run needed: .failed is the outcome (Task 1), and
        // the ladder maps failures 1,2,3 -> 1s,2s,4s (nextDelay is
        // harness-visible). Assert nextDelay(afterFailureCount: 1) == 1,
        // (2) == 2, (3) == 4 AND that the drain outcome for a settlement
        // failure is .failed — together: no hot loop by construction
        // (bar 286-F). If a nextDelay pin already exists in this file,
        // extend it rather than duplicating.
    }
```

- [ ] **Step 2-4: verify, implement nothing beyond the test, pass.**
- [ ] **Step 5: Full suite (`TalariaPlatformLinkTests` + `ProfileSwitchAtomicityTests` —
  the second file drives the same class through #285's discipline and must stay green),
  then the lane gate, backgrounded.**
- [ ] **Step 6: Close-out commit** — dated bars-met note in the #286 entry (each bar with
  its test name), outcome line on this plan. THE CLOSE-OUT RULE: correct anything the
  lane's result falsifies (expected: the entry's own "NOT STARTED" header phrase).
- [ ] **Step 7: PR** via `gh pr create` (body ends with the 🤖 line), hand Owen the merge.

---

## Self-review record

- **Spec coverage:** bars 286-A (T1), B (T1), C (T1+T2), D (T1), E (T3), F (T4); the
  protocol constraints (idempotent ack — no retry; consumed-once query — one bounded
  retry; recompute safe; no plugin changes) are all encoded in the tasks that touch them.
- **Placeholder scan:** Task 1 Step 1's tests are shape-sketches by design with the
  existing file named as the construction authority — the implementer transcribes the
  real harness, which this plan's author verified exists (`StubURLProtocol`, handler
  recording, `drainOnce` outcome assertions).
- **Type consistency:** `ack`/`answer -> Bool`, `settlementFailed` local, no new
  `DrainOutcome` case anywhere.
