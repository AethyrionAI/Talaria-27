# Talaria

> [!NOTE]
> Talaria is an independent community project. It is not affiliated with, endorsed by, or part of [Nous Research](https://nousresearch.com/) or the official [Hermes Agent](https://github.com/NousResearch/hermes-agent) project.

Talaria is a native SwiftUI iPhone app with a **fully on-device chat brain** (Apple's FoundationModels framework): streaming chat, a device tool belt (calendar, reminders, contacts, weather, health, alarms — every action confirmed in-app), sessions, themes, and voice, with zero host setup and no data leaving the phone.

Pairing a self-hosted [Hermes AI agent](https://github.com/NousResearch/hermes-agent) is the **upgrade tier**: it adds your full agent, your desktop model roster, server sessions, and phone-aware answers — your agent can ask this phone for location, health, motion, calendar, and weather **at query time** (the talaria plugin) — without turning your runtime into a hosted service.

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
| Inbox / Directives & daily briefing | Working — actionable items (approvals, reminders, briefings) land in the in-app inbox; approve or dismiss in place |
| Phone queries (location / HealthKit / motion / calendar / weather) | Working — your agent asks the phone at query time; deliberate opt-in (off by default) with per-sensor grants. The old always-on upload pipeline was retired 2026-08-16 (#352) — nothing streams, nothing queues |
| Model picking | Working — the full provider roster comes from the gateway's own API; a pick applies as a **per-turn model lock**, and takes effect immediately. The old models shim is retired — no third service |
| Widgets & Live Activities | Working — status, health, and briefing widgets; alarm Live Activity; lock-screen controls |
| Share extension | Working — share URLs, images, files, and text into Hermes from any app |
| Notifications (local + push) | Removed by design — the app posts no notifications and registers for no push; chat, the inbox, and Live Activities carry state in-app |
| Voice mode | Working — realtime speech-to-speech plus an on-device fallback engine; echo/self-interruption tuning and connect hardening actively in progress |
| CarPlay | Parked — scene and voice manager are built but disabled pending Apple's discretionary capability grant |

Expect rough edges. There is no TestFlight or App Store distribution — you build and sign it yourself.

One thing worth knowing up front: **pairing is optional.** On-device chat works out of the box. Pairing a host adds server sessions, phone-aware answers, and your desktop model roster.

---

## What it does

- **On-device chat** — a full local backend on Apple's FoundationModels framework, behind the same client seam as the hosted path: streaming, sessions drawer, persistence, read-aloud. Context-window-aware condensation instead of errors; no data leaves the device
- **Streaming chat** via the Hermes gateway (SSE), with markdown, code blocks, and inline images; agent-written text files surface in chat via the plugin's artifact mirror
- **Voice mode** — real-time WebRTC speech-to-speech, server-side voice, continuous mic, mute/barge-in, multimodal image support; bootstraps over the talaria plugin (#383) and falls back to an on-device engine when no voice host is reachable
- **Inbox / Directives** — your agent pushes to-dos, approvals, reminders, and a daily briefing to the phone; approve or dismiss in place, and the verdict lands back on the host
- **Phone-aware answers** — your agent asks the phone for location, HealthKit metrics, motion activity, calendar, and weather **at query time** over the talaria plugin; deliberate opt-in with per-sensor grants, and nothing streams in the background (the always-on upload pipeline was retired 2026-08-16, #352)
- **Model picking, gateway-native** — pick from your full provider roster in Settings → Models; the pick rides every turn as a model lock and pins the live session through the gateway itself (no shim, no restart)
- **Agent files** — files your agent generates surface as tappable share bubbles in chat
- **Widgets & Live Activities** — agent status, health tiles, and briefing widgets; alarm Live Activities; lock-screen toggle controls
- **Share extension** — send a web URL, up to four images, a file, or plain text straight into Hermes from the iOS share sheet
- **Siri & App Intents** — ask Hermes or start a voice session hands-free; conversations index into Spotlight
- **Device tool belt** — the agent can read your calendar, reminders, contacts, weather (WeatherKit), health, and media, and set real alarms/timers (AlarmKit) — every action confirmed in-app before it fires
- **Multi-host profiles** — pair more than one Hermes machine (e.g. a desktop and a dev box); each profile keeps its own API key in the Keychain
- **Full settings suite** — System, Uplink, Server, Models, Voice, Appearance, Sessions, Privacy, Diagnostics, Developer — everything configurable in-app, including a full-bleed theme channel browser (the live app is the preview), 30+ alternate app icons, and an optional Face ID app lock

---

## Architecture

On-device chat needs no host at all. Paired, the phone talks to your Hermes machine on two planes — plus a third, legacy one you only run if you still need it:

```
iPhone (Talaria)
  │
  ├─ Chat, sessions, models, runs ─→  Hermes Sessions API   :8642
  │    SSE streaming + mid-turn          hermes gateway run
  │    steering, model roster +
  │    per-turn lock, Bearer auth
  │    (API_SERVER_KEY)
  │
  ├─ Plugin link ──────────────────→  talaria plugin        :8642
  │    pairing · query-time phone        (same gateway process)
  │    asks · inbox / directives ·
  │    daily briefing
  │
  └─ LEGACY (optional): realtime- ─→  HermesMobile Relay    :8000
       voice WebRTC bootstrap            sidecar (Python/uvicorn)
                                         → connector → hermes_mobile MCP
```

Chat connects **directly** to the Sessions API — server sessions, model selection, and mid-turn steering all ride that one connection. The plugin link rides the same gateway (the `/api/platforms/talaria/events` channel): pairing, query-time phone asks (location, health, motion, calendar, weather — per-sensor opt-in), and the inbox/directives/briefing channel. The relay + connector tier is **legacy and no longer called by current builds at all** — realtime voice, its last surface, moved onto the talaria plugin on 2026-08-22 (#383); the tier remains in-tree only on its retirement path (#223). Agent-file downloads are handled by the plugin's artifact mirror; the relay's download path is superseded. Sensor ingestion is gone outright (2026-08-16, #352): phone data answers query-time asks; nothing streams, nothing queues. The verified SSE event taxonomy and API contract live in [CLEAN_CHAT_PATH.md](CLEAN_CHAT_PATH.md). (Earlier versions used a third service — a models shim on `:8765`; it is retired and current builds never call it.)

---

## Requirements

| Component | Requirement |
|-----------|-------------|
| iOS app | iOS 27 (beta), Xcode 27 beta (iOS 27 SDK), Apple Developer account — **this is the whole list for on-device mode** |
| Host OS (upgrade tier) | macOS or Windows (Linux untested) |
| Hermes (upgrade tier) | [hermes-agent](https://github.com/NousResearch/hermes-agent) installed and configured, with the talaria plugin for pairing and phone-aware answers |
| Network (upgrade tier) | Tailscale (recommended) or other private network access |
| Relay & connector (legacy tier — retired) | Python 3.11+, uvicorn; current builds never call it — realtime voice rides the talaria plugin (#383) |

> Building from the command line with multiple Xcode versions installed? Point at the beta toolchain first, e.g. `export DEVELOPER_DIR=/Applications/Xcode-beta6.app/Contents/Developer` (adjust for your install name). "Cannot find in scope" errors on iOS 27 APIs almost always mean the stable SDK is being used by mistake.

---

## Setup

### 1 — Generate and build the Xcode project (this is all on-device mode needs)

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
xcodegen generate
open Talaria.xcodeproj
```

Regenerate whenever Swift files are added or removed — sources are listed explicitly in the project. Set your own signing team and bundle identifier locally. Build to your iPhone with Xcode 27 beta.

On first launch the app works immediately in on-device mode — no account, no host, no cloud login. Everything below is the **upgrade tier**.

### 2 — Install Hermes Agent

Follow the [Hermes Agent](https://github.com/NousResearch/hermes-agent) install instructions for your host OS. Confirm `hermes` is in your PATH and a profile is configured.

### 3 — Start the Hermes gateway (Sessions API)

```bash
hermes gateway run
```

This starts the Sessions API on `:8642`. Use NSSM (Windows) or a launchd agent (macOS) for persistence across reboots. Bind to `0.0.0.0` and ensure your Tailscale IP can reach `:8642`.

> ⚠️ Do not run `hermes gateway install` on Windows — it creates a conflicting scheduled task that fights the manual service for port 8642.

### 4 — Pair the phone (talaria plugin)

Pairing is one command on the host — it requires the talaria plugin on your Hermes install (`hermes talaria status` to check):

```bash
hermes talaria pair
```

It prints a QR code and a one-time code. In the app: **Settings → Server → Pair New Device**, then scan the QR or enter the code. For hosted chat, also enter your gateway URL (`http://your-host:8642`) and that host's `API_SERVER_KEY` under **Settings → Uplink** (the key lives in the Hermes `.env` — `~/.hermes/.env` on macOS, `%LOCALAPPDATA%\hermes\.env` on Windows). Each paired profile keeps its own key in the Keychain, and you can pair more than one machine.

> ⚠️ **iCloud Private Relay** intercepts HTTP to Tailscale IPs. Disable it on your iPhone for Tailscale addresses, or the app will not reach your services.

---

### Legacy tier (optional): relay sidecar + connector

**Current builds never call the relay.** Realtime server voice — the last surface this tier carried — moved onto the talaria plugin on 2026-08-22 (#383); the tier stays on its retirement path (#223) and these instructions remain only for legacy installs. Sensor upload is gone app-side (#352), phone queries ride the talaria plugin, the inbox is served over the plugin channel, and agent-file downloads are handled by the plugin's artifact mirror — none of that needs the relay anymore.

<details>
<summary>Relay + connector install (legacy)</summary>

Deploy the relay sidecar:

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
| `AGENT_FILES_DIR` | Directory the relay is allowed to serve agent-generated files from (legacy — the app's in-chat download path was deleted 2026-08-19, #375; the plugin's artifact mirror replaced it) |
| `GATEWAY_API_KEY` | Your `API_SERVER_KEY` — lets the relay query the gateway on the phone's behalf |
| `APNS_KEY_PATH` / `APNS_KEY_ID` / `APNS_TEAM_ID` | Legacy remote push (current app builds don't register for push — safe to omit) |

Bind to `0.0.0.0` for Tailscale reachability. A `Dockerfile`, `docker-compose.yml`, and `fly.toml` are included if you'd rather run the relay containerized or hosted.

Then install and run the connector — the host-side bridge that owns the durable relay connection and registers the `hermes_mobile` MCP server:

```bash
cd connector
python -m venv .venv && source .venv/bin/activate
pip install -e .
hermes-mobile setup        # validates Hermes, pairs against your relay, registers the MCP server
```

Relay-tier phone pairing uses `hermes-mobile pair-phone` (QR + short-lived code; in the app, paste your relay URL with the code). See [connector/README.md](connector/README.md) for the full wizard options.

</details>

---

## Security

See [SECURITY.md](SECURITY.md) for the security architecture, reporting process, and known limitations.

One default worth knowing about up front: the app ships with a scoped App Transport Security exception permitting insecure HTTP **only to the Tailscale CGNAT range** (`100.64.0.0/10`), because the expected deployment is plain HTTP to Tailscale IPs on a private tailnet. TLS enforcement remains on for all other connections. If you front your services with `tailscale serve` (HTTPS + MagicDNS), you can remove even this exception locally.

---

## Repository layout

```
Talaria/              iOS app (SwiftUI, Swift 6.2)
TalariaWidgets/       Home screen widgets + Live Activities + lock-screen controls
TalariaShare/         Share extension (URLs, images, files, text → Hermes)
Shared/               Theme palette tables shared between app and widget targets
TalariaTests/         Unit tests (Swift Testing)
TalariaUITests/       UI tests (XCTest/XCUITest)
relay/                HermesMobile relay sidecar (Python/FastAPI; legacy tier — retired, not called by current builds)
connector/            Host-side bridge for the legacy relay tier (relay connection, hermes_mobile MCP tools)
tools/models-shim/    Legacy model-switching shim (Python; retired — current app builds are gateway-native)
tools/appicons/       Alternate app icon gallery renderer
project.yml           XcodeGen project definition (source of truth)
design/               UI design reference files + theme galleries
docs/                 Landing page + screenshots
scripts/              Host ops scripts (service install, watchdog, updates)
skills/talaria/       Agent skill for working in this repo
planning/             Eval notes and cross-machine handoffs
CLEAN_CHAT_PATH.md    Verified SSE event taxonomy and API contract
OPEN_ITEMS.md         Active work items and decisions log (live board)
OPEN_ITEMS-ARCHIVE.md Closed items, moved verbatim (one numbering across both)
BRANCHING.md          Branch/PR workflow conventions
CONTRIBUTING.md       Contribution guidelines
SECURITY.md           Security architecture and reporting
dispatch/             In-flight agent task specs (temporary)
```

---

## Network notes

- The gateway (`:8642`) must be reachable from your phone's Tailscale IP; `:8000` matters only if you run the legacy relay tier
- Bind each service to `0.0.0.0`, not `127.0.0.1`
- Add Windows Firewall inbound rules for each port if on Windows (a Tailscale process-level allow rule also covers this)
- iCloud Private Relay must be disabled (or Tailscale IPs excluded) for HTTP to Tailscale addresses

---

## License

MIT — see [LICENSE](LICENSE). Contributions welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).
