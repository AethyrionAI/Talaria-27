# FABLE — Lane E, Batch 4: Claude-Design Special Editions (Midnight Aquarium · Molten Forge · Haunted VHS)

**Repo:** `AethyrionAI/Talaria-27` · **Branch:** `claude/t27-lane-e3-batch4` off `main` ·
**One PR to `main`, do not merge** — Owen's device verdict gates, per house rule.
Pin every `gh` with `--repo AethyrionAI/Talaria-27`. Fable = implement + Swift Testing;
the Mac loop builds/verifies (cloud cannot compile).

## Source of truth + FORMAT NOTE (different from the old gallery)

`design/themes/theme-midnight-aquarium.html` · `theme-molten-forge.html` ·
`theme-haunted-vhs.html` — **Claude Design exports**, not the old gallery format:
- Styles are INLINE on elements (no CSS classes to grep — read the elements).
- `<sc-if value="{{ showX }}" hint-placeholder-val="{{ true }}">` wraps optional
  layers — placeholder default `true` means THE LAYER SHIPS. Do not treat as absent.
- `style-before="…"` attributes carry `::before` pseudo-element styles verbatim.
- `@keyframes` live in the single `<style>` block; element `animation:` props bind them.

## THE RECIPE IS LAW (OPEN_ITEMS #91 — every rule was paid for on device)
1. Specks = soft blurred points (never hard discs; CSS `transparent Npx` is a fade).
2. Panel/card/bubble washes NEVER become screen-scale pools.
3. Port the FULL element inventory — enumerate every layer/keyframe per theme in the
   PR (ported / deferred-with-reason / N/A). The `.spin-ring` lesson.
4. Numbers verbatim; perception tuning via preset knobs, never silent value changes.

## Owen's decisions (final, do not re-litigate)
- **All three ship as SPECIAL EDITION** (join Event Horizon, Graffiti Galaxy,
  Karaoke Supernova in `ThemeCatalog.specialEdition`).
- **Molten Forge stays despite the Solar Forge identity lane.** Differentiation
  mandate: its accent VARIANTS must use hues Solar Forge's variants do NOT —
  "pick variants that don't exist for maximum difference." Diff both variant sets
  in the PR to prove zero hue overlap.
- **Moon jelly is its own new `ThemeOrbStyle` case** — `.anglerLure` STAYS an
  intentional orphan (update the orphan set in `galleryOrbStylesAreNeverShared`
  only by ADDING the three new cases as owned, anglerLure unchanged).

## Per-theme mapping (from the pre-dispatch review — verify against the HTML)

**Midnight Aquarium** — deep-navy tank (#02050a→#061529), teal/pink/violet biolum.
- `bubbleRise` (3 fixed layers, non-square tiles 130×520 / 170×640 / 210×760,
  UPWARD drift, 14s + an 11s chat-screen pair) → `AtmosphereMotionSpec` with
  `tileHeight` (Karaoke laser machinery), soft specks per rule 1.
- `causticDrift` (repeating-linear ±105° lattices, drifting 16s/12s) →
  `ThemeLineFieldSpec` + **NEW: line-field drift** (see primitives).
- Orb: **NEW `.moonJelly`** — tri-ring (pink solid / teal dashed spinning /
  violet) + teal→pink radial core, `jellyFloat` bob (4s ±8px translateY —
  if orb-level bob needs new machinery, defer the bob with a note; the
  composition itself is the requirement).
- Title glow pink/teal (`ThemeTitleGlow`), gold chip accents.

**Molten Forge** — near-black iron, ember orange #ff6a1a / gold #ffd23c.
- `emberRise` speck layers (upward) → atmosphere motion; consider `emberTint`
  lineage but do NOT reuse Solar Forge values.
- `heatShimmer` — bottom 40-45% linear glow breathing (scaleY, 3.5-4s
  ease-in-out) → **NEW: shimmer/breather** OR approximate with a Phase 2
  pulsing pool anchored below the fold (approximation-first per the Karaoke
  gold-band precedent; note the choice).
- Orb: **NEW `.crucible`** per the HTML composition. Title glow orange/gold.
- Accent variants: prove zero hue overlap with Solar Forge (Owen mandate).

**Haunted VHS** — phosphor green #3bff6f / magenta #ff3bd4 / cyan #35e0ff on tape-black.
- Static specks (green/magenta phosphor) → atmosphere motion (`staticDrift`).
- CRT rows (1px dark / 3px pitch) → `scanlineOverlay` VERBATIM (exists).
- `trackingBar` — glowing horizontal band sweeping vertically → one
  `AtmosphereMotionSpec` bar layer with vertical drift (laser machinery);
  if the band's gradient profile can't be expressed, that's the third
  new-primitive candidate — note honestly.
- `vhsJitter` title (±3px magenta/cyan chromatic split, periodic) →
  `ThemeTitleShadowSpec` with `glitchPeriod` VERBATIM (exists — Glitch Garden).
- `recBlink` REC chip → `cornerRibbonSpec` + **NEW: blink affordance**
  (optional `blinkPeriod` on the ribbon; nil = static, byte-identical).
- Orb: **NEW `.phosphor`** per the HTML.

## New primitives (small, follow the house shape)
Each: `Equatable, Sendable` spec, all-optional field on `ThemeArtDirection`,
nil = byte-identical, reduce-motion honored, renderer in `ThemeTextures.swift`
(Canvas/TimelineView, batched draws, perf-first), nil-default + pinned tests.
1. **Line-field drift** — optional drift on `ThemeLineFieldSpec` (caustics).
2. **Shimmer/breather** — only if the pulsing-pool approximation fails on read.
3. **Ribbon blink** — optional `blinkPeriod` on the corner ribbon (REC).

## Guardrails (unchanged)
Never touch `ChatScreen.swift`. Themes without new specs byte-identical.
Widget target compiles (new `ThemeOrbStyle` cases → exhaustive switches).
File-scoped commits; no pbxproj in feature commits; flag any new files.
No mock data. Reduce Motion everywhere. Icon SVGs: flag as missing alongside
the existing three (graffiti/karaoke/event-horizon), don't fabricate.

## Definition of done
One open PR: 3 SE themes + orb cases + the minimal new primitives + element-
inventory disposition table + Solar-vs-Molten variant-hue diff + tests, as
discrete commits. Not merged — Owen's twelve-eyes… well, six-eyes verdict gates.
