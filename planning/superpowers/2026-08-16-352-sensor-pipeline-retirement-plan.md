# #352(a) Sensor-Pipeline Retirement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete the app-side sensor-ingestion/upload pipeline (capture → queues → relay POST) while preserving the #242 query-time path, per tracker #352 bars 352-A..K (all Owen-signed, Q1-Q4 = ride/purge/yes/yes).

**Architecture:** Ten ordered tasks, each leaving the tree compiling and the suite green: replace the About panel first (it reads the service), unwire AppContainer, delete the pipeline files + their tests, slim the three capture services to auth-only surfaces, add the one-shot purge, fix copy, replace the SETUP card, clean the manifest, land doc close-outs, gate + PR.

**Tech Stack:** SwiftUI / Swift Testing, xcodegen, `scripts/mac/lane-gate.sh`.

## Global Constraints

- Spec: `planning/superpowers/2026-08-16-352-sensor-pipeline-retirement-design.md`; bars: `OPEN_ITEMS.md` #352 (dated block 2026-08-16 night). A missed bar is a falsification, not a redefinition.
- `DEVELOPER_DIR=/Applications/Xcode-beta5.app/Contents/Developer` in every shell that builds.
- `xcodegen generate` after ANY file add/delete; commit the regenerated `project.pbxproj` in the same commit.
- **Never touch:** `PhoneQueryResponder.swift`, `LivePhoneQueryReader`, `DeviceToolBelt`/`DeviceReadTools`/`DeviceHealthTool`/`DeviceCalendarTools`, `TalariaPlatformLink.swift`, `PairingStore.swift`, `HealthQueryCore.swift`, both `HermesWidgetData.swift` copies, `SensorStreamingGrandfathering.swift`, the relay `apiClient`, inbox/voice surfaces.
- **Byte-stable persisted keys:** `sensorStreamingEnabled`, `healthCollectionEnabled`, `locationCollectionEnabled`, `motionCollectionEnabled` in `UserSettings` CodingKeys/decode/encode; `talaria.sensorStreamingMigrated` stamp key.
- Long builds/gates: run backgrounded and poll; never block a tool call on them.
- Branch `claude/t27-352-sensor-retirement` off a fetched, in-sync `origin/main` (BRANCHING.md protocol). PR opens DO-NOT-MERGE; Owen merges.
- Commit messages reference #352; the docs task's commit also references #323 and #269-A-D.

---

### Task 1: Replace the About "Sensor Pipeline" panel with "Phone Queries"

**Files:**
- Modify: `Talaria/Features/Settings/AboutSettingsContent.swift` (panel at :231-333, state at :31, task line :60, helpers :303-349)

**Interfaces:**
- Consumes: `permissionsStore.capabilities` (`[DeviceCapability]`), `settingsStore.settings.{sensorStreamingEnabled,healthCollectionEnabled,locationCollectionEnabled,motionCollectionEnabled}`, existing `permissionColor(_: PermissionStatus) -> Color` (:351-358), existing `rowDivider`.
- Produces: `phoneQueriesPanel` view; `panelRow(_:_:_:blinks:)` (renamed from `sensorRow`, same signature) — the voice panel's three call sites (:192-198) switch to it.

- [ ] **Step 1: Delete the relay-era panel and its plumbing**

In `AboutSettingsContent.swift` delete: the `@State private var sensorAccessToken: Bool?` (:31); the `sensorAccessToken = await container.sensorUploadService?.hasValidAccessToken()` line in `.task` (:60); the whole `// MARK: Sensor pipeline (#15)` section — `sensorPanel` (:233-285) — plus `tokenLabel` (:303-309), `tokenColor` (:311-317), `pendingLocationText` (:319-323), `pendingHealthText` (:325-327), `lastDrainText` (:329-333), `relativeAge` (:335-341), and `locationColor` (:343-349; its only callers were sensor rows — verify with `rg -n "locationColor" Talaria/Features/Settings/AboutSettingsContent.swift` before deleting; `permissionColor` STAYS).

- [ ] **Step 2: Rename `sensorRow` → `panelRow` and add the new panel**

Rename the helper at :287-301 to `panelRow` (same body), update the voice panel's three call sites. Where `sensorPanel` sat in `body` (:51), put `phoneQueriesPanel`, and add:

```swift
// MARK: Phone queries (#352)
//
// Replaced the relay-era "// Sensor Pipeline" panel when #352 retired the
// upload path. Reports ONLY what query-time actually consults: the share
// gates (UserSettings, the same table PhoneQueryResponder.deniedGate reads)
// and the iOS grants (PermissionsStore). Deliberately NO link-state row —
// probe-based link honesty is #269-A's lane, and #350 is why the page never
// asserts a live host from a stored token.

@ViewBuilder
private var phoneQueriesPanel: some View {
    VStack(alignment: .leading, spacing: Design.Spacing.sm) {
        MonoLabel("// Phone Queries", size: 10, tracking: Design.Tracking.monoXWide,
                  color: Design.Colors.mutedForeground)

        VStack(spacing: 0) {
            panelRow("Sensor Sharing",
                     settingsStore.settings.sensorStreamingEnabled ? "ON" : "OFF",
                     settingsStore.settings.sensorStreamingEnabled
                        ? Design.Brand.accent : Design.Colors.mutedForeground)
            rowDivider
            queryGateRow("Health", enabled: settingsStore.settings.healthCollectionEnabled,
                         permission: .health)
            rowDivider
            queryGateRow("Location", enabled: settingsStore.settings.locationCollectionEnabled,
                         permission: .location)
            rowDivider
            queryGateRow("Motion", enabled: settingsStore.settings.motionCollectionEnabled,
                         permission: .motion)
        }
        .hudPanel(
            cornerRadius: Design.CornerRadius.lg,
            borderColor: Design.Colors.accentTint(0.12),
            fill: Design.Colors.background.opacity(0.5),
            innerGlow: false
        )
    }
}

/// One row per gated sensor: the app-level share gate and the iOS grant,
/// in one honest line. "OFF" when either the master or this sensor's
/// toggle is off (matching deniedGate's master-outranks-stream order);
/// "SHARED · <grant>" when the toggles pass and iOS has the last word.
private func queryGateRow(_ label: String, enabled: Bool, permission: PermissionType) -> some View {
    let status = permissionsStore.capabilities
        .first { $0.permissionType == permission }?.status
    let shared = settingsStore.settings.sensorStreamingEnabled && enabled
    let text = shared ? "SHARED · \(status?.displayLabel.uppercased() ?? "—")" : "OFF"
    let color = shared ? permissionColor(status ?? .notDetermined)
                       : Design.Colors.mutedForeground
    return panelRow(label, text, color)
}
```

- [ ] **Step 3: Compile check**

Run (backgrounded if slow): `DEVELOPER_DIR=/Applications/Xcode-beta5.app/Contents/Developer xcodebuild -project Talaria.xcodeproj -scheme Talaria -configuration Debug -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
Expected: BUILD SUCCEEDED. Also `rg -n "Last Drain|Pending Health|Pending Location|Access Token" Talaria/Features/Settings/AboutSettingsContent.swift` → no hits (352-D).

- [ ] **Step 4: Commit**

```bash
git add Talaria/Features/Settings/AboutSettingsContent.swift
git commit -m "feat(#352): About page — Phone Queries panel replaces the relay-era Sensor Pipeline panel (352-D)"
```

---

### Task 2: Unwire the pipeline from AppContainer, InboxStore, and the M-8 destination

**Files:**
- Modify: `Talaria/Stores/AppContainer.swift` (:142, :196, :211, :245, :256-264, :628-680, :745, :776-786, :1390-1391, :1492-1497, :1692, :1730-1733, :1748-1751, :1762-1766, :1787, :1806-1815, :1826, :1828, :1840-1844 partial, :1856-1858, :1863-1869, :2132-2133)
- Modify: `Talaria/Stores/InboxStore.swift` (:87-118)
- Modify: `Talaria/Stores/BackendProfilesStore.swift` (:108-234 — the `sensorDestinationProfileID` members)
- Modify: `Talaria/Features/Settings/ServerSettingsScreen.swift` (:251, :327-328, :399-404)

**Interfaces:**
- Consumes: nothing new.
- Produces: `AppContainer` without `sensorUploadService`; setters `setSensorStreamingEnabled/setHealthCollectionEnabled/setLocationCollectionEnabled/setMotionCollectionEnabled(_:) async` keep their signatures (Privacy screen calls them) but shrink to settings-write + contextual permission request + `reloadCapabilities`.

- [ ] **Step 1: Delete the construction and container wiring**

In `AppContainer.swift`: delete the `sensorDestinationIsActive` closure and `sensorRelayClient` (:628-644); the `SensorUploadService(...)` construction (:649-680) — KEEP the three `let liveLocationService/liveHealthService/liveMotionService` lines and the `updateSyncPreference` line (:645-648; they feed `PermissionsStore` until Task 4); the `sensorUploadService: sensorUploadService` container argument (:745); the `onConnectorOutageAlert` wiring block with its `// #113` comment (:776-786); the stored property (:142) and both init-parameter sites (:196, :211).

- [ ] **Step 2: Delete the lifecycle call sites**

Delete: `containerLog.notice("initialize: starting sensor service")` + `sensorUploadService?.start()` (:1390-1391); the `// #136: the sensor foreground refresh…` comment + notice + `await sensorUploadService?.handleAppDidBecomeActive()` in `runBackgroundBootstrap` (:1492-1497); `await sensorUploadService?.handleAppDidBecomeActive()` in `handleForegroundActivation` (:1692); in `handleSystemLaunch` the "starting sensor service" notice + `sensorUploadService?.start()` + `await sensorUploadService?.handleSystemLaunch()` (:1730-1733 — the guards and the talk/LiveActivity lines STAY); in `handleBackgroundRefresh` the cold-launch comment + `sensorUploadService?.start()` + `await sensorUploadService?.handleSystemLaunch()` (:1762-1766) and reword its doc comment (:1748-1751) to "one reconcile fetch + widget rewrite"; `sensorUploadService?.start()` in `handlePairingActivated` (:1787); `sensorUploadService?.stop()` + `resetOutbox()` in `handlePairingRemoved` (:2132-2133); the whole `restartSensorPipelineIfPaired()` (:1863-1869).

- [ ] **Step 3: Shrink the four setters**

Each setter keeps its signature. Resulting bodies (the #6 revoke semantic — "the persisted flag is the durable stop" — now IS the whole mechanism; update the section comment at :1796-1801 to say the flags gate `PhoneQueryResponder.deniedGate`, not `SensorUploadService.start()`):

```swift
func setSensorStreamingEnabled(_ enabled: Bool) async {
    settingsStore.settings.sensorStreamingEnabled = enabled
    await permissionsStore.reloadCapabilities()
}

func setHealthCollectionEnabled(_ enabled: Bool) async {
    settingsStore.settings.healthCollectionEnabled = enabled
    if enabled { await permissionsStore.requestPermission(for: .health) }
    await permissionsStore.reloadCapabilities()
}

func setLocationCollectionEnabled(_ enabled: Bool) async {
    settingsStore.settings.locationCollectionEnabled = enabled
    if enabled { await permissionsStore.requestPermission(for: .location) }
    await permissionsStore.reloadCapabilities()
}

func setMotionCollectionEnabled(_ enabled: Bool) async {
    settingsStore.settings.motionCollectionEnabled = enabled
    if enabled { await permissionsStore.requestPermission(for: .motion) }
    await permissionsStore.reloadCapabilities()
}
```

(`setLocationCollectionEnabled(false)`'s two sync-preference reset lines (:1843-1844) die here with the arm that held them; the preference itself dies in Task 4.)

- [ ] **Step 4: Delete the LaunchInitStep cases and InboxStore alert members**

Remove `case startSensorService` (:245) and `case sensorForegroundRefresh` (:256) plus their mentions in the enum's comments (:258-264) and any `switch` arms over the enum (`rg -n "startSensorService|sensorForegroundRefresh" Talaria/`). In `InboxStore.swift` delete `connectorOutageAlertKind` (:87), `raiseConnectorOutageAlert()` (:92-109), `clearConnectorOutageAlert()` (:111-115), `isConnectorOutageAlert(_:)` (:117-119). Keep `localAlertPayloadKey` only if `rg -n "localAlertPayloadKey" Talaria/` still finds another user; delete it too if orphaned.

- [ ] **Step 5: Delete the M-8 sensor-destination machinery**

`BackendProfilesStore.swift`: delete `sensorDestinationProfileID` storage + accessors (:108-113, :192-234). `ServerSettingsScreen.swift`: delete `isSensorDestination` (:251), the "SENSORS" tag rendering (:327-328), the `setSensorDestination` action (:399-404). `rg -n "sensorDestination" Talaria/ TalariaTests/` → remaining hits are test files deleted in Task 3, else fix them now.

- [ ] **Step 6: Compile + suite**

Build as Task 1 Step 3, then run the unit suite (backgrounded):
`DEVELOPER_DIR=… xcodebuild -project Talaria.xcodeproj -scheme Talaria -configuration Debug -destination 'platform=iOS Simulator,id=<CC-lane UDID>' test 2>&1 | tail -5`
(Resolve a pool sim: `xcrun simctl list devices | grep CC-lane`; grant TCC first — see Task 10 Step 1.) Expected: green — the sensor test suites construct the service directly and still pass; `AppStoresTests` M-8 tests may reference `sensorDestinationProfileID` — if so, delete those `@Test` functions now and note the count.

- [ ] **Step 7: Commit**

```bash
git add Talaria/Stores/AppContainer.swift Talaria/Stores/InboxStore.swift Talaria/Stores/BackendProfilesStore.swift Talaria/Features/Settings/ServerSettingsScreen.swift
git commit -m "refactor(#352): unwire SensorUploadService from AppContainer/InboxStore; delete M-8 sensor destination (352-A prep, 352-B)"
```

---

### Task 3: Delete the pipeline files, their tests, and the persistence surface

**Files:**
- Delete: `Talaria/Services/Live/SensorUploadService.swift`, `Talaria/Services/Support/ConnectorOutageAlertPolicy.swift`, `TalariaTests/SensorOutboxChurnTests.swift`, `TalariaTests/ConnectorOutageAlertTests.swift`
- Modify: `Talaria/Services/Protocols/AppPersistenceStoreProtocol.swift` (:41-43), `Talaria/Services/Support/UserDefaultsAppPersistenceStore.swift` (:11, :50-53, :274-302), `Talaria/Services/SharedWidgetDataStore.swift` (:36-56), `TalariaTests/SensorOptInTests.swift` (delete `SensorStreamingGateTests` :225-282 + sensor-outbox stubs), `TalariaTests/AppStoresTests.swift` (delete the two `@Test`s at :3950 and :4004 + mock stubs), `TalariaTests/BriefingTests.swift` (:191-193 stubs), `TalariaTests/TalariaPlatformInboxServiceTests.swift` (stubs), `Talaria/Stores/ChatStore.swift` (:234 comment), `Talaria/Models/UserSettings.swift` (:358-361 comment)

**Interfaces:**
- Consumes: Task 2's unwired tree.
- Produces: `AppPersistenceStoreProtocol` without `loadSensorOutboxState()/saveSensorOutboxState(_:)/clearSensorOutboxState()`; `SharedWidgetDataStore` without `updateHealthMetrics(from:)`.

- [ ] **Step 1: Delete the two production files and two test files** (`git rm`).

- [ ] **Step 2: Shrink the persistence surface**

Remove the three sensor-outbox requirements from `AppPersistenceStoreProtocol.swift` (:41-43). In `UserDefaultsAppPersistenceStore.swift` remove `Keys.sensorOutboxState` (:11), `sensorOutboxCache` + `sensorOutboxWriteTask` (:50-53), and the four sensor-outbox members (:274-302). KEEP `Keys.healthAnchorPrefix` and the `loadHealthQueryAnchorData` family until Task 4. Remove the now-dead stub conformances from `SensorOptInTests.swift`, `AppStoresTests.swift`, `BriefingTests.swift`, `TalariaPlatformInboxServiceTests.swift` (`rg -n "SensorOutboxState" TalariaTests/` → zero after).

- [ ] **Step 3: Delete `SharedWidgetDataStore.updateHealthMetrics`** (:36-56) — `write`/`read` stay.

- [ ] **Step 4: Reword the two surviving comments**

`ChatStore.swift:234`: the `ComposeOutboxState` doc cites "the SensorUploadService pattern" — reword to "the retired sensor-outbox pattern (#352): debounced persistence with an immediate flush on lifecycle edges". `UserSettings.swift:358-361`: the collection-flag comment names `SensorUploadService` — reword to "These gate `PhoneQueryResponder.deniedGate` — a revoke survives relaunch because the flag is the mechanism (#6, #352)."

- [ ] **Step 5: xcodegen + full suite**

```bash
xcodegen generate
```
Then build + full unit suite (as Task 2 Step 6). Expected: green, count DOWN — record the exact before/after counts and the deleted suite names for the PR body (352-J). `rg -n "SensorUploadService|SensorOutboxState|ConnectorOutageAlertPolicy|crossCycleBackoffDeadline|drainOutboxIfPossible" Talaria/ TalariaWidgets/ Shared/ TalariaTests/` → zero hits (352-A).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(#352): delete SensorUploadService, outbox state, outage policy, their tests and persistence surface (352-A)"
```

---

### Task 4: Slim the capture services to auth-only; delete the sync preference

**Files:**
- Modify: `Talaria/Services/Live/LiveLocationService.swift`, `Talaria/Services/Live/LiveHealthService.swift`, `Talaria/Services/Live/LiveMotionService.swift`, `Talaria/Services/Protocols/LocationServiceProtocol.swift`, `Talaria/Services/Protocols/HealthServiceProtocol.swift`, `Talaria/Stores/PermissionsStore.swift`, `Talaria/Features/Settings/PrivacySettingsScreen.swift` (the "// Location" section :399-470), `Talaria/Models/UserSettings.swift` (`locationSyncPreference` + the `LocationSyncPreference` type), `Talaria/Stores/AppContainer.swift` (:646), `Talaria/Services/Protocols/AppPersistenceStoreProtocol.swift` (:64-66 anchor family), `Talaria/Services/Support/UserDefaultsAppPersistenceStore.swift` (anchor impl + `Keys.healthAnchorPrefix`), test mocks conforming to the two protocols

**Interfaces:**
- Consumes: Task 3's tree.
- Produces: `LocationServiceProtocol` = `{authorizationStatus, authorizationLevel, accuracyLevel, requestAuthorization(), refreshAuthorizationState(), openSystemSettings()}`; `HealthServiceProtocol` = `{authorizationStatus, requestAuthorization(), refreshAuthorizationStatus()}`; `LiveMotionService` = `{authorizationStatus, refreshAuthorizationStatus(), requestAuthorization()}`; `PermissionsStore` without `requestBackgroundLocationAccess/updateLocationSyncPreference/healthBackgroundDeliveryEnabled`.

- [ ] **Step 1: Slim `LiveLocationService`** — keep the members in the Produces list plus the `CLLocationManager`, the auth continuation/timeout machinery (:24-25, :211-235), `locationManagerDidChangeAuthorization` (:118), and the three mapping helpers (:269-297). Delete `LocationUpdate` (:4), `lastLocation`, `syncPreference`/`updateSyncPreference`, `onLocationUpdate`, `requestBackgroundAuthorization` (:49), monitoring (`startMonitoring`/`stopMonitoring`/`requestSingleLocation`/`configureMonitoringSessions`/`startLiveUpdatesIfNeeded`/`serviceSession`/`backgroundSession`/`liveUpdatesTask`/`isMonitoring`/`lastEmittedLocation`/`emitLocation`/`shouldEmit`), and the `didUpdateLocations`/`didFailWithError` delegate methods. Update the header comment to name the surviving consumer: "auth surface for PermissionsStore; query-time reads use DeviceLocationProvider (#242)."

- [ ] **Step 2: Slim `LiveHealthService`** — keep `authorizationStatus`, `requestAuthorization()` (:62), `refreshAuthorizationStatus()` (:83), and the `HKHealthStore`. Delete `HealthSnapshot` (:4-17), the metric descriptors, `backgroundDeliveryEnabled` + `configureBackgroundDeliveryIfNeeded` + `disableBackgroundDelivery`, `onHealthUpdate`, observer queries + `startMonitoring`/`stopMonitoring`, `collectSnapshot`, anchored-change machinery + `loadAnchor`/`saveAnchor`, and the `persistence` init dependency (`AppContainer.swift:647` becomes `LiveHealthService()`). Same header-comment treatment.

- [ ] **Step 3: Slim `LiveMotionService`** — delete `ActivityCode` (:6-33), `currentActivity`, `onActivityUpdate`, `startMonitoring`/`stopMonitoring`/`isMonitoring`. Keep the `CMMotionActivityManager` (the `requestAuthorization` prompt-trigger query at :95-103 uses it).

- [ ] **Step 4: Shrink the two protocols to the Produces sets** and fix every mock conformance (`rg -ln "LocationServiceProtocol|HealthServiceProtocol" TalariaTests/`).

- [ ] **Step 5: Delete the sync preference and its UI**

`UserSettings.swift`: remove `var locationSyncPreference` (:357), its init param + default (:435), CodingKeys case, decode line (:537), and the line in `encode(to:)` (:576ff); delete the `LocationSyncPreference` type (defined in this file — `rg -n "LocationSyncPreference" Talaria/` must be zero after). `PrivacySettingsScreen.swift`: delete the "// Location" section (the view containing the sync segmented control, the accuracy `MonoLabel` (:410), and the `requestBackgroundLocationAccess` call (:470)) and its call site in `body`. `AppContainer.swift:646`: delete the `updateSyncPreference` line. `PermissionsStore.swift`: delete `requestBackgroundLocationAccess` (:68-71), `updateLocationSyncPreference` (:73-76), `healthBackgroundDeliveryEnabled` (:64-66); in `healthStatusDetail` (:152-162) replace the background-sync line with plain `return "Read Only"`.

- [ ] **Step 6: Delete the health-anchor persistence**

Remove `loadHealthQueryAnchorData`/`saveHealthQueryAnchorData`/`clearHealthQueryAnchorData` from the protocol (:64-66), their implementation and `Keys.healthAnchorPrefix` from `UserDefaultsAppPersistenceStore`, and their test stubs (`rg -n "HealthQueryAnchor" Talaria/ TalariaTests/` → zero).

- [ ] **Step 7: Suite + commit**

Full unit suite green (settings round-trip tests in `SensorOptInTests.swift` updated for the removed field — the FOUR toggle keys' assertions stay untouched, 352-E). Count recorded.

```bash
git add -A
git commit -m "refactor(#352): capture services become auth-only surfaces; sync preference and health anchors deleted (352-B)"
```

---

### Task 5: One-shot purge of the stored queue + widget health fallback (TDD)

**Files:**
- Modify: `Talaria/Services/Support/UserDefaultsAppPersistenceStore.swift` (init :55-63), `Talaria/Services/SharedWidgetDataStore.swift`, `Talaria/Stores/AppContainer.swift` (`initialize()`, before `updateWidgetData()` :1393)
- Test: `TalariaTests/AppStoresTests.swift`

**Interfaces:**
- Consumes: `UserDefaultsAppPersistenceStore.init(defaults:keychainMirror:)`; `HermesWidgetData` (steps/activeCalories/sleepHours/heartRate are all Optionals).
- Produces: `SharedWidgetDataStore.clearingRetiredHealthMetrics(_ data: HermesWidgetData) -> HermesWidgetData` (pure) + `clearRetiredHealthMetrics()` (App-Group wrapper).

- [ ] **Step 1: Write the failing tests** (in `AppStoresTests`, standalone `@Test` funcs):

```swift
@Test func initPurgesRetiredSensorOutboxAndAnchorKeys() {
    let suiteName = "purge-test-\(UUID().uuidString)"
    let suite = UserDefaults(suiteName: suiteName)!
    defer { suite.removePersistentDomain(forName: suiteName) }
    suite.set(Data("junk".utf8), forKey: "hermes.sensorOutboxState")
    suite.set(Data("anchor".utf8), forKey: "hermes.healthAnchor.stepCount")
    _ = UserDefaultsAppPersistenceStore(defaults: suite)
    #expect(suite.data(forKey: "hermes.sensorOutboxState") == nil)
    #expect(suite.data(forKey: "hermes.healthAnchor.stepCount") == nil)
}

@Test func clearingRetiredHealthMetricsNilsAllFourFieldsAndNothingElse() {
    var data = HermesWidgetData.empty
    data.steps = 5000
    data.activeCalories = 300
    data.sleepHours = 7.5
    data.heartRate = 62
    data.hostName = "keep-me"
    let cleared = SharedWidgetDataStore.clearingRetiredHealthMetrics(data)
    #expect(cleared.steps == nil)
    #expect(cleared.activeCalories == nil)
    #expect(cleared.sleepHours == nil)
    #expect(cleared.heartRate == nil)
    #expect(cleared.hostName == "keep-me")
}
```

- [ ] **Step 2: Run to verify RED** — `-only-testing:` with the full Swift Testing name including trailing `()`; expected: compile failure ("no member `clearingRetiredHealthMetrics`") / purge assertion failure.

- [ ] **Step 3: Implement**

`UserDefaultsAppPersistenceStore.init`, after `self.decoder = decoder`:

```swift
purgeRetiredSensorUploadArtifacts()
```

```swift
/// #352: the sensor-upload pipeline is retired. Its persisted outbox (a
/// pending GPS fix + up to 500 health samples) and HealthKit query anchors
/// have no reader left — remove them. Unconditional and idempotent: removing
/// an absent key is free, and no surviving path recreates either key family.
/// Key strings are inlined because their Keys constants died with the
/// pipeline; they are retired names, never to be reused.
private func purgeRetiredSensorUploadArtifacts() {
    defaults.removeObject(forKey: "hermes.sensorOutboxState")
    for key in defaults.dictionaryRepresentation().keys
    where key.hasPrefix("hermes.healthAnchor.") {
        defaults.removeObject(forKey: key)
    }
}
```

`SharedWidgetDataStore`:

```swift
/// #352: the app-side health feed is retired; the widget queries HealthKit
/// itself each timeline pass and these snapshot fields were only its
/// fallback. Nil fields render "—" — honest, where a months-stale step
/// count would lie. Pure transform so the logic is unit-testable.
static func clearingRetiredHealthMetrics(_ data: HermesWidgetData) -> HermesWidgetData {
    var cleared = data
    cleared.steps = nil
    cleared.activeCalories = nil
    cleared.sleepHours = nil
    cleared.heartRate = nil
    return cleared
}

/// App-Group wrapper; writes only when something actually changes so the
/// per-launch call doesn't churn widget reloads.
static func clearRetiredHealthMetrics() {
    let data = read()
    guard data.steps != nil || data.activeCalories != nil
        || data.sleepHours != nil || data.heartRate != nil else { return }
    write(clearingRetiredHealthMetrics(data))
}
```

`AppContainer.initialize()`, immediately before `updateWidgetData()` (:1393):

```swift
SharedWidgetDataStore.clearRetiredHealthMetrics()  // #352
```

- [ ] **Step 4: Run tests GREEN**, then the full suite (count moved UP by 2 — record).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(#352): one-shot purge of the retired sensor outbox, health anchors, and widget health fallback (352-F)"
```

---

### Task 6: Privacy-screen copy stops describing streams

**Files:**
- Modify: `Talaria/Features/Settings/PrivacySettingsScreen.swift` (:302-304 comment, :339-346 caption, :370 accessibility label)

- [ ] **Step 1: Rewrite the caption** — `sensorStreamingCaption` (:339-346) loses the relay-pairing branch entirely (the toggle's meaning no longer depends on any link state, and keying copy on `pairingStore.isPaired` was the wrong plane):

```swift
private var sensorStreamingCaption: String {
    // #260(C)/#352: ONE switch governs all sensor egress, which since #352
    // means exactly one thing — answering the agent's query-time asks.
    // Nothing streams and nothing queues.
    "Lets your Hermes agent ask this phone for the sensors you enable — answered on demand, never streamed. Each sensor asks for its iOS permission when you turn it on. Turning this off declines sensor queries."
}
```

Update the comment at :302-304 to match ("ONE switch governs sensor query answers (#260(C), #352)"). Change the per-sensor accessibility label (:370) from `"Stream \(sensor.displayLabel)"` to `"Share \(sensor.displayLabel)"`.

- [ ] **Step 2: Verify no other stream-claiming copy survives**

`rg -n "stream|Stream" Talaria/Features/Settings/PrivacySettingsScreen.swift` — remaining hits must be identifiers (`sensorStreamingEnabled`, `StreamedSensor`, `sensorStreamRow`), never user-visible strings. Build.

- [ ] **Step 3: Commit**

```bash
git add Talaria/Features/Settings/PrivacySettingsScreen.swift
git commit -m "fix(#352): sensor-sharing copy describes query-time answers, not streams (352-E)"
```

---

### Task 7: Replace the stale `hermes-mobile` SETUP card (269-A-D, Q1 "ride along")

**Files:**
- Modify: `Talaria/Features/Settings/ConnectHermesHostScreen.swift` (:99-116)

- [ ] **Step 1: Rewrite `setupCard`** — the three retired-CLI steps become the plugin-era flow (`hermes talaria pair` is live on both hosts, #271). The install story is deliberately NOT taught (that is #269-B, blocked on publication):

```swift
private var setupCard: some View {
    HUDPanel(cornerRadius: Design.CornerRadius.xl) {
        VStack(alignment: .leading, spacing: Design.Spacing.md) {
            HStack(spacing: Design.Spacing.xs) {
                Image(systemName: "terminal")
                    .font(.system(size: Design.Size.iconSmall, weight: .semibold))
                    .foregroundStyle(Design.Brand.accent)
                MonoLabel("SETUP", weight: .medium, tracking: Design.Tracking.monoXWide,
                          color: Design.Colors.secondaryForeground)
            }

            Text("Requires the Talaria plugin on your Hermes host.")
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.secondaryForeground)

            setupStep(number: "1", command: "hermes talaria pair",
                      detail: "Prints a pairing code — scan it with Pair New Device below")
        }
        .padding(Design.Spacing.lg)
    }
}
```

- [ ] **Step 2: Bar check** — `rg -n 'hermes-mobile' Talaria/` → no user-visible string (269-A-D verbatim). Build.

- [ ] **Step 3: Commit**

```bash
git add Talaria/Features/Settings/ConnectHermesHostScreen.swift
git commit -m "fix(#352,#269-A-D): SETUP card teaches hermes talaria pair, retired hermes-mobile CLIs gone (352-K)"
```

---

### Task 8: Manifest honesty — background modes, usage string, entitlements

**Files:**
- Modify: `project.yml` (:58, UIBackgroundModes list, :166), `Talaria/Talaria.entitlements`

- [ ] **Step 1: Edit** — remove `- location` from `UIBackgroundModes` (keep `fetch`/`processing`/`audio`); remove `NSLocationAlwaysAndWhenInUseUsageDescription` (:166 — When-In-Use at :160 STAYS, query-time uses it); remove `com.apple.developer.healthkit.background-delivery: true` from the app target's entitlements `properties` (:58) AND the `<key>com.apple.developer.healthkit.background-delivery</key><true/>` pair from `Talaria/Talaria.entitlements` (the #44/#48 strip trap requires both). Widget target untouched.

- [ ] **Step 2: xcodegen idempotency (#319, 352-G)**

```bash
xcodegen generate && shasum Talaria.xcodeproj/project.pbxproj && xcodegen generate && shasum Talaria.xcodeproj/project.pbxproj
```
Expected: the two hashes identical. Build Debug AND Release (`-configuration Release`, the #218 lesson) — both succeed.

- [ ] **Step 3: Commit**

```bash
git add project.yml Talaria/Talaria.entitlements Talaria.xcodeproj/project.pbxproj
git commit -m "chore(#352): drop background-location mode, Always usage string, and health background-delivery entitlement (352-G)"
```

---

### Task 9: Doc close-outs + #323 residue note (352-H, 352-I)

**Files:**
- Modify: `CLAUDE.md`, `README.md`, `SECURITY.md`, `CLEAN_CHAT_PATH.md`, `OPEN_ITEMS.md` (#323 entry + #352 entry), `OPEN_ITEMS-ARCHIVE.md` (only if a sweep finds a falsified still-live claim)

- [ ] **Step 1: CLAUDE.md** — three corrections, each a dated supersession in place: (a) the "What this is" line ("retained **only** for sensor ingestion + the `hermes_mobile` MCP tools") gains "(#352 retired the app-side sensor path 2026-08-16; the fork rationale is historical)"; (b) the iCloud Private Relay gotcha gains "(moot for sensors since #352 — nothing uploads; the note stands for any other HTTP-to-tailnet path)"; (c) the HealthKit-on-`SensorUploadService.start()` gotcha is superseded: "HealthKit re-auth on start (#352: `SensorUploadService` is deleted; `DeviceHealthTool.performRead` does its own per-read `requestAuthorization`, which is why query-time needs no launch-time re-assert)".
- [ ] **Step 2: README.md** — rewrite the paired-tier sensor claims (:8, :26, :36, :75, :131): the paired tier's sensor story is now "your agent can ask the phone at query time (talaria plugin)"; the sensor-pipeline feature row and the connector "sensor pipeline and inbox go nowhere" line get replaced or dated. **SECURITY.md** (:34, :62-63): mark the relay's sensor-ingestion description historical (relay Stopped+Disabled #346; app-side path deleted #352). **CLEAN_CHAT_PATH.md**: one dated supersession note at the top of the sensor-plane description ("#352, 2026-08-16: the app-side sensor upload path is deleted; sensors are query-time via the talaria plugin — the narrative below is historical").
- [ ] **Step 3: #323 residue note** — dated block in the #323 entry: capture-behind-cover and upload-behind-cover died with #352 (the §V1 sensor lines cannot recur — code deleted); the surviving covered-state exposure is a phone query answered while the cover is up (`TalariaPlatformLink` drains during covered-active) plus the untouched chat/voice mechanism; #323 stays open.
- [ ] **Step 4: Archive sweep** — `rg -n "SensorUploadService|sensor pipeline" OPEN_ITEMS-ARCHIVE.md | head -30`; add #317(a) append-only pointer blocks ONLY where an entry asserts a still-live pipeline as present-tense fact (history stays untouched).
- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md README.md SECURITY.md CLEAN_CHAT_PATH.md OPEN_ITEMS.md OPEN_ITEMS-ARCHIVE.md
git commit -m "docs(#352): close-outs — CLAUDE.md/README/SECURITY/CLEAN_CHAT_PATH supersessions, #323 residue recorded (352-H, 352-I)"
```

---

### Task 10: Gate + PR (352-J)

- [ ] **Step 1: TCC grants** (immediately before the run — a fresh sim HANGS without them):

```bash
UDID=$(xcrun simctl list devices | grep "CC-lane-1" | grep -oE '[0-9A-F-]{36}')
xcrun simctl privacy "$UDID" grant calendar  org.aethyrion.talaria27
xcrun simctl privacy "$UDID" grant reminders org.aethyrion.talaria27
```

- [ ] **Step 2: Run the gate** (backgrounded; poll the log):

```bash
DEVELOPER_DIR=/Applications/Xcode-beta5.app/Contents/Developer TALARIA_SIM_NAME=CC-lane-1 nohup scripts/mac/lane-gate.sh > /tmp/gate-352.log 2>&1 &
```
Expected: `GATE: PASS` with positive markers from units + XCUITest + Release. On failure read `scripts/mac/lane-gate-classify.sh`'s verdict — it attributes per-test and fails safe.

- [ ] **Step 3: State the counts** — baseline (pre-lane) vs final, with each deleted suite and its test count enumerated so the downward delta reconciles, plus the purge tests' +2 (352-J's "stated and MOVED").

- [ ] **Step 4: Open the PR** — title `feat(#352): retire the sensor-ingestion/upload pipeline`; body: bars 352-A..K with per-bar evidence (the rg outputs, the count reconciliation, both xcodegen hashes, gate log tail), the surviving-call-site enumeration (352-B), mechanical-edit callout per test file (352-C), and a prominent **DO NOT MERGE — awaiting Owen's review**. Report the URL and stop; the device arms (352-B/352-C) run post-merge on `whoGoesThere` with Owen.

---

## Self-review record

- Spec coverage: every DELETE-table row lands in Tasks 1-8; every KEEP row is either untouched (Global Constraints) or explicitly preserved (setters, toggles, grandfathering, BGAppRefresh reconcile+widget lines). Bars: 352-A (T3), 352-B (T2/T4, device arm post-merge), 352-C (T3 suite + post-merge), 352-D (T1), 352-E (T4/T6), 352-F (T5), 352-G (T8), 352-H/I (T9), 352-J (T10), 352-K (T7).
- Known verify-at-implementation points (called out in their steps, not placeholders): `locationColor` callers, `localAlertPayloadKey` orphan check, M-8 test references, protocol mock conformance list, archive sweep hits.
