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
    @Environment(AppSessionStore.self) private var sessionStore
    @Environment(HermesHostStore.self) private var hostStore
    @Environment(PairingStore.self) private var pairingStore
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
            legacyRelayPanel
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
            hostConfigured: container.profilesStore?.activeProfile != nil || pairingStore.isPaired,
            connectionOnline: effectiveConnectionState == .online)
    }

    /// #350: the shared measured truth — see
    /// `ChatConnectionPresentation.settingsEffectiveState` (one function,
    /// three surfaces; the verbatim private copies are gone).
    private var effectiveConnectionState: HermesHostConnectionState {
        ChatConnectionPresentation.settingsEffectiveState(
            direct: container.chatStore.directConnectionStatus,
            hostFallback: hostStore.connectionState,
            hostConfigured: container.profilesStore?.activeProfile?.gatewayBaseURL.isEmpty == false)
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

    // MARK: Legacy relay (#353(b))
    //
    // The relay is a retiring tier (#346/#223). Red here is reserved for
    // "the phone-facing channel is down": with the plugin link measured
    // LIVE, an unreachable relay renders muted OFFLINE — a fact, not an
    // alarm. With the plugin NOT live the relay is the only channel and an
    // outage stays red. Derivation:
    // TalariaLinkObservation.legacyRelayReadsAsError (table-tested).

    private var legacyRelayPanel: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Legacy Relay", size: 10, tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)

            VStack(spacing: 0) {
                statusRow("Relay Link", relayStatus)
                rowDivider
                statusRow("Relay Identity", identityStatus)
            }
            .hudPanel(
                cornerRadius: Design.CornerRadius.lg,
                borderColor: Design.Colors.accentTint(0.12),
                fill: Design.Colors.background.opacity(0.5),
                innerGlow: false
            )
        }
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
            .fill(Design.Colors.hairline)
            .frame(height: 1)
            .padding(.horizontal, Design.Spacing.md)
    }

    private var hermesAPIStatus: RowStatus {
        switch container.chatStore.directConnectionStatus {
        case .connected:    RowStatus(text: "REACHABLE",   color: Design.Brand.accentText,        blinks: false)
        case .connecting:   RowStatus(text: "CHECKING",     color: Design.Brand.forgeText,         blinks: true)
        case .disconnected: RowStatus(text: "UNREACHABLE",  color: Design.Colors.danger,       blinks: false)
        case .error:        RowStatus(text: "ERROR",        color: Design.Colors.danger,       blinks: false)
        }
    }

    private var relayStatus: RowStatus {
        // #353(b): severity derives from measurement. (The old permanently
        // blinking STANDBY arm collapses into the derived pair — a forever
        // pulse against a retired relay was the same training-to-ignore
        // cost in miniature.)
        let pluginLive = pluginLink == .livePaired || pluginLink == .liveNotPaired
        switch sessionStore.state.connectionStatus {
        case .connected:
            return RowStatus(text: "LINKED", color: Design.Brand.accentText, blinks: false)
        case .connecting:
            return RowStatus(text: "CONNECTING", color: Design.Brand.forgeText, blinks: true)
        case .disconnected, .error:
            if TalariaLinkObservation.legacyRelayReadsAsError(
                pluginLive: pluginLive, relayReachable: false) {
                return RowStatus(text: "ERROR", color: Design.Colors.danger, blinks: false)
            }
            return RowStatus(text: "OFFLINE", color: Design.Colors.mutedForeground, blinks: false)
        }
    }

    // #3/#46: which relay user this session actually authenticates as. A
    // Keychain-resurrected identity from a previous install shows as a
    // mismatch against the user the current pairing minted — the "sensors
    // 202-forever while chat works" failure is a glance here, not a forensic
    // session. "—" when there's no session user yet.
    private var identityStatus: RowStatus {
        // #369/#180: a launch that could not READ the credential holds instead
        // of unpairing — so this row says so, rather than rendering the
        // resulting absence of a session user as a bland "—".
        //
        // #25: the text names the OBSERVATION and not a cause. "Waiting for
        // unlock" would have been the natural phrasing and it is exactly the
        // claim this app cannot make: the Keychain read collapses "locked",
        // "no item" and "no entitlement" into one nil, so which of them
        // happened is unknown here. Warning-coloured rather than danger — the
        // pairing is intact and a first unlock usually resolves it.
        if container.credentialsUnreadableHold {
            return RowStatus(text: "CREDENTIAL UNREADABLE", color: Design.Brand.forgeText, blinks: false)
        }
        if container.pairingStore.identityMismatchDetected {
            return RowStatus(text: "STALE — RE-PAIR", color: Design.Colors.danger, blinks: true)
        }
        guard let userID = sessionStore.state.userID else {
            return RowStatus(text: "—", color: Design.Colors.mutedForeground, blinks: false)
        }
        let short = userID.uuidString.prefix(8).uppercased()
        if container.pairingStore.expectedRelayUserID == nil {
            // Pre-#3 pairing: identity shown but unverifiable until a re-pair
            // records the minted user.
            return RowStatus(text: "USER \(short) · UNVERIFIED", color: Design.Brand.forgeText, blinks: false)
        }
        return RowStatus(text: "USER \(short)", color: Design.Brand.accentText, blinks: false)
    }

    private var locationStatus: RowStatus {
        let level = permissionsStore.locationAuthorizationLevel
        switch level {
        case .always, .whenInUse:
            return RowStatus(text: level.displayLabel.uppercased(), color: Design.Brand.accentText, blinks: false)
        case .denied, .restricted:
            return RowStatus(text: level.displayLabel.uppercased(), color: Design.Colors.danger, blinks: false)
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
            Design.Colors.danger
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
        case .denied, .restricted, .unsupported: Design.Colors.danger
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
