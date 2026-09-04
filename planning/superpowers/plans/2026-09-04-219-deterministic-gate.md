# 219 — A Deterministic Gate: The Swallowed-Tap Family And The Classifier's Contradiction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every lane pays a tax the tracker has priced: the XCUITest `testConnectedRelaunchSkipsTheConnectEntry` went red on six full-suite runs in one night (09-01), once on 09-02, three times across the 09-03 memory lanes, and once on the 422-S/T/U gate tonight — each a 30–40 minute identical-bytes re-roll, each announced by the classifier as *"ASSERTION TEXT PRESENT — do NOT re-roll"*, which is wrong for exactly this test. This plan (1) makes the failure path describe itself in the LOG so the next red carries the evidence the entry has wanted for a month, (2) makes the gate and classifier handle a NAMED flake by the protocol instead of contradicting it, (3) measures the natural rate, applies the one tap strategy the falsified hedge never tried, and re-measures. #182's renamed sibling (the CONTINUE tap) rides the same helper; #236 gets its evidence discipline without a code change; #324-W2 is out of scope by the entry's own rule.

**Architecture:** Test-side and scripts-side only. No production code changes except one DEBUG-only launch-environment seam if Owen elects it (decision 2). The mechanism named on 09-01 stands: *"the button EXISTS at a valid on-screen frame … and is `hittable=false` at the moment of the tap … the un-hittable state persists for the whole window in the affected instance."* Tonight's log sharpens it — see Evidence.

**Tech Stack:** XCUITest (`TalariaUITests/`) / `scripts/mac/lane-gate.sh` + `lane-gate-classify.sh` + `lane-gate-classify-test.sh` / bash + `xcodebuild -only-testing:TalariaUITests`.

## Evidence (tonight, 2026-09-03 ~23:33 CDT, CC-lane-1 on 24A5423a, bytes `b88f53d8` — saved verbatim in the lane's scratchpad as `219-evidence-20260904.txt`; file it into entry 219 as the first task)

- Preceding test in the bundle: `testChatSendFlow` — the one that TYPES into the composer (a keyboard was up in the process that was then terminated and relaunched).
- The failing instance: `t=21.97s XFLAKE pre hittable=false frame=(24.0, 509.0, 372.0, 56.0) window=(0.0, 0.0, 420.0, 912.0) scroll=(0.0, 127.0, 420.0, 785.0)` — the frame is inside both the window and the scroll view, as the entry says.
- **New:** the tap that followed logged `Scroll element to visible` → `Computed hit point {-1, -1} after scrolling to visible`. XCUITest resolved NO hit point for an element it could find and measure, then "synthesized" a tap at nowhere. This is XCUITest's own statement that hit-testing at the element's activation point found nothing it would deliver a touch to — an overlay, a zero-alpha ancestor, or an element the accessibility server considers off-screen despite its frame.
- Two later tests in the same run used the same helper on the same button at the same frame and read `hittable=true` (`testConnectingAHostViaSettingsEntryPointLandsBackInChat` at 24.65 s, `testDisconnectingAHostReturnsToStandaloneChat` at 23.64 s). Same bytes, same sim, same minute: the state is per-instance, not per-build.
- The test's own `:515-533` diagnostic (`keyboards=`, `springboardAlerts=`, `continueHittable=`) did NOT reach the log — only the `:540` `XCTFail` did. The `.xcresult` for this shape has hung at ~318 MB and never finished writing (09-01, 09-02). **So the evidence the entry keeps asking for is never captured. Task 0 fixes that before anything else.**

## Global Constraints

- **No tracker item numbers in text the gate PRINTS** (the gate's standing rule): the known-flake list is keyed on SEARCH STRINGS (the test name and the entry's header phrase), and `lane-gate-classify-test.sh` resolves each against the tracker file it names.
- **The protocol is unchanged:** on a named flake, re-run ONCE, record BOTH runs. Automating it (decision 1) must keep both logs on disk and name the re-roll in the verdict line; a second red is a real red.
- **Never widen a wait.** #236's lane rule applies to the whole family: *"A budget that has been wrong six times is not a budget that is slightly too small."* The falsified 5 s `isHittable` hedge is not re-tried in any form.
- **A flake fix's RED is a measured rate**, its GREEN is a measured zero. No "it passed three times" — the entry already has seven green induced-load runs that proved nothing.
- **≤ 3 booted simulators, ever.** The measurement batches run on ONE pool member, sequentially, unattended.
- **Plan-authored code is unreviewed code.** Sketches are interfaces; every tap-strategy change is an A/B against the baseline, never a belief.

## Decisions for Owen (one AskUserQuestion round)

1. **The gate re-rolls a named flake itself, once (recommended):** when the ONLY failing test(s) are on the known-flake list and the Swift Testing suite passed, `lane-gate.sh` re-runs the XCUITest target alone (`-only-testing:TalariaUITests`, ~6–8 min instead of ~35), keeps both logs, and prints `GATE: PASS (re-rolled once on a known flake: <test>)`. Alternative: keep the re-roll manual and only fix the classifier's advice.
2. **A DEBUG launch-environment seam that reproduces the fingerprint deterministically** (a transparent full-screen overlay over the wizard when `UITEST_OVERLAY_BLOCKS_WIZARD=1`) so Task 0's diagnostic and Task 3's tap strategy can be exercised on demand — recommended; it is a fixture for the failure PATH, not a claim about the cause. Alternative: test-only, verified on the next natural red.
3. **Coordinate tap as the fallback strategy** (`element.coordinate(withNormalizedOffset: .init(x: 0.5, y: 0.5)).tap()` after the hittable poll times out) — recommended as the A/B arm; it bypasses XCUITest's hit-point resolution, which is the step that returned `{-1, -1}`. Alternative: seed the connected state for this test via launch environment and skip the wizard tap entirely — NOT recommended until the mechanism is named (it deletes coverage rather than fixing it).

## Session contract

1. Read `OPEN_ITEMS-ARCHIVE.md` #219 (all 09-01/09-02 blocks and the sweep-14 close), #182, #236, #324-W2, and the 09-03 classifier notes in entry 422. File tonight's evidence into #219 as a dated append-only pointer block (the entry is archived; #317(a) applies). Pre-register bars DET-A..E.
2. Task 0 and Task 1 are independent lanes (test-side and scripts-side); both are RED-first against fixtures. Task 2 is an unattended batch. Task 3 waits on Task 2's baseline.
3. Worktree isolation for the code lane; the scripts lane touches `scripts/mac/` only and its self-test IS its gate.

## File structure

**Modify (test-side):**
- `TalariaUITests/AppTemplateUITests.swift` — the hittability-gated tap loop (`:477-509`) and the diagnostic block (`:515-533`) become one shared helper; `waitForComposer` (`:836`) polls hittability where a tap follows.
- `TalariaUITests/MessageIdentityUITests.swift` — its private `waitForComposer` (`:254`) delegates to the shared helper.
- **Create** `TalariaUITests/Support/HittableTap.swift` — `XCUIElement.tapWhenHittable(timeout:strategy:) -> TapOutcome`, the diagnostic activity emitter, the (decision 3) coordinate fallback behind a strategy enum.

**Modify (scripts-side):**
- `scripts/mac/lane-gate-classify.sh` — a `known-flake` verdict keyed on a search-string list; advice prints the protocol, not "do NOT re-roll".
- `scripts/mac/lane-gate-classify-test.sh` — a third fixture (XCUITest red WITH a locus on a known name → `known-flake`; the same shape on an unknown name → `assertion`), and the list's strings resolved against the tracker files.
- `scripts/mac/lane-gate.sh` — (decision 1) the single UI-target re-roll under the exact shape; both logs in `$LOGDIR`; the verdict line names it.
- **Create** `scripts/mac/ui-bundle-batch.sh` — runs `xcodebuild test -only-testing:TalariaUITests` N times on one named sim, sequentially, writing per-run logs and a one-line ledger (`run, verdict, failing tests, t=… XFLAKE lines`); the measurement instrument for DET-C/E.

**Modify (production, DEBUG only, if decision 2):** the wizard screen reads `UITEST_OVERLAY_BLOCKS_WIZARD` and mounts a clear, hit-testable overlay above START CHATTING.

## Bars (paste into entry 219 as a dated block before Task 0)

- **DET-A — the failure path describes itself (test-side, fixture-verified).** On a tap that times out un-hittable, the helper emits `XCTContext.runActivity` names carrying: `keyboards=N`, `alerts=N`, `windows=N`, `app.state`, the accessibility elements whose frames CONTAIN the target's centre point (identifier, type, frame — at most 12), and the target's `isEnabled`/`isSelected`. Under the decision-2 fixture the emitted list names the overlay; without it (a natural red) the list is still emitted. Mutation: drop the centre-point walk → the fixture test reds.
- **DET-B — the classifier tells the truth about a named flake (scripts, self-test).** Fixture: an XCUITest red with a locus on a listed name → `known-flake`, advice = the protocol; the same red on an unlisted name → `assertion` (unchanged); a runner death → `runner-flake` (unchanged); every listed search string resolves in the tracker file it names. Mutation: empty the list → the known-name fixture reds.
- **DET-C — the baseline (unattended, quiet box).** `ui-bundle-batch.sh` × 10 on `CC-lane-2` with nothing else building: the natural red rate for the three swallowed-tap tests (`testConnectedRelaunchSkipsTheConnectEntry`, `testConnectingAHostViaSettingsEntryPointLandsBackInChat`, `testDisconnectingAHostReturnsToStandaloneChat`) with each red's DET-A activity captured. Prediction written first: ≥ 1/10 red on the first, 0/10 on the others; the DET-A dump names the same top element in every red.
- **DET-D — the gate's single re-roll (scripts, fixture-verified, decision 1).** The re-roll fires ONLY when the failing set ⊆ the known list AND the Swift Testing suite printed its passed count; a red on any other test never re-rolls; both logs present; a second red is `GATE: FAIL`. Mutation: widen the condition to "any XCUITest red" → the unlisted fixture reds.
- **DET-E — the fix (unattended, after DET-C).** With decision 3's strategy on, `ui-bundle-batch.sh` × 20: **0/20 reds** on the three tests; Fisher p < 0.05 against DET-C's rate — or, if the rate does not move, the DET-A dumps NAME the mechanism and the consequence goes to Owen. Either outcome closes 219's reopen trigger with evidence.
- **DET-F (#236, no code):** the next MessageIdentity red on a gated run has its transcript dump (PR #326) quoted into the entry within the same lane that hit it; the gate's failure advice for that test names the dump's search string. 236-C's "name the cause first" rule is unchanged.

## Task 0: The self-describing failure path (bar DET-A)

- [ ] **Step 1 (fixture, decision 2):** the DEBUG overlay seam; a UI test `testOverlayFixtureMakesStartChattingUnhittable` that launches with the env and asserts the helper's `TapOutcome.unhittable` with a dump naming the overlay's identifier. RED (no helper, no seam).
- [ ] **Step 2:** the shared helper: poll `isHittable` up to the existing budget on a 0.25 s cadence; on timeout emit the DET-A activities and return `.unhittable(diagnostic)`; on success tap and return `.tapped`. Replace the three call sites. Every activity name ≤ 200 chars so the log stays greppable.
- [ ] **Step 3:** GREEN on the fixture; the existing 15 UI tests unchanged in count; mutation named in DET-A; commit; gate.

## Task 1: The classifier and the gate (bars DET-B, DET-D)

- [ ] **Step 1:** `lane-gate-classify-test.sh` gains the third fixture and the resolution check — RED.
- [ ] **Step 2:** `KNOWN_FLAKE_TESTS` (search strings + the tracker file each resolves in) in `lane-gate-classify.sh`; the `known-flake` verdict and its advice (the protocol text, both logs, the entry's header phrase to grep).
- [ ] **Step 3 (decision 1):** `lane-gate.sh` — after `require_xcuitest_count`, if the failing set ⊆ known and the Swift Testing count passed: run the UI target once more into `$LOGDIR/suite-reroll.log`, apply the same checks to it, print the verdict with the re-roll named. Never on a Swift Testing red.
- [ ] **Step 4:** self-test GREEN (~1 s); one real gate run on `main` to see the new path print; commit.

## Task 2: The baseline (bar DET-C)

- [ ] `ui-bundle-batch.sh` — sequential, one sim, ≤ 3 booted respected, per-run logs, ledger; run × 10 on a quiet box (overnight or a workday morning when no lane is building); file the ledger + every DET-A dump into #219.

## Task 3: The strategy A/B (bar DET-E)

- [ ] Decision 3's coordinate fallback behind `HittableTap.Strategy.coordinateAfterTimeout`, default OFF in the helper, ON via the batch's env for the measurement; `ui-bundle-batch.sh` × 20 with it ON. If 0/20: promote the strategy as the default and record the rate pair. If not: the dumps name the top element; STOP and file.

## Task 4: #182 and #236 (no new mechanism)

- [ ] #182's test and `testDisconnectingAHostReturnsToStandaloneChat` already use the shared helper after Task 0; their counters are read from DET-C/E's ledger rather than kept by hand.
- [ ] #236: the gate's advice for `MessageIdentityUITests` names `the on-device reply for` and the dump's search string; nothing else changes until a red arrives with the dump.

## Out of scope, and why

- **#324-W2** — two occurrences, both under ≥ 3 concurrent builds; the entry's own rule is "only if it recurs on a QUIET box." DET-C/E run on a quiet box and will say if it does.
- **Seeding the connected state to skip the wizard** — deletes coverage; not before the mechanism is named.

## Self-review (2026-09-04)

- Every line number was read tonight, not recalled (`AppTemplateUITests.swift:477-509`, `:515-533`, `:540`, `:836`; `MessageIdentityUITests.swift:254`; `lane-gate-classify.sh:96-113`, `:193-199`; `lane-gate.sh:369-372`, `:185-210`).
- The `{-1, -1}` hit point is tonight's log, verbatim; it is evidence about XCUITest's resolution step, not a named cause.
- The gate performs zero re-rolls today (verified by reading the script); decision 1 changes that only under the exact shape the bars pin.
- What this plan does NOT claim: that the coordinate tap fixes it. DET-E is the experiment; a null result is a finding.
