import SwiftUI
import Foundation

// MARK: - Diagnostics settings screen (Settings → DIAGNOSTICS)
//
// System-health readout. Mirrors design/Settings.dc.html screen 08, real-data-only:
//   • Status rows reflect live state — Hermes API (direct probe), Relay link
//     (relay session), Push token (registration), Location (authorization).
//   • App version + device identifier are real. HOST VERSION and UPTIME have no
//     client-reachable source yet, so they render "—" (deferred).
//   • There is no in-app log ring buffer yet, so the LOGS panel is an honest
//     placeholder pointing at the real capture path (Console.app). Tracked in
//     OPEN_ITEMS alongside an export action.
struct DiagnosticsSettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AppContainer.self) private var container
    @Environment(AppSessionStore.self) private var sessionStore
    @Environment(PermissionsStore.self) private var permissionsStore
    @Environment(SettingsStore.self) private var settingsStore

    private struct RowStatus {
        let text: String
        let color: Color
        let blinks: Bool
    }

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Design.Spacing.lg) {
                    SettingsScreenHeader(title: "Diagnostics", subtitle: "System Health") { dismiss() }
                    statusPanel
                    infoGrid
                    logsSection
                    footerLinks
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)
            }
        }
        .navigationTitle("Diagnostics")
        .toolbarVisibility(.hidden, for: .navigationBar)
        .task { await container.chatStore.refreshDirectHealth() }
    }

    // MARK: Status panel

    private var statusPanel: some View {
        VStack(spacing: 0) {
            statusRow("Hermes API", hermesAPIStatus)
            rowDivider
            statusRow("Relay Link", relayStatus)
            rowDivider
            statusRow("Push Token", pushStatus)
            rowDivider
            statusRow("Location", locationStatus)
        }
        .hudPanel(
            cornerRadius: Design.CornerRadius.lg,
            borderColor: Design.Colors.accentTint(0.12),
            fill: Design.Colors.background.opacity(0.5),
            innerGlow: false
        )
    }

    private func statusRow(_ label: String, _ status: RowStatus) -> some View {
        HStack(spacing: Design.Spacing.sm) {
            StatusPip(color: status.color, diameter: 8, blinks: status.blinks)
            Text(label)
                .font(Design.Typography.callout)
                .foregroundStyle(Design.Colors.foreground)
            Spacer()
            MonoLabel(status.text, size: 10, weight: .medium,
                      tracking: Design.Tracking.mono, color: status.color)
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Design.Colors.cyanHairline)
            .frame(height: 1)
            .padding(.horizontal, Design.Spacing.md)
    }

    private var hermesAPIStatus: RowStatus {
        switch container.chatStore.directConnectionStatus {
        case .connected:    RowStatus(text: "REACHABLE",   color: Design.Brand.accent,        blinks: false)
        case .connecting:   RowStatus(text: "CHECKING",     color: Design.Brand.forge,         blinks: true)
        case .disconnected: RowStatus(text: "UNREACHABLE",  color: Design.Colors.danger,       blinks: false)
        case .error:        RowStatus(text: "ERROR",        color: Design.Colors.danger,       blinks: false)
        }
    }

    private var relayStatus: RowStatus {
        switch sessionStore.state.connectionStatus {
        case .connected:    RowStatus(text: "LINKED",     color: Design.Brand.accent,  blinks: false)
        case .connecting:   RowStatus(text: "CONNECTING", color: Design.Brand.forge,   blinks: true)
        case .disconnected: RowStatus(text: "STANDBY",    color: Design.Brand.forge,   blinks: true)
        case .error:        RowStatus(text: "ERROR",      color: Design.Colors.danger, blinks: false)
        }
    }

    // Same three-state source of truth the Notifications screen renders
    // (AppContainer.pushTokenPipelineState). A locally cached APNs token alone
    // is NOT "registered" — the relay handshake is a separate stage, and
    // claiming otherwise made this row contradict Settings → Notifications.
    private var pushStatus: RowStatus {
        switch container.pushTokenPipelineState {
        case .registered:
            return RowStatus(text: "RELAY REGISTERED", color: Design.Brand.accent, blinks: false)
        case .awaitingRelay:
            return RowStatus(text: "TOKEN HELD · AWAITING RELAY", color: Design.Brand.forge, blinks: true)
        case .notIssued:
            return RowStatus(text: "NO APNS TOKEN", color: Design.Colors.mutedForeground, blinks: false)
        }
    }

    private var locationStatus: RowStatus {
        let level = permissionsStore.locationAuthorizationLevel
        switch level {
        case .always, .whenInUse:
            return RowStatus(text: level.displayLabel.uppercased(), color: Design.Brand.accent, blinks: false)
        case .denied, .restricted:
            return RowStatus(text: level.displayLabel.uppercased(), color: Design.Colors.danger, blinks: false)
        case .notDetermined:
            return RowStatus(text: "NOT SET", color: Design.Colors.mutedForeground, blinks: false)
        }
    }

    // MARK: Info grid

    private var infoGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: Design.Spacing.sm),
                GridItem(.flexible(), spacing: Design.Spacing.sm)
            ],
            spacing: Design.Spacing.sm
        ) {
            infoTile("App Version", appVersion)
            infoTile("Host Version", "—")
            infoTile("Uptime", "—")
            infoTile("Device", deviceIdentifier)
        }
    }

    private func infoTile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            MonoLabel(label, size: 8, weight: .medium,
                      tracking: Design.Tracking.monoWide, color: Design.Colors.mutedForeground)
            Text(value)
                .font(Design.Typography.mono(13, weight: .medium))
                .foregroundStyle(Design.Colors.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Design.Spacing.md)
        .hudPanel(
            cornerRadius: Design.CornerRadius.md,
            borderColor: Design.Colors.accentTint(0.12),
            fill: Design.Colors.background.opacity(0.5),
            innerGlow: false
        )
    }

    // MARK: Logs (deferred)

    private var logsSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Logs", size: 10, tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)

            VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                MonoLabel("In-app log buffer not yet captured.", size: 10,
                          tracking: Design.Tracking.mono, color: Design.Colors.secondaryForeground)
                MonoLabel("Capture via Console.app · filter org.aethyrion.talaria", size: 9,
                          tracking: Design.Tracking.mono, color: Design.Colors.mutedForeground)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Design.Spacing.md)
            .background(
                Design.Colors.background.opacity(0.6),
                in: RoundedRectangle(cornerRadius: Design.CornerRadius.md)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                    .strokeBorder(Design.Colors.cyanHairline, lineWidth: 1)
            }
        }
    }

    // MARK: Footer links

    private var footerLinks: some View {
        HStack(spacing: Design.Spacing.md) {
            footerLink("Terms", settingsStore.buildConfiguration.termsOfServiceURL)
            footerDot
            footerLink("Privacy", settingsStore.buildConfiguration.privacyPolicyURL)
            if settingsStore.buildConfiguration.supportURL != nil {
                footerDot
                footerLink("Support", settingsStore.buildConfiguration.supportURL)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, Design.Spacing.xs)
        .padding(.bottom, Design.Spacing.md)
    }

    private var footerDot: some View {
        Text("·")
            .font(Design.Typography.mono(9, weight: .regular))
            .foregroundStyle(Design.Colors.dimForeground)
    }

    @ViewBuilder
    private func footerLink(_ title: String, _ url: URL?) -> some View {
        Button {
            if let url { openURL(url) }
        } label: {
            MonoLabel(title, size: 9, weight: .medium, tracking: Design.Tracking.monoWide,
                      color: url == nil ? Design.Colors.mutedForeground : Design.Brand.accent)
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
    }

    // MARK: Derived values

    private var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "—"
        return "\(short) (\(build))"
    }

    private var deviceIdentifier: String {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafeBytes(of: &sysinfo.machine) { raw -> String in
            let ptr = raw.baseAddress!.assumingMemoryBound(to: CChar.self)
            return String(cString: ptr)
        }
        return machine.isEmpty ? "—" : machine
    }
}
