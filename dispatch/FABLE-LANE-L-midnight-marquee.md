# FABLE — Lane L · Midnight Marquee (7 themes / 8 palettes + 13 app icons)

**Repo:** `AethyrionAI/Talaria-27` · **Branch:** `claude/t27-midnight-marquee`
**Type:** theme content batch + one architectural first (the app's first adaptive light/dark theme) + icon batch
**Collision surface:** theme-system files only — `Shared/ThemePaletteCore.swift`, `Talaria/Core/ThemeArtDirection.swift`, `Talaria/Core/HUD/ReactorOrb.swift`, `Talaria/Models/ThemeCatalog.swift`, `Talaria/Models/AppIconCatalog.swift`, `Talaria/Features/Onboarding/AppRootView.swift`, `Talaria/Core/Design.swift`, `project.yml`. **No `ChatScreen.swift`, no relay, no model wiring.**
**OPEN_ITEMS:** #112

---

## Goal

Ship the **Midnight Marquee** collection — a new fifth gallery section of **7 themes** (8 palettes: Comic Book ships dark + light as the app's **first adaptive theme**), each with a bespoke orb and art direction per the shipped SE batch-4 pattern (`moonJelly` / `crucible`). Plus **13 new app icons**: the 5 Special Edition icons `AppIconCatalog` is already reserving a section for, and 8 Midnight Marquee icons.

**Do NOT design a new system.** The SE batch-4 themes (Midnight Aquarium, Molten Forge) are the exact precedent for a standard theme; the flagship + Lane K icon wiring is the exact precedent for icons. Read them end-to-end and mirror. If this spec contradicts the repo, **the repo wins** — parts of this spec are written from a snapshot.

## Sources of truth (committed in `design/themes/`)

- `midnight-marquee-final-lineup.html` — **THE authoritative 8 palettes** (section anchors `1b, 1c, 1f, 1g, 1j, 1k, 2a, 2b`). Full hex palettes, accent-slot mappings, status-chip labels, personality/motion copy.
- `midnight-marquee-app-icons.html` — the 8 MM icon SVGs (1024×1024, full-bleed).
- `app-icons.html` — updated rev; now carries the 5 SE icon SVGs in a Special Edition section.
- `midnight-marquee-options.html`, `se-themes-options.html` — **provenance only, rejected alternatives. Never implement from these.**

## Roster (verify every hex against the Final Lineup file, not this table)

| suggested id | Display name | Palette | Light? | Orb motif (handoff + icon art) |
|---|---|---|---|---|
| `luchaLibre` | Lucha Libre | Rudo Nocturno | dark | rudo mask — royal blue / pyro orange / chrome |
| `kaijuAttack` | Kaiju Attack | Code Red Tokyo | dark | dorsal fins in a siren ring — radioactive green / searchlight amber / siren red |
| `pulpNoir` | Pulp Noir | Dime Novel | **LIGHT** | fedora + teal dime stamp on aged pulp |
| `casinoLucky7s` | Casino Lucky 7s | House Felt | dark | marquee-bulb ring, cherry seven on felt |
| `cosmicBowling` | Cosmic Bowling | Carpet Classic | dark | grape house ball on squiggle carpet |
| `stickerBombToybox` | Sticker-Bomb Toybox | Kidcore Shelf | **LIGHT** | die-cut tangerine star, white sticker border |
| `comicBook` | Comic Book | Villain Variant (dark) + Sunday Funnies (light) | **ADAPTIVE** | POW/ZAP burst — see Phase 2 |

Ids are suggestions — existing enum naming convention wins. Paper Tape is the shipped light-theme precedent for the two light palettes.

---

## Hard rules

- **Probe before building.** Phase 0 findings go in the PR description before any implementation commit.
- **Real data only** — every color hex comes from the Final Lineup. Never invent or eyeball a hex.
- `xcodegen generate` after any Swift file add/remove; verify `aps-environment: development` survives in `Talaria/Talaria.entitlements` after every regen.
- File-scoped commits: `pbxproj` regens isolated; do **not** touch `OPEN_ITEMS.md` in this branch (#112 is session-owned).
- **Deep Field byte-identical guarantee holds** — no behavior change for any existing theme.
- Swift Testing (`@Test`) for new tests; don't mutate state inside `#expect` (macro captures receivers immutably — hoist to locals).

## Phase 0 — probe (mandatory)

1. Enumerate every call site of `AppearanceTheme.themeID`, `.isLight`, `preferredColorScheme`, `ThemePalette(theme:accent:)`, `ThemePaletteCatalog.definition(for:)`. Known: `AppRootView.swift:33` forces `preferredColorScheme` from `theme.isLight`; `ThemeRuntime.palette` (`Design.swift` ~387). Others exist (`VoiceState` references the scheme; the widget target compiles `Shared/ThemePaletteCore.swift`).
2. Find the **widget-side** palette resolution site and note how the widget learns the active theme.
3. Confirm the icon pipeline: `tools/appicons/render_gallery_icons.py` → `Talaria/Resources/AppIcons/Icon-<Name>@2x/@3x.png` + `IconPreview-<Name>.png` → `project.yml` `CFBundleAlternateIcons` → `AppIconCatalog`. Read `dispatch/FABLE-LANE-K-app-icons.md` and the shipped Lane K wiring.
4. Read the SE batch-4 precedent end-to-end: `midnightAquarium` / `moltenForge` across `ThemePaletteCore`, `ThemeArtDirection`, `ReactorOrb`, `ThemeCatalog`.

## Phase 1 — the six standard MM themes

Per theme, mirror the batch-4 pattern exactly:

- `ThemeID` case + `ThemePaletteCatalog` entry (`Shared/ThemePaletteCore.swift`) — `isLight: true` for Pulp Noir and Sticker-Bomb Toybox.
- `AppearanceTheme` case + `themeID` bridge arm (`Design.swift`).
- `ThemeCatalog`: new section **"Midnight Marquee"** (placement: after Special Edition, before Seasonal — mirror `sections` + `all`).
- `ThemeArtDirection` override per theme — the Final Lineup's Personality paragraph names each theme's motion motifs; express them in the existing `AtmosphereMotionSpec` / line-field / title / ribbon / sweep vocabulary. Extend the vocabulary only if a motif genuinely can't be expressed.
- Bespoke `ThemeOrbStyle` case + hand-written `ReactorOrb` composition per theme (widget compiles the enum table only; orb drawing stays app-side). Motif column above + each theme's icon SVG are the design source.
- Tests: mirror existing catalog/palette tests — count assertions, id uniqueness, section membership, `isLight` for the two light themes.

## Phase 2 — Comic Book, the first adaptive theme

**Product decision (Owen, 2026-07-12): ONE gallery entry that follows the SYSTEM light/dark appearance.** Villain Variant = dark, Sunday Funnies = light. The Final Lineup calls this "the collection's most animated theme" — it is the centerpiece; budget effort like Event Horizon got.

Suggested architecture (verify against Phase 0 findings; adjust to reality):

- **Two `ThemeID`s** (`comicVillain`, `comicFunnies`) — two ordinary `ThemePaletteCatalog` entries (`isLight` false/true). Pure data; the widget table just grows by two.
- **One `AppearanceTheme` case** `comicBook` (persisted raw value `"comicBook"`, one `ThemeCatalog` definition in the Midnight Marquee section).
- **Resolution becomes scheme-aware for this case only.** e.g. `themeID(for: ColorScheme)` where every existing theme ignores the scheme; `ThemeRuntime` gains `var systemColorScheme` mirrored from the root view's `@Environment(\.colorScheme)`; `ThemeRuntime.palette` resolves with it.
- **`preferredColorScheme`:** `AppRootView` returns `nil` for the adaptive theme so the system drives; the forced `.light`/`.dark` stays for every other theme (Paper Tape unchanged).
- **`isLight` call sites:** each site found in Phase 0 must get a scheme-resolved answer for `comicBook`. Audit all of them.
- **Two `ThemeArtDirection` overrides + orb treatment per variant.** Villain: ink black, kapow-yellow POW burst, Kirby-krackle twinkle, raking speed lines, drifting halftone, off-register title shake. Funnies: warm newsprint, drifting Ben-Day CMY dots, ZAP burst, hard cyan speech-bubble shadows. Two orb style cases if hue-curation demands it (precedent: every orb is hand-curated), or one shared composition parameterized by the resolved palette — pick after reading `ReactorOrb`.
- **Widget:** the widget's resolution site picks villain/funnies from the widget's own environment `colorScheme`.
- **Live switching:** toggling system appearance while foregrounded must re-skin without relaunch (Observation should handle it once `systemColorScheme` is runtime state — verify with a manual sim check, Settings → Developer → Dark Appearance).

Tests: dark→villain / light→funnies resolution; persistence round-trip of `"comicBook"`; `preferredColorScheme` nil only for the adaptive theme; every non-adaptive theme resolves identically to before (snapshot the mapping).

## Phase 3 — icons (13)

Mirror the shipped flagship + Lane K wiring exactly.

- **5 SE icons** — SVGs already in the updated `design/themes/app-icons.html` (Special Edition section). Render via `tools/appicons/render_gallery_icons.py`, add the reserved `AppIconSection` "Special Edition" to `AppIconCatalog`, `project.yml` `CFBundleAlternateIcons` entries, `xcodegen generate`.
- **8 MM icons** — SVGs in `design/themes/midnight-marquee-app-icons.html`. Preferred: merge them into `app-icons.html` as a "Midnight Marquee" section so the renderer keeps one gallery source; if the renderer's actual shape makes a second input file cleaner, do that instead. New `AppIconSection` "Midnight Marquee".
- **Comic Book ships BOTH icon variants** (Villain POW + Funnies ZAP) as two separately selectable icons — icons stay fully independent of theme selection (Lane K coupling rule).
- End state: **18 current + 13 = 31 selectable icons.** No Haunted VHS icon (theme cut 2026-07-11; `.phosphor` orb remains orphaned data — leave it).

## Deliverables

One PR. Phase-scoped commits (palette/catalog · art direction + orbs · adaptive architecture · icons · tests), `pbxproj` regens isolated. PR description opens with Phase 0 findings.

## Acceptance

- All 8 palettes render with Final Lineup hexes; both light MM themes drive light system chrome end-to-end.
- Comic Book: one picker card; follows system appearance live; both variants have distinct art direction + bespoke orbs.
- 31 icons selectable; icon choice independent of theme choice.
- Existing themes byte-identical; full suite green on the iOS 27 sim (`export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` in EVERY fresh shell — the wrong-Xcode smell is "unavailable in iOS" errors).
