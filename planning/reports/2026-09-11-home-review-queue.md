# Home review queue — September 11

All changes are draft PRs. Do not merge until Owen has reviewed and tested them.

1. Disclosure corrections: `codex/disclosure-review-corrections`, PR #453. Read the privacy policy and two reviewer drafts. They distinguish the default local brain, optional Private Cloud, and the host tier. They describe the weather gap in submitted build 3338 honestly. No runtime changes; merging the Pages source would publish it, so keep this draft until the wording is approved.
2. Voice weather: `codex/voice-weather-attribution`. Native Talk retains tool outcomes and captured brain through live transcript and saved chat. Completed local/PCC weather calls show the existing Apple Weather row; failures and host/unknown origins do not. Interrupted calls settle without losing completed weather evidence. Hosted WeatherKit attribution remains open.
3. Attachment failures: `codex/attachment-failure-reporting`, PR #452. Follow `2026-09-11-attachment-failure-review.md` for picker/share checks.

Each branch is based independently on main. Test each branch separately; they are not an integration build. Tracker changes may need reconciliation when merging later.

## Mac verification

Swift tests and builds were not run on Windows. Unplug the phone before running the gate to avoid the documented #438 audio-input hazard. On each Swift branch, use the RC toolchain and the repository gate:

```sh
DEVELOPER_DIR=/Applications/Xcode-rc.app/Contents/Developer TALARIA_SIM_NAME=CC-lane-1 scripts/mac/lane-gate.sh
```

Require actual Swift Testing/XCUITest counts, a clean Release build, and the gate's positive verdict. The voice branch replaces one old gap-measurement test with six regression tests (net +5). The attachment branch adds ten tests. These are expected counts, not observed passes.

## One device sitting

- Native Talk, on-device brain: ask for weather; inspect attribution in live Talk and in the saved reply after ending Talk. Tap the legal link, then relaunch and confirm it remains.
- Repeat with Private Cloud selected if available. Confirm an unrelated question has no weather row. A failed weather lookup must not acquire attribution from a previous turn.
- Interrupt a weather reply after it begins; visible weather text should retain attribution. Start another question and confirm tool history does not leak across turns. Stop or lock during an unfinished tool call; its saved history must not remain running.
- Run PR #452's attachment cases with an existing draft, including a valid share and a refused file.
- Use the same voice sitting to observe microphone shutdown on End Talk and App Lock. Record build/OS and the actual result; do not treat this as automatically discharging every older instrumented device bar.

Photo-picker failures before attachment staging remain an adjacent unresolved item. This queue does not change that path, deploy a host, upload a build, or submit a review response.
