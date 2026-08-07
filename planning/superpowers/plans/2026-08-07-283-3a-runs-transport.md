# Phase 3 Slice 3A — Runs Transport Parity Implementation Plan (#283)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remote turns can ride `POST /v1/runs` + `GET /v1/runs/{id}/events` (SSE) + `GET /v1/runs/{id}` (status-poll recovery) + `POST /v1/runs/{id}/stop` (real stop), behind a Developer switch, with the sessions path intact and default.

**Architecture:** The runs path is a second turn transport INSIDE `SessionsHermesClient` (new extension file), not a second client — everything except the turn transport (session lifecycle, history reads, openSession, model catalog, reconcile fetch) deliberately stays on the sessions plane per the migration plan §2.1. A `useRunsTransportProvider` closure (armed from `UserSettings.useRunsTransport`) selects the path per turn. Decoded output is the SAME `StreamingUpdate` stream, so `ChatStore` needs zero changes in 3A.

**Tech Stack:** Swift 6 / SwiftUI, Swift Testing (`@Test`/`#expect`), URLProtocol stubs, XcodeGen, Xcode-beta4.

**Parent docs:** `design/PHASE3-RUNS-MIGRATION-PLAN-2026-08-07.md` (design §2, bars §3), `OPEN_ITEMS.md` #283 (bars), research report `planning/superpowers/research/251-phase3-gap/I-3a0-persistence-attachment-probe.md` (the 3A-0 wire evidence this plan is built on).

## Global Constraints

- `DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer` in every build/test shell.
- `xcodegen generate` after adding/removing ANY Swift file (explicit source listings).
- Simulator: pin by UDID `47F68496-24F9-45D9-93D3-1C778DB6B557` (iPhone 17 Pro Max, iOS 27.0). The `CC-*` device names are GONE — never resolve by name grep.
- `-only-testing` selectors are SUITE-LEVEL only (`TalariaTests/<StructName>`); method-level silently runs 0 tests under `TEST SUCCEEDED`. Always read the executed count before the success marker. Plain `test`, never `test-without-building`. Never pass `CODE_SIGNING_ALLOWED=NO` on test runs.
- Swift Testing only in `TalariaTests/` (flat directory, no subfolders). Suites touching a static stub handler are `@Suite(.serialized)`. Per-test persistence isolation via `UserDefaults(suiteName: "<prefix>-\(UUID().uuidString)")`.
- SSE stub fixtures: pad ≥512 B with a leading SSE comment; a late error must be dispatched ~0.1 s AFTER the body (a synchronous fail reads as pre-response); runs frames are `data: {json}\n\n` with NO `event:` lines — single-line JSON only.
- Four-space indent; `PascalCase` types / `lowerCamelCase` members; no force-unwraps on network code.
- Real data only: no fabricated artifact content (bar 3A-D), no fabricated serving-model claims (runs `run.completed` carries no runtime block — `.modelResolved` simply never fires on this path; UI's existing nil-handling shows honest absence).
- Branch: `claude/t27-283-3a-runs-transport` in an isolated worktree. Commit per task. `scripts/mac/lane-gate.sh` (backgrounded, poll the log) before the PR.
- Single-file test run template:
  ```bash
  cd <worktree> && DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer \
  xcodebuild -project Talaria.xcodeproj -scheme Talaria \
    -destination 'platform=iOS Simulator,id=47F68496-24F9-45D9-93D3-1C778DB6B557' \
    -only-testing:TalariaTests/<SuiteName> test 2>&1 | tail -30
  ```

## Wire contract (from the live install @ `01a1037d1` + the 3A-0 probe — treat as fixed)

- `POST /v1/runs` body: `input` (plain string, OR message array `[{"role":"user","content":[<OpenAI-style parts>]}]` for attachment turns — the parts-array-only shape 400s), `session_id`, `conversation_history` (array of `{"role","content"}` — the handler coerces both to `str`, so prose strings only), optional `model`/`provider`. Response `202 {"run_id":"run_<hex>","status":"started"}`.
- `GET /v1/runs/{id}/events`: SSE; every frame is one line `data: {"event":"<name>",...}` (event name INSIDE the JSON — there are no `event:` lines on this stream, unlike the sessions plane). Keepalive = `: keepalive` comment every 30 s; close = `: stream closed` then socket close. Subscribing has a ~1 s registration race — the server retries 20×0.05 s then 404s `run_not_found`.
- Event payloads (all carry `run_id`, `timestamp`): `message.delta{delta}` · `tool.started{tool,preview}` (NO args — N1) · `tool.completed{tool,duration,error}` · `reasoning.available{text}` · `subagent.start/complete{...}` · `approval.request{command,choices,...}` (3B's business — ignore in 3A) · `run.completed{output,usage{input_tokens,output_tokens,total_tokens}}` · `run.failed{error}` · `run.cancelled`.
- `GET /v1/runs/{id}`: `{status: queued|running|waiting_for_approval|completed|failed|cancelled, output, usage, last_event, error, session_id, model}` — retained 3600 s. `model` here is the REQUESTED model, not the resolved runtime; never present it as "served by".
- `POST /v1/runs/{id}/stop`: real hard interrupt; 404 `run_not_found` on unknown id.
- Runs with `session_id` WRITE both turn rows into SessionDB (`/messages` stays truthful) but READ nothing — history must ride the request (3A-0/N4).

---

### Task 1: `RunsTurnBody` — the request encoder

**Files:**
- Create: `Talaria/Services/Live/SessionsHermesClient+RunsTransport.swift`
- Create: `TalariaTests/RunsTurnBodyEncodingTests.swift`
- Modify: `project.yml` — none needed (paths are directory-listed); run `xcodegen generate` after creating files.

**Interfaces:**
- Consumes: `SessionsHermesClient.ChatTurnBody.ContentPart` (internal, `SessionsHermesClient.swift:1754`), `AttachmentInlining.assemble(message:attachments:)` (`Talaria/Services/Support/AttachmentInlining.swift`), `ModelSelection` (`GatewayModelCatalog.swift:86`), `PendingAttachment`.
- Produces: `SessionsHermesClient.RunsTurnBody` with `static func make(message:attachments:sessionID:history:selection:) -> RunsTurnBody` and `struct HistoryEntry: Encodable { let role: String; let content: String }` — Tasks 4–6 build bodies exclusively through `make`.

- [ ] **Step 1: Write the failing tests** (`RunsTurnBodyEncodingTests.swift`, plain struct suite, mirror `ChatTurnBodyEncodingTests.swift`):

```swift
import Foundation
import Testing
@testable import Talaria

struct RunsTurnBodyEncodingTests {
    private func json(_ body: SessionsHermesClient.RunsTurnBody) throws -> [String: Any] {
        let data = try JSONEncoder().encode(body)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func textTurnEncodesPlainStringInputWithSessionAndHistory() throws {
        let body = SessionsHermesClient.RunsTurnBody.make(
            message: "hello",
            attachments: [],
            sessionID: "sess-1",
            history: [.init(role: "user", content: "KUMQUAT-N4A"),
                      .init(role: "assistant", content: "noted")],
            selection: nil
        )
        let obj = try json(body)
        #expect(obj["input"] as? String == "hello")            // plain string — NOT a parts array
        #expect(obj["session_id"] as? String == "sess-1")
        let history = try #require(obj["conversation_history"] as? [[String: Any]])
        #expect(history.count == 2)
        #expect(history[0]["content"] as? String == "KUMQUAT-N4A")
        #expect(obj["provider"] == nil)
        #expect(obj["model"] == nil)
    }

    @Test func selectionAddsProviderAndModel() throws {
        let body = SessionsHermesClient.RunsTurnBody.make(
            message: "hi", attachments: [], sessionID: "s", history: [],
            selection: ModelSelection(provider: "openrouter", modelID: "deepseek-v4")
        )
        let obj = try json(body)
        #expect(obj["provider"] as? String == "openrouter")
        #expect(obj["model"] as? String == "deepseek-v4")
        // Deliberately NO require_model_lock on the runs plane — the lock contract
        // is unverified there (#283 records the delta). Assert absence so a future
        // "helpful" addition trips a test instead of a 400-risk surprise.
        #expect(obj["require_model_lock"] == nil)
    }

    @Test func attachmentTurnWrapsPartsAsSingleUserMessage() throws {
        // The 3A-0 probe proved the bare parts array 400s and this wrap works.
        let png = PendingAttachment.stubTransmittableImage()  // see Step 3
        let body = SessionsHermesClient.RunsTurnBody.make(
            message: "what color?", attachments: [png],
            sessionID: "s", history: [], selection: nil
        )
        let obj = try json(body)
        let input = try #require(obj["input"] as? [[String: Any]], "attachment input must be a MESSAGE array")
        #expect(input.count == 1)
        #expect(input[0]["role"] as? String == "user")
        let parts = try #require(input[0]["content"] as? [[String: Any]])
        #expect(parts.contains { $0["type"] as? String == "text" })
        #expect(parts.contains { $0["type"] as? String == "image_url" })
    }
}
```

If `PendingAttachment` has no existing test factory for a transmittable image, add a minimal `static func stubTransmittableImage() -> PendingAttachment` under `#if DEBUG` in the test file itself (NOT production code) by building whatever `AttachmentInlining.assemble` needs to emit one `.imageDataURL` part — copy the construction used by `ChatTurnBodyEncodingTests.swift` if one exists there; otherwise construct via the type's own initializers with a tiny `data:image/png;base64,...` payload.

- [ ] **Step 2: `xcodegen generate`, run, verify FAIL** (type does not exist):
  `-only-testing:TalariaTests/RunsTurnBodyEncodingTests` → expect compile failure referencing `RunsTurnBody`.

- [ ] **Step 3: Implement** in `SessionsHermesClient+RunsTransport.swift`:

```swift
import Foundation

// Phase 3 slice 3A (#283): the runs-plane turn transport. Wire contract and
// probe evidence: design/PHASE3-RUNS-MIGRATION-PLAN-2026-08-07.md §2,
// planning/superpowers/research/251-phase3-gap/I-3a0-persistence-attachment-probe.md.
extension SessionsHermesClient {
    struct RunsTurnBody: Encodable {
        struct HistoryEntry: Encodable {
            let role: String
            let content: String
        }

        enum RunsTurnInput: Encodable {
            case text(String)
            /// Attachment turns: the 3A-0 probe proved a bare parts array 400s
            /// on /v1/runs ("No user message found in input") while the
            /// single-user-message wrap reaches the agent with the image intact.
            case userParts([ChatTurnBody.ContentPart])

            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .text(let text):
                    try container.encode(text)
                case .userParts(let parts):
                    try container.encode([RunsInputMessage(parts: parts)])
                }
            }
        }

        private struct RunsInputMessage: Encodable {
            let parts: [ChatTurnBody.ContentPart]
            private enum CodingKeys: String, CodingKey { case role, content }
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode("user", forKey: .role)
                try container.encode(parts, forKey: .content)
            }
        }

        let input: RunsTurnInput
        let sessionID: String
        let conversationHistory: [HistoryEntry]
        let provider: String?
        let model: String?

        private enum CodingKeys: String, CodingKey {
            case input, provider, model
            case sessionID = "session_id"
            case conversationHistory = "conversation_history"
        }

        static func make(
            message: String,
            attachments: [PendingAttachment],
            sessionID: String,
            history: [HistoryEntry],
            selection: ModelSelection?
        ) -> RunsTurnBody {
            let assembly = AttachmentInlining.assemble(message: message, attachments: attachments)
            let input: RunsTurnInput
            if assembly.parts.isEmpty {
                input = .text(message)
            } else {
                input = .userParts(assembly.parts.map { part in
                    switch part {
                    case .text(let text): ChatTurnBody.ContentPart.text(text)
                    case .imageDataURL(let dataURL): ChatTurnBody.ContentPart.imageURL(dataURL: dataURL)
                    }
                })
            }
            return RunsTurnBody(
                input: input,
                sessionID: sessionID,
                conversationHistory: history,
                provider: selection?.provider,
                model: selection?.modelID
            )
        }
    }
}
```

Match `ChatTurnBody.make`'s handling of `assembly.notTransmittable` / `assembly.omittedForBudget` logging (copy the two `Self.logger.warning` loops verbatim; `ChatTurnBody`'s nested logger is `private static` — declare a same-shape `private static let logger` in the extension's file scope or reuse via a small shared helper, whichever compiles without widening).

- [ ] **Step 4: Run tests, verify PASS.** Confirm the executed count MOVED (3 new tests).
- [ ] **Step 5: Commit** — `feat(#283): RunsTurnBody — runs-plane request encoder (probe-proven message-array wrap for attachments)`

---

### Task 2: Runs frame parser — data-only SSE dialect

**Files:**
- Modify: `Talaria/Services/Live/SessionsHermesClient+RunsTransport.swift`
- Create: `TalariaTests/RunsFrameParserTests.swift`

**Interfaces:**
- Produces (all `nonisolated static` on `SessionsHermesClient`, pure, offline-testable):
  - `enum RunsEvent: Equatable { case messageDelta(String); case toolStarted(name: String, preview: String?); case toolCompleted(name: String, error: String?); case reasoning(String); case runCompleted(output: String, rawJSON: String); case runFailed(error: String); case runCancelled; case ignored(String) }`
  - `static func parseRunsFrame(_ jsonPayload: String) -> RunsEvent?` — input is the JSON after `data: `; returns `nil` for unparseable payloads, `.ignored(name)` for known-but-unused events (`approval.request`, `approval.responded`, `subagent.start`, `subagent.complete`).
- Consumes: `decodeRunUsage(_ data: String) -> TokenUsage?` (`SessionsHermesClient.swift:1507`) — **widen from `private` to internal** with the comment `// runs-path-visible (#283): shared by both planes' run.completed decode` (the #216 tag discipline, new tag). `runCompleted.rawJSON` carries the whole frame JSON so the caller can reuse `decodeRunUsage` unchanged.

**Load-bearing dialect note (write it as a comment on the parser):** the runs stream has NO `event:` lines — every frame is a single `data: {json}` line and `bytes.lines` swallows the blank separators. So the runs loop dispatches ON EVERY `data:` line immediately. Reusing the sessions parser (which flushes on the next `event:` line) would buffer forever.

- [ ] **Step 1: Write failing tests:**

```swift
import Foundation
import Testing
@testable import Talaria

struct RunsFrameParserTests {
    @Test func messageDeltaParses() {
        let e = SessionsHermesClient.parseRunsFrame(#"{"event":"message.delta","run_id":"r1","timestamp":1.0,"delta":"Hel"}"#)
        #expect(e == .messageDelta("Hel"))
    }

    @Test func toolStartedCarriesPreviewButNeverArgs() {
        let e = SessionsHermesClient.parseRunsFrame(#"{"event":"tool.started","run_id":"r1","timestamp":1.0,"tool":"write_file","preview":"O:\\Hermes\\out.txt"}"#)
        #expect(e == .toolStarted(name: "write_file", preview: #"O:\Hermes\out.txt"#))
    }

    @Test func runCompletedKeepsRawJSONForUsageDecode() throws {
        let raw = #"{"event":"run.completed","run_id":"r1","timestamp":2.0,"output":"KUMQUAT","usage":{"input_tokens":10,"output_tokens":2,"total_tokens":12}}"#
        let e = try #require(SessionsHermesClient.parseRunsFrame(raw))
        guard case let .runCompleted(output, rawJSON) = e else {
            Issue.record("expected runCompleted, got \(e)"); return
        }
        #expect(output == "KUMQUAT")
        let usage = SessionsHermesClient.decodeRunUsage(rawJSON)
        #expect(usage?.totalTokens == 12)
    }

    @Test func reasoningAvailableParses() {
        let e = SessionsHermesClient.parseRunsFrame(#"{"event":"reasoning.available","run_id":"r1","timestamp":1.5,"text":"thinking…"}"#)
        #expect(e == .reasoning("thinking…"))
    }

    @Test func failureAndCancelParse() {
        #expect(SessionsHermesClient.parseRunsFrame(#"{"event":"run.failed","run_id":"r1","timestamp":3.0,"error":"boom"}"#) == .runFailed(error: "boom"))
        #expect(SessionsHermesClient.parseRunsFrame(#"{"event":"run.cancelled","run_id":"r1","timestamp":3.0}"#) == .runCancelled)
    }

    @Test func approvalAndSubagentAreIgnoredNotDropped() {
        #expect(SessionsHermesClient.parseRunsFrame(#"{"event":"approval.request","run_id":"r1","command":"rm -rf /tmp/x","choices":["once"]}"#) == .ignored("approval.request"))
        #expect(SessionsHermesClient.parseRunsFrame(#"{"event":"subagent.start","run_id":"r1"}"#) == .ignored("subagent.start"))
    }

    @Test func garbageReturnsNil() {
        #expect(SessionsHermesClient.parseRunsFrame("not json") == nil)
        #expect(SessionsHermesClient.parseRunsFrame(#"{"no_event_key":true}"#) == nil)
    }
}
```

- [ ] **Step 2: Run, verify FAIL** (missing symbols).
- [ ] **Step 3: Implement** `RunsEvent` + `parseRunsFrame` using `JSONSerialization` (matching the client's existing `decodeJSONString` style — see `SessionsHermesClient.swift:1232`); `tool.completed` maps `error` via `payload["error"] as? String`.
- [ ] **Step 4: Run, verify PASS; count moved (7 new).**
- [ ] **Step 5: Commit** — `feat(#283): runs SSE frame parser — data-only dialect, no event: lines`

---

### Task 3: Developer switch — storage, UI, client seam

**Files:**
- Modify: `Talaria/Models/UserSettings.swift` — five edits, all required (hand-written `init(from:)`): property near `:396`, memberwise init param near `:436`, init body near `:466`, `CodingKeys` near `:498`, tolerant decode near `:538`. New member: `var useRunsTransport: Bool` default `false`, decode `?? false`.
- Modify: `Talaria/Features/Settings/DeveloperSettingsScreen.swift` — `flagsSection` (`:179-215`): new `flagRow("Runs Transport (Phase 3)", detail: "/v1/runs + status-poll recovery · #283", isOn: runsTransportBinding)` after the existing rows with the standard hairline divider (`:192-195`); binding under `// MARK: Bindings` (`:480`) mirroring `verboseLoggingBinding` (`:482`) — get/set `settingsStore.settings.useRunsTransport`, no side-effect hook needed (the client reads through a provider closure, next bullet).
- Modify: `Talaria/Services/Live/SessionsHermesClient.swift` — new stored property next to `modelSelection` (`:109`): `var useRunsTransportProvider: @MainActor () -> Bool = { false }` with a doc comment naming #283 and "sessions path stays default until 3A-F passes".
- Modify: `Talaria/Stores/AppContainer.swift` — arm it where `sessionsClient.modelSelection` is armed at launch (`:782`): `sessionsClient.useRunsTransportProvider = { [weak settingsStore] in settingsStore?.settings.useRunsTransport ?? false }` (match the exact capture idiom used by neighboring closures at `:607`; if `settingsStore` is non-optional there, capture it directly).
- Create: `TalariaTests/RunsTransportSwitchTests.swift`

**Interfaces:**
- Produces: `UserSettings.useRunsTransport: Bool` (default false); `SessionsHermesClient.useRunsTransportProvider`. Task 5's dispatch reads the provider.

- [ ] **Step 1: Failing test** — settings round-trip + tolerant decode (mirror an existing `UserSettings` decode test if present; else):

```swift
import Foundation
import Testing
@testable import Talaria

struct RunsTransportSwitchTests {
    @Test func defaultsToOffAndSurvivesRoundTrip() throws {
        var settings = UserSettings()
        #expect(settings.useRunsTransport == false)
        settings.useRunsTransport = true
        let decoded = try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.useRunsTransport == true)
    }

    @Test func legacyPayloadWithoutKeyDecodesOff() throws {
        let legacy = try JSONEncoder().encode(UserSettings())
        var obj = try #require(JSONSerialization.jsonObject(with: legacy) as? [String: Any])
        obj.removeValue(forKey: "useRunsTransport")
        let stripped = try JSONSerialization.data(withJSONObject: obj)
        let decoded = try JSONDecoder().decode(UserSettings.self, from: stripped)
        #expect(decoded.useRunsTransport == false)
    }
}
```

(If `UserSettings()` has no argless init, use `DemoData.sampleUserSettings` as the seed — see `SettingsStore.swift:44`.)

- [ ] **Step 2: Run, FAIL** (property missing). **Step 3: implement all five `UserSettings` edits + screen row + binding + client property + AppContainer arming.** **Step 4: run switch tests + the full `TalariaTests/DeveloperSettings`-adjacent suites if any reference `flagsSection`; PASS, count moved.** **Step 5: Commit** — `feat(#283): Developer switch for the runs transport (default OFF)`

---

### Task 4: `streamTurnViaRuns` — happy path + history pre-fetch

**Files:**
- Modify: `Talaria/Services/Live/SessionsHermesClient+RunsTransport.swift` (the turn driver)
- Modify: `Talaria/Services/Live/SessionsHermesClient.swift` — widen these `private` members to internal, each tagged `// runs-path-visible (#283)`: `makeRequest(path:method:body:accept:profileID:)` (`:1051`), `resolveEndpoint(profileID:)` (`:1162`), `ensureHopForTurn()` (`:932`), `fetchSessionConversation(_:profileID:)` (`:786`), `failureMessage(for:)` (`:1492`), `decodeRunUsage` (done in Task 2), plus the `PreparedHop` type if private. Widen NOTHING else.
- Create: `TalariaTests/RunsPlaneTransportTests.swift`

**Interfaces:**
- Consumes: Tasks 1–2 types; `stallGuardedLines` (`:228`, already internal-ish — verify, widen with tag if private); `StreamingUpdate` cases verbatim (`Talaria/Models/StreamingUpdate.swift:25-64`); `ToolCallEvent` (`StreamingUpdate.swift:7`); `TokenUsage`; `usageIndex?.record(...)` mirroring the sessions call at `:407-458`.
- Produces: `func streamTurnViaRuns(message:attachments:into:) async` (same shape as `streamTurn` at `:264`, minus `allowStaleHopRetry` — a stale-hop 404 on `POST /v1/runs`? The runs submit doesn't hit `/api/sessions/{id}/...` so the 404-rehop shape differs: a 404 on submit is a server error, surface as `.failed`); `func fetchRunsHistory(sessionId:profileID:) async throws -> [RunsTurnBody.HistoryEntry]`; `struct RunSubmitResponse: Decodable { let runID: String }` (key `run_id`); poll types come in Task 6.

**Turn driver flow (implement exactly; the sessions `streamTurn` at `:264-550` is the reference for yields and bookkeeping):**
1. `ensureHopForTurn()` → sessionId/profileID; yield `.contextPrimed` the way `streamTurn` does at `:281-283`. (The transplant priming turn inside hop preparation stays on the SESSIONS plane in 3A — it is hop setup, not the migrating turn transport. Note this in a comment.)
2. `fetchRunsHistory` = `fetchSessionConversation(sessionId, profileID:)` → map `conversation.messages` to `[HistoryEntry]`: `sender == .user → "user"`, `sender == .hermes → "assistant"`, drop rows with empty/whitespace `content`, drop the trailing entry if it equals the outgoing message (the just-sent optimistic row is ChatStore-side only, but be defensive). Server truth is current because runs WRITE the row (probe N4).
3. `postJSON` the `RunsTurnBody` to `/v1/runs` → `RunSubmitResponse`. Record `activeRunContext = (runID, profileID)` (property added in Task 7 — for now a local `let runID`).
4. Immediately GET `/v1/runs/{runID}/events` with `Accept: text/event-stream` via `makeRequest` + `session.bytes(for:)` — the server tolerates ~1 s of registration race; a 404 here goes to the Task 6 poll fallback (in this task: yield `.failed` placeholder path, replaced in Task 6 — no, to avoid a knowingly-wrong intermediate: structure the function so stream-subscribe failure calls `pollRunToTerminal` which Task 6 fills in; in THIS task implement `pollRunToTerminal` as a minimal single GET returning terminal-or-nil so the seam exists and is honest).
5. Line loop: `for try await line in Self.stallGuardedLines(bytes.lines, threshold: streamStallThreshold)`; skip `:` comments; for `data:` prefixed lines strip the prefix (and one optional leading space) and dispatch `parseRunsFrame` **immediately per line** (dialect comment from Task 2).
6. Dispatch mapping → yields (mirror the sessions `dispatchEvent` switch at `:330-464`):
   - `.messageDelta(d)` → `continuation.yield(.textDelta(d))`
   - `.reasoning(text)` → run through `Self.incrementalReasoningDelta(from: text, assembled: assembledReasoning)` (`:1273`) exactly as the sessions `_thinking` path does, yield `.reasoningDelta` when non-nil
   - `.toolStarted(name, preview)` → `.toolActivity(ToolCallEvent(name: name, phase: .started, detail: preview))` — **NO `.artifactProduced`, ever, on this path in 3A** (bar 3A-D: `args` don't exist here; honest absence)
   - `.toolCompleted(name, _)` → `.toolActivity(ToolCallEvent(name: name, phase: .completed, detail: nil))`
   - `.runCompleted(output, rawJSON)` → build the final `Message` the way `run.completed` does at `:407-458`: content = output, reasoning = assembledReasoning (non-empty), usage = `decodeRunUsage(rawJSON)`, `usageIndex?.record` mirror, then `.finished(message, usage, nil)`; set `finishedYielded = true`; `break` the loop. NO fetchable-attachment sweep from announced paths (there are no tool payloads carrying paths; `agentFilesRelativePaths(in: output)` on the prose IS still legitimate — run it, matching `:451-456`'s prose-sweep half only).
   - `.runFailed(error)` → `.failed(failureMessage-style text)`; `finishedYielded = true`; break.
   - `.runCancelled` → if the client itself initiated stop (Task 7 flag) end silently; else `.interrupted(sessionId:runId:)`; break.
   - `.ignored`, `nil` → continue.
7. Terminal bookkeeping: on loop exit without `finishedYielded` (clean close, stall throw, transport error) → Task 6's recovery. In this task: minimal — yield `.interrupted(sessionId: sessionId, runId: runID)` when a 2xx stream was opened, else classify via `isUnreachableError` exactly like `:532-550`. `continuation.finish()` in all exits.

- [ ] **Step 1: Write the e2e stub tests** — new suite, copy the canonical stub pieces per the conventions map: `@Suite(.serialized)`; private `RunsStubURLProtocol` (clone `DroppingSSEProtocol`'s two-closure `Script` from `StreamLossClassificationTests.swift:17-54`); `bodyString(_:)` clone from `TalariaPlatformLinkTests.swift:366-380`; fixture builder:

```swift
    private static func runsSSE(_ frames: [String]) -> String {
        let padding = ": " + String(repeating: "-", count: 600) + "\n\n"
        return padding + frames.map { "data: \($0)\n\n" }.joined() + ": stream closed\n\n"
    }
```

Client construction: the minimal 5-arg form (`ReasoningChannelTests.swift:398-404`) + `client.useRunsTransportProvider = { true }`. Stub routing handler (suffix-match idiom):
`POST /api/sessions` → `{"session":{"id":"sess-r"}}` · `GET /api/sessions/sess-r/messages` → a two-row fixture (user "KUMQUAT-N4A" / assistant "noted", the `StoredMessage` shape used by `ReasoningChannelTests`' `MessagesStubProtocol` at `:637-655`) · `POST /v1/runs` → `202 {"run_id":"run-r1","status":"started"}` · `GET /v1/runs/run-r1/events` → the SSE body · `GET /v1/runs/run-r1` → status JSON (Task 6's business; stub `{"status":"running"}` here).

Tests in this task:

```swift
    @Test func happyTurnDecodesToParitySequence() async throws {
        // frames: message.delta "Hel", "lo", tool.started/completed shell, reasoning, run.completed
        // collect updates from client.sendStreaming(message: "hi", attachments: [], clientMessageID: UUID())
        // assert, in order: .contextPrimed, .textDelta("Hel"), .textDelta("lo"),
        //   .toolActivity(started shell), .toolActivity(completed shell),
        //   .reasoningDelta("thinking…"), .finished(message, usage, nil)
        // assert message.content == "Hello answer", usage.totalTokens == 12   (3A-A)
        // assert exactly ONE .finished
    }

    @Test func historyRidesTheSubmitBody() async throws {
        // capture the /v1/runs POST via bodyString; decode JSON
        // assert conversation_history contains {"role":"user","content":"KUMQUAT-N4A"}
        // and {"role":"assistant","content":"noted"}  (3A-G unit arm — the marker shape)
        // assert request log order: GET /messages BEFORE POST /v1/runs
    }

    @Test func writeFileToolStartedProducesNoArtifact() async throws {
        // frames include tool.started {"tool":"write_file","preview":"O:\\x\\a.txt"} then run.completed
        // assert a .toolActivity(name: "write_file") arrived AND zero .artifactProduced  (3A-D)
    }

    @Test func attachmentTurnSubmitsMessageArrayWrap() async throws {
        // send with one stub image attachment; bodyString the POST /v1/runs
        // assert input is an array, [0].role == "user", [0].content has an image_url part  (3A-H unit)
    }
```

Write them with the full collector loop (copy the `Task { @MainActor in for await ... } ` + 10 s belt + `await collector.value` hang-belt pattern from `StreamLossClassificationTests.swift:296-317` — every test in this suite uses the belt).

- [ ] **Step 2: Run, verify FAIL** (driver missing). **Step 3: implement the driver + `fetchRunsHistory` + dispatch in `sendStreaming`** — in `sendStreaming` (`:189`), route: `useRunsTransportProvider() ? streamTurnViaRuns : streamTurn` (details in Task 5, but the minimal routing lands here so these tests can run; Task 5 adds the off-path pin). **Step 4: run suite, PASS, count moved (4 new).** **Step 5: Commit** — `feat(#283): runs-plane turn driver — happy path, history pre-fetch, honest artifact absence`

---

### Task 5: Dual-path dispatch pin — OFF means untouched

**Files:**
- Modify: `Talaria/Services/Live/SessionsHermesClient.swift` (`sendStreaming` routing from Task 4 — verify shape)
- Modify: `TalariaTests/RunsPlaneTransportTests.swift`

**Interfaces:** consumes Task 3's provider + Task 4's driver. Produces nothing new — this task exists as the #218 guard: the untested branch must be PINNED, both directions.

- [ ] **Step 1: Two failing-or-green pins** (write both; they may pass immediately — run them and confirm they EXECUTE, count moved):

```swift
    @Test func switchOffUsesSessionsPlaneExclusively() async throws {
        // provider { false }; stub answers /api/sessions, /chat/stream (sessions SSE fixture
        //   copied from ArtifactStreamingTests' sse(_:) shape), /messages
        // send one turn; assert request log contains /chat/stream and does NOT contain /v1/runs
    }

    @Test func switchOnNeverTouchesChatStream() async throws {
        // provider { true }; happy-path stubs from Task 4
        // assert request log contains POST /v1/runs and does NOT contain /chat/stream
    }
```

- [ ] **Step 2: Run both, confirm executed + PASS.** **Step 3: Commit** — `test(#283): dual-path dispatch pinned both directions (#218 guard)`

---

### Task 6: Recovery — status polling, exactly-once, N8 fallback, sync send

**Files:**
- Modify: `Talaria/Services/Live/SessionsHermesClient+RunsTransport.swift`
- Modify: `TalariaTests/RunsPlaneTransportTests.swift` (or a second suite `RunsPlaneRecoveryTests` in the same file if the first exceeds ~15 tests — separate `@Suite(.serialized)` struct, own stub class, per the one-stub-per-suite convention)

**Interfaces:**
- Produces:
  - `struct RunStatusResponse: Decodable` — keys `status`, `output`, `error`, `usage` (nested `TokenUsage`-compatible), `last_event`, `session_id` (CodingKeys with snake_case).
  - `func pollRunToTerminal(runID: String, profileID: UUID?) async -> RunStatusResponse?` — loop: GET `/v1/runs/{runID}`; return on `status ∈ {completed, failed, cancelled}`; sleep `runsPollInterval` between attempts; give up at `runsPollBudget` wall-clock or on `Task.isCancelled` (return nil); a 404 (`run_not_found` — TTL expiry or wrong host) returns nil immediately.
  - Test knobs mirroring `streamStallThreshold` (`:43`): `var runsPollInterval: Duration = .seconds(2)` and `var runsPollBudget: Duration = .seconds(120)` — both `// harness-visible`-style documented.
- Recovery wiring in `streamTurnViaRuns`:
  - Stream loss after submit, `finishedYielded == false` → `pollRunToTerminal`. `completed` → synthesize the SAME final-message build as the stream path (content = `output`, usage from status `usage`, reasoning = assembled partial) → `.finished`, exactly once. `failed` → `.failed(error)`. `cancelled` → silent if self-stopped else `.interrupted`. `nil` (budget/404/cancel) → `.interrupted(sessionId:runId:)` — the existing ChatStore machinery is the unchanged backstop.
  - Subscribe 404 on `/events` (N8 race lost) → skip the stream entirely, straight to `pollRunToTerminal` (same exactly-once path).
- Sync path: in `send(message:attachments:clientMessageID:)`'s `performSyncTurn` (`:167`), when the provider is on: submit via `RunsTurnBody` then `pollRunToTerminal`; `completed → output`, else throw `SessionsClientError.requestFailed(...)` — mirroring the sessions sync path's error text style.

- [ ] **Step 1: Failing tests** (each uses the hang-belt; tune `runsPollInterval = .milliseconds(40)`, `runsPollBudget = .milliseconds(800)`, `streamStallThreshold = .milliseconds(400)`):

```swift
    @Test func killedStreamRecoversFinalAnswerViaStatusPollExactlyOnce() async throws {
        // Script: events stream = padded partial (one message.delta) then delayed
        //   URLError(.networkConnectionLost) 0.1s after body (DroppingSSEProtocol shape);
        //   GET /v1/runs/run-r1 → first call {"status":"running"}, second+ call
        //   {"status":"completed","output":"FULL ANSWER","usage":{"input_tokens":9,"output_tokens":3,"total_tokens":12}}
        //   (per-path call counter in the stub, RequestLog idiom)
        // assert exactly ONE .finished; content == "FULL ANSWER"; usage.totalTokens == 12;
        //   no .failed, no .unreachable   (3A-B + #237 pin)
    }

    @Test func streamCompletionSuppressesThePollPath() async throws {
        // happy stream WITH run.completed frame; status endpoint stub COUNTS calls
        // assert ONE .finished and zero GET /v1/runs/run-r1 status calls after completion
        //   (the #237 double-delivery shape pinned absent from the other side)
    }

    @Test func pollBudgetExpiryYieldsInterruptedNotFailed() async throws {
        // stream dies; status always {"status":"running"}
        // assert .interrupted(sessionId: "sess-r", runId: "run-r1"); no .finished; no .failed
        //   — the existing ChatStore pendingRun machinery is the backstop (unchanged in 3A)
    }

    @Test func subscribeRaceLostFallsBackToPolling() async throws {
        // GET /v1/runs/run-r1/events → 404 {"error":{"code":"run_not_found"}};
        //   status → completed with output
        // assert ONE .finished with the output   (N8)
    }

    @Test func zombieRunsStreamTripsTheStallGuard() async throws {
        // ZombieSSEProtocol shape: 2xx + padded partial body, then NOTHING (no finish, no error)
        // streamStallThreshold = .milliseconds(400); status → always running
        // assert .interrupted arrives (stall guard fired through the runs loop)   (#246 parity)
    }

    @Test func syncSendRidesRunsWhenSwitchOn() async throws {
        // provider on; POST /v1/runs + status completed; call client.send(...)
        // assert returned Message content == output; request log has NO /api/sessions/*/chat
    }
```

- [ ] **Step 2: Run, FAIL.** **Step 3: implement poll + wiring + sync path.** **Step 4: run the whole `RunsPlane*` set + `StreamLossClassificationTests` + `ReasoningChannelTests` (regression: the widened members and sendStreaming routing must not disturb the sessions plane), PASS, count moved (6 new).** **Step 5: Commit** — `feat(#283): status-poll recovery — exactly-once final answer, N8 fallback, real sync path`

---

### Task 7: Stop — a real server-side interrupt

**Files:**
- Modify: `Talaria/Services/Live/SessionsHermesClient+RunsTransport.swift` + `SessionsHermesClient.swift`
- Read-then-modify if needed: `Talaria/Services/Support/ChatBackendRouter.swift:483-489` and `Talaria/Services/Support/ResilientHermesClient.swift` — `abandonActiveRun` forwarding
- Modify: `TalariaTests/RunsPlaneTransportTests.swift`

**Interfaces:**
- Produces on `SessionsHermesClient`: `private(set) var activeRunContext: (runID: String, profileID: UUID?)?` (set at submit, cleared on terminal yield) and an implementation of the protocol's `func abandonActiveRun()` (currently absent — default no-op at `HermesClientProtocol.swift:150`): capture-and-clear `activeRunContext`, set a `selfStoppedRunIDs` insert (so a late `run.cancelled` frame / poll result ends silently, not `.interrupted`), then fire-and-forget `Task { try? await postJSON(path: "/v1/runs/\(runID)/stop", body: EmptyBody(), profileID: profileID) }` (define `struct EmptyBody: Encodable {}` or POST with `nil` body via `makeRequest` — match whichever the sessions client uses for body-less POSTs; `createBareSession` at `:972` is the reference).
- **Forwarding check (explicit step):** `ChatStore.cancelStreaming()` calls `hermesClient.abandonActiveRun()` where `hermesClient` is the ROUTER. Read `ChatBackendRouter.abandonActiveRun()` (`:483-489`) — it releases the routing lock; verify it ALSO forwards to the hermes client (`hermes.abandonActiveRun()` or via `ResilientHermesClient`). If it does not forward, add the forward call (router → resilient → sessions; `ResilientHermesClient` gets a one-line `func abandonActiveRun() { primary.abandonActiveRun() }` if missing). This is the difference between bar 3A-C passing and silently failing.

- [ ] **Step 1: Failing tests:**

```swift
    @Test func abandonActiveRunPostsStopWithAuth() async throws {
        // start a turn against a stream that parks (zombie shape) so the run stays active;
        // once the request log shows the events subscribe, call client.abandonActiveRun()
        // pump until the log contains POST /v1/runs/run-r1/stop with Authorization "Bearer test-key"
        // assert no .interrupted was yielded for the self-stopped run (silent teardown)
    }

    @Test func abandonWithNoActiveRunIsANoOp() async throws {
        // fresh client, provider on; call abandonActiveRun(); assert zero /stop requests
    }
```

- [ ] **Step 2: Run, FAIL.** **Step 3: implement + forwarding fix.** **Step 4: run `RunsPlane*` suites + `AppStoresTests` (ChatStore cancel path regression), PASS, count moved.** **Step 5: Commit** — `feat(#283): Stop is real on the runs plane — POST /v1/runs/{id}/stop (S23; today's Stop is cosmetic, S24)`

---

### Task 8: Gate, docs, PR

- [ ] **Step 1:** `xcodegen generate` (idempotent re-run), then full suite + Release via the gate, backgrounded:
  ```bash
  cd <worktree> && nohup scripts/mac/lane-gate.sh > /tmp/283-gate.log 2>&1 &
  ```
  Poll `/tmp/283-gate.log` until `GATE: PASS` / `GATE: FAIL`. Requirements: PASS, Swift Testing count MOVED from the pre-lane baseline (record both numbers), exactly the 2 known skips.
- [ ] **Step 2: Docs, same commit discipline as the close-out rule:**
  - `OPEN_ITEMS.md` #283: dated update — build-side bars status (3A-A/B/D/G-unit/H-unit met with test names; 3A-E gate evidence; 3A-C/F/G-device owed to the device pass), the serving-model delta note ("runs `run.completed` carries no runtime block — `.modelResolved` never fires on the runs path; UI shows honest absence; revisit at 3B+"), and the priming-turn-stays-sessions note.
  - `dispatch/DEVICE-PASS-RUNNING-LIST.md`: add the 3A device bars (3A-C stop-on-device with host-log evidence, 3A-F full conversation incl. backgrounded-stream kill, 3A-G device arm) — behind the existing queue front (78-F2 stays first).
- [ ] **Step 3: PR** from `claude/t27-283-3a-runs-transport` — body: what moved, the bars table with build-side evidence, the probe report link, explicit "Developer switch default OFF; sessions path untouched and pinned by `switchOffUsesSessionsPlaneExclusively`". End with the standard generated-with footer. **Do not merge without the gate PASS line quoted.**

---

## Self-review notes (run before handoff)

- Spec coverage: 3A-0 ✅ (done pre-plan, report I) · 3A-A Task 4 · 3A-B Task 6 · 3A-C Task 7 (+ device leg) · 3A-D Task 4 · 3A-E Task 8 · 3A-F device pass (out of plan scope, queued) · 3A-G Task 4 unit + device leg · 3A-H Tasks 1+4. Dual-path Q3 shape: Task 5. §2.5/2.6 (steer/queue composer), §2.2 approvals, §2.8 artifact mirror: deliberately NOT here — slices 3B/3C/3D.
- The `.ignored` events list keeps `approval.request` decodable-but-unconsumed so 3B extends the parser instead of rewriting it.
- Type-consistency: `RunsTurnBody.HistoryEntry` (Tasks 1/4), `RunsEvent`/`parseRunsFrame` (Tasks 2/4), `RunStatusResponse`/`pollRunToTerminal` (Task 6), `activeRunContext` (Tasks 4/7 — Task 4 uses a local until Task 7 promotes it; both compile independently because Task 4 ships the local).
