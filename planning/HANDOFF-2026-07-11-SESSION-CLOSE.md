# HANDOFF — 2026-07-11 session close (supersedes HANDOFF-2026-07-10-LANES-DE.md)

**Repo:** AethyrionAI/Talaria-27 `main` @ c2a385d. Phone (whoGoesThere) runs the
Lane E verdict build (branch `9c7ec11` = merged into c2a385d; rebuild from main
at leisure — identical content).
**Working tree:** OPEN_ITEMS.md edited (#91 gate cleared, #94/#95 added) —
**commit pending Owen**. `planning/` untracked by design.
**⚠️ FABLE CREDITS EXPIRE SUNDAY** — if any cloud dispatch is wanted (Phase 3
theme ports, deferred candidates #5 tool telemetry / #11 composer draft
persistence), TODAY is the window. Both deferred candidates are now
collision-free (the transcript/composer lanes all merged).

## What this session did (2026-07-10 evening → 07-11)

**Merge train (7 staged PRs → all resolved):**
#63 green baseline → #59 Lane C (correctness) → #60 Lane B (markdown, OPEN_ITEMS
#90-collision renumbered to #92, pbxproj regen-resolved) → #61 Lane A
(continuity fabric; ChatStore conflict hand-merged: onSendFailed + journal init
both preserved) → #62 (#84 preflight third state; gating verified in code before
merge). #65 Lane D stays open, DO-NOT-MERGE by design.

**Device-crash arc (3 root-caused from real evidence, all fixed + verified):**
- **PR #67** — image sends crash-looped: `beginLongSend` BGTask launch handler
  inherited @MainActor isolation (Swift 6.2), scheduler invoked it off-main →
  trap. Attachment-only because only attachment sends enter continued
  processing. + same fix on expirationHandler. Voice: viable-capture-format gate
  before both installTap sites (#82 wedge = uncatchable NSException otherwise).
- **PR #68** — voice lockup/`nullptr == Tap()`: wedge thrashed route changes into
  RACING restarts (no re-entrancy guard) + main-thread session activation.
  restartCapture now serialized + circuit-broken (>3/30s → #84 blocked state).
  Keychain: `kSecAttrAccessibleAfterFirstUnlock` (was WhenUnlocked default).
- **PR #69** — the "random unpair after reboot" solved: post-reboot location
  relaunch runs PRE-FIRST-UNLOCK → credentials read empty → cached for the
  process lifetime → foregrounding the zombie shows NOT PAIRED. Nothing was ever
  deleted. Fix: reload on protectedDataDidBecomeAvailable/didBecomeActive +
  isProtectedDataAvailable gates on handleSystemLaunch and
  refreshUnpairedRelayContext. **Verified: reboot → unlock → open (no
  force-quit) → pairing + key + relay URL present.**

**Lane E / theme suite (PR #66 merged — gate CLEARED: "Now THAT is an outrageous
theme"):** Phase 1 (taxonomy, motion engine w/ 3 presets ships `.faithful`,
`.singularity` orb, intensity pass) + three device-verdict corrections that ARE
the Phase 3 recipe: soft blurred specks (1.25pt, per-layer blur — CSS
radial-gradient is a FADE not a disc radius); panel/card washes must never
become screen-scale pools (teal-swamp bug, pools 5→3 design-exact); port the
full element inventory (`.spin-ring` lensing starburst was skipped → now
`RadialSpokeSpec`/`RadialSpokeField`, gold 2°/2° @ .03, 30s rotation,
reduce-motion safe, nil = byte-identical for other themes).

**Test suite:** 287 → **426** across the session, green at every merge.

## Device checklist results (planning/DEVICE-TEST-WAVES-2026-07-10.md)
Lane C ✅ · Lane B ✅ · Lane A 3a/3b/3d ✅ (3c inbox bad-row untested — needs a
malformed row injected into the relay DB on OJAMD; low-stakes, opportunistic) ·
#62 voice: blocks safely, wedge-caveated ✅ · images-over-Hermes ✅ ·
credential reboot survival ✅.

## Parked / standing
- **#82 voice wedge** — still Apple's seed; capture stack broken for all
  third-party apps. Retest ≈ 10 min on next seed (any reboot doubles as the
  test now). Owen still owes Apple Feedback.
- **#84 device checklist** — wedge-blocked half only; logic merged (#62).
- **#65 Lane D PR** — open by design; next rung = on-device emission-quality
  (needs FoundationModels runtime, Mac-side). Probe harness:
  `talaria-probe/probe.py` on OJAMD.
- **#85** hermes_delegate URL exposure (Owen decision) · **#86** QueuePool
  (watch) · **#25** CTX meter denominator (Owen gathering examples) ·
  **#90** DEVELOPMENT_TEAM (go-public cleanup).
- **NEW #94** pair() clear-before-redeem hardening (small; converts failed pair
  into credential loss today). **NEW #95** WATCH credential fixes across
  future reboots.
- Toolchain: ALWAYS `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`.
- Repo hygiene: merge-commit convention; xcodegen regen resolves every pbxproj
  conflict (never hand-edit); xcscheme mtime-touch after regen is a known
  false-positive — `git checkout --` it.
- Standing plan from 07-10 handoff still pending: revert `dispatch/` from main
  now that the lanes have landed.

## Next session opening moves
1. Owen commits the OPEN_ITEMS working-tree update.
2. Decide Fable dispatch before Sunday expiry: Phase 3 theme batch-port (recipe
   proven, spec = #91's corrections) and/or #5 / #11.
3. Lane E Phase 2 schema extension when theme work resumes.
4. Optional: #94 hardening (30-min fix), 3c inbox bad-row test via relay DB.

---

# ADDENDUM — 2026-07-11 afternoon: the gallery port wave

**`main` @ 27b5963.** Fable (Claude Code) delivered the Phase 2+3 dispatch as a
4-PR stack; all merged after review-test-verdict: **#70** (schema: line fields,
title shadows w/ glitch, pool pulse, laser bars/non-square tiles/halftone, 12 orb
compositions, landed unwired + byte-identical-pinned) → **#74** batch 1 (was #71 —
GitHub auto-CLOSED it when #70's base branch was deleted; recreated same-branch;
**new law: merge → retarget next PR to main → THEN delete branch**) → **#72**
batch 2 → **#73** batch 3 (+ Owen-approved correction round: TAG corner ribbon +
panel top-strip primitives).

**Device verdicts: 11/12 Good** (Glitch Garden's animation + Karaoke's motion
called out). **Deep Sea Diner CUT** — removed end-to-end on the batch 2 branch;
settings decode made tolerant (vanished theme → Deep Field, never a prefs reset);
`.anglerLure` kept as intentional orphan; orb invariant retooled to
"never-shared, orphans named". Tests: 445 → 441 → 445 across the wave (4
parameterized cases tracked the theme count — a count that doesn't move when it
should is the tell; a stale-DerivedData incident mid-wave proved it).

**Staged next wave** (`Neon-Arcade-2.zip`, Claude Design "Fable" session): Midnight
Aquarium / Molten Forge / Haunted VHS — reviewed, ~90% schema-native. Gaps: line-
field drift (caustics), heat-shimmer breather, REC blink. **Owen decision open:**
Molten Forge vs Solar Forge identity overlap. Files not yet in repo; Fable credits
expire SUNDAY — transfer + batch-4 dispatch today if going.
