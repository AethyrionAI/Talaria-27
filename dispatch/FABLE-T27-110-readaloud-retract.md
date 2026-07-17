# ⛔ ALREADY SHIPPED — DO NOT DISPATCH
# Merged to main before 2026-07-16 (see OPEN_ITEMS entry). Kept for the record.
# Dead-dispatch incident 2026-07-16: staleness passes MUST check merged-PR
# state (git log --grep / gh pr list) before refreshing any spec.

# FABLE T27-110 — Read-aloud stops on a retracted reply (#110)

**OPEN_ITEMS:** #110 (read-aloud speaks the collapsed loop)
**Branch prefix:** `claude/t27-110-`
**Cloud-safe:** client-only (ChatStore + SpeechOutputService). No relay/OJAMD/
device needed to design; a pure decision helper is the unit-test gate. The
audible confirmation itself is device-verify-owed.

## Objective

With auto read-aloud ON, a #102 degenerate-loop breaker trip rewrites the reply
bubble to ONE copy of the looped phrase — but the utterances already enqueued
during streaming still SPEAK the full run of copies. Eyes see the fixed
transcript; ears hear the loop the breaker just cut. Fix: when the finished
reply is SHORTER than what actually streamed, retract the pending speech
(`stop()`) instead of flushing the queue (`finishStream`) — a shorter finish
means content was retracted, so speaking the rest is wrong by construction.

## Grounding — read BEFORE designing

- `Talaria/Stores/ChatStore.swift:528 (POST-LANE-M 2026-07-16: drifted from :517 — the call is now `self.speechOutput?.finishStream(` at :528; SpeechOutputService exposes both stop() at :73 and finishStream() at :112)` — `self.speechOutput?.finishStream(messageID:)`
  in the stream-completion block (the exact site named in PR #83's write-up).
  During streaming, deltas are enqueued at :393 (`enqueueStreamChunk`); cancel
  paths are :534/:590/:607; hard stop is `speechOutput?.stop()` (:670/:692). The
  finished content in that block is `finalMessage.content`.
- `SpeechOutputService` (the `speechOutput` type, ChatStore:132) — concrete, NOT
  behind a protocol today, and there is NO mock. It owns the utterance queue, so
  it is the natural owner of "what was enqueued for this message."

## Deliverables

### 1. The retract decision (pure + tested — the acceptance core)
- A pure function — `shouldRetractSpeech(finishedContent:streamedText:) -> Bool`
  (finished shorter than streamed, whitespace-folded) — living where it is
  `@testable`. This is what the unit tests pin.

### 2. Wire it at the completion site
- At ChatStore:517, when the decision says retract → `speechOutput?.stop()` (drop
  the queued utterances for this reply); otherwise the existing
  `finishStream(messageID:)`. The streamed text must be available at the decision
  point — PREFER letting `SpeechOutputService` compare against its own enqueued
  text for `messageID` (pass `finishedContent` into `finishStream`), keeping
  ChatStore thin. Whichever seam, the DECISION stays the pure tested fn.

### 3. Testability seam (only if needed)
- If asserting stop()-vs-flush requires it, introduce a MINIMAL
  `SpeechOutputServiceProtocol` (enqueueStreamChunk / finishStream / cancelStream
  / stop) + a spy in tests. Keep it minimal — do NOT refactor the audio engine.

### 4. Tests (Swift Testing)
- Decision fn: finished < streamed → true (retract); finished == streamed →
  false; finished > streamed → false; empty finished + non-empty streamed → true;
  the #102 shape ("phrase phrase phrase" streamed, "phrase" finished) → true.
- If the spy seam lands: a completion with finished < streamed calls `stop()`,
  NOT `finishStream`; a normal finish (finished == streamed) calls `finishStream`.

## Hard constraints

- File-scoped to `ChatStore.swift` + `SpeechOutputService.swift` (+ a protocol/spy
  and a new test file if introduced). Do NOT touch the audio engine, the #102
  breaker itself, streaming, or any other completion semantics.
- The cancel/interrupt/failure paths (:534/:590/:607) are correct — leave them.
  Only the SUCCESS completion at :517 gains the retract branch.
- New file(s) ⇒ PR notes the Mac runs `xcodegen generate` + re-verifies
  `aps-environment` survives (#44/#48 trap).
- File-scoped commits; no `OPEN_ITEMS.md` edits; no pbxproj in feature commits.
- Cloud can't build: check any `SpeechOutputService` / AVSpeech API you touch
  against the iOS 27 SDK.

## Acceptance

- Decision fn covered by tests (all cases above); full suite green.
- Normal reply: read-aloud still speaks the whole thing (finishStream path
  unchanged). Breaker-shortened reply: the pending queue is dropped.
- Device-verify owed: with auto read-aloud ON, force a #102 trip → audio stops
  with the transcript instead of finishing the loop.
- PR titled `#110 — read-aloud stops on a retracted reply`.
