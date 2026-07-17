# FABLE T27-58 — Ask Hermes control inert: fix the launch wiring

**Repo:** `AethyrionAI/Talaria-27` · **Branch prefix:** `claude/t27-58-*`
**Dispatch date:** 2026-07-16 · **Tracks:** OPEN_ITEMS #58 (GitHub #7 remnant)
**Size:** micro-PR. One file plus tests. **Merged-PR check done 2026-07-16:**
no fix branch exists; the bug is live.

## The bug, fully localized

Device pass 2026-07-11: the Control Center "Ask Hermes" control does nothing.
Triage already split the stack: `hermes://` and `hermes://chat` open the app
fine from Safari (#77 verified in passing), so the scheme and
`AppEntry.handleDeeplink` route are innocent. The defect is inside
`TalariaWidgets/Controls/HermesControls.swift` (115 lines, the whole surface).

("Talk to Hermes" is ALSO inert but that is EXPECTED and excused — #82 audio
wedge. Do not chase it; fix both intents' wiring identically anyway since they
share the pattern.)

## Prime suspect (verified in source 2026-07-16)

Both extension-local intents (`OpenHermesChatIntent` :36, `OpenHermesVoiceIntent`
:62) combine:

- `static let openAppWhenRun = true`   (:43, :68)
- `perform()` → `.result(opensIntent: OpenURLIntent(destination))`  (:52-54)

That pair conflicts. Apple's sanctioned control-launches-app-to-URL shape is
`OpenURLIntent` returned from `perform()` **without** `openAppWhenRun` — the
OpenURLIntent itself is the launch. Setting both can silently no-op from
Control Center on current SDKs (symptom matches exactly: tap, nothing).

## The lane

1. **Instrument first** (stays in the fix, debug-only): `os.Logger` lines in
   both `perform()`s (subsystem `org.aethyrion.talaria27.widgets`) so Console
   can answer "did perform fire?" forever after. The extension has no other
   diagnostics.
2. **Fix:** drop `openAppWhenRun` from both intents (keep `isDiscoverable =
   false` and the doc comments — update the comments to explain WHY
   openAppWhenRun must stay absent, so it doesn't get "helpfully" re-added).
3. **Do not** rename `kind` strings (`org.aethyrion.talaria27.control.*`) —
   the system keys placed controls by them; a rename orphans Owen's placed
   controls.
4. **Do not** import app-target intents into the extension — the existing
   architecture comment explains the AppContainer drag; preserve it.

## Constraints (house)

- File-scoped commits; no OPEN_ITEMS edits; xcodegen only if files add/remove
  (none should).
- Cloud can't run Control Center: mark the PR device-verify-owed. The
  acceptance tap is Owen's: place the control, tap, app opens to chat with
  composer focused per `hermes://chat` semantics.

## Acceptance

- Both intents: `openAppWhenRun` gone, logging in, comments updated.
- Unit-testable slice: a test asserting the intents' static configuration
  (isDiscoverable false, no openAppWhenRun member — compile-level guarantee
  is enough; don't over-test AppIntents internals).
- Build green; PR notes the one-tap device check for Owen.
