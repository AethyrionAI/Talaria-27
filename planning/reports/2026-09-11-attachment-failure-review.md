# Attachment failure reporting — home review

Scope: OPEN_ITEMS #439 and #440. Branch `codex/attachment-failure-reporting`, based on `a462ea77438fc5dd711cd9771c379343d08b4a32`. Draft PR only; Owen has explicitly prohibited merging before pulling and testing at home.

The picker now reports refused files, failed image preparation, and a full composer through the existing dismissible banner. The share drain uses the same staging decision. Whole-share corruption, stale incomplete writes, and oversize payloads now reach that banner even when nothing can be staged. Reader accounting uses logical payload bytes, matching the writer's limit without charging filesystem allocation or envelope metadata.

Ten regression tests were added in the existing ShareInboxCoreTests and ShareInboxDrainTests suites. ShareCapPolicyTests now checks the actual staging result instead of a second refusal classifier. No new Swift source files were added.

## Verification status

Windows has no Swift/Xcode runtime available. The tests were written before production edits, but no failing baseline, passing Swift run, simulator run, or Release build has been observed. These changes are not launch-validated or shipped.

Independent diff review found no actionable bugs. Existing adjacent limitation: photo loading/decoding in `AttachmentPickerSheet` can fail before it emits an `AttachmentResult`; this earlier silent dismissal is outside these staging changes and remains unresolved. This PR does not cover every photo-picker failure.

Before any merge decision, pull the branch on the Mac and run the repository's full gate with the promoted Xcode RC toolchain. Unplug the phone first to avoid the documented #438 audio-input test hazard:

```sh
DEVELOPER_DIR=/Applications/Xcode-rc.app/Contents/Developer TALARIA_SIM_NAME=CC-lane-1 scripts/mac/lane-gate.sh
```

Confirm a positive gate verdict, actual nonzero Swift Testing and XCUITest counts, and the Release build. The new tests should increase the Swift Testing count by ten relative to the same base tree. If the gate fails, retain the first failure evidence and fix the branch before review.

## Device review

- Keep a draft and an existing attachment. Pick a text file over 350 KB, a PDF over 10 MB, and a corrupt PDF. Confirm the banner names the reason while preserving the draft and existing chips.
- Pick a valid image and text file, then reach the attachment-count limit. Confirm an additional item is refused with a useful explanation. Dismiss the banner.
- Share a valid file and confirm normal composer seeding. Whole-envelope corruption and interrupted writes are covered by the regression fixtures; avoid modifying the production App Group just to manufacture those failures.
- Check that the failure banner remains visible with a hostless/unavailable brain, and a later clean share clears the old share failure.

Record Mac gate and device results under #439/#440 before marking either item complete. Do not merge automatically.
