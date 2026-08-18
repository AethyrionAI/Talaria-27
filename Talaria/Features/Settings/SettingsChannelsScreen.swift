import SwiftUI

// MARK: - #252 Settings root — Subsystem Channels
//
// Grid of nine live-telemetry cards (Claude Design 1c) with a paged deck for
// drill-down. Cards and the developer row open the deck via `openSubsystem`;
// every sub-screen renders `embedded: true` inside a TabView page so its own
// header/background stay suppressed (Task 4).
struct SettingsChannelsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppContainer.self) private var container
    @Environment(AppSessionStore.self) private var sessionStore
    @Environment(HermesHostStore.self) private var hostStore
    @Environment(PairingStore.self) private var pairingStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(TalkStore.self) private var talkStore
    @Environment(TabRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    enum Mode: Equatable { case grid, deck(Int) }
    @State private var mode: Mode = .grid
    @State private var sessionCount: Int?

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                switch mode {
                case .grid: gridScroll
                case .deck: deckPager
                }
            }

            // Esc must dismiss the sheet in both grid and deck mode, even
            // though the visible left button changes action (✕ vs ‹) between
            // them — keep the shortcut on a control that's always present
            // rather than on whichever button happens to be showing.
            dismissKeyCatcher
        }
        .navigationTitle("System")
        .toolbarVisibility(.hidden, for: .navigationBar)
        .task {
            await hostStore.refresh()
            sessionCount = await container.chatStore.loadSessions().count
            // #256 verbiage round: the Voice card shows the live talk route,
            // so the grid needs the same readiness probe the deck fires.
            await talkStore.refreshReadiness()
        }
    }

    private var dismissKeyCatcher: some View {
        Button(action: { dismiss() }) { EmptyView() }
            .keyboardShortcut(.cancelAction)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            leftButton
            Spacer()
            VStack(spacing: Design.Spacing.xxs) {
                MonoLabel(kickerText, size: 9, weight: .medium,
                          tracking: Design.Tracking.monoXWide, color: Design.Colors.mutedForeground)
                MonoLabel(counterText, size: 10, weight: .medium,
                          tracking: Design.Tracking.monoWide, color: Design.Brand.accent)
                    .accessibilityIdentifier("settings.deck.counter")
            }
            Spacer()
            gridToggleGlyph
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.top, Design.Spacing.xs)
        .padding(.bottom, Design.Spacing.sm)
    }

    @ViewBuilder
    private var leftButton: some View {
        switch mode {
        case .grid:
            GlassCircleButton(icon: "xmark", accessibilityLabel: "Close settings") { dismiss() }
        case .deck:
            GlassCircleButton(icon: "chevron.left", accessibilityLabel: "Back to overview") {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { mode = .grid }
            }
        }
    }

    private var kickerText: String {
        switch mode {
        case .grid: "SYSTEM"
        case .deck: "SUBSYSTEM"
        }
    }

    private var counterText: String {
        switch mode {
        case .grid: "09 SUBSYSTEMS"
        case .deck: String(format: "%02d / 09", deckIndex + 1)
        }
    }

    // Flips grid↔deck. Accent-styled only in grid mode (its "you are on the
    // overview, tap to open the deck" affordance); muted once already in the
    // deck, where the ‹ back button is the primary way out.
    private var gridToggleGlyph: some View {
        let active = mode == .grid
        return Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                switch mode {
                case .grid: mode = .deck(deckIndex)
                case .deck: mode = .grid
                }
            }
        } label: {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: Design.Size.iconSmall, weight: .medium))
                .foregroundStyle(active ? Design.Brand.accentBright : Design.Colors.mutedForeground)
                .frame(width: Design.Size.glassCircleButton, height: Design.Size.glassCircleButton)
                .background(
                    active ? Design.Colors.accentTint(0.08) : Color.clear,
                    in: Circle()
                )
                .overlay {
                    Circle()
                        .strokeBorder(
                            active ? Design.Colors.strongBorder : Design.Colors.accentTint(0.16),
                            lineWidth: 1
                        )
                }
                .hudGlow(Design.Brand.accent, radius: 12, strength: active ? 0.25 : 0)
        }
        .buttonStyle(.plain)
        .frame(minWidth: Design.Size.minTapTarget, minHeight: Design.Size.minTapTarget)
        .contentShape(Circle())
        .hoverEffect(.highlight)
        .accessibilityLabel("Toggle overview")
    }

    // MARK: Deck

    private var deckIndex: Int {
        if case .deck(let i) = mode { return i }
        return 0
    }

    private func openSubsystem(_ subsystem: SettingsSubsystem) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
            mode = .deck(subsystem.rawValue)
        }
    }

    private var reduceMotion: Bool { systemReduceMotion || settingsStore.settings.reduceMotion }

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
        case .appearance: AppearanceDeckPage()
        case .privacy: PrivacySettingsScreen(embedded: true)
        case .sessions: SessionsSettingsScreen(embedded: true)
        case .about:
            ScrollView {
                AboutSettingsContent()
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.vertical, Design.Spacing.sm)
            }
        case .developer: DeveloperSettingsScreen(embedded: true)
        }
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

    // MARK: Grid

    private var gridScroll: some View {
        ScrollView {
            VStack(spacing: Design.Spacing.md) {
                statusStrip
                if !pairingStore.isPaired { upgradeBanner }
                cardGrid
                developerRow
                footer
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.sm)
        }
    }

    // MARK: #256 status strip (grid view only — at-a-glance LINK · HOST · MODEL,
    // Owen's device-pass call: the grid sat too high and the page wanted
    // one glanceable line of link telemetry)

    private var statusStripText: String {
        SettingsCardValues.statusStrip(
            state: effectiveConnectionState,
            isDirect: container.chatStore.directConnectionStatus == .connected,
            hostName: container.profilesStore?.activeProfile?.name,
            modelName: container.chatStore.activeModelName,
            brainLabel: container.chatBackendRouter?.activeBrain.monoLabel)
    }

    private var statusStrip: some View {
        HStack(spacing: Design.Spacing.sm) {
            StatusPip(
                color: effectiveConnectionState == .online
                    ? Design.Brand.accent : Design.Colors.mutedForeground,
                diameter: 8,
                blinks: effectiveConnectionState == .online)
            MonoLabel(statusStripText, size: 10, weight: .medium,
                      tracking: Design.Tracking.mono,
                      color: Design.Colors.foregroundBright)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPanel(
            cornerRadius: Design.CornerRadius.lg,
            borderColor: Design.Colors.hairline,
            fill: Design.Colors.background.opacity(0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(statusStripText)
        .accessibilityIdentifier("settings.statusStrip")
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

    private let gridColumns = [GridItem(.flexible(), spacing: Design.Spacing.sm),
                               GridItem(.flexible(), spacing: Design.Spacing.sm)]

    private var cardGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: Design.Spacing.sm) {
            ForEach(SettingsSubsystem.allCases.filter { $0 != .developer }) { subsystem in
                Button { openSubsystem(subsystem) } label: {
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
        Button { openSubsystem(.developer) } label: {
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

    // MARK: Telemetry (live stores → Task 2 formatters)

    /// #350: the shared measured truth — one function, three surfaces.
    private var effectiveConnectionState: HermesHostConnectionState {
        ChatConnectionPresentation.settingsEffectiveState(
            direct: container.chatStore.directConnectionStatus,
            hostFallback: hostStore.connectionState,
            hostConfigured: container.profilesStore?.activeProfile?.gatewayBaseURL.isEmpty == false)
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
                brainIsLocal: container.chatBackendRouter?.activeBrain != .hermes,
                engine: talkStore.voiceEngine,
                talkState: talkStore.connectionState)
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
            SettingsCardValues.about(isHealthy: aboutIsHealthy)
        case .developer:
            SettingsCardValues.developer(
                environmentLabel: settingsStore.settings.environment.displayLabel)
        }
    }

    // #252R-A: the predicates themselves live in SettingsChannels.swift beside
    // the value formatters — pure, store-free and unit-testable. This switch is
    // now only the store→argument wiring, which is the same shape `cardValue`
    // above already had. Before the extraction this was a private View method
    // no test could reach, which is why the Voice card's accent could drift
    // away from its value for four days without a single failure.
    private func cardIsAccented(_ subsystem: SettingsSubsystem) -> Bool {
        switch subsystem {
        case .uplink:
            SettingsCardAccent.uplink(state: effectiveConnectionState)
        case .server:
            SettingsCardAccent.server(hasActiveProfile: container.profilesStore?.activeProfile != nil)
        case .models:
            SettingsCardAccent.models(activeModelName: container.chatStore.activeModelName)
        case .voice:
            SettingsCardAccent.voice(
                brainIsLocal: container.chatBackendRouter?.activeBrain != .hermes,
                engine: talkStore.voiceEngine,
                talkState: talkStore.connectionState)
        case .appearance:
            SettingsCardAccent.appearance
        case .privacy:
            SettingsCardAccent.privacy(
                masterOn: settingsStore.settings.sensorStreamingEnabled,
                health: settingsStore.settings.healthCollectionEnabled,
                location: settingsStore.settings.locationCollectionEnabled,
                motion: settingsStore.settings.motionCollectionEnabled)
        case .sessions:
            SettingsCardAccent.sessions(count: sessionCount)
        case .about:
            SettingsCardAccent.about(isHealthy: aboutIsHealthy)
        case .developer:
            SettingsCardAccent.developer
        }
    }

    // #252 final-review: hostless is the DESIGNED state, not degraded —
    // shared with AboutSettingsContent's hero so the card and the hero can
    // never disagree (SettingsCardValues.aboutIsHealthy is the single source
    // of truth for both).
    private var aboutIsHealthy: Bool {
        SettingsCardValues.aboutIsHealthy(
            hostConfigured: container.profilesStore?.activeProfile != nil || pairingStore.isPaired,
            connectionOnline: effectiveConnectionState == .online)
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
                // #256: long theme names ("CASINO LUCKY 7S · CH 22") were
                // ellipsizing on device — scale to fit instead.
                .minimumScaleFactor(0.65)
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
