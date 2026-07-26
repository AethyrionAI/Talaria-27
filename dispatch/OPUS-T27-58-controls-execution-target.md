# OPUS-T27-58 — Control Center controls have never once executed

**Items:** OPEN_ITEMS #58 (likely subsumes #179) · **Repo:** AethyrionAI/Talaria-27 · **Base:** main
**Branch:** `claude/t27-58-controls-execution-target` · **Toolchain:** Xcode-beta4, pinned sim
**Baseline:** confirm the current green count before you start · `export GH_PAGER=cat` first

## The observation

**Device pass 2026-07-25 — every tap fails, ~6–11 ms in**, with the OS naming the reason:

```
openAppWhenRun is not supported in extensions   (Code 2001)
```

`perform()` has **never executed**. The app-group handoff built under #58 option (a) has therefore
never been exercised end to end, and **#179** ("first tap is swallowed") is almost certainly the same
thing seen from outside — no tap has ever landed, so "first" and "every" are indistinguishable.

**The suite is green on a dead feature.** `HermesControlsTests.swift:28` asserts
`openAppWhenRun == true` — a static constant the OS rejects at dispatch. The test pins the
declaration, not the behavior. **Fixing that test is part of this lane**, not an afterthought: a test
that cannot fail when the feature is dead is worse than no test.

## Direction

Adopt `allowedExecutionTargets = .main` plus `supportedModes` (IntentModes). Both are available at
our deployment target — `project.yml:6–7` sets `deploymentTarget.iOS: "27.0"`, so no `#available`
guards are needed. **Verify that against the SDK rather than trusting this line**; "right answer,
wrong method" is still a coin flip.

**Confirm before you build.** This is a confirm-then-fix lane. Establish that `.main` execution
actually delivers the tap to the app process on this SDK before restructuring anything around it.

## The prize, if it holds

`ControlHandoffStore` exists to shuttle intent across the app-group boundary *because* the control
could not open the app directly. If `.main` execution puts `perform()` in the app process, that
indirection may become unnecessary. **Removing it is in scope if and only if it becomes genuinely
dead** — do not keep a shim alive out of caution, and do not delete it if anything else reads it.
Check for other readers first and say what you found.

Note `a62503f` ("the controls hand off a destination, not a URL iOS won't open") already reworked the
handoff payload. Read it before deciding what is load-bearing.

## Definition of done

- A Control Center tap reaches `perform()` — proven by something other than the absence of an error.
- The control performs its action end to end from Control Center **and** from the Lock Screen.
- `HermesControlsTests` asserts something that would **fail** if controls stopped dispatching. If that
  cannot be tested off-device, say so plainly and delete the misleading assertion rather than leaving
  a green test on a dead path.
- **#179 resolved or explicitly separated** — if the first tap still behaves differently once controls
  dispatch, it survives as its own item; if not, close it against this lane.
- Device verification is **owed by Owen**; state in the PR body what to check.

## House rules

Merge commits only, never squash. File-scoped commits. **OPEN_ITEMS.md edits in their own separate
commit.** This lane touches the widget extension — `xcodegen generate` will be needed if files are
added or removed; keep the pbxproj regen as its own commit and **verify `aps-environment:
development` survived** afterwards.
