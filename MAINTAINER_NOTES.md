# Talaria — Maintainer Notes

This file is for maintainers who want a short internal snapshot of the current implementation. It is **not** the recommended onboarding guide for public users.

Start here instead:

- [README.md](README.md)
- [connector/README.md](connector/README.md)
- [relay/README.md](relay/README.md)
- [CLEAN_CHAT_PATH.md](CLEAN_CHAT_PATH.md)

## Current architecture

Three independent paths (see README for the full diagram):

```text
Chat:     iOS App ──HTTP/SSE (Bearer)──▶ Hermes Sessions API :8642
Sensors:  iOS App ──HTTP──▶ Relay :8000 ──WebSocket──▶ Connector ──▶ hermes_mobile MCP tools
Models:   iOS App ──HTTP──▶ Models Shim :8765 (optional; list + persistent default)
```

Chat does **not** pass through the relay. The relay carries everything else phone-facing: pairing and auth, sensor ingestion, APNs push, the inbox/directives channel, scheduled runs, agent-file downloads, and the voice WebRTC bootstrap. The old `iOS → Relay → Connector → Agent` chat topology is legacy and no longer applies.

## Current focus

- self-hosted-first setup
- public-safe defaults
- native iPhone UX for chat, voice, widgets, and sensor-aware context

## What is broadly working

- streaming chat and attachment delivery
- voice mode with Realtime bootstrap and Hermes delegation, plus an on-device fallback engine
- dynamic slash-command catalog from Hermes surfaces
- sensor pipeline (location, health, motion) through connector SQLite + MCP tools
- widgets, Live Activities, inline image rendering, and model/context UI
- APNs registration and relay-side delivery when configured

## What still requires physical-device validation

- APNs end-to-end on real Apple credentials
- background location behavior
- CarPlay entitlement path
- background audio continuity under real interruptions

## Test posture

- iOS suite: 931 tests across 84 suites (Swift Testing) plus 8 XCUITests — green on the Xcode-beta4 SDK
- connector suite: passing
- relay suite: passing
- simulator launch flakes still happen intermittently on targeted runs
- Swift Testing (`@Test`) suites report separately from XCTest — a `-only-testing` run can show "Executed 0 tests" in the XCTest summary while the real result is the `✔ "Test run with N tests passed"` lines. Reading only the XCTest line undercounts the full suite to 8.

## Historical corrections worth not re-learning

- **Voice capture was never an OS-level beta wedge.** This file previously asserted an iOS 27 beta seed audio-capture regression, "OS-level, not app-level". That was wrong. Root cause was app-side: `SpeechOutputService.releaseAudioSessionIfIdle` deactivated the shared `AVAudioSession` dozens of times per minute during voice sessions, killing the live mic. Fixed in #106 (`didActivateAudioSession` gate + edge-triggered callback). Do not reach for "it's the beta OS" as an explanation for audio behaviour.
- **The relay is not sensors-only.** See the architecture section above; this understatement recurred across README, SECURITY.md and this file.

Treat this file as a maintainer note, not product documentation.
