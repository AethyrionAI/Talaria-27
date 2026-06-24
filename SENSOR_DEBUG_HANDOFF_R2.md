# Sensor Pipeline Debug — Session Handoff (Round 2)

**Date:** 2026-06-23  
**Branch:** `feat/phase-b-wiring`  
**Prior handoff:** `SENSOR_DEBUG_HANDOFF.md` (round 1)

---

## What happened this session

### Root cause of invisible diagnostics: os_log level filtering

The round-1 console capture (console.txt) showed `start()` firing but zero drain, callback,
or gate logs. The reason: **Console.app does not show `.info` level messages by default.**
Almost all the diagnostic instrumentation added in commit `7639ec1` used `sensorLog.info()`,
which maps to the `info` os_log level — invisible in the default Console.app view.

Only `.notice` (→ `default`) and `.warning`/`.error`/`.fault` appear without toggling
"Action → Include Info Messages".

### What the console.txt DID reveal

**Second launch (PID 2891, 22:56:54) — privacy fix confirmed working:**

| Finding | Detail |
|---------|--------|
| `start()` fires | Outbox: 1 location + 13 health samples (stale) |
| **Health auth = `notDetermined`** | HealthKit was NEVER authorized on this Talaria install |
| Location auth = `authorizedWhenInUse` | Location permissions are granted |
| Launched by `locationd` into background | `scenePhase` never becomes `.active` |
| No `.warning` BLOCKED logs | Guards may be PASSING (but `.info` "proceeding" is invisible) |
| No `initialize:` notice log | `initialize()` either fails at silent early guard or succeeds past notice |

**The app was woken by locationd** (line 3943: "open application request from locationd"),
so it started in BG-Active state. The SwiftUI `.onChange(of: scenePhase)` handler for `.active`
**never fires**, meaning `container.handleAppDidBecomeActive()` is never called for this process.
Only `handleSystemLaunch()` runs.

### Changes made

1. **Upgraded ALL diagnostic `sensorLog.info()` → `sensorLog.notice()`** in SensorUploadService:
   - Sensor callbacks: 📍 location, 💓 health, 🏃 activity
   - `captureHealthSnapshot()` results (nil, empty, sample count)
   - `drainOutboxIfPossible()` start/finish + upload results
   - `executeUpload()` delivery state
   - `handleAppDidBecomeActive` / `handleSystemLaunch` entry logs

2. **Added diagnostic logging to silent guards** in AppContainer:
   - `initialize()`: now logs on isPaired failure, isInitialized skip, accessToken failure
   - `handleSystemLaunch()`: logs entry + guard results + "guards passed"
   - `handleRemoteNotificationWake()`: same pattern
   - `handleAppDidBecomeActive()`: `.info` → `.notice` for "proceeding"

---

## Confirmed issues

### Issue 1: HealthKit auth = `notDetermined`

The Talaria install has never called `HKHealthStore.requestAuthorization()`. No health data
can flow until this is triggered. Owen granted permissions through the OS Settings UI, but
HealthKit requires an in-app `requestAuthorization()` call before queries return data.

The `PermissionsStore.reloadCapabilities()` call in `initialize()` may need to explicitly
request HealthKit authorization if it hasn't been done yet.

### Issue 2: Background-only launches skip `handleAppDidBecomeActive`

When `locationd` wakes the app into background, only `handleSystemLaunch()` fires (from
`didFinishLaunchingWithOptions`). The SwiftUI `.onChange(of: scenePhase)` for `.active`
never triggers. This means `handleAppDidBecomeActive` on both AppContainer and SensorUploadService
is skipped entirely. The sensor service's `handleSystemLaunch()` does call
`captureHealthSnapshot()` + `drainOutboxIfPossible()`, but:
- With HealthKit `notDetermined`, health capture returns nil
- Whether drain runs and with what result was invisible (now fixed)

### Issue 3 (possible): Relay pairing status

The sensor upload pipeline uses `isPairedProvider` and relay access tokens. If the fresh
Talaria install was never paired with OJAMD's relay (via 8-digit code), `isPairedProvider()`
returns false and drain is permanently blocked. The next console capture will confirm.

---

## How to continue

### Step 1: Rebuild and redeploy

```bash
cd /Users/owenjones/Documents/Claude/Talaria
env DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild -project Talaria.xcodeproj -scheme Talaria \
  -destination 'id=91CBCB90-B313-5B09-A405-E0FE284C9D75' \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=DNL25ZFSD2 build

PHONE=91CBCB90-B313-5B09-A405-E0FE284C9D75
APP="$HOME/Library/Developer/Xcode/DerivedData/Talaria-bkmofmhhchhruzcdudrizbbblrae/Build/Products/Debug-iphoneos/Talaria for Hermes Desktop.app"
xcrun devicectl device install app --device "$PHONE" "$APP"
xcrun devicectl device process launch --device "$PHONE" org.aethyrion.talaria
```

### Step 2: Recapture console logs

1. Console.app → select **whoGoesThere** → filter `org.aethyrion.talaria`
2. Launch app, wait 5s for init, background it, re-open it
3. ALL diagnostic messages will now appear at `default` level — no "Include Info" needed

### Step 3: Read the logs

With the upgraded logging, the console will now show one of these diagnostic paths:

**Happy path (unlikely given HealthKit issue):**
```
handleSystemLaunch: entered
handleSystemLaunch: guards passed, starting sensor service
start() — activating sensor pipeline...
handleSystemLaunch: capturing health + draining outbox
captureHealth: got N samples
drain: starting...
drain: location upload ✅ delivered
drain: finished. Outbox remaining: loc=false, health=0
```

**Pairing blocked (likely):**
```
handleSystemLaunch: entered
handleSystemLaunch: BLOCKED — not paired
```

**Token blocked:**
```
handleSystemLaunch: entered
handleSystemLaunch: BLOCKED — no access token
```

**Health nil + drain blocked by pairing:**
```
handleSystemLaunch: guards passed, starting sensor service
start() — activating sensor pipeline...
handleSystemLaunch: capturing health + draining outbox
captureHealth: collectSnapshot returned nil (auth=notDetermined)
drain: BLOCKED — isPairedProvider() returned false
```

### Step 4: Fix based on diagnosis

- **"not paired"** → Talaria needs to be paired with OJAMD's relay via 8-digit code
- **"no access token"** → Relay session expired or never established
- **"isPairedProvider() returned false"** → Same as "not paired" but at sensor service level
- **"collectSnapshot returned nil"** → HealthKit `requestAuthorization()` needed in-app
- **"drain: ❌ failed"** → Relay HTTP error, check `upload: error —` line for details

---

## Files modified

| File | What changed |
|------|-------------|
| `Talaria/Services/Live/SensorUploadService.swift` | All `.info` → `.notice`; added `handleSystemLaunch` logging |
| `Talaria/Stores/AppContainer.swift` | Silent guard logging in `initialize`, `handleSystemLaunch`, `handleRemoteNotificationWake`; `.info` → `.notice` in `handleAppDidBecomeActive` |
| `SENSOR_DEBUG_HANDOFF_R2.md` | This file |
