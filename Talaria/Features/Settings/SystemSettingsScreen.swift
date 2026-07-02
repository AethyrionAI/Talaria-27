import SwiftUI

// MARK: - System settings index (Settings → SYSTEM, screen 01)
//
// The top-level Settings index from design/Settings.dc.html: host panel + grouped
// navigation into the drill-down sub-screens. Voice & Talk (05) joined the
// Experience group with #35 (the truthful status/launch rebuild).
//
// As of T3 sub-pages 09–12 this index now has a home for every section the
// monolith owned — relay (09), notifications/haptics (10), permissions/location
// (11), and internal environment + flags (12, DEBUG-only). ContentView presents
// this index as the live Settings entry; the old monolith remains in the tree
// only as dead code pending removal.
struct SystemSettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppContainer.self) private var container
    @Environment(AppSessionStore.self) private var sessionStore
    @Environment(HermesHostStore.self) private var hostStore
    @Environment(PairingStore.self) private var pairingStore
    @Environment(SettingsStore.self) private var settingsStore

    @State private var sessionCount: Int?

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Design.Spacing.lg) {
                    header
                    hostPanel
                    connectionGroup
                    experienceGroup
                    dataSystemGroup
                    #if DEBUG
                    developerGroup
                    #endif
                    footer
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)
            }
        }
        .navigationTitle("System")
        .toolbarVisibility(.hidden, for: .navigationBar)
        .task {
            await hostStore.refresh()
            sessionCount = await container.chatStore.loadSessions().count
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                Text("SYSTEM")
                    .font(Design.Typography.screenTitle2)
                    .tracking(Design.Tracking.display)
                    .foregroundStyle(Design.Colors.foregroundBright)
                MonoLabel("Talaria Control", size: 10, weight: .medium,
                          tracking: Design.Tracking.monoWide, color: Design.Colors.mutedForeground)
            }
            Spacer()
            GlassCircleButton(icon: "xmark", accessibilityLabel: "Close settings") { dismiss() }
        }
        .padding(.top, Design.Spacing.xs)
    }

    // MARK: Host panel

    private var hostPanel: some View {
        HStack(spacing: Design.Spacing.sm) {
            ReactorOrb(size: Design.Size.orbPanel, style: .standard)
            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                Text(hostName)
                    .font(Design.Typography.display(16, weight: .semibold, relativeTo: .headline))
                    .tracking(Design.Tracking.mono)
                    .foregroundStyle(Design.Colors.foregroundBright)
                    .lineLimit(1)
                MonoLabel(hostStatusLine, size: 10, weight: .medium,
                          tracking: Design.Tracking.mono, color: statusColor)
            }
            Spacer(minLength: Design.Spacing.xs)
            StatusPip(color: statusColor, diameter: 9, blinks: effectiveConnectionState == .unreachable)
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPanel(
            cornerRadius: Design.CornerRadius.xl,
            borderColor: Design.Colors.cyanBorder,
            fill: Design.Colors.accentTint(0.08),
            innerGlow: true
        )
    }

    // MARK: Groups

    private var connectionGroup: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            groupLabel("// Connection")
            VStack(spacing: 0) {
                navRow(icon: "dot.radiowaves.left.and.right", title: "Hermes Host", value: hostValue) {
                    UplinkSettingsScreen()
                }
                rowDivider
                navRow(icon: "point.3.connected.trianglepath.dotted", title: "Relay", value: relayValue,
                       valueColor: relayColor) {
                    RelaySettingsScreen()
                }
                rowDivider
                navRow(icon: "cpu", title: "Models", value: modelValue) {
                    ModelsSettingsScreen()
                }
            }
            .groupPanel()
        }
    }

    private var experienceGroup: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            groupLabel("// Experience")
            VStack(spacing: 0) {
                navRow(icon: "paintpalette", title: "Appearance & HUD", value: "REACTOR") {
                    AppearanceSettingsScreen()
                }
                rowDivider
                navRow(icon: "waveform", title: "Voice & Talk", value: "REALTIME",
                       valueColor: Design.Colors.secondaryForeground) {
                    VoiceSettingsScreen()
                }
                rowDivider
                navRow(icon: "bell", title: "Notifications", value: notificationsValue,
                       valueColor: notificationsColor) {
                    NotificationsSettingsScreen()
                }
                rowDivider
                navRow(icon: "lock.shield", title: "Privacy", value: "MANAGE",
                       valueColor: Design.Colors.secondaryForeground) {
                    PrivacySettingsScreen()
                }
            }
            .groupPanel()
        }
    }

    private var dataSystemGroup: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            groupLabel("// Data & System")
            VStack(spacing: 0) {
                navRow(icon: "clock.arrow.circlepath", title: "Sessions & Data", value: sessionsValue,
                       valueColor: Design.Colors.secondaryForeground) {
                    SessionsSettingsScreen()
                }
                rowDivider
                navRow(icon: "waveform.path.ecg", title: "About & Diagnostics", value: diagnosticsValue,
                       valueColor: diagnosticsColor) {
                    DiagnosticsSettingsScreen()
                }
            }
            .groupPanel()
        }
    }

    #if DEBUG
    private var developerGroup: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            groupLabel("// Developer")
            VStack(spacing: 0) {
                navRow(icon: "hammer", title: "Developer", value: environmentValue,
                       valueColor: Design.Colors.secondaryForeground) {
                    DeveloperSettingsScreen()
                }
            }
            .groupPanel()
        }
    }
    #endif

    // MARK: Row builder

    private func navRow<Destination: View>(
        icon: String,
        title: String,
        value: String,
        valueColor: Color = Design.Brand.accent,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: Design.Spacing.sm) {
                iconTile(icon)
                Text(title)
                    .font(Design.Typography.body(15, weight: .medium))
                    .foregroundStyle(Design.Colors.foreground)
                Spacer(minLength: Design.Spacing.xs)
                MonoLabel(value, size: 10, weight: .medium,
                          tracking: Design.Tracking.mono, color: valueColor)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Design.Colors.accentTint(0.7))
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func iconTile(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Design.Brand.accent)
            .frame(width: 32, height: 32)
            .background(Design.Colors.accentTint(0.05),
                        in: RoundedRectangle(cornerRadius: Design.CornerRadius.sm))
            .overlay {
                RoundedRectangle(cornerRadius: Design.CornerRadius.sm)
                    .strokeBorder(Design.Colors.accentTint(0.18), lineWidth: 1)
            }
    }

    private func groupLabel(_ text: String) -> some View {
        MonoLabel(text, size: 10, tracking: Design.Tracking.monoXWide,
                  color: Design.Colors.mutedForeground)
            .padding(.leading, Design.Spacing.xxs)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Design.Colors.cyanHairline)
            .frame(height: 1)
            .padding(.horizontal, Design.Spacing.md)
    }

    // MARK: Footer

    private var footer: some View {
        MonoLabel("TALARIA v\(appVersion) · DEVICE-BOUND", size: 9, weight: .regular,
                  tracking: Design.Tracking.monoWide, color: Design.Colors.dimForeground)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, Design.Spacing.sm)
            .padding(.bottom, Design.Spacing.lg)
    }

    // MARK: Derived values

    private var effectiveConnectionState: HermesHostConnectionState {
        if container.chatStore.directConnectionStatus == .connected { return .online }
        return hostStore.connectionState
    }

    private var isDirect: Bool {
        container.chatStore.directConnectionStatus == .connected
    }

    private var hostName: String {
        switch effectiveConnectionState {
        case .online, .offline: hostStore.currentHost?.resolvedDisplayName ?? "Hermes Host"
        case .unreachable, .notConnected: "Hermes Host"
        }
    }

    private var statusColor: Color {
        switch effectiveConnectionState {
        case .online: Design.Brand.accent
        case .offline, .unreachable: Design.Brand.forge
        case .notConnected: Design.Colors.mutedForeground
        }
    }

    private var hostStatusLine: String {
        switch effectiveConnectionState {
        case .online: "LINKED · \(isDirect ? "DIRECT" : "RELAY") · \(sessionStore.state.connectionStatus.displayLabel.uppercased())"
        case .offline: "OFFLINE · STANDBY"
        case .unreachable: "UNREACHABLE · CHECK UPLINK"
        case .notConnected: "NOT LINKED"
        }
    }

    private var hostValue: String {
        switch effectiveConnectionState {
        case .online: isDirect ? "DIRECT" : "RELAY"
        case .offline: "STANDBY"
        case .unreachable: "OFFLINE"
        case .notConnected: "NOT LINKED"
        }
    }

    private var modelValue: String {
        guard let name = container.chatStore.activeModelName, !name.isEmpty else { return "SELECT" }
        return name.uppercased()
    }

    private var sessionsValue: String {
        guard let count = sessionCount else { return "DATA" }
        return "\(count) SESSION\(count == 1 ? "" : "S")"
    }

    private var diagnosticsValue: String {
        effectiveConnectionState == .online ? "HEALTHY" : "DEGRADED"
    }

    private var diagnosticsColor: Color {
        effectiveConnectionState == .online ? Design.Brand.accent : Design.Brand.forge
    }

    private var relayValue: String {
        pairingStore.isPaired ? "PAIRED" : "SET UP"
    }

    private var relayColor: Color {
        pairingStore.isPaired ? Design.Brand.accent : Design.Colors.mutedForeground
    }

    private var notificationsValue: String {
        settingsStore.settings.notificationsEnabled ? "ON" : "OFF"
    }

    private var notificationsColor: Color {
        settingsStore.settings.notificationsEnabled ? Design.Brand.accent : Design.Colors.mutedForeground
    }

    #if DEBUG
    private var environmentValue: String {
        settingsStore.settings.environment.displayLabel.uppercased()
    }
    #endif

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
}

// MARK: - Group panel modifier

private extension View {
    func groupPanel() -> some View {
        self.hudPanel(
            cornerRadius: Design.CornerRadius.lg,
            borderColor: Design.Colors.accentTint(0.12),
            fill: Design.Colors.background.opacity(0.5),
            innerGlow: false
        )
    }
}
