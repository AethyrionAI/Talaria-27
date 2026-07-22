# Talaria

> [!NOTE]
> Talaria is an independent community project. It is not affiliated with, endorsed by, or part of [Nous Research](https://nousresearch.com/) or the official [Hermes Agent](https://github.com/NousResearch/hermes-agent) project.

Talaria is a native SwiftUI iPhone client for a self-hosted [Hermes AI agent](https://github.com/NousResearch/hermes-agent). It adds a native iOS app, a lightweight relay sidecar, and a models shim so Hermes can move between chat, phone, sensors, and voice — without turning your runtime into a hosted service.

It also works **standalone**: an on-device chat brain (Apple's FoundationModels framework) runs with zero host setup, and pairing your Hermes machine upgrades the app with your full agent, your models, and the sensor pipeline.

This repository (**Talaria-27**) is the active development line, targeting **iOS 27** and built with Swift 6.2 / strict concurrency. The original iOS 26 line lives at [ChronoRixun/Talaria](https://github.com/ChronoRixun/Talaria) and is stable but frozen.

**→ [Documentation and screenshots](https://aethyrionai.github.io/Talaria-27)**

---

## Status

Talaria is a working alpha, developed and used daily on real hardware. Honestly, per subsystem:

| Area | State |
|------|-------|
| Streaming chat (SSE) | Working — reasoning and answer channels separated, background continuation, reconciliation |
| On-device chat | Working — Apple FoundationModels, no host required; a Private Cloud Compute tier shows only when the entitlement and availability check actually pass (beta) |
| Tool calls & agent files | Working |
| Inbox / Directives & daily briefing | Working — agent pushes actionable items (approvals, reminders, briefings) to the phone |
| Sensor pipeline (location / HealthKit / motion) | Working — deliberate opt-in (off by default) with per-sensor grants; resume-from-background can occasionally be flaky |
| Model switching (shim) | Working — the shim sets the persistent default, the gateway pins the live session |
| Widgets & Live Activities | Working — status, health, and briefing widgets; alarm Live Activity; lock-screen controls |
| Share extension | Working — share URLs, images, files, and text into Hermes from any app |
| Local notifications | Working |
| Remote push (APNs) | Working — bring your own APNs key (.p8), configured on the relay |
| Voice mode | Working — realtime speech-to-speech plus an on-device fallback engine; echo/self-interruption tuning and connect hardening actively in progress |
| CarPlay | Parked — scene and voice manager are built but disabled pending Apple's discretionary capability grant |

Expect rough edges. There is no TestFlight or App Store distribution — you build and sign it yourself.

Two things worth knowing up front:

- **Pairing is optional.** On-device chat works out of the box. Pairing a host adds server sessions, sensor analytics, and your desktop model roster.
- **The repo contains a dormant monetization scaffold** for a possible future "Connected" supporter tier. It ships inert (`MonetizationConfiguration.isEnabled = false`), there is no App Store product, and the gate rules are pinned so existing pairings always pass — self-hosting your own server is never paywalled.

---

## What it does

- **On-device chat** — a full local backend on Apple's FoundationModels framework, behind the same client seam as the hosted path: streaming, sessions drawer, persistence, read-aloud. Context-window-aware condensation instead of errors; no data leaves the device
- **Streaming chat** via the Hermes Sessions API (SSE), with markdown, code blocks, inline images, and agent file downloads
- **Voice mode** — real-time WebRTC speech-to-speech, server-side voice, continuous mic, mute/barge-in, multimodal image support; falls back to an on-device engine when the relay is unpaired or unreachable
- **Inbox / Directives** — your agent pushes to-dos, approvals, reminders, and a daily briefing to the phone; approve or dismiss in place, and the verdict lands back on the host
- **Sensor pipeline** — location, 11 HealthKit metrics, and CoreMotion activity delivered to Hermes in the background; your agent gets live context about you and you own all the data
- **Live model switching** — pick from your full provider roster mid-session; the models shim sets the persistent default and the gateway pins the running session (no restart)
- **Agent files** — files your agent generates surface as tappable share bubbles in chat
- **Widgets & Live Activities** — agent status, health tiles, and briefing widgets; alarm Live Activities; lock-screen toggle controls
- **Share extension** — send a web URL, up to four images, a file, or plain text straight into Hermes from the iOS share sheet
- **Siri & App Intents** — ask Hermes or start a voice session hands-free; conversations index into Spotlight
- **Device tool belt** — the agent can read your calendar, reminders, contacts, weather (WeatherKit), health, and media, and set real alarms/timers (AlarmKit) — every action confirmed in-app before it fires
- **Multi-host profiles** — pair more than one Hermes machine (e.g. a desktop and a dev box); each profile keeps its own API key in the Keychain
- **Full settings suite** — System, Uplink, Server, Models, Voice, Appearance, Sessions, Notifications, Privacy, Diagnostics, Developer — everything configurable in-app, including a theme system, 30+ alternate app icons, and an optional Face ID app lock

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
  ├─ Sensors, push, inbox, ──→  HermesMobile Relay   :8000
  │    files, voice bootstrap      sidecar (Python/uvicorn)
  │                                → connector → hermes_mobile MCP tools
  │
  └─ Model switching  ──────→  Models Shim          :8765
       Live model list + swap      tools/models-shim/shim.py
       Per-session, no restart     (optional)
```

Chat connects **directly** to the Sessions API — it never transits the relay. The relay carries everything else phone-facing: pairing and auth, sensor ingestion, APNs push, the inbox/directives channel, scheduled runs (e.g. the daily briefing), agent-file downloads, and the voice WebRTC bootstrap. All three services are independently restartable. The verified SSE event taxonomy and API contract live in [CLEAN_CHAT_PATH.md](CLEAN_CHAT_PATH.md).

---

## Requirements

| Component | Requirement |
|-----------|-------------|
| iOS app | iOS 27 (beta), Xcode 27 beta (iOS 27 SDK), Apple Developer account |
| Host OS | macOS or Windows (Linux untested) |
| Hermes | [hermes-agent](https://github.com/NousResearch/hermes-agent) installed and configured |
| Network | Tailscale (recommended) or other private network access |
| Relay & connector | Python 3.11+, uvicorn |

> Building from the command line with multiple Xcode versions installed? Point at the beta toolchain first, e.g. `export DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer` (adjust for your install name). "Cannot find in scope" errors on iOS 27 APIs almost always mean the stable SDK is being used by mistake.

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

Key environment variables (`.env` in the relay directory):

| Variable | Why |
|----------|-----|
| `INTERNAL_API_KEY` | Change it from the default — the relay logs a security warning at startup if you don't |
| `PUBLIC_BASE_URL` | The URL the phone uses to reach the relay (e.g. `http://your-tailscale-ip:8000/v1`) |
| `AGENT_FILES_DIR` | Directory the relay is allowed to serve agent-generated files from (enables in-chat downloads) |
| `GATEWAY_API_KEY` | Your `API_SERVER_KEY` — lets the relay watch run completion for push notifications |
| `APNS_KEY_PATH` / `APNS_KEY_ID` / `APNS_TEAM_ID` | Remote push (optional; bring your own .p8) |

Bind to `0.0.0.0` for Tailscale reachability. A `Dockerfile`, `docker-compose.yml`, and `fly.toml` are included if you'd rather run the relay containerized or hosted.

### 4 — Install and run the connector

The connector is the host-side bridge that owns the durable relay connection, registers the `hermes_mobile` MCP server (the sensor tools your agent calls), and prints phone-pairing codes. **Without it, the sensor pipeline and inbox go nowhere.**

```bash
cd connector
python -m venv .venv && source .venv/bin/activate
pip install -e .
hermes-mobile setup        # validates Hermes, pairs against your relay, registers the MCP server
```

See [connector/README.md](connector/README.md) for the full wizard options (including `--skip-mcp` and background-service install).

### 5 — (Optional) Run the models shim

```bash
cd tools/models-shim
python shim.py
```

Required only if you want live model switching in the app. Listens on `:8765`. Two gotchas:

- It imports Hermes internals (`hermes_cli.*`), so run it from a Python environment where Hermes is installed.
- `TALARIA_SHIM_HOST` defaults to the author's own Tailscale IP — set it explicitly (e.g. `0.0.0.0` or your host's tailnet IP) before first run.

Auth is a Bearer token at `~/.hermes/talaria_shim_token` (auto-created on first run); the shim also accepts your `API_SERVER_KEY`. See [tools/models-shim/README.md](tools/models-shim/README.md).

### 6 — Generate and build the Xcode project

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
xcodegen generate
open Talaria.xcodeproj
```

Regenerate whenever Swift files are added or removed — sources are listed explicitly in the project. Set your own signing team and bundle identifier locally. Build to your iPhone with Xcode 27 beta.

### 7 — Launch, then pair (optional)

On first launch the app works immediately in on-device mode — no account, no cloud login. To connect your Hermes machine:

1. On the host, run `hermes-mobile pair-phone`. It prints a QR code and a short-lived 8-character code.
2. In the app, scan the QR code or tap **Enter Code Manually**, paste your relay URL, and enter the code.
3. For hosted chat, go to **Settings → Uplink** and enter your gateway URL (`http://your-host:8642`) and that host's `API_SERVER_KEY` (from `~/.hermes/.env`). Each paired profile keeps its own key.

> ⚠️ **iCloud Private Relay** intercepts HTTP to Tailscale IPs. Disable it on your iPhone for Tailscale addresses, or the app will not reach your services.

---

## Security

See [SECURITY.md](SECURITY.md) for the security architecture, reporting process, and known limitations.

One default worth knowing about up front: the app currently ships with a global App Transport Security exception (`NSAllowsArbitraryLoads`) because the expected deployment is plain HTTP to Tailscale IPs on a private tailnet. If you front your services with `tailscale serve` (HTTPS + MagicDNS), you can and should remove this exception locally.

---

## Repository layout

```
Talaria/              iOS app (SwiftUI, Swift 6.2)
TalariaWidgets/       Home screen widgets + Live Activities + lock-screen controls
TalariaShare/         Share extension (URLs, images, files, text → Hermes)
Shared/               Theme palette tables shared between app and widget targets
TalariaTests/         Unit tests (Swift Testing)
TalariaUITests/       UI tests (XCTest/XCUITest)
relay/                HermesMobile relay sidecar (Python/FastAPI)
connector/            Host-side bridge: relay connection, hermes_mobile MCP tools, pairing
tools/models-shim/    Model-switching shim (Python)
tools/appicons/       Alternate app icon gallery renderer
project.yml           XcodeGen project definition (source of truth)
design/               UI design reference files + theme galleries
docs/                 Landing page + screenshots
scripts/              Host ops scripts (service install, watchdog, updates)
skills/hermes-ios/    Agent skill for working in this repo
planning/             Eval notes and cross-machine handoffs
CLEAN_CHAT_PATH.md    Verified SSE event taxonomy and API contract
OPEN_ITEMS.md         Active work items and decisions log
BRANCHING.md          Branch/PR workflow conventions
CONTRIBUTING.md       Contribution guidelines
SECURITY.md           Security architecture and reporting
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

MIT — see [LICENSE](LICENSE). Contributions welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).
