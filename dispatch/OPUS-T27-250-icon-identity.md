# OPUS T27 #250 — Icon identity: teal Talaria as default, island wears the selected icon

> **⚠️ PARTIALLY SUPERSEDED 2026-08-10 — §5, §6 task 1, §6 task 6, §7 bullet 2
> and §9 items 2/4 are DISCHARGED.** The Debug harness trigger this document
> proposes-and-leaves-to-Owen was **ruled BUILD by Owen on 2026-08-09** and
> **built on 2026-08-10** by lane `t27-250-debug-island-trigger`
> (`dispatch/OPUS-T27-250-debug-island-trigger.md` is the live brief; bars
> 250T-A..D live in OPEN_ITEMS #250).
>
> - **§5 "Why 250-E has been unrunnable so far" is now history, not state.**
>   `ThrowawayLiveActivityHarness` + the Developer-screen button make the
>   island triggerable on demand. §5's diagnosis was correct — it was an app
>   testability gap, not a platform limit — and that is exactly what got fixed.
> - **§6 task 1 is DONE**, with one deliberate departure: it suggested
>   *"placeholder attributes/state."* The trigger instead starts the **REAL**
>   `HermesActivityAttributes` through the production `LiveActivityService`,
>   with synthetic *labels*. A placeholder attributes type would have rendered
>   something other than what a real run renders, and 250-E's whole question is
>   what the real activity puts in the island's icon slot.
> - **§6 task 6 / §9 item 4 ("queue 250-E once a trigger exists") is DONE** —
>   and the grep result quoted there is stale: the row was added 2026-08-09 as
>   **§R2** of `dispatch/DEVICE-PASS-RUNNING-LIST.md`, and was updated by this
>   lane from "standing watch, do not schedule" to a runnable, queued check.
> - **§7 bullet 2 / §9 item 2 ("is a harness trigger worth building at all —
>   Owen's call") is ANSWERED: yes, build it.** Do not re-raise it.
>
> **Still open and unchanged:** 250-E/250T-C itself — nobody has yet watched
> the island on a device. The trigger makes the check runnable; it does not
> perform it. §4's 250-F (assert the RIGHT icon is republished) and §7's
> tinted-glow look are also still open, untouched by this lane.

**Item:** #250 (`OPEN_ITEMS.md:8790`). **Goal of THIS dispatch, as assigned:**
verify the feasibility claim, assess the two halves, propose bars, and plan
remaining work — a normal "not yet scheduled" dispatch. **What the read at
HEAD actually found: the lane was already opened, built, and merged to `main`
on 2026-08-05 (PR #269), and is present in this checkout right now.** Bars
250-A/B/C are MET with a passing gate; 250-D (device) is PARTIAL — the
default-icon half is confirmed on Owen's phone, the island half is an
unverified **watch** with no queued way to trigger it reliably. This document
is reshaped accordingly: not a build plan, but a verification read of what
shipped, a correction of the stale tracker header, and a small closing lane
for the one open thread (a reliable island-trigger + the device check itself).
**No code was written for this dispatch; no Swift file was touched.**

---

## 1. Verified state

### 1a. Both halves are built, merged, and live in this checkout

`git log --all --oneline | grep -i 250` and `git merge-base --is-ancestor
e10ece4 HEAD` (the PR #269 merge commit) both confirm: `e10ece4` — "Merge pull
request #269 from AethyrionAI/claude/t27-250-icon-identity" — **is an ancestor
of the current HEAD** (`35c6234`, branch `t27-295-expiration-recovery`). The
feature commit is `da629f8`, 2026-08-05, "feat(#250): Deep Field orb as the
default app icon; island wears the selected icon."

### 1b. Half 1 — default icon — VERIFIED, matches the entry's design exactly

- `Talaria/Models/AppIconCatalog.swift:50-56` — `AppIconCatalog.primary` is the
  `id: "default"` option, `alternateIconName: nil` (the asset-catalog
  `AppIcon`), `previewImageName: "IconPreview-Default"`.
- `tools/appicons/generate_app_icons.py:179-194` (`emit_primary()`) —
  regenerates `AppIcon.png` / `AppIcon-Dark.png` / `AppIcon-Tinted.png` from
  the **same** Deep Field theme render the `DeepField` alternate uses ("so
  default and alternate can never drift" — the function's own docstring).
  Tinted = grayscale glyph on transparency (HIG-compliant); dark = deepened
  gradient.
- `git show --stat da629f8` confirms the primary appiconset PNGs were
  overwritten: `AppIcon.png` 1,115,442 → 89,826 bytes, `AppIcon-Dark.png` →
  87,159, `AppIcon-Tinted.png` → 77,249 — a large size drop consistent with
  swapping out the upstream Hermes art for the simpler generated render.
  `IconPreview-Default.png` was rebaked to match by
  `make_default_preview()` (`tools/appicons/generate_app_icons.py:197-209`),
  which explicitly bakes the picker thumbnail **from the same
  `AppIcon.appiconset/AppIcon.png`** so the picker card can't drift from the
  home screen.
- `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` (`project.yml:30`) — no plist
  change needed, exactly as the entry's feasibility note predicted.

### 1c. Half 2 — island wears the selected icon — VERIFIED, and the platform blocker is real (checked against the SDK, not recalled)

**The mechanism, file:line:**
- `Shared/SelectedIconHandoff.swift:12-45` — `SelectedIconHandoff` enum.
  `containerFileURL` resolves `selected-icon.png` inside the app-group
  container (`ControlHandoffStore.appGroupID`); `publish(previewImageName:from:to:)`
  loads the picker's preview PNG from the **app's** bundle and writes it,
  atomically, to that shared file; `load(from:)` reads it back as a
  `UIImage`. Explicit comment at the top: *"the widget extension cannot read
  the app bundle's loose alternate-icon PNGs by OS icon name … the APP
  publishes the selected icon's preview PNG into the shared app-group
  container."*
- `Talaria/Stores/AppIconStore.swift:24-48` — `AppIconStore` (the existing
  #25 store) now takes an injected `iconHandoffURL` (defaults to
  `SelectedIconHandoff.containerFileURL()`), and calls
  `publishSelectionForWidgets()` on **init** (heals a missing handoff on
  every launch — line 34), and again after a successful `select(_:)`
  (line 71).
- `TalariaWidgets/HermesLiveActivity.swift:35-54` — `HermesBrandIcon.loadImage()`
  tries `SelectedIconHandoff.load()` **first** (line 38); falls back to the
  bundled `AppIcon60x60` (line 41), then reaches into the **container app's**
  bundle two levels up from the extension's own `Bundle.main` (lines 45-51,
  an existing technique already in use for the default-art fallback); returns
  `nil` only if all three fail, at which point the view falls back to an SF
  Symbol (lines 24-32). `HermesBrandIcon` is used at all four Dynamic Island
  regions (expanded leading/center-adjacent, compact leading, minimal — lines
  77/98/106) plus the lock-screen view (line 115).
- `Shared/` is a whole-directory source for **both** the `Talaria` app target
  (`project.yml:70`) and the `TalariaWidgets` extension target
  (`project.yml:378`) — this is how `SelectedIconHandoff.swift` compiles into
  both without a duplicated file (unlike `HermesWidgetData.swift`, see §8).

**The platform claim, verified against the beta4 SDK header, not memory —
per the project's "never blame Apple first" rule:**

```
$ grep -n "alternateIconName" .../UIApplication.h
277: @property (readonly, nonatomic) BOOL supportsAlternateIcons
     NS_EXTENSION_UNAVAILABLE("Extensions may not have alternate icons")
     API_AVAILABLE(ios(10.3), tvos(10.2)) API_UNAVAILABLE(watchos);
280: - (void)setAlternateIconName:...
     NS_EXTENSION_UNAVAILABLE("Extensions may not have alternate icons") ...
283: @property (nullable, readonly, nonatomic) NSString *alternateIconName
     NS_EXTENSION_UNAVAILABLE("Extensions may not have alternate icons") ...
```
(`/Applications/Xcode-beta4.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/UIKit.framework/Headers/UIApplication.h:275-284`,
read directly, this session.)

`UIApplication.alternateIconName` is `NS_EXTENSION_UNAVAILABLE` in Apple's own
header text — a widget-extension target builds with
`APPLICATION_EXTENSION_API_ONLY = YES` by default, so this API is a **hard
compile error** inside `TalariaWidgets`, not a runtime restriction and not a
guess. **That is the actual, SDK-confirmed reason the widget can't just ask
"what's the current alternate icon?"** — not "can't read files from the
parent bundle" (it already does that, for the fallback chain, at lines
45-51). The entry's Half-2 reasoning was directionally right but imprecise
about *why*; the handoff-file design is the correct answer regardless, and
matches the existing `ControlHandoff`/`appearanceTheme` pattern the entry
cited as precedent.

**Tests (250-B/C), read at HEAD:**
`TalariaTests/SelectedIconHandoffTests.swift` — 4 `@Test`s: round-trip
(publish→load), nil/missing URL → nil, publish fails closed on unknown art or
nil destination (no partial write), and `AppIconStore(iconHandoffURL:)` heals
a fresh/missing handoff at init. File header comment: *"The widget-side read
order is device-verified (250-D)"* — i.e. the unit tests deliberately do not
claim to cover the widget process itself; only a device run can.

### 1d. Device verdict, read from the tracker's own dated notes (`OPEN_ITEMS.md:8861-8879`)

- **Home-screen half: RESOLVED.** Owen's first read ("didn't revert to the
  default… stayed on what it was set on before") was a false alarm — the
  picker was sitting on **Kaiju Attack**, an alternate, so keeping that icon
  was correct behavior. Follow-up screenshot confirms: *"I don't even see the
  old icon which is good"* — the upstream Hermes art is gone from every
  surface he's met.
- **Island half: still OPEN, as a WATCH, not a fail.** *"He can't
  consistently trigger the island; judge it whenever one appears."* No
  negative result — no unverified result either.

### 1e. Nothing here is ASSUMED — everything above was re-read from source at HEAD

The one thing that is inference rather than direct evidence: whether the
*specific* mechanism (`SelectedIconHandoff.load()` inside the widget process)
actually renders correctly on-device has never been observed — that's exactly
bar 250-D's open half, and is called out as such in §5 and §7.

---

## 2. The two halves — retrospective difficulty read

**Half 1 (default icon) was in fact trivial**, as the entry predicted: one
generator function reused, three PNGs regenerated, one preview rebaked, zero
plist/entitlement/project.yml changes. The entry's own risk flag — "confirm
WHICH icon Owen means by 'teal talaria'" — was the actual hard part, and it
was resolved by an `AskUserQuestion` before any code was written ("teal
talaria" = the Deep Field orb), not by guessing.

**Half 2 (island) was correctly scoped as "small" by the entry, and the build
matches that scope** — one new 45-line file, ~20 lines in an existing store,
~10 lines in the Live Activity view, 4 new unit tests. It was **not** trivial
in the way Half 1 was: it required recognizing that `UIApplication`'s
alternate-icon surface is unavailable to extensions (verified in §1c) and
routing around it via the app-group file handoff already proven for
`appearanceTheme`/`ControlHandoff`. That recognition is exactly what the
entry's design section did, correctly, before any code existed. **Half 2 is
NOT blocked** — it shipped, gate-passed, and the design is sound. What
remains open is **observation**, not implementation: nobody has watched the
island actually wear the selected icon on a live device, because the island
is hard to trigger on demand (see §5, §6).

---

## 3. ⚠️ Tracker corrections

**Correction 1 — the section header itself is stale and should be rewritten.**
`OPEN_ITEMS.md:8790` reads: *"FILED 2026-08-04 night (Owen's feature request,
with screenshot); feasible on existing #25 machinery; lane not yet
scheduled."* That is false at HEAD: the lane was opened the next evening
(`OPEN_ITEMS.md:8816`, "▶ LANE OPENED 2026-08-05 evening"), built the same
evening (`8849`, "✅ BUILT"), and merged as PR #269 (verified in git, §1a).
Bars A/B/C are MET, gate PASS. Only 250-D's island half remains genuinely
open, and only as a watch, not a fail. The header should read something like
"BUILT + MERGED 2026-08-05 (PR #269); 250-A/B/C MET, gate PASS; 250-D
home-screen half RESOLVED, island half OPEN AS A WATCH — no reliable trigger
yet." **This is not a small wording nit** — a reader who trusts the header
(as this dispatch's own brief did, per its framing "lane not yet scheduled")
will re-plan work that is already done. This is the exact ATS-lines shape
CLAUDE.md's Hard-won-gotchas section warns about: the summary line and the
body of the same entry disagree, and the summary line is what gets quoted
forward.

**Correction 2 — "feasible on existing #25 machinery" is true for Half 1 only,
imprecisely stated for Half 2.** Re-reading the entry's own **Feasibility**
section (`8799-8814`, written at filing, before any correction was needed):
it never actually claims Half 2 rides #25's machinery unchanged — it says the
opposite, that the widget "cannot read the APP bundle's loose alternate-icon
PNGs" and needs new machinery crossing the app-group boundary. The **design**
section later is explicit: *"`#25` machinery (CFBundleAlternateIcons, catalog,
picker) untouched"* (`8828-8829`) — i.e. Half 2 was built **alongside** #25,
not **on top of** it. Only the section **header's** compressed one-liner
("feasible on existing #25 machinery") collapses this nuance and reads as
if both halves ride the same rails. Recommend the corrected header (above)
drop that phrase entirely rather than repeat it — it invites exactly the
misreading this dispatch had to check its way out of.

**Correction 3 — no stale facts found in #25 or #112.** Spot-checked both:
#25 (`OPEN_ITEMS-ARCHIVE.md:589`) is the CTX-meter item, an unrelated reuse of
the number "#25" as informal shorthand inside two OTHER items' prose (`grep`
in `ChatStore.swift`/`LocalChatBackend.swift` per that entry's own note) —
**the #25 this dispatch was asked to verify is the alternate-icon item, whose
canonical description lives inline in `AppIconCatalog.swift:1-16`, not in the
tracker under a numbered heading of its own** (no `## 25.` heading exists in
either tracker file for the icon machinery — only the CTX-meter item claims
that number). This is worth flagging on its own: **#25 as "the alternate-icon
lane" is a codebase-comment convention (`// MARK: - App icon catalog (issue
#25)`, `AppIconCatalog.swift:3`), not a tracker item** — #250's header citing
"#25 machinery" points at that comment-level convention, not a numbered
OPEN_ITEMS entry, and a reader chasing "#25" in the tracker will land on the
wrong item. #112 (Midnight Marquee, `OPEN_ITEMS.md:2274`) checks out as
described — 13 icons landed, 31 total in the catalog, matches the picker
gallery constants in `AppIconCatalog.swift` (`laneKBatchIsFullyWired`,
`laneLBatchIsFullyWired` tests at `TalariaTests/AppIconCatalogTests.swift:68,78`).

---

## 4. Proposed bars

250-A through 250-D already exist in the entry and are MET/PARTIAL as
described in §1. This section proposes what a **closing** lane needs —
lettered as a continuation, 250-E onward — plus the one documentation bar
that settles the stale-header correction.

- **250-E (device, Owen — the only bar that actually moves the open
  question):** with a **reliable** way to bring up the Dynamic
  Island/compact presentation (see §6 task 1 for how to get one), the
  island's leading icon slot visually matches the icon currently selected in
  Settings → Appearance → App Icon, both immediately after a switch and on a
  fresh cold-launch island. Needs a device — this is exactly the class of
  check CLAUDE.md flags as invisible to a green Debug suite (asset-catalog +
  cross-process rendering).
- **250-F (unit, cheap, no device):** a `SelectedIconHandoffTests` case
  asserting `AppIconStore.select(_:)` re-publishes the handoff with the
  **newly selected** option's `previewImageName`, not just "any" PNG — i.e.
  round-trip the actual selected art, not merely that *a* write occurred.
  Strengthens 250-C's coverage without needing a device; closes the gap
  between "the file gets written" (already tested) and "the file contains
  the RIGHT icon" (implied but not directly asserted today — worth checking
  before treating 250-B/C as fully dispositive of the logic 250-E will
  visually confirm).
- **250-G (docs only, no code, no device):** `OPEN_ITEMS.md:8790`'s section
  header rewritten per Correction 1/2 in §3, and a closing note appended
  once 250-E lands, per CLAUDE.md's close-out rule (corrections go upstream
  to the header, not just downstream in a dated note under it — the header
  is exactly what a future reader trusts without reading the body, as this
  dispatch's own brief demonstrates).

A missed bar is a falsification, not a redefinition — 250-E in particular:
if the island is triggered and the icon does NOT match, that is a real
finding to file, not a reason to quietly drop the bar.

---

## 5. Why 250-E has been unrunnable so far, and how to fix that

Live Activities start via `Activity<HermesActivityAttributes>.request(...)`
(`Talaria/Services/Live/LiveActivityService.swift:31,66`), which in this app
fires from real usage (an active chat/tool-running turn — grep the call
sites of `LiveActivityService` for the exact trigger). Owen's own words in
the tracker — "he can't consistently trigger the island" — say the natural
trigger path is not reliably reproducible on demand. That is a **testability
gap in the app**, not a platform limitation: `Activity.request` itself is a
completely normal SDK call with no extension-unavailability attribute (unlike
§1c's finding), so nothing stops the app from starting one on command.

---

## 6. Task breakdown

All of this is small and additive; nothing here touches `HermesWidgetData.swift`
or `HermesActivityAttributes.swift` (see §8).

1. **Add an on-demand Live Activity trigger for verification.** Likely a
   Developer-screen button (the existing pattern — see
   `runToollessIndexBattery`/harness buttons referenced in
   `dispatch/DEVICE-PASS-RUNNING-LIST.md`'s Z1 entry) that calls
   `LiveActivityService`'s existing start path with placeholder attributes/state,
   so Owen can bring up the island without needing a real in-flight turn.
   Gate this behind `#if DEBUG` like the other harness buttons (Release must
   not ship a fake-activity button — re-check with a Release build per
   CLAUDE.md's #218 corollary if this is built, since a promoted `#if DEBUG`
   gate is exactly what broke Release silently before).
   - File: likely `Talaria/Features/Settings/DeveloperSettingsScreen.swift`
     or wherever the other harness buttons live — locate via
     `grep -rn "toollessIndexBatteryButton" Talaria/`.
   - No new file under `Shared/` is needed for this step, so no xcodegen
     regen is required *for this task alone*.
2. **Run 250-E on device** using the new trigger: switch the app icon in
   Settings → Appearance → App Icon to something distinctive (e.g. Kaiju
   Attack, already confirmed working for the home screen), fire the harness
   trigger, and check the compact/expanded/minimal Dynamic Island regions
   plus the Lock Screen presentation against `HermesLiveActivity.swift`'s
   four `HermesBrandIcon` call sites (lines 77, 98, 106, 115).
3. **If 250-E fails** (island shows stale or wrong art): the most likely
   failure mode given the code read in §1c is a **stale handoff file** —
   `AppIconStore.select(_:)` publishes synchronously right after
   `setAlternateIconName` succeeds (`AppIconStore.swift:69-71`), so a timing
   race against WidgetKit's own timeline reload is the first thing to check,
   not the write/read logic itself (both are unit-tested and simple file
   I/O). Diagnose with a verbose log line in `HermesBrandIcon.loadImage()`
   before changing anything, per CLAUDE.md's `TalariaLog`/verbose-logging
   convention.
4. **If a new Swift file is added anywhere in this lane** (e.g. the harness
   trigger lives in a new file rather than an existing screen): run
   `xcodegen generate` before building — mandatory per CLAUDE.md, and
   doubly so here since `Shared/` is a directory-level source (§1b) where
   XcodeGen still needs to re-scan and add the pbxproj file reference for
   any new file, even though the `project.yml` source line itself doesn't
   change.
5. **File 250-G**: once 250-E has a verdict either way, rewrite
   `OPEN_ITEMS.md:8790`'s header per §3, and append the dated verdict note
   under the existing 250-D notes (do not overwrite the 2026-08-05 notes —
   append, per the tracker's own convention of accreting dated notes).
6. **Queue 250-E in `dispatch/DEVICE-PASS-RUNNING-LIST.md`** rather than
   leaving it to chance a second time — confirmed by grep
   (`grep -n "#250\|island" dispatch/DEVICE-PASS-RUNNING-LIST.md` →
   zero matches) that the island watch is not currently listed anywhere in
   the running device-pass queue, which is exactly the "one queue, don't
   restate it" trap CLAUDE.md calls out for #112's device debt. Add it as a
   new dated row once the harness trigger (task 1) exists, so it's a
   runnable check, not a vague reminder.

---

## 7. What is OWEN'S to decide

- **The default-icon-change-at-a-version-boundary question the assigning
  brief raised does not need deciding — it already happened, and not at a
  version boundary.** Half 1 shipped in place on build 2034 (2026-08-05),
  the SAME bundle id, no gate, no opt-in. Owen has already seen it on his
  own device and confirmed it positively ("I don't even see the old icon
  which is good," `OPEN_ITEMS.md:8873`). There is no pending decision here
  to surface — flagging it only for completeness, since the brief explicitly
  asked. If Owen wants a DIFFERENT default in the future, that's a new,
  ordinary icon-catalog edit, not a special case (worth noting: Talaria is
  Owen's own OTA/dev-signed install, not an App Store release with a
  broader user base — the "changes what every existing user sees without
  asking" concern the brief raised applies at much lower stakes here than a
  public shipping app would carry).
- **Is a harness trigger (§6 task 1) worth building at all**, or would Owen
  rather keep judging the island opportunistically whenever one appears
  naturally during real use? The tracker's own note calls it "judge it
  whenever one appears" — that may be an intentional low-priority stance,
  not an oversight. This dispatch defaults to "build the cheap trigger" but
  Owen may prefer not to spend the (small) engineering time on a
  Debug-only verification aid for an already-shipped, already-mostly-verified
  feature.
- **The tinted-variant glow note from 250-A** ("the tinted variant's glow
  renders bright — placeholder-grade, judge on the phone," `8858-8859`) has
  no recorded verdict anywhere in the tracker. Worth a one-line judgment
  from Owen next time he's looking at the icon in a tinted (Focus-mode-style)
  context — separate from 250-E, doesn't need a new bar, just a look.

---

## 8. Traps

- **`HermesWidgetData.swift` exists in two copies**
  (`Talaria/Models/HermesWidgetData.swift`,
  `TalariaWidgets/Models/HermesWidgetData.swift`) that must stay in
  lockstep per CLAUDE.md. **Verified: #250 does not touch this file at
  all** (`git show --stat da629f8` lists no `HermesWidgetData.swift` in
  either location) — the lane correctly avoided the duplication trap by
  putting the new icon-handoff logic in `Shared/SelectedIconHandoff.swift`
  instead, which compiles into both targets from one source (§1c). Any
  follow-up work here (§6) should keep doing that — do not fork icon logic
  into per-target copies.
- **A related-but-separate duplication exists and was NOT introduced by
  #250: `HermesActivityAttributes.swift`** lives in both
  `Talaria/Models/HermesActivityAttributes.swift` and
  `TalariaWidgets/HermesActivityAttributes.swift` — `diff` between them is
  currently empty (byte-identical), but this is a manually-synced pair, not
  a `Shared/`-compiled single source, so any future edit to either needs
  the same lockstep discipline CLAUDE.md documents for `HermesWidgetData.swift`.
  #250 did not touch either copy. Flagging only so a future island-related
  change doesn't edit one copy and forget the other.
- **Asset-catalog changes are invisible to the Debug/Release test suite.**
  The gate's reported "1617 Swift Testing units + 12 XCUITest, Release
  green" (`OPEN_ITEMS.md:8856-8857`) proves the code compiles and the unit
  logic (write/read/fallback) works — it proves **nothing** about whether
  the actual pixels on a home screen or a Dynamic Island are correct. The
  only evidence that settles 250-A visually was Owen's own device look
  (§1d); the only evidence that will settle 250-E is likewise a device
  look, not a green gate.
- **Never blame Apple first — this dispatch checked, not assumed.** The
  natural-sounding claim "a widget extension can't read the app's selected
  icon" was verified against the literal beta4 SDK header text (§1c) rather
  than accepted from the entry's own prose. It turned out to be correct,
  but for a more specific and more mechanical reason
  (`NS_EXTENSION_UNAVAILABLE`, a compile-time attribute) than the entry's
  looser "can't read loose PNGs by name" framing — worth keeping the
  precise reason on file since it's what would need re-checking if a future
  iOS SDK ever changes extension entitlements.
- **The tracker header/body split (Correction 1, §3) is the trap most
  worth generalizing.** This dispatch's own assigning brief was written
  from the header line and was, in that specific respect, out of date
  before the read even started. Any future dispatch or handoff that quotes
  an OPEN_ITEMS section **header** without reading the body underneath it
  is exposed to the same miss.

---

## 9. Close-out

**Nothing in this dispatch requires new production code to be considered
"done" as a verification exercise** — the feature is built, merged, and
mostly device-confirmed already. What's left, in priority order:

1. Correct `OPEN_ITEMS.md:8790`'s header (§3, Correction 1/2) — cheap, purely
   upstream-truthful, unblocks nothing but prevents the next reader from
   repeating this dispatch's own initial misreading.
2. Decide (Owen, §7) whether a Debug harness trigger for the island is worth
   building, or whether "judge it whenever one appears" stays the standing
   plan.
3. If built: run 250-E on device, file the verdict (pass or a real finding),
   and only then close #250 outright with a final dated note appended to the
   existing 2026-08-05 block — not a rewrite of it.
4. Queue 250-E in `dispatch/DEVICE-PASS-RUNNING-LIST.md` the moment a
   trigger exists, so it doesn't fall through the same gap it already fell
   through once.

No gate run is owed for this dispatch itself — no Swift file was touched.
The gate is owed again only if task 1 in §6 (the harness trigger) is
actually built, at which point CLAUDE.md's standard `scripts/mac/lane-gate.sh`
(background it, poll the log for `GATE: PASS`) applies as normal, plus the
Release-build corollary from #218 because it would add a new `#if DEBUG` gate.
