import SwiftUI

// MARK: - Relay settings screen (Settings → RELAY, sub-screen 09)
//
// Transport configuration for the INDEPENDENT sensor/relay path (the dylan-buck
// relay on :8000) — distinct from the DIRECT chat link shown on UPLINK. Mirrors
// design/Settings-Additional.dc.html page 09, real-data-only:
//   • MODE / URL edit the real RelayConfiguration; hosted mode is offered only
//     when the build actually ships a hosted relay (canUseHosted), otherwise the
//     segment is disabled with an honest caption.
//   • Reachability reflects the live relay session state — no fabricated latency.
//   • DEVICE reads PairingStore: paired host name, RE-PAIR (→ pairing flow) and
//     FORGET (→ disconnect()). While paired the relay config is locked, matching
//     the connector's "disconnect before reconfiguring" constraint.
struct RelaySettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSessionStore.self) private var sessionStore
    @Environment(PairingStore.self) private var pairingStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(TabRouter.self) private var router

    @State private var showForgetConfirm = false

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Design.Spacing.lg) {
                    SettingsScreenHeader(title: "Relay", subtitle: "Transport") { dismiss() }
                    modeSection
                    urlSection
                    reachabilitySection
                    deviceSection
                    autoConnectPanel
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)
            }
        }
        .navigationTitle("Relay")
        .toolbarVisibility(.hidden, for: .navigationBar)
        .confirmationDialog(
            "Forget this relay?",
            isPresented: $showForgetConfirm,
            titleVisibility: .visible
        ) {
            Button("Forget Relay", role: .destructive) {
                Task { await pairingStore.disconnect() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Disconnects the paired Hermes relay. You'll need to pair again to resume the sensor path.")
        }
    }

    // MARK: Mode

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Mode", size: 10, tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)

            HStack(spacing: Design.Spacing.xxs) {
                modeSegment("Use My Relay", mode: .custom)
                modeSegment("Use Hosted", mode: .hosted)
            }
            .padding(Design.Spacing.xxs)
            .background(Design.Colors.background.opacity(0.5),
                        in: RoundedRectangle(cornerRadius: Design.CornerRadius.md))
            .overlay {
                RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                    .strokeBorder(Design.Colors.cyanHairline, lineWidth: 1)
            }

            Text(modeCaption)
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.secondaryForeground)
        }
    }

    private func modeSegment(_ label: String, mode: RelayMode) -> some View {
        let active = relayConfiguration.relayMode == mode
        let enabled = !pairingStore.isPaired && (mode == .custom || relayConfiguration.canUseHosted)
        return Button {
            guard enabled else { return }
            relayModeBinding.wrappedValue = mode
        } label: {
            Text(label.uppercased())
                .font(Design.Typography.display(11, weight: .semibold, relativeTo: .caption))
                .tracking(Design.Tracking.button)
                .foregroundStyle(active ? Design.Colors.background
                                 : (enabled ? Design.Colors.secondaryForeground : Design.Colors.dimForeground))
                .frame(maxWidth: .infinity)
                .padding(.vertical, Design.Spacing.sm)
                .background(active ? Design.Brand.accent : Color.clear,
                            in: RoundedRectangle(cornerRadius: Design.CornerRadius.sm))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var modeCaption: String {
        if pairingStore.isPaired {
            return "Disconnect the relay below before changing transport mode."
        }
        return relayConfiguration.canUseHosted
            ? "Hosted relay is configured in this build."
            : "Hosted relay is unavailable in this build."
    }

    // MARK: URL

    private var urlSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            MonoLabel("// Relay URL", size: 9, weight: .medium, tracking: Design.Tracking.monoWide,
                      color: Design.Colors.mutedForeground)

            if pairingStore.isPaired {
                readonlyURL(pairingStore.pairedRelayConfiguration?.baseURLString
                            ?? relayConfiguration.activeBaseURLString ?? "Not configured")
            } else if relayConfiguration.relayMode == .hosted {
                readonlyURL(relayConfiguration.hostedRelayBaseURL ?? "Not configured")
            } else {
                TextField("https://your-relay.example.com/v1", text: customRelayURLBinding)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .font(Design.Typography.callout.monospaced())
                    .foregroundStyle(Design.Colors.foreground)
                    .padding(Design.Spacing.md)
                    .modifier(RelayFieldBackground())
            }

            if let relayValidationMessage, !pairingStore.isPaired {
                Text(relayValidationMessage)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Brand.forge)
            } else {
                Text("Must be an absolute http(s) URL ending in /v1.")
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground)
            }
        }
    }

    private func readonlyURL(_ value: String) -> some View {
        Text(value)
            .font(Design.Typography.callout.monospaced())
            .foregroundStyle(Design.Colors.coolForeground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Design.Spacing.md)
            .modifier(RelayFieldBackground())
    }

    // MARK: Reachability

    private var reachabilitySection: some View {
        HStack(spacing: Design.Spacing.sm) {
            StatusPip(color: reachability.color, diameter: 9, blinks: reachability.blinks)
            Text("Reachability")
                .font(Design.Typography.body(15, weight: .regular))
                .foregroundStyle(Design.Colors.foreground)
            Spacer(minLength: Design.Spacing.xs)
            MonoLabel(reachability.text, size: 10, weight: .medium,
                      tracking: Design.Tracking.mono, color: reachability.color)
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPanel(
            cornerRadius: Design.CornerRadius.lg,
            borderColor: Design.Colors.cyanBorder,
            fill: Design.Colors.accentTint(0.07),
            innerGlow: true
        )
    }

    private var reachability: (text: String, color: Color, blinks: Bool) {
        switch sessionStore.state.connectionStatus {
        case .connected:    ("LINKED",     Design.Brand.accent,         false)
        case .connecting:   ("CONNECTING", Design.Brand.forge,          true)
        case .disconnected: ("STANDBY",    Design.Brand.forge,          true)
        case .error:        ("ERROR",      Design.Colors.danger,        false)
        }
    }

    // MARK: Device

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Device", size: 10, tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)

            if pairingStore.isPaired {
                VStack(spacing: Design.Spacing.md) {
                    HStack(spacing: Design.Spacing.sm) {
                        StatusPip(color: Design.Brand.accent, diameter: 7)
                        MonoLabel("PAIRED · \(pairedName)", size: 11, weight: .medium,
                                  tracking: Design.Tracking.mono, color: Design.Brand.accent)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: Design.Spacing.sm) {
                        secondaryAction("Re-Pair", tint: Design.Brand.accentBright,
                                        border: Design.Colors.accentTint(0.4),
                                        fill: Design.Colors.accentTint(0.1)) {
                            router.dismissSheet()
                            router.navigate(to: .connectHost)
                        }
                        secondaryAction("Forget", tint: Design.Colors.dangerBright,
                                        border: Design.Colors.danger.opacity(0.34),
                                        fill: Design.Colors.danger.opacity(0.07)) {
                            showForgetConfirm = true
                        }
                    }
                }
                .padding(Design.Spacing.md)
                .hudPanel(
                    cornerRadius: Design.CornerRadius.lg,
                    borderColor: Design.Colors.accentTint(0.12),
                    fill: Design.Colors.background.opacity(0.5),
                    innerGlow: false
                )
            } else {
                VStack(spacing: Design.Spacing.sm) {
                    HStack(spacing: Design.Spacing.sm) {
                        StatusPip(color: Design.Colors.mutedForeground, diameter: 7)
                        MonoLabel("NOT PAIRED", size: 11, weight: .medium,
                                  tracking: Design.Tracking.mono, color: Design.Colors.mutedForeground)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.top, Design.Spacing.md)

                    GlowButton(title: "Pair Device", systemImage: "link") {
                        router.dismissSheet()
                        router.navigate(to: .connectHost)
                    }
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.bottom, Design.Spacing.md)
                }
                .hudPanel(
                    cornerRadius: Design.CornerRadius.lg,
                    borderColor: Design.Colors.accentTint(0.12),
                    fill: Design.Colors.background.opacity(0.5),
                    innerGlow: false
                )
            }
        }
    }

    private var pairedName: String {
        let name = pairingStore.pairedRelayConfiguration?.hostDisplayName ?? relayConfiguration.relayOriginLabel
        return name.isEmpty ? "RELAY" : name
    }

    private func secondaryAction(_ label: String, tint: Color, border: Color, fill: Color,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label.uppercased())
                .font(Design.Typography.display(12, weight: .semibold, relativeTo: .caption))
                .tracking(Design.Tracking.button)
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Design.Spacing.sm)
                .background(fill, in: RoundedRectangle(cornerRadius: Design.CornerRadius.md))
                .overlay {
                    RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                        .strokeBorder(border, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: Auto-connect

    private var autoConnectPanel: some View {
        HStack {
            Text("Auto-connect on launch")
                .font(Design.Typography.callout)
                .foregroundStyle(Design.Colors.foreground)
            Spacer()
            Toggle("", isOn: autoConnectBinding)
                .labelsHidden()
                .tint(Design.Brand.accent)
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
        .hudPanel(
            cornerRadius: Design.CornerRadius.lg,
            borderColor: Design.Colors.accentTint(0.12),
            fill: Design.Colors.background.opacity(0.5),
            innerGlow: false
        )
    }

    // MARK: Bindings (real RelayConfiguration round-trips)

    private var relayConfiguration: RelayConfiguration {
        settingsStore.settings.relayConfiguration
    }

    private var relayValidationMessage: String? {
        relayConfiguration.validationMessage
    }

    private var relayModeBinding: Binding<RelayMode> {
        Binding(
            get: { settingsStore.settings.relayConfiguration.relayMode },
            set: { newValue in
                var config = settingsStore.settings.relayConfiguration
                config.relayMode = newValue
                settingsStore.settings.relayConfiguration = config
            }
        )
    }

    private var customRelayURLBinding: Binding<String> {
        Binding(
            get: { settingsStore.settings.relayConfiguration.customRelayBaseURL },
            set: { newValue in
                var config = settingsStore.settings.relayConfiguration
                config.customRelayBaseURL = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                settingsStore.settings.relayConfiguration = config
            }
        )
    }

    private var autoConnectBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.autoConnectOnLaunch },
            set: { settingsStore.settings.autoConnectOnLaunch = $0 }
        )
    }
}

// MARK: - HUD field background

private struct RelayFieldBackground: ViewModifier {
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
