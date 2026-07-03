# Talaria Theme System — Implementation Plan (Revised)

**Status:** Reviewed against the codebase 2026-07-03 and revised. Original draft co-authored
with Hermes; this revision corrects ground-truth facts, resolves the open design questions,
and re-scopes the widget work around the target that already exists.

**Goal:** Evolve Talaria's accent-swap system into a full theme system with four distinct
visual personalities — **Deep Field**, **Solar Forge**, **Terminal**, **Paper Tape** — each
owning its color environment, background atmosphere, and reactor-orb identity, with the
existing accent picker re-interpreted per theme.

**Verdict: feasible, and the codebase is unusually well prepared for it.** The token layer
is already centralized and live-observable; view code is effectively 100 % token-pure
(raw hex exists in only 3 files, all with a reason). No server changes. CarPlay untouched.

---

## 1. Verified ground truth (corrections to the draft)

The draft was written from memory of the codebase; these facts were verified on
`main`/`claude/theming-options-plan-c4356l` and change parts of the plan:

1. **Tech stack:** deployment target is **iOS 26.0**, **Swift 6.2 with
   `SWIFT_STRICT_CONCURRENCY: complete`**, Xcode 26.3 beta (not "iOS 17+"). Strict
   concurrency shapes the `ThemePalette` design (§4.2): store `Color`s and scalars, not
   gradient values.
2. **The color audit (draft Task 6) is already ~done.** `Color(hex:` appears in exactly
   3 files: `Design.swift` (the tokens themselves), `AppearanceSettingsScreen.swift`
   (4 uses, local preview helpers), and `ModelTransitionOverlay.swift` (1 scrim color).
   The remaining `.white`/`.black` literals are intentional (fullscreen image viewer,
   camera backdrop, Live Activity previews) except `VoiceState.swift:40` (disconnected
   pip) and the orb's specular highlight, which should become tokens.
3. **A widget target already exists**: `TalariaWidgets` (app-extension) with
   `HermesStatusWidget`, `HermesHealthWidget`, and `HermesLiveActivity`, fed by
   `SharedWidgetDataStore` (App Group UserDefaults, `group.org.aethyrion.talaria`).
   Today they use plain system styling (`Color(.systemBackground)`, `.green`/`.gray`
   pips) — no HUD identity at all. The widget task is therefore *"bring the design
   system to the existing widgets + add a theme intent parameter"*, not "create widgets"
   (§6). The draft's new Voice/Inbox widgets are deferred to a follow-up.
4. **`ThemeRuntime` wiring already exists** at `AppEntry.swift:86` and
   `AppContainer.swift:106` (`ThemeRuntime.shared.apply(settings)`), and the Observation
   pattern already re-skins every token-reading view live. Nothing new is needed at the
   app root except widening `apply(_:)`.
5. **`ThemeRuntime.warning`** (the forge/amber swap under the amber accent) lives outside
   the palette today — it folds into `ThemePalette` as planned.
6. **`Design.Colors` statics that must become theme-aware:** `background`, the
   foreground ramp (6 values), `surface`, `chipSurface`, `divider`, `chipBorder`,
   `danger`, `dangerBright`, `scrim`, `drawerGradient`, `screenGradient`. All become
   `@MainActor static var` computed off the palette — the `accentTint(_:)` /
   `cyanHairline` precedent proves the pattern compiles cleanly under strict
   concurrency, including as default argument values in view initializers.
7. **`cyanHairline` → `hairline` / `cyanBorder` → `strongBorder` rename** touches
   **64 call sites across 37 files** — mechanical (sed + build check), but budget for it.
8. **`project.yml` uses directory-based sources** (`path: Talaria`), so new files under
   existing target folders need only `xcodegen generate` — no project.yml edit. The one
   exception is the **shared palette file for the widget target** (§6.2), which needs a
   new `Shared/` source entry in *both* targets, i.e. one deliberate project.yml edit.

---

## 2. Design principles (unchanged, plus two)

1. **Theme ≠ Accent.** A theme is a complete environment; the accent is the energetic hue
   inside it.
2. **Tokens are the source of truth.** Every theme-able property resolves through
   `ThemeRuntime`. No raw values in view code.
3. **Drastic but legible.** Bubbles, code blocks, pips, and danger states must read in
   every theme.
4. **No pixel assets.** All theme effects are shapes/gradients/`Canvas`.
5. **CarPlay neutral.** CarPlay keeps the system template; widgets carry the personality.
6. **No migration debt.** Persisted values (`appearanceAccent` raw strings) do not change
   meaning-of-storage; themes re-interpret them (§3.5).
7. **Photosensitivity-safe.** No flicker effects. Texture motion (ember drift, scan
   sweep) is gated behind Reduce Motion; static textures are always allowed.

---

## 3. The four themes

Palette values below are starting points — expect tuning on device (Task 8).

### 3.1 Deep Field (default — current look, byte-identical)
- **Background:** radial `#0C2730 → #070D15 → #04070C` over `#06080C` (current values).
- **Foregrounds:** current slate-cyan ramp. **Surfaces/hairlines:** current values.
- **Accents (slots, §3.5):** Cyan·Arc (hero) / Amber·Forge / Violet·Flux — unchanged.
- **Grid:** current 26 pt line grid. **Orb:** current arc-reactor. **Texture:** optional
  faint starfield dots (static).

### 3.2 Solar Forge
- **Vibe:** industrial forge — brass, ember, warm metal.
- **Background:** radial `#2A1A0C → #120C07 → #080602`. **Foregrounds:** warm cream ramp
  `#F5E8D8 / #B8A58F / #7D6B5A`. **Surfaces:** `#1A140E` @ 60 %.
- **Accents:** Forge Amber (hero) / Plasma Cyan / Violet Flux.
- **Grid:** warm brass lines. **Orb:** heavier concentric rings, ember core.
- **Texture:** slow-drift ember particles (motion-gated; static ember specks under
  Reduce Motion). No heat shimmer in v1.

### 3.3 Terminal
- **Vibe:** CRT phosphor. **Background:** true black `#000000`.
- **Foregrounds:** phosphor ramp derived from the active accent hue (green ramp for the
  hero slot). **Surfaces:** `#0A0F0A` @ 70 %. **Hairline:** accent @ 25 % (stronger).
- **Accents:** Phosphor Green (hero) / Amber Phosphor / IBM Cyan.
- **Grid:** off by default; "faint/bold" render a phosphor **dot grid** instead of lines.
- **Orb:** blocky crosshair glyph with CRT bloom (glow radius up, ring count down).
- **Texture:** subtle static scanlines. **No flicker** (principle 7). More-mono
  typography is out of v1 (§8 Q4).

### 3.4 Paper Tape ⚠ highest-risk theme — built last
- **Vibe:** teleprinter / ledger. **Background:** warm off-white `#F2EFE9`.
- **Foregrounds:** ink ramp `#2B2B2B / #5C5C5C / #8A8A8A`. **Surfaces:** `#E8E4DC` @ 80 %.
- **Accents:** Tracker Red (hero) / Cyan Ink / Amber Ink.
- **Grid:** faint horizontal rules (ledger). **Orb:** sprocket/reel outline, radial ticks.
- **Texture:** paper grain (static Canvas noise) + feed lines.
- **Light-theme mechanics (new in this revision):**
  - The app never sets `preferredColorScheme` today — it is dark purely by token values.
    Add a root-level `.preferredColorScheme(theme.colorScheme)` (`.light` for Paper Tape,
    `.dark` otherwise) so system chrome — keyboard, sheets, context menus, `Toggle`/
    `Slider` internals, `ShareLink` UI — follows the theme.
  - `hudGlow` outer glows look wrong on paper. `ThemePalette` gains a **`glowScale`**
    multiplier (≈ 0.15 for Paper Tape) applied inside `hudGlow`, turning glows into
    faint ink shadows without touching call sites.
  - `danger`/`dangerBright` need dark-on-light variants (`#B3261E`-class red).

### 3.5 Accent model — "three slots, theme-interpreted" (resolves draft Open Q1)

`AppearanceAccent` keeps its three cases and raw values (`cyan`/`amber`/`violet`) — they
become **abstract slots** persisted exactly as today (zero migration, no invalid
cross-theme state):

- **Slot `.cyan` = the theme's hero accent** (Cyan Arc / Forge Amber / Phosphor Green /
  Tracker Red). Users who never touched the picker (the default) automatically get each
  theme's canonical hue — Paper Tape defaults to red *for free*.
- Slots `.amber` / `.violet` = each theme's two alternates (§3.1–3.4).
- A `displayLabel(for theme:)` helper supplies contextual names ("Phosphor · Green",
  "Tracker · Red"); the swatches in Settings render the *resolved* per-theme colors.

Per-theme accent memory (remembering a different slot per theme) is a cheap follow-up
(`accentByTheme` dictionary) but **not v1** — one global slot keeps the model obvious.

---

## 4. Data model changes

### 4.1 `AppearanceTheme` enum — `Talaria/Models/UserSettings.swift`

As drafted: four cases + `displayLabel`, plus (new) `var colorScheme: ColorScheme` and
`var isLight: Bool`. Add `appearanceTheme: AppearanceTheme = .deepField` to
`UserSettings` with `CodingKeys` / `init(from:)` (`decodeIfPresent ?? .deepField`) /
`encode(to:)` / memberwise-init updates — the file's existing pattern makes this
mechanical (see `verboseLogging` as the template).

### 4.2 `ThemePalette` — `Talaria/Core/Design.swift`

Replaces `AccentPalette`. **Strict-concurrency note (revised):** store only `Color`
(Sendable) and scalars. Do **not** store `RadialGradient`/`LinearGradient` values —
gradient *stops* live in the palette; the gradients themselves stay as `@MainActor`
computed vars on `Design.Brand`/`Design.Colors` built from those stops (current
`reactorCore`/`accentGradient` pattern).

```swift
struct ThemePalette: Equatable, Sendable {
    // Environment
    let background: Color
    let screenGradientStops: [(Color, Double)]   // fed into Design.Colors.screenGradient
    let texture: BackgroundTexture               // .none/.starfield/.embers/.scanlines/.paperGrain

    // Foreground ramp (6): foreground, foregroundBright, secondaryForeground,
    // mutedForeground, dimForeground, coolForeground
    // Surfaces & borders: surface, chipSurface, divider, chipBorder, hairline,
    // strongBorder, scrim, drawerGradientStops
    // Accent (resolved slot): base, bright, deep, coreHighlight, coreShadow
    // Semantics: forge, danger, dangerBright
    // Behavior: glowScale (Double), gridStyle (.lines/.dots/.rules/.none), gridCell
}
```

`init(theme: AppearanceTheme, accent: AppearanceAccent)` is one exhaustive switch —
boring on purpose. Deep Field values must stay **byte-identical** to today's constants.

### 4.3 `ThemeRuntime` — `Talaria/Core/Design.swift`

Add `var theme: AppearanceTheme = .deepField`; `palette` becomes
`ThemePalette(theme: theme, accent: accent)`; `warning` folds into the palette; extend
`apply(_:)` with the theme field (same per-field-guard pattern). `Design.Brand.*` /
`Design.Colors.*` resolve through `palette` — ~11 statics become `@MainActor` computed
vars (§1.6). `hudGlow` multiplies by `palette.glowScale`.

Rename `cyanHairline`→`hairline`, `cyanBorder`→`strongBorder` (64 call sites, 37 files —
mechanical sweep in the same commit).

---

## 5. View-layer changes

### 5.1 `HUDScreenBackground` + `GridOverlay` (`HUDComponents.swift:11-55`)
Background reads `palette.background` + gradient (already does via tokens — becomes
theme-aware automatically) and adds the texture overlay. `GridOverlay` switches its
Canvas on `palette.gridStyle`: vertical+horizontal lines (today) / dot lattice
(Terminal) / horizontal rules (Paper Tape) / none. Grid Density pref keeps meaning
(opacity) across all styles.

### 5.2 `ThemeTextures.swift` (new, `Talaria/Core/HUD/`)
`StarfieldTexture`, `EmberTexture`, `ScanlineTexture`, `PaperGrainTexture` as `Canvas`
views behind a single `ThemeTextureView(texture:)` switch. Static by default;
`EmberTexture` drift uses `TimelineView` only when Reduce Motion is off. Seeded
pseudo-random layouts (hash of grid position) so textures are stable frame-to-frame.

### 5.3 `ReactorOrb` (`ReactorOrb.swift`)
Orb reads `ThemeRuntime.shared.theme` internally; the four `Style` presets stay the
public API. Per theme: Deep Field = current drawing (unchanged); Solar Forge = ring
weights up, ember core gradient; Terminal = crosshair/blocky glyph + bloom;
Paper Tape = sprocket outline + tick marks, no glow (glowScale already handles it).
`BreathingCore`/`VoiceCore`/`PingHalo` keep their motion; only shapes/weights vary.

### 5.4 `AppearanceSettingsScreen`
- New **Theme section** above Accent: four preview cards (mini background gradient +
  texture + mini orb + name), selection writes `settingsStore.settings.appearanceTheme`.
- Accent swatches render **theme-resolved** slot colors with contextual labels (§3.5);
  the local `accentColors(_:)` hex helper is replaced by palette lookups.
- The locked Theme row (`AppearanceSettingsScreen.swift:266-275`) becomes live:
  `"\(theme.displayLabel) · \(accent.displayLabel(for: theme))"`.
- Preview panel reflects theme + texture + glow + grid (its hardcoded Deep Field
  gradient at lines 51-52 goes theme-aware).

### 5.5 Remaining literals (the *real* residue of draft Task 6)
- `ModelTransitionOverlay.swift:112` scrim `#06080C @ 0.92` → `palette.scrim`-derived.
- `VoiceState.swift:40` disconnected `Color.white.opacity(0.15)` → new token.
- Keep as-is (intentional): fullscreen image viewer black-out (`MarkdownContentView`),
  camera backdrop (`LiveCameraOverlay`), Live Activity previews (system surface), orb
  specular white (works on all four backgrounds; revisit in Task 8 if Paper Tape says
  otherwise).

---

## 6. Widget layer (re-scoped)

### 6.1 What exists
`TalariaWidgets` target: `HermesStatusWidget` (small + lock-screen accessories),
`HermesHealthWidget`, `HermesLiveActivity` — all `StaticConfiguration`, all system
styling, data via `SharedWidgetDataStore` (App Group). The widget target compiles only
`TalariaWidgets/` sources, so it cannot see `Design.swift` or `ThemeRuntime`.

### 6.2 v1 scope
1. **Shared palette core:** new `Shared/WidgetThemePalette.swift` — the theme/accent →
   color tables only (no `ThemeRuntime`, no textures), compiled into **both** targets
   via a new `Shared/` sources entry in `project.yml` (the one project.yml edit) +
   `xcodegen generate`. `Design.swift` delegates its raw tables here so values are
   defined once.
2. **`WidgetTheme` AppEnum** (`matchApp` default + four themes) and migration of
   `HermesStatusWidget` + `HermesHealthWidget` from `StaticConfiguration` to
   **`AppIntentConfiguration`** so the theme is pickable per widget instance in the edit
   sheet. (Existing placed widgets survive this migration with default parameters.)
3. **`matchApp` resolution:** add `appearanceTheme` + `appearanceAccent` raw values to
   `HermesWidgetData`; the app root calls `WidgetCenter.shared.reloadAllTimelines()`
   when appearance settings change.
4. **Rendering:** `containerBackground` gets the theme gradient; pips/text use palette
   colors; a tiny static orb glyph replaces `HermesBrandIcon` where it fits. Lock-screen
   accessory families stay system-rendered (accented/vibrant modes ignore custom color
   anyway).

**Deferred (follow-up item, not v1):** new Voice-session and Inbox-count widgets from
the draft.

---

## 7. Tasks (revised, with build gates)

Every task ends with the CLI compile check (backgrounded per CLAUDE.md):
`xcodebuild -project Talaria.xcodeproj -scheme Talaria -configuration Debug -destination
'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`. New files ⇒
`xcodegen generate` first. Device verification via `RunProject` at the milestones marked 📱.

| # | Task | Scope notes |
|---|------|-------------|
| 1 | `AppearanceTheme` enum + `UserSettings` persistence | Mechanical; template = `verboseLogging`. |
| 2 | `ThemePalette` + `ThemeRuntime.theme` + `Design` token rewiring + hairline rename | The structural heart. Deep Field must stay byte-identical — verify by running the app before/after. 📱 |
| 3 | `ThemeTextures.swift` + `GridOverlay` styles + `HUDScreenBackground` | Static textures first; motion behind Reduce Motion. |
| 4 | `ReactorOrb` per-theme shapes | Deep Field untouched; three new drawings. |
| 5 | `AppearanceSettingsScreen` theme cards + contextual accents + live Theme row | First end-to-end selectable milestone: Deep Field + Solar Forge + Terminal. 📱 |
| 6 | Paper Tape + light-theme mechanics | `preferredColorScheme`, `glowScale`, danger variants, `ModelTransitionOverlay`/`VoiceState` literals. Sequenced late deliberately. 📱 |
| 7 | Widget theming (§6.2) | project.yml `Shared/` entry + xcodegen; intent migration; matchApp plumbing; WidgetKit previews. |
| 8 | Contrast/accessibility pass, all themes | Chat bubbles, code blocks, status cards, onboarding, Dynamic Type, Reduce Motion. Fix in palette values only. 📱 |
| 9 | Docs: `Design.swift` header, `CLAUDE.md` design-system section, `OPEN_ITEMS.md` entry | Note CarPlay stays system-default. |

Tasks 1–2 are one session; 3–5 one to two; 6 one; 7 one; 8–9 fold into device-testing
sessions with Owen. **No server work, no relay work, no sensor-path risk.**

## 8. Draft open questions — resolved

1. **Paper Tape default red?** Yes — falls out of the hero-slot model (§3.5) with no
   special-casing.
2. **Widget default?** `.matchApp`.
3. **Seasonal themes?** Architecture supports it (one more enum case + palette switch
   arm); not in v1.
4. **`themeFont` (mono Terminal)?** Deferred — typography-wide changes multiply the
   Task 8 test matrix; revisit after v1 ships.
5. **project.yml changes?** Only the `Shared/` sources entry (§6.2); everything else is
   `xcodegen generate` on existing directory globs.

## 9. Risks (revised)

| Risk | Mitigation |
|---|---|
| Paper Tape breaks dark-only assumptions | §3.4 mechanics (`preferredColorScheme`, `glowScale`, danger variants); sequenced last; audit already verified only 2 real literals remain. |
| Deep Field regresses during token rewiring | Byte-identical palette values + before/after device check in Task 2. |
| 64-call-site rename churn | Mechanical sed + compile gate; done inside Task 2's commit. |
| Texture battery cost | Static-first Canvas; motion only via `TimelineView` when Reduce Motion off; low particle counts. |
| Widget intent migration confuses existing placed widgets | `AppIntentConfiguration` defaults preserve current appearance (`matchApp` ⇒ Deep Field until app writes shared state). |
| Strict-concurrency friction on new tokens | Palette stores `Color`+scalars only; gradients stay `@MainActor` computed — the proven existing pattern. |

## 10. Testing

- **`TalariaTests/DesignThemeTests.swift`** (new): all 4×3 theme/accent palettes
  resolve; Deep Field × cyan matches the legacy constants exactly; themes produce
  distinct backgrounds/accents; `ThemeRuntime.apply(_:)` mirrors all five prefs;
  `UserSettings` decoding without `appearanceTheme` defaults to `.deepField`.
- **Manual matrix (with Owen, on whoGoesThere):** Chat (bubbles, code blocks, input
  bar), Talk/voice orb, Onboarding, Settings suite, Sessions drawer — × 4 themes;
  Dynamic Type + Reduce Motion spot checks; widget gallery + edit-sheet theme picker.

## 11. Out of scope (unchanged)

CarPlay visuals · server-side anything · per-theme app icons · paywalls · new widget
kinds (deferred) · per-theme fonts (deferred) · per-theme accent memory (deferred).

## 12. Success criteria

- [ ] Four themes selectable in Settings; entire app re-skins live, no relaunch.
- [ ] Deep Field default is pixel-identical to the pre-theme app.
- [ ] Accent picker functional in every theme with contextual labels; persisted value
      unchanged in format (no migration).
- [ ] No raw hex outside `Design.swift` / `Shared/WidgetThemePalette.swift` /
      appearance-preview helpers.
- [ ] Status + Health widgets render all five `WidgetTheme` options; `matchApp` follows
      the app live.
- [ ] All themes pass the Task 8 legibility pass on device.
- [ ] CarPlay and Live Activity untouched.
