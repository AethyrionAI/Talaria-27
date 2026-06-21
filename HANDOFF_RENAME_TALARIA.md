# Handoff — HermesMobile → Talaria Rename

**Date:** 2026-06-19
**Owner:** Owen Jones (j.owen.jones@live.com)
**Repo:** https://github.com/ChronoRixun/Talaria
**Working directory:** `/Users/owenjones/Downloads/Talaria`

---

## TL;DR

The app was renamed from **HermesMobile** (`io.hermesmobile`) to **Talaria** (`org.aethyrion.talaria`). The rename has been committed to a feature branch and **pushed to GitHub**. A PR has **not** been opened yet, and **master is unchanged**. The build was verified on iOS Simulator before commit.

---

## Current state

| Item | Value |
|---|---|
| Branch with the rename | `rename/talaria` |
| Branch HEAD SHA | `8256f7342e42581f05757494b7056143865c39d9` |
| Pushed to origin? | ✅ Yes (`origin/rename/talaria`) |
| `master` modified? | ❌ No — still at `f1c8b44` |
| New Xcode project | `Talaria.xcodeproj` (use this one) |
| Old Xcode project | `HermesMobile.xcodeproj` — **deleted**, do not look for it |
| Build verified | ✅ iOS Simulator Debug build of `Talaria` scheme succeeded |

**Branch URL:** https://github.com/ChronoRixun/Talaria/tree/rename/talaria

---

## What changed (in the single rename commit)

- Renamed source directories:
  - `HermesMobile/` → `Talaria/`
  - `HermesMobileTests/` → `TalariaTests/`
  - `HermesMobileUITests/` → `TalariaUITests/`
  - `HermesMobileWidgets/` → `TalariaWidgets/`
- Renamed entitlements files (`HermesMobile.entitlements` → `Talaria.entitlements`, same for widgets).
- Updated `project.yml`:
  - `name: HermesMobile` → `name: Talaria`
  - `bundleIdPrefix: io.hermesmobile` → `bundleIdPrefix: org.aethyrion`
  - All source/target/entitlement paths updated to new names
  - App group: `group.io.hermesmobile.HermesMobile` → `group.org.aethyrion.talaria`
  - Bundle IDs: `io.hermesmobile.HermesMobile` → `org.aethyrion.talaria`
  - Widget bundle ID: `io.hermesmobile.HermesMobile.Widgets` → `org.aethyrion.talaria.Widgets`
  - Display name: `Hermes` → `Talaria`
  - Added `NSAllowsArbitraryLoads: true` under `NSAppTransportSecurity`
  - Added `CFBundleDisplayName: Talaria Widgets` and explicit `NSExtensionPointIdentifier` for widgets
- Regenerated `Talaria.xcodeproj` via XcodeGen (replaces deleted `HermesMobile.xcodeproj`).
- Brought in two previously untracked changes that were already in the working tree:
  - `CLEAN_CHAT_PATH.md` (new doc)
  - `Talaria/Services/Live/SessionsHermesClient.swift` (new file)
- Various small edits (~10 files with content changes besides the path rename — git showed them with similarity <100%):
  - `Talaria/AppEntry.swift`
  - `Talaria/Core/Design.swift`
  - `Talaria/Features/Settings/SettingsScreen.swift`
  - `Talaria/Models/DeviceRegistrationRequest.swift`
  - `Talaria/Models/PendingAttachment.swift`
  - `Talaria/Models/UserSettings.swift`
  - `Talaria/Resources/Info.plist`
  - `Talaria/Services/Live/LiveHermesClient.swift`
  - `Talaria/Services/Live/LiveSpeechService.swift`
  - `Talaria/Services/Live/LiveVoiceSessionService.swift`
  - `Talaria/Services/SharedWidgetDataStore.swift`
  - `Talaria/Stores/AppContainer.swift`
  - `TalariaWidgets/HermesLiveActivity.swift`
  - `TalariaWidgets/HermesTimelineProvider.swift`
  - `TalariaWidgets/Info.plist`
  - `TalariaTests/AppStoresTests.swift`
  - `TalariaTests/AppTemplateTests.swift`
  - `TalariaUITests/AppTemplateUITests.swift`
  - `TalariaUITests/AppTemplateUITestsLaunchTests.swift`

Total diff: **167 files changed, 2,233 insertions(+), 1,688 deletions(-)**.

---

## What still needs to happen

1. **Open Xcode against the new project.** If Xcode is still showing `HermesMobile.xcodeproj` it will look broken because that folder no longer exists. Open `Talaria.xcodeproj` instead.
2. **Decide how to land the rename on `master`.** Two options below.
3. **(Optional)** Rename internal Swift symbols and asset references that still say "Hermes" (e.g. `HermesActivityAttributes`, `HermesAvatar`, `HermesTimelineProvider`, `HermesWidgetData`). These were intentionally **not** renamed — the rename only touched directory names, bundle IDs, and product names. The code still uses `Hermes*` for many types.
4. **Reconsider `NSAllowsArbitraryLoads: true`** in `Talaria/Resources/Info.plist`. This was added in the rename; if it's only needed for dev, it should not ship.

### Option A — Open a PR (recommended)

```bash
cd /Users/owenjones/Downloads/Talaria
gh pr create --base master --head rename/talaria \
  --title "Rename HermesMobile → Talaria" \
  --body "Renames app + widgets to Talaria (org.aethyrion.talaria). Regenerated Talaria.xcodeproj via XcodeGen. Builds clean on iOS Simulator Debug."
```

### Option B — Fast-forward merge straight to master

```bash
cd /Users/owenjones/Downloads/Talaria
git checkout master
git merge --ff-only rename/talaria
git push origin master
```

---

## How to verify the build yourself

```bash
cd /Users/owenjones/Downloads/Talaria
xcodebuild -project Talaria.xcodeproj \
           -scheme Talaria \
           -destination 'generic/platform=iOS Simulator' \
           -configuration Debug build
```

Expected: `** BUILD SUCCEEDED **`. One non-fatal warning about widget `CFBundleShortVersionString` (`1.0`) not matching parent app (`1.0.0`) — cosmetic, fix in `project.yml` widget target if you care.

---

## Tooling installed during this session

- **Homebrew** — installed by user.
- **XcodeGen** (v2.45.4) — `brew install xcodegen`. Required whenever `project.yml` changes; regenerates `Talaria.xcodeproj`.
- **GitHub CLI** (`gh` v2.95.0) — `brew install gh`. Authenticated as `ChronoRixun` via `gh auth login`, then `gh auth setup-git` wired it into git's credential helper.

Run `xcodegen generate` (from the repo root, where `project.yml` lives) whenever you change `project.yml`. It rewrites `Talaria.xcodeproj/project.pbxproj` in place.

---

## Watch-outs / gotchas

- **Don't recreate `HermesMobile.xcodeproj`.** It was the broken project; we intentionally deleted it. If Xcode auto-recreates it for some reason, delete it again and reopen `Talaria.xcodeproj`.
- **Bundle ID change is breaking for installed copies.** A device with the old `io.hermesmobile.HermesMobile` build can keep that app side-by-side with the new `org.aethyrion.talaria` build — they're different apps to iOS. Uninstall old before installing new, or expect two icons.
- **App group migration.** The shared `UserDefaults`/widget data lives under `group.io.hermesmobile.HermesMobile` on existing installs. After the rename, the app reads/writes `group.org.aethyrion.talaria` — **users will lose any previously-shared widget state**. If that matters, you'll need a migration shim that reads old → writes new on first launch.
- **HealthKit re-auth.** New bundle ID = new entitlement subject. Users will re-prompt for HealthKit / mic / speech permissions because iOS treats it as a fresh app.
- **TestFlight / App Store.** If you ever shipped under `io.hermesmobile.HermesMobile`, the new bundle ID is a *new* app on App Store Connect. Cannot be promoted in place.
- **Schemes:** XcodeGen only generated `Talaria` and `TalariaWidgets` schemes. If you previously had a separate widgets scheme (the old `HermesMobileWidgets.xcscheme` was deleted), you don't need to re-create it — the widget builds as a dependency of the app scheme.

---

## Useful one-liners for a future session

```bash
# Check current state
cd /Users/owenjones/Downloads/Talaria
git status
git log --oneline -5
git branch -vv

# See the rename commit
git show 8256f73 --stat | head -30

# Compare branch to master
git diff master..rename/talaria --stat

# If project.yml is edited later
/opt/homebrew/bin/xcodegen generate
```

---

## Files added this session

- `HANDOFF_RENAME_TALARIA.md` (this file)
- `CLEAN_CHAT_PATH.md` (was already in working tree, now committed)

---

## Open questions for next session

1. Should the internal Swift symbols (`Hermes*` class names) be renamed too, or is the rename intentionally scoped to product identity?
2. Is `NSAllowsArbitraryLoads: true` meant to ship, or is it dev-only?
3. Do existing widget/HealthKit users need a migration path, or is this effectively a fresh start?
4. Should the GitHub repo description / README be updated to reflect the new name?
