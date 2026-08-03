# Notification Removal (#238) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete the app's entire notification surface (APNs registration, delegate, producers, push-token pipeline, settings UI, entitlement/background mode) in one clean cut, per the approved spec `docs/superpowers/specs/2026-08-03-notification-removal-design.md`.

**Architecture:** Consumers are cut before producers so every intermediate task compiles: settings model → ChatStore → AppContainer → stores/protocols/services → AppEntry → UI → project config. Deletion is verified by absence greps (238-B) and a counted suite delta, never by green alone.

**Tech Stack:** SwiftUI / swift-testing, xcodegen, `scripts/mac/lane-gate.sh`.

## Global Constraints

- Branch: `claude/t27-238-notification-removal` (cut from main ≥ `7bb9bd9`).
- `DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer` in every shell.
- `xcodegen generate` mandatory after adding/removing Swift files.
- Suite baseline on main: **1565**. After test edits, count the expected delta and record it in the #238 entry BEFORE the verification run; the reported count MUST move to exactly that number (stale-`.xctest` rule).
- `-only-testing:` at FILE/suite level only (function-level silently selects zero).
- **STAYS untouched:** BGAppRefresh scheduling/handler (comment rewrite only), Live Activities, inbox/briefings, sensors, relay device registration (only its APNs token field goes), durable installation identity, the relay itself.
- Bars 238-A–E are already pre-registered in the spec; Task 1 copies them into the OPEN_ITEMS #238 entry before any verification run.
- Gate (Debug suite + Release build) before PR. Hook disarm + OTA happen at merge time on Owen's word (Task 10) — NOT before.

---

### Task 1: Branch + OPEN_ITEMS #238 entry (bars first)

**Files:**
- Modify: `OPEN_ITEMS.md` (new entry above #237)

**Interfaces:** Produces the #238 entry every later task's records append to.

- [ ] **Step 1: Branch**

```bash
git checkout -b claude/t27-238-notification-removal
```

- [ ] **Step 2: Write the #238 entry** — title: `## 238. ✂️ NOTIFICATION REMOVAL — the pivot's first cut (post-#235/#237, banners are scaffolding around a fixed defect) — LANE OPEN 2026-08-03`. Body: two-paragraph rationale from the spec (Owen's "the notification is moot" quote; #47 collateral accepted; Live Activities stay), then a `## 📋 BARS — PRE-REGISTERED 2026-08-03 evening, BEFORE the run. Written first.` block copying 238-A through 238-E verbatim from the spec, then a line reserving the counted suite delta: "Expected suite count after edits: recorded in Task 8's commit before the verification run."

- [ ] **Step 3: Commit**

```bash
git add OPEN_ITEMS.md && git commit -m "OPEN_ITEMS #238: notification removal lane open, bars pre-registered"
```

### Task 2: UserSettings loses `notificationsEnabled`, decode-tolerantly (TDD)

**Files:**
- Modify: `Talaria/Models/UserSettings.swift` (property ~353, init param ~415, assignment ~446, CodingKeys ~479, `init(from:)` ~513)
- Modify: `Talaria/Components/DemoData.swift:167` (drop arg)
- Modify: `TalariaTests/AppStoresTests.swift:2448` (drop arg)
- Test: `TalariaTests/AppStoresTests.swift` (new test near the other UserSettings decode tests)

**Interfaces:** Produces a `UserSettings` with no `notificationsEnabled` member — later tasks (7) rely on its absence compiling.

- [ ] **Step 1: Write the failing test** (fails to compile once the property is gone is NOT the point — this test must pass BEFORE and AFTER, proving tolerance; write it first, watch it pass against current code, then keep it green through the removal):

```swift
@Test func settingsJSONCarryingRetiredNotificationsKeyStillDecodes() throws {
    let legacy = """
    {"userName":"Owen","notificationsEnabled":false,"hapticFeedbackEnabled":false}
    """.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(UserSettings.self, from: legacy)
    #expect(decoded.userName == "Owen")
    #expect(decoded.hapticFeedbackEnabled == false)
}
```

- [ ] **Step 2: Run it, expect PASS (pre-removal green pin)**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer xcodebuild test -project Talaria.xcodeproj -scheme Talaria -destination 'platform=iOS Simulator,id=<pinned sim>' -only-testing:TalariaTests/AppStoresTests 2>&1 | tail -5
```

- [ ] **Step 3: Remove the member** — delete the `var notificationsEnabled: Bool` declaration, the init parameter + assignment, the CodingKeys case, and the `init(from:)` line. Drop the `notificationsEnabled: true,` argument at `DemoData.swift:167` and `AppStoresTests.swift:2448`. (JSONDecoder ignores unknown JSON keys, so a stored key with no CodingKeys case is skipped — the Step-1 test now pins that.)

- [ ] **Step 4: Re-run the test — PASS; commit**

```bash
git add -A && git commit -m "#238 T2: UserSettings drops notificationsEnabled, decode-tolerant (pinned)"
```

### Task 3: ChatStore drops the notifications dependency

**Files:**
- Modify: `Talaria/Stores/ChatStore.swift` (~154 property, ~395 init param + default + init-body priming Task, ~819 priming Task, ~1893–1896 notify block)
- Modify: `TalariaTests/AppStoresTests.swift` (~716 `PrimingSpyNotifications` + every test using it; any `notifications:` label in ChatStore constructions)

**Interfaces:** Produces `ChatStore.init(hermesClient:persistence:journal:)` — Task 5's constructor-arg sweep must NOT touch ChatStore (its label is `notifications:`, already gone here).

- [ ] **Step 1: Delete production references** — the `private let notifications` property, the `notifications:` init parameter and `?? LocalNotificationService()` default, the init-body `Task { await self.notifications.requestAuthorizationIfNeeded() }`, the ~819 priming Task (keep the surrounding `startReconcileLoopIfNeeded()` / `continuedSend?.finish` logic), and the ~1893 block `if UIApplication.shared.applicationState != .active { notifications.notifyRunCompleted(...) }` (delete the whole conditional; keep `finalizeOnDeviceIntelligence()`).
- [ ] **Step 2: Delete test scaffolding** — `PrimingSpyNotifications` and the priming-trigger tests that inject it; remove `notifications:` labels from any remaining ChatStore constructions. Record how many `@Test` functions were deleted (feeds the counted delta).
- [ ] **Step 3: Compile check** (Debug CLI build, backgrounded if slow) — expect the ONLY remaining errors to be in files later tasks own; if ChatStore-adjacent errors appear, fix before committing.
- [ ] **Step 4: Commit** — `#238 T3: ChatStore sheds LocalNotificationScheduling (priming + completion notify)`

### Task 4: AppContainer sheds the push pipeline and notification handlers

**Files:**
- Modify: `Talaria/Stores/AppContainer.swift`
- Modify: `Talaria/Models/AppSessionState.swift:26` (drop `registeredPushToken`)
- Modify: `Talaria/Services/Live/LiveSessionBootstrapService.swift` (~156–160 `locallyHeldAPNsToken` + its use in the registration payload)

**Interfaces:** Consumes nothing new. Produces an AppContainer with NO `notificationService`/`localNotifications` members and NO `handleNotificationTap/Reply/RemoteNotificationWake/registerPushTokenIfNeeded` — Task 6 (AppEntry) relies on their absence.

- [ ] **Step 1: Delete whole functions** (anchor by name, not line): `handleNotificationReply(_:sessionID:)` (~1604, includes both `notifyReplyFailed` sites), `handleNotificationTap(sessionID:)` (~1680), `handleRemoteNotificationWake()` (~1691), `pushTokenPipelineState` (static + computed + the `PushTokenPipelineState` type), `registerPushTokenIfNeeded(_:)`, `registerPushTokenWithActiveRelay(...)` (+ its `PushRegisterBody`), the profile-switch re-register block (second `PushRegisterBody`, ~1969–2010), `setNotificationsEnabled(_:)` (~2091), `registerStoredPushTokenIfNeeded()` (~2164) and its call inside `handleSystemLaunch()` (the rest of `handleSystemLaunch` STAYS), `cachedAPNsDeviceToken`, `apnsTokenDefaultsKey`.
- [ ] **Step 2: Delete members/wiring** — `private let localNotifications = LocalNotificationService()` (109), `notificationService` property/param/assignment (121/161/178), `LiveNotificationService()` creation in `makeDefault` (358) and pass-throughs (419/735/745). Where a deleted call sat inside a kept function, remove only the call.
- [ ] **Step 3: AppSessionState** — delete `var registeredPushToken: String?`; check its CodingKeys/decode the same tolerant way as Task 2 (if it has explicit CodingKeys, drop the case).
- [ ] **Step 4: Bootstrap** — delete `locallyHeldAPNsToken()` and the token field it feeds in the relay device-registration payload; the registration call itself stays.
- [ ] **Step 5: Compile check; expect residual errors only in PermissionsStore/tests/AppEntry/UI (later tasks). Commit** — `#238 T4: AppContainer sheds push pipeline, notification handlers, session token record`

### Task 5: Protocols, services, PermissionsStore, test constructor sweep

**Files:**
- Delete: `Talaria/Services/Live/LocalNotificationService.swift`, `Talaria/Services/Live/LiveNotificationService.swift`, `Talaria/Services/Mocks/MockNotificationService.swift`, `Talaria/Services/Protocols/NotificationServiceProtocol.swift`
- Modify: `Talaria/Stores/PermissionsStore.swift` (12/19/25/34/46/100), `Talaria/Models/PermissionType.swift:6` (drop `case notifications`)
- Modify tests: `ServerSettingsTests.swift:75`, `BackendProfilesTests.swift:98`, `BriefingTests.swift:220`, `ConnectorOutageAlertTests.swift:213`, `InstallationIdentityTests.swift:41/86/95/133`, `AppStoresTests.swift:302/343/457/2548/2663/2720` — drop the `notificationService: MockNotificationService(),` argument at every site.
- Delete: `TalariaTests/PushRegistrationRecordTests.swift` (232 lines, 11 @Test — pipeline + alertsDisplayState tests, all of whose subjects died in Task 4)

**Interfaces:** Produces `PermissionsStore.init` WITHOUT `notificationService:` — the test sweep above is the complete caller list (verify with a grep before committing).

- [ ] **Step 1: PermissionsStore** — remove the dependency + `refreshAuthorizationStatus` + `requestAuthorization` calls + the `.notifications` `DeviceCapability` row. Remove `case notifications` from PermissionType; let the compiler surface every remaining switch arm (PrivacySettings/Diagnostics arms are Task 7's — if they block compilation now, delete those arms in this task instead and note it).
- [ ] **Step 2: Delete the four service/protocol files + PushRegistrationRecordTests; sweep test constructors; `xcodegen generate`.**
- [ ] **Step 3: Verify caller completeness**

```bash
grep -rn 'notificationService\|LocalNotificationScheduling\|MockNotificationService' Talaria/ TalariaTests/ --include='*.swift'
```
Expected: zero hits.
- [ ] **Step 4: Compile check; commit** — `#238 T5: notification services/protocol deleted, PermissionsStore + PermissionType + 13 test constructors swept`

### Task 6: AppEntry cut

**Files:**
- Modify: `Talaria/AppEntry.swift`

**Interfaces:** Consumes Task 4's absences (the handlers it called are gone).

- [ ] **Step 1: Delete** — the `NotificationReplyAction` enum (line 13), `application.registerForRemoteNotifications()`, the `UNUserNotificationCenter.current().delegate = self` + `setNotificationCategories` lines, the `UNUserNotificationCenterDelegate` conformance and both delegate methods (`willPresent`, `didReceive`), `didRegisterForRemoteNotificationsWithDeviceToken`, `didFailToRegisterForRemoteNotificationsWithError`, `didReceiveRemoteNotification(fetchCompletionHandler:)`, the `import UserNotifications` (if present) and the class-doc comment about UNNotificationResponse. KEEP: `LiveActivityService.endAllActivities()`, `SingleWindowPolicy.activate()`, `BackgroundRefreshScheduler.register()`, `handleSystemLaunch()` Task.
- [ ] **Step 2: Compile check (app target should now be clean except UI screens); commit** — `#238 T6: AppEntry sheds APNs registration, notification delegate, lock-screen reply`

### Task 7: Settings UI cut + haptics relocation

**Files:**
- Delete: `Talaria/Features/Settings/NotificationsSettingsScreen.swift`
- Modify: `Talaria/Features/Settings/SystemSettingsScreen.swift` (nav row 176–179 + a `rowDivider`, `notificationsValue`/`notificationsColor` ~363–367)
- Modify: `Talaria/Features/Settings/AppearanceSettingsScreen.swift` (haptics toggle joins the reduce-motion row's section)
- Modify: `Talaria/Features/Settings/PrivacySettingsScreen.swift` (27/34/42/50/577/587/597 — every `.notifications` arm + the enum case at 34 if locally defined)
- Modify: `Talaria/Features/Settings/DiagnosticsSettingsScreen.swift` (Push Token row 74–96, `pushStatus` ~167–175, `.notifications` lookup 188, header comment line 9)

**Interfaces:** Consumes Task 2's UserSettings (no `notificationsEnabled`).

- [ ] **Step 1: SystemSettingsScreen** — delete the Notifications `navRow` block + adjacent `rowDivider` + both derived vars.
- [ ] **Step 2: AppearanceSettingsScreen** — add beside the reduce-motion toggle, using its exact idiom:

```swift
private var hapticsBinding: Binding<Bool> {
    Binding(
        get: { settingsStore.settings.hapticFeedbackEnabled },
        set: { settingsStore.settings.hapticFeedbackEnabled = $0 }
    )
}
```
and a row mirroring the reduce-motion row (same label/toggle structure, title "Haptic Feedback").
- [ ] **Step 3: PrivacySettingsScreen + DiagnosticsSettingsScreen** — delete every `.notifications` arm, the shownPermissions element, the Push Token row + `copyPushToken()` + `pushStatus`; fix the header comment.
- [ ] **Step 4: `xcodegen generate`; full compile check — the app target MUST now build clean. Commit** — `#238 T7: Notifications settings screen deleted, haptics relocated to Appearance, privacy/diagnostics rows cut`

### Task 8: project.yml, BGTask comment, absence sweep (238-B), counted delta

**Files:**
- Modify: `project.yml` (line 49 `aps-environment: development`, line 361 `- remote-notification`)
- Modify: `Talaria/Services/Live/BackgroundTaskService.swift` (comment ~31–37)

- [ ] **Step 1: Remove both project.yml keys; `xcodegen generate`.** Verify `Talaria/Talaria.entitlements` no longer carries `aps-environment` after regen.
- [ ] **Step 2: Rewrite the BGAppRefresh doc comment** to:

```swift
/// Native background wake — the app's only background catch-up path since
/// notification removal (#238): one refresh pass drains the sensor outbox,
/// runs one reconcile fetch, and rewrites widget data. Discretionary by
/// design: iOS decides when a pass runs (can be hours) — a safety net, not
/// real-time delivery. Foreground reconcile (#235) is the primary surface.
```
- [ ] **Step 3: 238-B absence sweep** (must all be empty):

```bash
grep -rn 'UserNotifications\|UNUserNotificationCenter\|UNNotification\|registerForRemoteNotifications\|apnsToken\|apns_token\|aps-environment\|remote-notification' Talaria/ Shared/ TalariaWidgets/ project.yml --include='*.swift' --include='*.yml'
```
- [ ] **Step 4: Full suite run.** Count the new total (the `Test run with N tests` line), verify it equals 1565 − (11 + Task-3 deletions) + (Task-2 test + any other additions), and record that number in the #238 entry + commit message BEFORE calling anything verified.
- [ ] **Step 5: Commit** — `#238 T8: entitlement + background mode removed, 238-B sweep clean, suite delta counted (N)`

### Task 9: 238-A fresh-install UI test, gate, PR

**Files:**
- Test: `TalariaUITests/` (new test beside the existing onboarding UI tests, following their launch-argument idiom)

- [ ] **Step 1: Write the 238-A UI test** — fresh app state, walk far enough to pass onboarding + first chat + settings, and assert the springboard permission alert never appears:

```swift
@MainActor
func testFreshInstallNeverPresentsNotificationPermissionDialog() throws {
    let app = XCUIApplication()
    app.launchArguments += ["-ui-testing-fresh-install"] // match existing reset idiom
    app.launch()
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    // Walk the same path the existing onboarding test walks (reuse its helpers).
    // At each settle point:
    XCTAssertEqual(springboard.alerts.count, 0, "notification permission dialog must never appear")
}
```
(Adapt the walk to the existing onboarding helper methods — read them first; the assertion set is the deliverable.)
- [ ] **Step 2: Run the UI test on the pinned sim after an erase** (`xcrun simctl erase <udid>`), watch it pass.
- [ ] **Step 3: Gate** — `scripts/mac/lane-gate.sh`, backgrounded, poll the log; requires POSITIVE markers incl. Release. On PASS:
- [ ] **Step 4: PR** — title `#238: notification removal — the pivot's first cut`, body summarizing the spec + bars status (A sim-met, B met, C met with counted delta, D/E owed to merge time), ending with the standard generation footer.

### Task 10 (merge time, Owen-routed — do NOT run before his word)

- [ ] Disarm the Mac hook: `rm ~/.hermes/talaria/push/devices/whoGoesThere.json` (OFF switch; no restart).
- [ ] OPEN_ITEMS: #238 record; #223 push lanes (1/3/4) retired-by-pivot note (Lane 6 re-attach UNAFFECTED); retirement notes on #47, #189, #226 leg (b), #31; #133/#143 push-half note.
- [ ] Merge; OTA stage from main on Owen's word; 238-D/E verified after his install.
