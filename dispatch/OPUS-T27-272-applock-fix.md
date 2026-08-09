# DISPATCH — #272 App Lock re-prompt loop: THE FIX LANE

**Written 2026-08-09, the same sitting that met 272-C on device. Bars 272-E…H
are pre-registered in OPEN_ITEMS #272 — they are the contract; this brief is
the context that lets a cold session start without re-deriving anything.**

## The ruling you are implementing (do not re-litigate)

**Option B — one auto-prompt per locked stretch.** Owen ruled 2026-08-09,
accepting the recommendation **with a recorded reservation** ("feels very
'whoosh'"). Consequences of that reservation, binding on this lane:

- Bar **272-H** (device, Owen's hand) is the reservation's exit — if the fixed
  behaviour feels wrong on the phone, the ruling REOPENS. Do not argue with
  the bar.
- The plain-behaviour contract already given to Owen, which the fix must
  match exactly:
  1. Fresh lock → Face ID auto-prompts **once** (unchanged from today).
  2. Cancel → the sheet **stays down**; the in-app UNLOCK button is the only
     path, and it must work.
  3. Successful unlock → next locked stretch auto-prompts again.
  4. Known accepted cost: after a cancel, however long ago, returning to the
     app never auto-prompts within that same locked stretch — one extra
     UNLOCK tap. This is deliberate ("cancel means cancel").

## The defect, in three lines (all verified — 272-A unit, 272-C device)

`AppLockController.scenePhaseChanged(to: .active)` clears
`didFailAuthentication` at `AppLockController.swift:110`, then calls
`autoAuthenticateIfNeeded()` at `:114`. The auto-auth's fourth guard
(`!didFailAuthentication`, `:210` — *"retry button is showing"*) is the
correct design already in the file; it never executes because its input is
destroyed upstream **in the same call** (device ladder: the clear and the
re-fire share a millisecond timestamp on every rung; `attempt=` reached 4 in
~7 s; only `guard=phase(background)` ended it).

## The fix shape

1. **Reset `episodeAttempt` when the cover NEWLY locks** (transition into
   `.locked` from any not-locked cover state). It already survives
   foregrounds; today it resets only on success (`:157`) and lock-disable
   (`:122`). Find the transition where `refreshCover()` (or the machine)
   moves cover → `.locked`; do NOT reset on every `refreshCover()` call.
2. **Guard `autoAuthenticateIfNeeded()` on `episodeAttempt == 0`** — a fifth
   sequential guard in the same split style 272-B established (each guard
   logs its name; follow the pattern so the device log names the block).
3. **Leave the `:110` clear alone unless a test forces otherwise** — with the
   new guard it no longer fuels the loop, and touching it risks the 272-D
   cases this lane is forbidden to edit.
4. The UNLOCK button's own path (`AppLockOverlayView.swift:87`, its
   independent `Task { await requestUnlock() }`) must remain guard-free —
   the user's tap always gets an attempt.

## Traps, from the sessions that came before you

- **Every existing controller test drives `requestUnlock()` directly** — none
  exercises the `scenePhaseChanged → autoAuth` loop (the 272-A result block
  documents this, including why `MockAppLockAuthenticator`'s synchronous
  return makes the interleaving structurally inexpressible). 272-E exists
  because of this; use the `GatedAppLockAuthenticator` from
  `TalariaTests/AppLockControllerRaceTests.swift`, which parks inside
  `authenticate(reason:)`.
- **272-D's two named cases must show ZERO DIFF**, not merely stay green.
- **Release build check is part of the gate** (`scripts/mac/lane-gate.sh`) —
  and remember `xcodegen generate` after any file add, plus the known scheme
  churn (revert `BuildableName` drift by hand, see
  `handoffs/NEEDS-OWEN-2026-08-09-BACKLOG-RUN.md` §xcodegen).
- **272-H's log read**: the app is hand-launched for the device trial, so use
  `sudo /usr/bin/log collect --device-udid 00008150-000E794C3C47801C` (Owen
  pastes; hardware UDID, not the CoreDevice UUID) and grep `AppLock`. Today's
  failing signature is the paired lines
  `didFailAuthentication true->false on .active` + `autoAuth FIRED (no tap)`
  sharing a timestamp; the fixed build must show the new guard's BLOCKED line
  there instead.
- **#302 is adjacent, NOT this lane's scope**: a Control Center voice launch
  starts ~650 ms before App Lock evaluates its cover. It composes with #272
  (the unbounded locked interval was its worst case); fixing the loop
  changes #302's exposure, so note in the PR body that 302-B's "locked
  interval held open" fixture gets harder after this merges — someone should
  re-read #302's bars then. Do not fix #302 here.

## Evidence pointers

- OPEN_ITEMS #272 — 272-A/B result block (unit repro, five interleavings),
  272-C block (device ladder, both grace settings, severity statement), the
  ruling + bars 272-E…H.
- Device archive from 272-C: session-scratchpad `applock-272.logarchive`
  (session-local; the ladder is quoted in the entry).
- `dispatch/DEVICE-PASS-RUNNING-LIST.md` §R4 — the trial procedure 272-H
  repeats.
