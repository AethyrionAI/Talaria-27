# #239 Themes Sub-Section Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Appearance shows a compact "Themes" navRow (value = resolved theme, seasonal-aware) pushing a new ThemesSettingsScreen that owns the theme cards, seasonal toggle, and accent swatches — and re-skins live when a theme is picked.

**Architecture:** Pure relocation per the approved spec (`docs/superpowers/specs/2026-08-03-239-themes-subsection-design.md`). A nonisolated static value helper (unit-tested) feeds the navRow; the new screen duplicates the parent's small resolution helpers (`theme`/`accent`/`palette`/`resolvedThemeID`) and carries its own `HUDScreenBackground`, so selection re-skins it exactly as the single screen does today. No settings-key or palette changes.

**Tech Stack:** SwiftUI, swift-testing (`TalariaTests/DesignThemeTests.swift`), XCUITest (`TalariaUITests/AppTemplateUITests.swift`), xcodegen.

## Global Constraints

- `DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer` on every xcodebuild.
- `xcodegen generate` after creating `ThemesSettingsScreen.swift`.
- Pinned sim `47F68496-24F9-45D9-93D3-1C778DB6B557`.
- Counters pinned in the entry BEFORE verification: swift-testing 1555 → **1557** (2 helper tests); XCUITest `Executed` 9 → **10**.
- TDD watched RED on 239-A; the 239-B walk is new coverage (RED = fails against a build without the sub-screen — witnessed by running it before Task 2's UI change only if cheap; otherwise its assertions are validated by the Task 3 run on the finished build, honest note in the entry).
- Gate before PR. Branch `claude/t27-239-themes-subsection` (created).
- Do not touch `ThemePaletteCore.swift`, `ThemeCatalog` data, or the SystemSettingsScreen "REACTOR" row.

---

### Task 1: navRow value helper (239-A, TDD)

**Files:**
- Modify: `Talaria/Features/Settings/AppearanceSettingsScreen.swift` (add static helper near the top of the struct)
- Test: `TalariaTests/DesignThemeTests.swift` (append 2 tests)

**Interfaces:**
- Consumes: `UserSettings.effectiveAppearanceTheme(on:)`, `UserSettings.appearanceThemeMode` (`.automatic`/`.manual`), `ThemeCatalog.season(on:)`, `AppearanceTheme.displayLabel`.
- Produces: `AppearanceSettingsScreen.themesRowValue(settings:on:) -> String` (nonisolated static) — Task 2's navRow consumes it.

- [ ] **Step 1: Write the failing tests** (append inside the existing suite in `DesignThemeTests.swift`):

```swift
    // MARK: - #239: Themes navRow value

    @Test func themesRowValueManualModeIsUppercasedThemeName() {
        var settings = UserSettings()
        settings.appearanceThemeMode = .manual
        settings.appearanceTheme = .solarForge
        #expect(AppearanceSettingsScreen.themesRowValue(settings: settings, on: Date(timeIntervalSince1970: 1_700_000_000))
            == "SOLAR FORGE")
    }

    @Test func themesRowValueAutomaticModePrefixesSeason() {
        var settings = UserSettings()
        settings.appearanceThemeMode = .automatic
        let midsummer = DateComponents(calendar: .init(identifier: .gregorian),
                                       year: 2026, month: 7, day: 10).date!
        let value = AppearanceSettingsScreen.themesRowValue(settings: settings, on: midsummer)
        let season = ThemeCatalog.season(on: midsummer).displayLabel.uppercased()
        let theme = settings.effectiveAppearanceTheme(on: midsummer).displayLabel.uppercased()
        #expect(value == "\(season) · \(theme)")
    }
```

(If `UserSettings()` needs arguments or `.solarForge` differs, mirror the construction used by existing `DesignThemeTests` cases — read the file's existing fixtures first and keep their idiom.)

- [ ] **Step 2: Run — watch RED** (`themesRowValue` unresolved):

```bash
cd /Users/owenjones/Documents/Claude/Talaria-27 && DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer xcodebuild -project Talaria.xcodeproj -scheme Talaria -destination 'platform=iOS Simulator,id=47F68496-24F9-45D9-93D3-1C778DB6B557' -only-testing:TalariaTests/DesignThemeTests test 2>&1 | tail -15
```

Expected: compile failure naming `themesRowValue`.

- [ ] **Step 3: Implement** (in `AppearanceSettingsScreen`, near the other computed helpers):

```swift
    /// #239: the Themes navRow value — seasonal mode surfaces the season so
    /// automatic rotation stays legible from the top level.
    nonisolated static func themesRowValue(settings: UserSettings, on date: Date = Date()) -> String {
        let theme = settings.effectiveAppearanceTheme(on: date)
        guard settings.appearanceThemeMode == .automatic else {
            return theme.displayLabel.uppercased()
        }
        return "\(ThemeCatalog.season(on: date).displayLabel.uppercased()) · \(theme.displayLabel.uppercased())"
    }
```

- [ ] **Step 4: Run — GREEN** (same command). **Step 5: Commit** (`#239 T1: themesRowValue helper (239-A)`).

---

### Task 2: ThemesSettingsScreen + navRow relocation

**Files:**
- Create: `Talaria/Features/Settings/ThemesSettingsScreen.swift`
- Modify: `Talaria/Features/Settings/AppearanceSettingsScreen.swift`

**Interfaces:**
- Consumes: `themesRowValue` (Task 1); the symbols being MOVED (exact list below); `SettingsScreenHeader`, `HUDScreenBackground`, `MonoLabel`, `Design.*`, `hudPanel`.
- Produces: `struct ThemesSettingsScreen: View` pushed via NavigationLink from Appearance.

- [ ] **Step 1: Create `ThemesSettingsScreen.swift`.** Move these symbols VERBATIM out of `AppearanceSettingsScreen` (current lines noted for orientation): `themeSection` (~196), `themeGroup` (~211), `automaticPanel` (~230), `automaticCaption` (~254), `automaticBinding` (~261), `themeCard` (~268), `lockBadge` (~326), `accentSection` (~337), `accentSwatch` (~355). The new struct re-declares the parent's small resolution layer it depends on (copy verbatim from the parent, which KEEPS its own copies for the preview panel): `settingsStore` environment property, `theme`, `accent`, `palette`, `resolvedThemeID(_:)`, and the `dismiss` environment if `SettingsScreenHeader` needs it. Body shape (mirrors the parent's):

```swift
    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: Design.Spacing.lg) {
                    SettingsScreenHeader(title: "Themes", subtitle: "Appearance") { dismiss() }
                    themeSection
                    if theme.themeID.lockedAccentSlot == nil {
                        accentSection
                    }
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)
            }
        }
        .navigationTitle("Themes")
        .toolbarVisibility(.hidden, for: .navigationBar)
    }
```

- [ ] **Step 2: Rewire Appearance.** In `AppearanceSettingsScreen.body`, replace `themeSection` + the conditional `accentSection` block with one navRow (local copy of the SystemSettingsScreen idiom, icon `paintpalette`):

```swift
                    themesNavRow
```

```swift
    /// #239: the theme cards + accents live one level down; the row surfaces
    /// the resolved state so automatic mode stays legible from here.
    private var themesNavRow: some View {
        NavigationLink {
            ThemesSettingsScreen()
        } label: {
            HStack(spacing: Design.Spacing.sm) {
                Image(systemName: "paintpalette")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Design.Brand.accent)
                Text("Themes")
                    .font(Design.Typography.body(15, weight: .medium))
                    .foregroundStyle(Design.Colors.foreground)
                Spacer(minLength: Design.Spacing.xs)
                MonoLabel(Self.themesRowValue(settings: settingsStore.settings),
                          size: 10, weight: .medium,
                          tracking: Design.Tracking.mono, color: Design.Brand.accent)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Design.Colors.accentTint(0.7))
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.sm)
            .hudPanel(cornerRadius: Design.CornerRadius.lg,
                      borderColor: Design.Colors.accentTint(0.12),
                      fill: Design.Colors.background.opacity(0.5),
                      innerGlow: false)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Themes")
    }
```

(Mirror the exact `iconTile`/`hudPanel` composition the codebase's navRow uses if it differs — read SystemSettingsScreen:221-250 while editing and keep ITS visual idiom; the block above is the shape, the neighboring code is the authority.) Delete the moved symbols from the parent; the parent KEEPS `theme`/`accent`/`palette`/`resolvedThemeID`/`resolvedAccent` (the preview panel and accent-independent sections still use them).

- [ ] **Step 3:** `xcodegen generate`, then CLI compile check (sim `generic` Debug build). Fix anything the move broke (e.g., a helper still referenced by a moved symbol — move or duplicate it deliberately, never share via `internal` widening).

- [ ] **Step 4:** Run `DesignThemeTests` + the full `TalariaTests` bundle stays for Task 4's count; here run at least `-only-testing:TalariaTests/DesignThemeTests` GREEN. **Step 5: Commit** (`#239 T2: ThemesSettingsScreen split + navRow`).

---

### Task 3: 239-B XCUITest — theme change from the new page

**Files:**
- Test: `TalariaUITests/AppTemplateUITests.swift` (append; fresh-context idiom from `testFreshInstallNeverPresentsNotificationPermissionDialog`, ~line 130)

**Interfaces:**
- Consumes: `UITestLaunchContext()`, `makeApp(context:)`, gear button `app.buttons["Open settings"]`, navRow labels ("Appearance & HUD" / "Themes"), theme-card accessibility labels (`definition.displayName`, e.g. "Solar Forge").

- [ ] **Step 1: Write the test:**

```swift
    /// 239-B: the Themes sub-screen exists, a theme picked THERE applies
    /// (sub-screen re-skins; selection trait moves), and the parent row
    /// reflects the new theme on return.
    func testThemeChangeFromThemesSubScreenAppliesAndSurfacesInRow() throws {
        let context = UITestLaunchContext()
        let app = makeApp(context: context)
        app.launch()

        app.buttons["Open settings"].tap()
        let appearanceRow = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Appearance'")).firstMatch
        XCTAssertTrue(appearanceRow.waitForExistence(timeout: 10))
        appearanceRow.tap()

        let themesRow = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Themes'")).firstMatch
        XCTAssertTrue(themesRow.waitForExistence(timeout: 10), "Appearance must surface the Themes navRow (#239)")
        themesRow.tap()

        let solarForge = app.buttons["Solar Forge"]
        XCTAssertTrue(solarForge.waitForExistence(timeout: 10), "theme cards must live in the sub-screen (#239)")
        solarForge.tap()
        XCTAssertTrue(solarForge.isSelected || solarForge.waitForSelection(timeout: 5),
                      "picking a card in the sub-screen must apply immediately (239-B)")

        app.navigationBars.buttons.firstMatch.tapIfExists()
        let updatedRow = app.buttons.matching(NSPredicate(format: "label CONTAINS 'SOLAR FORGE' OR label CONTAINS 'Solar Forge'")).firstMatch
        XCTAssertTrue(updatedRow.waitForExistence(timeout: 10),
                      "the Themes row value must show the newly selected theme (239-B)")
    }
```

(`waitForSelection`/`tapIfExists` — if these helpers don't exist in the file, inline the equivalent: poll `solarForge.isSelected` with `XCTNSPredicateExpectation`, and use the SettingsScreenHeader back control — read how the header exposes its dismiss button and target THAT; the test file's existing navigation code is the authority.)

- [ ] **Step 2:** Run only this test on the pinned sim; iterate until it passes for the RIGHT reasons (check the xcresult if a tap drops — sim-verify memory: hedge with one re-tap on flaky same-tick transitions). **Step 3: Commit** (`#239 T3: 239-B walk`).

---

### Task 4: Records, gate, PR, corded deploy

- [ ] **Step 1:** Full suite count check: swift-testing must read **1557**; XCUITest `Executed` **10**.
- [ ] **Step 2:** OPEN_ITEMS #239 entry: bars 239-A/B met (test names, observed counters), 239-C owed to Owen on device.
- [ ] **Step 3:** Gate (backgrounded + pid waiter). **Step 4:** push, PR (`#239: Themes sub-section in Appearance`), Owen merges.
- [ ] **Step 5 (post-merge):** corded deploy — build Debug for device, `devicectl device install app`, then `devicectl device process launch --terminate-existing` (the #240 footnote). Owen observes 239-C.
