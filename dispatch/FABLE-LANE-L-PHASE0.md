# Lane L — Phase 0 probe findings (Midnight Marquee)

Probe of the theme system, adaptive-scheme seams, and icon pipeline before any
implementation commit (spec: `dispatch/FABLE-LANE-L-midnight-marquee.md`). The
PR description carries the same findings; this file is the in-repo record.

## 1 · Resolution call sites (the scheme-sensitivity audit)

Every render-identity resolution funnels through **three seams**, all keyed on
`AppearanceTheme.themeID`:

| Site | File | Scheme-sensitive for Comic Book? |
|---|---|---|
| `ThemeRuntime.palette` | `Talaria/Core/Design.swift:387` | **YES** — the palette seam every `Design.Brand/Colors` token + `ReactorOrb` (orbStyle) reads |
| `ThemeRuntime.artDirection` | `Talaria/Core/ThemeArtDirection.swift:984` | **YES** — all HUD art-direction consumers (`ThemeTextures.swift:16,65`, `HUDComponents.swift:25–46,298–345`) read this |
| Root `preferredColorScheme` | `Talaria/Features/Onboarding/AppRootView.swift:33` | **YES** — must return `nil` for the adaptive theme |
| `AppearanceTheme.isLight` | `Talaria/Models/UserSettings.swift:265` | Consulted ONLY by AppRootView:33 + `DesignThemeTests` — keeps schemeless (canonical-variant) semantics once AppRootView special-cases the adaptive theme |
| `AppearanceAccent.displayLabel(for:)` | `UserSettings.swift:302` | Sole caller is `AppearanceSettingsScreen.swift:329` — screen threads a scheme-resolved id instead |
| Picker previews (direct `ThemePalette(theme:accent:)`) | `AppearanceSettingsScreen.swift:31,257,338` | Cards/swatches resolve with the runtime's mirrored scheme |
| `ThemeDefinition.paletteDefinition` | `ThemeCatalog.swift:93` | Schemeless (canonical) — only tests consume it today |
| `ThemeID.lockedAccentSlot` | `Shared/ThemePaletteCore.swift:60` | Both Comic Book variants ship `nil` — no divergence possible |
| `VoiceState.displayColor` | `Talaria/Models/VoiceState.swift:41` | Comment-only: uses `Color.primary`, which follows the root scheme for free |

No other `preferredColorScheme` / `colorScheme` / `isLight` /
`ThemePaletteCatalog.definition(for:)` call sites exist in app code.

## 2 · Widget-side palette resolution

- The app writes `effectiveAppearanceTheme().rawValue` +
  `appearanceAccent.rawValue` into the App Group snapshot
  (`AppContainer.updateWidgetData()`, `Talaria/Stores/AppContainer.swift:1333`).
- `HermesWidgetEntry.palette` (`TalariaWidgets/HermesTimelineProvider.swift:13`)
  → `WidgetTheme.resolvedPalette(data:)` (`TalariaWidgets/WidgetTheme.swift:40`):
  `.matchApp` does `ThemeID(rawValue:)` with a Deep Field fallback. **The raw
  value `"comicBook"` is not a `ThemeID`** — without wiring, the widget would
  silently fall back to Deep Field. Fix: a Shared-level resolver (raw value +
  dark/light → `ThemeID`) used by both targets, and the two consuming views
  (`HermesStatusWidget.swift`, `HermesHealthWidget.swift` — the only
  `entry.palette` readers) pass their own `@Environment(\.colorScheme)`.
- `WidgetTheme` deliberately has **no explicit cases beyond flagship +
  seasonal** — NAC/SE batches never added them; collection themes reach
  widgets via `.matchApp` only. MM follows that shipped precedent (the
  CLAUDE.md "+ a WidgetTheme case" note is stale; repo wins).
- `HermesWidgetData.swift` exists in two lockstep copies (app + widget); the
  snapshot schema (`appearanceTheme: String?`) needs **no change**.

## 3 · Icon pipeline (Lane K, as shipped — differs from the Lane K spec text)

Loose bundle files + `CFBundleAlternateIcons`, NOT an asset catalog:

1. `tools/appicons/render_gallery_icons.py` parses `design/themes/app-icons.html`'s
   `icons[]` (regex-paired `id: '…'` / `svg: \`…\``) → renders
   `Icon-<Name>@2x.png` (120), `@3x.png` (180), `IconPreview-<Name>.png` (240)
   into `Talaria/Resources/AppIcons/` (flat RGB, no alpha). `<Name>` =
   PascalCased gallery id. The script has a hardcoded `ICON_IDS` list to extend.
2. `project.yml` `CFBundleIcons.CFBundleAlternateIcons` (lines ~156–235) **and**
   the hand-mirrored committed `Talaria/Resources/Info.plist` both list every
   icon (`CFBundleIconFiles: [Icon-<Name>]`, `UIPrerenderedIcon: false`).
3. One `AppIconOption` per icon in `Talaria/Models/AppIconCatalog.swift`
   sections; picker renders whatever the catalog lists.
4. `xcodegen generate` after (resources are path-globbed in `project.yml` —
   new PNGs must land in the regenerated pbxproj).

Current state: 18 selectable (1 primary + 17 alternates; 35 icon PNG pairs +
preview files, 55 files). `app-icons.html` already carries **24** `icons[]`
entries including the five SE SVGs (`event-horizon`, `graffiti-galaxy`,
`karaoke-supernova`, `midnight-aquarium`, `molten-forge` — tagged `se: true`,
which the renderer's regex pairing tolerates) and the never-wired
`deep-sea-diner` (theme cut — stays unwired).
`midnight-marquee-app-icons.html` is a canvas-mode doc with **inline `<svg>`
blocks, not an `icons[]` array** — per the spec's stated preference the 8 MM
SVGs get merged into `app-icons.html` as a Midnight Marquee `icons[]` section
(one gallery source for the renderer), verbatim SVG bodies.

## 4 · SE batch-4 precedent (`midnightAquarium` / `moltenForge`)

- **Palette** (`Shared/ThemePaletteCore.swift:1893,1967`): bg1 = `background`;
  `screenGradientStops` = [bg2 @0.0, bg1 @0.52, bg3 @1.0]; `drawerColors` =
  [bg2, bg1, bg3]; ramp = {fg, fg, muted, muted, dim, muted}; `surface` = hero
  @0.08; chips fixed = slot1 @0.08 / slot2 @0.08 / slot3 @0.06; borders
  `.accentTinted(0.14, 0.30)`; scrim black @0.85; grid `.lines`
  `.accentTinted(0.08)` cell 26; glowScale 1.1; handoff-native slot display
  names (EH precedent).
- **Derived family steps — the "house formula"** (reverse-engineered exactly,
  176/180 channels of the shipped derived families byte-exact, 4 channels
  hand-nudged ±1/255): per RGB channel with integer truncation —
  `bright = base + (255−base)·63⁄255`, `deep = base·0.70`,
  `coreHighlight = base + (255−base)·114⁄255`, `coreShadow = base·0.55`;
  `dangerBright = danger + (255−danger)·0.15`. Light themes (Paper Tape
  precedent) invert: `bright = base·0.70` (emphasis = more ink),
  `deep = base + (255−base)·114⁄255` (pale tint), `coreHighlight` = mix 0.90
  toward white, `coreShadow = base·0.55`, `dangerBright = danger·0.78`
  (Paper Tape's exact observed step). Paper Tape's own families are
  hand-curated with no single ratio; the constants above sit at/inside its
  observed ranges and are documented per-entry.
- **Art direction** (`ThemeArtDirection.swift:826,889`): glow pools, ember/
  bubble atmosphere layers (non-square tiles, one-tile-per-loop drift),
  drifting line fields, panel halo at the EH compression (.24 rim, 40
  radius), EH-shape title glow. Vocabulary available: `glowPools` (pulse),
  `starfield`, `panelHalo`, `atmosphereMotion` (specks/bars/halftone via
  `blurScale`, `stepCount` scramble), `radialSpokes`, `lineTexture` (+drift),
  `scanlineOverlay`, `sweepBar`, `titleGlow`, `titleShadow` (+`glitchPeriod`),
  `cornerRibbon` (+blink), `panelTopStrip`. **The MM motifs all fit the
  existing vocabulary — no new primitives needed** (speed lines = angled
  lineTexture; marquee-bulb rows = dot-lattice grid + blink ribbon where
  panel-scope; halftone/Ben-Day = low-`blurScale` dot atmosphere with
  `dotDrift` as slow whole-field drift; ink-shake title = `titleShadow.glitchPeriod`;
  spotlights/searchlight = glow pools + `radialSpokes`).
- **Orbs** (`ReactorOrb.swift:555,571`): the batch-4 tri-ring anatomy — rings
  1.0/0.74/0.48 @ .35/.55/.75, pulse 3.5s staggered 0/.3/.6, dashed middle
  ring spinning (`spinPeriod`), 30% two-hue core `.brighten(4, 1.12, 0.3)`,
  `coreOuterGlow` third hue — **exactly matches all eight MM lineup orbs**
  (verified against every `#1b…2b` orb block: same ring stack, same
  `pulse 3.5s` / `orbSpin` / `corePulse 4s` keyframes, core
  `radial(30% 30%, hueA, hueB)` with `0 0 30px hero, 0 0 60px third@.4`).
  New `ThemeOrbStyle` cases + `TriRingOrbSpec` data + hue enums per theme;
  hand-written extras only where a motif demands it (`moonJellyLayers` bob /
  `cauldronBrewLayers` bubbles are the precedent). Pulp Noir + Sunday Funnies
  cores print with hard ink shadows instead of glow (Paper Tape hub
  precedent) — those two get bespoke treatment.
- **Tests**: `DesignThemeTests` (hero hex, orb style, isLight set, labels,
  catalog coverage), `ThemeCatalogTests` (section membership/order, id ==
  rawValue), `ThemeArtDirectionTests` (deliberate per-theme slot sets — the
  new line-field/scanline/title-shadow/pulse adopters must be added to those
  sets).

## 5 · Comic Book adaptive architecture (verified against the seams above)

- Two `ThemeID`s (`comicVillain` dark / `comicFunnies` light) — plain catalog
  entries; widget table grows by two.
- One `AppearanceTheme.comicBook` (persisted raw `"comicBook"`), one
  `ThemeCatalog` definition in the new Midnight Marquee section.
- `AppearanceTheme.themeID` stays schemeless → canonical **villain** (id
  stability for `lockedAccentSlot`/`paletteDefinition`); new
  `themeID(for: ColorScheme)` diverges only for `.comicBook`. A Shared
  resolver maps snapshot raw `"comicBook"` + isDark → `ThemeID` for the
  widget (the widget target does not compile `UserSettings.swift`).
- `ThemeRuntime.systemColorScheme` mirrored from `AppRootView`'s
  `@Environment(\.colorScheme)`; `palette`/`artDirection` resolve through it.
  **Known nuance:** `preferredColorScheme` loops back into the window's
  environment, so while a forced theme is active the mirror reads the forced
  scheme — harmless: the mirror is only consulted when Comic Book is active
  (root preferred = `nil` → environment IS the system scheme), and picker
  previews rendering with the presented scheme is coherent (a light settings
  surface previews Funnies). Documented, sim-verified on the Mac
  (Developer → Dark Appearance) per spec.
- Live re-skin: environment change → AppRootView `.onChange` → runtime
  mutation → Observation invalidates every palette/artDirection reader.

## 6 · Spec-vs-repo deviations (repo wins)

- Lane K spec described asset-catalog alternate icons; shipped reality is
  loose-bundle `CFBundleAlternateIcons` (§3). Mirrored as shipped.
- CLAUDE.md says new themes add a `WidgetTheme` case; batches 1–4 stopped
  adding explicit widget cases (flagship + seasonal only). MM mirrors the
  shipped decision (§2).
- The spec's `themeID(for:)` sketch is adopted, with the addition of the
  Shared raw-value resolver the widget needs (§5).
- `midnight-marquee-app-icons.html` is not in `icons[]` format — SVGs are
  merged into `app-icons.html` verbatim (§3, spec's stated preference).

## 7 · Hex provenance

Every implemented hex comes from `midnight-marquee-final-lineup.html`
(sections 1b Lucha Libre, 1c Kaiju Attack, 1f Pulp Noir, 1g Casino Lucky 7s,
1j Cosmic Bowling, 1k Sticker-Bomb Toybox, 2a Villain Variant, 2b Sunday
Funnies): backgrounds 1–3, foreground/muted/dim, three accent slots + slot
mapping lines, danger, warning, plus in-mock values (chat-surface hex, status
chip inks, texture/grid dot colors + pitches, orb hue stacks). The only
non-lineup hexes are the mechanical house-formula derivations above, flagged
per entry. `*-options.html` files untouched (rejected alternatives).
