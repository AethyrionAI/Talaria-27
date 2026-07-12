# FABLE LANE J — iPad Support (Universal Target → Native Split View)

**Repo:** `AethyrionAI/Talaria-27` · **Branch prefix:** `claude/t27-lane-j-*`
**Dispatch date:** 2026-07-12 · **Supersedes:** nothing (new lane)
**Delivery:** TWO PRs, in order. PR 1 must be independently mergeable and leave
iPhone behavior pixel-identical. PR 2 builds on PR 1.

---

## Mission

Make Talaria a universal app that is genuinely good on iPad — not a stretched
iPhone app. Target hardware: iPad Air (M3), iPadOS 27 beta. M3 is Apple
Intelligence-capable, so the on-device brain path (FoundationModels) is fully
live on this device — do not gate it off.

**Phase 1 (PR 1):** universal target, arbitrary-window-size survival, hardware
keyboard shortcuts, pointer polish. No navigation restructure. Green baseline
on iPad.

**Phase 2 (PR 2):** `NavigationSplitView` native layout — persistent sidebar
(conversation list, including the landed Lane F search/pin/archive surfaces) +
chat detail in regular width; automatic collapse to today's stack navigation in
compact width.

---

## Non-negotiable constraints (house rules)

- **iPhone is sacred.** In compact size class the app must be byte-for-byte
  behaviorally identical to current main. Pattern precedent: the Deep Field
  pixel-identity bar from the theme work. Add a guard test where feasible.
- **Size classes, not device idiom.** Never branch on
  `UIDevice.userInterfaceIdiom` for layout. iPadOS 26+ windows are freely
  resizable (`UIRequiresFullScreen` is ignored); an iPad window can be
  iPhone-narrow (Slide Over) and must get the compact layout. Idiom checks are
  permitted ONLY for capability facts (e.g. keyboard-shortcut registration).
- **Real data only.** No mock/demo content on new surfaces; `—` for unknowns.
- **File-scoped commits.** `pbxproj`/scheme regen in its own commit. No
  `OPEN_ITEMS.md` edits in feature commits.
- **xcodegen:** any file add/remove → `xcodegen generate` on the Mac side.
  After EVERY regen, verify `aps-environment: development` survived in
  `Talaria/Talaria.entitlements`, plus the WeatherKit and CarPlay keys
  (standing #44/#48 trap).
- **Cloud can't build.** Author for the Mac review-then-build loop
  (`DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`). Note any
  API you could not compile-verify.
- **Tests:** Swift Testing (`@Test`) for new logic, matching repo convention.

---

## PR 1 — Universal target + adaptive foundation

### J-1. Target configuration (`project.yml`)

- `TARGETED_DEVICE_FAMILY: "1,2"` on the app target AND `TalariaWidgets`.
- Info.plist additions: `UISupportedInterfaceOrientations~ipad` = all four.
- Deployment target stays iOS/iPadOS 27.
- Regen + commit `pbxproj`/scheme file-scoped; entitlements survival check.

### J-2. Multi-window decision (explicit, not accidental)

`UIApplicationSupportsMultipleScenes: true` is already in the manifest for
CarPlay. On iPad this exposes "New Window" / Stage Manager multi-window
whether we like it or not.

**Decision for this lane: SINGLE app window.** The store layer
(`ChatStore`/`AppContainer`) was never audited for concurrent scene
observation, and multi-window is not worth that audit yet. Implement the
narrowest mechanism that (a) keeps the CarPlay scene functional and (b)
prevents a second chat window (scene-delegate/session refusal or equivalent —
document the mechanism chosen in the PR). File a follow-up OPEN_ITEMS
candidate for true multi-window later.

### J-3. Arbitrary-size layout survival

Acceptance is a **resize sweep**, not an orientation pair: full screen (both
orientations), Split View 1/2 and 1/3, Slide Over, Stage Manager free resize.

- **Chat transcript readable-measure cap:** at regular width, cap message
  content width (target ~700pt, centered) so bubbles don't stretch to 1180pt
  lines. Bubbles keep their existing leading/trailing alignment within the
  measure.
- **Composer:** same cap; attachment strip and staged chips must not stretch
  full-bleed.
- **HUD header:** #75's `hudSingleLine` hardening should make wide widths
  trivial — verify, don't rebuild. Check the narrow extreme (Slide Over) too.
- **Sheets/popovers:** iPadOS renders sheets as centered cards/popovers.
  Sweep every sheet (settings, theme gallery, voice-memo review, attachment
  pickers, confirm dialogs) for anchoring and sizing sanity.
- **Theme atmosphere:** the Lane E motion engine (parallax starfield, embers,
  scanlines) must render full-bleed at 13" canvas sizes without seams or
  perf collapse, and must re-layout live during window resize. Orb placement
  re-anchors sanely. Reduce Motion gating unchanged.

### J-4. Hardware keyboard shortcuts

Registered via SwiftUI `.keyboardShortcut`/commands. Work on any connected
keyboard (iPad primary; harmless on iPhone):

- `⌘N` new conversation
- `⌘K` conversation search (Lane F surface — wire to the landed entry point)
- `Return` sends from composer; `⇧Return` inserts newline
- `Esc` dismisses topmost sheet/overlay
- `⌘,` opens Settings
- `⌘1…⌘9` jump to nth pinned/recent conversation IF cheap after F's data
  model; otherwise drop and note in PR — do not contort for it.

### J-5. Pointer polish

- `.hoverEffect` on tappable chrome (header buttons, chips, conversation rows,
  theme cards).
- Verify existing context menus trigger on secondary click.
- No custom cursor work beyond system hover effects.

### J-6. Sensor/voice reality pass (report, don't build)

- `SensorUploadService` on iPad: HealthKit exists on iPadOS but data is
  sparse; CoreMotion differs. Requirement: graceful degradation, honest `—`
  states, NO fake readings, and the #104 outbox behavior must not regress.
  If a capability probe is missing, add the minimal one.
- Talk/voice: attempt nothing new. Whether the iPadOS 27 beta shares the
  iPhone seed's third-party mic wedge (#82 successor) is a device-pass
  question, not a code question. Preflight (#84 lineage) already reports
  honestly — leave it.

### J-7. PR 1 tests + acceptance

- Tests: layout-decision logic (measure cap thresholds, shortcut
  registration table) where extractable; compact-parity guard if feasible.
- Build: app + widgets compile for iPad destination
  (`generic/platform=iOS Simulator`, then an iPad Air 13-inch (M3)-class
  iPadOS 27 sim — Mac session pins the concrete sim ID).
- Sim sweep: the J-3 resize matrix, dark/light, two themes (Deep Field +
  one Lane E complex theme), Dynamic Type spot check.

---

## PR 2 — Native split-view layout

### J-8. Navigation restructure

- Introduce `NavigationSplitView` at the root chat surface:
  - **Sidebar (regular width):** conversation list — the SAME list component
    Lane F ships (search field, pin section, archive access). Do not fork it;
    extract/reuse so F's surfaces exist exactly once.
  - **Detail:** `ChatScreen` for the selected conversation; sensible empty
    state ("no conversation selected") using real app chrome, no placeholder
    art.
  - **Compact:** `NavigationSplitView`'s automatic collapse must reproduce
    today's iPhone navigation flow exactly. If it can't be made identical,
    keep an explicit compact branch that renders the current stack untouched
    — parity beats purity.
- Settings remains a sheet (card presentation on iPad) — no sidebar tab
  architecture in this lane.
- Selection state lives in the store layer (observable), not view-local, so
  sidebar and detail can't desync.

### J-9. Split-view polish

- Sidebar toggle button per platform convention; state persists across
  launches.
- `⌘K` focuses the sidebar search field directly in regular width.
- Theme atmosphere spans the whole window (behind both columns), not
  per-column.
- Resize sweep from J-3 re-run: transitions across the compact/regular
  boundary (Stage Manager drag) must not lose composer text, scroll
  position, or in-flight streaming state. **Streaming across a size-class
  transition is the highest-risk case in this PR — test it explicitly.**

### J-10. PR 2 tests + acceptance

- Tests: selection-state model; compact-parity guard extended.
- Sim: full matrix again, plus mid-stream resize, plus voice-overlay
  presentation in both width classes.

---

## Collision surface

- Lane F: **landed on main** — reuse, don't fork, its conversation-list
  components. Rebase onto current main before starting.
- Lane D (PR #65 DO-NOT-MERGE) / #99: new-files-only, no contact expected.
- Lane H: generation/`streamResponse` layer — no layout contact expected,
  but PR 2 touches `ChatScreen`; if H has landed ChatScreen-adjacent guards
  by then, rebase before PR 2, not after.
- Lane G: relay-side Python — zero contact.

## Device verification prerequisites (Owen, not Fable)

1. Shelley's iPad Air (M3) on **iPadOS 27 beta** — hard requirement
   (deployment target). If it's on stable iPadOS 26, nothing installs.
2. Developer Mode enabled on the iPad; device registered in the provisioning
   profile / added to the dev cert device list.
3. Record which Xcode seed builds each iPad install (#83 hard rule applies
   to the iPad exactly as to whoGoesThere).

## Device pass checklist (post-merge, per PR)

- PR 1: install, resize matrix on-device, external keyboard shortcut sweep
  (Smart/Magic Keyboard if available), pointer hover, theme atmosphere perf
  at full screen, sensor screens show honest states.
- PR 2: sidebar flow, mid-stream resize, compact parity vs iPhone
  side-by-side, voice overlay both widths.

## Out of scope (explicitly)

Multi-window (J-2 follow-up), Apple Pencil features, iPad-specific widgets
layouts beyond compile-and-render, Mac Catalyst, CarPlay changes of any kind.
