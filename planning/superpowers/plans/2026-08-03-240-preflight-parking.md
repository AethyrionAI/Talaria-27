# #240 Pre-`run.started` Parking Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A stream that dies after the server accepted the run (HTTP 2xx) but before `run.started` arms recovery (`.interrupted`) instead of parking the turn as queued, and the outbox drain adopts (drops) any queued turn the server already holds — killing the visible dupe and the armed auto-resend.

**Architecture:** Two independent guards per the approved spec (`planning/superpowers/specs/2026-08-03-240-pre-runstarted-parking-design.md`). Fix 1 is a `responseReceived` flag inside `SessionsHermesClient.streamTurn` that widens the catch branch's recovery condition. Fix 2 is a one-fetch adoption guard at the top of `ChatStore.drainComposeOutboxIfPossible()` backed by a pure static predicate. No UI change, no settings, no migration; `ComposeOutboxState` untouched.

**Tech Stack:** Swift / SwiftUI app, swift-testing (`@Test`/`#expect`) in `TalariaTests`, URLProtocol SSE stubs, Xcode-beta4 toolchain.

## Global Constraints

- Every `xcodebuild` invocation needs `DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer`.
- **`xcodegen generate` is mandatory after adding the new test file** (explicit source listings).
- Pinned simulator UDID: `47F68496-24F9-45D9-93D3-1C778DB6B557`.
- Suite counter discipline: the swift-testing counter currently reads **“Test run with 1548 tests.”** This plan adds **7** tests → the verification run must report **1555**. If the counter does not move, the build is stale — purge `<derived-data>/Build/Intermediates.noindex` and run plain `test` (resolve the DerivedData hash from `info.plist`, never from memory).
- TDD with **watched RED**: run each new test and see it fail for the expected reason before implementing.
- Bars 240-A/240-B are already pre-registered in the OPEN_ITEMS #240 entry — a missed bar is a falsification, not a redefinition. 240-C (the parked Steam row on Owen's phone draining without a second answer) is device-side and Owen's to observe post-OTA.
- **THE GATE** (`scripts/mac/lane-gate.sh` — Debug suite + XCUITest + Release build) must pass before the PR. Run it backgrounded and poll; never arm a waiter whose marker can't occur.
- Branch: `claude/t27-240-preflight-parking` off current `main`.
- Long builds exceed the 4-min tool cap — background (`nohup … &`) and poll the log.

---

### Task 1: Fix 1 — `responseReceived` guard (SessionsHermesClient)

**Files:**
- Modify: `Talaria/Services/Live/SessionsHermesClient.swift` (~line 207 locals; ~line 240 after the 2xx guard; ~lines 447–457 catch branch)
- Create: `TalariaTests/StreamLossClassificationTests.swift`
- Modify: `project.yml` is untouched, but **run `xcodegen generate`** so the new test file joins the target.

**Interfaces:**
- Consumes: `SessionsHermesClient(baseURLProvider:apiKeyProvider:journal:transplanter:session:)`, `sendStreaming(message:attachments:clientMessageID:) -> AsyncStream<StreamingUpdate>`, `StreamingUpdate.interrupted(sessionId: String, runId: String?)` / `.unreachable(String)` / `.failed(String)` — all existing.
- Produces: no new public surface. The behavior change: catch branch yields `.interrupted` whenever `runStarted || responseReceived`.

- [ ] **Step 1: Create branch**

```bash
cd /Users/owenjones/Documents/Claude/Talaria-27 && git checkout -b claude/t27-240-preflight-parking
```

- [ ] **Step 2: Write the failing test file**

Create `TalariaTests/StreamLossClassificationTests.swift`. The stub follows `ReasoningChannelTests.SSEStubProtocol`'s idiom (class-global handler, `.serialized` suite) with one addition: it can fail the load *after* delivering the response + a partial body — the backgrounding-teardown shape.

```swift
import Foundation
import Testing
@testable import Talaria

/// #240: classification of a stream that dies in the accepted-but-pre-
/// `run.started` window. A 2xx on the chat/stream POST proves the turn
/// reached the API; the teardown error that follows (fast backgrounding
/// kills the SSE with an unreachable-family URLError) must arm RECOVERY
/// (`.interrupted`), never the offline compose outbox (`.unreachable`) —
/// parking a delivered turn is a visible dupe plus an armed auto-resend.
@Suite(.serialized)
struct StreamLossClassificationTests {

    /// SSE stub that can fail BEFORE the response (`response` throws) or
    /// AFTER delivering the response + a partial body (`failAfterBody`
    /// returns an error for the request).
    private final class DroppingSSEProtocol: URLProtocol, @unchecked Sendable {
        struct Script {
            let response: @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
            let failAfterBody: @Sendable (URLRequest) -> Error?
        }
        nonisolated(unsafe) static var script: Script?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let script = Self.script else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            do {
                let (response, data) = try script.response(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                if let error = script.failAfterBody(request) {
                    client?.urlProtocol(self, didFailWithError: error)
                } else {
                    client?.urlProtocolDidFinishLoading(self)
                }
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }

    /// Runs one streamed turn against the scripted transport and returns the
    /// classification-relevant updates.
    @MainActor
    private func collectUpdates() async -> (
        interrupted: [(sessionId: String, runId: String?)],
        sawUnreachable: Bool,
        sawFailed: Bool
    ) {
        let suiteName = "stream-loss-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DroppingSSEProtocol.self]
        let session = URLSession(configuration: configuration)

        let client = SessionsHermesClient(
            baseURLProvider: { "http://hermes.test" },
            apiKeyProvider: { "test-key" },
            journal: ConversationJournalStore(persistence: persistence),
            transplanter: ContextTransplanter(intelligence: LocalIntelligenceService()),
            session: session
        )

        var interrupted: [(sessionId: String, runId: String?)] = []
        var sawUnreachable = false
        var sawFailed = false
        for await update in client.sendStreaming(message: "Q", attachments: [], clientMessageID: UUID()) {
            switch update {
            case let .interrupted(sessionId, runId):
                interrupted.append((sessionId: sessionId, runId: runId))
            case .unreachable:
                sawUnreachable = true
            case .failed:
                sawFailed = true
            default:
                break
            }
        }
        return (interrupted, sawUnreachable, sawFailed)
    }

    /// 240-A, the hole: 2xx received, stream dies before `run.started` with
    /// an unreachable-family teardown error. Must arm recovery, not park.
    @Test @MainActor
    func acceptedButPreRunStartedDropArmsRecoveryNotParking() async {
        DroppingSSEProtocol.script = .init(
            response: { request in
                guard let url = request.url else { throw URLError(.badURL) }
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                switch url.path {
                case "/api/sessions":
                    return (response, Data(#"{"session":{"id":"sess-1"}}"#.utf8))
                case "/api/sessions/sess-1/chat/stream":
                    // Partial body: the server spoke, but run.started never arrived.
                    return (response, Data("event: message.started\ndata: {}\n\n".utf8))
                default:
                    throw URLError(.badURL)
                }
            },
            failAfterBody: { request in
                request.url?.path == "/api/sessions/sess-1/chat/stream"
                    ? URLError(.notConnectedToInternet) : nil
            }
        )
        defer { DroppingSSEProtocol.script = nil }

        let outcome = await collectUpdates()

        #expect(outcome.interrupted.count == 1)
        #expect(outcome.interrupted.first?.sessionId == "sess-1")
        #expect(outcome.interrupted.first?.runId == nil)
        #expect(!outcome.sawUnreachable)
    }

    /// The honest case keeps working: the SAME error before any response on
    /// the chat request means the turn never reached the API — still parks.
    @Test @MainActor
    func preResponseDropStillParksAsUnreachable() async {
        DroppingSSEProtocol.script = .init(
            response: { request in
                guard let url = request.url else { throw URLError(.badURL) }
                if url.path == "/api/sessions" {
                    let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    return (response, Data(#"{"session":{"id":"sess-1"}}"#.utf8))
                }
                throw URLError(.notConnectedToInternet)
            },
            failAfterBody: { _ in nil }
        )
        defer { DroppingSSEProtocol.script = nil }

        let outcome = await collectUpdates()

        #expect(outcome.interrupted.isEmpty)
        #expect(outcome.sawUnreachable)
        #expect(!outcome.sawFailed)
    }
}
```

- [ ] **Step 3: Regenerate the project and run the new suite — watch it fail**

```bash
cd /Users/owenjones/Documents/Claude/Talaria-27 && xcodegen generate
```

```bash
cd /Users/owenjones/Documents/Claude/Talaria-27 && DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer xcodebuild -project Talaria.xcodeproj -scheme Talaria -destination 'platform=iOS Simulator,id=47F68496-24F9-45D9-93D3-1C778DB6B557' -only-testing:TalariaTests/StreamLossClassificationTests test 2>&1 | tail -30
```

Expected: `acceptedButPreRunStartedDropArmsRecoveryNotParking` **FAILS** (`interrupted.count == 1` is false and `sawUnreachable` is true — today the drop parks). `preResponseDropStillParksAsUnreachable` **PASSES** (it is the regression guard for the honest case). If the first test fails for any *other* reason (e.g. transport plumbing), fix the fixture before touching production code.

- [ ] **Step 4: Implement the guard**

In `Talaria/Services/Live/SessionsHermesClient.swift`:

(a) Beside the locals (~line 207):

```swift
        var capturedSessionId = ""
        var runId: String?
        var runStarted = false
        // #240: 2xx on the chat/stream POST proves the turn REACHED the API,
        // even when the stream dies before run.started is parsed.
        var responseReceived = false
```

(b) Immediately after the 2xx guard block closes (currently `connectionStatus = .connected`, ~line 240):

```swift
            responseReceived = true
            connectionStatus = .connected
```

(c) The catch branch condition (~line 447) — replace `if runStarted {` and its comment:

```swift
            if runStarted || responseReceived {
                // Run committed (run.started seen) or at least accepted (2xx
                // seen) server-side — a dropped stream (e.g. the app
                // suspended on lock) is recoverable, not a failure, and
                // NEVER a re-queue: parking an accepted turn re-sends it and
                // Hermes answers twice (#240). runId is nil before
                // run.started; reconcile resolves positionally.
                continuation.yield(.interrupted(sessionId: capturedSessionId, runId: runId))
            } else if Self.isUnreachableError(error) {
```

- [ ] **Step 5: Run the suite again — both tests pass**

Same command as Step 3. Expected: 2/2 pass.

- [ ] **Step 6: Commit**

```bash
cd /Users/owenjones/Documents/Claude/Talaria-27 && git add TalariaTests/StreamLossClassificationTests.swift Talaria/Services/Live/SessionsHermesClient.swift Talaria.xcodeproj && git commit -m "#240 fix 1: responseReceived guard — accepted-but-pre-run.started drop arms recovery, never parks

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Fix 2 — drain-time adoption guard (ChatStore)

**Files:**
- Modify: `Talaria/Stores/ChatStore.swift` (`drainComposeOutboxIfPossible()` ~line 1370; new static predicate beside it)
- Test: `TalariaTests/ContinuityFabricTests.swift` (extend the private `ScriptedClient` ~line 198; new tests after `drainDropsTurnThatDuplicatesAPendingRow` ~line 398)

**Interfaces:**
- Consumes: `hermesClient.reconcileFromServer() async -> Conversation?` (protocol requirement; `ScriptedClient` currently inherits the `nil` default from the protocol extension), `ComposeOutboxState.PendingTurn` (`id: UUID`, `text: String`, `composedAt: Date` — memberwise init), `Message(sender:content:timestamp:status:)` (`timestamp` defaults `.now`), `persistence.saveConversationCache(_:)`, `chatLog.notice(...)`.
- Produces: `nonisolated static func historyAdoptsQueuedTurn(_ turn: ComposeOutboxState.PendingTurn, serverMessages: [Message]) -> Bool` on `ChatStore` (used by the drain; unit-tested directly).

- [ ] **Step 1: Extend `ScriptedClient` with scriptable history**

In `TalariaTests/ContinuityFabricTests.swift`, inside `ScriptedClient` (after `var scripts`):

```swift
        /// #240: scripted server history for the drain-time adoption guard.
        /// nil = fetch failed / no server-backed session — drain as before.
        var reconcileConversation: Conversation?
```

and after `clearConversation()`:

```swift
        func reconcileFromServer() async -> Conversation? { reconcileConversation }
```

- [ ] **Step 2: Write the failing tests**

Append after `drainDropsTurnThatDuplicatesAPendingRow` (still inside the same suite):

```swift
    // MARK: - #240: drain-time adoption guard

    @Test @MainActor
    func drainAdoptsTurnAlreadyDeliveredServerSide() async throws {
        let persistence = Self.makePersistence()
        let client = ScriptedClient()
        client.scripts = [[.unreachable("down")]]
        let store = ChatStore(hermesClient: client, persistence: persistence)

        await store.sendMessage("was the steam sale worth it")
        #expect(store.hasQueuedComposeTurns)

        // The server already holds the question: the park was the
        // accepted-but-pre-run.started misclassification (#240) — the turn
        // WAS delivered; only the client's stream died.
        var serverConvo = Conversation(title: Conversation.defaultTitle)
        serverConvo.messages = [
            Message(sender: .user, content: "was the steam sale worth it", status: .delivered),
            Message(sender: .hermes, content: "Yes — 60% off.", status: .delivered),
        ]
        client.reconcileConversation = serverConvo

        await store.drainComposeOutboxIfPossible()

        // Adopted, not re-sent: the park-time send stays the only send.
        #expect(client.sentMessages == ["was the steam sale worth it"])
        #expect(!store.hasQueuedComposeTurns)
        #expect(persistence.loadComposeOutboxState().isEmpty)
        #expect(store.conversation?.messages.contains(where: { $0.status == .queued }) == false)
    }

    @Test @MainActor
    func drainStillResendsTurnAbsentFromServerHistory() async throws {
        let persistence = Self.makePersistence()
        let client = ScriptedClient()
        client.scripts = [
            [.unreachable("down")],
            [.finished(Message(sender: .hermes, content: "delivered at last", status: .delivered), nil, nil)],
        ]
        let store = ChatStore(hermesClient: client, persistence: persistence)

        await store.sendMessage("never made it")

        var serverConvo = Conversation(title: Conversation.defaultTitle)
        serverConvo.messages = [
            Message(sender: .user, content: "some other question", status: .delivered),
        ]
        client.reconcileConversation = serverConvo

        await store.drainComposeOutboxIfPossible()

        #expect(client.sentMessages == ["never made it", "never made it"])
        #expect(!store.hasQueuedComposeTurns)
    }

    @Test @MainActor
    func drainWithNilHistoryFetchDrainsAsToday() async throws {
        let persistence = Self.makePersistence()
        let client = ScriptedClient()
        client.scripts = [
            [.unreachable("down")],
            [.finished(Message(sender: .hermes, content: "delivered at last", status: .delivered), nil, nil)],
        ]
        let store = ChatStore(hermesClient: client, persistence: persistence)

        await store.sendMessage("offline drain")
        // reconcileConversation stays nil — the fetch "failed"; the guard is
        // an optimization, not a gate (offline drains must still work).

        await store.drainComposeOutboxIfPossible()

        #expect(client.sentMessages == ["offline drain", "offline drain"])
        #expect(!store.hasQueuedComposeTurns)
    }

    @Test
    func adoptionPredicateMatchesTrimmedTextWithinClockSkewWindow() {
        let composedAt = Date(timeIntervalSince1970: 1_000_000)
        let turn = ComposeOutboxState.PendingTurn(id: UUID(), text: "  hello there \n", composedAt: composedAt)

        let match = Message(sender: .user, content: "hello there", timestamp: composedAt.addingTimeInterval(-59), status: .delivered)
        #expect(ChatStore.historyAdoptsQueuedTurn(turn, serverMessages: [match]))

        let tooOld = Message(sender: .user, content: "hello there", timestamp: composedAt.addingTimeInterval(-61), status: .delivered)
        #expect(!ChatStore.historyAdoptsQueuedTurn(turn, serverMessages: [tooOld]))
    }

    @Test
    func adoptionPredicateIgnoresNonUserAndDifferentText() {
        let composedAt = Date.now
        let turn = ComposeOutboxState.PendingTurn(id: UUID(), text: "hello", composedAt: composedAt)

        let hermesEcho = Message(sender: .hermes, content: "hello", timestamp: composedAt, status: .delivered)
        let different = Message(sender: .user, content: "hello?", timestamp: composedAt, status: .delivered)
        #expect(!ChatStore.historyAdoptsQueuedTurn(turn, serverMessages: [hermesEcho, different]))
    }
```

- [ ] **Step 3: Run the suite — watch the RED**

```bash
cd /Users/owenjones/Documents/Claude/Talaria-27 && DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer xcodebuild -project Talaria.xcodeproj -scheme Talaria -destination 'platform=iOS Simulator,id=47F68496-24F9-45D9-93D3-1C778DB6B557' -only-testing:TalariaTests/ContinuityFabricTests test 2>&1 | tail -30
```

Expected: **compile failure first** — `historyAdoptsQueuedTurn` does not exist yet. That is the predicate tests' RED. To watch the behavioral RED too, the compile error must be cleared by the predicate alone, so implement Step 4(a) only, re-run, and expect `drainAdoptsTurnAlreadyDeliveredServerSide` to **FAIL** on `sentMessages == [...]` (it re-sends: count 2) while the other new tests pass. Then proceed to 4(b).

- [ ] **Step 4: Implement predicate + drain integration**

(a) In `Talaria/Stores/ChatStore.swift`, directly above `drainComposeOutboxIfPossible()`:

```swift
    /// #240: a queued turn whose text the server ALREADY holds as a user
    /// message (at/after `composedAt` − 60s clock-skew slack) was delivered —
    /// the park was a misclassification of the accepted-but-pre-`run.started`
    /// window, and re-sending it makes Hermes answer the question twice.
    nonisolated static func historyAdoptsQueuedTurn(
        _ turn: ComposeOutboxState.PendingTurn,
        serverMessages: [Message]
    ) -> Bool {
        let text = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        return serverMessages.contains { message in
            message.sender == .user
                && message.timestamp >= turn.composedAt.addingTimeInterval(-60)
                && message.content.trimmingCharacters(in: .whitespacesAndNewlines) == text
        }
    }
```

(b) In `drainComposeOutboxIfPossible()`: after the `defer` line, fetch once; inside the loop, add the adoption branch after the queued-row removal and before `sendMessage`:

```swift
        isDrainingComposeOutbox = true
        defer { isDrainingComposeOutbox = false }

        // #240: one history fetch per drain. A queued turn the server already
        // holds was DELIVERED (pre-`run.started` parking) — drop the outbox
        // copy instead of making Hermes answer it twice. A nil fetch
        // (offline, or no server-backed session) drains exactly as before:
        // the guard is an optimization, not a gate.
        let serverMessages = await hermesClient.reconcileFromServer()?.messages

        while let turn = composeOutbox.pendingTurns.first {
            composeOutbox.remove(id: turn.id)
            persistComposeOutbox()
            if var conv = conversation {
                conv.messages.removeAll { $0.id == turn.id || $0.clientMessageID == turn.id }
                conversation = conv
            }
            if let serverMessages, Self.historyAdoptsQueuedTurn(turn, serverMessages: serverMessages) {
                // The transcript already carries the server's copy (the #235
                // reconcile adopted the server view); the queued row was
                // removed above — persist that removal, since no send
                // pipeline follows to do it.
                chatLog.notice("compose outbox: turn already delivered server-side — adopted, not re-sent (#240)")
                if let conversation { persistence.saveConversationCache(conversation) }
                continue
            }
            let dispatched = await sendMessage(turn.text)
```

(the rest of the loop is unchanged)

- [ ] **Step 5: Run the suite — all green**

Same command as Step 3. Expected: all `ContinuityFabricTests` pass, including the four pre-existing outbox tests (they exercise the nil-fetch path via the protocol default until Step 1's override, and the explicit nil script after it — behavior identical).

- [ ] **Step 6: Commit**

```bash
cd /Users/owenjones/Documents/Claude/Talaria-27 && git add Talaria/Stores/ChatStore.swift TalariaTests/ContinuityFabricTests.swift && git commit -m "#240 fix 2: drain-time adoption guard — queued turns the server already holds are dropped, not re-sent

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Records, gate, PR

**Files:**
- Modify: `OPEN_ITEMS.md` (#240 entry: bars record + build note)
- No code changes.

**Interfaces:**
- Consumes: Tasks 1–2 committed on `claude/t27-240-preflight-parking`.
- Produces: gate-verified branch + open PR; entry updated with observed counts.

- [ ] **Step 1: Full suite count check (pre-gate)**

```bash
cd /Users/owenjones/Documents/Claude/Talaria-27 && DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer nohup xcodebuild -project Talaria.xcodeproj -scheme Talaria -destination 'platform=iOS Simulator,id=47F68496-24F9-45D9-93D3-1C778DB6B557' test > /private/tmp/claude-501/-Users-owenjones-Documents-Claude-Talaria-27/22e57a75-8a46-4c55-bea2-395a07d0e604/scratchpad/240-suite.log 2>&1 &
```

Poll the log; require the swift-testing line to read **“Test run with 1555 tests”** (1548 + 7) and 0 failures. If it still says 1548, the test binary is stale — purge `Intermediates.noindex` for THIS worktree's DerivedData (resolve hash via `plutil -extract WorkspacePath raw ~/Library/Developer/Xcode/DerivedData/Talaria-*/info.plist`) and re-run.

- [ ] **Step 2: Update the OPEN_ITEMS #240 entry**

In the entry header, replace `BUILD STARTED post-compaction same night (Owen: "lets continue")` with `BUILT same night — 240-A/B in suite; gate + PR pending` (then update again after the gate). In the body, append a dated block recording: fix 1 + fix 2 landed (commit ids), bars 240-A (test names in `StreamLossClassificationTests`) and 240-B (test names in `ContinuityFabricTests`) MET with the observed 1555 counter, 240-C still owed to Owen's device post-OTA (the armed Steam row draining silently).

- [ ] **Step 3: Run THE GATE (backgrounded, polled)**

```bash
cd /Users/owenjones/Documents/Claude/Talaria-27 && DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer nohup ./scripts/mac/lane-gate.sh > /private/tmp/claude-501/-Users-owenjones-Documents-Claude-Talaria-27/22e57a75-8a46-4c55-bea2-395a07d0e604/scratchpad/240-gate.log 2>&1 &
```

Poll until it reports its POSITIVE success markers for Debug suite, XCUITest, and Release build. Any failure: stop, systematic-debugging, no PR.

- [ ] **Step 4: Commit records, push, open PR**

```bash
cd /Users/owenjones/Documents/Claude/Talaria-27 && git add OPEN_ITEMS.md && git commit -m "OPEN_ITEMS #240: bars 240-A/B met in suite (1555), gate green

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>" && git push -u origin claude/t27-240-preflight-parking
```

```bash
cd /Users/owenjones/Documents/Claude/Talaria-27 && gh pr create --title "#240: pre-run.started parking fix — responseReceived guard + drain-time adoption" --body "$(cat <<'EOF'
## Summary
- Fix 1: `responseReceived` flag in `SessionsHermesClient.streamTurn` — a stream that dies after the 2xx but before `run.started` now arms recovery (`.interrupted`, nil runId) instead of parking the turn as queued (the dupe + armed auto-resend from 238-D trial 2).
- Fix 2: drain-time adoption guard in `ChatStore.drainComposeOutboxIfPossible()` — one history fetch per drain; a queued turn the server already holds is dropped with a log line, never re-sent. Heals rows parked before the fix, including the live one.

## Test plan
- 240-A: `StreamLossClassificationTests` (2 tests, watched RED) — accepted-but-pre-run.started drop yields `.interrupted(sess, nil)`, pre-response drop still yields `.unreachable`.
- 240-B: `ContinuityFabricTests` (+5 tests, watched RED) — adoption drop, absent-from-history re-send, nil-fetch drains as today, predicate window/trim/sender edges.
- Suite: 1555 swift-testing tests green (1548 + 7). Gate: Debug suite + XCUITest + Release build all passed.
- 240-C (device): owed post-OTA — the parked Steam row on Owen's phone drains without a second answer.

Spec: planning/superpowers/specs/2026-08-03-240-pre-runstarted-parking-design.md (approved)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 5: Ping Owen** — PR link + the 240-C instruction (after merge + OTA install, just open the app on good network and confirm the Steam question is NOT answered a second time). Owen routes the merge.
