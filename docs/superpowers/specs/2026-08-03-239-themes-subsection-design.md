# #239 — Themes as a tappable sub-section inside Appearance — Design

**Date:** 2026-08-03 (night) · **Approved by Owen:** design approved in
conversation same night ("Spec approved, build it. Make sure the new page is
covered for theme changes too"). Owen-originated: *"we may want to put Themes
in a tappable section inside Appearance. It takes up so much, that folks won't
realize there are other options."*

## Problem

`AppearanceSettingsScreen` stacks the theme card groups (plus the seasonal
auto-rotate toggle) and the accent swatches above Glow, Grid, App Icon, and
the feel toggles (Reduce Motion, Haptic Feedback). The cards dominate the
scroll; a first-time visitor never discovers the rest. Post-pivot this is a
launch-quality concern.

## Design

- **Appearance (top level) keeps:** `SettingsScreenHeader`, `previewPanel`
  (live (theme, accent) mirror — unchanged), **new Themes navRow**,
  `glowSection`, `gridSection`, `appIconRow`, `togglePanel`. The navRow
  mirrors `SystemSettingsScreen`'s private `navRow` idiom (NavigationLink +
  iconTile + MonoLabel value + chevron; icon `paintpalette`).
- **Themes navRow value** (pure helper, unit-tested): seasonal rotation ON →
  `"<SEASON> · <THEME>"` (e.g. `SUMMER · DEEP FIELD` — same composition the
  seasonal toggle subtitle uses today); OFF → the theme display name
  uppercased. Reuses `ThemeCatalog.season(on:)` + `displayLabel`.
- **New `ThemesSettingsScreen`** (pushed by the row) owns, moved verbatim:
  the theme card groups (`themeSection` incl. the seasonal auto-rotate
  toggle, #24) and `accentSection` (with the existing Terminal locked-accent
  rule — accents hidden when `lockedAccentSlot != nil`).
- **Live re-skin on the new page (Owen's explicit requirement):** the
  sub-screen carries its own `HUDScreenBackground` + theme-resolved tokens
  and observes the same settings store the parent does, so tapping a theme
  card re-skins the sub-screen immediately — identical behavior to today's
  single screen, now proven by 239-B.
- **No behavior change:** same settings keys, same `ThemeRuntime`
  resolution, pure relocation. `DesignThemeTests` byte-identity guard
  untouched.

## Bars — pre-registered in the #239 entry BEFORE the run

- **239-A (suite, TDD watched RED):** pure navRow-value helper — manual mode
  returns the uppercased theme name; seasonal mode returns
  `"<SEASON> · <THEME>"` for a fixed date.
- **239-B (XCUITest, new walk):** launch fresh context → Settings →
  Appearance & HUD → Themes → tap a different theme card by accessibility
  label → the sub-screen re-skins (selection applies) → pop back → the
  Themes navRow value shows the NEW theme's name. This is the "new page
  covered for theme changes" requirement made mechanical.
- **239-C (device, Owen, observational):** Appearance opens compact (row
  instead of card wall); theme switching from the sub-screen re-skins live;
  Glow/Grid/App Icon/toggles visible without scrolling past cards.
- Gate (Debug suite + Release) before PR; suite delta counted first
  (swift-testing pin 1555 + helper tests; XCUITest `Executed` count 9 + 1).

## Out of scope

Renaming the SystemSettingsScreen "Appearance & HUD" row or its hardcoded
"REACTOR" value; any theme/palette data change; widget theme pickers.
