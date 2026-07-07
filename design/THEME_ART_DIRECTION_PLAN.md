# Talaria Theme Art Direction — Presentation Layer over the Palette Catalog

**Status:** Phase A landed 2026-07-06 (branch `claude/theme-art-direction-tokens-5ygv01`).
**Extends:** `THEME_SYSTEM_PLAN.md` (4-theme system) and `THEME_FRAMEWORK_PLAN.md` (#49
data-driven catalog).
**Written in a cloud session — needs the Mac ritual:** `xcodegen generate` (two new files:
`Talaria/Core/ThemeArtDirection.swift`, `TalariaTests/ThemeArtDirectionTests.swift`), CLI
build, `DesignThemeTests` + `ThemeArtDirectionTests`, then on-device eyes.

---

## 1. Problem

#49 made themes *cheap* (one catalog entry) but not *expressive*: the catalog's vocabulary
is colors plus a closed multiple-choice set (4 textures / 3 grids / 4 orbs) designed around
the original flagships. Recolor themes (seasonal set) port fine; art-directed handoffs do
not. Event Horizon (`theme-event-horizon.html`) is the type specimen — its identity is
mostly **non-color**: drifting four-hue lensed starlight, stacked nebula radial glows, a
violet-rimmed haloed chat frame, a three-ring multi-hue orb around a gold→magenta
singularity core, display typography. The flat port collapsed to "Deep Field in purple"
with **amber forge embers** (EmberTexture hardcoded `Design.Brand.forge`) drifting up a
black-hole void.

## 2. Architecture — two layers, widget-safe

- **`ThemePaletteDefinition`** (`Shared/ThemePaletteCore.swift`) stays the flat, widget-safe
  color table. Unchanged shape; the only shared addition is the `.starfield` texture *case*
  (widgets never draw textures — the shared enum only selects).
- **`ThemeArtDirection`** (`Talaria/Core/ThemeArtDirection.swift`, **app target only**) is
  the presentation payload, resolved via `ThemeRuntime.shared.artDirection` →
  `ThemeArtDirectionCatalog.artDirection(for:)`.

**Inert-default invariant:** every field is optional-with-off-default; a theme without a
catalog entry resolves to `ThemeArtDirection.standard`, which renders byte-identically to
the pre-art-direction app. Deep Field (and all non-Event-Horizon themes) have **no entry**
— guarded by `ThemeArtDirectionTests.onlyEventHorizonOverridesArtDirection` and the
existing `DesignThemeTests` pixel guard.

## 3. Token vocabulary

### Phase A — atmosphere (landed)
| Token | Renders in | Handoff CSS it captures |
|---|---|---|
| `glowPools: [ThemeGlowPool]` (color, unit center — may sit off-canvas, radius fraction) | `GlowPoolField` in `HUDScreenBackground`, between screen gradient and texture | stacked `radial-gradient(... at X% Y%, rgba(...) 0, transparent N%)` washes |
| `emberTint: Color?` | `ThemeTextureView` → `EmberTexture` | warm speck color (nil = legacy forge color, correct for Solar Forge) |
| `starfield: ThemeStarfield` (colors, count, driftScale) | new `.starfield` texture → `StarfieldTexture`, 4 drift layers, 15fps TimelineView, static under Reduce Motion | `.page-bg` four-layer `background-position` pan (`starfieldDrift`) |
| `panelHalo: ThemePanelHalo` (ringColor, glowColor, glowRadius) | `.panelHalo()` inside `HUDPanel` + `.hudPanel` — offset rim ring + outer shadow scaled by glow pref × `glowScale` | `box-shadow: 0 0 0 8px rgba(...), 0 0 50px rgba(...)` framing |

### Phase B — orb (planned)
`orbHues` (outer/mid/inner ring hues, core highlight/shadow pair, halo, glow) + a new
`ThemeOrbStyle.singularity` composition in `ReactorOrb`. Compositions stay **hand-written
Swift** — a parameterized orb DSL was considered and rejected: Claude writes all code
anyway, and hand-tuned layers beat generic parameter soup. The data only supplies *hues*,
letting one composition serve future multi-hue themes.

### Phase C — chrome (planned)
`userBubble` (fill gradient stops + border) consumed by `MessageBubble`; `titleGlow`
consumed by `SettingsScreenHeader` (the handoffs' neon `text-shadow` headings). Custom
display *font families* (Orbitron etc.) are **out of scope** — bundling font files is a
Mac-session task; Chakra Petch already covers the sci-fi display role.

### Phase D — motion/materials (planned, on-device only)
Slow conic "lensing" spoke layer; MeshGradient / Metal `colorEffect` materials. Highest
fidelity, needs per-iteration device eyes — do not write blind in cloud sessions.

## 4. Porting checklist (handoff HTML → theme)

The #54 gallery port only harvested the palette table. A full port reads the handoff's CSS
top-to-bottom and fills **every** row; write "none" deliberately rather than skipping:

1. **Palette table** → `ThemePaletteDefinition` (as before). Slot names: use the handoff's
   theme-native names verbatim in `displayName` ("Accretion Violet", not "Violet · Horizon").
2. `body`/`main` stacked `radial-gradient`s → first stop set = `screenGradientStops`;
   additional washes = `glowPools` (center %, alpha, size fraction map 1:1).
3. Animated `background-image` speck layers (`.page-bg`) → `starfield` colors/drift
   (or `emberTint` if the motif is rising sparks).
4. Container `box-shadow` stacks → `panelHalo` (outer ring width/alpha → ringColor;
   blur radius → glowRadius).
5. Orb markup (`.orb-ring` colors, dash, core gradient) → Phase B `orbHues` (+ new
   composition case only if no existing one fits the geometry).
6. `.message.user` background/border → Phase C `userBubble`.
7. `h1 text-shadow` → Phase C `titleGlow`.
8. Extra accent hues beyond the three slots (e.g. Singularity Magenta) live in art
   direction (starfield colors, orb core, bubble gradient) — **not** in the palette.
9. `@keyframes` → map to existing reduce-motion-aware primitives; never add flicker.

## 5. Event Horizon deltas in Phase A

- Palette: `texture: .embers → .starfield`; slot names → handoff-native.
- Art direction entry: violet bloom pinned above the screen + cyan/magenta pools,
  4-hue starfield, violet panel halo.
- Magenta `#FF2AA8` enters via starfield + pools (palette untouched, widgets unaffected).

## 6. Verification (Mac session)

1. `xcodegen generate` — two new files.
2. CLI simulator build (backgrounded, poll the log — see CLAUDE.md).
3. Run `DesignThemeTests`, `ThemeCatalogTests`, `ThemeArtDirectionTests`.
4. Device: Deep Field must be pixel-identical (no art-direction entry exists for it);
   Solar Forge embers unchanged; Event Horizon shows starfield + nebula + haloed panels;
   Reduce Motion freezes the starfield; Paper Tape panels stay halo-free with glow ≈ 0.
