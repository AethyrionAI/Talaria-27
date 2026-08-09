# OPUS T27 #272 — App Lock re-prompt loop: the no-device prerequisite

**Item:** #272 (`OPEN_ITEMS.md:6783`), CRITICAL, unreproduced since
2026-07-25. **Goal of THIS dispatch:** rule #252 in or out as named in the
entry, read the actual state-machine code the entry only pointed at, and spec
(a) a no-device unit reproduction attempt, (b) instrumentation that makes
Owen's next accidental repro cheap to read, and (c) bars for #272 itself.
**Not done here: no diagnosis is claimed complete, no fix is proposed, no
code is written.**

---

## 1. Verified state

### 1a. #252 is RULED OUT as a code cause — VERIFIED by exhaustive git history, not inferred

The entry (`OPEN_ITEMS.md:6810-6818`) says #252's build history records
*"App Lock grace segments — parity gap caught by review, live-verified"* as a
mid-lane fix, and that this has *"never been checked against this specific
symptom."* I checked it.

The claim's source, quoted in full context:
`handoffs/HANDOFF-2026-08-05-T27-BIG-DAY.md:50-58`:
> *"Full SDD lane: 10 tasks, per-task reviews, one mid-lane fix round (App
> Lock grace segments — parity gap caught by review, live-verified)…"*

**Every commit that ever touched App Lock code, full history, not scoped to
any date range:**
```bash
git log --oneline -- Talaria/Core/AppLock/ Talaria/Services/Support/AppLockCore.swift
```
```
baff8fa feat(#124): scene-level lock cover window + AppEntry wiring
3108de7 feat(#124): AppLockController + fresh-LAContext authenticator, capability degradation
02a1e3f feat(#124): AppLockCore — pure lock-state machine + grace/cover matrix tests
```
Three commits, all dated **2026-07-19**, all from #124's original build — six
days before Owen's 2026-07-25 report — and **nothing since**. #252 (PR #267,
merged 2026-08-05) touches none of them.

**Every commit that ever touched the App Lock *section* of
`PrivacySettingsScreen.swift` (the grace-period segmented control the claim
names):**
```bash
git log --oneline -- Talaria/Features/Settings/PrivacySettingsScreen.swift
```
```
64f11f1 feat(#260): privacy legibility …
f8badf7 feat(#252): SubsystemHero + per-page heroes
dce6042 feat(#252): embedded presentation mode on eight sub-screens
048253b #238 T7: Notifications settings screen deleted …
6f166c6 #193: destructive confirmations move to .alert …
2c545c5 feat(#137): Sensor Streaming opt-in section …
c8aca04 feat(#124): Privacy → App Lock section (adaptive label, grace picker) …
```
I diffed the two #252 commits (`f8badf7`, `dce6042`) against this file
directly:
```bash
git show dce6042 -- '**/PrivacySettingsScreen.swift'   # adds an `embedded: Bool` flag, wraps the
                                                          # background/header in `if !embedded`
git show f8badf7 -- '**/PrivacySettingsScreen.swift'   # adds a SubsystemHero block for deck mode
```
Both touch only the top of `body` (roughly lines 14–95: the background,
header, and a new hero view). The App Lock section itself — `appLockSection`,
`graceSegment(_:)`, the `ForEach(AppLockGracePeriod.allCases…)` loop — lives
at **`PrivacySettingsScreen.swift:475-556`**, untouched by either commit
(confirmed by reading the diffs' line ranges, not by grepping for a keyword).
`64f11f1` (#260) and the other three commits above are each independently
confirmed unrelated by subject (notifications, dialogs, sensor streaming,
privacy-legibility copy on other rows) and by a direct grep for `appLock`/
`App Lock` in their diffs, which returns nothing.

**Conclusion, VERIFIED: no commit, ever, has changed App Lock's state
machine, controller, overlay view, or its Settings UI section, before OR
after Owen's 2026-07-25 report.** Whatever "mid-lane fix … live-verified"
refers to, it left no diff on this surface — most plausibly the #252 review
was checking that the *existing, unmodified* App Lock section still rendered
and was reachable inside the new embedded/deck presentation (a layout
question, `embedded: Bool` was the actual code change that week, and it
changes header/background chrome, not App Lock), not fixing App Lock
behavior. **#252 is ruled OUT as a cause, a mask, or an interaction. #272 is
best treated as pre-existing since #124's original 2026-07-19 build,
unrelated to any later lane.** This closes the entry's own open question
without needing a device.

### 1b. The suspect mechanism — a hypothesis grounded in the code, not yet reproduced

Full files read: `Talaria/Services/Support/AppLockCore.swift` (152 lines, the
pure state machine + capability types), `Talaria/Core/AppLock/AppLockController.swift`
(144 lines, the `@Observable` orchestrator), `Talaria/Core/AppLock/AppLockOverlayView.swift`
(110 lines, the UIWindow presenter + SwiftUI overlay). Wiring:
`Talaria/AppEntry.swift:100-103,157-160`.

**The wiring, verbatim (`AppEntry.swift:157-160`):**
```swift
.onChange(of: scenePhase) { _, newPhase in
    appLock.scenePhaseChanged(to: AppLockScenePhase(newPhase))
    ...
```
Every SwiftUI `scenePhase` delivery calls `AppLockController.scenePhaseChanged(to:)`
directly, synchronously, on the MainActor.

**`AppLockController.scenePhaseChanged(to:)` (`AppLockController.swift:46-55`):**
```swift
func scenePhaseChanged(to phase: AppLockScenePhase) {
    if phase == .active {
        refreshCapability()
        didFailAuthentication = false          // <-- unconditional reset, every foreground
    }
    machine.scenePhaseChanged(to: phase, configuration: effectiveConfiguration(), now: now())
    refreshCover()
    autoAuthenticateIfNeeded()
}
```

**`autoAuthenticateIfNeeded()` (`:102-106`), the ONLY anti-loop guard in the
class, and the class's own doc comment's promise:**
```swift
/// First foregrounding of a lock episode prompts without a tap; a failed
/// or cancelled attempt drops to the retry button (no prompt loop).
private func autoAuthenticateIfNeeded() {
    guard cover == .locked, machine.phase == .active,
          !isAuthenticating, !didFailAuthentication else { return }
    Task { await requestUnlock() }
}
```

**`requestUnlock()` (`:66-79`):**
```swift
func requestUnlock() async {
    guard machine.isLocked, effectiveConfiguration().isEnabled, !isAuthenticating else { return }
    isAuthenticating = true
    defer { isAuthenticating = false }
    let unlocked = await authenticator.authenticate(reason: "Unlock Talaria")
    if unlocked {
        machine.authenticationSucceeded()
        didFailAuthentication = false
    } else {
        didFailAuthentication = true
    }
    refreshCover()
}
```

**The hypothesis, stated precisely.** The "no prompt loop" guarantee the
class's own comment promises rests entirely on `didFailAuthentication`
staying `true` after a failed/interrupted attempt, so a subsequent
`autoAuthenticateIfNeeded()` call declines to re-fire. But
`scenePhaseChanged(to:)` **unconditionally clears `didFailAuthentication` on
every single `.active` delivery, before it re-checks whether to auto-fire in
the same call.** That reset is not scoped to "a fresh lock episode" — it
fires on *every* foreground event, including a foreground that happens while
a PRIOR unlock attempt from the *same* still-locked episode is still in
flight, or was just interrupted by exactly the kind of transition that
produced it.

Two concrete paths into a loop, neither requiring anything exotic:

1. **Interrupted-attempt path.** `.active` fires → auto-fires
   `requestUnlock()` → the system Face ID/passcode UI is presented while
   `await authenticator.authenticate(...)` is pending. If the app is
   backgrounded before that resolves (the user swipes home, or the OS itself
   delivers an `.inactive`/`.background` blip as part of presenting the
   system sheet — both are ordinary iOS behavior, not edge cases), the
   pending `evaluatePolicy` call is cancelled by the OS and resolves to
   `false` (`AppLockController.swift:133-142`, `catch { return false }`).
   `requestUnlock()` sets `didFailAuthentication = true`. But the very next
   `.active` delivery (re-foregrounding) resets it to `false` again, at the
   TOP of `scenePhaseChanged`, **before** `autoAuthenticateIfNeeded()` runs
   later in the same function — so the guard that is supposed to say "we
   already tried and failed this episode, wait for a tap" never gets a
   chance to hold. A fresh `Task { await requestUnlock() }` fires again,
   presenting the system prompt again. Repeat under background/foreground
   churn and the symptom is exactly Owen's: *"continually tries to unlock
   and won't stay stagnant on the app-provided unlock prompt."*
2. **TOCTOU on `isAuthenticating`.** `autoAuthenticateIfNeeded()`'s guard
   checks `!isAuthenticating`, but `isAuthenticating = true` is only set
   **inside** the spawned `Task`'s body, at its first line — not
   synchronously at the `Task { … }` call site. An unstructured `Task`
   spawned from MainActor-isolated code is not guaranteed to begin executing
   before the next MainActor work item runs (there is no ordering contract
   between "a freshly spawned Task" and "the next SwiftUI `onChange`
   delivery already queued on the same executor"). A second `.active`
   delivery arriving in that gap would see `isAuthenticating == false` and
   spawn a SECOND `requestUnlock()` — two concurrent fresh `LAContext`
   evaluations (the class deliberately uses "a FRESH `LAContext` per attempt,"
   `AppLockController.swift:109-110`, so nothing here dedupes them), which
   is a very plausible reading of "gives the system/faceid stuff" repeatedly
   without a single stable prompt to interact with.

Both paths are hypotheses from reading the code, **not confirmed by
reproduction.** They are not mutually exclusive and may compound. Framed this
way because the entry explicitly asks for exactly this: *"the obvious place a
re-entrant unlock could re-arm itself before the prior attempt's result is
consumed"* — this section names the specific lines, not just the file.

### 1c. The suite cannot see either path — VERIFIED, not assumed

`TalariaTests/AppLockTests.swift` (282 lines) has real coverage of the pure
state machine (`AppLockStateMachineTests`, incl. `lockSurvivesRepeatedForegrounding`
at line 100) and of `AppLockController` in isolation
(`AppLockControllerTests`, lines 184-258). But **every controller test calls
`requestUnlock()` directly and awaits it** (`controller.scenePhaseChanged(to: .active); await controller.requestUnlock()`
— see `successfulUnlockClearsCover`, `failedUnlockKeepsLockAndFlagsRetry`,
`retryAfterFailureUsesNewEvaluation`, all lines 203-230). **None of them ever
exercises the `autoAuthenticateIfNeeded()` → `Task { await requestUnlock() }`
path at all**, and none delivers a second `scenePhaseChanged` call while a
`requestUnlock()` is suspended mid-flight. The double `MockAppLockAuthenticator`
(`:172-181`) returns synchronously from `authenticate(reason:)` — there is no
way to park it, so the interleaving in §1b(2) is **structurally inexpressible
in the current suite**, the same shape CLAUDE.md's `[[task-value-not-cancellable]]`
memory and #285's `GatedSecureStore` precedent describe: *"every existing
conformer is SYNCHRONOUS under the hood… the interleaving was literally
inexpressible in a test until a gated double was built."* A fully green
`lane-gate.sh` run says nothing about this bug, by construction.

---

## 2. ⚠️ Tracker corrections

- **`OPEN_ITEMS.md:6810-6818` (#272's "Possible interaction" paragraph)**
  currently reads as an open question ("has never been checked… Rule it in
  or out before diagnosing blind"). §1a above answers it: **RULE OUT**, with
  the full commit list as evidence. Whoever opens the #272 lane should fold
  this ruling into the entry (not re-derive it) and move straight to §1b's
  hypothesis.
- No other stale claims found in #272's entry — it is otherwise accurate:
  genuinely unreproduced, genuinely never diagnosed, genuinely no bars filed
  yet.

---

## 3. Proposed bars (#272 says "Bars pre-register here before any code" — none exist yet)

**272-A (no-device, deterministic reproduction attempt).** Build a
`GatedAppLockAuthenticator` test double (same idiom as `GatedSecureStore` /
`GatedCronJobService` — park on a `withCheckedContinuation` inside
`authenticate(reason:)` instead of returning immediately). Drive
`AppLockController` through: `.active` (auto-fires, parks mid-`authenticate`)
→ a second `.active` delivered while parked → assert whether a second
`authenticate()` call fires (§1b-2) and/or whether `didFailAuthentication`
being reset mid-flight lets a THIRD auto-fire happen after the first
resolves failed (§1b-1). **This is falsifiable either way** — if the double
proves the guards hold under interleaving, §1b's hypothesis is refuted and
#272 needs a different mechanism, which is itself a real result worth
recording (same as #285's repro attempt, which was pre-registered to accept
"no RED reproduces" as a valid outcome).

**272-B (instrumentation lands regardless of 272-A's result).** See §4 — Owen's
next accidental repro must be legible from a log, not just felt.

**272-C (device repro, opportunistic — do NOT schedule a sitting for this
alone).** Per the entry's own status line, this bug has not been seen once in
15 days despite ordinary use; do not burn a dedicated device sitting chasing
it the way `dispatch/DEVICE-PASS-RUNNING-LIST.md` Group 4 already tried
("attempt repro of the #272 App Lock re-prompt loop (background/foreground
churn while the unlock prompt is up)"). Fold a **deliberate, harder-than-
ordinary attempt** — rapid background/foreground churn specifically WHILE the
Face ID sheet is visible, on both `.immediate` and a longer grace period — into
the NEXT sitting that is already touching Settings/Privacy, now that §4's
logging makes a hit legible without extra setup.

**272-D (regression guard).** Whatever fix eventually lands must not break the
seven existing `AppLockControllerTests`/`AppLockStateMachineTests` cases,
in particular `lockSurvivesRepeatedForegrounding` and
`retryAfterFailureUsesNewEvaluation` — both encode intentional repeat-tap
behavior that a naive "never reset `didFailAuthentication` on foreground" fix
could wrongly kill (a user who fixes their Face ID and returns SHOULD get a
fresh attempt eventually; the bug is about an attempt re-arming out from under
an *unconsumed* one, not about all repeats being wrong).

**Pre-registered response, per this project's own discipline:** if 272-A
cannot reproduce the loop even with a gated double parked at every plausible
interleaving point, record that as a real falsification of §1b's hypothesis
— do not force a patch onto an unconfirmed mechanism. The state machine has
other transitions (`.inactive` handling, `configurationChanged()`, the retry
button's own independent `Task { await controller.requestUnlock() }` at
`AppLockOverlayView.swift:87`) that a fresh pass might implicate instead.

---

## 4. Task breakdown — what a follow-up lane does, in order

1. **Fold §1a's ruling into #272's entry** (tracker correction, §2) — this
   needs no code and can happen in the same commit that opens the lane.
2. **Write `GatedAppLockAuthenticator`** in `TalariaTests/AppLockTests.swift`
   (or a new `AppLockControllerRaceTests.swift` if the existing file's
   `@MainActor struct AppLockControllerTests` layout doesn't suit a
   continuation-based double cleanly) — mirror `GatedSecureStore`'s shape:
   an `authenticate(reason:)` that suspends until the test explicitly
   resumes it, so the test controls exactly when the pending call resolves
   relative to a second `scenePhaseChanged` delivery.
3. **Run 272-A** against both hypothesized interleavings from §1b. Record
   RED/GREEN either way, same as #285's `RED-REPORT.md` convention — a
   passing (non-reproducing) result is evidence, not a null result.
4. **Instrumentation (272-B), regardless of 272-A's outcome.** Add a
   `Logger(subsystem: TalariaLog.subsystem, category: "AppLock")` (pattern
   already used by `TalariaPlatformLink`/`CronJobsStore`/etc.,
   `Talaria/Core/TalariaLog.swift:23`) and emit **always-on `.notice`** lines
   (not gated behind Verbose Logging — this is rare and diagnostic, and
   CLAUDE.md's own gotcha is that Console.app hides `.info` by default, so
   `.notice`+ with `privacy: .public` interpolations is the right level) at:
   - every `scenePhaseChanged(to:)` entry: old phase (track it) → new phase,
     with `isLocked`/`isAuthenticating`/`didFailAuthentication` BEFORE the
     function's own mutations;
   - the `didFailAuthentication = false` reset specifically, only when it is
     resetting a `true` (i.e., log "cleared a real failure/interruption flag
     on foreground" — a no-op reset from `false→false` is not interesting
     and would just add noise);
   - every `autoAuthenticateIfNeeded()` call: whether it fired or was
     blocked, and by which guard clause;
   - every `requestUnlock()` entry/exit: which branch (guard-declined /
     succeeded / failed), with an attempt counter scoped to the current
     lock episode (resets on `authenticationSucceeded()` or on the
     configuration being disabled) so a log grep instantly shows "3 attempts
     in 4 seconds" instead of requiring manual timestamp math.
   A single `grep AppLock` over a Console.app pull after Owen's next sighting
   should make the mechanism visible without needing to reproduce it live in
   front of a debugger.
5. **272-C** — fold into the next ordinary Settings/Privacy sitting per §3,
   not its own trip.
6. **Gate:** `scripts/mac/lane-gate.sh` (Debug + XCUITest + Release) before
   any PR, per CLAUDE.md's standing rule — background it, poll the log with
   an `until` loop, never arm a Monitor.

---

## 5. Traps

- **Don't mistake "no commit touched it" for "nothing about it could have
  changed."** #252 embedded `PrivacySettingsScreen` inside a `TabView` deck
  page (`dce6042`) — that changes the view's LIFECYCLE (appear/disappear
  timing as the deck pages swipe) even though it never touches the App Lock
  section's own code. If a future session wants to fully close the #252
  question rather than just rule out a direct code cause, the deck's
  `.task`/`.onAppear` timing under swipe navigation is a different, thinner
  thread worth naming — not investigated here because the entry asked about
  the grace-segment "fix" specifically, and that is answered.
- **A green gate proves nothing here (§1c).** Don't accept "the suite is
  green" as evidence against §1b without confirming a gated double was
  actually built and actually parked at the right point — the existing tests
  are all designed in a way that cannot see this class of bug.
- **Owen's 2026-07-25 wording didn't mention backgrounding explicitly** — he
  said the app "continually tries to unlock and won't stay stagnant," not
  "when I background and foreground it." §1b's path 2 (the TOCTOU race) can
  fire from `.active → .inactive → .active` blips alone (Control Center,
  certain system sheets, possibly the Face ID prompt's own presentation on
  some iOS versions) — don't narrow the repro attempt to background/
  foreground churn only; try inactive-only churn too.
- **This dispatch is not a diagnosis.** §1b is a hypothesis with named
  file:line evidence, explicitly not confirmed by reproduction. Do not let a
  future session's summary of this document upgrade "suspect mechanism" to
  "root cause" without 272-A actually running.

---

## 6. What is Owen's to decide

- Whether to open the #272 lane now (a no-device unit-reproduction attempt,
  §3/§4 steps 2-4) or continue waiting for a live sighting before spending
  the time — this dispatch argues the no-device half is cheap and
  self-contained regardless, but the call to spend a session on it is his.
- If 272-A reproduces the loop, the actual FIX shape (e.g., should
  `didFailAuthentication` survive a foreground event within the same lock
  episode until either success or an explicit user tap; should
  `autoAuthenticateIfNeeded` track "already attempted this episode"
  independent of the transient flag) is new work this dispatch does not
  spec — that is the next lane's plan, reviewed against 272-D's regression
  guard.

---

## 7. Close-out

This dispatch's job is done when a follow-up session can open the #272 lane
without re-deriving §1a (the #252 ruling) or re-reading the three App Lock
files cold. Nothing here edits `AppLockCore.swift`, `AppLockController.swift`,
`AppLockOverlayView.swift`, `PrivacySettingsScreen.swift`, or
`OPEN_ITEMS.md`. The lane that executes this brief should fold §2's
correction and §3's bars into #272's entry as its first commit, before any
test or production code.
