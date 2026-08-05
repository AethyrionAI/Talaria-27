# #252 Settings "Subsystem Channels" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the settings root with a nine-card live-telemetry grid that toggles into a swipeable full-bleed subsystem deck (Claude Design direction 1c), per `planning/superpowers/specs/2026-08-05-252-settings-channels-design.md`.

**Architecture:** A new `SettingsChannelsScreen` owns a `grid`/`deck(index)` state. Grid = `LazyVGrid` of `SubsystemCard`s fed by pure value formatters; deck = paged `TabView` whose pages embed the existing sub-screens (headers/backgrounds suppressed via an `embedded:` flag), later topped with `SubsystemHero`s. Stage 3 merges Diagnostics into About and relocates the battery harness to Developer.

**Tech Stack:** SwiftUI (iOS 27 SDK, Xcode-beta4), XCTest + XCUITest, xcodegen.

## Global Constraints

- Branch: `claude/t27-252-settings-channels`. The #249 instrument dirt in `DeviceActionTools.swift` is NOT part of this lane — never stage it.
- Zero palette/token changes; type via existing `Design.Typography`; no new fonts.
- Plain SwiftUI only: `LazyVGrid`, paged `TabView`, sheets, segmented buttons.
- Appearance browser (`AppearanceSettingsScreen`), `AppIconSettingsScreen`, `ConnectHermesHostScreen`, `BatteryResultsScreen` family: UNTOUCHED (except Task 4's embedded flag does NOT apply to AppearanceSettingsScreen).
- No `List`; `.hudPanel` groups; `MonoLabel("// …")` headers; destructive confirms via `.alert` (#193).
- Real data only: unknown values render `—`/`…`, never placeholders. No fictional latency, models, voices, or pairing theater.
- Label substrings preserved verbatim: `"Connect Hermes Desktop"`, `"UPGRADE"`, `"Pairing & Devices"`, `"Disconnect"`, `"Open settings"`.
- `xcodegen generate` after every file add/delete, before building.
- After editing tests, confirm the reported test COUNT moved (stale-`.xctest` trap).
- Compile check (background it; poll the log — takes minutes):
  `DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer xcodebuild -project Talaria.xcodeproj -scheme Talaria -configuration Debug -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
- Unit-test run (CC sims only — stock iPhone 17 sims are not scheme-compatible; resolve `UDID=$(xcrun simctl list devices | grep -m1 'CC-' | grep -oE '[A-F0-9-]{36}')`):
  `DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer xcodebuild test -project Talaria.xcodeproj -scheme Talaria -destination "platform=iOS Simulator,id=$UDID" -only-testing:TalariaTests/SettingsChannelsTests`
- **THE GATE before the PR:** `scripts/mac/lane-gate.sh` (Debug suite + XCUITest + Release build). Task 8 moves `#if DEBUG` boundaries — Release green is a hard bar (252-F, #218 class).
- Commits end with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

## File map

| File | Fate |
|---|---|
| `Talaria/Features/Settings/SettingsChannels.swift` | CREATE — `SettingsSubsystem` enum + `SettingsCardValues` pure formatters |
| `Talaria/Features/Settings/SettingsChannelsScreen.swift` | CREATE — root: grid + deck + cards + banner |
| `Talaria/Features/Settings/SubsystemHero.swift` | CREATE — shared deck-page hero (Task 7) |
| `Talaria/Features/Settings/AppearanceDeckPage.swift` | CREATE — spectrum hero + read-only rows + browser handoff (Task 6) |
| `Talaria/Features/Settings/AboutSettingsContent.swift` | CREATE (Task 8) — the merge |
| `TalariaTests/SettingsChannelsTests.swift` | CREATE — formatter unit tests |
| `Talaria/ContentView.swift:270-276` | MODIFY — mount swap |
| Uplink/Server/Models/Voice/Privacy/Sessions/Diagnostics/Developer screens | MODIFY — `embedded:` flag (Task 4); heroes (Task 7); Developer gains batteries (Task 8) |
| `Talaria/Features/Settings/SystemSettingsScreen.swift` | DELETE (Task 8) |
| `Talaria/Features/Settings/DiagnosticsSettingsScreen.swift` | DELETE (Task 8, after content split) |
| `TalariaUITests/AppTemplateUITests.swift` | MODIFY (Task 9) |

---

### Task 1: Branch + bars pre-registered

**Files:** Modify: `OPEN_ITEMS.md` (#252 entry).

- [ ] **Step 1:** `git checkout -b claude/t27-252-settings-channels` (from current `main`).
- [ ] **Step 2:** In OPEN_ITEMS #252, replace "Bars pre-register HERE before the build runs." with the finalized bars block:

```markdown
**BARS (pre-registered 2026-08-05, before any build):**
- **252-A** — sim UI test: the settings sheet presents a grid with NINE subsystem
  entries whose value labels are live-store-derived (no "REACTOR"/"REALTIME"
  literals anywhere in the new surface).
- **252-B** — sim UI test: card tap opens the deck at that subsystem; counter reads
  `%02d / 09`; grid-toggle returns; swipe advances the counter.
- **252-C** — control parity: every control in
  `planning/superpowers/specs/2026-08-05-252-settings-inventory.md` §1–§11 is reachable
  in the new IA (checklist pass, sim or device).
- **252-D** — DEBUG build: the battery harness is reachable under Developer and
  `Battery results →` still opens; a battery button still arms (visual check).
- **252-E** — the four updated pairing/appearance UI tests green.
- **252-F** — Release build green
  (`xcodebuild -configuration Release … build CODE_SIGNING_ALLOWED=NO`).
A missed bar is a falsification, not a redefinition.
```

- [ ] **Step 3:** Commit: `docs(#252): pre-register bars 252-A..F` (+ trailer).

### Task 2: `SettingsSubsystem` + pure card-value formatters (TDD)

**Files:** Create `Talaria/Features/Settings/SettingsChannels.swift`, `TalariaTests/SettingsChannelsTests.swift`. Run `xcodegen generate`.

**Interfaces — Produces (later tasks consume exactly these):**
- `enum SettingsSubsystem: Int, CaseIterable, Identifiable` — cases in deck order: `uplink, server, models, voice, appearance, privacy, sessions, about, developer`; `var id: Int { rawValue }`; `var title: String` (uppercased display), `var chip: String`, `var indexLabel: String` ("01"…"09"), `var a11yID: String` ("settings.card.uplink" … / "settings.row.developer").
- `enum SettingsCardValues` — static, store-free, all returning `String`:
  - `uplink(state: HermesHostConnectionState, isDirect: Bool) -> String`
  - `server(activeProfileName: String?, isPaired: Bool) -> String`
  - `models(activeModelName: String?, brainLabel: String?) -> String`
  - `voice(readAloudOn: Bool, sessionLive: Bool, engineStateText: String) -> String`
  - `appearance(themeName: String, channelIndex: Int?) -> String`
  - `privacy(masterOn: Bool, health: Bool, location: Bool, motion: Bool) -> String`
  - `sessions(count: Int?, isPaired: Bool) -> String`
  - `about(isHealthy: Bool) -> String`
  - `developer(environmentLabel: String) -> String`

- [ ] **Step 1: Write the failing tests** (`TalariaTests/SettingsChannelsTests.swift`):

```swift
import Testing
@testable import Talaria

struct SettingsChannelsTests {
    @Test func deckOrderIsNineAndStable() {
        let all = SettingsSubsystem.allCases
        #expect(all.count == 9)
        #expect(all.first == .uplink)
        #expect(all.last == .developer)
        #expect(SettingsSubsystem.about.indexLabel == "08")
        #expect(SettingsSubsystem.uplink.a11yID == "settings.card.uplink")
        #expect(SettingsSubsystem.developer.a11yID == "settings.row.developer")
    }

    @Test func uplinkValueMirrorsRootRowLogic() {
        #expect(SettingsCardValues.uplink(state: .online, isDirect: true) == "DIRECT")
        #expect(SettingsCardValues.uplink(state: .online, isDirect: false) == "RELAY")
        #expect(SettingsCardValues.uplink(state: .offline, isDirect: false) == "STANDBY")
        #expect(SettingsCardValues.uplink(state: .unreachable, isDirect: false) == "OFFLINE")
        #expect(SettingsCardValues.uplink(state: .notConnected, isDirect: false) == "NOT LINKED")
    }

    @Test func serverValue() {
        #expect(SettingsCardValues.server(activeProfileName: "Studio", isPaired: true) == "STUDIO")
        #expect(SettingsCardValues.server(activeProfileName: nil, isPaired: true) == "PAIRED")
        #expect(SettingsCardValues.server(activeProfileName: nil, isPaired: false) == "NO PROFILE")
    }

    @Test func modelsValuePrefersModelThenBrain() {
        #expect(SettingsCardValues.models(activeModelName: "kimi-k3", brainLabel: nil) == "KIMI-K3")
        #expect(SettingsCardValues.models(activeModelName: nil, brainLabel: "ON-DEVICE") == "ON-DEVICE")
        #expect(SettingsCardValues.models(activeModelName: "", brainLabel: nil) == "SELECT")
        #expect(SettingsCardValues.models(activeModelName: nil, brainLabel: nil) == "SELECT")
    }

    @Test func voiceValue() {
        #expect(SettingsCardValues.voice(readAloudOn: true, sessionLive: false, engineStateText: "STANDBY") == "READ-ALOUD ON")
        #expect(SettingsCardValues.voice(readAloudOn: false, sessionLive: false, engineStateText: "STANDBY") == "READ-ALOUD OFF")
        #expect(SettingsCardValues.voice(readAloudOn: true, sessionLive: true, engineStateText: "SESSION LIVE") == "SESSION LIVE")
    }

    @Test func appearanceValue() {
        #expect(SettingsCardValues.appearance(themeName: "Deep Field", channelIndex: 3) == "DEEP FIELD · CH 03")
        #expect(SettingsCardValues.appearance(themeName: "Deep Field", channelIndex: nil) == "DEEP FIELD")
    }

    @Test func privacyStreamCount() {
        #expect(SettingsCardValues.privacy(masterOn: false, health: true, location: true, motion: true) == "0 STREAMS")
        #expect(SettingsCardValues.privacy(masterOn: true, health: true, location: false, motion: true) == "2 STREAMS")
        #expect(SettingsCardValues.privacy(masterOn: true, health: true, location: false, motion: false) == "1 STREAM")
    }

    @Test func sessionsValueHandlesUnloaded() {
        #expect(SettingsCardValues.sessions(count: nil, isPaired: false) == "…")
        #expect(SettingsCardValues.sessions(count: 12, isPaired: false) == "12 SESSIONS")
        #expect(SettingsCardValues.sessions(count: 1, isPaired: false) == "1 SESSION")
        #expect(SettingsCardValues.sessions(count: 148, isPaired: true) == "148 · SYNCED")
    }

    @Test func aboutAndDeveloper() {
        #expect(SettingsCardValues.about(isHealthy: true) == "HEALTHY")
        #expect(SettingsCardValues.about(isHealthy: false) == "DEGRADED")
        #expect(SettingsCardValues.developer(environmentLabel: "Production") == "PRODUCTION")
    }
}
```

- [ ] **Step 2:** `xcodegen generate`, then run the unit-test command (Global Constraints). Expected: FAIL — types not defined. **Watch it fail.**
- [ ] **Step 3: Implement** `Talaria/Features/Settings/SettingsChannels.swift`:

```swift
import SwiftUI

// MARK: - #252 Subsystem Channels — model layer
//
// Deck order and card telemetry for the settings grid/deck. Pure — no store
// access here so the formatters are unit-testable; SettingsChannelsScreen
// feeds them live values.
enum SettingsSubsystem: Int, CaseIterable, Identifiable {
    case uplink, server, models, voice, appearance, privacy, sessions, about, developer

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .uplink: "UPLINK"
        case .server: "SERVER"
        case .models: "MODELS"
        case .voice: "VOICE"
        case .appearance: "APPEARANCE"
        case .privacy: "PRIVACY"
        case .sessions: "SESSIONS"
        case .about: "ABOUT"
        case .developer: "DEVELOPER"
        }
    }

    var chip: String {
        switch self {
        case .uplink: "CONNECTION"
        case .server: "BACKEND PROFILES"
        case .models: "MODEL CATALOG"
        case .voice: "TALK ENGINE"
        case .appearance: "THEME CHANNELS"
        case .privacy: "PERMISSIONS"
        case .sessions: "STORAGE & DATA"
        case .about: "DIAGNOSTICS"
        case .developer: "INTERNAL TOOLS"
        }
    }

    var indexLabel: String { String(format: "%02d", rawValue + 1) }

    var a11yID: String {
        self == .developer ? "settings.row.developer" : "settings.card.\(String(describing: self))"
    }
}

enum SettingsCardValues {
    static func uplink(state: HermesHostConnectionState, isDirect: Bool) -> String {
        switch state {
        case .online: isDirect ? "DIRECT" : "RELAY"
        case .offline: "STANDBY"
        case .unreachable: "OFFLINE"
        case .notConnected: "NOT LINKED"
        }
    }

    static func server(activeProfileName: String?, isPaired: Bool) -> String {
        if let name = activeProfileName, !name.isEmpty { return name.uppercased() }
        return isPaired ? "PAIRED" : "NO PROFILE"
    }

    static func models(activeModelName: String?, brainLabel: String?) -> String {
        if let name = activeModelName, !name.isEmpty { return name.uppercased() }
        if let brain = brainLabel, !brain.isEmpty { return brain.uppercased() }
        return "SELECT"
    }

    static func voice(readAloudOn: Bool, sessionLive: Bool, engineStateText: String) -> String {
        if sessionLive { return engineStateText.uppercased() }
        return readAloudOn ? "READ-ALOUD ON" : "READ-ALOUD OFF"
    }

    static func appearance(themeName: String, channelIndex: Int?) -> String {
        guard let index = channelIndex else { return themeName.uppercased() }
        return "\(themeName.uppercased()) · CH \(String(format: "%02d", index))"
    }

    static func privacy(masterOn: Bool, health: Bool, location: Bool, motion: Bool) -> String {
        let count = masterOn ? [health, location, motion].filter { $0 }.count : 0
        return "\(count) STREAM\(count == 1 ? "" : "S")"
    }

    static func sessions(count: Int?, isPaired: Bool) -> String {
        guard let count else { return "…" }
        if isPaired { return "\(count) · SYNCED" }
        return "\(count) SESSION\(count == 1 ? "" : "S")"
    }

    static func about(isHealthy: Bool) -> String { isHealthy ? "HEALTHY" : "DEGRADED" }

    static func developer(environmentLabel: String) -> String { environmentLabel.uppercased() }
}
```

- [ ] **Step 4:** Re-run the tests. Expected: PASS, and the reported count INCREASED vs the pre-task suite.
- [ ] **Step 5:** Commit: `feat(#252): SettingsSubsystem + card value formatters (TDD)`.

### Task 3: `SettingsChannelsScreen` grid shell + mount swap

**Files:** Create `Talaria/Features/Settings/SettingsChannelsScreen.swift`; Modify `Talaria/ContentView.swift:270-276`. `xcodegen generate`.

**Interfaces — Consumes:** Task 2's enum + formatters. Environment: `AppContainer`, `AppSessionStore`, `HermesHostStore`, `PairingStore`, `SettingsStore`, `TabRouter` (same set as the old root, `SystemSettingsScreen.swift:15-21`).
**Produces:** `SettingsChannelsScreen` with `enum Mode: Equatable { case grid, deck(Int) }`, `@State private var mode: Mode = .grid`, `@State private var sessionCount: Int?`; private `func openSubsystem(_ s: SettingsSubsystem)`; private `func cardValue(_ s: SettingsSubsystem) -> String` and `func cardIsAccented(_ s: SettingsSubsystem) -> Bool`. Task 5 replaces the interim NavigationLinks with `mode = .deck(index)`.

- [ ] **Step 1: Implement the screen.** Full reference implementation (interim behavior: cards push the EXISTING sub-screens via NavigationLink so nothing regresses before Task 5):

```swift
import SwiftUI

// MARK: - #252 Settings root — Subsystem Channels
//
// Grid of nine live-telemetry cards (Claude Design 1c). Deck mode arrives in
// Task 5; until then cards push the existing sub-screens, so every control
// stays reachable at every commit on this lane.
struct SettingsChannelsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppContainer.self) private var container
    @Environment(AppSessionStore.self) private var sessionStore
    @Environment(HermesHostStore.self) private var hostStore
    @Environment(PairingStore.self) private var pairingStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(TabRouter.self) private var router

    enum Mode: Equatable { case grid, deck(Int) }
    @State private var mode: Mode = .grid
    @State private var sessionCount: Int?

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(spacing: Design.Spacing.md) {
                        if !pairingStore.isPaired { upgradeBanner }
                        cardGrid
                        developerRow
                        footer
                    }
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.vertical, Design.Spacing.sm)
                }
            }
        }
        .navigationTitle("System")
        .toolbarVisibility(.hidden, for: .navigationBar)
        .task {
            await hostStore.refresh()
            sessionCount = await container.chatStore.loadSessions().count
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            GlassCircleButton(icon: "xmark", accessibilityLabel: "Close settings") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            VStack(spacing: Design.Spacing.xxs) {
                MonoLabel("SYSTEM", size: 9, weight: .medium,
                          tracking: Design.Tracking.monoXWide, color: Design.Colors.mutedForeground)
                MonoLabel("09 SUBSYSTEMS", size: 10, weight: .medium,
                          tracking: Design.Tracking.monoWide, color: Design.Brand.accent)
                    .accessibilityIdentifier("settings.deck.counter")
            }
            Spacer()
            // Grid-toggle button: accent-active in grid mode. Becomes the
            // deck/grid flip in Task 5; inert-but-visible until then.
            gridToggleGlyph
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.top, Design.Spacing.xs)
        .padding(.bottom, Design.Spacing.sm)
    }

    private var gridToggleGlyph: some View {
        GlassCircleButton(icon: "square.grid.2x2", accessibilityLabel: "Toggle overview") {
            // Task 5 wires deck↔grid; in grid-only Stage 1 this is a no-op.
        }
    }

    // MARK: Upgrade banner (unpaired only — label containment is a test contract)

    private var upgradeBanner: some View {
        Button {
            router.dismissSheet()
            router.navigate(to: .connectHost)
        } label: {
            VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                HStack {
                    Text("Connect Hermes Desktop")
                        .font(Design.Typography.body(15, weight: .semibold))
                        .foregroundStyle(Design.Colors.foregroundBright)
                    Spacer(minLength: Design.Spacing.xs)
                    MonoLabel("UPGRADE", size: 10, weight: .medium,
                              tracking: Design.Tracking.mono, color: Design.Brand.accent)
                }
                Text("Adds server sessions, sensors & desktop models")
                    .font(Design.Typography.caption2)
                    .foregroundStyle(Design.Colors.secondaryForeground)
            }
            .padding(Design.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hudPanel(
                cornerRadius: Design.CornerRadius.lg,
                borderColor: Design.Colors.strongBorder,
                fill: Design.Colors.accentTint(0.06),
                innerGlow: true
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.upgradeBanner")
    }

    // MARK: Grid

    private let gridColumns = [GridItem(.flexible(), spacing: Design.Spacing.sm),
                               GridItem(.flexible(), spacing: Design.Spacing.sm)]

    private var cardGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: Design.Spacing.sm) {
            ForEach(SettingsSubsystem.allCases.filter { $0 != .developer }) { subsystem in
                NavigationLink { interimDestination(subsystem) } label: {
                    SubsystemCard(
                        subsystem: subsystem,
                        value: cardValue(subsystem),
                        accented: cardIsAccented(subsystem)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(subsystem.a11yID)
            }
        }
        .accessibilityIdentifier("settings.grid")
    }

    private var developerRow: some View {
        NavigationLink { DeveloperSettingsScreen() } label: {
            HStack(spacing: Design.Spacing.sm) {
                MonoLabel(SettingsSubsystem.developer.indexLabel, size: 10, weight: .bold,
                          tracking: Design.Tracking.monoXWide, color: Design.Colors.mutedForeground)
                Text("DEVELOPER")
                    .font(Design.Typography.display(13, weight: .bold, relativeTo: .subheadline))
                    .tracking(Design.Tracking.display)
                    .foregroundStyle(Design.Colors.foreground)
                Spacer(minLength: Design.Spacing.xs)
                MonoLabel(SettingsCardValues.developer(
                    environmentLabel: settingsStore.settings.environment.displayLabel),
                          size: 9, weight: .medium,
                          tracking: Design.Tracking.mono, color: Design.Colors.secondaryForeground)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Design.Colors.accentTint(0.7))
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.sm)
            .hudPanel(
                cornerRadius: Design.CornerRadius.md,
                borderColor: Design.Colors.accentTint(0.12),
                fill: Design.Colors.background.opacity(0.4),
                innerGlow: false
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(SettingsSubsystem.developer.a11yID)
    }

    private var footer: some View {
        MonoLabel("TAP A CARD · TALARIA v\(appVersion) · DEVICE-BOUND", size: 9,
                  weight: .regular, tracking: Design.Tracking.monoWide,
                  color: Design.Colors.dimForeground)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, Design.Spacing.sm)
    }

    // MARK: Interim destinations (replaced by the deck in Task 5)

    @ViewBuilder
    private func interimDestination(_ subsystem: SettingsSubsystem) -> some View {
        switch subsystem {
        case .uplink: UplinkSettingsScreen()
        case .server: ServerSettingsScreen()
        case .models: ModelsSettingsScreen()
        case .voice: VoiceSettingsScreen()
        case .appearance: AppearanceSettingsScreen()
        case .privacy: PrivacySettingsScreen()
        case .sessions: SessionsSettingsScreen()
        case .about: DiagnosticsSettingsScreen()
        case .developer: DeveloperSettingsScreen()
        }
    }

    // MARK: Telemetry (live stores → Task 2 formatters)

    private var effectiveConnectionState: HermesHostConnectionState {
        if container.chatStore.directConnectionStatus == .connected { return .online }
        return hostStore.connectionState
    }

    private func cardValue(_ subsystem: SettingsSubsystem) -> String {
        switch subsystem {
        case .uplink:
            SettingsCardValues.uplink(
                state: effectiveConnectionState,
                isDirect: container.chatStore.directConnectionStatus == .connected)
        case .server:
            SettingsCardValues.server(
                activeProfileName: container.profilesStore?.activeProfile?.name,
                isPaired: pairingStore.isPaired)
        case .models:
            SettingsCardValues.models(
                activeModelName: container.chatStore.activeModelName,
                brainLabel: container.chatBackendRouter?.activeBrain.monoLabel)
        case .voice:
            SettingsCardValues.voice(
                readAloudOn: settingsStore.settings.readAloudAutoPlay,
                sessionLive: false,
                engineStateText: "")
        case .appearance:
            SettingsCardValues.appearance(
                themeName: currentThemeName, channelIndex: currentChannelIndex)
        case .privacy:
            SettingsCardValues.privacy(
                masterOn: settingsStore.settings.sensorStreamingEnabled,
                health: settingsStore.settings.healthCollectionEnabled,
                location: settingsStore.settings.locationCollectionEnabled,
                motion: settingsStore.settings.motionCollectionEnabled)
        case .sessions:
            SettingsCardValues.sessions(count: sessionCount, isPaired: pairingStore.isPaired)
        case .about:
            SettingsCardValues.about(isHealthy: effectiveConnectionState == .online)
        case .developer:
            SettingsCardValues.developer(
                environmentLabel: settingsStore.settings.environment.displayLabel)
        }
    }

    private func cardIsAccented(_ subsystem: SettingsSubsystem) -> Bool {
        switch subsystem {
        case .uplink: effectiveConnectionState == .online
        case .server: container.profilesStore?.activeProfile != nil
        case .models: container.chatStore.activeModelName?.isEmpty == false
        case .voice: settingsStore.settings.readAloudAutoPlay
        case .appearance: true
        case .privacy:
            settingsStore.settings.sensorStreamingEnabled &&
            (settingsStore.settings.healthCollectionEnabled ||
             settingsStore.settings.locationCollectionEnabled ||
             settingsStore.settings.motionCollectionEnabled)
        case .sessions: sessionCount != nil
        case .about: effectiveConnectionState == .online
        case .developer: false
        }
    }

    // Same channel list the #244 browser counts with (AppearanceSettingsScreen
    // builds `ThemeChannels.build(on:)` and indexes into it).
    private var currentThemeName: String {
        ThemeRuntime.shared.theme.displayLabel
    }

    private var currentChannelIndex: Int? {
        let channels = ThemeChannels.build(on: Date())
        if settingsStore.settings.appearanceThemeMode == .automatic {
            return channels.firstIndex { $0.id == "auto" }
        }
        let stored = settingsStore.settings.appearanceTheme
        return channels.firstIndex { $0.kind == .theme && $0.definition.appearanceTheme == stored }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
}

// MARK: - Grid card

private struct SubsystemCard: View {
    let subsystem: SettingsSubsystem
    let value: String
    let accented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MonoLabel(subsystem.indexLabel, size: 10, weight: .bold,
                      tracking: Design.Tracking.monoXWide,
                      color: accented ? Design.Brand.accent : Design.Colors.mutedForeground)
            Spacer(minLength: Design.Spacing.sm)
            Text(subsystem.title)
                .font(Design.Typography.display(18, weight: .bold, relativeTo: .headline))
                .tracking(Design.Tracking.display)
                .foregroundStyle(Design.Colors.foregroundBright)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            MonoLabel(value, size: 9, weight: .medium,
                      tracking: Design.Tracking.mono,
                      color: accented ? Design.Brand.accent : Design.Colors.mutedForeground)
                .lineLimit(1)
                .padding(.top, Design.Spacing.xxs)
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .hudPanel(
            cornerRadius: Design.CornerRadius.lg,
            borderColor: subsystem == .appearance
                ? Design.Colors.strongBorder : Design.Colors.accentTint(0.16),
            fill: subsystem == .appearance
                ? Design.Colors.accentTint(0.14) : Design.Colors.background.opacity(0.5),
            innerGlow: subsystem == .appearance
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(subsystem.title) \(value)")
    }
}
```

Adjust only where a named token does not exist (e.g. if `Design.Typography.display(_:weight:relativeTo:)` differs, use the exact signature `SystemSettingsScreen`/`VoiceSettingsScreen` already use — those two files are the token reference).
- [ ] **Step 2:** In `Talaria/ContentView.swift` case `.settings`, replace `SystemSettingsScreen()` with `SettingsChannelsScreen()` (comment: `// #252: Subsystem Channels root (1c). SystemSettingsScreen retired in Task 8.`).
- [ ] **Step 3:** `xcodegen generate`; run the CLI compile check (backgrounded). Expected: BUILD SUCCEEDED.
- [ ] **Step 4:** Boot a CC sim, install, screenshot the settings sheet: nine entries, live values, banner present when unpaired. (`xcrun simctl` + the xc-testing screenshot tools.)
- [ ] **Step 5:** Commit: `feat(#252): SettingsChannelsScreen grid shell replaces the root (interim pushes)`.

### Task 4: `embedded:` mode on seven sub-screens

**Files:** Modify `UplinkSettingsScreen.swift`, `ServerSettingsScreen.swift`, `ModelsSettingsScreen.swift`, `VoiceSettingsScreen.swift`, `PrivacySettingsScreen.swift`, `SessionsSettingsScreen.swift`, `DeveloperSettingsScreen.swift`. (NOT Appearance — Task 6 builds its deck page. NOT Diagnostics — Task 8 splits it; until then the About deck page will embed `DiagnosticsSettingsScreen(embedded: true)`, so ALSO apply the flag to `DiagnosticsSettingsScreen.swift` — eight files total.)

**Interfaces — Produces:** every listed screen gains `var embedded: Bool = false` and renders without its own background/header when `embedded == true`. Existing call sites compile unchanged (defaulted parameter).

- [ ] **Step 1: Apply the recipe to each file.** The recipe, shown in full on `VoiceSettingsScreen.swift` (every file follows the same three edits):

```swift
struct VoiceSettingsScreen: View {
    // #252: deck pages supply the background and top bar; the screen keeps
    // owning its content, tasks, and sheets in both presentations.
    var embedded: Bool = false
    // …existing properties unchanged…

    var body: some View {
        ZStack {
            if !embedded {
                HUDScreenBackground()
                    .ignoresSafeArea()
            }
            ScrollView {
                VStack(spacing: Design.Spacing.lg) {
                    if !embedded {
                        SettingsScreenHeader(title: "Voice", subtitle: "Talk Engine") { dismiss() }
                    }
                    heroPanel
                    // …rest of the sections unchanged…
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)
            }
        }
        .navigationTitle("Voice")
        .toolbarVisibility(.hidden, for: .navigationBar)
        .task { await talkStore.refreshReadiness() }
    }
```

Per-file specifics (the line to wrap is each screen's header call; all else identical):
| File | Header call to wrap in `if !embedded` |
|---|---|
| `UplinkSettingsScreen.swift` | `SettingsScreenHeader(title: "Uplink", subtitle: <activeProfileName expr>) { dismiss() }` |
| `ServerSettingsScreen.swift` | `SettingsScreenHeader(title: "Server", subtitle: "Backend Profiles") { dismiss() }` |
| `ModelsSettingsScreen.swift` | its BESPOKE header block (GlassCircleButton back + `Text("MODELS")` + spacer HStack) — wrap the whole HStack |
| `VoiceSettingsScreen.swift` | shown above |
| `PrivacySettingsScreen.swift` | `SettingsScreenHeader(title: "Privacy", subtitle: "Permissions") { dismiss() }` |
| `SessionsSettingsScreen.swift` | `SettingsScreenHeader(title: "Sessions", subtitle: "Storage & Data") { dismiss() }` |
| `DiagnosticsSettingsScreen.swift` | `SettingsScreenHeader(title: "Diagnostics", subtitle: "System Health") { dismiss() }` |
| `DeveloperSettingsScreen.swift` | `SettingsScreenHeader(title: "Developer", subtitle: "Internal Tools") { dismiss() }` |

(Exact title/subtitle strings per the inventory §2–§11; read each file before editing — if a screen's header call differs from the table, wrap what is actually there, never invent.)
- [ ] **Step 2:** CLI compile check (backgrounded). Expected: BUILD SUCCEEDED — defaulted parameter means zero call-site churn.
- [ ] **Step 3:** Run the full existing unit suite once (no `-only-testing`). Expected: same green count as pre-task.
- [ ] **Step 4:** Commit: `feat(#252): embedded presentation mode on eight sub-screens`.

### Task 5: The deck — paged TabView, dots, counter, toggle

**Files:** Modify `SettingsChannelsScreen.swift`.

**Interfaces — Consumes:** Task 4's `embedded:` flags. **Produces:** `mode`-driven body; `openSubsystem(_:)` used by cards; deck pages for all nine subsystems (Appearance page is an interim button-only page until Task 6).

- [ ] **Step 1: Replace the interim NavigationLinks with deck navigation.** Body becomes:

```swift
    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                switch mode {
                case .grid: gridScroll          // Task 3's ScrollView content
                case .deck: deckPager
                }
            }
        }
        .navigationTitle("System")
        .toolbarVisibility(.hidden, for: .navigationBar)
        .task {
            await hostStore.refresh()
            sessionCount = await container.chatStore.loadSessions().count
        }
    }
```

with these additions (full code):

```swift
    private var deckIndex: Int {
        if case .deck(let i) = mode { return i }
        return 0
    }

    private func openSubsystem(_ subsystem: SettingsSubsystem) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
            mode = .deck(subsystem.rawValue)
        }
    }

    private var reduceMotion: Bool { settingsStore.settings.reduceMotion }

    private var deckPager: some View {
        VStack(spacing: 0) {
            TabView(selection: Binding(
                get: { deckIndex },
                set: { mode = .deck($0) }
            )) {
                ForEach(SettingsSubsystem.allCases) { subsystem in
                    deckPage(subsystem)
                        .tag(subsystem.rawValue)
                        .accessibilityIdentifier("settings.deck.page.\(String(describing: subsystem))")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            pageDots
        }
    }

    @ViewBuilder
    private func deckPage(_ subsystem: SettingsSubsystem) -> some View {
        switch subsystem {
        case .uplink: UplinkSettingsScreen(embedded: true)
        case .server: ServerSettingsScreen(embedded: true)
        case .models: ModelsSettingsScreen(embedded: true)
        case .voice: VoiceSettingsScreen(embedded: true)
        case .appearance: appearanceInterimPage   // replaced in Task 6
        case .privacy: PrivacySettingsScreen(embedded: true)
        case .sessions: SessionsSettingsScreen(embedded: true)
        case .about: DiagnosticsSettingsScreen(embedded: true)   // merge lands in Task 8
        case .developer: DeveloperSettingsScreen(embedded: true)
        }
    }

    // Interim until Task 6: preserves the browser handoff so Appearance never
    // becomes unreachable mid-lane.
    private var appearanceInterimPage: some View {
        VStack(spacing: Design.Spacing.lg) {
            Spacer()
            NavigationLink { AppearanceSettingsScreen() } label: {
                MonoLabel("OPEN CHANNEL BROWSER", size: 12, weight: .bold,
                          tracking: Design.Tracking.monoWide, color: Design.Colors.foregroundBright)
                    .padding(.vertical, Design.Spacing.md)
                    .frame(maxWidth: .infinity)
                    .hudPanel(cornerRadius: Design.CornerRadius.lg,
                              borderColor: Design.Colors.strongBorder,
                              fill: Design.Colors.accentTint(0.12), innerGlow: true)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, Design.Spacing.md)
    }

    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(SettingsSubsystem.allCases) { subsystem in
                Button {
                    mode = .deck(subsystem.rawValue)
                } label: {
                    Capsule()
                        .fill(subsystem.rawValue == deckIndex
                              ? Design.Brand.accent
                              : Design.Colors.accentTint(0.25))
                        .frame(width: subsystem.rawValue == deckIndex ? 20 : 5, height: 5)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(subsystem.title)")
            }
        }
        .padding(.vertical, Design.Spacing.sm)
    }
```

Top-bar changes: left button = `✕` (dismiss) in grid, `‹` (back to grid) in deck; kicker `SYSTEM`/`SUBSYSTEM`; counter `09 SUBSYSTEMS` / `String(format: "%02d / 09", deckIndex + 1)` (same `settings.deck.counter` identifier); grid-toggle button now flips `mode` both ways and is accent-styled when `mode == .grid`. Card taps and the developer row call `openSubsystem(_:)` (NavigationLinks removed). KEEP Esc = dismiss in both modes.
- [ ] **Step 2:** CLI compile check (backgrounded). Expected: BUILD SUCCEEDED.
- [ ] **Step 3:** Sim smoke: card tap lands on the right page (counter matches), swipe advances, dots jump, toggle returns to grid, Uplink page shows Base URL/API Key controls (embedded content real). Screenshot each.
- [ ] **Step 4:** Commit: `feat(#252): subsystem deck — paged TabView, dots, counter, grid toggle`.

### Task 6: Appearance deck page

**Files:** Create `Talaria/Features/Settings/AppearanceDeckPage.swift`; Modify `SettingsChannelsScreen.swift` (swap `appearanceInterimPage` → `AppearanceDeckPage()`). `xcodegen generate`.

- [ ] **Step 1: Implement** (full code):

```swift
import SwiftUI

// MARK: - #252 Appearance deck page
//
// The deck entry for the #244 channel browser — a spectrum hero + read-only
// tuning values + the handoff button. The browser itself is UNCHANGED; this
// page never duplicates its controls.
struct AppearanceDeckPage: View {
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        ScrollView {
            VStack(spacing: Design.Spacing.lg) {
                spectrumHero
                infoPanel
                NavigationLink { AppearanceSettingsScreen() } label: {
                    MonoLabel("OPEN CHANNEL BROWSER", size: 12, weight: .bold,
                              tracking: Design.Tracking.monoWide,
                              color: Design.Colors.foregroundBright)
                        .padding(.vertical, Design.Spacing.md)
                        .frame(maxWidth: .infinity)
                        .hudPanel(cornerRadius: Design.CornerRadius.lg,
                                  borderColor: Design.Colors.strongBorder,
                                  fill: Design.Colors.accentTint(0.12), innerGlow: true)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.appearance.openBrowser")
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.sm)
        }
    }

    private var spectrumHero: some View {
        VStack(spacing: Design.Spacing.sm) {
            RoundedRectangle(cornerRadius: Design.CornerRadius.xl)
                .fill(LinearGradient(
                    colors: [Design.Colors.background,
                             Design.Brand.accentDeep,
                             Design.Brand.accent,
                             Design.Brand.accentBright],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(height: 140)
                .overlay(alignment: .bottomLeading) {
                    MonoLabel(channelLabel, size: 12, weight: .bold,
                              tracking: Design.Tracking.monoXWide,
                              color: Design.Colors.background)
                        .padding(Design.Spacing.md)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Design.CornerRadius.xl)
                        .strokeBorder(Design.Colors.strongBorder, lineWidth: 1)
                }
                .accessibilityHidden(true)
            Text(themeName.uppercased())
                .font(Design.Typography.screenTitle2)
                .tracking(Design.Tracking.display)
                .foregroundStyle(Design.Colors.foregroundBright)
            MonoLabel(accentLine, size: 11, weight: .medium,
                      tracking: Design.Tracking.monoWide, color: Design.Brand.accent)
        }
    }

    private var infoPanel: some View {
        VStack(spacing: 0) {
            infoRow("GLOW", String(format: "%.1f×", settingsStore.settings.hudGlowIntensity))
            divider
            infoRow("GRID", String(describing: settingsStore.settings.gridDensity).uppercased())
            divider
            infoRow("APP ICON", currentIconName)
        }
        .hudPanel(cornerRadius: Design.CornerRadius.lg,
                  borderColor: Design.Colors.accentTint(0.14),
                  fill: Design.Colors.background.opacity(0.5), innerGlow: false)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            MonoLabel(label, size: 10, weight: .medium,
                      tracking: Design.Tracking.mono, color: Design.Colors.secondaryForeground)
            Spacer()
            MonoLabel(value, size: 10, weight: .medium,
                      tracking: Design.Tracking.mono, color: Design.Colors.foreground)
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
    }

    private var divider: some View {
        Rectangle().fill(Design.Colors.hairline).frame(height: 1)
            .padding(.horizontal, Design.Spacing.md)
    }

    private var themeName: String { ThemeRuntime.shared.theme.displayLabel }

    private var accentLine: String {
        ThemeRuntime.shared.accent.displayLabel(for: ThemeRuntime.shared.theme).uppercased()
    }

    private var channelLabel: String {
        let channels = ThemeChannels.build(on: Date())
        let index: Int?
        if settingsStore.settings.appearanceThemeMode == .automatic {
            index = channels.firstIndex { $0.id == "auto" }
        } else {
            let stored = settingsStore.settings.appearanceTheme
            index = channels.firstIndex { $0.kind == .theme && $0.definition.appearanceTheme == stored }
        }
        guard let index else { return "CHANNEL —" }
        return String(format: "CHANNEL %02d", index)
    }

    private var currentIconName: String {
        AppIconCatalog.option(forAlternateIconName: UIApplication.shared.alternateIconName)?
            .displayName.uppercased() ?? "DEFAULT"
    }
}
```

(Verify `ThemeRuntime.shared.theme.displayLabel`, `accent.displayLabel(for:)`, and `AppIconCatalog.option(forAlternateIconName:)` signatures against `Design.swift` / `AppIconCatalog.swift` before building — use whatever the Appearance browser and Tuning sheet already call for the SAME values; never invent a parallel lookup.)
- [ ] **Step 2:** Swap into `deckPage(.appearance)`; delete `appearanceInterimPage`.
- [ ] **Step 3:** `xcodegen generate`; compile check; sim smoke (hero shows current theme + channel number; browser opens; back returns to deck). Commit: `feat(#252): Appearance deck page with browser handoff`.

### Task 7: `SubsystemHero` + per-page heroes

**Files:** Create `Talaria/Features/Settings/SubsystemHero.swift`; Modify the seven embedded screens (hero insertion at top of embedded content) + `VoiceSettingsScreen` (its old `heroPanel` remains for standalone mode only) and `UplinkSettingsScreen` (its link panel likewise).

**Interfaces — Produces:**

```swift
struct SubsystemHero: View {
    enum Motif { case rings, profileBars, barChart, waveform, hatchShield, stackedRows, sparkline, squares }
    let motif: Motif
    let title: String
    let status: String
    let statusColor: Color
    let chip: String
    let accented: Bool
}
```

- [ ] **Step 1: Implement `SubsystemHero`** — centered VStack: motif drawing (~120pt, plain `Circle().strokeBorder`/`Capsule`/`Path` shapes tinted `accented ? Design.Brand.accent : Design.Colors.mutedForeground`, `accessibilityHidden(true)`), `Text(title)` at `Design.Typography.screenTitle2` scale ×1.4 (`display(34, weight: .bold, relativeTo: .largeTitle)` if the token family supports it — otherwise the largest existing display token), `MonoLabel(status, …, color: statusColor)`, chip capsule (`MonoLabel(chip)` in a bordered rounded rect, muted). Motif drawings per subsystem mirror the prototype (concentric rings / stacked outlined bars / bar chart / thin waveform bars / hatched hexagon via `clipShape` on a repeating-gradient / stacked rows / sparkline `Path` / 3×3 squares). Keep every motif under 40 lines; no images, no new assets.
- [ ] **Step 2:** For each embedded screen, insert at the top of the scroll content when `embedded == true`:

```swift
if embedded {
    SubsystemHero(motif: .waveform, title: "VOICE",
                  status: engineState.text, statusColor: engineState.color,
                  chip: "TALK ENGINE", accented: engineState.color == Design.Brand.accent)
}
```

Per-page (motif, status source — all existing expressions named in the inventory): Uplink(.rings, the link panel's `linkTitle`+detail logic, its status color); Server(.profileBars, active-profile line); Models(.barChart, active model line); Voice(.waveform, `engineState`); Privacy(.hatchShield, stream-count line via `SettingsCardValues.privacy`); Sessions(.stackedRows, `SettingsCardValues.sessions` + counts); About/Diagnostics(.sparkline, HEALTHY/DEGRADED); Developer(.squares, environment). Where a screen already renders an equivalent top panel (Voice `heroPanel`, Uplink link panel), wrap that old panel in `if !embedded` so it survives standalone mode and the deck shows only the new hero.
- [ ] **Step 3:** `xcodegen generate`; compile check; sim sweep of all nine pages (screenshots). Commit: `feat(#252): SubsystemHero + per-page heroes`.

### Task 8: The About merge + battery relocation + deletions

**Files:** Create `Talaria/Features/Settings/AboutSettingsContent.swift`; Modify `DeveloperSettingsScreen.swift`, `SettingsChannelsScreen.swift`, `ContentView.swift` (comment only); Delete `SystemSettingsScreen.swift`, `DiagnosticsSettingsScreen.swift`. `xcodegen generate`.

- [ ] **Step 1:** Create `AboutSettingsContent.swift` by MOVING (verbatim, minus the battery/local-brain block and minus `SettingsScreenHeader`) these members out of `DiagnosticsSettingsScreen`: `statusPanel`, the voice panel, the sensor panel, `infoGrid`, `logsSection`, `footerLinks`, and every helper/computed property they reference (inventory §10 a/b/d/e/f/g). Add the absorbed root footer line (`TALARIA v… · DEVICE-BOUND`) at the bottom. Struct signature: `struct AboutSettingsContent: View` with the same `@Environment` set the moved members need — copy the environment lines from `DiagnosticsSettingsScreen` and prune unused ones by compiler error.
- [ ] **Step 2:** In `DeveloperSettingsScreen.swift`, add after the `// Build` section:

```swift
#if DEBUG
    batteriesSection   // #252: relocated verbatim from DiagnosticsSettingsScreen (#200 harness)
#endif
```

and MOVE (verbatim — zero renames, zero behavior change) the entire `// Local brain — #102` block from `DiagnosticsSettingsScreen`: the session-shape picker, every battery/probe button, the WeatherKit probe row, the alarm sweep, the forced-trip panel, the `Battery results →` NavigationLink, and all their `@State`/helpers, under a `// MARK: Batteries (#200 harness — relocated by #252)` extension gated `#if DEBUG`. Section header label: `groupLabel("// Batteries (#200 harness)")` (match the screen's existing group-label helper).
- [ ] **Step 3:** `deckPage(.about)` → `ScrollView { AboutSettingsContent() … }` (match the embedded padding pattern from Task 4's recipe). Delete `SystemSettingsScreen.swift` and `DiagnosticsSettingsScreen.swift`. Fix any stray references by grep: `grep -rn "SystemSettingsScreen\|DiagnosticsSettingsScreen" Talaria TalariaTests TalariaUITests`.
- [ ] **Step 4:** `xcodegen generate`; compile check Debug. Then **compile check Release** (same command, `-configuration Release`) — the moved `#if DEBUG` boundary is exactly the #218 trap; Release must be green BEFORE commit. Expected: both BUILD SUCCEEDED.
- [ ] **Step 5:** Sim smoke DEBUG: Developer page shows the batteries section; `Battery results →` opens; About page shows status/sensor/info/logs/footer. Commit: `feat(#252): About merge + battery harness relocation; retire SystemSettings + Diagnostics screens`.

### Task 9: UI-test rework + new coverage

**Files:** Modify `TalariaUITests/AppTemplateUITests.swift`.

- [ ] **Step 1: Update the four navigation tests** per the spec contract:
  - `testMockPairingViaSettingsEntryPoint` — entry row → `app.buttons["settings.upgradeBanner"]` (fallback: containment on "Connect Hermes Desktop" still valid; assert BOTH).
  - `testPairedRelaunchSkipsPairingEntry` — assert `settings.upgradeBanner` does NOT exist after pairing.
  - `testDisconnectReturnsToStandaloneChat` — "Hermes Host" row → `app.buttons["settings.card.uplink"].tap()`, then on the deck page tap "Pairing & Devices" (containment), then Disconnect; keep the iOS-27 re-tap hedge as-is.
  - `testAppearanceChannelBrowserAppliesThemeOnLand` — `settings.card.appearance` → `settings.appearance.openBrowser` → existing `appearance.channelCounter` assertions unchanged.
- [ ] **Step 2: Add two tests** (252-A/252-B evidence):

```swift
@MainActor
func testSettingsGridPresentsNineSubsystems() throws {
    let app = launchStandalone()   // reuse the file's existing launch helper
    app.buttons["Open settings"].tap()
    XCTAssertTrue(app.otherElements["settings.grid"].waitForExistence(timeout: 10),
                  "Settings must open on the subsystem grid (#252)")
    for id in ["settings.card.uplink", "settings.card.server", "settings.card.models",
               "settings.card.voice", "settings.card.appearance", "settings.card.privacy",
               "settings.card.sessions", "settings.card.about", "settings.row.developer"] {
        XCTAssertTrue(app.buttons[id].exists, "\(id) card must be present")
    }
    XCTAssertFalse(app.staticTexts["REACTOR"].exists, "hardcoded root values must be gone (#252)")
}

@MainActor
func testSettingsDeckNavigation() throws {
    let app = launchStandalone()
    app.buttons["Open settings"].tap()
    app.buttons["settings.card.uplink"].tap()
    let counter = app.staticTexts["settings.deck.counter"]
    XCTAssertTrue(counter.waitForExistence(timeout: 10), "deck counter must appear")
    XCTAssertEqual(counter.label, "01 / 09")
    app.otherElements["settings.deck.page.uplink"].swipeLeft()
    XCTAssertEqual(counter.label, "02 / 09", "swipe must advance the deck")
    app.buttons["Toggle overview"].tap()
    XCTAssertTrue(app.otherElements["settings.grid"].waitForExistence(timeout: 5),
                  "grid toggle must return to the overview")
}
```

Adapt the launch-helper name and element queries to the file's actual idioms (read the file first; the two tests above are the required assertions, not sacred selectors — e.g. the counter may be a `staticTexts` or `otherElements` match depending on `MonoLabel`'s a11y shape; use what Task 3/5 actually produced).
- [ ] **Step 3:** Run the XCUITest suite on a CC sim; confirm the count MOVED and all settings tests green.
- [ ] **Step 4:** Commit: `test(#252): settings navigation tests for the channels IA (252-A/B/E)`.

### Task 10: Polish, gate, bars, PR

**Files:** touch-ups only; `OPEN_ITEMS.md` (#252 verdicts).

- [ ] **Step 1:** Reduce-motion audit (deck animation gated on `settings.reduceMotion` — verify by toggling in sim). iPad-width sanity: run on an iPad-class sim viewport; grid stays 2-col (acceptable) with no clipping; deck pages fill.
- [ ] **Step 2:** 252-C control-parity checklist: walk `2026-08-05-252-settings-inventory.md` §1–§11 top to bottom on the sim, ticking every control reachable. Record any misses and fix before proceeding.
- [ ] **Step 3:** **THE GATE:** `scripts/mac/lane-gate.sh` (backgrounded; poll). Requires positive markers from Debug suite + XCUITest + Release build. 252-F rides the Release leg.
- [ ] **Step 4:** OPEN_ITEMS #252: record bar verdicts (252-A..F, each with evidence — test names, gate log path, checklist result). Honest recording: any missed bar is a falsification and stops the lane here.
- [ ] **Step 5:** PR: title `feat(#252): Settings Subsystem Channels — grid + deck (design 1c)`, body = spec link + bars table + screenshots; `Co-Authored-By` trailer; PR body ends with the standard generated-with footer. Do NOT stage `DeviceActionTools.swift`.

---

## Self-review (done at write time)

- Spec coverage: grid+deck (T3/T5), telemetry kills hardcodes (T2/T3), upgrade banner (T3), embedded pages (T4), Appearance handoff (T6), heroes (T7), About merge + battery relocation + deletions (T8), a11y/test contract (T3/T5/T9), staged shippability (interim pushes T3, interim Appearance page T5), bars incl. Release (T1/T8/T10). Gap check: `.settingsModels` standalone sheet — unchanged, still presents `ModelsSettingsScreen()` (defaulted `embedded: false`) ✓; #193 alerts untouched ✓; `ConnectHermesHostScreen` untouched ✓.
- Placeholder scan: none of the banned patterns; per-file tables carry exact strings; code blocks complete.
- Type consistency: `SettingsSubsystem`/`SettingsCardValues`/`Mode`/`openSubsystem`/`SubsystemHero.Motif` used consistently across T2–T9.
