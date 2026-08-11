# iOS 27 Beta 5 / Xcode 27 Beta 5 — overnight SDK audit

**Run 2026-08-10 → 2026-08-11 (overnight), tracker #324.** Owen's /goal before bed: check the
new SDK for (1) regressions, (2) usable new features, (3) things the update fixed, (4) anything
else useful — using simulators, with subagent authority (Haiku/Sonnet chore, Opus work, Fable
orchestrating). Pre-bed decisions: skip live Hermes pairing tonight; **auto-promote the
toolchain if fully green**; phone updating to beta 5 overnight.

## Executive summary

**Beta 5 is a safe, boring update for Talaria — promoted to standard toolchain in this commit.**
The full gate is green under the beta5 SDK on the beta5 sim runtime (2056 Swift Testing tests in
156 suites + 14 XCUITest + Release build, 0 errors). The SDK diff touches **nothing Talaria
calls**. Neither of our two known runtime bugs was fixed (one proven still present, one
unreproducible-by-probe), so no workaround can be dropped. The sim still cannot run
FoundationModels generation. Best new API: `SystemLanguageModel.variant`. One new hazard worth
respecting: **beta-to-beta dyld strong-linking** (details below).

| Toolchain | Xcode build | swiftlang | iOS 27.0 sim runtime |
|---|---|---|---|
| beta4 (old std) | 27A5228h | 6.4.0.27.1 | 24A5390f (retained) |
| **beta5 (new std)** | **27A5237l** | **6.4.0.30.4** | **24A5408d** |

First-launch/license: already complete on arrival (no sudo needed). SDK build advertised by
`iphoneos27.0`: 24A5408c; `simctl runtime match` chooses 24A5408d.

## 1. Regressions — none found

- **Debug compile** under beta5: BUILD SUCCEEDED (first checkpoint, ~23:15).
- **Lane gate run 1** (suite + Release): Release PASS (exit 0, 0 Swift compile errors),
  XCUITest 14/14 PASS, **one unit failure**:
  `HTMLArtifactSandboxTests.controlArmWithoutRulesLeaksToTheListener()` — "Expectation failed:
  landed" (negative-control beacon, 5s budget).
- **Triage** (systematic-debugging): passed **3/3 in isolation** on the same beta5 sim (run
  count verified — not the `-only-testing` zero-match trap). Root cause class: the documented
  load-flake precedent (sim-verify-gotchas §9, 2026-08-09: ≥3 concurrent xcodebuild runs flake
  exactly this test's 5s WebKit budget; 3.07s when healthy). Gate run 1 ran alongside three
  probe builds — self-inflicted load, the known trap.
- **Gate run 2** (`--suite`, quiet box): **GATE: PASS** — TEST SUCCEEDED, 2056 tests/156 suites,
  XCUITest 14, skips = the 4 known documented ones (CondenserFidelityTests hardware pair +
  #282 decision pair). Combined with run 1's Release PASS ⇒ promotion condition met.
- WATCH 324-W2: if that control-arm test ever fails on a *quiet* box, treat it as a finding.

## 2. New features catalog

Mechanical diff (Sonnet) + analysis (Opus) over 16 frameworks' `.swiftinterface`; every claim
grounded in interface text (WWDC26 postdates model cutoff — nothing from recall). Artifacts:
session scratchpad `sdk-diff/` (diff-summary.txt, diffs/*.diff, ANALYSIS.md).

**Usable now / soon:**
- **`SystemLanguageModel.variant`** (iOS 27+): `Variant { displayName }`, `.core3` = "AFM 3
  Core", `.coreAdvanced3` = "AFM 3 Core Advanced" (runtime-probed on sim; sim default ==
  .core3). First honest way to *name* the on-device model in Settings→Models / Developer, and
  to stamp battery runs with the serving variant. Two caveats, both probe-proven: it reads
  catalog metadata, so it works even when generation can't (not an availability signal); and
  `hashValue` is per-process (`==` is stable) — never persist or compare by hash.
- **SwiftUI `presentationPlacement(_:)`** + `PresentationPlacement` (.automatic /.leading
  /.center /.trailing; the directional three are iOS-only): direct fit for the app's seven
  `.presentationDetents` sheets on wide layouts.
- **`Transcript.HistoryView`**: Mutable/RandomAccess/RangeReplaceableCollection +
  ExpressibleByArrayLiteral. Fits the condensed-replay path that hand-builds
  `[Transcript.Entry]` (`LocalChatBackend.swift:1232-1247`).
- **FM metadata is now typed** (`[String: GeneratedContent]` / `ConvertibleToGeneratedContent`,
  ~25 declarations): the first per-turn-metadata feature must wrap values in
  `GeneratedContent(...)`, not bare String/Int.
- Smaller: SwiftData `HistoryToken.storeIdentifier: String` + Equatable on sectioned results;
  Vision `RecognizeAnimalsRequest` .revision3 + `Identifier {dog, cat, dogHead, catHead}`;
  `onDropSessionUpdated`/`dragConfiguration` gained iOS.

**Churn that is NOT change (so nobody re-diagnoses it next beta):**
- SwiftUI's scary **831 removed lines = relocation into SwiftUICore** (`@_exported import`
  keeps every name resolving; 0 fully-qualified `SwiftUI.<Type>` refs in the repo; all four
  relocated APIs we use still resolve — the clean build is *explained*, not just observed).
- AppIntents' 1.67MB diff ≈ 99.6% interface reordering. Real delta by sorted set-diff: 43
  lines removed / 14 added, none used by Talaria. (`AudioPlaybackIntent` is NOT new — a
  relocation artifact the unified diff presents as insertion. Method note: run the sorted
  set-diff *first* on mass-reordered interfaces.)
- `EnhancedLinkSecurity` framework **removed from the SDK** — 0 repo references. No frameworks
  added; overlay set (58) unchanged; `_Vision_FoundationModels` (OCRTool/BarcodeReaderTool)
  byte-identical. EventKit, Speech, WidgetKit, HealthKit, CoreMotion, Contacts, Observation,
  ActivityKit, AVFoundation: header-only. **Zero availability deferrals** anywhere in the diff.
- FM removals all land on unused surface: `Transcript.CustomSegment` deleted; `history` became
  `HistoryView`; two already-deprecated members deleted; PCC locale accessors now
  `nonisolated(nonsending) async throws`. Every surface Talaria calls (ToolCallingMode,
  DynamicProfile, tokenCount, LanguageModel protocol, LanguageModelError arms, @Generable,
  UnavailableReason, PCC accessors) — **untouched**.

## 3. Fixed-by-update — nothing we can bank

- **Dynamic actor-isolation trap (#301 family): NOT FIXED.** Reproduced on 24A5408d, 2/2
  deterministic, byte-for-byte signature (`_dispatch_assert_queue_fail` →
  `_swift_task_checkIsolatedSwift` on TCC's XPC reply queue) with a `@Sendable` control passing
  on the same first-grant transition; completions still delivered off-main. Disassembly shows
  beta5's compiler still plants the check in non-Sendable MainActor-formed closure prologues.
  **All @Sendable fixes stay.** Bonus finding: this trap class produces **no .ips on the sim**
  — only an in-process handler or the host-log libdispatch assertion shows it; "no crash
  report" is a false negative.
- **SwiftData `mainContext` trap: UNKNOWN.** A 15-shape probe app (Task-after-yield/sleep,
  inline .task, insert+save, detached→MainActor.run, continuation/URLSession resumes, 8-task
  burst) ran clean in **every** build×runtime cell — including beta4-built × beta4-runtime,
  the July conditions. MainActor bodies never left the true main thread anywhere, so the bug's
  precondition never arose in a minimal app; the 2026-07-26 in-app trap evidently needed full
  app context. **Do not call it fixed; do not drop the private-context workaround** (it is
  correct under both behaviors). Only closer: in-app retest (WATCH 324-W1; probe preserved).
- **FM on the simulator: STILL cannot generate.** `availability == .available`,
  `isAvailable == true`, 24 languages — and every `respond()`/guided generation throws.
  Mechanism confirmed in the sim log: catalog resolves
  `com.apple.fm.language.instruct_3b.fm_api_generic`, entitlement passes, provider selected,
  then every asset reports `version: (none)` — metadata present, weights absent. Availability
  is a catalog question; generation is a weights question. **Verification posture unchanged:
  generation/tokenCount behavior is device-only.**
  - The thrown error's identity differs from beta4's recorded finding: an **un-bridged
    NSError** — domain *string* `FoundationModels.LanguageModelError`, code −1, wrapping
    `ModelManagerServices.ModelManagerError` **Code=1026** — on which `as? LanguageModelError`
    (and every typed cast tried) does **not** fire. UnifiedAssetFramework 5000 appears on b5
    only in unrelated siriactionsd boot logs. Same-binary b4 control is impossible (next
    bullet), so treat this as a measurement note, not a contradiction of the 08-08 finding
    (WATCH 324-W4).
  - `tokenCount(for:)` throws the same 1026 on sim; `SystemLanguageModel.contextSize` (sync,
    non-throwing) returns **0** on sim — code must treat 0 as "unknown". tokenCount lives on
    `SystemLanguageModel` (5 overloads, iOS 26.4+), not on the session.

## 4. Anything else useful

- **🔴 Beta-to-beta dyld hazard (proven, new rule in CLAUDE.md):** a beta5-built binary that
  references new-in-beta5 symbols (our FM probe referencing `variant`) **dies at dyld launch on
  a beta4 27.0 runtime** — `RBSProcessExitStatus domain:dyld(6) code:4`, no .ips, no output.
  `@available(iOS 27.0)` strong-links on any 27.0 runtime; there is no weak-link safety between
  betas of one version. Adopt new beta5 API only while every target device/sim is on beta5
  (the phone updated overnight, so the fleet is clean as of this morning).
- **idb is broken under both Xcode 27 betas**: SimulatorKit.framework moved to
  `Contents/SharedFrameworks/`, FBControlCore hardcodes the release-Xcode
  `Developer/Library/PrivateFrameworks/` path. Workaround (running now, bound to sim
  047279D9): spawn the companion with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
  Kill with `pkill -f "idb_companion --udid 047279D9"` if unwanted.
- `simctl runtime match set` user-override is the working A/B lever between the two 27.0
  runtimes for NEW boots (booted sims keep their runtime). Used twice tonight; **verified
  cleared both times**. First boot after a rebind is slow — budget minutes, not seconds.
- The gate's #300 classifier earned its keep on its first real failure: named the test, quoted
  the assertion, refused to call it a flake, and the skip listing matched the skip count.
- `xcode-select` still points at beta4's CLT — harmless (CLT has no iOS SDK/xcodebuild; the
  `DEVELOPER_DIR` export is mandatory either way). Re-point at leisure (sudo).

## What was promoted in this commit

CLAUDE.md (intro + Build/tooling + Release-command example) · `scripts/mac/lane-gate.sh` +
`scripts/mac/ota-stage.sh` DEVELOPER_DIR defaults · README.md:89 · CONTRIBUTING.md ×3 ·
MAINTAINER_NOTES.md test posture (2056/156 + 14) · OPEN_ITEMS.md #324 (this audit + WATCH
items). Historical docs (dispatch/, past reports, project.yml ATS provenance comment)
deliberately untouched. Memory files updated the same night: device-only-isolation-trap,
swiftdata-maincontext-trap, ios27-beta4-fm-sdk-surfaces, sim-verify-gotchas (+ MEMORY.md index).

## Morning follow-ups for Owen (also in #324 WATCH)

1. Phone is on beta5 → the device confirmations worth a pass when convenient: #301 §V2
   fresh-install negative control; FM `variant.displayName` + tokenCount asymmetry on device;
   maximumResponseTokens throw-vs-truncate.
2. Decide if/when to spend a lane on 324-W1 (in-app SwiftData retest) — zero urgency, the
   workaround is safe and free.
3. Sims CC-B5-probe / CC-B5-control can be deleted whenever; CC-B5-iPhone-Air is the new gate
   sim (panel attached). Beta4 runtime 24A5390f stays on disk as the A/B control.
