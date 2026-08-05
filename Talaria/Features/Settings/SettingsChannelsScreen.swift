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
                        .font(Design.Typography.body(15, weight: .medium))
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
