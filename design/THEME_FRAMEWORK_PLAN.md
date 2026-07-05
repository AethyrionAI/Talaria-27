# Talaria Theme Framework — Design Pass (issue #24)

**Status:** design pass + foundational implementation landed 2026-07-05.
**Extends:** `THEME_SYSTEM_PLAN.md` (the shipped 4-theme system).
**Scope of this doc:** resolve the "enum-per-theme vs. data-driven catalog" question
the issue flagged, specify the framework, and sequence the risky part (the palette-core
de-duplication) for a Mac session where the byte-identical guard can actually run.

---

## 1. Problem

`AppearanceTheme` supports exactly four hand-built themes, each requiring hand-written
switch arms across five files (`Shared/ThemePaletteCore.swift`, `Core/Design.swift`,
`Core/HUD/ReactorOrb.swift`, `Models/UserSettings.swift`, `TalariaWidgets/WidgetTheme.swift`).
That's the right shape for four flagships but doesn't scale to the roadmap: seasonal
auto-rotation, holiday themes that appear only in-window, a paid-tier `locked` flag, and
"many more drastic themes" without a five-file edit each.

## 2. The core decision — enum **and** catalog (not enum *vs.* catalog)

A single all-or-nothing rewrite of `ThemePaletteCore` is the wrong move: Deep Field × cyan
is **byte-identical to the pre-theming constants and guarded by `DesignThemeTests`**, and
that guard can only be *run* on a Mac. So we split the framework in two layers with a clean
seam:

- **Metadata layer (data-driven, shipped in this PR).** A `ThemeDefinition` catalog carries
  everything that is *not* raw color: identity, availability (always / seasonal / holiday),
  and the `locked` gate. New seasonal/holiday behavior is pure data here.
- **Render layer (still enum-switched, unchanged in this PR).** `AppearanceTheme` →
  `ThemePalette` stays exactly as-is, so the pixel guarantee is untouched. Each
  `ThemeDefinition` maps onto a render `AppearanceTheme`.

This gives the framework's *behaviors* now, at zero risk to the render path, and isolates
the one genuinely risky change (making palettes data-driven) into a separately-verifiable
follow-up (§6).

## 3. What shipped in this PR (foundational)

All additive; **manual mode is the default, so existing installs are byte-identical.**

- **`ThemeCatalog` / `ThemeDefinition`** (`Models/ThemeCatalog.swift`) — the data model:
  `id`, `displayName`, `subtitle`, `appearanceTheme` (render identity), `availability`,
  `locked`. Flagship definitions describe the four shipped themes 1:1.
- **Seasonal auto-rotation** — `AppearanceThemeMode { manual, automatic }` persisted on
  `UserSettings`; `UserSettings.effectiveAppearanceTheme(on:)` returns the manual pick in
  manual mode and `ThemeCatalog.seasonalTheme(on:)` in automatic mode. `ThemeRuntime`, the
  widget snapshot, and the change-detector all read the *effective* theme, so automatic
  mode drives the whole app (and widgets) live. Re-resolved on foreground so a season
  rollover applies without a relaunch.
- **Holiday date windows** — `DateWindow` (recurring month/day range, year-wrap aware) +
  `ThemeAvailability.holiday`. `ThemeCatalog.availableDefinitions(on:)` filters holiday
  themes to their window; the Appearance picker renders that filtered set, so an
  out-of-window holiday theme is simply absent.
- **`locked` flag** — on every definition from day one; the picker shows a lock affordance.
  Nothing ships locked, so it's inert — a future tier is a flag flip, not a retrofit.
- **Picker** — the theme grid is now catalog-driven (`availableDefinitions(on:)`), plus a
  **Seasonal (Auto)** toggle that shows the active season + resolved theme.
- **Tests** — `ThemeCatalogTests`: season boundaries, date-window wrap, holiday windowing,
  catalog invariants, and `effectiveAppearanceTheme` mode behavior.

### Design rules chosen here
- **Seasons:** Northern-Hemisphere **meteorological** (month-based) boundaries — stable, no
  ephemeris, trivially testable. Hemisphere hardcoded per the issue.
- **Seasonal set (v1):** each season maps to an existing flagship palette (winter → Deep
  Field, spring → Terminal, summer → Solar Forge, autumn → Paper Tape). This is a documented
  **placeholder** — bespoke seasonal palettes are content (§5), and a `.seasonal` definition
  overrides the default map for its season the moment one exists.
- **Manual override always wins:** picking any theme card sets `.manual`.

## 4. Deliberately NOT shipped here
- **No new visual identities (holiday/seasonal palettes).** Curating new palettes is a
  separate issue (the Open Design gallery pass, with dedupe still in progress). Shipping a
  holiday theme that renders as an existing palette would violate "real data only," so the
  catalog ships flagship-only; the holiday/seasonal machinery is complete and tested and
  accepts a real theme with no further picker/runtime changes.
- **No palette-core rewrite.** See §6.

## 5. How a new theme drops in (once its palette is curated)
1. Add the palette (see §6 for the target data-driven shape; until then, a new
   `AppearanceTheme` case + its switch arms).
2. Add one `ThemeDefinition` to `ThemeCatalog.special` with its `availability`
   (`.seasonal(_)` or `.holiday(DateWindow(...))`) and `locked` flag.
3. Nothing else — the picker, seasonal resolver, and windowing already consume it.

## 6. Sequenced follow-up — data-driven palette core (the render-layer de-dup)

This is the part that removes the five-file-per-theme edit, and the part that must be done
where `DesignThemeTests` can run.

- Move each theme's ~30 resolved colors + per-slot accent families out of the private
  `init(deepField:)`/etc. switch arms into a `ThemeDefinition` palette payload.
- `ThemePalette(theme:accent:)` resolves via the catalog instead of a switch.
- **Guard:** Deep Field × cyan must stay byte-identical — keep `DesignThemeTests` green at
  every step; port one theme at a time. Because the accent slots re-interpret per theme
  (not just static values), this is real logic, not a mechanical move — hence a Mac session,
  not a blind cloud rewrite.
- Once done, `AppearanceTheme` can collapse into the catalog (or become a thin id), and a
  new theme is genuinely one catalog entry.

## 7. Known v1 limitations (tracked)
- Seasonal rollover applies on next foreground/relaunch, not at the instant midnight crosses
  a boundary while the app is open (acceptable; no timer added).
- Automatic mode reflects in "Match App" widgets via the effective-theme snapshot, but a
  widget timeline only re-reads on its own reload cadence + on theme change.
- The season→theme map is a placeholder until curated seasonal palettes exist (§3).

## 8. Decoupled: app icon picker (#25)
Tracked and shipped separately (its own PR). The icon `AppIconCatalog` intentionally mirrors
this catalog's shape (immutable value + array, resolvable by id) so the two read the same way,
but they share no code and neither gates the other. Auto-binding an icon to the active theme
remains an explicit non-goal.
