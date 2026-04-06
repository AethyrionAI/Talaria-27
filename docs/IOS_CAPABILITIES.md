# iOS Capabilities Reference

A living document tracking every iOS capability integrated into Hermes iOS — what's working, what's next, and how each feeds into the Hermes agent's context awareness.

---

## 1. CoreMotion — Activity Detection

**What it does:** Classifies the user's physical activity in real-time (stationary, walking, running, driving, cycling) using the device's motion coprocessor.

**Data format:** Health metric `user_activity` with numeric activity codes:
| Code | Activity |
|------|----------|
| 0 | Stationary |
| 1 | Walking |
| 2 | Running |
| 3 | Automotive (driving) |
| 4 | Cycling |
| 5 | Unknown |

### Current Status

| Component | State | Detail |
|-----------|-------|--------|
| `LiveMotionService.swift` | Wired | CMMotionActivityManager wrapper with auth + monitoring |
| `SensorUploadService` | Wired | Receives `motionService`, enqueues activity as health metric |
| `AppContainer` | Wired | LiveMotionService instantiated and injected into SensorUploadService + PermissionsStore |
| `PermissionType` | Wired | `.motion` case with icon, color, label, onboarding support |
| MCP tool `get_user_activity` | Wired | Queries `health_latest WHERE metric = 'user_activity'`, returns label + freshness |
| MCP registration | Wired | `get_user_activity`, `get_sensor_schema`, `query_sensor_data` in `MCP_TOOL_NAMES` |
| Voice context | Wired | `talk_support.py` includes "User is currently walking" when fresh |

### Next Steps
- [x] Add `LiveMotionService` instantiation to `AppContainer.makeDefault()`
- [x] Pass it to `SensorUploadService` init
- [x] Add `.motion` to `PermissionType` enum + onboarding permissions
- [x] Add `"get_user_activity"` to `MCP_TOOL_NAMES` in `mcp_registration.py`
- [ ] Run `hermes-mobile configure-mcp` to update the Hermes config
- [ ] Test on physical device (verify permission prompt + activity updates)

### Use Case Ideas
- **Context-aware responses**: "You've been sitting for 2 hours — time for a walk?" (proactive health nudge)
- **Smart notifications**: Don't send non-urgent messages while user is driving
- **Activity logging**: "How active was I this week?" → agent queries activity history from sensor pipeline
- **Hermes Skill**: iOS-aware skill that checks `get_user_activity` before deciding how to deliver information (voice summary while walking vs detailed text while stationary)

---

## 2. Live Activities (ActivityKit)

**What it does:** Shows persistent, real-time Hermes status on the Lock Screen and Dynamic Island during voice sessions, tool calls, or active agent work.

**Data model:** `HermesActivityAttributes` (conforms to `Sendable`)
- Static: `agentName` ("Hermes")
- Dynamic: `status` (string), `toolName` (optional), `elapsedSeconds`, `startDate` (for native `Text(timerInterval:)` clock), `sessionType` (voice/chat/tool)

### Current Status

| Component | State | Detail |
|-----------|-------|--------|
| Widget Extension target | Wired | `HermesMobileWidgets` in project.yml, dependency in main app |
| `HermesActivityAttributes.swift` | Wired | ActivityAttributes + ContentState with Sendable, startDate for native timer |
| `HermesLiveActivity.swift` | Wired | Lock Screen + Dynamic Island layouts with `Text(timerInterval:)` live clock |
| `HermesWidgetBundle.swift` | Wired | Widget bundle entry point |
| `LiveActivityService.swift` | Wired | Manages lifecycle — start/update/end; no polling timer (native clock via startDate) |
| `TalkStore` | Wired | Starts on voice connect, updates on state change, ends on session close |
| `ChatStore` | Wired | Starts on tool call, ends on finish/fail/cancel/clear |
| Info.plist | Configured | `NSSupportsLiveActivities: true`, `NSSupportsLiveActivitiesFrequentUpdates: true` |
| Xcode Previews | Wired | `LiveActivityPreviews.swift` in main app target (Lock Screen + Dynamic Island mockups) |

### Next Steps
- [x] Add `Activity<HermesActivityAttributes>.request()` call in `TalkStore.startSession()`
- [x] Add `activity.update()` on voice state changes (thinking, speaking, tool call)
- [x] Add `activity.end()` in `TalkStore.endSession()`
- [x] Add `activity.update()` in `ChatStore` during streaming (tool activity labels)
- [x] Add cleanup on stream failure, cancellation, and conversation clear
- [x] Use `Text(timerInterval:)` for native live-ticking timer on Lock Screen
- [x] Embed widget extension in main app bundle (Copy Files → PlugIns in pbxproj)
- [ ] Test on physical device (Dynamic Island requires iPhone 14 Pro+)

### Use Case Ideas
- **Voice session indicator**: Lock Screen shows "Hermes is listening" with elapsed time — user knows the session is active without opening the app
- **Tool call progress**: "Hermes is reading config.yaml..." visible on Lock Screen while phone is locked
- **Future: Home Screen widgets**: Same Widget Extension target hosts static widgets showing health summary, last location, recent conversations
- **Future: CarPlay**: Widget architecture enables CarPlay voice assistant integration
- **Hermes Skill**: Agent could trigger Live Activities for long-running tasks — "I'll research that and update you" → Live Activity shows progress

---

## 3. Background Location (Always)

**What it does:** Continues receiving location updates when the app is in the background or suspended, enabling continuous spatial awareness.

### Current Status

| Component | State | Detail |
|-----------|-------|--------|
| `NSLocationAlwaysAndWhenInUseUsageDescription` | Configured | In project.yml |
| `UIBackgroundModes: location` | Configured | In project.yml |
| `CLBackgroundActivitySession` | Built | Already in `LiveLocationService.swift` |
| `requestBackgroundAuthorization()` | Built | Two-stage flow (When In Use → Always) |
| `CLBackgroundActivitySession` | Built | Created when `syncPreference == .backgroundAllowed && auth == .always` |
| Permissions UI | Wired | Settings exposes background sync toggle and can request upgraded access |
| Default sync preference | Foreground-only | `LocationSyncPreference` defaults to foreground; background requires explicit opt-in |

### Next Steps
- [x] Add settings UI toggle for "Background Location" that calls `updateLocationSyncPreference(.backgroundAllowed)` and `requestBackgroundLocationAccess()`
- [ ] Test background location on physical device (verify blue indicator bar)
- [ ] Verify location uploads continue when app is backgrounded
- [ ] Consider iOS 26's `CLBackgroundActivitySession` guidance for While In Use apps

### Use Case Ideas
- **Automatic context**: Hermes always knows where you are — "Am I near a grocery store?" works even after the app was backgrounded hours ago
- **Geofencing**: "Remind me when I get home" → region monitoring triggers notification
- **Travel detection**: Agent notices you arrived at a new city → offers local recommendations
- **Hermes Skill**: Location-aware skill that detects home/work/travel patterns and adjusts behavior ("You're at the office — here's your morning briefing")

---

## 4. Remote Notifications (Silent Push)

**What it does:** Allows the relay server to wake the iOS app in the background to refresh data, even when the app isn't running.

### Current Status

| Component | State | Detail |
|-----------|-------|--------|
| `UIBackgroundModes: remote-notification` | Configured | In project.yml |
| `registerForRemoteNotifications()` | Wired | Called in AppDelegate on launch |
| Device token storage | Wired | Stored in UserDefaults as `hermes.apns.deviceToken` |
| `didReceiveRemoteNotification` | Wired | Triggers `handleAppDidBecomeActive()` for data refresh |
| Token upload to relay | Wired | `POST /v1/push/register` called from AppDelegate and replayed after pairing/app launch |
| Relay endpoint | Wired | `POST /v1/push/register` stores token in SQLite, returns `registered: true` |
| APNs server-side sending | **NOT BUILT** | Relay stores tokens but cannot send push notifications yet |
| APNs certificate/key | **NOT CONFIGURED** | Need Apple Developer Portal → Keys → APNs |

### Next Steps
- [x] Send token to relay during/after pairing
- [ ] Generate APNs key in Apple Developer Portal
- [ ] Implement APNs client in relay (use `aioapns` or `httpx` with HTTP/2)
- [ ] Add connector RPC for "send proactive message" → relay sends silent push → app wakes → refreshes conversation
- [ ] Add visible push notifications for proactive Hermes messages

### Use Case Ideas
- **Proactive messaging**: Hermes finishes a long-running task → pushes result to your phone even if app is closed
- **Calendar reminders**: "Your meeting starts in 15 minutes" pushed from Hermes agent
- **Health alerts**: "You haven't moved in 3 hours" triggered by sensor analysis on the connector
- **Conversation continuity**: Start a task on desktop Hermes → get the result pushed to your phone
- **Hermes Skill**: Proactive notification skill that uses sensor data + calendar + weather to send contextual alerts

---

## 5. Background Audio

**What it does:** Keeps the audio session alive when the user switches to another app during a voice conversation with Hermes.

### Current Status

| Component | State | Detail |
|-----------|-------|--------|
| `UIBackgroundModes: audio` | Configured | In project.yml |
| WebRTC audio session | Wired | `.playAndRecord` category, `.default` mode, `forceSpeakerIfNeeded()` |
| Voice session continuity | Wired | App no longer kills session on background — WebRTC stays alive |
| Audio interruption handling | Wired | Reconfigures audio session on interruption end |
| Speaker re-assertion | Wired | `forceSpeakerIfNeeded()` after WebRTC connect + 500ms delay + route changes |
| Live Activity in background | Wired | Dynamic Island shows compact status while app is backgrounded |

### Next Steps
- [x] Remove session kill on app background (was in AppEntry.swift scenePhase handler)
- [x] Handle interruptions (phone call, Siri) gracefully
- [x] Fix speaker volume (forceSpeakerIfNeeded after WebRTC resets audio route)
- [ ] Test on physical device: start voice → switch app → verify audio continues
- [ ] Test: Dynamic Island shows compact view while backgrounded

### Use Case Ideas
- **Hands-free operation**: Start a Hermes voice conversation → switch to Maps for navigation → continue talking to Hermes
- **Multi-tasking**: Ask Hermes a question while reading an article in Safari
- **Hermes Skill**: Long-form voice sessions where the agent walks you through a complex task while you work in other apps

---

## 6. Speech Recognition

**What it does:** On-device audio transcription using Apple's Speech framework (SFSpeechRecognizer). Can supplement or replace OpenAI Realtime transcription for local voice commands.

### Current Status

| Component | State | Detail |
|-----------|-------|--------|
| `NSSpeechRecognitionUsageDescription` | Configured | In project.yml |
| `LiveSpeechService.swift` | Built | SFSpeechRecognizer wrapper with on-device recognition support |
| On-device recognition | Built | Uses `supportsOnDeviceRecognition` when available |
| Permission request | Built | `SFSpeechRecognizer.requestAuthorization()` in service |
| Chat composer mic button | Wired | Dictation button in ChatInputBar with live transcript |
| Audio session | Built | Configured with `.allowBluetoothHFP` (non-deprecated) |

### Next Steps
- [x] Create `LiveSpeechService.swift` wrapping `SFSpeechRecognizer`
- [x] Implement on-device real-time transcription from audio buffer
- [x] Add mic button to chat input bar for dictation
- [ ] Add `.speechRecognition` to `PermissionType` enum
- [ ] Integrate as fallback when OpenAI Realtime is unavailable
- [ ] Consider using for local "wake word" detection without a full Realtime session

### Use Case Ideas
- **Offline voice commands**: "Hey Hermes, set a timer" works without internet via on-device recognition
- **Wake word**: Local speech recognition listens for "Hey Hermes" to start a full voice session
- **Privacy-first transcription**: Users who don't want audio sent to OpenAI can use on-device only
- **Hermes Skill**: Local command skill that handles simple requests (timers, reminders, quick queries) without touching the cloud

---

## 7. HealthKit (11 Metrics)

**What it does:** Reads comprehensive health and fitness data from the user's Apple Watch and iPhone sensors.

### Current Status

| Component | State | Detail |
|-----------|-------|--------|
| HealthKit entitlements | Configured | `healthkit`, `healthkit.access`, `healthkit.background-delivery` |
| `LiveHealthService` | Wired | 11 metrics with background delivery |
| Sensor pipeline | Wired | Health samples flow through relay → connector → SQLite |
| MCP tools | Wired | `get_health_summary`, `get_health_metric`, `get_health_metrics_list` |
| Voice context | Wired | Freshness summary in voice system prompt |
| Daily aggregates | Wired | `health_daily` table with correct rollup semantics |
| Sleep analysis | Wired | Attributed to wake-up day, overnight-aware |

**Active metrics:** steps, active_calories, distance_walking, heart_rate, resting_heart_rate, blood_oxygen, respiratory_rate, body_mass, workout_minutes, stand_hours, sleep_duration

### Next Steps
- [ ] Add more metrics: HRV, VO2 max, walking speed, environmental audio exposure
- [ ] Add workout session tracking (HKWorkoutType)
- [ ] Consider iOS 26 Medications API when available

### Use Case Ideas
- **Wellness dashboard**: "How's my health this week?" → agent queries daily aggregates, generates trend analysis
- **Correlations**: "Do I sleep better on days I exercise?" → agent runs SQL query across health_daily
- **Hermes Skill**: Health insight skill that proactively analyzes trends and sends weekly summaries

---

## Agent Integration: The iOS Context Skill

All these capabilities feed into a single vision: **Hermes should always know what you're doing, where you are, and how you're doing** — so it can be proactive, context-aware, and genuinely helpful.

### How It Flows

```
iPhone Sensors → iOS App → Relay WebSocket → Connector → SQLite
                                                          ↓
                                              MCP Tools ← Hermes Agent
                                                          ↓
                                              Voice Context → Realtime API
```

### Proposed Hermes Skill: `ios-context-awareness`

A Hermes skill that:
1. Checks `get_user_location`, `get_user_activity`, `get_health_summary` on each conversation
2. Adapts response style based on context:
   - Walking → brief voice-friendly responses
   - Driving → audio only, no tool calls that require reading
   - Stationary at home → detailed, can include code/links
   - Late night + sleep metrics low → "You should rest"
3. Enables proactive messaging triggers:
   - `user_activity` changed from `stationary` to `walking` for 30+ minutes → send encouragement
   - `steps` hit 10,000 → congratulations notification
   - Location changed to a new city → offer local info
4. Surfaces relevant data without being asked:
   - Morning conversation → "You slept 7.2 hours, walked 3,400 steps yesterday"
   - Health metric anomaly → "Your resting heart rate has been elevated for 3 days"

This skill would be installed in `~/.hermes/skills/ios-context-awareness/` and loaded when the iOS app is the active session source.

---

## Configuration Reference

### Info.plist Keys (all in project.yml)

| Key | Purpose |
|-----|---------|
| `NSLocationWhenInUseUsageDescription` | Location (foreground) |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | Location (background) |
| `NSMotionUsageDescription` | CoreMotion activity detection |
| `NSHealthShareUsageDescription` | HealthKit read |
| `NSHealthUpdateUsageDescription` | HealthKit write (system requirement) |
| `NSCameraUsageDescription` | Camera for voice mode + attachments |
| `NSMicrophoneUsageDescription` | Microphone for voice mode |
| `NSPhotoLibraryUsageDescription` | Photo library for attachments |
| `NSSpeechRecognitionUsageDescription` | On-device speech recognition |
| `NSSupportsLiveActivities` | ActivityKit Live Activities |
| `NSSupportsLiveActivitiesFrequentUpdates` | Push-based Live Activity updates |

### Background Modes

| Mode | Purpose |
|------|---------|
| `processing` | Background task scheduler (health delivery, data sync) |
| `location` | Background location updates |
| `remote-notification` | Silent push to wake app |
| `audio` | Voice session survives app switch |

### Entitlements

| Key | Value |
|-----|-------|
| `com.apple.developer.healthkit` | `true` |
| `com.apple.developer.healthkit.access` | `[]` |
| `com.apple.developer.healthkit.background-delivery` | `true` |
