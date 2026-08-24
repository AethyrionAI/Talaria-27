# Contributing to Talaria

Talaria is a personal self-hosting project. Issues and pull requests are welcome, but please read this first.

## What this project is

Talaria is a native iOS app built specifically for self-hosters running [Hermes Agent](https://github.com/NousResearch/hermes-agent) on their own hardware. It is not a general-purpose Hermes client and is not designed for managed or cloud-hosted backends.

## Before you open a PR

- Check [OPEN_ITEMS.md](OPEN_ITEMS.md) — active work items and known issues are tracked there
- For anything architecture-affecting, open an issue first to align before writing code
- The iOS app requires Xcode with the **iOS 27 SDK** (Xcode 27 beta — `Xcode-beta6.app` as of 2026-08-24)

## Development setup

**iOS app**

```bash
# Requires Xcode 27 beta (iOS 27 SDK).
# The .xcodeproj is generated from project.yml — generate it first.
xcodegen generate
open Talaria.xcodeproj

# Building from the command line with several Xcodes installed?
# Point at the beta toolchain first, or iOS 27 APIs fail to resolve:
export DEVELOPER_DIR=/Applications/Xcode-beta6.app/Contents/Developer
```

> ⚠️ The project uses explicit source file listings via XcodeGen. If you add or remove Swift files, run `xcodegen generate` and commit the regenerated `project.pbxproj`.

**Relay sidecar (legacy — optional)**

The relay tier is on a retirement path. Current builds need it only for the realtime-voice WebRTC bootstrap; pairing, phone queries, the inbox, and model picking all ride the gateway now. Skip this unless you need server voice today.

```bash
cd relay
pip install -e .
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

The connector (`connector/`) is the host-side bridge for the relay tier. Only needed alongside the relay above.

```bash
cd connector
python -m venv .venv && source .venv/bin/activate
pip install -e .
hermes-mobile setup
```

## Code conventions

- Swift 6 strict concurrency — no `@unchecked Sendable` without a comment explaining why
- Real data only in settings UI — `"—"` placeholders where values aren't knowable at runtime; no mocked toggles
- Relay-side and app-side changes should be separate commits
- Read `CLEAN_CHAT_PATH.md` before touching the SSE parsing or Sessions API integration

## Testing

**iOS app** — there is a substantial automated suite (Swift Testing for units, XCUITest for launch/UI). One script runs everything a change must pass before submission:

```bash
scripts/mac/lane-gate.sh
```

It runs the Debug suite **and a Release build**, and reports PASS/FAIL per check. Release is not optional: the suite, device installs and the plain CLI compile check are all Debug, so a symbol that exists only under `#if DEBUG` and is referenced by production compiles green everywhere except the configuration you ship. That happened, and it went unnoticed for two days behind a fully green suite.

To run the suite alone:

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta6.app/Contents/Developer
xcodebuild test -project Talaria.xcodeproj -scheme Talaria \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  CODE_SIGNING_ALLOWED=NO
```

Note that Swift Testing and XCTest report separately. Look for the `Test run with N tests in M suites passed` line for the unit suite — the `Executed N tests` line only covers the XCUITest target, so reading that alone badly undercounts. Device-only behaviour (push, HealthKit, real voice) still needs on-device verification.

**Relay** — has its own suite:

```bash
cd relay
pytest
```

Run bare `pytest`; the project's `pyproject` already sets `addopts = -q`, and passing `-q` again doubles it and suppresses the summary.

## Not in scope

- App Store distribution
- Managed or cloud relay hosting
- Hermes Agent core changes (file issues upstream at [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent))
