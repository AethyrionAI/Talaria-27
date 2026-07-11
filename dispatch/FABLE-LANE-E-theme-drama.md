# Lane E — Theme Drama, Phase 1: prove the bar on Event Horizon

**Repo:** `AethyrionAI/Talaria-27` · **Branch:** `claude/t27-theme-lane-e` off `main` · **PR to:** `main` · **Do not merge.**

## Mission

Event Horizon is selectable and on-device, but Owen's verdict was "not as drastic as I had hoped."
Root causes are verified at HEAD (`4098322`):

1. **No motion.** The handoff's drama is a 4-layer parallax starfield drift; the app renders a
   static-ish field. No animation engine exists (`TimelineView` appears only in the ember drift
   in `ThemeTextures.swift`).
2. **No bespoke orb.** `ThemeOrbStyle` has only the four flagship cases; Event Horizon's palette
   maps `orbStyle: .arcReactor`. The singularity orb from the handoff was never wired.
3. **Conservative values.** The one existing art-direction override (`.eventHorizon` in
   `Talaria/Core/ThemeArtDirection.swift`) translated the handoff quietly.

This lane fixes all three for Event Horizon and restructures the catalog taxonomy, establishing
the repeatable recipe for the remaining ~10 gallery themes (Phase 3, separate lane).

**Source of truth:** `design/themes/theme-event-horizon.html` (committed alongside this spec;
the full 17-theme gallery lives in `design/themes/`).

## Task 0 — Catalog taxonomy (data + picker sections)

`ThemeCatalog` currently has `flagship` + one `special` list holding both the seasonals and the
complex four. Restructure to mirror the gallery taxonomy:

- `flagship` — unchanged (Deep Field, Solar Forge, Terminal, Paper Tape).
- `neonArcadeCollection` — Cereal Box, Bubblegum Mecha, Retro Sci-Fi (Neon Arcade #01 itself and
  the remaining seven join in Phase 3).
- `specialEdition` — Event Horizon (Graffiti Galaxy and Karaoke Supernova join in Phase 3).
- `seasonal` — the four seasonals, keeping their `.seasonal(...)` availability.

The Appearance picker renders these as titled sections: **Flagship / Neon Arcade Collection /
Special Edition / Seasonal**. Keep `ThemeDefinition`, availability, and `locked` semantics
unchanged; update `ThemeCatalogTests` intentionally to the new grouping. `availableDefinitions(on:)`
behavior must be preserved.

## Task 1 — Atmosphere motion engine (the headline)

Add a data-driven animation spec to the art-direction layer and a renderer for it.

**Schema** (in `Talaria/Core/ThemeArtDirection.swift`): an optional `atmosphereMotion` on
`ThemeArtDirection`. Suggested shape:

```
struct AtmosphereMotionSpec {
    struct Layer {
        let tileSize: CGFloat        // px
        let driftPerLoop: CGVector   // px displacement over one period
        let hue: Color               // speck color
        let speckAlpha: Double
    }
    let layers: [Layer]
    let period: TimeInterval         // seconds per loop, linear, infinite
    let fieldOpacity: Double
}
```

Default `nil` → current static rendering, byte-identical for every theme without a spec.

**Renderer:** in `Talaria/Core/HUD/ThemeTextures.swift`, colocated with the existing ember-drift
pattern. `TimelineView(.animation(minimumInterval: 1.0/20.0))` + a single `Canvas`; tile each
layer's specks and translate by `driftPerLoop * (t / period)` mod tile bounds. No per-speck views.
Honor `accessibilityReduceMotion` → freeze at t = 0. **No motion code in
`Shared/ThemePaletteCore.swift`** — the shared layer stays widget-safe and pure.

**Event Horizon values** (verbatim from the handoff's `.page-bg` + `starfieldDrift`):

| Layer | tile | drift/loop | hue | alpha |
|---|---|---|---|---|
| 1 | 90px | (+90, +90) | violet `rgba(138,92,255)` | 0.12 |
| 2 | 120px | (−120, +120) | cyan `rgba(0,240,255)` | 0.10 |
| 3 | 150px | (+150, −150) | gold `rgba(255,220,80)` | 0.08 |
| 4 | 110px | (−110, +110) | magenta `rgba(255,42,168)` | 0.10 |

Period **24s linear infinite**, field opacity **0.45**.

**Presets:** expose one constant selecting between three presets so Owen can A/B on-device
without a round trip: **A faithful** (values above) · **B punchy** (fieldOpacity 0.65, period 18s,
speck alphas ×1.5) · **C subtle** (fieldOpacity 0.35, period 30s). Ship with A selected.

## Task 2 — Singularity orb

- Add `.singularity` to `ThemeOrbStyle` in `Shared/ThemePaletteCore.swift`; confirm the widget
  layer (`TalariaWidgets/WidgetTheme.swift`) still compiles/switches exhaustively.
- Flip Event Horizon's palette definition to `orbStyle: .singularity`.
- Author the composition in `Talaria/Core/HUD/ReactorOrb.swift`, matching the handoff:
  - **Core:** radial gradient gold → magenta (circle at 30% 30%), `singularityPulse` — 4s
    ease-in-out, scale 1→1.1, brightness 1→1.25.
  - **Rim:** 2pt Hawking-cyan ring at inset −8, counter-pulse 3.5s ease-in-out **reverse**
    (scale 1→1.05, opacity 0.5→0.7).
  - **Accretion ring:** slow rotation, `horizonSpin` 30s linear, multi-hue sweep
    (violet/cyan/gold/magenta).
  - **Glow:** layered shadow — magenta 30px + violet `rgba(138,92,255,0.4)` 60px.
- **Check for remnants first:** CR PRs #56 (singularity orb) / #58 (lensing spoke) added related
  rendering that may exist unwired in the tree. Reuse if present; report findings either way.
- Both the Appearance preview card and the HUD route through `orbStyle`, so both must show it.

## Task 3 — Intensity pass

Diff every value in the `.eventHorizon` override in `Talaria/Core/ThemeArtDirection.swift`
against `design/themes/theme-event-horizon.html` — glow-pool opacities, speck counts, panel-halo
strength, neon title glow (layered violet+cyan shadows). Push conservative translations up to the
handoff's levels. List before/after values in the PR description.

## Guardrails

- **Never touch `ChatScreen.swift`** — Lanes A and C own it; this lane must stay mergeable in any
  order relative to A–D.
- Themes without a motion spec render **byte-identical**. `DesignThemeTests`,
  `ThemeArtDirectionTests` stay green; `ThemeCatalogTests` updated only for the Task 0 taxonomy.
- File-scoped commits, one per task. **No `xcodegen` output / `project.pbxproj` in feature
  commits.** Prefer extending existing files; if a new Swift file is unavoidable, flag it
  prominently in the handoff note (the Mac session runs `xcodegen generate` + the
  `aps-environment` entitlement check).
- Honor reduced motion everywhere. No mock data. Performance first — the field renders behind a
  scrolling chat; if in doubt, fewer/cheaper layers.
- Cloud sessions cannot build. Note compile-risk areas honestly in the handoff; the Mac
  review-then-build loop verifies against the iOS 27 SDK (`DEVELOPER_DIR` → Xcode-beta).

## Definition of done

An open PR from `claude/t27-theme-lane-e` containing Tasks 0–3 as discrete commits, plus a
handoff note covering: the preset knob location and the three preset values, findings on PR
#56/#58 remnant reuse, any new files needing pbxproj wiring, and anything unverifiable from the
cloud. Not merged.
