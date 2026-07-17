# FABLE T27-118-119 — Voice residuals lane (Lane V)

**Repo:** `AethyrionAI/Talaria-27` · **Branch prefix:** `claude/t27-lane-v-*`
**Dispatch date:** 2026-07-17 · **Tracks:** OPEN_ITEMS #118, #119 + async-session rider
**Size:** one PR, three tightly-related fixes on the voice session surface.
**Toolchain:** Xcode-beta3 (`DEVELOPER_DIR=/Applications/Xcode-beta3.app/Contents/Developer`).
**Baseline to beat:** 755 tests / 62 suites (main @ `588d885`).

Context that must survive into the implementation: PR #106 just ended the
five-day voice wedge, whose root cause was audio-session ownership violations
(read-aloud deactivating a session it didn't activate). **The prime directive
for this lane: one owner per audio session; release only what you activated;
never touch the session from a surface that doesn't own it.** Every change
below is judged against that rule.

## Fix 1 — #118: capture stays live after leaving the app (PRIVACY)

Observed on the #82 device-confirm run: background the app mid/post voice
session → the system mic-in-use indicator stays lit. The capture chain isn't
torn down on scene-phase change.

- Add a background hook to the voice session lifecycle: on
  `didEnterBackground` (or scene-phase `.background`) while a native voice
  session is active → end the session cleanly (same path as the user tapping
  end: stop capture, stop TTS, release the session, update TalkStore state).
  There is NO intentional background-audio mode in this app today — leaving
  the app means the session is over.
- Beware Swift 6 region isolation: block-based `NotificationCenter.addObserver`
  is a known landmine in this codebase — use the selector-based observer or a
  `@Sendable`-annotated path (house learning; BGTask handlers hit
  `dispatch_assert_queue_fail` without it).
- The realtime engine (`LiveVoiceSessionService`) needs the same audit — if it
  also survives backgrounding, fix it the same way; if it already tears down,
  say so in the PR and leave it alone.
- Test: a decision-function test pinning "session active + background event →
  teardown requested". Keep the decision pure so it's cloud-testable.

## Fix 2 — #119a: 'Cancellation failed: no active response found' banner

A barge-in/cancel racing an already-completed response bubbles the backend
error string into the session UI. A no-op cancel is a NORMAL race, not an
error: catch that specific failure shape at the call site, log `.notice`,
swallow it. Every other cancel failure still surfaces. Test the classifier.

## Fix 3 — #119b: header stuck on 'VOICE LINK · CONNECTING'

Screenshot on file: full two-way conversation flowing while the header still
reads CONNECTING. The status label isn't tracking the session state machine
past the connect phase. Find where the header derives its string; bind it to
the live TalkStore/session state (connected / listening / speaking — whatever
states exist; do NOT invent new states). Likely the same screen as Fix 2.

## Rider — synchronous setActive on the main thread

Device logs show walls of `AVAudioSession_iOS.mm:978: This method can lead to
UI unresponsiveness if called on the main thread. Consider using the
asynchronous activate/deactivate API`. Post-#106 the CALL SITES are correct in
ownership terms — this rider is about mechanics only:
- Migrate the session activate/deactivate calls in the voice path
  (`NativeVoicePipelineService`, `SpeechOutputService`, `LiveSpeechService`,
  `LiveVoiceSessionService`) to the async API or off-main execution, WITHOUT
  changing ownership, ordering, or the #106 `didActivateAudioSession` gate.
- If reordering risk appears anywhere (activation must complete before engine
  start), keep the await sequencing explicit. If any site can't migrate
  safely, leave it and note why — this rider must not destabilize the
  just-fixed pipeline. Mechanical change, no behavior tests expected beyond
  the existing suite staying green.

## Constraints (house)

- File-scoped commits; no `OPEN_ITEMS.md` edits in feature commits.
- `xcodegen generate` only if files add/remove (a new test file will —
  separate regen commit; verify `aps-environment: development` survives in
  `Talaria/Talaria.entitlements`).
- Do not touch the #106 gate logic, the #105 churn guards, or capture config.

## Acceptance

- Suite green ≥ baseline; new decision tests for Fix 1 + Fix 2.
- PR body lists the device checks for Owen: (1) start voice session →
  background the app → mic indicator goes OFF within a beat; (2) barge-in
  after a reply finishes → no banner; (3) header tracks state through a full
  conversation; (4) the setActive main-thread warning wall is gone or greatly
  reduced in Console.
