# #237 Stable Identity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. TDD per task, RED watched.

**Goal:** Reconcile adoptions stop duplicating transcripts (stable ids), a run can never resolve twice (idempotence), and already-corrupted threads heal on load (sweep).

**Spec:** `docs/superpowers/specs/2026-08-03-237-stable-identity-design.md` (routed). Branch `claude/t27-237-stable-identity`. Sim UDID `47F68496-24F9-45D9-93D3-1C778DB6B557`; `DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer`; no new files → no xcodegen; commit trailer as always.

### Task 1 (F1 · 237-A): `stableMessageID` + threading

- Test (ReasoningChannelTests, new MARK): determinism (`stableMessageID(sessionId:"s1", serverRowID: 9046)` equal across two calls), distinctness across rowID and sessionId, and version/variant bits sane (`uuidString` parses). RED = missing member.
- Implement in `SessionsHermesClient`: CryptoKit SHA-256 over `"talaria-msg:\(sessionId):\(serverRowID)"`, first 16 bytes, set `bytes[6] = (bytes[6] & 0x0F) | 0x50`, `bytes[8] = (bytes[8] & 0x3F) | 0x80`, build UUID from tuple.
- Thread: `mapStoredMessage(_ m:, sessionId: String)`; call site 723 becomes `response.data.compactMap { Self.mapStoredMessage($0, sessionId: id) }`; inside, when `m.id` (verify field name in `SessionMessagesResponse.StoredMessage`) is non-nil, pass `id: Self.stableMessageID(sessionId: sessionId, serverRowID: rowID)` to `Message(...)`; nil keeps `UUID()`.
- Run ReasoningChannelTests → GREEN; commit `#237 F1: stable message identity at the mapping boundary (237-A)`.

### Task 2 (F3 · 237-D): the dedupe sweep

- Tests (AppStoresTests, new MARK): a quadrupled fixture (same rows repeated 4×, same timestamps) collapses to one copy; idempotent (second application identical); two user messages with equal content but different timestamps BOTH survive; empty-content tool-shell rows dedupe only when `toolActivities` labels match.
- Implement `Conversation.dedupingAdoptedEchoes(_ messages: [Message]) -> [Message]` (static, pure): first-occurrence-wins keyed on `(sender, content.trimmed, timestamp)`, with empty-content rows additionally keyed on joined activity labels.
- Apply at the END of `mergeConversationMetadata` (before returning) and in the client's cache-restore path (`restoreFromCacheIfNeeded` / `loadConversation` — grep at execution, apply where the cached conversation is adopted).
- GREEN; commit `#237 F3: dedupe sweep heals adopted-echo corruption (237-D)`.

### Task 3 (F2 · 237-B/C): run idempotence + the no-growth pin

- Tests (AppStoresTests): (C) a client whose second `sendStreaming` yields `.interrupted` with the SAME runId as an already-resolved run → no new PendingRun (`pendingRunSessionId == nil`), `onRunResolved` fired once total (count via the closure seam). (B) two full strand→resolve cycles against a growing server transcript → final message count equals the server transcript's mapped count + unconfirmed locals only (exact number asserted; no duplication).
- Implement: `private var resolvedRunIDs: Set<String> = []` on ChatStore (cleared where the conversation resets — mirror the pendingRun clears); record in `attemptReconcile` on success (`if let runId = pending.runId`); guard in the `.interrupted` case (`if let runId, resolvedRunIDs.contains(runId) { continuedSend?.finish(success: true); return }` — adapt to the case's actual control flow at execution, keep placeholder-removal semantics for the duplicate-interrupt path minimal and honest).
- GREEN; commit `#237 F2: a resolved run never resolves twice (237-B/C)`.

### Task 4: entry, gate, PR, OTA

- Entry header + built-note (bars A–D claimed only after gate; E parked for device with the 235-F unpark note).
- Gate backgrounded; count must move by the new-test total (tally at execution).
- PR (`#237: stable message identity — transcripts stop duplicating and heal (OPEN_ITEMS numbering)`, body cites the union-site root cause + falsified-heal evidence; device bars not claimed). OTA staged from the branch per Owen's standing "stage when green."

Self-review: spec F1/F2/F3 ↔ tasks 1/3/2; 237-E is device-only by design; names consistent (`stableMessageID`, `dedupingAdoptedEchoes`, `resolvedRunIDs`).
