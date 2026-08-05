# #252 — Settings "Subsystem Channels" redesign (Claude Design direction 1c)

**Status:** awaiting Owen's review. **Tracker:** OPEN_ITEMS #252 (routing recorded
there 2026-08-05). **Source design:** Claude Design handoff — `Settings Channels
Prototype.dc.html` (primary, fully interactive) + `Settings Redesign.dc.html`
(three-directions survey; 1c chosen). **Companion:** every existing control this spec
must re-home is inventoried in `2026-08-05-252-settings-inventory.md` (§ references
below point there).

## Goal

Replace the settings ROOT (a drill-down row list) with the channel metaphor the app
already uses for themes: a **grid of nine live-telemetry subsystem cards** that
toggles into a **swipeable full-bleed subsystem deck**. Sub-screen content survives;
its top half becomes a hero, and horizontal swipes move between subsystems the way
the #244 browser moves between theme channels.

## Decisions already made (Owen, 2026-08-05 — do not relitigate)

1. Direction **1c** as prototyped. (1b's settings search = possible follow-on lane.)
2. **No AUTO routing** — filed as #253. Nothing in this lane adds per-message routing;
   the existing Chat Brain section (inventory §4) is the routing surface and ships
   unchanged.
3. **About merge** — System-root identity + Diagnostics fold into one ABOUT subsystem.
   Battery/harness UI displaced by the merge relocates under Developer.
4. Full scale green-lit; build staged internally (shell → pages → merge → tests).

## Held fixed (from the survey doc, adopted as constraints)

- Deep Field (and every other channel) exactly as shipped — **zero palette/token
  changes**. Type via existing `Design.Typography` tokens; no new fonts.
- Plain SwiftUI: `LazyVGrid`, paged `TabView`, sheets, segmented buttons. No custom
  layout engine.
- **Appearance untouched:** its deck page is an entry that hands off to the #244
  channel browser unchanged (`AppearanceSettingsScreen` as-is, Tuning sheet and
  App Icon child included).
- **Unpaired is the designed state.** On-device reads complete; pairing is framed as
  added capability.
- Existing idioms preserved (inventory §15): no `List`, `.hudPanel` groups,
  `MonoLabel("// …")` headers, destructive confirms via `.alert` (#193),
  `ReactorOrb`, `GlassCircleButton`, ✕-to-close, Esc shortcuts.

## Architecture

### New root: `SettingsChannelsScreen`

Replaces `SystemSettingsScreen` as the content of `ContentView.sheetDestination(.settings)`
(same NavigationStack + `.large` detent). Two view states:

- **`grid`** (default on open): status bar area untouched; header row `✕` (close,
  Esc) · center kicker `SYSTEM` + counter `09 SUBSYSTEMS` · grid-toggle button
  (accent-active in this state). Below: the card grid (next section), then the
  Developer compact row, then footer `TAP A CARD · TALARIA v<version> · DEVICE-BOUND`.
- **`deck(index)`**: header row `‹` (returns to grid) · kicker `SUBSYSTEM` + counter
  `%02d / 09` · grid-toggle button. Below: a paged `TabView(selection:)` of the nine
  subsystem pages, page dots (current = 20pt pill, accent), swipe with natural
  paging. Respect `settings.reduceMotion` / `ThemeRuntime.appReduceMotion`: no
  animated transition when set.

Tapping a grid card opens `deck(cardIndex)`. The grid-toggle button flips states from
anywhere. Closing the sheet from deck state is via `‹` → grid → `✕` (matches
prototype; keep Esc = close-sheet in both states).

Widths/heights are layout-derived (GeometryReader / container-relative), never the
prototype's fixed 393pt — iPad must not regress (`IPadAdaptationTests`).

### The nine subsystems, in deck order

| # | Card | Deck page content = hero + (existing screen content, verbatim unless noted) |
|---|---|---|
| 01 | UPLINK | Hero: concentric rings + orb (paired: lit accent; unpaired: muted — prototype's `up.r*`/orb states), title, status (`LINKED · DIRECT` / `NOT LINKED · ON-DEVICE ONLY` etc. from inventory §2's link panel logic), chip `CONNECTION`. Content: inventory §2 rows 3–10 (nudge, Base URL, API Key + Save + paywall gate, Pairing & Devices, Test Connection + status row). |
| 02 | SERVER | Hero: stacked profile-bar motif, status `<ACTIVE PROFILE> · ACTIVE` / `NO PROFILE CONFIGURED`, chip `BACKEND PROFILES`. Content: inventory §3 in full (profile cards + menus, provisioning message, Add Profile, Auto-connect toggle, alerts, editor sheet). |
| 03 | MODELS | Hero: bar-chart motif, status = active model (`chatStore.activeModelName` else brain label), chip `MODEL CATALOG`. Content: inventory §4 in full (Chat Brain incl. Automatic + PCC quota, freshness bar, host default, provider sections, error panel). `ModelTransitionOverlay` pins to the deck page. Standalone `.settingsModels` sheet keeps presenting the SAME content view (wrapped without deck chrome). |
| 04 | VOICE | Hero: waveform motif, status = engine state line (from `talkStore`), chip `TALK ENGINE`. Content: inventory §7 in full (status group, model & voice read-only group, read-aloud incl. voice picker/speed/personal voice/preview, transcripts, last session, Start Voice Session). |
| 05 | APPEARANCE | Hero: theme spectrum card (current palette gradient, `CHANNEL %02d` from the ThemeChannels index), status `<THEME NAME> · <ACCENT SLOT>`, three accent-slot dots (display only). Content: read-only info rows GLOW (`hudGlowIntensity`, `%.1f×`), GRID (`gridDensity` label), APP ICON (current icon display name) + **OPEN CHANNEL BROWSER** GlowButton → pushes `AppearanceSettingsScreen()` unchanged. No Tuning duplication — tuning stays in the browser's sheet. |
| 06 | PRIVACY | Hero: shield-hatch motif, status `N SENSOR STREAM(S) ACTIVE` / `NOTHING LEAVES THIS PHONE` (count = enabled child streams when master on, else 0), chip `PERMISSIONS`. Content: inventory §8 in full (permissions rows, sensor streaming master+children, location accuracy/sync, App Lock + grace, Spotlight, revoke/reset, Manage in System Settings). |
| 07 | SESSIONS | Hero: stacked-rows motif, status `N SESSIONS · M MSGS` (+ ` · SYNCED` when paired) from the cached async load — render `…` until loaded, chip `STORAGE & DATA`. Content: inventory §9 in full (stat tiles, Show Empty Sessions, Recent, Export, Clear + alert). NO fictional storage bar — real counts only. |
| 08 | ABOUT | **The merge.** Hero: sparkline motif, status `ALL SYSTEMS HEALTHY` / `1+ WARNING` (health verdict), chip `DIAGNOSTICS`. Content, in order: Diagnostics status panel (Hermes API / Relay Link / Relay Identity / Location — inventory §10a); `// Voice / Talk` diag rows (§10b); `// Sensor Pipeline` (§10d); info grid (App Version / Host Version / Uptime / Device — §10e); `// Logs` placeholder (§10f); Terms · Privacy · Support links (§10g); footer `TALARIA v<version> · DEVICE-BOUND` (absorbed from old root). |
| 09 | DEVELOPER | Grid shows a compact full-width row (label + environment value + chevron), not a card — per prototype. Deck page hero: grid-of-squares motif, status `<ENVIRONMENT> ENVIRONMENT`, chip `INTERNAL TOOLS`. Content: inventory §11 in full (environment, flags incl. Verbose Logging + Writing Tools warning, GenUI DEBUG, monetization DEBUG, migration DEBUG, build info) **plus the relocated battery harness** (next section). |

### Battery harness relocation (Owen's decision 3)

The entire `// Local brain — #102` DEBUG block (session-shape picker, all battery/
probe launcher buttons, WeatherKit probe, alarm sweep, forced-trip panel, and the
`Battery results →` link to `BatteryResultsScreen`) moves VERBATIM from Diagnostics
into the Developer deck page as a `// Batteries (#200 harness)` section, still
`#if DEBUG`. Pure relocation: no renames, no behavior change, `BatteryResultsScreen`
and children untouched. (They head for deletion eventually; until then they live
where internal tools live.)

### What gets deleted / retired

- `SystemSettingsScreen.swift` — replaced by `SettingsChannelsScreen`. Its host
  panel's information is absorbed by the Uplink card/hero; its footer moves to grid
  + About; its `sessionCount` caching pattern moves to the Sessions card.
- `DiagnosticsSettingsScreen.swift` — content split: diagnostics → About page,
  batteries → Developer page. File retired after the split.
- `SettingsScreenHeader` usage on deck pages — the deck top bar replaces per-screen
  headers. The component itself may remain for `AppIconSettingsScreen` and any pushed
  child screens.

Unchanged: `AppearanceSettingsScreen`, `AppIconSettingsScreen`,
`ConnectHermesHostScreen` (router-level), `ModelTransitionOverlay`,
`BatteryResultsScreen` family, all sheets (ProfileEditor, ConnectedPaywall, Tuning,
ShareSheet) and all `.alert` confirms.

### The unpaired upgrade entry

The root's `Connect Hermes Desktop` row (inventory §1 row 1) becomes a full-width
**upgrade banner card above the grid**, visible only when `!pairingStore.isPaired`
(1a's dashed-border card style; title `Connect Hermes Desktop`, subtitle "Adds server
sessions, sensors & desktop models", `UPGRADE` badge). Tap → `router.dismissSheet()` +
`.navigate(.connectHost)` exactly as today. Its accessibility label MUST keep
containing "Connect Hermes Desktop" and "UPGRADE" (tests match by containment; the
paired-relaunch test asserts its absence).

### Grid card anatomy & telemetry

Card = 16pt-radius `.hudPanel`-style tile, 2-column `LazyVGrid`: corner index number
(`01`–`08`, accent when the subsystem is "active/healthy", muted otherwise, mirroring
the prototype), decorative motif (rings/bars/hatch per prototype — drawn with plain
shapes, `accessibilityHidden`), title, one-line value MonoLabel. Values (all from
inventory §13, all free except Sessions):

| Card | Value (live) | Accent condition |
|---|---|---|
| UPLINK | `DIRECT` / `RELAY` / `STANDBY` / `OFFLINE` / `NOT LINKED` (root row 2's exact logic; no latency figure — that's Test Connection's job) | linked |
| SERVER | active profile name / `NO PROFILE` | has active profile |
| MODELS | `chatStore.activeModelName` / brain label / `SELECT` | model known |
| VOICE | `READ-ALOUD ON/OFF` when idle; engine state when a session is live | readAloud on or session live |
| APPEARANCE (hero-gradient card) | `<THEME> · CH %02d` on the current palette's gradient | always |
| PRIVACY | `N STREAM(S)` / `0 STREAMS` | N > 0 |
| SESSIONS | `N · SYNCED` (paired) / `N SESSIONS` (local) / `…` until loaded | loaded |
| ABOUT | `HEALTHY` / `DEGRADED` | healthy |
| DEVELOPER (row) | environment label | never (muted) |

This kills the two hardcoded root values ("REACTOR", "REALTIME") — every card value
is real state. **Real data only: any value not knowable renders `—`/`…`, never a
placeholder.**

### Reality substitutions vs the prototype (binding)

- No "Talaria 3B/8B", no model downloads, no GET buttons. Models page = the real
  FoundationModels brain rows + PCC quota + live gateway roster (inventory §4).
- No ON-DEVICE/AUTO/SERVER segmented control — the existing Chat Brain picker IS the
  routing surface (its "Automatic" is reachability-based; per-message AUTO is #253).
- No fictional voices/retention rows — Voice page carries the real read-aloud
  controls; server voice remains read-only ("managed on the Hermes host").
- No fictional pairing progress theater — PAIR HERMES DESKTOP on the Uplink page is
  the real `Pairing & Devices` route (`.connectHost`), not an inline animation.
- No latency/"12 MS" claims anywhere a real probe doesn't back them (Test Connection's
  measured `ONLINE · N MS` is the only latency figure, where it appears today).

## Accessibility & test contract

- Introduce identifiers (new, stable): `settings.grid`, `settings.card.uplink|server|
  models|voice|appearance|privacy|sessions|about`, `settings.row.developer`,
  `settings.deck.counter`, `settings.deck.page.<name>`, `settings.upgradeBanner`.
- Preserve these exact label substrings (containment-matched today): `"Open settings"`
  (chat gear — untouched), `"Connect Hermes Desktop"`, `"Pairing & Devices"`,
  `"Disconnect"`, `"Next theme"` / `"Back"` / `appearance.channelCounter` (browser,
  untouched).
- UI-test updates required (inventory §14): `testMockPairingViaSettingsEntryPoint`
  (banner instead of row — containment still works), `testPairedRelaunchSkipsPairingEntry`
  (absence assertion unchanged), `testDisconnectReturnsToStandaloneChat` ("Hermes
  Host" row → `settings.card.uplink`, then "Pairing & Devices" on the deck page),
  `testAppearanceChannelBrowserAppliesThemeOnLand` ("Appearance" row →
  `settings.card.appearance` → OPEN CHANNEL BROWSER → counter assertion). New tests:
  grid↔deck toggle, swipe/page navigation + counter, upgrade banner presence rules,
  battery section reachable under Developer in DEBUG.
- Deck paging must remain functional under VoiceOver (page dots are buttons, as in
  the prototype; cards/pages get `.accessibilityElement(children: .contain)`).

## Staged build (each stage independently shippable, gate before each PR)

1. **Shell** — `SettingsChannelsScreen` with grid + deck containers; deck pages embed
   the EXISTING sub-screens' content views (headers suppressed); cards carry live
   telemetry; upgrade banner; root swap behind it all. Old screens still exist.
2. **Heroes** — per-page hero conversion (visual + status + chip), page-by-page;
   `SettingsScreenHeader` retired from deck pages.
3. **The merge** — About page assembled; battery harness relocated to Developer;
   `SystemSettingsScreen` + `DiagnosticsSettingsScreen` deleted; `xcodegen` regen.
4. **Tests & polish** — UI-test rework per the contract above; reduce-motion audit;
   iPad pass; a11y pass.

Bars pre-register in OPEN_ITEMS #252 at plan time, before any build runs. Candidate
bars (to be finalized in the entry): **252-A** grid presents nine live-value cards
(sim UI test); **252-B** deck swipe + counter + grid toggle round-trip (UI test);
**252-C** control-parity checklist — every inventory §1–§11 control reachable in the
new IA (manual checklist against the companion doc, device); **252-D** DEBUG build
reaches the battery harness under Developer and a battery run still captures
(device); **252-E** the four updated pairing/appearance UI tests green; **252-F**
Release build green (a #218-class gate — the harness relocation moves `#if DEBUG`
boundaries).

## Out of scope

#253 AUTO routing; 1b settings search (possible follow-on); any change inside the
#244 channel browser, App Icon screen, or `ConnectHermesHostScreen`; #250's icon
artwork (sequence deliberately — it touches the App Icon surface this lane leaves
alone); monetization gating logic (gates are preserved, not redesigned).
