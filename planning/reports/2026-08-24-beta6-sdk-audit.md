# iOS 27 Beta 7 / Xcode 27 Beta 6 — regression round + SDK audit

**Run 2026-08-24, tracker #401.** Owen's ask: *"start a quick round of regression testing
for the new version, and check and see if any new features were added? Or anything to look
out for / may have been resolved by this version."* Bars 401-A..E pre-registered in
`OPEN_ITEMS.md` (commit `f5c7a473`) before any run. Naming care throughout: **Apple's
"Xcode 27 beta 6" ships the iOS 27 *beta 7* SDK and sim runtime**; the phone's `24A5418b`
is iOS beta 6. The two "beta 6"s are different axes — builds, not ordinals, are quoted
where it matters.

## Executive summary

**Beta 6 (Xcode) / beta 7 (iOS) is a safe, boring update for Talaria — GATE: PASS** on
the first run, no re-runs: TEST SUCCEEDED with **2482 Swift Testing tests + 14 XCUITest**
on the 24A5423a sim runtime (verified from the booted device), Release build clean, zero
Swift compile errors under swiftlang 6.4.0.33.1, and the only skips are the
known-permanent CondenserFidelityTests pair. One pre-registered clause of 401-A **missed
as written** — the ≥ 2497 unit floor — and the miss is a bar-formation error, measured
exactly (§1), not a regression: PR #360's transport deletion removed a net 15 tests after
the floor's baseline was recorded.

The SDK is a polish release: of **280 swiftinterfaces** in the iOS SDK, 186 are
byte-identical to beta5's, 88 differ only in the `-user-module-version` stamp, and **6
have real changes — none on surface Talaria calls**. FoundationModels' interface is
**byte-identical**. The interesting movement is all in the *runtime* release notes: an FM
fix for **excessive tool calling** (the #215 over-serving family), **PCC now works on
simulators**, and **PCC greedy decoding fixed** — all of which land on the phone when it
takes iOS beta 7. New hazard: the sim runtime now **leapfrogs** the device, and the beta6
Xcode's SDK is beta-7-vintage, so new-SDK API adoption is dyld-blocked until the phone
updates (#324's rule, third arrow).

| Toolchain | Xcode build | swiftlang | iOS SDK | iOS 27.0 sim runtime |
|---|---|---|---|---|
| beta5 (current std) | 27A5237l | 6.4.0.30.4 | 24A5408c | 24A5408d |
| **beta6 (new)** | **27A5252f** | **6.4.0.33.1** | **24A5422a** | **24A5423a** |
| device `whoGoesThere` | — | — | — | 24A5418b (iOS beta 6) |

First-launch/license complete on arrival (`xcodebuild -checkFirstLaunchStatus` exit 0, no
sudo). Runtimes on disk: 24A5423a + 24A5408d + 24A5390f + 26.5 23F77 (30.3 GB).
`simctl runtime match` chooses 24A5423a for new iOS 27.0 boots with no user override —
so the CC-lane pool silently advanced to the new runtime, which is what this round wanted
and what 398-C warns about for every future round.

## 1. Regressions (401-A) — none found; one bar clause missed as written

Full `lane-gate.sh` (Debug suite + Release build),
`DEVELOPER_DIR=/Applications/Xcode-beta6.app/Contents/Developer`,
`TALARIA_SIM_NAME=CC-lane-1`, no concurrent builds. Preflight all PASS, including the
in-gate TCC grant and the classifier self-test (15 checks).

- **GATE: PASS, first run.** xcodebuild exit 0 · `TEST SUCCEEDED` · **2482 Swift Testing
  tests** · **14/14 XCUITest** · Release build succeeded, 0 Swift compile errors. Skips:
  exactly the 2 known-permanent CondenserFidelityTests (Apple Intelligence hardware) —
  no unexplained skip.
- **Booted runtime VERIFIED from the device itself**, per the bar: `simctl getenv
  SIMULATOR_RUNTIME_BUILD_VERSION` on booted CC-lane-1 → **24A5423a** (not inferred from
  match policy).
- **The ≥ 2497 unit-count clause MISSED as written** (2482 < 2497), and per the standing
  rule that is a falsification to record, not a floor to quietly rewrite. **Root cause is
  the bar's formation, measured, not argued:** the floor was pinned to #393's 2026-08-23
  gate, whose tree predates PR #360 (#382's sessions-transport deletion, squash
  `5f50e498`, merged later that same night). `git diff c8341df5..HEAD` over the test
  targets removes **29 `@Test` functions and adds 14 — net −15, exactly the 2497→2482
  delta** — concentrated in the files that deletion gutted (ReasoningChannelTests −295
  lines, StreamLossClassificationTests −258, ArtifactStreamingTests −196,
  SessionModelImmunityTests −114). So 2482 is the complete suite at HEAD; nothing
  silently failed to run, and no beta5 control run is owed because the delta is fully
  attributed by content, not by toolchain. **Correctly-formed floor for future gates:
  2482 + 14 at HEAD `f5c7a473`.** Lesson for the next bar-writer: a count floor must be
  pinned to the HEAD being gated, not to the most recent gate's number.
- The SE-0508 source break does not bite: zero compile errors across 571 compile steps
  under the new compiler (and the repo has no hand-written init accessors).

## 2. SDK surface diff (401-B) — beta5 → beta6, method: full-file sweep

Every `*.swiftinterface` under `System/Library/Frameworks` + `usr/lib/swift` in the beta5
iOS SDK compared byte-for-byte against beta6's, then non-identical files re-diffed with
the `// swift-module-flags:` line excluded to separate version-stamp churn from real
change. (First attempt matched on `arm64-apple-ios.swiftinterface` and found **zero
files** — the slices are `arm64e-apple-ios` — a live rehearsal of the empty-result trap;
the impossible `total=0` is what caught it.)

**Totals: 280 interfaces · 186 byte-identical · 88 version-stamp-only · 6 real · 0 added
· 0 removed.** Framework inventory identical (no frameworks added or removed);
`_Vision_FoundationModels` is among the byte-identical (it is a framework at
`System/Library/Frameworks`, not a usr/lib/swift overlay).

The 6 real changes, each read in full — **none is surface Talaria uses** (verified by
repo grep, empty on all six):

| module | change |
|---|---|
| `_Concurrency` | `withUnsafeCurrentTask` nonsending overload ABI refactor (`…Nonsending` → `…NonsendingExportedImpl`, body now emitted inline `@export(implementation)`, `__abi_` compat shim added). Same public name; source-compatible. |
| `UIKit` | `shouldReplace(foundTextRange:document:withText:)` parameter type fixed `AnyHashable??` → `UITextView.DocumentIdentifier?` (find-and-replace adopter API). |
| `CryptoKit` | **Removed** pre-GM `Insecure.UnauthenticatedAES.permute/inversePermute` and `Insecure.UnauthenticatedChaCha20.encrypt` — new-in-27 API pulled before release. |
| `NowPlaying` | Removed `collectionID`/`serviceID` members; added `AnimatedArtwork.compatibleAspectRatios`. |
| `_DataDetection_SwiftUI` | Availability narrowed: macOS/macCatalyst now unavailable. |
| `VideoToolbox` | Formatting-only re-emission (`supportedScaleFactors` same declaration, re-wrapped). |

**401-C verdict: NO API Talaria calls changed.** The #324 FM checklist (ToolCallingMode,
DynamicProfile, tokenCount, LanguageModel protocol, LanguageModelError arms, @Generable,
UnavailableReason, PCC accessors) sits in a byte-identical FoundationModels interface;
`SystemLanguageModel.variant` (adopted since #324) likewise. SwiftUI, SwiftData, EventKit,
Speech, AVFAudio, WidgetKit, HealthKit, CoreMotion, Contacts, ActivityKit, AppIntents,
Vision: byte-identical or version-stamp-only. **There is no new beta6-SDK API to adopt —
which also means the dyld adoption freeze (below) currently costs nothing.**

## 3. What the release notes say (grounded in Apple's pages, fetched 2026-08-24)

Sources: Apple's rolling pages, fetched via their JSON backend the same day —
[Xcode 27 Beta 6 Release Notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes)
and [iOS & iPadOS 27 Beta 7 Release Notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes).
**Attribution caveat: both pages are cumulative for the 27 cycle** — a "Resolved" item
proves the fix is in beta 7, not that beta 7 introduced it. The SDK diff above is the
precise instrument for "new since beta 5"; the notes are the instrument for runtime
behavior, which an interface diff cannot see.

### Likely to matter to Talaria

- **FM: "using the on-device Apple Foundation Model for both tool calling and guided
  generation, some prompts might cause the model to call tools excessively" — FIXED
  (177748926).** That is the #215 over-serving family's exact configuration (Talaria uses
  tool calling + guided generation together). When the phone takes beta 7, tool-chaining
  rates measured on earlier runtimes describe a runtime that no longer exists — one more
  reason 398-B's re-measure must record its runtime.
- **FM: "Private Cloud Compute might not work when you use simulators" — FIXED
  (177684296).** If real, the PCC tier (#395) becomes sim-testable for the first time —
  every PCC observation so far has been device-only. Elective follow-up probe filed in
  #401; not verified this round.
- **FM: "PrivateCloudComputeLanguageModel always uses greedy decoding" — FIXED
  (178181782).** PCC outputs gain sampling variance; any PCC behavioral baseline
  (#388/#391/#395-era) was measured under greedy decoding.
- **FM: @Generable enum deprecation-warning fix; onPrompt/Profile fixes** — the
  @Generable warning fix may quiet build noise; onPrompt is unused here.
- **SwiftData: deadlock fixed for @Query when saving a ModelContext on a background actor
  while scheduling ModelActor tasks (178113288).** Adjacent to, but NOT, our mainContext
  trap (ours is a SIGTRAP on mainContext fetches from MainActor Tasks; status UNKNOWN per
  324-W1). No workaround is dropped.
- **Dictation: new on-device model behind Settings → Keyboard → Dictation → "Advanced
  Dictation Preview" (178444388)**, plus fixes for spoken-punctuation doubling, contact
  names, and phantom trailing words. This is the *keyboard* dictation path (composer
  typing), not the app's own Speech pipeline — but if Owen flips that toggle, keyboard
  dictation behavior baselines shift, and the phantom-trailing-words fix is the same
  *symptom family* as #396's over-capture (different mechanism — do not conflate).
- **Core AI / Neural Engine: background NE access now restricted** (like GPU), new
  entitlement `com.apple.developer.background-tasks.continued-processing.inference` for
  background inference; NE memory now attributed to the app process in Allocations.
  Talaria generates in the foreground today; this is a constraint to remember if
  background brain work is ever proposed.
- **Core Spotlight known issue:** `SpotlightSearchTool` default configuration exceeds the
  on-device model's context window when used with an on-device `LanguageModelSession`
  (workaround: `.focused(…)` guides). Not used by Talaria; worth knowing as an
  FM-ecosystem gotcha.
- **UIKit (cumulative 27-SDK conformance, checked this round):** launch screen required
  on 27-SDK App Store submissions — **Talaria conforms** (`UILaunchScreen` +
  `INFOPLIST_KEY_UILaunchScreen_Generation` in `project.yml`); scene-based lifecycle
  required — conforms (SwiftUI App lifecycle, `UIApplicationSceneManifest` present);
  `canOpenURL` newly deprecated — zero repo uses.
- **SwiftUI behavior notes that touch existing code** (cumulative, already in effect on
  the SDK we ship with): selectable `Text` (`textSelection(.enabled)`, 5+ files) now uses
  system selection UI with additional gestures — custom gestures on those views should
  move to `.highPriorityGesture` if they ever conflict; `AsyncImage`
  (MarkdownParser/MarkdownContentView) now auto-caches per HTTP headers, with new
  `URLRequest`/session initializers to control it; the new macro-based `@State` is
  source-compatible with our usage (no init-accessor patterns in repo, gate compile
  confirms).
- **Swift 6.4 / SE-0508 source break (Xcode notes):** a computed property with an init
  accessor plus array/dictionary-literal initial value no longer compiles when the getter
  precedes the init accessor. Repo has no hand-written init accessors; macro-generated
  ones are regenerated by the current compiler. Gate compile is the proof.

### Xcode 27 beta 6 tooling notes worth keeping

- **Parallel-testing stdout/stderr streaming can be significantly delayed (165098287)** —
  affects live log *polling* of test runs, not final verdicts; the gate parses the
  finished log.
- **`devicectl` JSON v5 deprecates `hardwareProperties`/`deviceProperties`/
  `connectionProperties`** (use `properties`); `--filter`/`--sort-by`/`--columns` fixes.
  Repo scripts that parse devicectl JSON should migrate keys before the removal lands.
- **Simulator fix:** black wallpaper / blank icons on first boot fixed; sims for pre-18
  OSes accept keyboard/mouse again.
- **Beta5-era MCP preview** (`sudo xcrun mcp-server enable`) — Xcode's MCP server can now
  run without an open workspace; possibly interesting for the Xcode-bridge workflows some
  future day, not this round.
- Requires macOS Tahoe 26.4+ — this Mac is on 26.5.2. ✅

## 4. Known-trap ledger (401-D) — honest status against 24A5423a

| trap | status this round |
|---|---|
| #301-family dynamic actor-isolation trap (MainActor-formed completion on a framework's private queue) | **NOT RE-TESTED.** #324's probe was a session-scratchpad artifact and is gone; rebuilding it is a scoped follow-up. All `@Sendable` fixes stay unconditionally. Nothing in the notes claims this fixed. |
| SwiftData `mainContext` SIGTRAP (324-W1) | **NOT RE-TESTED; status stays UNKNOWN.** The beta-7 SwiftData deadlock fix (178113288) is a different signature. Private-context workaround stays. |
| FM generation on simulator | **NOT RE-TESTED** (probe gone, same as above). No release note claims sim *on-device* generation works; the PCC-on-sim fix is a different tier. Verification posture unchanged: on-device generation/tokenCount behavior remains device-only — but the **PCC tier may now be sim-testable** (elective probe, see #401). |

## 5. Hazards / look-out-for (the user's third question)

1. **The runtime skew FLIPPED, then CLOSED the same day (#398).** At audit time the sim
   (24A5423a) leapfrogged the device (24A5418b). Hours later Owen upgraded the phone to
   iOS 27 beta 7 — **the fleet is aligned for the first time since beta 5** (exact device
   build string unmeasured until the next device log pass; Owen's word settles the
   ordinal). The FM tool-calling fix arrives with the update, so over-serving numbers
   must be re-measured after, not across, it (398-B).
2. **Dyld adoption freeze: LIFTED same day.** While the phone was on 24A5418b, any
   new-in-24A5422a symbol would have strong-linked and died at launch (#324's proven
   rule). With the phone on beta 7 the freeze is gone — though the diff found nothing
   worth adopting anyway.
3. **The CC-lane pool silently advanced runtimes.** `runtime match` now boots 27.0 sims
   on 24A5423a with no one deciding it. This round wanted that; a future A/B against
   beta5 behavior needs `simctl runtime match set iphoneos27.0 24A5408d` (and ALWAYS
   `match set iphoneos27.0 --default` after) — same lever as #324's A/B.
4. **idb note:** #324's finding (SimulatorKit moved; spawn companion with release-Xcode
   `DEVELOPER_DIR`) presumed unchanged under beta6 — not re-probed this round.

## 6. Promotion recommendation (401-E)

**The gate is green, so the recommendation is: PROMOTE beta6 to standard toolchain** —
CLAUDE.md toolchain section, `lane-gate.sh` + `ota-stage.sh` `DEVELOPER_DIR` defaults,
README/CONTRIBUTING mentions — keeping **beta5 on disk as the A/B fallback** (the beta4
deletion left no fallback last time; keep one this time) and the 24A5408d runtime for
runtime A/Bs. The case is stronger than #324's was: the SDK surface is near-identical,
the gate passed first-run, and the device is already on the matching iOS beta 7 (upgraded
the same day), so builds, sims, and the phone would all sit on one vintage. **Owen
decides** — #324's "auto-promote if green" was a per-instance pre-bed authorization and
does not carry; no promotion edits are made in this commit.

**⟵ EXECUTED same day on Owen's word** (*"Yes, promote it, keep beta5 as the fallback for
now"*): CLAUDE.md + AGENTS.md toolchain sections, `lane-gate.sh` / `ota-stage.sh` /
`run-instrument.sh` `DEVELOPER_DIR` defaults, README, CONTRIBUTING, and
MAINTAINER_NOTES' test posture (2482 tests / 200 suites + 14 XCUITest) all point at
beta6; beta5 stays on disk as the A/B fallback. Deliberately untouched:
`run-sweep.sh` (its 24A5408d precondition is #343-era comparability armor — the next
sweep owner moves that pin knowingly or the preflight rightly refuses), historical
planning/dispatch docs (per #324's precedent), and `score-eras.py` (era labels are its
subject matter).
