# FABLE-T27-133 — Dormant-relay push registration idempotency (+ AppEntry double-report rider)

**Item:** OPEN_ITEMS #133 (M-7 follow-up). **Branch:** `claude/fable-t27-133-push-idempotency`.
**Severity:** low (no user-visible bug) — payoff is launch-log readability (primary sensor-pipeline
diagnostic surface) and 5 relay writes → 2 per launch.

## Problem

One launch, zero user input, produces FIVE relay push registrations across a 2-profile config
(both legitimately paired):

```
registerPushToken: relay accepted push registration            (x2, active)
registerPushToken: dormant relay 'Mac Mini' accepted ...       (x3, dormant)
```

**Mechanism (source-confirmed, not hypothesised):**
`AppContainer.registerPushTokenWithActiveRelay` short-circuits when nothing changed:

```swift
if notificationService.isPushTokenRegistered,
   notificationService.currentPushToken == normalizedToken {
    sessionStore.state.pushTokenRegistered = true
    return
}
```

`registerPushTokenWithDormantRelays` has NO equivalent guard — it loops
`profilesStore.profiles where profile.id != activeProfileID` and POSTs unconditionally on every
call. Amplified by caller count: `registerStoredPushTokenIfNeeded()` has five call sites
(`AppContainer.swift` 1005, 1034, 1168, 1198, 1910) plus `AppEntry.swift:167` and the toggle in
`NotificationsSettingsScreen.swift:217`; none coordinate.

## Fix

1. **Mirror the active-relay short-circuit per dormant profile.** The per-profile state already
   exists and is already WRITTEN — `profileRelaySessions.markPushTokenRegistered(_:profileID:)`
   is called on the deactivate path — it is simply never READ as a guard. Before POSTing to a
   dormant profile, check its recorded token: same normalized token already registered → skip.
   Token changed or never registered → POST, then record.
2. **Re-registration must still work** after a relay-side registration wipe: keep whatever
   existing invalidation path clears the per-profile mark (profile unpair/re-pair, explicit
   Settings toggle) intact — the guard is "same token already acked", not "registered once ever".
3. **Rider (same launch path, trivial):** `AppEntry.swift` `.background` branch of the
   `scenePhase` `onChange` dispatches `reportAppStateIfNeeded("background")` TWICE — once in a
   bare `Task`, once at the head of the following `Task` that also calls
   `watchPendingRunIfNeeded()`. Edit artifact — drop the bare `Task`.

## NOT in scope (checked 2026-07-17 — do not chase)

- Doubled `app-refresh scheduled` + doubled health/location refresh in the same log are two
  legitimate lifecycle entries (background launch → foreground activation), not fan-out.
- Relay-side dedupe: server writes are idempotent; this is app-side hygiene only.
- **#24f is DEAD — do not cite it.** The relay is DB-backed; redundant POSTs are real writes,
  not a persistence workaround.

## Tests

Unit-test the guard decision (pure logic preferred: extract a small
`shouldRegisterDormant(profileToken:currentToken:) -> Bool` or equivalent if the guard is
otherwise untestable): same-token skip, changed-token re-register, never-registered register,
cleared-mark re-register. Assert the active-path behavior is unchanged.

## Constraints (standing)

- File-scoped commits; merge commits only.
- **OPEN_ITEMS.md edits in a SEPARATE commit** — never mixed into feature commits.
- No Swift files added/removed expected → no `xcodegen generate`; if you DO add a test file,
  regen in its own commit and re-verify `aps-environment: development` survives.

## DoD

- Fresh launch with 2 paired profiles logs at most one registration per profile per token change.
- Single `reportAppStateIfNeeded("background")` per backgrounding.
- Guard tests green; full suite green (baseline 675/56 pre-#121/#122; use current main).
- Device pass (Owen): launch log shows 2 registrations max, sensor pipeline unaffected.
