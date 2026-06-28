# Talaria

> [!NOTE]
> Talaria is an independent community project. It is not affiliated with, endorsed by, or part of [Nous Research](https://nousresearch.com/) or the official [Hermes Agent](https://github.com/NousResearch/hermes-agent) project.

Talaria is a native SwiftUI iPhone client for a self-hosted [Hermes AI agent](https://github.com/NousResearch/hermes-agent). It adds a native iOS app, a lightweight relay sidecar, and a models shim so Hermes can move between chat, phone, sensors, and voice — without turning your runtime into a hosted service.

**→ [Full documentation and screenshots at ChronoRixun.github.io/Talaria](https://ChronoRixun.github.io/Talaria)**

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
  ├─ Chat & sessions  ──────→  Hermes Gateway      :8642
  │    SSE streaming, sync         hermes gateway run
  │    Bearer auth
  │
  ├─ Sensor data  ──────────→  HermesMobile Relay  :8000
  │    Location, HealthKit,        sidecar (Python/uvicorn)
  │    CoreMotion, background      → hermes_mobile MCP tools
  │
  └─ Model switching  ──────→  Models Shim         :8765
       Live model list + swap      tools/models-shim/shim.py
       Per-session, no restart     (optional)
```

Chat connects **directly** to the Hermes Gateway — it does not go through the relay. The relay exists solely for sensor ingestion and the voice WebRTC bootstrap. All three services are independently restartable.

---

## Requirements

| Component | Requirement |
|-----------|-------------|
| iOS app | iOS 26+, Xcode (iOS 26 SDK), Apple Developer account |
| Host OS | macOS or Windows (Linux untested) |
| Hermes | [hermes-agent](https://github.com/NousResearch/hermes-agent) installed and configured |
| Network | Tailscale (recommended) or other private network access |
| Relay | Python 3.11+, uvicorn |

> **No TestFlight or App Store distribution.** You build and sign the app yourself in Xcode.

---

## Setup

### 1 — Install Hermes Agent

Follow the [Hermes Agent](https://github.com/NousResearch/hermes-agent) install instructions for your host OS. Confirm `hermes` is in your PATH and a profile is configured.

### 2 — Start the Hermes Gateway

```bash
hermes gateway run
```

This starts the Sessions API on `:8642`. Use NSSM or a Scheduled Task (Windows) or a launchd agent (macOS) for persistence across reboots. Bind to `0.0.0.0` and ensure your Tailscale IP can reach `:8642`.

> ⚠️ Do not run `hermes gateway install` on Windows — it creates a conflicting scheduled task that fights the manual service for port 8642.

### 3 — Deploy the relay sidecar

```bash
cd relay
pip install -e .
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Set `AGENT_FILES_DIR` in your `.env` if you want agent-generated files downloadable from the phone. Bind to `0.0.0.0` for Tailscale reachability.

### 4 — (Optional) Run the models shim

```bash
cd tools/models-shim
python shim.py
```

Required only if you want live model switching in the app. Listens on `:8765`.

### 5 — Build Talaria in Xcode

Open the Xcode project (requires the iOS 26 SDK). Select your iPhone as the run destination and build. Sign with your Apple Developer account.

### 6 — Pair on first launch

Enter your host's Tailscale IP or hostname, the gateway port (`8642`), and your `API_SERVER_KEY` on the onboarding screen. The app connects directly — no account, no cloud login required.

> ⚠️ **iCloud Private Relay** intercepts HTTP to Tailscale IPs. Disable it on your iPhone for Tailscale addresses, or the app will not reach your services.

---

## Repository layout

```
Talaria/              iOS app (SwiftUI, Swift 6)
relay/                HermesMobile relay sidecar (Python)
connector/            Hermes connector for sensor MCP tools
tools/
  models-shim/        Model-switching shim (Python)
design/               Claude Design source files for UI reference
docs/                 GitHub Pages (landing page + screenshots)
CLEAN_CHAT_PATH.md    Verified SSE event taxonomy and API contract
OPEN_ITEMS.md         Active work items and decisions log
```

---

## Network notes

- All three services (`8642`, `8000`, `8765`) should be reachable from your phone's Tailscale IP
- Bind each service to `0.0.0.0`, not `127.0.0.1`
- Add Windows Firewall inbound rules for each port if on Windows
- iCloud Private Relay must be disabled (or Tailscale IPs excluded) for HTTP to Tailscale addresses

---

## License

MIT — see [LICENSE](LICENSE).

