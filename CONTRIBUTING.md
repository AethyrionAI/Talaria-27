# Contributing to Talaria

Talaria is a personal self-hosting project. Issues and pull requests are welcome, but please read this first.

## What this project is

Talaria is a native iOS app + relay sidecar built specifically for self-hosters running [Hermes Agent](https://github.com/NousResearch/hermes-agent) on their own hardware. It is not a general-purpose Hermes client and is not designed for managed or cloud-hosted backends.

## Before you open a PR

- Check [OPEN_ITEMS.md](OPEN_ITEMS.md) — active work items and known issues are tracked there
- For anything architecture-affecting, open an issue first to align before writing code
- The iOS app requires Xcode with the **iOS 26 SDK** (Xcode-beta as of mid-2026)

## Development setup

**iOS app**

```bash
# Requires Xcode (iOS 26 SDK)
open Talaria.xcodeproj
```

> ⚠️ The project uses explicit source file listings via XcodeGen. If you add or remove Swift files, run `xcodegen generate` and commit the regenerated `project.pbxproj`.

**Relay sidecar**

```bash
cd relay
pip install -e .
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

**Models shim**

```bash
cd tools/models-shim
python shim.py
```

## Code conventions

- Swift 6 strict concurrency — no `@unchecked Sendable` without a comment explaining why
- Real data only in settings UI — `"—"` placeholders where values aren't knowable at runtime; no mocked toggles
- Relay-side and app-side changes should be separate commits
- Read `CLEAN_CHAT_PATH.md` before touching the SSE parsing or Sessions API integration

## Testing

The relay has a test suite. Run it before submitting relay changes:

```bash
cd relay
pytest
```

The iOS app has no automated test suite — changes are verified on-device.

## Not in scope

- App Store distribution
- Managed or cloud relay hosting
- Hermes Agent core changes (file issues upstream at [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent))
