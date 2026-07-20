# FABLE-T27-135 — Refresh stale template UITests for the no-pairing-wall world

**Item:** OPEN_ITEMS #135. **Branch:** `claude/fable-t27-135-uitests-refresh`.

## Problem

`AppTemplateUITests.swift` (`TalariaUITests` class, July-5 vintage) predates the #31
no-pairing-wall redesign — every test opens expecting `Enter Code Manually` as the landing
state, which no longer exists. They had NEVER run (target wasn't in the test scheme) until the
#120 E2E-guard lane added it 2026-07-18, surfacing all five failing at once. Currently skipped
at the scheme level (`project.yml` → `skippedTests: [TalariaUITests]`), not deleted.
`MessageIdentityUITests` and `TalariaUITestsLaunchTests` stay active in the gate.

## Fix

Rewrite the five `TalariaUITests` flows against current reality, then un-skip:

1. **Landing state:** first launch lands in MainTabView/chat backed by the local brain — no
   pairing wall. Assert the chat surface, not a code-entry screen.
2. **Pairing entry point moved:** Settings → System → "Connect Hermes Desktop" (#31), not
   onboarding-first. `completePairing` must navigate there.
3. **Known-stale locator:** GlowButton uppercases its title into the a11y label — `CONTINUE`,
   not `Continue` (verified via hierarchy dump 2026-07-18). Audit ALL button locators in the
   file for the same casing trap, not just the one known instance.
4. **Keep and reuse the mock scaffolding** — it is explicitly worth keeping:
   `UITEST_PAIRING_MODE=mock`, `MockPairingService`, the
   `/tmp/hermesmobile-uitest-config.json` external config.
5. **Flows to cover (refresh the original five in current shape):** standalone first launch →
   chat reachable; mock pairing via the Settings entry point; chat send; paired relaunch
   (skip-path); disconnect returns cleanly to standalone (wall gone).
6. Remove `TalariaUITests` from `skippedTests` in `project.yml` once green.

## Constraints (standing)

- File-scoped commits; merge commits only.
- **OPEN_ITEMS.md edits in a SEPARATE commit.**
- `project.yml` change (`skippedTests` removal) requires `xcodegen generate` in its own commit;
  **re-verify `aps-environment: development` survives the regen.** Same if any test file is
  added/removed.
- UI tests run on the standard sim: `47F68496-24F9-45D9-93D3-1C778DB6B557`,
  `CODE_SIGNING_ALLOWED=NO`. Note the HealthKit harness trap: unsigned sim builds strip
  entitlements — do NOT assert on HealthKit auth outcomes in UI tests.
- Swift Testing vs XCTest reporting: grep the right summary lines when validating locally.

## DoD

- All five refreshed `TalariaUITests` green on the standard sim, un-skipped in the scheme.
- Existing `MessageIdentityUITests` + `TalariaUITestsLaunchTests` still green.
- Full unit suite unaffected.
