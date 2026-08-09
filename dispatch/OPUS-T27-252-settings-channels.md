# OPUS — #252 SETTINGS REDESIGN ("Subsystem Channels")

**Label:** OPUS · **Item:** OPEN_ITEMS #252 · **Written:** 2026-08-09

> **⛔ THIS IS A VERDICT, NOT A DISPATCH. #252 SHIPPED TO `main` ON 2026-08-05.**
> All six pre-registered bars (252-A…F) are MET, the device pass is done
> (build 2034), and the final review wave landed. **There is no lane to open.**
> Dispatching this item would respec merged, gated, device-judged work.
> The only residual is one untested visual-coherence defect the #256 verbiage
> round introduced afterwards (§5, bar 252R-A) — a ~10-line fix, not a redesign.

**Goal of this document:** record that #252 is complete, prove it at HEAD, correct
the stale tracker header, and scope the single residual found by re-reading the
shipped code.

---

## 2. Verified state

### VERIFIED — the redesign is on `main` and running

Every commit below is on `main` (`git branch --contains`, all eight):

| Commit | What it landed |
|---|---|
| `20b85b4` | `SettingsChannelsScreen` grid shell replaces the root (interim pushes) |
| `fff72bf` | Subsystem deck — paged `TabView`, dots, counter, grid toggle |
| `a73ea09` | Appearance deck page with #244 browser handoff |
| `f8badf7` | `SubsystemHero` + per-page heroes |
| `c470631` | About merge + battery harness relocation; retire SystemSettings + Diagnostics |
| `c47a91b` | Final-review wave — verdict coherence, stale strings, system reduce-motion |

**Wired as the settings root:** `Talaria/ContentView.swift:273` presents
`SettingsChannelsScreen()`. There is no drill-down row list left to replace.

**Nine subsystems exist as routed** (Uplink, Server, Models, Voice, Appearance,
Privacy, Sessions, About, Developer) —
`Talaria/Features/Settings/SettingsChannels.swift:9`. The About merge is real:
`SystemSettingsScreen.swift` and `DiagnosticsSettingsScreen.swift` are **gone**
from `Talaria/Features/Settings/` (compare the as-built inventory's file table,
`planning/superpowers/specs/2026-08-05-252-settings-inventory.md:11-27`, which
still lists both — that document is a snapshot of the PRE-redesign surface and is
correct as such).

**Deck pages embed the real screens**, not reproductions —
`SettingsChannelsScreen.swift:177-195` (`deckPage(_:)`) hands each subsystem its
existing screen with `embedded: true`; Appearance gets `AppearanceDeckPage()`,
which hands off to the #244 browser unchanged, exactly as the routing required.

**Counter and toggle as specced:** `SettingsChannelsScreen.swift:102-107`
(`"09 SUBSYSTEMS"` in grid, `"%02d / 09"` in deck).

### VERIFIED — the real-data rule is honored by construction

This is the part worth having checked, because a nine-card live-telemetry grid is
precisely where CLAUDE.md's *"Real data only in UI — show `—` where a value isn't
knowable; no mocked toggles"* bites hardest.

**Every card value is store-derived.** `SettingsChannelsScreen.swift:374-409`
(`cardValue(_:)`) — no literal reaches a card:

- uplink ← `effectiveConnectionState` + `chatStore.directConnectionStatus`
- server ← `profilesStore?.activeProfile?.name`
- models ← `chatStore.activeModelName` / `chatBackendRouter?.activeBrain`
- voice ← `chatBackendRouter?.activeBrain`, `talkStore.voiceEngine`, `talkStore.connectionState`
- appearance ← `ThemeRuntime.shared.theme.displayLabel` + live channel index
- privacy ← four real `settingsStore` sensor flags
- sessions ← live `sessionCount`
- about ← `aboutIsHealthy` (shared predicate)
- developer ← `settings.environment.displayLabel`

**Unknowables render honestly, not optimistically:**
- `SettingsChannels.swift:112` — unknown host → `"—"`, with the comment
  *"unknowable hosts render `—` (real data only)"*.
- `SettingsChannels.swift:121-122` — `sessions(count:)` with a nil count returns
  `"…"` rather than inventing `0`. A not-yet-loaded count is not zero sessions.
- `SettingsChannels.swift:82` — voice `.checking` → `"…"`.
- `SettingsChannels.swift:134-136` — `aboutIsHealthy` makes hostless read
  **HEALTHY**, honoring the routed "unpaired is the designed state" constraint.
  The old root's DEGRADED-when-hostless was an inherited defect the redesign had
  briefly promoted to a hero; `c47a91b` fixed it and made the grid card and the
  About hero share one predicate so they cannot disagree.

**Verdict on 252-A's real-data clause: it holds at HEAD.** No `REACTOR`/`REALTIME`
literal survives as a fake value; the one `"REALTIME"` string that exists
(`SettingsChannels.swift:81`) is a live `talkState` reading, which is the opposite
of the thing 252-A forbade.

### VERIFIED — the one residual defect (found by this re-read, not previously filed)

**`SettingsChannelsScreen.swift:417` — the Voice card's ACCENT still measures
read-aloud, but its VALUE now measures the voice route.**

```swift
case .voice: settingsStore.settings.readAloudAutoPlay
```

Every other card's accent predicate (`cardIsAccented`,
`SettingsChannelsScreen.swift:411-428`) means *"this subsystem is in a live/active
state"* — uplink online, a profile is set, a model is set, sensors are streaming,
sessions loaded, about healthy. Voice's does not, and did not always disagree:
#256-H (commit `c8b27fb`) moved the voice card's TEXT from the read-aloud toggle
to the engine route and **left the accent predicate behind**.

Observable consequence: the card can read `REALTIME · LIVE` (a voice session is
genuinely connected) and render **unaccented** because read-aloud auto-play is
off; or read `ON-DEVICE` and **glow** because read-aloud is on. The glow is
telling the user about a setting the card no longer names.

`SettingsChannelsScreen.swift:417` is now the only site reading
`readAloudAutoPlay` outside `VoiceSettingsScreen.swift:191-192`'s own toggle —
which is the tell that it was orphaned rather than intended.

**It is untested.** `TalariaTests/SettingsChannelsTests.swift` has 13 `@Test`
cases, all formatter-level; `cardIsAccented` has zero coverage. This is a small
instance of the **#180** family (a signal that does not say what it appears to
say), which is why it is worth fixing rather than shrugging at.

### ASSUMED (stated, not verified this pass)

- **The suite is still green at HEAD.** The last recorded `GATE: PASS` for this
  surface is #256's verbiage round (1618 units + 12 XCUITest + Release). `main`
  has advanced a long way since (#284/#286/#295/#297; the #297 lane reports 1852
  units). No gate was run by this document — it wrote no code.
- **The parity checklist** proving 252-C is at
  `.superpowers/sdd/2026-08-05-252-settings-channels/parity-checklist.md`, which
  is **gitignored and local-only**. Its existence is taken from the tracker; it
  could not be read here. If that machine is gone, 252-C's artifact is gone with
  it — the verdict stands on the tracker's record.
- The `.dc.html` design sources live in a session scratchpad / `~/Downloads` zip;
  not re-read. Per the standing note they need a React host and render blank —
  read as spec, never deployed. Nothing here depends on re-opening them.

---

## 3. The #252 ↔ #256 relationship

**VERDICT: (a) — #256 was a stepping stone that SURVIVES #252 intact, because
#256 was built ON the #252 surface, not on the old one. Neither throws the other
away. Both already shipped, twelve hours apart, in the correct order.**

The question as posed ("would shipping #256 into a surface #252 replaces be
waste?") assumes #256 targets the *old* grid. It does not. The evidence:

1. **#256's strip lives inside the #252 screen.** `settings.statusStrip` is
   rendered at `SettingsChannelsScreen.swift:222`, inside `gridScroll` — the
   #252 file. It could not exist before #252 landed.
2. **#256's origin is #252's own device pass.** #252's entry, verdict (f):
   *"INFO STRIP APPROVED: the grid sits too high… a full-row status bar (~two
   cards wide) between the top bar and the grid 'would move it down perfectly'."*
   #256 is the follow-on lane that verdict opened. Owen was looking at the
   **new** grid when he asked for the strip.
3. **#256's Privacy rewrite corrects a #252 string.** #252 verdict (d) records
   `"0 STREAMS"` REJECTED on device; #256's `privacy()` formatter
   (`SettingsChannels.swift:94-99`) is the replacement, and its own comment says
   so: *"#256 (Owen's device-pass verdict): '0 STREAMS' clarified nothing."*
4. **Commit order confirms it.** #252's six commits, then `2c17f86` (#256 strip),
   then `c8b27fb` (#256 verbiage) — all 2026-08-05, all on `main`.

**Shipping order: already correct and already executed — #252, then #256.** The
standing "don't fix a component with a planned end-of-life" lesson does not apply
here in either direction: #256 did not harden a doomed surface, it finished the
replacement surface using Owen's first look at it. That is the healthy shape of
this pairing, and it is worth naming because the reverse would have been waste.

**Residual coupling to know:** the two lanes now share a defect seam. #256-H
changed a #252 card's semantics (Voice: toggle → route) without changing the
#252 accent predicate that depended on the old semantics. §5's bar 252R-A closes
it. This is the only place the two lanes are not cleanly separable.

---

## 4. ⚠️ Tracker corrections

Owed against `OPEN_ITEMS.md` **#252** and the spec. **This document edits neither
file** — the orchestrator files these.

1. **#252's header is stale.** `OPEN_ITEMS.md:7980` still reads
   *"ROUTED 2026-08-05 (all four decisions), **spec in progress**."* The spec is
   written, the lane is built, merged, gated, and device-judged, and the same
   entry's own body records all six bars MET. **Proposed header state:
   ✅ CLOSED 2026-08-05 — 252-A…F all MET, gate PASS, device pass on build 2034;
   ride-along follow-ons routed into #256 (shipped) and #249F (shipped).** The
   board index line (`OPEN_ITEMS.md:197`) needs the same treatment. This is the
   close-out rule's exact target: a header that a lane's own result falsifies.
2. **The spec's status line is stale.**
   `planning/superpowers/specs/2026-08-05-252-settings-channels-design.md:3`
   reads *"**Status:** awaiting Owen's review."* Owen reviewed it, routed it,
   and device-judged the build on 2026-08-05. Correction goes UPSTREAM, into the
   spec itself — a dated supersession line at minimum: *"SUPERSEDED BY THE BUILD
   2026-08-05 — shipped on `main`; see OPEN_ITEMS #252 bar verdicts."*
3. **The inventory's file table describes a surface that no longer exists.**
   `2026-08-05-252-settings-inventory.md:11-27` lists `SystemSettingsScreen.swift`
   as "THE ROOT" and `DiagnosticsSettingsScreen.swift` as a live file; both were
   deleted by `c470631`. The document is explicitly an *"as-built, 2026-08-05"*
   pre-redesign snapshot and is **correct as a historical baseline** — but a
   reader arriving cold will mistake it for current. One dated line at the top
   ("this describes the PRE-#252 surface; the redesign deleted rows 1 and 10")
   prevents the next lane from grepping for a file that isn't there.
4. **The false-green invocation warning is already recorded and should stay
   loud.** #252's entry carries it, and the #249F lane hit the same trap again
   from the other direction (a METHOD path under a Swift Testing struct runs 0
   tests under `TEST SUCCEEDED`). Both are the same failure: a selector that
   matches nothing reports success. The rule that survives both is **check the
   executed count moved**, never the success marker alone.

---

## 5. Bars

### As-shipped (recorded, all MET — do not re-run)

252-A (nine store-derived cards, no literals) · 252-B (deck nav, `%02d / 09`,
swipe) · 252-C (control parity vs the inventory §1–§11) · 252-D (battery harness
under Developer, `Battery results →` opens) · 252-E (four updated pairing/
appearance UI tests) · 252-F (Release build green). Verdicts and their evidence
are in `OPEN_ITEMS.md` #252 under "Bar verdicts (2026-08-05, Task 10 — all six
MET)". Gate: `GATE: PASS`, 1600 units + 12 XCUITest + Release.

### PROPOSED — the residual only (orchestrator files these; Owen approves the lane)

- **252R-A (unit + visual) — THE REAL-DATA BAR, and the reason this document
  exists.** *A card's ACCENT must describe the same fact as its VALUE.* Change
  `SettingsChannelsScreen.swift:417` from `readAloudAutoPlay` to a route-derived
  predicate — the card glows when voice is genuinely live/active
  (`talkState == .connected`, or brain-local as the honest on-device active
  state), never when an unrelated read-aloud toggle is on. **Extract
  `cardIsAccented`'s per-subsystem predicates into pure functions in
  `SettingsChannels.swift` beside the value formatters, so they are unit-testable
  at all** — today they are unreachable from tests, which is why this drifted
  silently for four days.
  *Evidence:* watched-RED unit pins — a case asserting `voice` accent is FALSE
  while `readAloudAutoPlay` is true and the route is idle, and TRUE when
  `talkState == .connected` and read-aloud is off. Both fail against HEAD for
  the right reason before the fix. Unit count must MOVE (state the arithmetic).
  *Device need:* **NONE.** This is settled by the unit pins plus one sim
  screenshot of the Voice card with read-aloud off and a live talk session.
  Do not spend Owen's phone time on it.

- **252R-B (no collateral).** The 13 existing `SettingsChannelsTests` cases and
  both strip XCUITest assertions (`TalariaUITests/AppTemplateUITests.swift:466`
  present-in-grid, `:515` absent-in-deck) stay green **unmodified**. If any
  existing pin needs editing, the change has exceeded its scope — stop and
  re-scope rather than adjusting the test.
  *Evidence:* the gate's executed count, read as a number, not as `TEST
  SUCCEEDED`.

- **252R-C (gate).** `scripts/mac/lane-gate.sh` full run, literal `GATE: PASS`,
  Release leg included. Background it and poll the log with an `until` loop.
  *Evidence:* the marker plus the moved unit count from 252R-A.

**A missed bar is a falsification, not a redefinition.**

---

## 6. Task breakdown (only if Owen wants 252R)

Small — one file's worth of extraction plus pins. Roughly one sitting.

1. **Read** `Talaria/Features/Settings/SettingsChannelsScreen.swift:411-428` and
   `Talaria/Features/Settings/SettingsChannels.swift:48-139` together. The
   accent predicates and the value formatters are the same nine-way switch
   written twice, in two files, at two levels of testability.
2. **Extract** the nine accent predicates into `SettingsCardValues` (or a peer
   `SettingsCardAccent` enum) in `SettingsChannels.swift`, pure and
   store-free — mirroring exactly how the value formatters were made testable.
   No behavior change in this step for the eight non-voice cards.
3. **Write the RED pins** in `TalariaTests/SettingsChannelsTests.swift` for the
   voice accent, per 252R-A. Watch them fail against the unchanged predicate.
   Confirm the failure reason is the semantic mismatch, not a compile error.
4. **Fix** the voice predicate. Green.
5. **Gate.** `scripts/mac/lane-gate.sh`, backgrounded, polled.

**`xcodegen generate` is NOT needed for 252R** — it adds and removes no Swift
files, only moves code within two existing ones. (Had this been the redesign
itself it would have been mandatory: that lane added `SettingsChannels.swift`,
`SettingsChannelsScreen.swift`, `SubsystemHero.swift`, `AppearanceDeckPage.swift`
and deleted two screens. If any follow-on ever adds a file, regenerate before
building, and expect the "project modified on disk" modal on the next
`RunProject`.)

---

## 7. What is OWEN'S to decide

1. **Whether 252R is worth a sitting at all.** It is a glow that means the wrong
   thing on one card out of nine. Honest options: fix it, or drop the voice
   accent to always-false and let the value text carry the whole signal. Both
   are defensible; the current state — accent describing a fact the card no
   longer names — is the only one that isn't.
2. **The Voice accent's semantics, if fixed.** Should the card glow for *any*
   live voice route (including `ON-DEVICE`, which is always "available"), or only
   for an actively connected realtime session? "Always on for on-device" makes
   the accent meaningless on a hostless install — the default user under the
   launch pivot. Recommendation: glow only on `talkState == .connected`.
3. **Whether to close #252 outright** or hold it open as the umbrella for the
   1b settings-search follow-on. The spec explicitly parked 1b as *"a possible
   follow-on lane, not in scope"*; it has no tracker number of its own, and by
   the #268 rule ("a phase name is not a filing") it needs one before it can be
   said to exist anywhere.
4. **Ride-along (a), still filed and unresolved:** deck entry builds all nine
   pages, so every grid↔deck flip re-fires nine read-only status probes. Judged
   acceptable at build time, *"revisit if Owen notices."* He has now used the
   surface for four days. Does he notice?

---

## 8. Traps

- **Shipping a fix into a surface about to be replaced — inverted here, and
  worth stating plainly.** The standing lesson (⛔ don't harden the relay) is
  that reliability bought in a component with a planned end-of-life expires
  while the update friction compounds. #256 looked like that shape and **was
  not**: it built on the replacement, not the corpse. The real trap in this pair
  is the opposite one — reading "252 is a redesign, 256 is a fix" off the
  headers and cancelling the wrong item. Read the commit order.
- **Both `HermesWidgetData.swift` copies.** If any follow-on touches widget
  appearance, the app-target and widget-target copies must move in lockstep —
  they are separate files with identical contents, and a one-sided edit compiles
  cleanly and diverges silently. **252R does not touch widgets;** this trap is
  listed because the settings surface owns theme selection and the next
  Appearance-adjacent lane will meet it.
- **Theme resolution is live, and the card values ride it.**
  `currentThemeName` reads `ThemeRuntime.shared.theme.displayLabel`
  (`SettingsChannelsScreen.swift:441-443`). Any test that pins an Appearance
  card string is pinning theme-catalog data. Never hardcode a palette value —
  everything lives in `Shared/ThemePaletteCore.swift`, compiled into **both**
  the app and widget targets.
- **The gate is the only check that can see a Release break.** #218's lesson:
  a green Debug suite proved nothing while `main` could not build in Release
  for two days. `252R` touches no `#if DEBUG` gate, but the Release leg is not
  optional.
- **`-only-testing` selectors that match nothing report success.** Two separate
  variants have burned this project: a class name that doesn't exist (#252's
  own correction of record) and a METHOD path under a Swift Testing struct
  (#249F). **Read the executed count.**
- **Do not re-run the shipped bars to "confirm."** 252-A…F are MET with recorded
  evidence and a device pass. Re-running them costs a sitting and can only
  produce a weaker verdict than the one already on file.

---

## 9. Close-out

**This item does not need a lane. It needs its header corrected.**

The close-out rule (2026-08-06) says a lane does not close until every entry,
doc, and CLAUDE.md line its result falsifies is corrected in the same commit,
and that corrections go UPSTREAM to the stale claim's own home. #252 shipped
without that sweep: its header still says *"spec in progress"* while its body
records six MET bars, and its spec still says *"awaiting Owen's review."* §4
lists all four corrections and their homes.

If 252R runs, it closes when: the RED pins were watched red for the right
reason, the accent predicates are pure and tested, `GATE: PASS` with a moved
unit count, and §4's corrections land **in the same commit** as the fix.

Nothing here is owed to Owen's phone. Say so when reporting — the device queue
is the scarcest resource in this project, and this lane does not draw on it.

**Cross-reference:** `dispatch/OPUS-T27-256-settings-strip.md` (the companion
verdict; #256 is likewise shipped, with two genuinely-owed passive device
observations routed there).
