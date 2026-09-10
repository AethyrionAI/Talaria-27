# iOS 27 RC / Xcode 27 RC — regression round + SDK audit

**Run 2026-09-09 (night), tracker #441.** Owen's ask: *"Xcode27 Release Candidate has
released, loaded as xcode-rc… iOS27 Release Candidate has released as well — installing
tonight… can you look and do any regression testing necessary? Make sure everything
worked. Make sure there's nothing new unblocked, or features we need to adopt."* Bars
441-A..F pre-registered in `OPEN_ITEMS.md` (commit `805b4691`) before any run. Submission
prep is explicitly out of scope tonight (Owen: *"will need help with that later, but not
tonight"*). Naming care: this Xcode calls itself **27.0 (27A266a)** with no "RC" in the
build string; Apple's release-notes pages title themselves "Xcode 27 RC" and
"iOS & iPadOS 27 RC". Builds, not labels, are quoted where it matters.

## Executive summary

**The RC is a safe, boring update for Talaria — GATE: PASS on the first run, no re-roll:**
`TEST SUCCEEDED` with **3426 Swift Testing tests in 281 suites + 18/18 XCUITest** on the
**24A434** sim runtime (verified from the booted device by the gate's own preflight, not
inferred from match policy), Release build clean, **0 Swift compile errors** under
swiftlang 6.4.0.34.1; the only skips are the known-permanent CondenserFidelityTests pair.
Both 441-A count floors met exactly (3426 ≥ 3426, 18 ≥ 18). The SDK is a polish release:
5 of 280 device interfaces carry real changes (Cinematic, CoreMedia, Photos, PhotosUI, one
AVFoundation property) — all additive, none on surface Talaria calls; FoundationModels is
version-stamp-only. **Nothing is unblocked:** the #402 re-probe on 24A434 reproduces the
24A5423a result line for line — PCC's metadata plane works, generation on BOTH tiers still
dies in under a second (`SystemLanguageModel.Error code=0 "assets unavailable"` for PCC,
`LanguageModelError -1` with `contextSize=0` for on-device) — so #324's "generation is
device-only" stands on the RC runtime and every sim-side structural pin stays. Nothing to
adopt: the RC SDK adds no API the app references. The one thing the arrival falsified was
already false before it arrived: Xcode-beta5 is gone from `/Applications`.

| Toolchain | Xcode build | swiftlang | iOS SDK | iOS 27.0 sim runtime |
|---|---|---|---|---|
| beta6 (current std) | 27A5252f | 6.4.0.33.1 | 24A5422a | 24A5423a |
| **rc (new)** | **27A266a** | **6.4.0.34.1** (clang-2100.3.34.1) | **24A430** | **24A434** |
| device `whoGoesThere` | — | — | — | **24A5430a** (measured 2026-09-06 by #392/#398's device runs, on the phone since 08-31/09-01); **UNMEASURED after tonight's RC install** |

Measured on the Mac Mini directly (no MCP caveat). First-launch/license complete on
arrival (`xcodebuild -checkFirstLaunchStatus` exit 0, no sudo). macOS 26.6.2 (25G83).
Runtimes on disk: 24A434 + 24A5423a + 24A5408d + 24A5390f + iOS 26.5 23F77 (37.8 GB).
`simctl runtime match list` for `iphoneos27.0`: SDK Build 24A430, **Chosen Runtime
24A434**, no user override — the RC's sim runtime is one build newer than its own SDK,
the first time the two have differed inside one Xcode. Consequence already visible: the
CC-lane pool **silently advanced** — `simctl list -v devices` shows CC-lane-1 and
CC-lane-3 under 24A434 while CC-lane-2 (booted since an earlier lane) still runs
24A5423a until its next boot. Exactly the hazard #401 §5.3 / 398-C named.

**🔴 Falsified on arrival: `/Applications/Xcode-beta5.app` is GONE.** #401's promotion
kept it as the A/B fallback on Owen's word and CLAUDE.md still says it "STAYS on disk";
only `Xcode-beta6.app`, `Xcode-rc.app` (installed 2026-09-03 07:21) and release
`Xcode.app` (26.6, 17F113) remain. Deletion date/hand unknown. The 24A5408d *runtime*
survives, so runtime A/Bs still work; a beta5 *build* needs a re-download.

## 1. Regressions (441-A) — none found; every clause met

Full `lane-gate.sh` (Debug suite + Release build),
`DEVELOPER_DIR=/Applications/Xcode-rc.app/Contents/Developer`, `TALARIA_SIM_NAME=CC-lane-1`,
`main @ cf0a2d21`, launched 23:51 with zero concurrent xcodebuilds (counted by
`ps -axo comm`, not pgrep), phone not corded (USB scan: 0 iPhones — #438 clear), 1 other
sim booted. Preflight all PASS: in-gate TCC grant, classifier self-test (86 checks),
pbxproj drift check, **runtime verified `iOS 27.0 (24A434)` from the booted device**.

- **GATE: PASS on 24A434, first run, no re-roll** (verdict 00:07; ~16 min end to end).
  xcodebuild exit 0 · `** TEST SUCCEEDED **` · **Swift Testing: 3426 tests in 281 suites,
  passed in 215 s** · **XCUITest: 18/18 passed** per the per-test ledger (longest
  `testTranscriptNeverRendersDuplicateMessageIDs` 57 s; the dropped-tap retry loop logged
  nothing) · Release build `** BUILD SUCCEEDED **`, 0 Swift errors, 20 warnings.
- **Both 441-A count clauses met exactly as pinned:** 3426 ≥ 3426 (the 3425 of #431's
  gate on `c195a41e` plus the one `@Test` NamingSweepTests gained since) and 18 ≥ 18.
  The floor was pinned to the HEAD being gated, per 401-A's lesson, and the count MOVED
  by exactly the expected one — no stale-incremental doubt.
- Skips: exactly the 2 known-permanent CondenserFidelityTests (Apple Intelligence
  hardware). No unexplained skip.
- The six `NativeVoiceCaptureGenerationTests` rows that hang when the phone is corded
  (#438) ran green inside the 3426.

Compile facts already in hand from the suite build: **0 Swift errors** under swiftlang
6.4.0.34.1; **87 warnings**, every one in a family that predates this toolchain —
approachable-concurrency diagnostics in the UI-test helpers (`main actor-isolated
property … nonisolated context`, 37 of the 87, all in `HittableTap.swift` /
`RemoteImageRenderTests.swift` / `AppTemplateUITests.swift`), our own `#198`
deprecation shims (`legacyIsContextOverflow` and siblings — "Delete with
GenerationError"), and `#NoUsage` / `#ImplicitStrongCapture` lint. No warning names a
new-in-RC API. **Caveat on the count:** the beta6 gate logs on this Mac report 0
warnings only because they were incremental builds that recompiled nothing (the stale
incremental trap); this run was a full rebuild under a new toolchain, so 87 is the
project's true standing warning count, not an RC regression. The SE-0508 source break
(still listed as a Known Issue in the RC notes) does not bite — zero compile errors.

## 2. SDK surface diff (441-B) — beta6 → rc, method: full-file sweep

Same recipe as #401 §2: every `*.swiftinterface` under `System/Library/Frameworks` +
`usr/lib/swift` in the beta6 iOS SDK compared byte-for-byte against the rc's, then
non-identical files re-diffed with the `// swift-compiler-version:` and
`// swift-module-flags:` lines excluded. The recipe is now a committed script,
`scripts/mac/sdk-interface-diff.sh <outdir>` (`OLD_SDK` / `NEW_SDK` env override the
beta6→rc defaults), so the next toolchain's audit is one command. Run twice — device SDK
and simulator SDK — as a parity control.

**Device SDK (`iPhoneOS27.0.sdk`): 280 common interfaces · 11 byte-identical · 264
version-stamp-only · 5 real · 11 added · 0 removed. Framework inventory identical
(312 → 312).** The "identical" count collapsed from #401's 186 because every module's
flags line now carries `-target-arch-variant arm64e.x1` (Apple's new Hardware-Checked
Pointer Arithmetic slice — Enhanced Security notes, 152104701); the 11 *added*
interfaces are exactly that: a new `arm64e.x1-apple-ios` slice for the stdlib modules
(`Swift`, `_Concurrency`, `Observation`, `Synchronization`, `Distributed`,
`RegexBuilder`, `_StringProcessing`, `_Volatile`, `_Builtin_float`,
`SwiftOnoneSupport`, `hvf`). Not an API change; nothing to adopt.

**Simulator SDK (`iPhoneSimulator27.0.sdk`): 516 common · 492 identical · 16 stamp-only
· 8 real · 0 added · 0 removed** — the same four modules × two slices (Cinematic has no
sim slice), which is the parity the control was for.

The 5 real changes, each read in full — **all additive, none on surface Talaria calls**
(repo grep per symbol, with a positive control that `import SwiftUI` hits 109 files):

| module | change | Talaria use |
|---|---|---|
| `Cinematic` | New `CNAssetPreprocessConfiguration`, `CNAssetInfo.cinematicCapability(for:)` / `resourceStatus` / `downloadResources` / `preprocessAsset`; three `encodeRender` overloads move to `CVReadOnlyPixelBuffer` (old ones deprecated 27.0) | none (`import Cinematic`: 0 files) |
| `CoreMedia` | `CMClock.StartTimePattern` + `nextPreferredStartTimePattern()`, `implementsPreferredStartTimePattern`, `preferredStartTimeNotAvailable` error | none (`CMClock`: 0) |
| `Photos` | New `PHReferenceImageInfo` (fileURL / asset init, `imageContainsReferenceImageData`) | `import Photos` in 4 files (attachment/voice pickers, markdown view, LiveMediaService) — none touches the new type |
| `_PhotosUI_SwiftUI` | New `View.photosReferenceImageViewer(…)` in four flavours (asset / pickerItem / pickerResult / fileURL) | `PhotosPicker` in 2 files; new modifier unused |
| `AVFoundation` (overlay) | `AVCaptureDevice.Format.recommendedLensApertureStops` | `AVCaptureDevice` in 3 files; property unused |

**441-C verdict: NO API Talaria calls changed.** `FoundationModels`,
`_Vision_FoundationModels`, `_FoundationModels_SwiftUI`, `_FoundationModels_UIKit`,
`_CoreSpotlight_FoundationModels` are all version-stamp-only (their module-flags line
gained the arch-variant flag and nothing else) — the #324 FM checklist
(ToolCallingMode, DynamicProfile, tokenCount, LanguageModel protocol, LanguageModelError
arms, @Generable, UnavailableReason, PCC accessors) and `SystemLanguageModel.variant`
sit in an unchanged interface. SwiftUI, SwiftData, EventKit, Speech, AVFAudio,
WidgetKit, HealthKit, CoreMotion, Contacts, ActivityKit, AppIntents, Vision: stamp-only.
Two specific "did the SDK finally ship it?" checks, both **no change**: AVFAudio still
ships no refined-for-Swift overlay for `installTapOnBus:` (0 hits in both SDKs — the
`__installTap` spelling in `TalkSessionRules.swift:256` stays); AppIntents'
`LongRunningIntent` / `CancellableIntent` / `ProgressReportingIntent` are present in
the RC interface at the same counts as beta6 (2 / 3 / 3), so #56's
`TALARIA_IOS27_INTENTS` adoption is now verifiable against a **final** SDK — a lane,
not a tonight.

**There is no new-in-24A430 API to adopt.** The dyld rule (#324) is moot for this SDK
in the safe direction: the RC SDK adds nothing the app references, and the phone is
taking the RC tonight.

## 3. What the release notes say (441-E — Apple's pages, fetched 2026-09-09)

Sources: Apple's JSON docs backend for
[Xcode 27 RC Release Notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes)
and [iOS & iPadOS 27 RC Release Notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes)
(the HTML pages are JS-rendered and fetch empty). **Attribution caveat, unchanged from
#401: both pages are cumulative for the 27 cycle** — a "Resolved" item proves the fix is
in the RC, not that the RC introduced it. The SDK diff is the instrument for "new since
beta6"; the notes are the instrument for runtime behaviour.

### Foundation Models — the SAME six resolved items as beta 7, nothing new for the RC

`Private Cloud Compute might not work when you use simulators` (177684296) ·
`excessive tool calls with tool calling + guided generation` (177748926) · `@Generable`
enum deprecation warning (177899620) · two `onPrompt` fixes (177901494, 177902488) ·
`PrivateCloudComputeLanguageModel always uses greedy decoding` (178181782). No RC-only FM
resolution, no FM known issue. So the FM behaviour the phone gets tonight is, by Apple's
account, the beta-7 behaviour — the 398-B re-measure still owes its runtime stamp, and
the "sim can't generate" question is answered by measurement in §4, not by these notes.

### Likely to matter to Talaria (iOS 27 RC page)

- **System Stability — "Devices might freeze or panic when idle" FIXED (178343305).**
  Worth knowing before any overnight battery run on the phone: an idle-panic on the
  earlier betas would have read as a dead instrument.
- **Core AI (unchanged from beta 7):** background Neural Engine access restricted; new
  entitlement `com.apple.developer.background-tasks.continued-processing.inference` for
  background inference. Talaria generates in the foreground; a constraint to remember.
- **App Intents:** `AppEntity` instances now have a cumulative **10 MB** size limit
  (181763422 — "your app might crash if an entity exceeds this limit"); Siri's
  `OpenIntent` / `system.open` routing fix (177992979); `calendar.deleteEvents` schema
  renamed `calendar.deleteEvent` (176751155). Talaria's entities are small; the schema
  rename touches no repo code (grep: 0).
- **SwiftUI (cumulative, already in effect on our SDK):** `TabView` now **crashes** when
  selection is set to a hidden/unavailable tab (164516837); `controlSize` and sibling
  environment values reset inside sheets/popovers (167448274); selectable `Text` uses the
  system selection UI (5+ files use `textSelection(.enabled)`); `AsyncImage` HTTP caching
  (MarkdownContentView); the macro-based `@State` (source-compatible here — 0 errors);
  `toolbarMinimizationBehavior` replaces `toolbarMinimizeBehavior` (repo: 0 uses of
  either). `TextField` `.roundedBorder` style is *soft*-deprecated for `.bordered`.
- **UIKit (cumulative conformance, re-checked):** launch screen required on 27-SDK
  submissions — conforms (`UILaunchScreen` in `project.yml`); scene-based lifecycle
  required — conforms; `canOpenURL:` deprecated — 0 repo uses.
- **HealthKit:** the new permissions flow lets users grant *limited history* vs *full
  history* (172310874) — `DeviceHealthTool`'s per-read `requestAuthorization()` should
  expect a limited-history grant as a valid outcome, not a denial. Device-only to observe.
- **Dictation:** the "Advanced Dictation Preview" toggle and the phantom-trailing-words
  fix are the *keyboard* path (unchanged from beta 7; see #401 §3 for the #396 caveat).
- **Writing Tools known issue (177097101):** unresponsive after the Plus button while in
  use (Messages) — different surface from the composer's `.writingToolsBehavior(.complete)`
  developer flag, but the same subsystem is still shipping known-broken in the RC.
- **Reminders / Siri:** recurring-reminder creation via Siri fixed (177722240); reminder
  list-name fuzziness fixed (176400964) — Siri-side, not EventKit; no app change.
- **WidgetKit:** `@UnionValue` intent parameter rendering fix (177493357) — Talaria's
  widget intents use no `@UnionValue`.

### Xcode 27 RC tooling notes worth keeping

- **Simulator runtimes now ship a pre-built dyld cache** — first boot is much faster
  (179846743). `simctl reboot` exists (172303413). Known issue: removed runtimes can
  **re-appear after a reboot** (141290052) — relevant if anyone prunes the four iOS 27.0
  runtime images.
- **Testing:** Swift Testing now associates issues recorded on detached tasks / dispatch
  queues / background threads with the right test (169036231) — our classifier keys on
  the `recorded an issue at File.swift:LINE:COL:` shape, which is unchanged;
  cross-framework assertion misuse now surfaces as a warning-severity runtime issue
  (170335449); new **`XCUIVoiceOverService`** UI-testing API (175858549); test plans can
  set target-crash severity for UI tests (168107814).
- **devicectl JSON v5** deprecates `hardwareProperties` / `deviceProperties` /
  `connectionProperties` (183772705) — repo scripts parse none of them (grep: 0).
- **Swift dependency scanner** now errors on duplicate Clang module names across module
  maps (136303612) — no vendored module maps in this repo; the gate compile is the proof.
- **Foundation Models Instrument** in Instruments (164223804) — traces instructions,
  prompts, responses, token usage. A device-side instrument for #335's family.
- The beta-6-era MCP-server preview (`sudo xcrun mcp-server enable`), lldb-mcp, and the
  Preview Snapshot MCP variants are still "preview" in the RC.
- The RC notes list **no** signing / distribution / archive / TestFlight changes. #166's
  earlier finding stands: App Store *submission* needs this RC/GM Xcode, and this is it.

## 4. Known-trap ledger (441-D) — honest status against 24A434

The #402 probe was re-run on the RC runtime by its own one-command recipe (copy into
`TalariaTests/`, `xcodegen generate`, `-only-testing:TalariaTests/PCCSimProbeTests`, then
delete + regenerate — `project.pbxproj` byte-identical to HEAD afterwards, verified).
Three arms, 3/3 "passed" (the probe records, it does not judge), runtime stamped
in-process: `runtime_build=24A434 device=iPhone18,4`.

| trap | status this round |
|---|---|
| **PCC-on-sim (#402)** | **RE-TESTED — identical to 24A5423a, line for line.** `availability=available`, `isAvailable=true`, `quotaUsage=belowLimit(isApproachingLimit: false)`, **`contextSize=32768`**, `supportedLanguages.count=24`; `respond()` **THREW in 0.07 s** with `domain=FoundationModels.SystemLanguageModel.Error code=0 "The assets required for the session are unavailable"`; the no-instructions arm fails identically. The metadata plane works, generation does not, and no RC change moved it. `pccGrantConfirmed` and the DEBUG-sim metadata carve-out both keep their exact justification. |
| **FM on-device generation on sim (#324)** | **RE-TESTED — still dead.** `SystemLanguageModel.default`: available, variant **"AFM 3 Core"**, **`contextSize=0`**, `respond()` → `FoundationModels.LanguageModelError code=-1` — the beta5 un-bridged signature, unchanged through three runtimes. Corroborated by the gate's own suite log: 3,606 `UnifiedAssetFramework Code=5000 "no underlying assets … com.apple.modelcatalog"` lines and 2,218 `ModelManagerError` lines on 24A434. Every "structure only, because the simulator cannot generate" test pin stays; the `+Preflight` sim error-row branch stays. |
| SwiftData `mainContext` SIGTRAP (324-W1) | **NOT RE-TESTED; status stays UNKNOWN.** No probe exists (the beta5 null result was a scratch artifact); the RC notes' SwiftData fix (178113288) is the beta-7 deadlock, a different signature. Private-context pattern stays — and is defensible on its own. |
| #301-family isolation trap (MainActor-formed completion on a framework queue) | **NOT RE-TESTED.** Probe gone since #324; nothing in the RC notes claims it. All `@Sendable` fixes stay — they are correct Swift 6 code regardless. |
| #438 host-mic hang | **Environmental status: clear this run** — phone not corded (USB scan 0 iPhones at launch), the six capture rows ran green. Not a runtime finding; the lane-shaped fix (tests should not depend on the host's input device) is still #438's. |
| Dropped synthesized taps on the iOS 27 sim (the `HittableTap` retry loop) | **One data point, not a verdict:** 18/18 XCUITest green, no retry logged. The loop stays until a bundle-warm repeat run says otherwise. |

**No "probably fixed" verdict exists in this table.** A trap not re-tested keeps its
workaround unconditionally.

### Code-level inventory of beta-pinned workarounds (read-only sweep, 2026-09-09)

Formal skip APIs are unused repo-wide (`withKnownIssue` 0, `XCTSkip` 0,
`XCTExpectFailure` 0, `.disabled(` 0, no `FB` ids); every beta compensation is a
`#if targetEnvironment(simulator)` branch or a comment-gated pattern. Rows that hinge on
tonight's measurements are marked; the rest keep regardless.

| site | compensates for | tonight's verdict |
|---|---|---|
| `SwiftDataLocalSessionStore.swift:99`, `MemoryStore.swift:93` — private `ModelContext`, never `mainContext` | 324-W1 SIGTRAP (status UNKNOWN since beta5's null probe) | NOT RE-TESTED; keep regardless (defensible pattern) |
| `NativeVoicePipelineService.swift:1159` `@Sendable` completion (#301) | isolation trap on framework queues | keep regardless — correct Swift 6 code |
| `TalkSessionRules.swift:256` `__installTap` spelling | AVFAudio ships no refined overlay | **still true on the RC SDK** (0 hits) — keep |
| `ChatInputBar.swift:276` + `UserSettings.swift:303` `.writingToolsBehavior(.complete)` behind an off-by-default developer flag | beta-2 device freeze | device-only; NOT RE-TESTED (no device tonight); Writing Tools still carries an RC known issue |
| `ChatScreen.swift:181` Release path skips the empty `safeAreaInset` | beta-4 layout collapse | NOT RE-TESTED; keep |
| `LocalChatBackend.swift:797` `pccGrantConfirmed` false on sim | structural (no entitlement in unsigned sim builds) | keep regardless |
| `LocalChatBackend.swift:839` DEBUG-sim PCC metadata carve-out | #402's measurement on 24A5423a | RE-TESTED — 24A434 gives the identical metadata plane (contextSize 32768, 24 languages), so the carve-out's premise holds; keep |
| `LocalChatBackend+Preflight.swift:298-500` sim "error row" branch (tokenCount throws, contextSize 0) | #324 / 324-W3 | RE-TESTED (arm 3): `contextSize=0` and `respond` → `LanguageModelError -1` on 24A434 — the error-row branch is still the sim's reality; keep |
| `LocalChatBackend+SurfaceProbe.swift:87` `dlopen` instead of `import` | #324 dyld launch death | keep; low priority to revisit |
| `InstrumentRegistry.swift:687-690` "every device on beta5" comment gate | beta4↔beta5 dyld | narrative only — removable once the fleet is on the RC/GA |
| `AskHermesLongRunSupport.swift` whole file behind `TALARIA_IOS27_INTENTS` (#56) | written blind against WWDC26-345 | SDK symbols present and now final — a lane, not tonight |
| ~20 test sites pinning structure only "because the simulator cannot generate" (#324) | FM sim generation | RE-TESTED (arm 3): generation still dead on 24A434 — none can grow a real-generation assertion; all ~20 pins keep |
| `AppTemplateUITests.swift:308,648`, `HittableTap.swift:117` re-tap loop + frameless-root parser skip | dropped synthesized taps on the iOS 27 beta sim | 18/18 green with no retry logged on 24A434 — one data point; not a removal verdict, keep |
| `scripts/mac/*.sh` `DEVELOPER_DIR` defaults → beta6; `run-sweep.sh` `EXPECTED_OS` 24A5408d; `score-eras.py` era constants | toolchain / era pins | promotion edits (441-F) if Owen elects; `run-sweep.sh` + `score-eras.py` untouched per #401's precedent |

## 5. Hazards / look-out-for

1. **The device build after the RC install is UNMEASURED.** The last measured build is
   `24A5430a` (2026-09-06); tonight's install moves the phone to whatever Apple's iOS 27
   RC build is, and the sim's `24A434` may lead or trail it — do not guess which. The
   number comes free from the next instrument artifact's `osVersion` field (398-A's
   route); until then every rate carries "24A434 (sim)" and nothing else.
2. **The RC's sim runtime is not the RC's SDK build** — `24A434` runtime vs `24A430` SDK,
   the first time one Xcode has shipped two different builds. The gate prints the
   runtime it booted, which is the only reason this is visible.
3. **The CC-lane pool advanced silently — again.** CC-lane-1/3 already follow `24A434`;
   CC-lane-2 is still booted on `24A5423a` from an earlier lane and will jump on its
   next boot. A runtime A/B against beta 7 behaviour needs
   `simctl runtime match set iphoneos27.0 24A5423a` (and `--default` after), and the RC
   notes warn that a *removed* runtime can re-appear after a reboot (141290052).
4. **There is no beta5 toolchain any more.** `Xcode-beta5.app` is gone; the only A/B
   against the RC is beta6. If the RC is promoted, beta6 becomes the fallback and the
   fleet has exactly two iOS-27-capable Xcodes.
5. **The `hermes update` on both hosts (same night) did not lose the gateway-side
   plugin** — both gateways restarted after their updates and both wire-prove the
   talaria handler (#442). The unexplained part is which *pane* showed it missing.
6. **RC-cumulative behaviour that touches shipped code:** `TabView` now crashes on a
   hidden selection (164516837); `controlSize`-family environment resets inside sheets
   (167448274); HealthKit's limited-history grant is a new valid outcome for
   `DeviceHealthTool`'s per-read authorization (172310874); `AppEntity` 10 MB cap
   (181763422). None showed in the suite; all are device/behaviour-side to watch.
7. **Idle freeze/panic fixed in the RC (178343305)** — an overnight device battery on the
   earlier betas could have died to this and read as instrument death; on the RC it
   cannot be blamed.

## 6. Promotion recommendation (441-F)

**The gate is green first-run, the SDK is additive-only, and this is the Xcode an App
Store submission requires (#166's finding) — recommendation: PROMOTE `Xcode-rc` to the
standard toolchain, with `Xcode-beta6` as the A/B fallback** (beta5 is already gone,
so "keep one fallback" is beta6 by default). Edits if elected: CLAUDE.md + AGENTS.md
toolchain sections; the `DEVELOPER_DIR` defaults in `lane-gate.sh`, `ota-stage.sh`,
`preota-subset.sh`, `run-instrument.sh`, `ui-bundle-batch.sh` and the *hardcoded* one
in `testflight-stage.sh`; README, CONTRIBUTING, MAINTAINER_NOTES posture (3426 / 281 +
18 on 24A434). Deliberately untouched, per #401's precedent: `run-sweep.sh`'s
`EXPECTED_OS` era pin (#343 comparability armor — the next sweep owner moves it
knowingly), `score-eras.py` (era labels are its subject matter), historical
planning/dispatch docs. **Owen decides** — no promotion edits are made in this commit;
the arrival-falsified lines (beta5 gone, newest runtime, device build) are corrected
regardless, because they are wrong whichever toolchain is standard.
