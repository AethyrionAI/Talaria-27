# HANDOFF 2026-07-21 — Push fixes pivot (#143 dedupe, #145 wedge)

Session: v0.19 verification → #147 crash root-cause → device verify. This doc pivots
the next session straight into the two fix lanes. OPEN_ITEMS is current through `606cd83`
(+ the #143 carrier correction committed alongside this handoff). Single-writer on
OPEN_ITEMS: whichever session holds the Mac DC connection owns it.

## State (all pushed to main)
- #147 CLOSED (crash): `@MainActor` on `HermesAppDelegate` (PR #129, merge `20b46fc`),
  device-verified. .ips analyzed; PR #126 exonerated. Full suite 931/84 + XCTest 8/8 green.
- #147 remainder → #145: cold notification-tap now WEDGES on bare splash;
  survives force-quit; REINSTALL clears → wedge state persisted in app container,
  written during tap handling.
- Shim pruning live on Mac (nvidia via hermes config excluded_providers; MoA via
  shim-side filter, commit `a461c70`, env `TALARIA_SHIM_HIDDEN_PROVIDERS`).
- Repro harness: OJAMD Hermes session `api_1784679478_b01f5299` sends inbox alerts on
  demand via `mcp__hermes_mobile__send_inbox_item` (notify: alert).

## Lane A — #143 ×4 duplicates (SERVER-side; probably small)
CORRECTED CARRIER ANALYSIS: NOT app-local scheduling — the app has no inbox local
notifications (`LocalNotificationService` only has reply-failed/run-completed, UUID ids).
Mechanism: `relay/app/main.py:413` loops `active_push_registrations_for_user`
(`relay/app/services.py:918`) → one `send_alert_push` PER active (Device, PushRegistration)
row. Each app reinstall re-enrolls → new active rows → ×N to the same phone. Spacing =
sequential send loop. Cross-refs #144 (row pollution), #146 (row bookkeeping).
Ship list:
1. OJAMD DC window: count whoGoesThere's active rows in
   `O:\Hermes\Talaria\relay\hermes_mobile.db` (expect ≈4) — confirms before code.
2. Fix in `upsert_push_registration` (`services.py:873`): same physical device
   re-registering must DEACTIVATE prior rows (dedupe by device identity and/or replace
   same-token rows), plus send-loop token dedupe as belt-and-braces.
3. Handle APNs 410 Unregistered → deactivate row (hygiene, kills stale tokens).
4. relay venv pytest (bare `pytest`, no -q). Deploy: OJAMD rebase flow
   (`git fetch t27`, rebase `ojamd-deploy`), restart `HermesMobileRelay` (Owen elevates).
5. Verify: one controlled send → exactly ONE notification.

## Lane B — #145 wedge (app-side investigation → fix)
Evidence: tap-created, container-persisted (survives force-quit, cleared by reinstall),
bare splash = `shouldShowLaunchSplash` stuck (`pairingStore.isPaired && !isInitialized`).
Prime suspects: `ChatStore.reconcilePendingRuns` (`ChatStore.swift:1418`) — persisted
`pendingRun` + `startReconcileLoopIfNeeded()` retry loop; also inbox `markRead` local state.
Trace list:
1. Where `pendingRun` is written/persisted (UserDefaults? file?) and why a nil-session
   inbox tap leaves one.
2. What `attemptReconcile` awaits; ANY timeout? What the retry loop holds.
3. Why any of it runs ahead of `isInitialized` — check `LaunchInitStep` critical path
   (`AppContainer.swift` ~195) ordering vs `handleNotificationTap` (`AppContainer.swift:1387`).
4. Fix shape: #136 timeout non-negotiables extended to tap/foreground path; nothing
   written on the tap path may wedge subsequent launches; recovery: launch must clear or
   bypass a poisoned pendingRun.
5. Device DoD: cold tap opens clean; force-quit relaunch clean; no reinstall needed.

## Queued (unchanged)
OJAMD window: nvidia excluded_providers in OJAMD config + `TalariaModelsShim` restart
(shim filter code rides the rebase); #148 installed hermes-ios skill refresh under
HERMES_HOME; Lane A step 1 (DB count). Owen advised not to tap Talaria notifications
until Lane B ships.

## Rules reminders
`DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer` every shell; sim UDID
`47F68496-24F9-45D9-93D3-1C778DB6B557`; merge commits only; OPEN_ITEMS edits separate
surgical commits with idempotency-guarded /tmp scripts; verify Swift Testing counts via
"Test run with N tests" lines (931/84 baseline).
