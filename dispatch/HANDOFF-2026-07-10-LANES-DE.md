# HANDOFF — 2026-07-10 evening (supersedes HANDOFF-2026-07-11.md)

**Repo:** AethyrionAI/Talaria-27 `main` @ b6637f3+, clean (`planning/` untracked by design).
Phone (whoGoesThere) keeps `c9e909e`. **Fable credits expire SUNDAY.**

## Lane status — the confusion, resolved

| Lane | Spec | Fable status | Mac status |
|---|---|---|---|
| A — Continuity Fabric | `FABLE-LANE-A-continuity-fabric.md` | DONE → **PR #61 open** | review+merge LAST (after C) |
| B — Markdown depth | `FABLE-LANES-BC.md` | DONE → **PR #60 open** | review+merge anytime |
| C — correctness batch | `FABLE-LANES-BC.md` | DONE → **PR #59 open** | review+merge BEFORE A |
| — #84 preflight third state | (C item 5) | DONE → **PR #62 open** | logic mergeable; device checklist stays wedge-blocked (#82) |
| — green test baseline | — | **PR #63 open** | merge FIRST (restores green so other PRs signal cleanly) |
| D — P8 IR v0 | `FABLE-LANE-D-p8-ir-v0.md` (NEW) | **NOT started** — was "if credits remain", never spec'd until now | dispatch NOW |
| E — Theme drama ph.1 | `FABLE-LANE-E-theme-drama.md` (NEW) | **NOT started** | dispatch NOW |

## Independence & start order

- **D and E are independent of A/B/C and of each other.** Neither touches
  `ChatScreen.swift` (A/C's collision surface). E lives in ThemeCatalog /
  ThemeArtDirection / ThemeTextures / ReactorOrb / ThemePaletteCore; D is
  new-files-only (IR schema + renderer + tests + DEBUG harness).
- **Everything can start now.** Fable lanes run on separate branches; only the
  MAC-SIDE MERGE order is constrained, never dispatch order. Dispatch D + E in
  parallel today so they run against the Sunday expiry while the A–C PRs go
  through the review-build-merge loop.
- Deferred Lane-D alternates: candidate #5 (tool telemetry) and #11 (composer
  draft persistence) collide with transcript/composer surfaces (Lanes B/A/C) —
  hold until after the merge train.

## Mac-side merge train (review-then-build loop, DEVELOPER_DIR=Xcode-beta)

1. **PR #63** (green baseline) → 2. **PR #59** (Lane C) → 3. **PR #60** (Lane B,
   anytime) → 4. **PR #61** (Lane A, last) → 5. **PR #62** (#84 preflight logic —
   merge when Owen chooses; device checklist waits on the next beta seed).
   After lanes land: revert `dispatch/` from main (standing plan).

## New this session (2026-07-10)

- **Theme suite mapped end-to-end** (OPEN_ITEMS **#91**): gallery committed to
  `design/themes/` (17 themes + app-icons + index); root causes of "not drastic"
  verified (no motion engine, no bespoke orbs, art direction only on Event
  Horizon); orb issue finally filed as **gh#64** (the 7/6 draft never was).
- Lane E spec = prove the drastic bar on Event Horizon (taxonomy, motion engine
  w/ 3 on-device presets, `.singularity` orb, intensity pass). Gate: Owen's
  device verdict → then Phase 2 (schema extension) + Phase 3 (port the 10
  remaining themes).

## Parked / standing (carried from 07-11 handoff — still true)

- #82 voice wedge PARKED (Apple seed breaks all third-party capture; Owen owes
  Apple Feedback). #84 device checklist wedge-blocked.
- #85 hermes_delegate URL exposure decision (Owen). #86 QueuePool (watch only).
- #25 CTX meter denominator ~1.4x high (Owen gathering examples).
- OJAMD: #87 deployed, #88 fixed, #54 verified-resolved (all closed 07-09 late).
- Toolchain: ALWAYS `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`.
- Probe harness reusable at `talaria-probe/probe.py` (OJAMD) for the on-device
  condenser rung.
