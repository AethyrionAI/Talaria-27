# HANDOFF 2026-07-12 — Lane H dispatch (the last outstanding lane)

**Supersedes:** `dispatch/HANDOFF-2026-07-10-LANES-DE.md`
**Main @** `0384858` · **OPEN_ITEMS @** #109 · 542/542 tests green (49 suites)

## Why this handoff exists

Lane audit 2026-07-12: **every lane except H is disposed.** A/B/C/E landed in the
07-10/07-11 train; D (#106) merged + device-verified; F surfaces on main (reused
by Lane J); G (#98) merged (PR #76) **and deployed to OJAMD, verified live**;
I (#99) merged (PR #78); J (#108) + K merged 07-12 via the Mac review loop and
device-confirmed on iPhone. **Lane H (#102/#61) was specced but never
dispatched** — no branch, no PR, no code. That is this session's Priority 1.

## Priority 1 — dispatch Lane H to Fable

- **Spec:** `dispatch/FABLE-LANE-H-local-brain-gen-health.md` (73 lines,
  CORRECTED 2026-07-11 — the runaway-regeneration theory is ruled out and the
  line-597 `GenerationOptions()` is flagged as a red herring; hold Fable to the
  probe-first steps, especially verifying the `GenerationOptions` API surface
  against the iOS 27 SDK before coding).
- **Scope recap:** #102 — `LocalChatBackend.streamResponse` passes NO options;
  add explicit cap (~1024 max response tokens) + sane sampling + a conservative
  tail-repetition breaker. #61 — degenerate-card guard on title/preview
  generation that logs WHICH path (guided vs fallback) tripped.
- **Collision check (re-verified 2026-07-12):** both target files
  (`Talaria/Services/Live/LocalChatBackend.swift`,
  `Talaria/Services/Live/LocalIntelligenceService.swift`) are UNTOUCHED since
  the spec was written — Lanes I/J/K did not contact them. Spec is current;
  Fable should branch from today's main.
- **Mac loop after the PR:** `export DEVELOPER_DIR=/Applications/Xcode-beta.app/
  Contents/Developer` → merge origin/main if needed → `xcodegen generate` (only
  if Swift files were added/removed) → verify `aps-environment: development`
  survives in `Talaria/Talaria.entitlements` → full test on the iPhone 17 Pro
  Max sim `47F68496-24F9-45D9-93D3-1C778DB6B557` with `CODE_SIGNING_ALLOWED=NO`
  → merge with `--merge`. Fresh traps from the 07-12 loop are recorded in
  OPEN_ITEMS #108 (Swift 6 block-observer isolation; INFOPLIST_KEY_* ignored
  with a generated plist; `.automatic == .detailOnly` on this SDK).
- **Verification is on-device:** #102/#61 are device symptoms (phrase-loop,
  thermal "serious", repeated title/preview). After merge, rebuild to
  whoGoesThere and re-run the #67-style session; watch the new degenerate-card
  log line to close the #61 guided-vs-fallback question.

## Also open (context, not this session's blockers)

- **iPad Air matrix (Lane J residual, #108):** J-3 resize matrix, external
  keyboard sweep, mid-stream Stage Manager boundary crossing,
  column-transparency check (`containerBackground(.clear)` risk). Needs
  Shelley's iPad Air, iPadOS 27.
- **Lane G last rubber stamp (#98):** create one real schedule and watch it
  fire + push (route surface and auth already proven live on OJAMD).
- **T6 Phase 1 (#107):** Mini execution checklist untouched — runbook at
  `relay/docs/DEPLOY_MAC.md`.
- **#104 outbox-persistence hardening:** un-gated, small, dispatchable as its
  own lane (no collision with H).
- **Voice wedge (#82 successor):** retest on the next iOS 27 beta seed;
  whoGoesThere no longer carries the c9e909e instrumented build (replaced by
  the Lane D and Lane J/K installs) — rebuild the `#84` branch first.

Written by the 2026-07-12 Mac session (Lanes J+K merge train).
