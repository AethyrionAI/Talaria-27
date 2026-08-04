# #244 — Appearance as a full-bleed theme CHANNEL browser (subsumes #243; supersedes #239's sub-screen)

**Date:** 2026-08-04 · **Items:** #244 (umbrella, "It doesn't flow right"), #243 (gallery idea — subsumed), #239 (Themes sub-screen — superseded one day after it shipped; its live-re-skin guarantee carries forward)

**Authority:** Owen's goal-run instruction — "take a look at Claude Design's attempt at an appearance tab settings redesign. Some settings will need to be rehomed. If this is something doable and you like the design, implement that as well." Evaluation: doable (all primitives exist) and good (it answers #244's flow complaint directly). The mockup (`~/Downloads/SettingsRedesign/Appearance Channel.dc.html`) is the design artifact; its three open decisions are resolved below. **Merge remains Owen's.**

## The shape

`AppearanceSettingsScreen` becomes a full-bleed **channel browser**: one theme per channel, the LIVE app chrome as the canvas (the theme applies as you land on it, so the screen you're looking at IS the preview), with every non-theme setting rehomed into a bottom **TUNING** sheet. `ThemesSettingsScreen` (#239) is deleted — the browser replaces both the old preview-plus-panels screen and the day-old grid sub-screen.

### Channel list (pure, testable)

`ThemeChannels.build(on: Date)` → `[Channel]`, where `Channel` is one of:
- `.automatic(resolved: ThemeDefinition)` — **channel 00, ahead of Flagship** (mockup decision 2). Shows the CURRENT season's resolved theme with an "AUTO · SEASONAL" collection chip and the season name in the slot line. Landing on it writes `appearanceThemeMode = .automatic`.
- `.theme(ThemeDefinition, sectionTitle: String)` — the 29 picker identities in catalog section order (Flagship 4 → Neon Arcade 9 → Special Edition 5 → Midnight Marquee 7 → Seasonal 4), filtered through `ThemeCatalog.availableDefinitions(on:in:)` exactly as the grid was. Landing writes `appearanceThemeMode = .manual; appearanceTheme = definition.appearanceTheme` (the same atomic pair #239's card tap wrote).

Counter renders `CHANNEL NN / MM` from the built list's live count (30 today: auto + 29; availability filtering can shrink it — the counter is computed, never hardcoded).

### Channel content (on the live background)

Top bar: back chevron (GlassCircleButton) · "APPEARANCE" + counter · ⟳ random. Center: `ReactorOrb(size: 96, style: .standard)` (the runtime orb — bespoke anatomies free), the theme name in display type, the slot line (accent `displayName` for the active slot — the `ThemeDefinition.subtitle` hero-hue string), the collection chip (section title; `definition.locked` renders the existing lock treatment — inert machinery carried forward deliberately, mockup decision 3). Below: the **spectrum strip** — five swatches (accent `bright`/`base`/`deep`, ramp foreground, background) with hex labels from a resolved-Color→hex helper (real computed values; the palettes store no raw hex — mockup's own noted gap).

**Accent slots (mockup decision 1): three dots UNDER the spectrum** — always visible without opening tuning; each dot fills with `ThemePalette(theme: resolved, accent: slot).base` (slots as THIS theme resolves them, the #239 behavior). Hidden entirely when `resolvedThemeID.lockedAccentSlot != nil` (Terminal), matching the sub-screen's rule.

Bottom: TUNING handle → sheet; then ‹ / **SURPRISE ME** / › (random jumps to a different channel, same as ⟳).

### Paging + apply

`TabView(.page(indexDisplayMode: .never))` over the channels, selection bound to a channel id. **Apply-on-land** (mockup: "applies as you go"): a settled selection change writes the settings pair; the whole app chrome — including this screen's own background — re-skins live (the #239 guarantee, now by construction: the browser has no local palette, it reads the runtime). Opening the screen starts on the channel matching current state (auto mode → channel 00; else the theme's channel). Page-peek slivers are dropped (TabView has no native peek; ‹ › + counter carry adjacency). Reboot flourish: a one-shot vertical sweep band on channel land, gated on `accessibilityReduceMotion || ThemeRuntime.shared.appReduceMotion`.

### TUNING sheet (the rehoming)

`presentationDetents([.height(360)])` + `presentationBackgroundInteraction(.enabled(upThrough:))` so channels stay browsable under it. Contents, top to bottom — every control identical in binding to today's:
1. GLOW slider (0…1.6 step 0.1 → `hudGlowIntensity`) with live value readout
2. GRID segments OFF/FAINT/BOLD (→ `gridDensity`)
3. Reduce Motion toggle (→ `reduceMotion`)
4. Haptic Feedback toggle (→ `hapticFeedbackEnabled`) — non-visual, but TUNING covers feel; stays on this surface rather than migrating screens
5. App Icon row → `AppIconSettingsScreen` pushed inside the sheet's own `NavigationStack`

Dies with the redesign: the 150pt `previewPanel` (the screen is the preview), the `themesNavRow` (+ `themesRowValue` helper and its 2 tests), the read-only Theme·Accent value row (the channel is that info), and the grid-preview opacity table (0.0/0.55/1.0) whose divergence from `GridDensity.gridIntensity` (0.0/0.35/0.8) dissolves because only live values remain.

### Untouched / lockstep

- Persistence fields unchanged (`appearanceTheme`/`appearanceThemeMode`/`appearanceAccent`/`hudGlowIntensity`/`gridDensity`/`reduceMotion`/`hapticFeedbackEnabled`) ⇒ widget lockstep (`updateWidgetData` writes the effective theme) holds by construction; both `HermesWidgetData` copies untouched.
- `ThemeRuntime`, palette catalog, `DesignThemeTests`' invariants (catalog coverage, Terminal lock, adaptive comicBook) untouched.
- Deep Field × cyan byte-identity guarantee unaffected (no palette edits).

## Error handling

No network, no failure states. Alternate-icon errors stay `AppIconSettingsScreen`'s own. Reduce-motion disables the sweep + the orb's implicit animations exactly as the HUD already does.

## Testing (bars pre-register in OPEN_ITEMS #244 before the verification run)

- **244-A (unit):** `ThemeChannels.build` — channel 00 is `.automatic` resolving today's season; order = catalog section order; count = availableDefinitions+1; Terminal's channel reports the locked slot; a holiday-window-filtered date shrinks the list (using the existing availability seam).
- **244-B (unit):** hex helper renders known colors ("#54E6F0" class of values for Deep Field's base) — resolved, not hardcoded.
- **244-C (UI, replaces the #239 test in place):** settings → Appearance → channel browser present (counter visible) → › to Solar Forge's channel → name label renders → back out; app-level theme actually changed (assert via the browser reopening on Solar Forge's channel or an app-chrome signal). Keeps per-channel a11y labels.
- **Counted delta:** DesignThemeTests 25 − 2 (themesRowValue pair) + 4 (channels ×3, hex ×1) = 27 ⇒ swift-testing 1557 + 2 = **1559 expected on this branch**; XCUITest 10 (one replaced in place).
