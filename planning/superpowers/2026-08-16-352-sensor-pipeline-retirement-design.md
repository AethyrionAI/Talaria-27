# #352(a) — Retire the sensor-ingestion/upload pipeline (design)

**Date:** 2026-08-16 night · **Tracker:** #352 (routed (a) by Owen: "retired the
old sensor stuff") · **Verified against:** `main` @ `471531b` · **Bars:**
pre-registered in the #352 entry (same commit as this spec) · **Status:**
AWAITING OWEN'S SIGN-OFF — no implementation until bars + this spec are read.

## Why (one paragraph)

The app still captures location/health/motion on every launch/foreground and
uploads to relay `:8000`, which has been Stopped + Disabled on OJAMD since
2026-08-10 (#346). Queues grow (500 health samples at cap), the About page
reports permanent failure, battery burns on backoff retries forever, and the
same pipeline captures behind App Lock (#323). #251 decision 2 already ruled
"sensors ride #242, not an ingestion pipeline" — query-time answers from the
phone are live and proven. Direction is DELETION, not robustness (the ⛔ rule).

## Verified premises (read from code this session, not inherited)

1. **Query-time does not touch the upload path.**
   [PhoneQueryResponder.swift](../../Talaria/Services/Live/PhoneQueryResponder.swift)
   dispatches through `LivePhoneQueryReader` to the belt's own statics:
   `DeviceHealthTool.performRead` (fresh `HKHealthStore()` per read, its own
   `requestAuthorization`), `LocationTool.performLocationRead` (shared
   `DeviceLocationProvider` — NOT `LiveLocationService`), `MotionTool` (live
   `CMPedometer`/`CMMotionActivityManager`), `CalendarReadTool`/
   `ReminderReadTool` (live `EKEventStore`), `WeatherTool` (WeatherKit).
   Nothing reads `SensorOutboxState`, `SensorUploadService`, or its
   persistence. `AppContainer.swift:1057-1064` documents the plane split
   explicitly.
2. **The four toggles are shared.** `PhoneQueryResponder.deniedGate`
   (`PhoneQueryResponder.swift:184-200`) reads `sensorStreamingEnabled` +
   `healthCollectionEnabled`/`locationCollectionEnabled`/
   `motionCollectionEnabled` — the same `UserSettings` keys that gate the
   uploader. **The keys survive; the upload half of their meaning dies.**
3. **The widget is safe-ish.** The health widget queries HealthKit directly
   every 15-minute timeline pass
   (`HermesTimelineProvider.swift:69-96`, `HealthQueryCore.loadWidgetMetrics`);
   the app-written snapshot (`SensorUploadService.swift:652`) is only the
   fallback for denied-auth/locked-device passes. Deleting the feed degrades
   only that fallback (Q4).
4. **Relay pairing is load-bearing far beyond sensors.** `PairingStore.isPaired`
   has 30+ consumers (chat routing, splash, launch guards, channels UI…).
   This lane does not touch it.
5. **Two "drains" exist and collided once already** (#352's filing): the
   sensor upload drain (dies here) and the plugin's webhook long-poll drain
   (`TalariaPlatformLink`, survives). After this lane the word "drain" has
   ONE referent in the app.

## Approaches considered

- **(1) Single-lane full deletion — RECOMMENDED.** One branch, ordered
  commits, each scoped (service+wiring+tests → About → settings copy →
  persistence purge → manifest → docs close-outs → optional 269-A-D card).
  Mostly deletions; net thousands of lines removed. Matches the ⛔ deletion
  direction and #351's "solved by removal" house style.
- **(2) Interim gate (#352 option (b)).** Stop the uploader when no relay is
  reachable, render RETIRED. Rejected: Owen already routed (a); builds
  surface on a tier whose direction is deletion.
- **(3) Staged retirement (never-start first, delete later).** Rejected: the
  zombie state (dead code that looks live) is exactly what #352 exists to
  kill; two lanes' worth of gate runs for one outcome.

## Scope — DELETE

| Artifact | Where | Note |
|---|---|---|
| `SensorUploadService` (1,149 lines: `SensorOutboxState`, queues, busy ladder, `crossCycleBackoffDeadline`, capture cycle) | `Talaria/Services/Live/SensorUploadService.swift` | whole file |
| `ConnectorOutageAlertPolicy` | `Talaria/Services/Support/ConnectorOutageAlertPolicy.swift` | upload-only |
| InboxStore outage-alert members (`raiseConnectorOutageAlert`/`clearConnectorOutageAlert`/`isConnectorOutageAlert`/`connectorOutageAlertKind`) | `Talaria/Stores/InboxStore.swift:87-118` | only caller is the deleted wiring |
| Sensor-outbox persistence (protocol methods + `UserDefaultsAppPersistenceStore` impl + debounce cache) | `AppPersistenceStoreProtocol.swift:41-43`, `UserDefaultsAppPersistenceStore.swift:274-302` | protocol shrink touches every mock conformance (mechanical) |
| AppContainer wiring: property, construction (`:649-680`), outage-alert hookup (`:779-786`), all ~16 call sites, `restartSensorPipelineIfPaired`, `LaunchInitStep.startSensorService`, `sensorForegroundRefresh` step; the two sensor lines in `handleBackgroundRefresh` (`:1765-1766`) | `Talaria/Stores/AppContainer.swift` | the four `set*Enabled` setters SURVIVE minus their dead service calls; BGAppRefresh keeps reconcile + widget rewrite |
| About `// Sensor Pipeline` panel + row helpers + `sensorAccessToken` task | `AboutSettingsContent.swift:231-333` + `:60` | replaced (below) |
| M-8 sensor-destination profile machinery (`sensorDestinationProfileID`, "SENSORS" tag, `setSensorDestination`, `isSensorDestination`) | `BackendProfilesStore.swift:108-234`, `ServerSettingsScreen.swift:251,327-328,399-404` | upload-only routing concept |
| `locationSyncPreference` key + segmented control + plumbing | `UserSettings.swift:357`, `PrivacySettingsScreen.swift:399-434`, `AppContainer.swift:646,1843` | only functional consumer is `LiveLocationService.updateSyncPreference` |
| Capture services with no surviving consumer | `LiveLocationService.swift`, `LiveHealthService.swift`, (`LiveMotionService` partially — see KEEP) | plan enumerates consumers file-by-file before deleting; bar 352-B governs |
| Tests: `SensorOutboxChurnTests.swift` (3 suites), `SensorStreamingGateTests` (in `SensorOptInTests.swift`), `ConnectorOutageAlertTests.swift` (both suites), 2 `@Test`s in `AppStoresTests.swift` (`:3950`, `:4004`) | `TalariaTests/` | each deleted suite named with its count in the PR (352-J) |
| Background `location` mode; app-target HealthKit background-delivery entitlement | `project.yml:363-367`, `Talaria.entitlements` | Q3; widget target untouched |

## Scope — KEEP (with edits)

- **`PhoneQueryResponder` family, belt tools, `DeviceLocationProvider`,
  `TalariaPlatformLink`, `HealthQueryCore`** — untouched (bar 352-C).
- **The four `UserSettings` toggle keys** — raw keys byte-unchanged; captions
  edited: drop "as live streams", "drops queued samples"; the unpaired
  caption stops keying on relay pairing (`PrivacySettingsScreen.swift:339-346`).
  `StreamedSensor` rows + `PermissionsStore` status pips survive as-is.
- **`LiveMotionService` auth surface** — `PermissionsStore` consumes it for
  motion authorization (`PermissionsStore.swift:13-97`). Keep the auth
  members; delete capture/streaming members if separable.
- **`SensorStreamingGrandfathering` (#137)** — migrates the master toggle,
  which survives with query-time meaning; keep.
- **BGAppRefresh registration** (`BackgroundRefreshScheduler`) — survives for
  reconcile + widget rewrite; only the sensor lines go.
- **Relay pairing, `PairingStore`, relay client, inbox, voice** — Phase 4
  territory, explicitly out of scope.

## About-page replacement (sketch)

Section retitled (e.g. `// Phone Queries`). Rows report ONLY what query-time
actually consults: per-sensor share-toggle state + iOS authorization, three
rows (Health / Location / Motion). Calendar/Reminders kinds are served but
iOS-permission-gated with no app toggle — no rows for them (YAGNI; iOS
Settings already shows those grants). **No link-state row** — probe-based LINKED honesty is
#269-A's lane and #350 is why we don't assert from a stored token. No row
named "Drain". Data feeds: `UserSettings` + `PermissionsStore` only. Real
data only; "—" where unknowable.

## One-shot purge (Q2, bar 352-F)

First launch at this build removes the persisted sensor-outbox blob (pending
GPS fix + up to 500 health samples in UserDefaults). Seeded-blob unit test
proves removal. Rationale: the queue is the dead tier's own buffer; orphaned
location+health data in UserDefaults forever is the worse privacy state.

## #323 coordination (bar 352-H)

This lane deletes capture-behind-cover and upload-behind-cover (the #323 §V1
sensor lines cannot recur — the code is gone). It does NOT close #323: a
phone query arriving while the cover is up is still answered
(`TalariaPlatformLink` drains during covered-active, and chat/voice remain
ungated). Dated residue note lands in #323 in the same commit.

## Docs close-outs (bar 352-I)

CLAUDE.md: fork-rationale line (:13), iCloud Private Relay gotcha (:456),
HealthKit-on-`SensorUploadService.start()` gotcha. README: paired-tier
sensor-pipeline claims (:8, :26, :36, :75, :131). SECURITY.md: relay-carries-
sensors (:34, :62-63). CLEAN_CHAT_PATH.md: dated supersession note (historic
narrative, not rewritten). Archive entries asserting a live pipeline get
#317(a) append-only pointers.

## Test/gate plan

`lane-gate.sh` (units + XCUITest + Release) on a `CC-lane-N` pool sim, TCC
calendar+reminders granted immediately before every run, UDID not name for
any hand-rolled `xcodebuild`, `DEVELOPER_DIR` = Xcode-beta5. Count stated and
MOVED — down, with deleted suites enumerated so the delta reconciles.
Post-merge device arms (Owen): zero capture/drain lines across a
launch→foreground→background cycle; a live `talaria_phone_query` answers.

## Questions for Owen (Q1-Q4)

Mirrored in the #352 entry bars block: **Q1** 269-A-D card rides or stays
(recommend RIDE, isolated commit). **Q2** purge queued samples (recommend
YES). **Q3** drop background-location mode + health background-delivery
entitlement (recommend YES). **Q4** accept widget-fallback degradation
(recommend YES). Only their contingent bars block on the answers; the lane
itself can start on sign-off.

## Sizing

One brainstorm/plan cycle (this doc) + one implementation lane. Mostly
deletions; the delicate parts are the AppContainer wiring extraction, the
protocol shrink across mock conformances, and the About replacement. Plan
(via writing-plans) after sign-off.
