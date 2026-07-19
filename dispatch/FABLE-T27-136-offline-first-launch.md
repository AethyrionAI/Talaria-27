# FABLE-T27-136 — Offline-first launch: splash must not await relay/shim

**OPEN_ITEMS:** #136 · **Repo:** `AethyrionAI/Talaria-27` · **Branch prefix:** `claude/fable-t27-136-`

## The bug (device-caught 2026-07-19)

With the OJAMD relay (`:8000`) and models shim (`:8765`) services STOPPED but the machine UP,
the app sat on the `ESTABLISH UPLINK` splash for minutes. Windows Firewall silently DROPS
packets to listener-less ports (no TCP refusal), so every relay/shim request hangs the full
URLSession timeout (~60s, error `-1001`) instead of failing fast. `AppContainer.initialize()`
is serial and only sets `isInitialized = true` — the flag that drops the splash via
`shouldShowLaunchSplash` (AppContainer.swift ~147) — at the very end, after up to six
network-touching awaits back to back.

The existing #3/#46 degraded-mode hardening (comment block inside `initialize()`, ~line 998)
only covers relays that ANSWER (401, connection refused). It does not cover the black-hole
case. Do NOT remove that hardening — extend around it.

## Non-negotiables

1. **No relay or shim call on the splash critical path.** `isInitialized = true` flips after
   LOCAL-only work: `permissionsStore.reloadCapabilities()`, access-token guard,
   `chatStore.loadConversationIfNeeded()`, `sensorUploadService.start()` +
   `handleAppDidBecomeActive()`, `reconcileLiveActivities()`, `updateWidgetData()`,
   `drainShareInbox()`.
2. **Relay-backed init moves to a background task** launched from `initialize()`:
   `sessionStore.bootstrap()`, `pairingStore.validateRestoredIdentity()` (MUST still run
   after bootstrap, in order — #3/#46 reinstall-identity check), `hostStore.refresh()` +
   `lastKnownHostOnline` update, `inboxStore.loadInbox()`,
   `refreshCommandCatalog(force: true)`, `seedActiveModelFromShim()` fallback,
   `registerStoredPushTokenIfNeeded()`. State updates land live as each completes.
   Degraded is the DEFAULT launch posture; connectivity upgrades it.
3. **Keychain-local guards STAY on the critical path**: the `pairingStore.isPaired` guard, the
   `currentAccessToken() == nil → clearLocalPairing()` guard, and the double-init guard are
   local and cheap — unchanged, in place, before the flag flips.
4. **Short-timeout bootstrap session**: dedicated `URLSessionConfiguration` for the
   background-init probes with `timeoutIntervalForRequest ≈ 5s` (and a matching resource
   timeout), so even background init converges quickly against a black-holed host. Scope it
   to launch/bootstrap probes only — do NOT change timeouts on the chat SSE path (`:8642`)
   or on user-initiated requests.
5. **Idempotency + re-entry preserved**: re-pairing still re-runs `initialize()`; the
   background task must be single-flight (a second `initialize()` or foreground event while
   one is in flight must not double-run bootstrap); the two `isInitialized = false` reset
   sites (~1271, ~1847) must also cancel/supersede any in-flight background init.
6. **#123 share drain stays free-tier-safe**: `drainShareInbox()` remains on the critical
   path, before any relay-gated work, exactly as its comment demands.
7. **Freemium contract**: free tier = standalone on-device. Cold launch with ZERO hosts
   reachable must land on a fully functional app (chat via on-device brain, settings,
   sessions list from local store) in roughly splash-minimum time, not timeout time.

## Tests (Swift Testing unless the surface demands XCTest)

- Pure-logic: extract the "which init steps are local vs relay-backed" partition into a
  testable seam if needed; assert the critical path contains no network-touching step.
- Black-hole simulation: mock client whose relay calls suspend indefinitely (or 60s) —
  assert `isInitialized` flips without awaiting them, and that background completion
  updates `lastKnownHostOnline` / inbox / catalog state afterward.
- Single-flight: concurrent `initialize()` calls run bootstrap once.
- Reset races: `isInitialized = false` reset while background init in flight → no stale
  state lands after reset.
- Regression: existing #3/#46 degraded-mode tests stay green; `validateRestoredIdentity()`
  still ordered strictly after `bootstrap()`.

## Ground rules

- Merge-commit workflow; file-scoped commits.
- **Do NOT edit OPEN_ITEMS.md** — closure is handled loop-side.
- No new Swift files expected; if you add any, run `xcodegen generate`, commit the pbxproj
  regen SEPARATELY, and verify `aps-environment: development` survives in
  `Talaria/Talaria.entitlements`.
- Full suite must be green (baseline 2026-07-19: 893 tests / 77 suites).
