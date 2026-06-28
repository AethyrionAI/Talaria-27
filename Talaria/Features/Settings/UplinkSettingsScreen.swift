import SwiftUI

// MARK: - Uplink settings screen (Settings → UPLINK)
//
// The DIRECT chat link to the Hermes Sessions API (:8642): live link status,
// base URL, a Keychain-backed API key, and pair / test-connection actions.
// Mirrors design/Settings.dc.html screen 02.
//
// The RELAY/DIRECT control is a *readout* of the current effective transport,
// not an override — chat is locked to DIRECT per the architecture and the relay
// carries the independent sensor path. Relay/pairing configuration is migrated
// separately (it is not part of the direct-link surface the design shows here).
struct UplinkSettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppContainer.self) private var container
    @Environment(AppSessionStore.self) private var sessionStore
    @Environment(HermesHostStore.self) private var hostStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(TabRouter.self) private var router

    @State private var hermesAPIKeyDraft = ""
    @State private var hermesAPIKeySaving = false
    @State private var hermesAPIKeyJustSaved = false
    @State private var isTesting = false

    /// Prefers the direct Sessions API probe over the relay-based host state, so
    /// the link reads "online" when chat works even if the relay is down.
    private var effectiveConnectionState: HermesHostConnectionState {
        if container.chatStore.directConnectionStatus == .connected { return .online }
        return hostStore.connectionState
    }

    private var isDirect: Bool {
        container.chatStore.directConnectionStatus == .connected
    }

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Design.Spacing.lg) {
                    SettingsScreenHeader(title: "Uplink", subtitle: "Hermes Host") { dismiss() }
                    linkStatusPanel
                    linkModeReadout
                    baseURLSection
                    apiKeySection
                    actionButtons
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)
            }
        }
        .navigationTitle("Uplink")
        .toolbarVisibility(.hidden, for: .navigationBar)
        .task { await hostStore.refresh() }
        .onAppear { hermesAPIKeyDraft = container.hermesAPIKey }
    }

    // MARK: Link status panel

    private var linkStatusPanel: some View {
        HStack(spacing: Design.Spacing.sm) {
            ReactorOrb(size: Design.Size.orbPanel, style: .standard)

            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                Text(linkTitle)
                    .font(Design.Typography.display(18, weight: .bold, relativeTo: .headline))
                    .tracking(Design.Tracking.mono)
                    .foregroundStyle(Design.Colors.foregroundBright)
                    .lineLimit(1)

                MonoLabel(
                    linkDetail,
                    size: 10,
                    weight: .medium,
                    tracking: Design.Tracking.mono,
                    color: linkColor
                )
            }

            Spacer(minLength: Design.Spacing.xs)

            StatusPip(color: linkColor, diameter: 9, blinks: effectiveConnectionState == .unreachable)
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

    private var linkTitle: String {
        switch effectiveConnectionState {
        case .online: isDirect ? "DIRECT LINK" : "RELAY LINK"
        case .offline: "STANDBY"
        case .unreachable: "OFFLINE"
        case .notConnected: "NOT LINKED"
        }
    }

    private var linkColor: Color {
        switch effectiveConnectionState {
        case .online: Design.Brand.accent
        case .offline, .unreachable: Design.Brand.forge
        case .notConnected: Design.Colors.mutedForeground
        }
    }

    private var linkDetail: String {
        switch effectiveConnectionState {
        case .online: "\(hostDisplay) · \(sessionStore.state.connectionStatus.displayLabel.uppercased())"
        case .offline: "\(hostDisplay) · STANDBY"
        case .unreachable: "UNREACHABLE · CHECK UPLINK"
        case .notConnected: "NOT CONFIGURED"
        }
    }

    private var hostDisplay: String {
        settingsStore.settings.hermesAPIBaseURL
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
    }

    // MARK: Link-mode readout (display-only)

    private var linkModeReadout: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Link Mode", size: 10, tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)

            HStack(spacing: Design.Spacing.xxs) {
                modeSegment("Relay", active: !isDirect && effectiveConnectionState == .online)
                modeSegment("Direct", active: isDirect)
            }
            .padding(Design.Spacing.xxs)
            .background(Design.Colors.background.opacity(0.5),
                        in: RoundedRectangle(cornerRadius: Design.CornerRadius.md))
            .overlay {
                RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                    .strokeBorder(Design.Colors.cyanHairline, lineWidth: 1)
            }

            Text("Chat uses the direct Sessions API; the relay carries the independent sensor path.")
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.secondaryForeground)
        }
    }

    private func modeSegment(_ label: String, active: Bool) -> some View {
        Text(label.uppercased())
            .font(Design.Typography.display(12, weight: .semibold, relativeTo: .caption))
            .tracking(Design.Tracking.button)
            .foregroundStyle(active ? Design.Colors.background : Design.Colors.secondaryForeground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Design.Spacing.sm)
            .background(active ? Design.Brand.accent : Color.clear,
                        in: RoundedRectangle(cornerRadius: Design.CornerRadius.sm))
    }

    // MARK: Base URL

    private var baseURLSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            MonoLabel("Base URL", size: 9, weight: .medium, tracking: Design.Tracking.monoWide,
                      color: Design.Colors.mutedForeground)

            TextField("http://ojamd:8642", text: hermesAPIBaseURLBinding)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .font(Design.Typography.callout.monospaced())
                .foregroundStyle(Design.Colors.foreground)
                .padding(Design.Spacing.md)
                .modifier(HUDFieldBackground())

            Text("Hermes Sessions API endpoint, e.g. http://ojamd:8642.")
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.secondaryForeground)
        }
    }

    // MARK: API key

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            HStack {
                MonoLabel("API Key", size: 9, weight: .medium, tracking: Design.Tracking.monoWide,
                          color: Design.Colors.mutedForeground)
                Spacer()
                HStack(spacing: Design.Spacing.xxs) {
                    StatusPip(color: Design.Brand.accent, diameter: 5)
                    MonoLabel("Keychain", size: 9, weight: .medium, tracking: Design.Tracking.mono,
                              color: Design.Brand.accent)
                }
            }

            SecureField("Bearer key from ~/.hermes/.env", text: $hermesAPIKeyDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(Design.Typography.callout.monospaced())
                .foregroundStyle(Design.Colors.foreground)
                .padding(Design.Spacing.md)
                .modifier(HUDFieldBackground())

            HStack {
                Text(container.hermesAPIKey.isEmpty ? "No key stored." : "Key stored in Keychain.")
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground)
                Spacer()
                saveKeyButton
            }
        }
    }

    private var saveKeyButton: some View {
        Button {
            Task { await saveHermesAPIKey() }
        } label: {
            HStack(spacing: Design.Spacing.xs) {
                if hermesAPIKeySaving { ProgressView().controlSize(.mini) }
                Text((hermesAPIKeyJustSaved ? "Saved" : "Save").uppercased())
                    .font(Design.Typography.mono(11, weight: .medium))
                    .tracking(Design.Tracking.mono)
            }
            .foregroundStyle(Design.Brand.accentBright)
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.xs)
            .background(Design.Colors.accentTint(0.10), in: Capsule())
            .overlay { Capsule().strokeBorder(Design.Colors.accentTint(0.4), lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .disabled(hermesAPIKeyDraft == container.hermesAPIKey)
    }

    // MARK: Actions

    private var actionButtons: some View {
        VStack(spacing: Design.Spacing.sm) {
            GlowButton(title: "Pair Device", systemImage: "link") {
                router.dismissSheet()
                router.navigate(to: .connectHost)
            }
            GhostButton(
                title: isTesting ? "Testing…" : "Test Connection",
                systemImage: "antenna.radiowaves.left.and.right"
            ) {
                Task { await testConnection() }
            }
        }
        .padding(.top, Design.Spacing.xs)
    }

    private func testConnection() async {
        isTesting = true
        await hostStore.refresh()
        await container.chatStore.refreshDirectHealth()
        isTesting = false
    }

    // MARK: Bindings / persistence

    private var hermesAPIBaseURLBinding: Binding<String> {
        Binding(
            get: { settingsStore.settings.hermesAPIBaseURL },
            set: { settingsStore.settings.hermesAPIBaseURL = $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        )
    }

    private func saveHermesAPIKey() async {
        hermesAPIKeySaving = true
        await container.saveHermesAPIKey(hermesAPIKeyDraft)
        hermesAPIKeySaving = false
        hermesAPIKeyJustSaved = true
        try? await Task.sleep(for: .seconds(1.5))
        hermesAPIKeyJustSaved = false
    }
}

// MARK: - HUD field background

private struct HUDFieldBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                Design.Colors.background.opacity(0.6),
                in: RoundedRectangle(cornerRadius: Design.CornerRadius.lg)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Design.CornerRadius.lg)
                    .strokeBorder(Design.Colors.cyanHairline, lineWidth: 1)
            }
    }
}
