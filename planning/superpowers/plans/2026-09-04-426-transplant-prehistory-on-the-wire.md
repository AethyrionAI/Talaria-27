# 426 — The Transplanted Prehistory Rides Every Run, Not Just The First Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On a transplanted Hermes thread, every `POST /v1/runs` after the priming turn carries the transplanted prehistory in `conversation_history`. Today it does not: `fetchRunsHistory` (`SessionsHermesClient+RunsTransport.swift:967-973`) builds the wire body from the DISPLAY mapping (`fetchSessionConversation` → `mappedTranscript` → `collapsingTransplantAcknowledgments(rows.compactMap { mapStoredMessage })`, `SessionsHermesClient.swift:719-724`), which rewrites the stored primer row into a `.system` notice with the content REPLACED (`:778-783`) and drops the acknowledgment (`:749`); `runsHistory` then skips `.system` (`+RunsTransport.swift:990`). So ~1,500 tokens of condensed journal ride the priming turn only, and — because runs WRITE the session transcript but never READ it — every later turn on that hop ships without them. A regression from #330's display fix (`faa725df`, PR #383, 2026-08-26): a display fix that changed the wire body, pinned by an 08-07 test. The fix builds the wire history from the RAW stored rows and leaves primer hiding to presentation.

**Architecture:** Split `fetchSessionConversation` into its network+decode half (`fetchStoredMessages(_:profileID:endpoint:) -> [StoredMessage]`) and its display half (unchanged: `mappedTranscript`). `fetchRunsHistory` calls the first and a NEW pure mapper, `runsHistory(fromStored:excludingTrailing:)`, that carries `user`/`assistant` rows verbatim (trimmed, non-empty), applies the existing trailing-duplicate rule, and performs NO primer remap and NO acknowledgment collapse. The `[Message]`-based `runsHistory(from:)` is deleted so there is exactly one wire history builder and it cannot be fed the display shape. Both run paths (`streamTurnViaRuns` `:536`, `syncTurnViaRuns` `:860`) already call `fetchRunsHistory` and change nothing. Display (`openSession`, the status card, `SessionTotalsAfterReopenTests`) is byte-untouched.

**Tech Stack:** Swift 6.4 / `SessionsHermesClient` (+RunsTransport) / `RunsStubURLProtocol` fixture (`RunsPlaneTransportTests.swift:50-125`) / Swift Testing / the Mac gateway's `agent.log` as the wire-truth instrument / `scripts/mac/lane-gate.sh`.

**Why this is the shape:** the audit and the entry both say it — *"construct wire history from raw stored messages … apply primer hiding only to presentation … this is not a request to restore the retired sessions transport (#382)."* The display remap is CORRECT for the user (#330's device observation 2: a wall of journal text under the user's own name) and WRONG for the agent, whose transcript that text is. Two consumers, two needs, one shared mapping — the composed-path shape (memory `composed-path-blind-spots`: *"for any representation shared by display and wire, ask which consumer's needs the mapping serves"*). Building the wire from the host's own stored rows is also the runs contract's own words (N4: *"server truth is current precisely because of that write half"*).

**Evidence measured tonight (2026-09-04, read-only on the Mac gateway — this is Task 0 (a), already done and recorded here so the lane does not redo it):**
- The host logs the BODY's history count per turn: `agent/turn_context.py:797` (checkout `71f8c60f6a`, listener started 17:51 today — no drift) — `"conversation turn: session=%s … history=%d msg=%r"` with `history = len(conversation_history or [])`. That is `conversation_history` from OUR request body, counted by the host. A free wire-body probe.
- In `~/.hermes/logs/agent.log`, the first real turn after a transplant (`history=0 msg='[CONTEXT TRANSPLANT — …'`) reads **`history=2` on 08-22, 08-23 and 08-25** (four sessions — the primer + its ack rode the wire) and **`history=0` on 08-26 17:59 and 18:01** (two sessions, the day `faa725df` landed — nothing rode). Later turns on the 08-31 session go 2 → 4 → 6, i.e. the two exchanges since priming and never the priming pair. The regression is measured on the wire, not inferred from source.
- **One anomaly for the lane to explain, not explain away:** the 08-31 session's FIRST turn (`20:18:55 what is the capital of France?`) reads `history=2`. The aiohttp access log beside it names the client (`"Talaria%2027/<build> CFNetwork/…"` for the app; another User-Agent for an MCP/CLI client) — read that line before drawing any conclusion. If it was the app, the premise "always 0 since 08-26" is wrong in a way the plan must know.

## Global Constraints

- **Display is untouched.** `mapStoredMessage`'s primer remap (`:778-783`), `collapsingTransplantAcknowledgments` (`:740-757`), `openSession`, the `TurnReceiptSidecar` replay, and every test in `SessionTotalsAfterReopenTests` stay byte-identical. A lane that "fixes" this by changing the display map has re-opened #330.
- **One wire history builder.** `runsHistory(from: [Message], …)` is DELETED, not deprecated; its four tests are rewritten against stored rows (the rules they pin — drop blanks, drop only the TRAILING outgoing duplicate, keep a non-outgoing tail — survive unchanged).
- **Verbatim.** The stored primer's content rides as stored: no trimming beyond whitespace, no truncation, no re-labelling of its role. The host wrote it as `user`; the agent reads it as `user`.
- **Not a sessions-transport restore (#382).** No `/chat`, no `/chat/stream`, no new call site — the structural pin from #382 must stay green.
- **Score the wire from the host's count, never from the model's reply** (#347's rule applied to a different log): `history=N` on the host is the mechanism bar; "did the answer use the prehistory" is the experience bar and is scored second.
- **Tokens:** the primer is ~1,500 tokens per turn from now on, forever, on transplanted hops. That is the PRE-08-26 behaviour restored, not a new cost — say so in the RESULT block, and note #279's uncounted-history instrumentation (`RunsTurnBody.make`'s `historyBytes` warning, `+RunsTransport.swift:100-115`) will see it.
- **Gate + merge protocol:** worktree isolation; RED-first with the mutation named per bar; `TALARIA_SIM_NAME=CC-lane-N scripts/mac/lane-gate.sh`, ≤ 3 booted, kill only your recorded PID; positive `GATE: PASS`; merge on green; RESULT block in entry 426 (with the wire numbers).
- **Plan-authored code is unreviewed code.** The mapper is small enough to write here in full; the RED integration fixture is the real bar.

## Decisions for Owen (one AskUserQuestion round — recommended arm first)

1. **Ship what the host stored — the primer AND its acknowledgment (recommended).** The ack is the assistant's own one-sentence reply to the primer; it keeps the history alternating user/assistant and costs ~20 tokens. Alternative: primer only (drop the ack) — saves a sentence, ships a user/user pair.
2. **The wire measurement runs from the SIMULATOR against the Mac gateway (recommended)** — the runs plane works on the sim (only the on-device brain does not), and the Mac's `agent.log` gives the count; no phone needed for the mechanism bar. Alternative: device only.
3. **The experience bar's planted fact (recommended: one concrete, unusual fact in the local prehistory — "my dentist is Dr Patel on Lamar" — asked on turn 2 as "who is my dentist?").** Alternative: Owen picks a fact from a real local thread of his.
4. **No new log line in the app (recommended)** — the host already counts the body, and a client-side `history=N` line would be a second instrument saying the same thing. Alternative: add a verbose-gated client line for offline archives.

## Session contract

1. Read `OPEN_ITEMS.md` entry 426; `OPEN_ITEMS-ARCHIVE.md` #330 (the fix lane's block — the display remap's reasons), #283 (3A — `runsHistory`'s birth, bar 3A-G), #382 (the sessions transport deletion and its structural pin), #90 (the transplant itself). Pre-register bars 426-A..GATE in entry 426 BEFORE Task 0 (b).
2. Task 0 (a) is done (above). Task 0 (b) — the anomaly read and ONE sim-vs-Mac transplant on the CURRENT build to record the RED wire number — is the lane's first half hour.
3. One worktree lane (Opus): Tasks 1–3, RED-first, mutations named, gate, merge on green, RESULT block. Fable only for a falsified bar.
4. The experience check (426-E's second half) is a §01 runbook card for Owen's evening; the mechanism bar needs no device.

## File structure

**Modify:**
- `Talaria/Services/Live/SessionsHermesClient.swift`
  - `:659-700` `fetchSessionConversation` — its request/decode/`.error`-log half becomes `func fetchStoredMessages(_ id: String, profileID: UUID?, endpoint: ResolvedEndpoint? = nil) async throws -> [SessionMessagesResponse.StoredMessage]`; `fetchSessionConversation` calls it and maps exactly as today (the #330 SEAM 1 verboseNotice stays where it is).
- `Talaria/Services/Live/SessionsHermesClient+RunsTransport.swift`
  - `:967-973` `fetchRunsHistory` — `let rows = try await fetchStoredMessages(sessionId, profileID: nil, endpoint: endpoint); return Self.runsHistory(fromStored: rows, excludingTrailing: outgoing)`.
  - `:975-1000` `runsHistory(from: [Message], …)` — DELETED; replaced by:

```swift
/// Pure mapping half of the pre-fetch, from the host's OWN stored rows.
///
/// #426: this deliberately does NOT go through `mappedTranscript`. The
/// display map rewrites the transplant primer into a notice (its CONTENT
/// replaced) and drops the acknowledgment — right for the user, wrong for
/// the agent, whose transcript that text is. A run never reads the session
/// it writes (N4), so what leaves here is the only context the agent gets.
nonisolated static func runsHistory(
    fromStored rows: [SessionMessagesResponse.StoredMessage],
    excludingTrailing outgoing: String
) -> [RunsTurnBody.HistoryEntry] {
    var entries: [RunsTurnBody.HistoryEntry] = []
    for row in rows {
        let role: String
        switch (row.role ?? "").lowercased() {
        case "user": role = "user"
        case "assistant": role = "assistant"
        default: continue   // system / tool / other host roles are not the thread
        }
        let text = (row.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { continue }
        entries.append(RunsTurnBody.HistoryEntry(role: role, content: text))
    }
    let trimmedOutgoing = outgoing.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedOutgoing.isEmpty, let last = entries.last, last.role == "user", last.content == trimmedOutgoing {
        entries.removeLast()
    }
    return entries
}
```

**Tests:**
- `TalariaTests/RunsPlaneTransportTests.swift` — `RunsHistoryMappingTests` (`:2110-2200`) rewritten on stored rows; ONE new integration test beside `historyRidesTheSubmitBody` (`:513-540`).
- The `RunsStubURLProtocol` script helper (`Self.script(sseBody:)`) gains a `messagesJSON:` parameter defaulting to today's two-row body, so every existing test's fixture is byte-identical and the new test supplies the four-row body.

## Bars (paste into entry 426 as a dated block BEFORE Task 0 (b))

- **426-A — the stored primer rides the wire verbatim (unit, pure).** `runsHistory(fromStored:)` over `[user: <marker>\n<PREHISTORY-KUMQUAT body>, assistant: "Acknowledged.", user: "ping", assistant: "pong"]` → 4 entries; `[0].role == "user"`; `[0].content` starts with `ContextTransplanter.transplantMarker` and contains `PREHISTORY-KUMQUAT`; `[1] == ("assistant", "Acknowledged.")`. **This is the 08-07 pin flipped:** `mapsUserAndHermesRolesAndDropsEveryoneElse` asserted a `"Context transplanted."` `.system` row is dropped — true for a DISPLAY notice, and there is no display notice on the wire any more; the rewritten test asserts a stored `system`-ROLE row (a host role, not our notice) is still dropped, and the primer (a `user` row) is kept. Mutation: route `fetchRunsHistory` back through `fetchSessionConversation` → the integration bar reds; feed the mapper a remapped notice → this unit bar reds.
- **426-B — the next POST carries it (integration, `RunsStubURLProtocol`).** `/api/sessions/sess-r/messages` answers the four-row JSON; one streamed turn `"who is my dentist"`; the recorded `POST /v1/runs` body's `conversation_history.count == 4`, `[0].content` starts with the marker and contains `PREHISTORY-KUMQUAT`, and the GET still precedes the POST (3A-G's ordering half, kept). RED on the current tree (today's body carries 2 entries, `ping`/`pong`). The existing `historyRidesTheSubmitBody` stays byte-identical and green.
- **426-C — the three surviving rules survive (unit).** Blank/whitespace rows dropped; ONLY the trailing row equal to the outgoing turn dropped (an identical EARLIER row survives); a trailing assistant row or a different tail is kept; a whitespace-only outgoing drops nothing. Same assertions as the 08-07 tests, sourced from stored rows.
- **426-D — display is untouched (existing suites, plus one witness).** `SessionTotalsAfterReopenTests` and `RunsPlaneTransportTests`' other tests byte-identical and green; `RepoSourceWitness.functionBody(from: "func fetchRunsHistory", in: "Talaria/Services/Live/SessionsHermesClient+RunsTransport.swift")` contains `fetchStoredMessages(` and contains neither `fetchSessionConversation(` nor `mappedTranscript(`; `runsHistory(from:` (the `[Message]` overload) has zero occurrences in the tree (`grep -rn 'runsHistory(from:' Talaria TalariaTests` → 0 — a compile-time fact once deleted, recorded as a grep in the RESULT block).
- **426-E — the wire, measured on the host (sim → Mac gateway; then device for the experience half).** (i) CURRENT build (RED): a new local thread with the planted fact, switch to the Mac Hermes profile (transplant fires), one turn → `agent.log`'s `agent.turn_context` line for that turn reads `history=0`. (ii) FIX build (GREEN): same recipe → `history=2` on the first real turn, `history=4` on the second. (iii) Experience, on the phone, Owen's evening: the second turn asks "who is my dentist?" and the reply names Dr Patel. Both numbers carry the app build and the host commit/version.
- **426-GATE** — positive `GATE: PASS`, count moved by exactly this lane's tests (the mapping suite's count is unchanged: four rewritten + one new).

## Task 0 (b): The anomaly and the RED wire number (no production code; ~30 min)

- [ ] **Step 1 — explain 08-31 20:18:55.** `grep -n '20:18:5' ~/.hermes/logs/agent.log` and read the `aiohttp.access` line(s) within the same second: an app request carries `"Talaria%2027/<build> CFNetwork/…"`. Record the client. If it WAS the app, re-read `mappedTranscript` for a reason a stored primer could escape the remap (e.g. leading whitespace before the marker — `hasPrefix` after `trimmingCharacters` at `:764`/`:778`) and file it; the fix below makes the question moot for the wire but the display map would then have a hole of its own (#330's business, filed not fixed here).
- [ ] **Step 2 — the RED number on the current build.** On `CC-lane-N`, with a Debug build of `main`, a Hermes profile pointed at the Mac gateway (`100.79.222.100:8642`, the dev box — chat turns are read-only probes under CLAUDE.md's live-install rule; no config changes): start a LOCAL thread, say "my dentist is Dr Patel on Lamar", switch the thread to the Hermes backend so the transplant fires, send "hello". Then: `grep 'agent.turn_context' ~/.hermes/logs/agent.log | tail -3` — the transplant line (`history=0 msg='[CONTEXT TRANSPLANT`) followed by `history=0 msg='hello'`. Record both lines verbatim in the entry as `426-T0b`. If it reads `history=2`, STOP: the premise is wrong on this build and the lane's first job is to find out why (the anomaly in Step 1 is the first suspect).

## Task 1: `fetchStoredMessages` + the stored-row mapper (bars 426-A, 426-C)

**Files:** modify `SessionsHermesClient.swift:659-700`, `+RunsTransport.swift:967-1000`; modify `RunsPlaneTransportTests.swift:2110-2200`.

- [ ] **Step 1 — RED tests (the rewritten mapping suite):**

```swift
struct RunsHistoryMappingTests {
    private func row(_ role: String, _ content: String) -> SessionMessagesResponse.StoredMessage {
        // Decode from JSON — StoredMessage has a hand-written init(from:) and no memberwise init.
        try! JSONDecoder().decode(SessionMessagesResponse.StoredMessage.self,
            from: Data(#"{"role":"\#(role)","content":\#(String(data: try! JSONEncoder().encode(content), encoding: .utf8)!)}"#.utf8))
    }

    @Test func aStoredTransplantPrimerRidesTheWireVerbatimAndHostRolesStillDrop() {   // 426-A, the flipped 08-07 pin
        let primer = ContextTransplanter.primingText(body: "The user's dentist is Dr Patel on Lamar. PREHISTORY-KUMQUAT")
        let history = SessionsHermesClient.runsHistory(fromStored: [
            row("user", primer), row("assistant", "Acknowledged."),
            row("system", "a host-side system row"), row("tool", "{}"),
            row("user", "ping"), row("hermes", "pong-with-an-unknown-role"),
        ], excludingTrailing: "")
        #expect(history.map(\.role) == ["user", "assistant", "user"])
        #expect(history[0].content.hasPrefix(ContextTransplanter.transplantMarker))
        #expect(history[0].content.contains("PREHISTORY-KUMQUAT"))
        #expect(history[1].content == "Acknowledged.")
    }
    // 426-C: dropsEmptyAndWhitespaceOnlyRows / dropsATrailingRowEqualToTheOutgoingTurn /
    //        keepsATrailingRowThatIsNotTheOutgoingTurn — the 08-07 bodies, with `row(...)` in place of `message(...)`.
}
```

- [ ] **Step 2 — RED:** compile failure (`runsHistory(fromStored:)` undefined). Run `-only-testing:TalariaTests/RunsHistoryMappingTests`.
- [ ] **Step 3 — implement:** the mapper above; `fetchStoredMessages` extracted (the `.error` decode log at `:668-669` moves with it unchanged — #432 owns that line's content, not this lane); `fetchSessionConversation` = `fetchStoredMessages` + `mappedTranscript` + the existing SEAM 1 notice; `fetchRunsHistory` rewired; the `[Message]` overload deleted (the compiler lists any straggler caller).
- [ ] **Step 4 — GREEN + mutation:** feed the mapper `row("system", ContextTransplanter.transplantNoticeLabel(usage: nil))` in place of the primer row (the DISPLAY shape) → the primer assertions red — proving the bar can see the old body. Restore. **Commit:** `426-A/C: wire history from the host's stored rows — the primer rides verbatim; the 08-07 pin flipped RED-first`.

## Task 2: The POST body carries it (bar 426-B) + the witness (426-D)

**Files:** modify `RunsPlaneTransportTests.swift` (the script helper + one test near `:513`); a new witness test in the same file or `RunsHistoryWitnessTests.swift`.

- [ ] **Step 1 — RED test:**

```swift
@Test @MainActor
func aTransplantedHopShipsItsPrehistoryOnTheNextRun() async throws {   // 426-B
    RunsStubURLProtocol.reset()
    let primer = ContextTransplanter.primingText(body: "The user's dentist is Dr Patel on Lamar. PREHISTORY-KUMQUAT")
    let messagesJSON = """
    {"data":[
      {"id":1,"role":"user","content":\(jsonString(primer)),"timestamp":1.0},
      {"id":2,"role":"assistant","content":"Acknowledged.","timestamp":1.1},
      {"id":3,"role":"user","content":"ping","timestamp":1.2},
      {"id":4,"role":"assistant","content":"pong","timestamp":1.3}
    ]}
    """
    RunsStubURLProtocol.script = Self.script(sseBody: Self.runsSSE([
        #"{"event":"run.completed","run_id":"run-r1","timestamp":1.5,"output":"Dr Patel","usage":{"input_tokens":1,"output_tokens":1,"total_tokens":2}}"#,
    ]), messagesJSON: messagesJSON)
    defer { RunsStubURLProtocol.reset() }

    let client = makeClient(label: "prehistory")
    _ = await collect(from: client)          // sends "hi" per the fixture — the outgoing text is not in the stored rows

    let submit = try #require(RunsStubURLProtocol.request("POST", "/v1/runs"))
    let body = try #require(JSONSerialization.jsonObject(with: Data(submit.body.utf8)) as? [String: Any])
    let history = try #require(body["conversation_history"] as? [[String: Any]])
    #expect(history.count == 4, "the priming pair must ride every run — today it rides none after the first")
    #expect((history[0]["content"] as? String)?.hasPrefix(ContextTransplanter.transplantMarker) == true)
    #expect((history[0]["content"] as? String)?.contains("PREHISTORY-KUMQUAT") == true)
    #expect(history[1]["content"] as? String == "Acknowledged.")
    let messagesIndex = try #require(RunsStubURLProtocol.index("GET", "/api/sessions/sess-r/messages"))
    let submitIndex = try #require(RunsStubURLProtocol.index("POST", "/v1/runs"))
    #expect(messagesIndex < submitIndex)
}
```

- [ ] **Step 2 — RED on the current tree:** `history.count == 2` (`ping`/`pong`) — record the failure text verbatim for the RESULT block. (Run this test BEFORE Task 1's implementation lands in the worktree, or stash-and-run: the RED must be witnessed on the unmodified mapping, not assumed.)
- [ ] **Step 3 — the helper:** `Self.script(sseBody:messagesJSON:)` with the default equal to today's literal body (read the helper; the two-row `KUMQUAT-N4A`/`noted` JSON is what `historyRidesTheSubmitBody` expects — keep it byte-identical).
- [ ] **Step 4 — GREEN after Task 1. Witness (426-D):** `RepoSourceWitness.functionBody(from: "func fetchRunsHistory", in: "Talaria/Services/Live/SessionsHermesClient+RunsTransport.swift", boundary: "\n    nonisolated static func ")` — contains `fetchStoredMessages(`, contains neither `fetchSessionConversation(` nor `mappedTranscript(`. Mutation: point `fetchRunsHistory` back at `fetchSessionConversation` → 426-B AND 426-D red together. **Commit:** `426-B/D: the next POST carries the primer (RED witnessed at count 2); the wire builder is pinned to stored rows`.

## Task 3: Gate, PR, the wire numbers, RESULT block, close-out corrections

- [ ] `TALARIA_SIM_NAME=CC-lane-N scripts/mac/lane-gate.sh` (background, PID-poll); positive `GATE: PASS`; count moved by exactly +1 (four rewritten, one new, one witness = +2 if the witness is its own test — say which).
- [ ] PR; merge on green.
- [ ] **426-E (ii) — the GREEN wire number:** the Task 0 (b) recipe on the FIX build (sim → Mac gateway): `history=2` on the first real turn, `history=4` on the second; paste the three `agent.turn_context` lines into the RESULT block beside Task 0 (b)'s `history=0`. Host commit/version from `/health` + the reflog-vs-start-time rule (CLAUDE.md).
- [ ] RESULT block in entry 426: bars A–E(i,ii) met/missed with RED + mutation outputs; the token-cost note (pre-08-26 behaviour restored); E(iii) owed to Owen's evening.
- [ ] **Close-out rule (same commit):** `OPEN_ITEMS-ARCHIVE.md` #330's fix block gets an append-only dated pointer (*the display remap was correct; the wire followed it and should not have — #426*); #283's 3A-G bar text (*"history rides the submit body"*) gets a dated pointer naming the stored-row builder; the `runsHistory` doc comment at `+RunsTransport.swift:975-979` is rewritten for the new source; `CLEAN_CHAT_PATH.md` if it names `runsHistory(from:)` (grep first).
- [ ] `scripts/mac/ota-stage.sh main Debug`; one §01 runbook card for 426-E (iii): local thread with the planted fact → switch to Hermes → "hello" → "who is my dentist?" → the reply names Dr Patel; PASS/FAIL; same-day `agent.log` read on the host.

## Out of scope, and why

- **#432 (A7)** — the `.error` decode log with 500 body bytes at `:668-669` moves into `fetchStoredMessages` UNCHANGED; its content is that lane's.
- **Trimming or budgeting the history** — #279's review note (*"trimming what history the agent sees is a behavioral decision, filed separately"*) stands; this plan restores the pre-08-26 body, it does not shape it.
- **The display map's own potential hole** (Task 0 (b) Step 1's second branch) — filed under #330 if found, not fixed here.

## Self-review (2026-09-04, at plan-writing time)

- Every line number was read tonight: `fetchRunsHistory` `:967-973`; `runsHistory(from:)` `:980-1000` with `default: continue // system notices are ours` at `:990`; `mappedTranscript` `:719-724`; the remap `:764-783` (`hasPrefix(ContextTransplanter.transplantMarker)` after trim, content replaced by `transplantNoticeLabel(usage: nil)`); the ack collapse `:740-757`; `fetchSessionConversation` `:659-700`; both call sites `:536` and `:860`; the pin `RunsPlaneTransportTests.swift:2124-2136`; `StoredMessage` `SessionsHermesClient.swift:2027-2055` (hand-written `init(from:)` — hence the JSON-decoded fixture rows); `historyRidesTheSubmitBody` `:513-540`.
- The wire regression is MEASURED (the Mac `agent.log`, tonight), and the instrument's semantics were read in the host's source (`turn_context.py:797`), not assumed. The one anomaly is named and assigned, not smoothed over.
- What this plan does NOT claim: that the agent's ANSWERS improve (426-E (iii) measures it once, on Owen's evening); that the 08-31 first turn came from the app (Task 0 (b) reads the access log).
- Type consistency: `fetchStoredMessages(_:profileID:endpoint:)`; `runsHistory(fromStored:excludingTrailing:)`; `RunsTurnBody.HistoryEntry(role:content:)`; `SessionMessagesResponse.StoredMessage`; `ContextTransplanter.transplantMarker` / `.primingText(body:)` / `.transplantNoticeLabel(usage:)`; `RunsStubURLProtocol.script(sseBody:messagesJSON:)` — used consistently across Tasks 1–3.
