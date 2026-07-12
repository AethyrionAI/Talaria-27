# FABLE — Lane K · App Icons (remaining 14)

**Repo:** `AethyrionAI/Talaria-27` · **Branch:** `claude/t27-app-icons-batch`
**Type:** asset + light Swift wiring · **Collision surface:** none with Lanes D/F/G/H (icon picker + asset catalog only; no `ChatScreen.swift`, no relay, no model wiring)
**Depends on:** the already-shipped **flagship** app-icon feature (Deep Field / Solar Forge / Terminal / Paper Tape). This lane *replicates that exact pattern* for the other 14 icons — it does not invent a new one.

---

## Goal

The flagship app-icon set (4 icons) is live and selectable. Wire **14** more theme icons from `app-icons.html` into the alternate-app-icon picker — same mechanism, same picker UI, same naming convention. End state: **18** selectable icons.

**Do NOT design a new system.** First read the flagship wiring end-to-end and mirror it per icon. If anything below contradicts what's actually in the repo, the repo wins — this spec is written from a stale snapshot and the flagship feature post-dates it.

**Coupling (confirmed):** the icon picker is **independent** of theme selection. Choosing a theme must NOT change the home-screen icon, and choosing an icon must NOT change the theme. Mirror the flagship behavior.

---

## Step 0 — Read the flagship implementation first (mandatory)

Before touching anything, locate and read how the 4 flagship icons are wired. Expected touchpoints (verify actual names):

1. **Asset catalog** — the alternate `*.appiconset` folders (likely under `Talaria/Assets.xcassets/` or a dedicated `AppIcons` catalog). Note the folder/set naming and the `Contents.json` shape (single-size 1024 vs. multi-size).
2. **`project.yml`** — how alternate icons are declared. Most likely `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` (space-separated set names) + `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS: YES` in the target's `settings`. Confirm exact keys.
3. **The picker screen** — where the user chooses an icon (a new `AppIconSettingsScreen.swift`, or a section inside `AppearanceSettingsScreen.swift`). Note the layout, the preview thumbnail source, and the selected-state handling.
4. **The icon catalog / enum** — the data structure listing icons (id, display name, alternate-icon-name, group). This is what you extend.
5. **The runtime switch** — the `UIApplication.shared.setAlternateIconName(_:)` call site and how "primary/nil" is handled.

**Write down the 4 flagship entries verbatim as your template**, then produce 14 more that are byte-for-structure identical apart from id/name/asset.

---

## The 14 icons to add

Source of truth for artwork: the SVGs in `app-icons.html` (each is a complete full-bleed 1024×1024 with its own background `<rect>`). Group them to mirror the shipped **theme gallery taxonomy**.

| # | icon id | Display name | Group | Matching theme? |
|---|---------|--------------|-------|-----------------|
| 1 | `neon-arcade` | Neon Arcade | Neon Arcade Collection | none — collection namesake (NA#01 is gallery chrome, never ported as a theme) |
| 2 | `glitch-garden` | Glitch Garden | Neon Arcade Collection | ✓ |
| 3 | `witchs-brew` | Witch's Brew | Neon Arcade Collection | ✓ |
| 4 | `holo-sushi` | Holo Sushi | Neon Arcade Collection | ✓ |
| 5 | `lunar-diner` | Lunar Diner | Neon Arcade Collection | ✓ |
| 6 | `cyber-cactus` | Cyber Cactus | Neon Arcade Collection | ✓ |
| 7 | `disco-inferno` | Disco Inferno | Neon Arcade Collection | ✓ |
| 8 | `cereal-box` | Cereal Box | Neon Arcade Collection | ✓ (drama-retrofitted) |
| 9 | `bubblegum-mecha` | Bubblegum Mecha | Neon Arcade Collection | ✓ (drama-retrofitted) |
| 10 | `retro-sci-fi` | Retro Sci-Fi | Neon Arcade Collection | ✓ (drama-retrofitted) |
| 11 | `autumn-harvest` | Autumn Harvest | Seasonal | ✓ |
| 12 | `spring-sprout` | Spring Sprout | Seasonal | ✓ |
| 13 | `summer-solar` | Summer Solar | Seasonal | ✓ |
| 14 | `winter-frost` | Winter Frost | Seasonal | ✓ |

**Explicitly NOT wired:** `deep-sea-diner` — its icon exists in the gallery, but the theme was cut and Owen has cut the icon too (icon↔theme parity). Skip it entirely.

**Not in this batch (no art yet):** `event-horizon`, `graffiti-galaxy`, `karaoke-supernova` — shipped SE themes with no icon SVG. These are handled by the Claude Design hand-off below, then wired in a small follow-up.

---

## Hard requirement: SVG → PNG

**iOS `.appiconset` accepts PNG only — never SVG.** Each gallery SVG must be rasterized to a **1024×1024 PNG** before it goes in the asset catalog. Mirror however the flagship PNGs were produced (check whether the repo committed a build step or a script). If none exists, rasterize headless (e.g. `resvg`, `rsvg-convert`, or `cairosvg`) at exactly 1024×1024 and commit the PNGs. Each SVG's opening `<rect width="1024" height="1024">` is the full-bleed background, so a straight 1024 render is a complete icon — do **not** add rounded corners or padding (iOS masks the corners).

Extract each icon's SVG from `app-icons.html` by its `id` (the `icons[]` array; use the `svg` field verbatim).

---

## Acceptance criteria

- [ ] 14 new PNGs at 1024×1024, one per icon id, in the asset catalog mirroring the flagship set structure
- [ ] `project.yml` lists all 14 new alternate-icon names alongside the existing 4 (same key(s) the flagships use); `xcodegen generate` run after edits
- [ ] Icon catalog/enum extended with 14 entries, grouped per the taxonomy above
- [ ] Picker screen shows all 18 icons (4 flagship + 14 new) in grouped sections; tapping one calls `setAlternateIconName` and it takes effect on the home screen
- [ ] Icon choice is independent of theme choice (neither drives the other)
- [ ] Selected icon persists and the picker shows the current selection on reopen
- [ ] `xcodegen generate` did **not** strip `aps-environment: development` from `Talaria/Talaria.entitlements` (the #44/#48 trap — verify it survived; also re-check WeatherKit / widget-HealthKit entitlements)
- [ ] App target builds clean (Xcode-beta, iOS 27 SDK); existing icon tests (if any) still green
- [ ] No mock/placeholder icons surface to the user; every listed icon renders real art

---

## Process notes (house rules)

- **File-scoped commits.** Keep the `pbxproj`/xcodegen regen commit **separate** from feature commits. No `pbxproj` in an asset or Swift commit. Suggested split: (a) PNG assets + `Contents.json`, (b) `project.yml` settings + catalog/enum + picker wiring, (c) `xcodegen generate` regen (pbxproj + scheme) on its own.
- **Cloud can't build.** You author; the Mac review-then-build loop compiles against the iOS 27 SDK. Write the Swift defensively (mirror flagship call sites exactly) since you can't run `xcodebuild`.
- **New files → `xcodegen generate` is mandatory** (new asset catalog entries and any new Swift file). Flag in the PR that the Mac session must regen + re-verify entitlements.
- Single PR, standard `--merge`. Pin `--repo AethyrionAI/Talaria-27` on every `gh` call; `export GH_PAGER=cat`.

---

## Hand-off: 3 new Special-Edition icons → dispatch Claude Design

Three shipped SE themes have **no icon art** yet, so they can't be wired here. This is net-new design work, not a port — **dispatch Claude Design** to author the SVGs, then wire them in a small follow-up PR (same pipeline as this lane). Forward the brief below to Claude Design verbatim:

> **Brief for Claude Design — 3 Talaria app-icon SVGs**
>
> Create three 1024×1024 app-icon SVGs, one per shipped Special-Edition theme. Match the visual language of the existing icons in `app-icons.html`: full-bleed dark background (unless the identity calls for otherwise), a single bold centered motif, neon/high-contrast palette, no text, no rounded corners or padding (iOS masks corners). Each icon must start with a full-canvas `<rect width="1024" height="1024">` background.
>
> Deliver each as an entry shaped exactly like the `icons[]` objects in `app-icons.html` — `{ id, name, desc, bg, svg }` — so they drop straight into the gallery:
>
> 1. **`event-horizon` — "Event Horizon"** — the flagship "outrageous" SE. A singularity: black core, bright accretion ring, gravitational-lensing starburst spokes. Deep violet/blue-black field. (Reference the shipped `.singularity` orb + `RadialSpokeField` lensing.)
> 2. **`graffiti-galaxy` — "Graffiti Galaxy"** — street-art SE. Spray-paint energy: a spray-cap / tag motif, drip and streak texture, bright multi-color over dark. (Reference the spray-cap orb + TAG ribbon art direction.)
> 3. **`karaoke-supernova` — "Karaoke Supernova"** — stage/disco SE. A ♪ mirror-ball motif under pulsing spotlights, laser-bar accents, saturated stage neon. (Reference the ♪ mirror-ball orb + roomPulse spotlights.)
>
> Output the three entries plus a note on where they slot into `app-icons.html`. After they land, they follow the same SVG→1024 PNG → asset-catalog → picker wiring as the other icons.

Once Claude Design returns the SVGs and they're added to `app-icons.html`, extending the picker from 18 → 21 is a trivial follow-up (add art, add 3 catalog entries, regen).
