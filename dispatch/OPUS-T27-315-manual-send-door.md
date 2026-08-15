# OPUS T27-315 — the composer's queue DOOR renders on `isStreaming`; a manual send during the reconcile window posts into a live `pendingRun`

**Item:** OPEN_ITEMS **#315** — the LAST door in the #278 corruption class
(#306 shut the queue-fire door, #307 the drain door). **Difficulty: OPUS** —
one predicate swap in the door condition plus unit pins; the semantics it
adopts (row 3 of #306's matrix) already shipped. Written 2026-08-10.

## 1. Verified state

- **The window:** `streamingMessageID == nil && pendingRun != nil` — the #278
  state, documented at `ChatStore.swift:127-135` (as-filed refs), lasting up
  to minutes after a stream drop. `isTranscriptBusy`
  (`ChatStore.swift:139`, verified at HEAD 2026-08-10:
  `streamingMessageID != nil || pendingRun != nil`) is THE predicate for it.
- **The defect (from #306's whole-lane review, which traced the door while
  verifying C2):** the composer's queue door renders only on `isStreaming` —
  during the reconcile window it therefore offers **plain Send**. A manual
  send there posts into the live `pendingRun`, and `attemptReconcile`'s
  `timestamp > pending.sentAt` adoption can pair the dropped run's recovery
  with the manual turn's reply — someone else's reasoning re-attached, a
  fabricated duration, the old prompt re-paired, nothing erroring. The #307
  mechanism exactly, user-driven instead of drain-driven.
- **What already guards the OTHER doors at HEAD (verified):**
  `holdComposedTurn`'s fire gate and `drainComposeOutboxIfPossible`
  (`:2076-2078` — "#278: `isTranscriptBusy`, not `isStreaming`"), the drain
  guard (`:2267`), and `ChatScreen.queueComposedMessage()`'s fallback
  (`ChatScreen.swift:1529` — `!chatStore.isTranscriptBusy` before
  `sendMessage()`). **The un-guarded surface is the DOOR — which button/path
  the composer offers.**
- **⚠️ VERIFY AT LANE START:** the door's exact render condition. Anchors:
  `ChatScreen.swift:1095-1099` (a "#278: NOT `isStreaming`" comment already
  sits beside an `isTranscriptBusy:` pass-through — the door's condition is
  the sibling that still reads `isStreaming`). Grep `isStreaming` in
  `ChatScreen.swift` and name the line in the entry before editing.
  - **🔴 CORRECTED 2026-08-10 AT THE LANE — the bracketed guess above is
    FALSE, and the verify step is what caught it.** `ChatScreen.swift:1095-1099`
    is the **MessageBubble menu's** `isTranscriptBusy:` pass-through, already
    correct since #278; it has no `isStreaming` sibling. **The door is not in
    `ChatScreen.swift` at all** — it lives in
    `Talaria/Features/Chat/ChatInputBar.swift` at **two** sites, `actionButton`
    (`:479`) and the hardware-keyboard `.onKeyPress` (`:152`), both reading the
    `isStreaming` **prop** fed at `ChatScreen.swift:291`. Grepping only
    `ChatScreen.swift` (as this line instructs) cannot find either. See #315's
    entry for the full verified anchor list; the other line numbers in §1/§4
    had drifted too (`:2076-2078`/`:2267` → `ChatStore.swift:2285`;
    `:2172-2178` → `:2188-2199`).

## 2. Fix shape (the entry's own, one clause)

Render the queue door on **`isTranscriptBusy`** — C2 applied to the DOOR, not
only the fire gate. A mid-reconcile commit then becomes a HOLD, and #306's
row-3 semantics (hold until terminal + reconcile adoption, then fire once)
do the rest. No new machinery.

## 3. Bars — copy into #315's entry before the run

- **315-A (unit, RED→GREEN):** state = reconcile window
  (`streamingMessageID = nil`, live `pendingRun`); the composer path resolves
  to QUEUE/HOLD, not plain send. RED first on unmodified HEAD (today it
  resolves to send).
- **315-B (unit):** a held turn committed during the window fires exactly
  once, only after the reconcile adopts — reuse bar 306-E's fixture
  (`livePendingRunBlocksFireAndDrainUntilReconcileAdopts`) extended to enter
  through the DOOR; the #307 mechanism must not fire through the new path.
- **315-C (no-regression):** idle transcript (`isTranscriptBusy == false`) →
  plain Send unchanged; streaming (`isStreaming == true`) → door unchanged.
- **315-D:** `GATE: PASS`, counts MOVED.

## 4. Traps

- **`refreshDirectHealth` stays `!isStreaming` — DELIBERATE** (#307's amended
  resolution, `ChatStore.swift:2172-2178`): tightening the PROBE would paint
  connectivity surfaces online-unprobed for the whole window. This lane
  touches the door only. Do not "fix" the probe guard again.
- Slash commands and empty content bypass the queue path
  (`queueComposedMessage`'s guard) — keep that; the door change must not
  swallow `/commands` into holds.
- Attachment turns don't queue (v1 limit, #314) — the door change must leave
  the attachment path's existing behaviour alone; note what it does in the
  window and record it, don't redesign it here.

## 5. Owen's to decide

Nothing pre-registered. If the door turns out to have more than one render
site (e.g. hardware-keyboard send), report the count before widening scope.
