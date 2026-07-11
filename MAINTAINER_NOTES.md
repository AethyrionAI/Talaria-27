# Talaria — Maintainer Notes

This file is for maintainers who want a short internal snapshot of the current implementation. It is **not** the recommended onboarding guide for public users.

Start here instead:

- [README.md](README.md)
- [connector/README.md](connector/README.md)
- [relay/README.md](relay/README.md)
- [CLEAN_CHAT_PATH.md](CLEAN_CHAT_PATH.md)

## Current architecture

Two independent paths (see README for the full diagram):

```text
Chat:     iOS App ──HTTP/SSE (Bearer)──▶ Hermes Sessions API :8642
Sensors:  iOS App ──HTTP──▶ Relay :8000 ──WebSocket──▶ Connector ──▶ hermes_mobile MCP tools
```

Chat does **not** pass through the relay. The relay/connector path exists only for sensor ingestion and the voice WebRTC bootstrap. The old `iOS → Relay → Connector → Agent` chat topology is legacy and no longer applies.

## Current focus

- self-hosted-first setup
- public-safe defaults
- native iPhone UX for chat, voice, widgets, and sensor-aware context

## What is broadly working

- streaming chat and attachment delivery
- voice mode with Realtime bootstrap and Hermes delegation (currently wedged by an iOS 27 beta seed audio-capture regression — OS-level, not app-level)
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

- connector suite: passing
- relay suite: passing
- iOS build: passing
- targeted iOS tests: useful, but simulator launch flakes still happen intermittently
- Swift Testing (`@Test`) suites report separately from XCTest — a `-only-testing` run can show "Executed 0 tests" in the XCTest summary while the real result is the `✔ "Test run with N tests passed"` lines

Treat this file as a maintainer note, not product documentation.
