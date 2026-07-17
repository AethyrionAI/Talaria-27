# FABLE T27-124 — Face ID app lock

**Repo:** `AethyrionAI/Talaria-27` · **Branch prefix:** `claude/t27-124-*`
**Dispatch date:** 2026-07-17 · **Tracks:** OPEN_ITEMS #124 (new) · **Size:** one PR, small
**Baseline:** 755/62 · **Toolchain:** Xcode-beta3.

## Why

Health data + location + an agent's conversation history in one app: a
biometric lock is table stakes for anything paid, and it SELLS the privacy
posture. Free-tier feature, off by default.

## The build

1. Settings toggle in `PrivacySettingsScreen` (exists): "Require Face ID" —
   LocalAuthentication, `.deviceOwnerAuthentication` policy (biometry WITH
   passcode fallback; never biometry-only, lockout bricks the app otherwise).
   Persist in `UserSettings`.
2. Lock overlay at the APP ROOT (scene level, above all navigation): shown on
   cold launch and on return-to-foreground after a grace period (immediate /
   1 min / 5 min — a sub-setting, default immediate). Blur/obscure content
   beneath; retry button on auth failure; no way around it except passcode
   fallback via the system sheet.
3. Privacy snapshot: set the scene's content hidden in the app switcher while
   locked (the standard `UIApplication` snapshot obscuring approach for the
   SwiftUI lifecycle — an opaque overlay driven by scenePhase `.inactive` is
   acceptable and simpler; state which was used and why).
4. Interactions that MUST survive a lock without breaking:
   - Incoming APNs/inbox: arrive normally; UI stays locked.
   - Live Activities and widgets: unaffected (they render outside the app).
   - App Intents (Ask Hermes from Siri/Shortcuts): **decision embedded — the
     intent path bypasses the UI lock (it has no UI) but any
     `OpenURLIntent`/deep-link landing INTO the app hits the lock first.**
     That is the correct shape; pin it with a comment.
   - Voice session in progress when backgrounded: Lane V (#118) already ends
     it; no interaction. If Lane V hasn't merged first, note the ordering.
5. `LAContext` per attempt (contexts are single-use); evaluate on a fresh
   context each retry; handle `biometryNotAvailable`/`notEnrolled` by hiding
   the toggle's biometry language and offering passcode-policy lock instead.

## Tests

Lock-state decision function pure + tested: scenePhase transitions × grace
period × toggle × auth result → show/hide/require matrix. No LAContext in
tests (protocol-mock the evaluator).

## Constraints & acceptance

- No new entitlements; add `NSFaceIDUsageDescription` to the Info.plist
  source (`project.yml` `info.properties` — the #58 lesson: INFOPLIST_KEY_*
  build settings are silently ignored with a generated plist; put it in
  project.yml).
- File-scoped commits; regen on file add; suite green ≥ 755/62.
- Device check (PR body): toggle on → background → reopen → Face ID prompt;
  fail twice → passcode fallback works; app switcher shows obscured snapshot;
  Siri ask works while locked, tapping its result lands on the lock.
