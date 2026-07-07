# Theme Test Suite Verification — Handoff

**For:** a Mac Claude Desktop session (Xcode only — the CLI can't resolve the
`TalariaTests` test host, #51/#52).
**Status:** not run yet. Written 2026-07-05, after PR #38 merged and a manual/
visual on-device pass (themes, accents, icons, Seasonal Auto toggle) already
confirmed by Owen. This handoff is specifically the automated-suite gap left in
#38's own PR checklist — manual testing doesn't exercise the 26 `@Test`
assertions below.

## Mission

Run and confirm two test suites pass in Xcode, closing out the one remaining
unchecked item from PR #38's checklist. This is verification, not development —
if everything's green, this is a ~10 minute task; only dig further if something
is red.

## Required environment

- Mac Mini only, Xcode-beta (`/Applications/Xcode-beta.app`) — `xcodebuild test`
  can't resolve the `TalariaTests` host from the CLI (#51/#52), so this must run
  inside Xcode's UI.
- Repo is already at `main` HEAD (`6e8b4cc` or later). `xcodegen generate` already
  run + committed (`2cda9ff`), plain build already confirmed BUILD SUCCEEDED.
  No setup needed beyond opening the project.

## What to run — scoped, not a blind Cmd+U

Don't just hit Cmd+U for the whole suite: `TalariaTests` has other files with
**known, currently-unrelated failures** — PR #44 ("Fix/sensor store test
fixtures") is open and unmerged, so the full suite may show red for reasons that
have nothing to do with theming. Scope the run to just these two:

1. Open `Talaria.xcodeproj` in Xcode-beta.
2. Cmd+6 (Test Navigator).
3. Find `TalariaTests → DesignThemeTests` and `TalariaTests → ThemeCatalogTests`.
4. Run each suite individually (hover → diamond play button next to the suite
   name, or right-click → Run), rather than the whole target.

## What "green" means

Both use Swift Testing (`@Test func ...`), not XCTest's `func testX()` — passing
tests show as filled diamonds in the Test Navigator and the editor gutter.

- **`DesignThemeTests.swift`** (13 tests) — the byte-identical guard lives here.
  The one that matters most: `deepFieldCyanMatchesLegacyConstants` — asserts
  every resolved field of `ThemePalette(theme: .deepField, accent: .cyan)`
  against hardcoded legacy hex values (background `0x06080C`, foreground
  `0xE8EEF5`, accent `0x54E6F0`, gradient stops, drawer colors, grid params,
  etc). Nothing in #38 touched `ThemePaletteCore.swift`, so this should already
  pass — if it doesn't, that's a real regression signal, not something to fix by
  adjusting the test.
- **`ThemeCatalogTests.swift`** (13 tests) — the new #38 behavior: season-
  boundary math, `DateWindow` year-wrap, holiday windowing, catalog invariants
  (unique ids, flagship ids match raw values, nothing ships locked), and
  `effectiveAppearanceTheme` manual-vs-automatic mode behavior + Codable default.

## If something fails

- **`DesignThemeTests` red** → stop, don't patch the test. This means Deep
  Field × cyan drifted from the legacy constants somewhere outside #38's diff —
  escalate before touching anything.
- **`ThemeCatalogTests` red** → likely a genuine bug in the new #38 code (season
  math, date-window wrap, or a mode-resolution edge case) — worth its own small
  bug-fix issue referencing #38, not a silent tweak.

## When done

- All green → comment on PR #38 (or issue #49) that the test-suite checklist
  item is closed; nothing else to do.
- Anything red → note which test(s) and the failed assertion, file it, and don't
  proceed into #49 (palette-core de-dup) with a red guard test.

## References

- PR #38 — original (currently unchecked) test checklist item
- Issue #49 — palette-core de-dup, blocked on this guard staying green
- `TalariaTests/DesignThemeTests.swift`, `TalariaTests/ThemeCatalogTests.swift`
