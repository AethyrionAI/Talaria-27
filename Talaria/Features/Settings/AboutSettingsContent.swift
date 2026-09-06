import SwiftUI
import Foundation
import UIKit

// MARK: - About settings content (Settings → ABOUT deck page)
//
// #252 Task 8: the deck's ABOUT page absorbs DiagnosticsSettingsScreen's
// non-battery content directly (SettingsChannelsScreen.deckPage(.about) hosts
// this inside its own ScrollView — no header, no background, no embedded
// toggle; there is no other presentation of this content left). The #200
// battery harness moved to DeveloperSettingsScreen instead (#252 Task 8) —
// DEBUG-only instrumentation never belonged on the page real users open.
//
// System-health readout. Mirrors design/Settings.dc.html screen 08, real-data-only:
//   • Status rows reflect live state — Hermes API (direct probe), Relay link
//     (relay session), Location (authorization).
//   • App version + device identifier are real. HOST VERSION and UPTIME have no
//     client-reachable source yet, so they render "—" (deferred).
//   • There is no in-app log ring buffer yet, so the LOGS panel is an honest
//     placeholder pointing at the real capture path (Console.app). Tracked in
//     OPEN_ITEMS alongside an export action.
struct AboutSettingsContent: View {
    @Environment(\.openURL) private var openURL
    @Environment(AppContainer.self) private var container
    @Environment(HermesHostStore.self) private var hostStore
    @Environment(PermissionsStore.self) private var permissionsStore
    @Environment(SettingsStore.self) private var settingsStore

    private struct RowStatus {
        let text: String
        let color: Color
        let blinks: Bool
    }

    /// #269-A: the measured plugin-link state (probe + credential, composed).
    @State private var pluginLink: TalariaLinkDisplayState = .unknown

    var body: some View {
        VStack(spacing: Design.Spacing.lg) {
            SubsystemHero(
                motif: .sparkline,
                title: SettingsSubsystem.about.title,
                status: SettingsCardValues.about(isHealthy: isHealthy),
                statusColor: isHealthy ? Design.Brand.accentText : Design.Brand.forgeText,
                chip: SettingsSubsystem.about.chip,
                accented: isHealthy
            )
            statusPanel
            voicePanel
            phoneQueriesPanel
            infoGrid
            logsSection
            footerLinks
            rootFooter
        }
        .task {
            await container.chatStore.refreshDirectHealth()
            await permissionsStore.reloadCapabilities()
            if let profile = container.profilesStore?.activeProfile {
                async let token = container.talariaDeviceToken(for: profile)
                async let observation = container.talariaPlatformLink?.probeLinkState()
                pluginLink = TalariaLinkDisplayState.compose(
                    observation: await observation,
                    deviceToken: await token
                )
            }
        }
    }

    // MARK: Hero (#252 Task 7)

    /// #252 final-review: matches SettingsChannelsScreen's grid-card verdict
    /// exactly — same `SettingsCardValues.aboutIsHealthy` formatter, same
    /// inputs — so the card and this hero can never disagree. Hostless (no
    /// profile, not paired) is the DESIGNED state and always reads HEALTHY;
    /// once a host is configured, health tracks the real direct-or-relay
    /// connection signal.
    private var isHealthy: Bool {
        SettingsCardValues.aboutIsHealthy(
            hostConfigured: container.hasGatewayCredentials,
            connectionOnline: effectiveConnectionState == .online)
    }

    /// #264 half 2: the app's ONE connection derivation. This surface supplies
    /// no arguments — not even `hostConfigured` — because the three settings
    /// screens used to spell that predicate differently and disagree.
    private var effectiveConnectionState: HermesHostConnectionState {
        ConnectionSignal.settingsState(container: container, hostStore: hostStore)
    }

    // MARK: Status panel

    private var statusPanel: some View {
        VStack(spacing: 0) {
            statusRow("Hermes API", hermesAPIStatus)
            rowDivider
            statusRow("Plugin Link", pluginLinkStatus)
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

    private var pluginLinkStatus: RowStatus {
        switch pluginLink {
        case .livePaired:
            RowStatus(text: pluginLink.label, color: Design.Brand.accentText, blinks: false)
        case .notLive:
            RowStatus(text: pluginLink.label, color: Design.Brand.forgeText, blinks: false)
        case .unknown, .liveNotPaired, .hostUnreachable:
            RowStatus(text: pluginLink.label, color: Design.Colors.mutedForeground, blinks: false)
        }
    }

    // MARK: Legacy relay — DELETED 2026-08-25 (#309 Lane B)
    //
    // `legacyRelayPanel`, `relayStatus` and `identityStatus` are gone with
    // `AppSessionStore`/`PairingStore`. Every value they rendered was a RELAY
    // fact: the session's `connectionStatus` against a service retired on both
    // hosts (#346/#375), and the #3/#46 stale-identity check against a relay
    // user id nothing mints any more. A panel whose two rows can only ever say
    // OFFLINE and "—" is not a diagnostic; it is furniture that trains the
    // reader to ignore this screen.
    //
    // The one live signal in there kept a home: the #369/#25 CREDENTIAL
    // UNREADABLE hold now surfaces on Connect Host's key row, next to the
    // credential it is about (`ConnectedHost.credentialUnreadable`).
    // `TalariaLinkObservation.legacyRelayReadsAsError` lost its only caller
    // here and went with it.

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
            .fill(Design.Colors.hairline)
            .frame(height: 1)
            .padding(.horizontal, Design.Spacing.md)
    }

    private var hermesAPIStatus: RowStatus {
        switch container.chatStore.directConnectionStatus {
        case .connected:    RowStatus(text: "REACHABLE",   color: Design.Brand.accentText,        blinks: false)
        case .connecting:   RowStatus(text: "CHECKING",     color: Design.Brand.forgeText,         blinks: true)
        case .disconnected: RowStatus(text: "UNREACHABLE",  color: Design.Colors.dangerText,       blinks: false)
        case .error:        RowStatus(text: "ERROR",        color: Design.Colors.dangerText,       blinks: false)
        }
    }

    private var locationStatus: RowStatus {
        let level = permissionsStore.locationAuthorizationLevel
        switch level {
        case .always, .whenInUse:
            return RowStatus(text: level.displayLabel.uppercased(), color: Design.Brand.accentText, blinks: false)
        case .denied, .restricted:
            return RowStatus(text: level.displayLabel.uppercased(), color: Design.Colors.dangerText, blinks: false)
        case .notDetermined:
            return RowStatus(text: "NOT SET", color: Design.Colors.mutedForeground, blinks: false)
        }
    }

    // MARK: Voice / talk pipeline (#84)
    //
    // The #82 evening: talk showed a live session over a dead microphone.
    // This panel answers the diagnostic ladder's first three questions at a
    // glance — can the app record, can it transcribe, and where is audio
    // actually routed right now.

    private var voicePanel: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Voice / Talk", size: 10, tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)

            VStack(spacing: 0) {
                panelRow("Microphone", voicePermissionLabel(.microphone),
                         voicePermissionColor(.microphone))
                rowDivider
                panelRow("Speech Recognition", voicePermissionLabel(.speechRecognition),
                         voicePermissionColor(.speechRecognition))
                rowDivider
                panelRow("Audio Route", TalkAudioRoute.currentSummary() ?? "—",
                         Design.Colors.secondaryForeground)
            }
            .hudPanel(
                cornerRadius: Design.CornerRadius.lg,
                borderColor: Design.Colors.accentTint(0.12),
                fill: Design.Colors.background.opacity(0.5),
                innerGlow: false
            )
        }
    }

    private func voiceCapabilityStatus(_ type: PermissionType) -> PermissionStatus? {
        permissionsStore.capabilities.first(where: { $0.permissionType == type })?.status
    }

    private func voicePermissionLabel(_ type: PermissionType) -> String {
        voiceCapabilityStatus(type)?.displayLabel.uppercased() ?? "—"
    }

    private func voicePermissionColor(_ type: PermissionType) -> Color {
        switch voiceCapabilityStatus(type) {
        case .authorized, .authorizedAlways, .authorizedWhenInUse:
            Design.Brand.accentText
        case .denied, .restricted:
            Design.Colors.dangerText
        case .limited:
            Design.Brand.forgeText
        case .notDetermined, .unsupported, .none:
            Design.Colors.mutedForeground
        }
    }

    // MARK: Phone queries (#352)
    //
    // Replaced the relay-era "// Sensor Pipeline" panel when #352 retired the
    // upload path. Reports ONLY what query-time actually consults: the share
    // gates (UserSettings, the same table PhoneQueryResponder.deniedGate reads)
    // and the iOS grants (PermissionsStore). Deliberately NO link-state row —
    // probe-based link honesty is #269-A's lane, and #350 is why the page never
    // asserts a live host from a stored token.

    @ViewBuilder
    private var phoneQueriesPanel: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Phone Queries", size: 10, tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)

            VStack(spacing: 0) {
                panelRow("Sensor Sharing",
                         settingsStore.settings.sensorStreamingEnabled ? "ON" : "OFF",
                         settingsStore.settings.sensorStreamingEnabled
                            ? Design.Brand.accentText : Design.Colors.mutedForeground)
                rowDivider
                queryGateRow("Health", enabled: settingsStore.settings.healthCollectionEnabled,
                             permission: .health)
                rowDivider
                queryGateRow("Location", enabled: settingsStore.settings.locationCollectionEnabled,
                             permission: .location)
                rowDivider
                queryGateRow("Motion", enabled: settingsStore.settings.motionCollectionEnabled,
                             permission: .motion)
            }
            .hudPanel(
                cornerRadius: Design.CornerRadius.lg,
                borderColor: Design.Colors.accentTint(0.12),
                fill: Design.Colors.background.opacity(0.5),
                innerGlow: false
            )
        }
    }

    /// One row per gated sensor: the app-level share gate and the iOS grant,
    /// in one honest line. "OFF" when either the master or this sensor's
    /// toggle is off (matching deniedGate's master-outranks-stream order);
    /// "SHARED · <grant>" when the toggles pass and iOS has the last word.
    private func queryGateRow(_ label: String, enabled: Bool, permission: PermissionType) -> some View {
        let status = permissionsStore.capabilities
            .first { $0.permissionType == permission }?.status
        let shared = settingsStore.settings.sensorStreamingEnabled && enabled
        let text = shared ? "SHARED · \(status?.displayLabel.uppercased() ?? "—")" : "OFF"
        let color = shared ? permissionColor(status ?? .notDetermined)
                           : Design.Colors.mutedForeground
        return panelRow(label, text, color)
    }

    private func panelRow(_ label: String, _ value: String, _ color: Color, blinks: Bool = false) -> some View {
        HStack(spacing: Design.Spacing.sm) {
            StatusPip(color: color, diameter: 8, blinks: blinks)
            Text(label)
                .font(Design.Typography.callout)
                .foregroundStyle(Design.Colors.foreground)
            Spacer(minLength: Design.Spacing.sm)
            MonoLabel(value, size: 10, weight: .medium,
                      tracking: Design.Tracking.mono, color: color)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
    }

    private func permissionColor(_ status: PermissionStatus) -> Color {
        switch status {
        case .authorized, .authorizedWhenInUse, .authorizedAlways: Design.Brand.accentText
        case .limited: Design.Brand.forgeText
        case .denied, .restricted, .unsupported: Design.Colors.dangerText
        case .notDetermined: Design.Colors.mutedForeground
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
                    .strokeBorder(Design.Colors.hairline, lineWidth: 1)
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
            footerDot
            licensesLink
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, Design.Spacing.xs)
        .padding(.bottom, Design.Spacing.md)
    }

    /// #434: the way into the bundled third-party notices.
    ///
    /// A `NavigationLink`, not a `footerLink` — its three neighbours leave the
    /// app through `openURL`, and this one must not: the notice document ships
    /// INSIDE the bundle precisely so it can be read with no network, no host
    /// and no account, which is the state a reviewer opens it in.
    private var licensesLink: some View {
        NavigationLink {
            LicensesScreen()
        } label: {
            MonoLabel(LicensesDocument.title, size: 9, weight: .medium,
                      tracking: Design.Tracking.monoWide, color: Design.Brand.accentText)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.about.licenses")
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
                      color: url == nil ? Design.Colors.mutedForeground : Design.Brand.accentText)
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
    }

    // MARK: Root footer (absorbed from the retired SystemSettingsScreen root, #252 Task 8)

    private var rootFooter: some View {
        MonoLabel("TALARIA v\(rootFooterVersion) · DEVICE-BOUND", size: 9, weight: .regular,
                  tracking: Design.Tracking.monoWide, color: Design.Colors.dimForeground)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, Design.Spacing.sm)
            .padding(.bottom, Design.Spacing.lg)
    }

    // Matches the retired root's own `appVersion` (short version only, no
    // build) — distinct from the infoGrid's richer "short (build)" reading
    // below, and kept that way so this line still reads identically to the
    // grid page's own "TALARIA v… · DEVICE-BOUND" footer.
    private var rootFooterVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
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
