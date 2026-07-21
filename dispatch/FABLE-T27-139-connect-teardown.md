# FABLE-T27-139 — Voice connect teardown: no zombie sessions, honest connect outcomes

**Item:** OPEN_ITEMS #139 (🐛) · **Repo:** AethyrionAI/Talaria-27 · **Base:** main (≥ `b780b0b`)
**Branch:** `claude/t27-139-connect-teardown` · **Size:** small-medium, one PR
**Staleness check (2026-07-20):** only open PR is #128 (`probe/t27-130-halfduplex`), DO-NOT-MERGE probe touching `NativeVoicePipelineService.swift`. **Avoid that file entirely** — this lane's fix does not need it.

## The defect (device-confirmed 2026-07-20, mechanism source-confirmed)

User starts a voice session against a slow host → overlay shows ESTABLISHING LINK → user
gives up and dismisses. Minutes later the session comes ALIVE — audio + live mic — while the
user is elsewhere in the app. Privacy-grade defect.

**Mechanism (read, not guessed):**
- `TalkStore.startSessionDirectly()` (Stores/TalkStore.swift:68) sets
  `connectionState = .connecting` then `await voiceService.startSession()` INLINE. During a
  slow connect this await is in flight and `isSessionActive` is still **false** — it only
  becomes true when `applySnapshot` runs after the await returns (and via the snapshot
  handler at ~line 190).
- `VoiceOverlayScreen.onDisappear` (Features/Talk/VoiceOverlayScreen.swift:91) guards
  teardown behind `if talkStore.isSessionActive` — so dismissal during the connect window
  schedules NOTHING.
- When the slow `startSession()` finally returns, `applySnapshot` flips the store live and
  `liveActivity.startVoiceSession()` fires. Zombie complete.
- `endSessionIfNeeded()` (line ~133) has the same `guard isSessionActive` hole.

## Deliverables

### D1 — Session intent generation (the core fix)
`TalkStore` gains a monotonic **session generation** (`private var sessionGeneration: Int`).
- Every start path (`startSession`, `startSessionDirectly`) increments and captures the
  generation BEFORE awaiting the service.
- New `abandonSession()` — callable regardless of `isSessionActive` — increments the
  generation (revoking any in-flight connect) and, if the service reports an
  active/connecting session, awaits `voiceService.endSession()`.
- After the awaited `voiceService.startSession()` returns, compare captured vs current
  generation. **Stale → immediately `await voiceService.endSession()`, discard the
  snapshot, never flip live state, never start the Live Activity.** This closes the zombie
  even if the underlying RPC cannot be cancelled mid-flight.
- `endSessionIfNeeded()` also bumps the generation so it kills in-flight connects, not just
  live sessions.

### D2 — Overlay dismissal uses intent, not liveness
`VoiceOverlayScreen.onDisappear`: replace the `isSessionActive` guard with the intent path —
dismissal (after the existing 500ms camera-transient hedge, which MUST keep working: camera
fullScreenCover re-present case, see in-file comment) calls `abandonSession()` when the
overlay is truly gone, covering `.connecting` as well as connected. Do not shorten or remove
the camera hedge.

### D3 — Connect timeout with an honest outcome
Race the connect against a **12s** timeout (constant, named, one place). Implement the
decision as a pure function so it's TDD-able:

```
enum ConnectOutcome { case connected, timedOut, failed(Error) }
struct ConnectOutcomeRule {
    static func outcome(elapsed: Duration, limit: Duration, result: Result<Void,Error>?) -> ConnectOutcome
}
```

- On `timedOut`: bump the generation, `await voiceService.endSession()` (belt and
  suspenders), set an honest terminal state — overlay shows an actionable line in the
  standardized preflight wording family (#84 precedent), e.g. "VOICE HOST UNREACHABLE —
  CHECK UPLINK OR TRY THE LOCAL ENGINE". No silent retry loop, no eternal
  ESTABLISHING LINK.
- Timeout applies to the connect phase ONLY. Do not add mid-session watchdogs.

### D4 — Engine truth on fallback (minimal scope)
The session snapshot already carries the actual engine (`voiceEngine = snapshot.engine`
feeds the LOCAL VOICE badge). The lie is silence about the FALLBACK itself:
- When the session lands on a different engine than the profile's configured/preferred one,
  surface it ONCE in-session (transient line or badge accent in the overlay status area):
  "REALTIME UNAVAILABLE — LOCAL ENGINE". Log a `.notice` naming configured vs actual.
- Voice Settings engine row: display configured engine AND last-actual when they differ
  (one-line change if the row already binds `voiceEngine`; keep it small).
- OUT OF SCOPE: per-host availability matrix in settings, connect-latency fixes on the host,
  #138 echo work.

## Constraints (non-negotiable)
- **Do NOT touch `NativeVoicePipelineService.swift`** (open probe PR #128 owns that surface;
  also the #128-item tap invariant lives there). The fix lives in `TalkStore.swift`,
  `VoiceOverlayScreen.swift`, and — only if connect cancellation-cooperation is added —
  `LiveVoiceSessionService.swift` await points (audit; add `Task.checkCancellation()` at
  natural seams if you wrap the connect in a child Task; if the RPC is not cancellable, the
  D1 generation check alone is acceptable and preferred for size).
- **Audio law (#106):** no AVAudioSession management changes anywhere;
  `didActivateAudioSession` and `SpeechOutputService` untouched.
- **CarPlay (#19/#118):** `CarPlayVoiceManager` uses the same store. CarPlay sessions run
  backgrounded BY DESIGN — dismissal semantics are overlay-scoped; do not wire
  scene/background events into `abandonSession()`. Verify CarPlay start still works by
  reading its call sites; do not change them.
- Swift 6: if you need an observer/closure hop, use the repo's established patterns
  (selector-based observers; unstructured Task + @MainActor accumulator — see Lane M notes).
- Tests: pure rules first, RED before GREEN — generation-staleness decision (start returns
  after abandon → discarded; after re-start → only newest wins), `ConnectOutcomeRule`
  boundary cases, endSessionIfNeeded-kills-connecting. Ride existing test files where
  sensible; new files require an `xcodegen generate` regen as its OWN commit (verify
  `aps-environment` survives — #44/#48 trap).
- **File-scoped commits. Do NOT edit OPEN_ITEMS.md in this lane** — the write-back happens
  in the merge loop, separately. (Repeat guidance; it has been mixed into feature commits
  before.)
- Merge via the standard loop: PR against main, merge commit only (never squash).

## Definition of done (device, Owen)
1. Start a session (settings-origin AND composer-origin) → dismiss during
   ESTABLISHING LINK → session NEVER resurrects: no later audio, no Live Activity, mic
   indicator never lights. Repeat against the slow host (Mac profile).
2. Unreachable/slow host → honest failure line at ≤12s, no eternal ESTABLISHING LINK.
3. Fallback session states its engine truthfully (overlay line + settings row).
4. Fast-connect happy path unchanged; camera overlay transient still does not kill the
   session; CarPlay session start unaffected.

## Report back
PR body: files touched, test names with red→green evidence, any deviation from D1–D4 with
rationale, and explicitly whether `LiveVoiceSessionService` connect was made
cancellation-cooperative or left to the generation check.
