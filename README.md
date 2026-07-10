# Talaria

> [!NOTE]
> Talaria is an independent community project. It is not affiliated with, endorsed by, or part of [Nous Research](https://nousresearch.com/) or the official [Hermes Agent](https://github.com/NousResearch/hermes-agent) project.

Talaria is a native SwiftUI iPhone client for a self-hosted [Hermes AI agent](https://github.com/NousResearch/hermes-agent). It adds a native iOS app, a lightweight relay sidecar, and a models shim so Hermes can move between chat, phone, sensors, and voice — without turning your runtime into a hosted service.

This repository (**Talaria-27**) is the active development line, targeting **iOS 27** and built with Swift 6.2 / strict concurrency. The original iOS 26 line lives at [ChronoRixun/Talaria](https://github.com/ChronoRixun/Talaria) and is stable but frozen.

**→ [Documentation and screenshots](https://aethyrionai.github.io/Talaria-27)**

---

## Status

Talaria is a working alpha, developed and used daily on real hardware. Honestly, per subsystem:

| Area | State |
|------|-------|
| Streaming chat (SSE) | Working — reasoning and answer channels separated, background continuation, reconciliation |
| Tool calls & agent files | Working |
| Sensor pipeline (location / HealthKit / motion) | Working — resume-from-background can occasionally be flaky |
| Model switching (shim) | Working |
| Local notifications | Working |
| Remote push (APNs) | Client side complete; delivery pending server-side key configuration |
| Voice mode | Code-complete, but **currently wedged by an iOS 27 beta seed regression** that breaks third-party audio capture system-wide (not Talaria-specific); revisit on the next seed |

Expect rough edges. There is no TestFlight or App Store distribution — you build and sign it yourself.

---

## What it does

- **Streaming chat** via the Hermes Sessions API (SSE), with markdown, code blocks, inline images, and agent file downloads
- **Voice mode** — real-time WebRTC speech-to-speech, server-side voice, continuous mic, mute/barge-in, multimodal image support
- **Sensor pipeline** — location, 11 HealthKit metrics, and CoreMotion activity delivered to Hermes in the background; your agent gets live context about you and you own all the data
- **Live model switching** — pick from your full provider roster mid-session via the models shim
- **Agent files** — files your agent generates surface as tappable share bubbles in chat
- **Full settings suite** — System, Uplink, Models, Voice, Appearance, Sessions, Diagnostics — everything configurable in-app

---

## Architecture

Three independent paths, each talking to a dedicated service on your host:

```
iPhone (Talaria)
  │
  ├─ Chat & sessions  ──────→  Hermes Sessions API  :8642
  │    SSE streaming, sync         hermes gateway run
  │    Bearer auth (API_SERVER_KEY)
  │
  ├─ Sensor data  ──────────→  HermesMobile Relay   :8000
  │    Location, HealthKit,        sidecar (Python/uvicorn)
  │    CoreMotion, background      → connector → hermes_mobile MCP tools
  │
  └─ Model switching  ──────→  Models Shim          :8765
       Live model list + swap      tools/models-shim/shim.py
       Per-session, no restart     (optional)
```

Chat connects **directly** to the Sessions API — it does not go through the relay. The relay exists solely for sensor ingestion and the voice WebRTC bootstrap. All three services are independently restartable. The verified SSE event taxonomy and API contract live in [CLEAN_CHAT_PATH.md](CLEAN_CHAT_PATH.md).

---

## Requirements

| Component | Requirement |
|-----------|-------------|
| iOS app | iOS 27 (beta), Xcode 27 beta (iOS 27 SDK), Apple Developer account |
| Host OS | macOS or Windows (Linux untested) |
| Hermes | [hermes-agent](https://github.com/NousResearch/hermes-agent) installed and configured |
| Network | Tailscale (recommended) or other private network access |
| Relay | Python 3.11+, uvicorn |

> Building from the command line with multiple Xcode versions installed? Point at the beta toolchain first: `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`. "Cannot find in scope" errors on iOS 27 APIs almost always mean the stable SDK is being used by mistake.

---

## Setup

### 1 — Install Hermes Agent

Follow the [Hermes Agent](https://github.com/NousResearch/hermes-agent) install instructions for your host OS. Confirm `hermes` is in your PATH and a profile is configured.

### 2 — Start the Hermes gateway (Sessions API)

```bash
hermes gateway run
```

This starts the Sessions API on `:8642`. Use NSSM (Windows) or a launchd agent (macOS) for persistence across reboots. Bind to `0.0.0.0` and ensure your Tailscale IP can reach `:8642`.

> ⚠️ Do not run `hermes gateway install` on Windows — it creates a conflicting scheduled task that fights the manual service for port 8642.

### 3 — Deploy the relay sidecar

```bash
cd relay
pip install -e .
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Set `AGENT_FILES_DIR` in your `.env` if you want agent-generated files downloadable from the phone. Bind to `0.0.0.0` for Tailscale reachability. Change `INTERNAL_API_KEY` from its default — the relay logs a security warning if you don't.

### 4 — (Optional) Run the models shim

```bash
cd tools/models-shim
python shim.py
```

Required only if you want live model switching in the app. Listens on `:8765`.

### 5 — Generate and build the Xcode project

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
xcodegen generate
open Talaria.xcodeproj
```

Regenerate whenever Swift files are added or removed — sources are listed explicitly in the project. Set your own signing team and bundle identifier locally. Build to your iPhone with Xcode 27 beta.

### 6 — Pair on first launch

Enter your host's Tailscale IP or hostname, the gateway port (`8642`), and your `API_SERVER_KEY` on the onboarding screen. The app connects directly — no account, no cloud login required.

> ⚠️ **iCloud Private Relay** intercepts HTTP to Tailscale IPs. Disable it on your iPhone for Tailscale addresses, or the app will not reach your services.

---

## Security

See [SECURITY.md](SECURITY.md) for the security architecture, reporting process, and known limitations.

One default worth knowing about up front: the app currently ships with a global App Transport Security exception (`NSAllowsArbitraryLoads`) because the expected deployment is plain HTTP to Tailscale IPs on a private tailnet. If you front your services with `tailscale serve` (HTTPS + MagicDNS), you can and should remove this exception locally.

---

## Repository layout

```
Talaria/              iOS app (SwiftUI, Swift 6.2)
TalariaWidgets/       Home screen widgets + Live Activities
TalariaTests/         Unit tests (XCTest + Swift Testing)
Shared/               Code shared between app and widget targets
relay/                HermesMobile relay sidecar (Python)
connector/            Hermes connector for sensor MCP tools
tools/models-shim/    Model-switching shim (Python)
project.yml           XcodeGen project definition (source of truth)
design/               UI design reference files
docs/                 Landing page + screenshots
CLEAN_CHAT_PATH.md    Verified SSE event taxonomy and API contract
OPEN_ITEMS.md         Active work items and decisions log
dispatch/             In-flight agent task specs (temporary)
```

---

## Network notes

- All three services (`8642`, `8000`, `8765`) should be reachable from your phone's Tailscale IP
- Bind each service to `0.0.0.0`, not `127.0.0.1`
- Add Windows Firewall inbound rules for each port if on Windows (a Tailscale process-level allow rule also covers this)
- iCloud Private Relay must be disabled (or Tailscale IPs excluded) for HTTP to Tailscale addresses

---

## License

MIT — see [LICENSE](LICENSE).
