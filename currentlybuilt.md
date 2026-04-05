# HermesMobile — Current Build Status

**Last updated:** April 5, 2026

## Architecture

```
iOS App ──HTTP/SSE──▶ Relay (Fly.io) ◀──WebSocket──▶ Connector (Mac mini) ──▶ Hermes Agent
                                      ◀──────────────▶ OpenAI Realtime API (voice, via iOS WebRTC)
```

- **iOS App**: SwiftUI, iOS 26, Swift 6.2 strict concurrency
- **Relay**: FastAPI on Fly.io, SQLite, WebSocket + SSE
- **Connector**: Python service on Mac mini, bridges relay to Hermes CLI/API
- **Hermes Agent**: Local agent with tools, memory, MCP, model gpt-5.4-mini via openai-codex

---

## What Works

### Chat
- Single-surface chat with the Hermes agent
- Image attachments (768px/350KB, staged to disk, agent uses vision_analyze)
- SSE streaming with event buffering and polling fallback
- Tool activity rail, inline git diffs, markdown rendering
- Message retry, conversation persistence
- Voice transcript injection after voice session ends
- Voice context shared with Hermes agent via [Recent voice conversation] block

### Voice Mode
- WebRTC via OpenAI Realtime API (gpt-realtime-1.5)
- SOUL.md personality in voice system prompt
- MCP tool delegation (hermes_delegate) with voice follow-up
- Semantic VAD, barge-in, input transcription
- Live camera (1.5s frame capture, video-only AVCaptureSession)
- Live transcript, session teardown on dismiss
- Handles both beta and GA Realtime API events (ready for May 7, 2026 deprecation)

### Sensor Pipeline (11 metrics)
- SQLite at ~/.hermes-mobile/state/sensors.db
- Location with reverse geocoding
- Health: steps, active_calories, distance_walking, heart_rate, resting_heart_rate, blood_oxygen, respiratory_rate, body_mass, workout_minutes, stand_hours, sleep_duration
- Sleep attributed to wake-up day, overnight-aware
- Daily aggregates with correct rollup semantics
- 90-day retention, 7 MCP tools including raw SQL query
- Schema documented in connector/SENSOR_SCHEMA.md

### Permissions
- Real LiveMediaService for camera/photos
- Onboarding + settings with "Open Settings" for denied state
- HealthKit background delivery
- Foreground refresh on app return

---

## Known Issues (from code review)

| Severity | Issue |
|----------|-------|
| **Critical** | Voice session `performAuthorizedRequest` discards refreshed token on retry |
| **High** | Force-unwraps on optional conversation in ChatStore streaming loop |
| **High** | WebRTC properties (`nonisolated(unsafe)`) accessed cross-thread without sync |
| **High** | `query_sensor_data` SQL injection — safety checks bypassable |
| **High** | SensorStore SQLite shared across threads without locking |
| Medium | CIContext per-frame, UIGraphicsImageRenderer on background queue |
| Medium | Synchronous file I/O in MessageBubble attachment cell |
| Medium | Unbounded event buffer in relay, attachment staging never cleaned |
| Low | Static streaming dots, placeholder ToS/Privacy buttons |

---

## Test Coverage

| Suite | Tests | Status |
|-------|-------|--------|
| Connector | 76 | All passing |
| Relay | 44 | All passing |
| iOS AppStoresTests | ~15 | Passing (streaming, attachments, sleep) |
| iOS UI Tests | Stale | Not maintained |

---

## Services: Live vs Mock

| Service | Production | Test |
|---------|-----------|------|
| Location | LiveLocationService | MockLocationService |
| Health | LiveHealthService | MockHealthService |
| Notifications | LiveNotificationService | MockNotificationService |
| Media | **LiveMediaService** | MockMediaService |
| Voice | LiveVoiceSessionService | MockVoiceSessionService |
| Hermes Client | LiveHermesClient | MockHermesClient |
| Sync Coordinator | MockSyncCoordinator | MockSyncCoordinator |
