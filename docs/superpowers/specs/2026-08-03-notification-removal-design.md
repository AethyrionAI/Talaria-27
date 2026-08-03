# Notification Removal — Design (OPEN_ITEMS #238)

**Date:** 2026-08-03 (evening) · **Approved by Owen** (direction, scope, approach A, design sections — same evening)

## Rationale (Owen's, verbatim in spirit)

Post-pivot, Talaria is a **self-contained local brain that can upgrade to Hermes** — the
default user is hostless, so notifications can never fire for them, yet the app still
shows the iOS permission dialog on first run. For the upgrade tier, self-hosted Hermes
cannot sign APNs pushes (the team `.p8` can never ship to user hosts). And the one user
notifications served — Owen — no longer needs them: *"I was only going to check because
it wasn't giving me the answer completed... If that's there when I go to check, the
notification is moot."* The banner was scaffolding around the #235 defect; #235 fixed
reconstruction and #237 fixed dedupe, so **open-the-app-and-it's-there is the trusted
surface** and the scaffolding holds up nothing.

Confirmed collateral (Owen accepted explicitly): **reply-from-the-lock-screen (#47) and
its "Reply not sent" failure banner go too** — no banners, nothing to long-press.

## Approach (A — one clean cut)

Single branch, everything deleted at once, one gate, one OTA. Rejected: two-stage
silence-then-delete (the #218 gated-dead-code hazard family, and the prompt code would
still ship) and UI stubs (violates real-data-only).

## Scope — REMOVED

| Surface | Detail |
|---|---|
| APNs registration | `AppEntry`: `registerForRemoteNotifications()`, both token callbacks, `didReceiveRemoteNotification` silent-push handler |
| Notification delegate | `UNUserNotificationCenterDelegate` conformance (willPresent, didReceive tap/reply routing), category registration, `NotificationReplyAction` type |
| Producers | `LocalNotificationService` (notifyRunCompleted #226, notifyReplyFailed #47, lazy auth #31/#189), `LiveNotificationService`, `MockNotificationService`, the `LocalNotificationScheduling` protocol |
| ChatStore | `notifications` dependency (init params), both priming calls, the reconcile's `notifyRunCompleted` |
| AppContainer | `apnsTokenDefaultsKey`, `cachedAPNsDeviceToken`, `PushTokenPipelineState` (#189), `registerPushTokenIfNeeded` / `registerStoredPushTokenIfNeeded` / unregister bodies (relay `push/register` ×2), `handleNotificationTap` / `handleNotificationReply` / `handleRemoteNotificationWake`, both `notifyReplyFailed` sites, `setNotificationsEnabled` + its gates |
| Bootstrap | `LiveSessionBootstrapService.locallyHeldAPNsToken` + the token field in relay device registration (**registration itself stays** — sensors still pair) |
| Settings UI | `NotificationsSettingsScreen` (331 lines) deleted; System-screen nav row + ON/OFF status; Privacy-matrix `.notifications` row; Diagnostics token/pipeline rows |
| UserSettings | `notificationsEnabled` removed **decode-tolerantly** — old persisted JSON carrying the stale key must still load (pinned by test) |
| PermissionsStore | notifications capability row + `notificationService` dependency |
| project.yml | `aps-environment` entitlement, `remote-notification` UIBackgroundMode. **xcodegen regen mandatory** |
| Tests | `PushRegistrationRecordTests` deleted; push-specific halves of `InstallationIdentityTests`; spies/references in `AppStoresTests`, `ServerSettingsTests`, `BackendProfilesTests`, `BriefingTests`, `ConnectorOutageAlertTests` updated. Suite count MUST move down by a delta counted in the plan |

## Scope — STAYS (deliberate)

- **BGAppRefresh (#14)** — now the sole background catch-up; its "complementing relay
  APNs" comment is rewritten. It drains the sensor outbox, runs one reconcile, rewrites
  widget data.
- **Live Activities** — separate surface (lock-screen run progress), untouched.
- **Inbox / briefings** — poll-fed (`loadInbox`), no notification dependency (verified).
- **Connector-outage alert** — an in-app inbox alert (verified), untouched.
- **Durable installation identity (#133/#143)** — the deviceId also serves sensor
  pairing; identity stays, only its push-specific halves go.
- **The relay** — zero edits. Its `push/register` endpoints and `apns_token` rows starve.
  Deletion by starvation is doctrine-clean; deactivation of dead rows is an optional
  later one-time chore, not part of this lane.

## Host side + records

- **Mac talaria-push hook: disarmed at merge time** by deleting
  `~/.hermes/talaria/push/devices/whoGoesThere.json` (the designed OFF switch — no
  gateway restart, no Errno-48 exposure). The hook directory is removed at the next
  natural gateway restart. **OJAMD deploy (Task 1.7): cancelled, never happened.**
- Branch `claude/t27-223-talaria-push` remains unmerged as the archive/reference
  implementation (a future hosted-forwarder decision could revive the mechanism).
- OPEN_ITEMS: new entry **#238** carries this lane with the bars below pre-registered
  before any run; **#223**'s push lanes (1, 3, 4) marked retired-by-pivot (the
  zero-setup direction itself continues — this removal *advances* relay deletion);
  retirement notes on #47, #189, #226 leg (b), #31 priming.
- Phone keeps banners on build 1886 until the removal OTA installs.

## Bars — pre-registered in the #238 entry BEFORE the run

- **238-A (sim, fresh install):** erased sim, scripted pass through onboarding + first
  chat + settings → the iOS notification permission dialog **never appears**.
- **238-B (mechanical):** zero `UserNotifications` / `UNUserNotificationCenter`
  references in app-target sources; `project.yml` clean of `aps-environment` and
  `remote-notification`.
- **238-C (suite):** #235 recovery tests green; the UserSettings decode-tolerance test
  green; suite count moves DOWN by the plan's counted delta (stale-`.xctest` rule).
- **238-D (device, OTA):** remote run, app backgrounded → **no banner**; open the app →
  answer present at the tail. The waiting surface observed doing the banners' old job.
- **238-E (host):** a Mac-gateway session completion produces **no** APNs attempt in
  agent.log — the Lane-1 OFF-check, inverted.
- Gate (`scripts/mac/lane-gate.sh`) before PR, Release build included (#218 —
  entitlement edits are config-plane, invisible to Debug).

## Testing strategy

TDD where behavior changes: decode tolerance (old JSON with the stale key), ChatStore
construction without the notifications dependency, PermissionsStore capability list,
haptics toggle surviving in its new System-settings home. Deletion verified by absence
(238-B greps) + the counted suite delta, not by green alone.

## Risks

1. **Stale-key decode:** JSONDecoder ignores unknown keys, but UserSettings has a custom
   `init(from:)` — the tolerance must be verified against the actual decoder path, not
   assumed (the StoredMessage `id` lesson from #237).
2. **Entitlement/plist changes are Debug-invisible** — covered by the gate's Release arm
   and 238-A on a fresh sim.
3. **Hidden consumers** — the inventory swept producers and consumers; any straggler
   surfaces as a compile error at deletion time, which is the desired failure mode.
