# #252 companion — Settings surface control inventory (as-built, 2026-08-05)

Produced by a read-only sweep of `Talaria/Features/Settings/` at `main` ≈ `2e88cc2`.
This is the canonical "every control must land somewhere" checklist for the #252 spec
(`2026-08-05-252-settings-channels-design.md`). Ignore `.claude/worktrees/` copies
(stale; includes a deleted NotificationsSettingsScreen).

## Files

| File | Role |
|---|---|
| `SystemSettingsScreen.swift` | THE ROOT (380 lines) |
| `UplinkSettingsScreen.swift` | Hermes Host / direct link |
| `ServerSettingsScreen.swift` | Backend profiles |
| `ModelsSettingsScreen.swift` | Model catalog + chat brain |
| `AppearanceSettingsScreen.swift` | #244 channel browser + Tuning sheet |
| `AppIconSettingsScreen.swift` | Icon grid (child of Appearance Tuning) |
| `VoiceSettingsScreen.swift` | Talk engine + read-aloud |
| `PrivacySettingsScreen.swift` | Permissions, sensors, App Lock, Spotlight |
| `SessionsSettingsScreen.swift` | Sessions & data |
| `DiagnosticsSettingsScreen.swift` | System health + THE ENTIRE #200 battery harness (1,869 lines) |
| `DeveloperSettingsScreen.swift` | Environment, flags, monetization |
| `BatteryResultsScreen.swift` | DEBUG-only, 3 nested screens |
| `ConnectHermesHostScreen.swift` | Pairing & Devices — router-level, NOT in the settings stack |
| `ModelTransitionOverlay.swift` | Overlay on Models |
| `SettingsScreenHeader.swift` | Shared sub-screen header |
| `SettingsSectionView.swift` | Titled panel wrapper (used once: Models → Chat Brain) |
| `ThemeChannels.swift` | Channel-list builder for Appearance |

## 1. Root — SystemSettingsScreen

Presented by `ContentView.sheetDestination(.settings)` → `NavigationStack`,
`.presentationDetents([.large])`. Opened from the chat gear (`"Open settings"`), the
chat menu (⌘,), and two programmatic paths. NOT a `List`: HUDScreenBackground +
ScrollView + hand-built `.groupPanel()` groups with `MonoLabel("// Name")` headers.
Row = iconTile + title + value MonoLabel + chevron.

Order:
- Header: `SYSTEM` / `Talaria Control`; ✕ GlassCircleButton (Esc) → dismiss.
- **Host panel** (info): ReactorOrb + hostName (`hostStore.currentHost?.resolvedDisplayName`)
  + status line (`LINKED · DIRECT|RELAY · <connectionStatus>` / `OFFLINE · STANDBY` /
  `UNREACHABLE · CHECK UPLINK` / `NOT LINKED`) + StatusPip (blinks on unreachable).
- `// Connection`:
  1. **Connect Hermes Desktop** — Button, subtitle "Adds server sessions, sensors &
     desktop models", `UPGRADE` badge → `router.dismissSheet()` + `.navigate(.connectHost)`.
     **Only when `!pairingStore.isPaired`.**
  2. **Hermes Host** → UplinkSettingsScreen; value `DIRECT/RELAY/STANDBY/OFFLINE/NOT LINKED`.
  3. **Server** → ServerSettingsScreen; value = active profile name uppercased, else `PAIRED`/`SET UP`.
  4. **Models** → ModelsSettingsScreen; value = `chatStore.activeModelName` else `SELECT`.
- `// Experience`:
  5. **Appearance & HUD** → AppearanceSettingsScreen; value HARDCODED `"REACTOR"`.
  6. **Voice & Talk** → VoiceSettingsScreen; value HARDCODED `"REALTIME"`.
  7. **Privacy** → PrivacySettingsScreen; value `"MANAGE"` (verb, not status).
- `// Data & System`:
  8. **Sessions & Data** → SessionsSettingsScreen; value `"N SESSION(S)"` from async
     `loadSessions().count` cached in `@State` (`"DATA"` until loaded) — the ONLY
     network-priced root value.
  9. **About & Diagnostics** → DiagnosticsSettingsScreen; value `HEALTHY`/`DEGRADED`.
- `// Developer`:
  10. **Developer** → DeveloperSettingsScreen; value = environment label. **NOT
      DEBUG-gated** (#231/#228 — Release needs a path to Verbose Logging; re-hiding is
      "a Phase 7 decision").
- Footer: `TALARIA v<version> · DEVICE-BOUND`.

## 2. Uplink — "UPLINK" / subtitle = active profile name

1. SettingsScreenHeader. 2. Link status panel (orb + `DIRECT LINK/RELAY LINK/STANDBY/
OFFLINE/NOT LINKED` + detail + pip). 3. "PAIRED — KEY MISSING" nudge (conditional:
`unkeyedNudgeVisible` — paired AND key blank). 4. **Base URL** TextField (writes BOTH
`profilesStore.updateActiveProfile{$0.gatewayBaseURL}` and
`settings.hermesAPIBaseURL`). 5–7. **API Key** SecureField + status text + Save/Saved
capsule (`container.saveHermesAPIKey`; monetization gate → ConnectedPaywallSheet).
8. **Pairing & Devices** GlowButton → router `.connectHost`. 9. **Test Connection**
GhostButton (5s probe of `<base>/v1/models`). 10. Test status row: `TESTING <host>` /
`ONLINE · N MS` / `REFUSED`/`NO ANSWER`/`NO HOST`/`NO KEY`/`HTTP <code>`/`NOT SET`/`FAILED`.
`.onChange(of: gatewayBaseURL)` resets the test state.

## 3. Server — "SERVER" / "Backend Profiles"

Profile cards (per `profilesStore.profiles`): name + active check, host label, note,
`ACTIVE`/`SENSORS` tags, `GATEWAY <ONLINE|NO KEY|OFFLINE|—>` probe row, `PAIRED`/`NOT
PAIRED`, ellipsis Menu + identical contextMenu. Actions: Edit; Pair/Re-Pair;
Refresh Provisioning (paired only); Forget Pairing (paired only, destructive);
Route Sensors Here (when not destination); Delete (when not active and not sensor
destination). Then: provisioning message; **Add Profile** (paywall gate);
**Auto-connect on launch** Toggle (`settings.autoConnectOnLaunch`); delete error.
Alerts (all `.alert` per #193): "Switch backend?", "Forget this pairing?", "Delete this
profile?". Sheets: ProfileEditorSheet (Name / Gateway URL / Relay URL / Note / API Key
+ validation + Add/Save), ConnectedPaywallSheet.

## 4. Models — "MODELS"

Also standalone sheet (`.settingsModels`). Bespoke header (chevron back, Esc).
- **Chat Brain** (SettingsSectionView; conditional `showsBrainPicker`): **Automatic**
  ("Hermes when reachable, on-device otherwise") + `selectableBrains` rows +
  Private Cloud quota row (`BELOW/NEARING/REACHED [· RESETS <t>]` + "Show options"
  when suggestion available) + footer `ROUTING NEXT MESSAGE: <brain>`.
- Freshness bar `MODEL CATALOG · gateway · /api/model/options` + Refresh capsule.
- Status/error lines. **Host default** row (checkmark when no explicit pick).
- Provider sections → model rows (checkmark, per-row ProgressView while applying) →
  `container.applyModelSelection`. `N MORE PROVIDERS NEED SETUP`. Error panel + Retry.
- **ModelTransitionOverlay**: ACTIVATING telemetry lines → SUCCESS (auto-dismiss 750ms)
  / ERROR (Dismiss + Retry), 12s watchdog.

## 5. Appearance — #244 channel browser (full-bleed paged TabView)

Top bar: back (Esc) · `APPEARANCE` + `CHANNEL %02d / %02d` (**a11y id
`appearance.channelCounter`** — the ONLY identifier in the settings surface) ·
"Surprise me". Per channel: orb, name, slot line, section capsule (+ lock), spectrum
strip, 3 accent dots (hidden when `locksAccent`, #12), TUNING handle. Bottom:
prev/Surprise Me/next. Apply-on-land via `.onChange(of: selectedChannelID)`.
**TUNING sheet** (420pt detent): Glow Slider (`hudGlowIntensity`), Grid segments
(`gridDensity`), Reduce Motion Toggle, Haptic Feedback Toggle (#238 relocation),
**App Icon** nav-link → AppIconSettingsScreen.

## 6. App Icon — "APP ICON" / "Home Screen"

Entry ONLY via Appearance Tuning. Unsupported-device notice; error notice; sectioned
LazyVGrid of icon cards (thumbnail + name + subtitle, accent border + check when
selected) → `AppIconStore.select`; footer "SELECTION PERSISTS ACROSS RELAUNCH".

## 7. Voice — "VOICE" / "Talk Engine"

Hero panel (orb + engine descriptor + state + pip). `// Status`: Engine / Host /
Configured / Ready info-rows + blockedReason prose. `// Model & Voice` (read-only):
Model / Voice / Voice Context + "managed on the Hermes host" caption. `// Read-Aloud`:
**Auto-Read Replies** Toggle (`readAloudAutoPlay`); **Voice** Menu picker (System
Default + available voices with tier suffixes → `readAloudVoiceIdentifier`); **Speed**
Slider 0.3–0.7 (`readAloudRate`); Personal Voice footer (Enable button / prose by
authorization state); **Preview Voice** GhostButton. `// Transcripts`: **Send
Transcripts to Hermes** Toggle (`postVoiceTranscriptsToHermes`) + caption.
`// Last Session`: Bootstrap / Connect / First Reply metrics. **Start Voice Session**
GlowButton (disabled unless `canStartSession`; dismisses sheet then presents voice
overlay). Footer engine line.

## 8. Privacy — "PRIVACY" / "Permissions" (App Lock lives here)

`// Permissions`: rows for location/health/motion/microphone → `ENABLE ›` (request) or
`MANAGE ›` (system settings). `// Sensor Streaming` (#137): **Stream Sensors to
Hermes** master Toggle (`setSensorStreamingEnabled`) + Health/Location/Motion child
toggles (visible only when master on). `// Location`: Accuracy info-row; Foreground
Only / Background segments (`locationSyncPreference`). `// App Lock` (#124): Toggle
labelled by capability ("Require Face ID"/…) → `appLockEnabled` (+ grace-period
segments when on). `// System Search` (#17): **Spotlight Indexing** Toggle (+ donation
refresh/removal side effects). `// Revoke / Reset` (#6): Health/Location revoke rows
with confirm alerts. **Manage in System Settings** button.

## 9. Sessions — "SESSIONS" / "Storage & Data"

Stat tiles: Sessions / Messages (K-abbrev) / Active. `// Shelf`: **Show Empty
Sessions** Toggle (#187 caption). `// Recent`: up to 8 session rows (active dot,
title, relative time · N MSGS, optional cost line from `SessionCostReadout`) →
`chatStore.openSession` + dismiss; Loading/empty states. `// Manage`: **Export
Conversations** (JSON → ShareSheet) and **Clear Conversation** (destructive, confirm
alert). Footer "Sessions stored on the Hermes host".

## 10. Diagnostics — "DIAGNOSTICS" / "System Health" (hosts the #200 battery harness)

Order: status panel → voice panel → sensor panel → local-brain panel (DEBUG) →
info grid → logs → footer links.
- Status: **Hermes API** (`REACHABLE/CHECKING/UNREACHABLE/ERROR` ←
  `chatStore.directConnectionStatus`); **Relay Link** (← `sessionStore.state`);
  **Relay Identity** (`STALE — RE-PAIR` blink / `USER <8>` / `· UNVERIFIED` / `—`);
  **Location** (auth level).
- `// Voice / Talk` (#84): Microphone / Speech Recognition / Audio Route.
- `// Local brain — #102` — **#if DEBUG**: session-shape Picker (13 shapes,
  `debug.sessionShape`), ~46 battery/probe launcher buttons (shape/router/action/
  read-tool/motion/scoped/routed/intent/destall/…/honesty v2 + WeatherKit probe +
  alarm sweep), forced-trip panel (2 buttons), **Battery results →** →
  BatteryResultsScreen (3 nested DEBUG screens: run list / run detail with Copy+Share
  / trial list). All battery buttons set idle-timer-disabled + auto-accept/decline.
- `// Sensor Pipeline` (#15): Pipeline / Paired / Access Token / Pending Location /
  Pending Health / Last Drain / Location / Health / Motion (from
  `sensorUploadService.sensorDiagnostics`; sync property — `hasValidAccessToken()` is
  async, don't card it).
- Info grid: App Version / Host Version (`—`) / Uptime (`—`) / Device.
- `// Logs`: placeholder ("In-app log buffer not yet captured" / Console.app filter).
- Footer links: Terms · Privacy · Support (conditional).

## 11. Developer — "DEVELOPER" / "Internal Tools" (Verbose Logging lives here)

NOT DEBUG-gated as a screen; three sections inside are. Warning banner ("visible in
all builds until launch (#231)"). `// Environment`: env rows (Production-only in
Release) → `settings.environment`. `// Flags`: **Verbose Logging** Toggle
(`settings.verboseLogging` + `TalariaLog.setVerbose`); **Composer Writing Tools**
Toggle + iOS 27 b2 freeze warning (#4). `// Generative UI` (DEBUG): IR v0 Harness →
GenUIDebugScreen. `// Monetization` (#127, DEBUG): Connect Gate Toggle; Entitlement
Override menu Picker; STOREKIT info-row. `// Sensor opt-in migration` (DEBUG): Clear
migration stamp. `// Build`: VERSION / BUILD / COMMIT (`—`).

## 12. ConnectHermesHostScreen — "Pairing & Devices" (#152)

Router-level (`.connectHost`), NOT in the settings stack; reached from root row 1,
Uplink, Server per-profile Pair, and chat. Host status card; setup card (3
`hermes-mobile` steps, when no host); actions: **Pair New Device (QR)**, **Revoke
Host** (conditional, destructive), **Disconnect** (destructive); error banner.

## 13. Cheap telemetry for cards (store → cost)

| Value | Source | Cost |
|---|---|---|
| Link state | `chatStore.directConnectionStatus` + `hostStore` state | free |
| Host name | `hostStore.currentHost?.resolvedDisplayName` | free (async refresh) |
| Active model | `chatStore.activeModelName` | free |
| Brain label | `chatBackendRouter.activeBrain.monoLabel` | free |
| Voice engine/state | `talkStore.voiceEngine` / `.connectionState` / `.readiness` | free (probe async) |
| Sensor streams enabled | `settings.sensorStreamingEnabled` + 3 child booleans | free |
| Sensor pipeline | `sensorUploadService.sensorDiagnostics` | free |
| Session count | `await chatStore.loadSessions().count` | **network** (cache in @State) |
| Health verdict | derived: connection online → HEALTHY else DEGRADED | free |
| Theme + accent | `ThemeRuntime.shared.theme/.accent` + ThemeChannels index | free |
| Environment | `settings.environment.displayLabel` | free |
| Active profile | `profilesStore.activeProfile?.name` | free |
| Paired | `pairingStore.isPaired` | free |
| App version | Bundle | free |

## 14. Tests touching settings navigation

`TalariaUITests/AppTemplateUITests.swift`:
- `testStandaloneFirstLaunchLandsInChat` — `"Open settings"` button exists.
- `testMockPairingViaSettingsEntryPoint` — Settings → row whose LABEL CONTAINS
  "Connect Hermes Desktop" → Enter Code Manually → redeem.
- `testPairedRelaunchSkipsPairingEntry` — paired: "Connect Hermes Desktop" ABSENT.
- `testDisconnectReturnsToStandaloneChat` — row containing "Hermes Host" →
  "Pairing & Devices" → Disconnect → upsell returns. (Has an iOS-27 re-tap hedge.)
- `testAppearanceChannelBrowserAppliesThemeOnLand` — row containing "Appearance" →
  `appearance.channelCounter` exists; Next theme; apply-on-land persistence.
**Rows are matched by label containment, not identifiers** — the redesign must either
preserve those label strings or (better) introduce identifiers and update the tests.

Unit: `ServerSettingsTests` (probe classify, unkeyed nudge, editor draft),
`AppLockTests`, `ModelsPickerModelTests`, `IPadAdaptationTests` (⌘,).

## 15. Idioms (all preserved by #252)

No SwiftUI `List` anywhere; HUDScreenBackground + ScrollView + `.hudPanel` groups;
`MonoLabel("// Name")` section headers; destructive confirms are `.alert`, never
`.confirmationDialog` (#193); two hardcoded root values (REACTOR / REALTIME) are the
known telemetry gaps; `SettingsSectionView` used exactly once.
