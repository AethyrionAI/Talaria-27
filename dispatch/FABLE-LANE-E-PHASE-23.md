# FABLE — Lane E, Phases 2+3: theme-drama schema extension + gallery port

**Repo:** `AethyrionAI/Talaria-27` · base `main` @ c2a385d (or newer — re-confirm refs at your HEAD).
Pin every `gh` with `--repo AethyrionAI/Talaria-27`. **PRs to `main`, do not merge** — every
theme batch gates on Owen's on-device verdict, same as Phase 1.
**Verification model:** Fable = implement + Swift Testing. Cloud cannot build; the Mac
review-then-build loop verifies against the iOS 27 SDK (`DEVELOPER_DIR` → Xcode-beta).

## Context — Phase 1 verdict and THE RECIPE (non-negotiable)

Phase 1 (PR #66 + verdict corrections) cleared the drastic bar on Event Horizon:
**"Now THAT is an outrageous theme."** It took three on-device correction rounds to get
there, and those corrections are now LAW for every port (OPEN_ITEMS #91):

1. **Specks are soft points, never hard discs.** CSS
   `radial-gradient(circle, hue 0, transparent Npx)` is a FADE-OUT distance, not a solid
   radius. A verbatim hard-disc translation reads as confetti on a 460ppi OLED. Render:
   small center (~1.25pt) + per-layer blur (see `AtmosphereMotionField`), alphas verbatim.
2. **Panel-scope washes never become screen-scope pools.** `card::before`,
   `bubble` and other panel-local gradients belong to panels/bubbles. Promoting them to
   40-60%-of-screen `ThemeGlowPool`s swamped Event Horizon's void-black base into a teal
   wash the design never had. Screen pools = ONLY what the design paints on `body` /
   `.chat-screen` itself.
3. **Port the FULL element inventory.** The original EH port skipped `.spin-ring` — the
   design's single most dramatic chat-surface element. For every theme, enumerate EVERY
   visual element in its HTML (pseudo-elements, keyframes, per-layer backgrounds) and
   account for each one: ported, deferred (say why), or genuinely N/A.
4. Numbers verbatim from the HTML; **perception tuned via the preset-knob pattern**
   (`eventHorizonAtmospherePreset` precedent) — never by silently changing design values.

## Infrastructure you already have (reuse, don't reinvent)

- `AtmosphereMotionSpec` + `AtmosphereMotionField` — tiled parallax drift (soft-speck
  rendering built in), supersedes the palette's static texture when set.
- `RadialSpokeSpec` + `RadialSpokeField` — rotating repeating-conic starburst
  (HUDScreenBackground wiring precedent).
- `ThemeGlowPool` / `ThemePanelHalo` / `ThemeTitleGlow` (+ `hudTitleGlow()`) /
  `ThemeStarfield` / `emberTint`.
- `ThemeOrbStyle` + `ReactorOrb` compositions (`.singularity` = the port precedent;
  widget layer must stay exhaustive-safe — building the app scheme builds the widget).
- Catalog taxonomy sections: Flagship / Neon Arcade Collection / Special Edition /
  Seasonal (`ThemeCatalog`, Phase 1 Task 0).
- Test patterns to copy: nil-default inertness (`radialSpokesDefaultToNil`), pinned
  design values (`eventHorizonIntensitySitsAtHandoffLevels`), byte-identical guarantee
  for themes without specs.

## Phase 2 — schema extension (branch `claude/t27-lane-e2-schema`, ONE PR, lands first)

**Task 0 — Discovery (drives everything).** Inventory ALL 9 unported theme HTMLs
(`design/themes/`): `theme-glitch-garden` · `theme-witchs-brew` · `theme-holo-sushi` ·
`theme-lunar-diner` · `theme-cyber-cactus` · `theme-deep-sea-diner` ·
`theme-disco-inferno` · `theme-graffiti-galaxy` · `theme-karaoke-supernova` — PLUS the
three in-app Neon Arcade recolors that never got drama treatment: `theme-cereal-box` ·
`theme-bubblegum-mecha` · `theme-retro-sci-fi`. Also reconcile "Neon Arcade #01" (named
in OPEN_ITEMS #91 but no standalone file) against `index.html` — report whether it's a
12th portable theme or the gallery chrome itself.
Produce a table in the PR: theme × element (bg layers, pseudo-elements, keyframes,
orb treatment, title/panel treatment) × mapping (existing schema / new schema needed /
panel-scope [recipe rule 2] / N/A).

**Task 1 — Extend the art-direction schema** with ONLY what the inventory demands.
Expected from the #91 notes (verify against the HTML, don't assume): halftone dots,
spray-paint grain, chrome/scanline band textures; additional motion patterns beyond
tiled drift (e.g. pulse/flicker/wave keyframes) as new spec types following the
`AtmosphereMotionSpec`/`RadialSpokeSpec` shape: `Equatable, Sendable`, all-optional on
`ThemeArtDirection`, nil = byte-identical, reduce-motion honored, Canvas/TimelineView
renderers colocated in `ThemeTextures.swift`, no per-element views, perf-first (renders
behind a scrolling chat).

**Task 2 — Orb compositions.** New `ThemeOrbStyle` cases per the inventory + gh#64.
Every case: `Shared/ThemePaletteCore.swift` enum + `ReactorOrb` composition +
`TalariaWidgets/WidgetTheme.swift` exhaustive switch stays compiling.

**Tests:** nil-default inertness for every new spec type; renderer decode/geometry
sanity; catalog invariants unchanged.

## Phase 3 — the port (batched, AFTER Phase 2 merges)

Batches of ~3 themes per branch/PR so the Mac review-build-verdict loop stays tractable:
- `claude/t27-lane-e3-batch1` — Neon Arcade Collection wave 1 (suggest: Glitch Garden,
  Witch's Brew, Holo Sushi) + drama-retrofit Cereal Box / Bubblegum Mecha / Retro Sci-Fi.
- `claude/t27-lane-e3-batch2` — Lunar Diner, Cyber Cactus, Deep Sea Diner, Disco Inferno.
- `claude/t27-lane-e3-batch3` — Special Editions: Graffiti Galaxy, Karaoke Supernova
  (+ Neon Arcade #01 if discovery says it's real). SEs join `specialEdition` alongside
  Event Horizon; collection themes join `neonArcadeCollection`.

Per theme: `ThemeID` case + palette (screen gradient stops, drawer colors, foregrounds,
surface, texture selection) + full art-direction override (recipe rules 1-3) + orb style
+ catalog placement + availability/`locked` semantics preserved + icon pairing noted from
`design/themes/app-icons.html` (icon ASSETS are Mac-side — flag, don't fabricate).
Per batch: pinned-value tests per theme + updated `ThemeCatalogTests` counts
(intentional), and a handoff note listing the element-inventory disposition table,
preset knobs added, any new files (pbxproj wiring is Mac-side), and compile-risk areas.

## Guardrails (unchanged from Phase 1, they all earned their place)

- **Never touch `ChatScreen.swift`.** Themes without new specs render byte-identical —
  `DesignThemeTests` / existing `ThemeArtDirectionTests` stay green except intentional
  count updates. File-scoped commits, one per task/theme. **No xcodegen output /
  `project.pbxproj` in feature commits**; flag new Swift files prominently (Mac session
  runs `xcodegen generate` + the `aps-environment` entitlement check). Honor reduced
  motion everywhere. No mock data. Performance first — fewer/cheaper layers when in doubt.
- Widget target: every `ThemeOrbStyle`/palette change must keep
  `TalariaWidgets` compiling (exhaustive switches).
- Owen's verdict gates EVERY batch — expect correction rounds; the Phase 1 pattern
  (screenshot vs HTML → chase the specific delta) is the loop, not a failure.

## Definition of done

Phase 2 PR open (schema + renderers + orb cases + inventory table + tests), then three
batch PRs open as Phase 2 lands, each with its handoff note. Nothing merged — the
device-verdict gate is Owen's.
