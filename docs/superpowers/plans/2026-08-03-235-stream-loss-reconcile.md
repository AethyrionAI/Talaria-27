# #235 Stream-Loss Reconcile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A remote turn whose SSE stream dies can no longer lose its answer — empty closes arm recovery, the foreground reconcile stops being starved, and recovered replies land at the transcript tail per Owen's rule.

**Architecture:** Three routed end-states into the EXISTING `attemptReconcile` machinery (which is correct and stays untouched in its core): F1 a clean close with a started run and no answer text yields `.interrupted` instead of an empty `.finished`; F2 `reconcilePendingRuns()` moves to the FRONT of the activation chain (it was starved at the end of a cancellable network ladder — the mechanism revision found the trigger existed) plus a chat-appear single-shot; F3 `attemptReconcile` places a displaced recovered reply at the tail with a `recoveredForPrompt` marker. Plus the one-off 20-vs-300 timeout experiment, split-session change gated on its verdict.

**Tech Stack:** Swift/SwiftUI, swift-testing, xcodebuild on Xcode-beta4; pure-static truth-table test shape (the project standard).

**Spec:** `docs/superpowers/specs/2026-08-03-235-stream-loss-reconcile-design.md` (approved). **Mechanism revision vs spec, discovered pre-plan and honored here:** the foreground trigger EXISTS at AppContainer.swift:1573 — the defect is placement (end of the #145 Part D serial chain, superseded by rapid app-switching), so F2 is a MOVE plus one new trigger, not two new triggers. Record this in the entry at Task 5.

## Global Constraints

- `export DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer` in every build/test shell
- Branch `claude/t27-235-stream-reconcile` (exists; work here)
- NO new Swift files → no `xcodegen` run
- Sim destination: resolve exactly like the gate (`SIM_NAME="${TALARIA_SIM_NAME:-iPhone 17 Pro Max}"` → UDID; the session's resolved UDID is `47F68496-24F9-45D9-93D3-1C778DB6B557`)
- Plain `test`, never `test-without-building`; background long runs and poll; confirm reported counts MOVED
- Commits end with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`
- The reconcile core (`attemptReconcile`'s fetch/adopt/receipt/notify logic) is NOT restructured — only its placement step is appended
- #180: recovered-but-displaced replies are visibly stamped; undisplaced recovery renders byte-identically

---

### Task 1 (F1): empty clean-close routes to `.interrupted`

**Files:**
- Modify: `Talaria/Services/Live/SessionsHermesClient.swift` (the `!finalMessageDelivered` block at ~line 408; new pure static near the other decision statics)
- Test: `TalariaTests/ReasoningChannelTests.swift` (new MARK — the file already truth-tables this client's statics)

**Interfaces:**
- Consumes: existing locals in the stream function: `runStarted: Bool`, `pendingFinalMessage: Message?`, `assembledContent: String`, `capturedSessionId: String`, `runId: String?`; `StreamingUpdate.interrupted(sessionId:runId:)`
- Produces: `SessionsHermesClient.cleanCloseArmsRecovery(runStarted: Bool, effectiveContent: String) -> Bool`

- [ ] **Step 1: Write the failing truth-table test**

```swift
    // MARK: #235 F1 — the empty clean-close decision

    /// A started run whose stream closes with NO answer text must arm
    /// recovery, not deliver an empty bubble. Non-empty content keeps the
    /// partial-answer fallback (streamed text beats store adoption). A run
    /// that never started has nothing to reconcile.
    @Test func emptyCleanCloseArmsRecoveryOnlyForStartedRuns() {
        #expect(SessionsHermesClient.cleanCloseArmsRecovery(runStarted: true, effectiveContent: ""))
        #expect(SessionsHermesClient.cleanCloseArmsRecovery(runStarted: true, effectiveContent: "  \n\t"))
        #expect(!SessionsHermesClient.cleanCloseArmsRecovery(runStarted: true, effectiveContent: "partial answer"))
        #expect(!SessionsHermesClient.cleanCloseArmsRecovery(runStarted: false, effectiveContent: ""))
        #expect(!SessionsHermesClient.cleanCloseArmsRecovery(runStarted: false, effectiveContent: "text"))
    }
```

- [ ] **Step 2: Run to verify it fails**

```bash
nohup env DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer xcodebuild test -project Talaria.xcodeproj -scheme Talaria -destination "platform=iOS Simulator,id=47F68496-24F9-45D9-93D3-1C778DB6B557" -only-testing:TalariaTests/ReasoningChannelTests > /tmp/t235-task1-red.log 2>&1 &
```

Expected: BUILD FAILURE — `no member 'cleanCloseArmsRecovery'`.

- [ ] **Step 3: Implement — the pure static + the wiring**

Static (place beside `thinkingDelta`/`reasoningMirrorsAnswer`):

```swift
    /// #235 F1: a stream that ends CLEANLY (no thrown error) without
    /// run.completed, on a run that started, with no answer text assembled —
    /// the 9:47 shape. Delivering it as `.finished` produced an empty bubble
    /// and suppressed all recovery; it must arm the same `.interrupted` path
    /// a thrown error takes. Non-empty content keeps the fallback: a partial
    /// streamed answer beats store adoption, which would drop it.
    nonisolated static func cleanCloseArmsRecovery(runStarted: Bool, effectiveContent: String) -> Bool {
        runStarted && effectiveContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
```

Wiring — the `!finalMessageDelivered` block gains a guard at its TOP (before the fallback message is built):

```swift
            if !finalMessageDelivered {
                let effectiveContent = (pendingFinalMessage?.content.isEmpty == false)
                    ? pendingFinalMessage!.content : assembledContent
                if Self.cleanCloseArmsRecovery(runStarted: runStarted, effectiveContent: effectiveContent) {
                    // #235 F1: same recovery path as a thrown error — see the
                    // static's doc for why an empty close is not a success.
                    continuation.yield(.interrupted(sessionId: capturedSessionId, runId: runId))
                    return
                }
```

(The remainder of the existing block is unchanged and now only runs for non-empty closes.) Note: check the surrounding function — if the block sits in a closure where `return` would skip needed teardown, use the same exit shape the `catch` path uses; read the enclosing code before editing.

- [ ] **Step 4: Re-run; expected: new test PASSES, file count moved +1, no regressions**
- [ ] **Step 5: Commit**

```bash
git add Talaria/Services/Live/SessionsHermesClient.swift TalariaTests/ReasoningChannelTests.swift
git commit -m "#235 F1: empty clean-close arms recovery instead of delivering an empty bubble

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2 (F2): unstarve the foreground reconcile + chat-appear single-shot

**Files:**
- Modify: `Talaria/Stores/AppContainer.swift` (activation chain ~lines 1553–1574: move the reconcile call to the front)
- Modify: `Talaria/Features/Chat/ChatScreen.swift` (screen-level appear trigger)
- Test: `TalariaTests/AppStoresTests.swift` (model on its existing reconcile fixtures — grep `attemptReconcile`/`pendingRun` there and reuse the file's factory/fake-client pattern; do NOT invent a parallel seam)

**Interfaces:**
- Consumes: `ChatStore.reconcilePendingRuns()` (existing single-flight), `ChatStore.pendingRunSessionId`, the #145 Part D chain structure
- Produces: no new API — a reordering and one new call site

- [ ] **Step 1: Write the failing test** (adapt fixture names to the file's existing reconcile tests):

```swift
    /// #235 F2: the reconcile loop's budget expiring must NOT orphan the run —
    /// pendingRun survives retirement, and one reconcilePendingRuns() call
    /// (the foreground/appear single-shot) resolves it once the reply exists.
    @Test func budgetExpiryKeepsPendingRunAndSingleShotResolves() async throws {
        // Fixture shape per this file's existing reconcile tests: a ChatStore
        // with a fake backend whose server conversation is controllable, a
        // pendingRun installed, and the harness-visible budget shrunk:
        //   store.reconcileWallClockBudget = .milliseconds(80)
        //   store.reconcilePollInterval = .milliseconds(20)
        // 1. Backend returns NO qualifying reply → start the loop, await its
        //    retirement (poll store.hasActiveReconcileLoop == false with a
        //    bounded yield-pump).
        // 2. #expect(store.pendingRunSessionId != nil)   // NOT orphaned
        // 3. Point the fake backend at a conversation whose last hermes
        //    message postdates pending.sentAt with non-empty content.
        // 4. await store.reconcilePendingRuns()          // the single-shot
        // 5. #expect(store.pendingRunSessionId == nil)   // resolved
    }
```

(The comment-skeleton is the CONTRACT; write it as real code against the file's actual fixtures at execution. If the file's existing tests already pin "expiry keeps pendingRun", extend rather than duplicate.)

- [ ] **Step 2: Run `-only-testing:TalariaTests/AppStoresTests` → confirm the new test FAILS or errors only for the intended reason** (if `pendingRun` is already kept on expiry — the code suggests it is — the test may pass at once: then it is a pin, not a RED; note which in the commit message. The RED half of this task is Step 3's order-move having no test — the device bar covers it.)

- [ ] **Step 3: Move the activation-chain call to the front.** In `AppContainer` (the #145 Part D chain), DELETE these two lines at ~1573:

```swift
        await chatStore.reconcilePendingRuns()
        if Task.isCancelled { return }
```

and INSERT immediately BEFORE `await permissionsStore.reloadCapabilities()` (~line 1553):

```swift
        // #235 F2: a pending run is the user's stranded ANSWER — reconcile
        // FIRST, before the cancellable network ladder. At the old position
        // (end of chain) rapid app-switching superseded the chain before it
        // ever got here — measured on Owen's device 2026-08-03: answers sat
        // in the store while the chain restarted five fetches ahead of them.
        await chatStore.reconcilePendingRuns()
        if Task.isCancelled { return }
```

- [ ] **Step 4: The chat-appear single-shot.** In `ChatScreen` (environment `chatStore` exists at line 33): find the outermost view's modifier chain in `body`; if an `.onAppear`/`.task` already exists, add inside it, else attach:

```swift
        .task {
            // #235 F2: opening the chat is the user looking at the transcript —
            // one single-shot reconcile; single-flight coalesces with any
            // in-flight pass; instant no-op when nothing is pending.
            await chatStore.reconcilePendingRuns()
        }
```

- [ ] **Step 5: Run the AppStoresTests file → PASS; count moved as expected**
- [ ] **Step 6: Commit**

```bash
git add Talaria/Stores/AppContainer.swift Talaria/Features/Chat/ChatScreen.swift TalariaTests/AppStoresTests.swift
git commit -m "#235 F2: reconcile moves to the FRONT of the activation chain + chat-appear single-shot

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3 (F3): tail placement with the recovered marker

**Files:**
- Modify: `Talaria/Models/Message.swift` (new optional field after `reasoningSummary` ~line 84)
- Modify: `Talaria/Stores/ChatStore.swift` (`attemptReconcile` ~1780: capture prompt text pre-adoption; apply placement post-adoption; new pure static near `watchableSessionId`)
- Modify: `Talaria/Features/Chat/MessageBubble.swift` (marker row above the content, near the reasoning disclosure ~line 229)
- Test: `TalariaTests/AppStoresTests.swift` (placement truth-table) and `TalariaTests/ReasoningChannelTests.swift` if Message cache round-trip tests live there (grep `cache round-trip`; put the field round-trip test beside the existing Message-field one)

**Interfaces:**
- Consumes: `Message` (Codable, synthesized — optionals decode as absent-tolerant), `attemptReconcile`'s `pending: PendingRun` (`userMessageID`, `sentAt`) and `reply` lookup
- Produces: `Message.recoveredForPrompt: String?`; `ChatStore.placingRecoveredReply(_ replyID: UUID, prompt: String?, in messages: [Message]) -> [Message]`

- [ ] **Step 1: Write the failing tests**

```swift
    // MARK: #235 F3 — tail placement for recovered replies

    /// Owen's placement rule: a recovered reply DISPLACED by later exchanges
    /// moves to the tail and is stamped with the prompt it answers; an
    /// undisplaced reply is untouched — byte-identical adoption.
    @Test func displacedRecoveredReplyMovesToTailWithMarker() {
        let reply = Message(sender: .hermes, content: "the late answer", status: .delivered)
        let later1 = Message(sender: .user, content: "next question", status: .delivered)
        let later2 = Message(sender: .hermes, content: "next answer", status: .delivered)
        let placed = ChatStore.placingRecoveredReply(
            reply.id, prompt: "So what's the holdup?", in: [reply, later1, later2])
        #expect(placed.last?.id == reply.id)
        #expect(placed.last?.recoveredForPrompt == "So what's the holdup?")
        #expect(placed.map(\.id) == [later1.id, later2.id, reply.id])
    }

    @Test func undisplacedRecoveredReplyIsUntouched() {
        let q = Message(sender: .user, content: "question", status: .delivered)
        let reply = Message(sender: .hermes, content: "answer", status: .delivered)
        let placed = ChatStore.placingRecoveredReply(reply.id, prompt: "question", in: [q, reply])
        #expect(placed.map(\.id) == [q.id, reply.id])
        #expect(placed.last?.recoveredForPrompt == nil)
    }

    @Test func placementWithUnknownReplyIDIsIdentity() {
        let q = Message(sender: .user, content: "question", status: .delivered)
        let placed = ChatStore.placingRecoveredReply(UUID(), prompt: nil, in: [q])
        #expect(placed.map(\.id) == [q.id])
    }

    /// Prompt text is clipped to 60 chars for the marker.
    @Test func markerPromptIsClipped() {
        let reply = Message(sender: .hermes, content: "late", status: .delivered)
        let later = Message(sender: .user, content: "x", status: .delivered)
        let long = String(repeating: "p", count: 200)
        let placed = ChatStore.placingRecoveredReply(reply.id, prompt: long, in: [reply, later])
        #expect(placed.last?.recoveredForPrompt?.count == 60)
    }
```

- [ ] **Step 2: Run → BUILD FAILURE (`no member 'placingRecoveredReply'`, `no member 'recoveredForPrompt'`)**

- [ ] **Step 3: Implement**

`Message.swift`, after `reasoningSummary`:

```swift
    /// #235 F3: set ONLY when this reply was recovered after its stream died
    /// AND later exchanges had displaced it — carries a clipped prefix of the
    /// user prompt it answers. Local-only (a later openSession refetch shows
    /// server order); absent on every normal reply, so old caches decode fine.
    var recoveredForPrompt: String?
```

`ChatStore`, near `watchableSessionId` (the pure-static shape):

```swift
    /// #235 F3 — Owen's placement rule, pure so it truth-tables: a recovered
    /// reply below later exchanges is where nobody is looking; move it to the
    /// tail and stamp WHICH question it answers so it cannot masquerade as a
    /// reply to the newest one. Undisplaced → identity, byte-identical.
    nonisolated static func placingRecoveredReply(
        _ replyID: UUID, prompt: String?, in messages: [Message]
    ) -> [Message] {
        guard let idx = messages.firstIndex(where: { $0.id == replyID }),
              idx != messages.indices.last else { return messages }
        var result = messages
        var reply = result.remove(at: idx)
        reply.recoveredForPrompt = prompt.map { String($0.prefix(60)) } ?? "an earlier question"
        result.append(reply)
        return result
    }
```

`attemptReconcile` wiring — BEFORE the adoption line (`conversation = mergeConversationMetadata(...)`), capture the prompt:

```swift
        // #235 F3: the prompt text lives in the PRE-adoption conversation
        // (server rows have different ids) — capture it before replacing.
        let promptText = conversation?.messages
            .first(where: { $0.id == pending.userMessageID })?.content
```

AFTER the existing receipt/usage block (just before `pendingRun = nil`):

```swift
        // #235 F3: Owen's placement rule — recovered replies land at the tail.
        if var conv = conversation {
            conv.messages = Self.placingRecoveredReply(reply.id, prompt: promptText, in: conv.messages)
            conversation = conv
        }
```

(Note: `reply.id` here is the SERVER-adopted message's id — the same object the receipt block already indexes by `reply.id`, so the id is consistent within this function.)

`MessageBubble.swift` — insert directly ABOVE the reasoning disclosure (~line 229, inside the same content VStack):

```swift
                // #235 F3: a recovered reply displaced to the tail says which
                // question it answers — a late answer must never read as a
                // reply to the newest one (#180: degradation visible).
                if let prompt = message.recoveredForPrompt {
                    MonoLabel("↩ RECOVERED REPLY — “\(prompt)”", size: 8,
                              tracking: Design.Tracking.mono,
                              color: Design.Colors.mutedForeground)
                }
```

- [ ] **Step 4: Run both test files → PASS, counts moved (+4 placement tests)**
- [ ] **Step 5: Commit**

```bash
git add Talaria/Models/Message.swift Talaria/Stores/ChatStore.swift Talaria/Features/Chat/MessageBubble.swift TalariaTests/AppStoresTests.swift
git commit -m "#235 F3: recovered replies land at the tail with a marker naming their prompt (Owen's placement rule)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4 (235-D): the 20-vs-300 timeout experiment (one-off, never committed)

- [ ] **Step 1:** Write a TEMPORARY test file `TalariaTests/TimeoutPrecedenceProbe.swift` (xcodegen NOT run — add via `-only-testing` after a one-off `xcodegen generate`? NO: a new file needs the project regenerated. Instead put the probe INSIDE an existing file temporarily — append to `ReasoningChannelTests.swift`, clearly fenced with `// #235-D PROBE — DELETE BEFORE COMMIT`):

```swift
    // #235-D PROBE — DELETE BEFORE COMMIT
    /// Which idle timeout wins: the session config's 20s or the request's 300s
    /// stamp? A silent URLProtocol answers it: headers + one byte, then
    /// silence. If the task throws ~20s in, the CONFIG wins (every quiet
    /// stretch has been killing foregrounded streams); ~link stays alive past
    /// 30s → the REQUEST stamp wins and nothing changes (#145's assumption).
    final class StallingProtocol: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                           httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "text/event-stream"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("event: run.started\n".utf8))
            // then: silence forever
        }
        override func stopLoading() {}
    }

    @Test func probeWhichIdleTimeoutWins() async {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.protocolClasses = [StallingProtocol.self]
        let session = URLSession(configuration: config)
        var request = URLRequest(url: URL(string: "https://stall.probe/x")!)
        request.timeoutInterval = 300
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let start = ContinuousClock.now
        do {
            let (bytes, _) = try await session.bytes(for: request)
            for try await _ in bytes.lines { }
            Issue.record("stream ended without error — inconclusive")
        } catch {
            let elapsed = ContinuousClock.now - start
            print("#235-D VERDICT: threw after \(elapsed) — \(error.localizedDescription)")
            #expect(Bool(true))
        }
    }
    // END #235-D PROBE
```

- [ ] **Step 2:** Run ONLY this test (backgrounded; ~25–35 s runtime), read the printed VERDICT from the log.
- [ ] **Step 3:** Record the verdict in the OPEN_ITEMS #235 entry (Task 5 carries the edit). **Delete the probe code** (`git checkout` or edit it out — it must never be committed).
- [ ] **Step 4 (CONDITIONAL — only on a config-wins verdict):** give streams their own session in `SessionsHermesClient`:

```swift
    /// #235-D: streams get their own session — the shared config's 20s idle
    /// budget was measured to override the per-request 300s stamp, killing
    /// any stream with a >20s silent stretch. Config carries the streaming
    /// budgets; interactive requests keep the strict shared session.
    nonisolated static func makeStreamingSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = streamingRequestTimeout
        configuration.timeoutIntervalForResource = 3600
        return URLSession(configuration: configuration)
    }
```

…route the two `text/event-stream` call sites through it (grep `text/event-stream` in the file), and add a structural test pinning that the streaming path uses a session whose `configuration.timeoutIntervalForRequest == 300`. On a request-wins verdict: change NOTHING, record only.

- [ ] **Step 5: Commit** (verdict recording rides Task 5's OPEN_ITEMS commit; a conditional split-session change commits here with its structural test)

---

### Task 5: OPEN_ITEMS record, gate, PR

- [ ] **Step 1:** Update the #235 entry: header suffix `— **FIX BUILT 2026-08-03; 235-A/B/C green in suite; 235-D verdict recorded; device bars 235-E/F owed to the next OTA**`; a dated built-note blockquote naming the tests, the F2 mechanism revision (trigger existed, was STARVED at the end of the #145 Part D chain — the fix is a move-to-front), and the 235-D verdict with elapsed time.
- [ ] **Step 2:** Run the gate (backgrounded): `nohup ./scripts/mac/lane-gate.sh > /tmp/t235-gate.log 2>&1 &` — require `GATE: PASS` and the Swift Testing count moved by exactly the new-test total (tally at execution; expected 1559 + 6 = 1565 if Task 2's pin lands as one test).
- [ ] **Step 3:** Commit OPEN_ITEMS; push; open the PR:

```bash
gh pr create --title "#235: dead streams reconcile — empty-close arms recovery, unstarved foreground single-shot, tail placement (OPEN_ITEMS numbering)" --body "$(cat <<'EOF'
Fixes OPEN_ITEMS #235 (CRITICAL): a remote turn whose SSE stream died could lose its answer forever while the server store held it. Three routed end-states into the existing (correct) reconcile machinery: an empty clean-close now arms `.interrupted` recovery instead of delivering an empty bubble; `reconcilePendingRuns()` moves to the FRONT of the activation chain (the trigger existed but was starved behind the #145 Part D network ladder under rapid app-switching) plus a chat-appear single-shot; recovered replies displaced by later exchanges land at the transcript tail with a marker naming their prompt (Owen's placement rule, #180-stamped). The 20-vs-300 idle-timeout precedence was measured (verdict in the entry); the split-session change lands only on a config-wins verdict.

Spec: docs/superpowers/specs/2026-08-03-235-stream-loss-reconcile-design.md (approved). TDD, RED watched. Bars 235-A/B/C green in suite; 235-D verdict recorded. **Device bars NOT claimed:** 235-E (Owen's reproduction: long turn → background → return → answer appears at the tail) and 235-F (displaced recovery shows the marker) ride the next OTA.

Owen routes the merge; the branch is stageable for OTA as-is.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Self-Review (completed at write time)

1. **Spec coverage:** F1 → Task 1; F2 (as revised: unstarve + appear) → Task 2; F3 → Task 3; experiment + conditional split → Task 4; bars/entry/gate/PR → Task 5. Spec's "budget expiry keeps pendingRun" is pinned in Task 2's test (the code appears to already keep it — the test is the pin either way).
2. **Placeholders:** Task 2 Step 1 is deliberately a contract-skeleton adapted to the file's real fixtures at execution — the assertions and harness knobs are stated concretely; everything else is full code.
3. **Type consistency:** `cleanCloseArmsRecovery(runStarted:effectiveContent:)`, `placingRecoveredReply(_:prompt:in:)`, `Message.recoveredForPrompt`, `makeStreamingSession()` consistent across tasks.
