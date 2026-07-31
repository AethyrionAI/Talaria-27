import SwiftUI
import Foundation
import UIKit

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

    @State private var sensorAccessToken: Bool?

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
                    voicePanel
                    sensorPanel
                    #if DEBUG
                    localBrainPanel
                    #endif
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
        .task {
            await container.chatStore.refreshDirectHealth()
            await permissionsStore.reloadCapabilities()
            sensorAccessToken = await container.sensorUploadService?.hasValidAccessToken()
        }
    }

    // MARK: Status panel

    @State private var tokenCopied = false

    private var statusPanel: some View {
        VStack(spacing: 0) {
            statusRow("Hermes API", hermesAPIStatus)
            rowDivider
            statusRow("Relay Link", relayStatus)
            rowDivider
            statusRow("Relay Identity", identityStatus)
            rowDivider
            statusRow("Push Token", tokenCopied
                ? RowStatus(text: "COPIED", color: Design.Brand.accent, blinks: false)
                : pushStatus)
                .contentShape(Rectangle())
                .onTapGesture { copyPushToken() }
            rowDivider
            statusRow("Notifications", notificationAuthStatus)
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

    /// Tap the Push Token row to copy the full APNs device token to the
    /// clipboard (the row otherwise only shows the pipeline state, so there
    /// was nothing to read for host-side push testing).
    private func copyPushToken() {
        guard let token = container.cachedAPNsDeviceToken else { return }
        UIPasteboard.general.string = token
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation { tokenCopied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { tokenCopied = false }
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

    // #3/#46: which relay user this session actually authenticates as. A
    // Keychain-resurrected identity from a previous install shows as a
    // mismatch against the user the current pairing minted — the "sensors
    // 202-forever while chat works" failure is a glance here, not a forensic
    // session. "—" when there's no session user yet.
    private var identityStatus: RowStatus {
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
            return RowStatus(text: "USER \(short) · UNVERIFIED", color: Design.Brand.forge, blinks: false)
        }
        return RowStatus(text: "USER \(short)", color: Design.Brand.accent, blinks: false)
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

    // #189: OS notification authorization as its own row. An APNs token and a
    // relay registration are both obtainable while authorization is
    // NotDetermined, so the Push Token row alone read as a false green — this
    // panel previously consulted UNAuthorizationStatus nowhere. "Registered"
    // and "authorized" are different facts and render as different rows.
    private var notificationAuthStatus: RowStatus {
        let status = permissionsStore.capabilities
            .first { $0.permissionType == .notifications }?.status ?? .notDetermined
        return RowStatus(
            text: Self.notificationAuthorizationText(status),
            color: notificationAuthorizationColor(status),
            blinks: false
        )
    }

    /// Pure label rule (the #146 precedent — assertable without a container):
    /// `NotDetermined` must never render as anything green or active.
    /// `.limited` is how LiveNotificationService maps the provisional and
    /// ephemeral UNAuthorizationStatus cases.
    static func notificationAuthorizationText(_ status: PermissionStatus) -> String {
        switch status {
        case .notDetermined: "NOT REQUESTED"
        case .authorized, .authorizedAlways, .authorizedWhenInUse: "AUTHORIZED"
        case .limited: "PROVISIONAL"
        case .denied: "DENIED"
        case .restricted: "RESTRICTED"
        case .unsupported: "—"
        }
    }

    private func notificationAuthorizationColor(_ status: PermissionStatus) -> Color {
        switch status {
        case .authorized, .authorizedAlways, .authorizedWhenInUse: Design.Brand.accent
        case .limited: Design.Brand.forge
        case .denied, .restricted: Design.Colors.danger
        case .notDetermined, .unsupported: Design.Colors.mutedForeground
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
                sensorRow("Microphone", voicePermissionLabel(.microphone),
                          voicePermissionColor(.microphone))
                rowDivider
                sensorRow("Speech Recognition", voicePermissionLabel(.speechRecognition),
                          voicePermissionColor(.speechRecognition))
                rowDivider
                sensorRow("Audio Route", TalkAudioRoute.currentSummary() ?? "—",
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
            Design.Brand.accent
        case .denied, .restricted:
            Design.Colors.danger
        case .limited:
            Design.Brand.forge
        case .notDetermined, .unsupported, .none:
            Design.Colors.mutedForeground
        }
    }

    #if DEBUG
    // MARK: Local brain — forced-trip harness (#134, DEBUG builds only)
    //
    // Device-verification trigger for the merged #102 breaker + #110 speech
    // retraction: drives a synthetic degenerate stream through the REAL
    // on-device chat path (the live model's guardrails defeat organic loop
    // repros). The reply in the chat collapses to one copy of the loop unit,
    // Console shows the #102 escalation notice, and — with read-aloud on —
    // speech cuts instead of droning the loop.

    private enum ForcedTripState: Equatable {
        case idle
        case running
        case done
    }

    @State private var forcedTripState: ForcedTripState = .idle
    // #196: mirrors the persisted debug.sessionShape override; seeded from
    // defaults so the picker reflects the pending (next-launch) cell,
    // normalized through SessionShape so a RETIRED cell name ("armed-noprose"
    // from 176C, "armed-direct"/"armed-noneg" from the first battery) can't
    // leave the control unselected — it lands on production, by design.
    // Post-promotion (2026-07-28) production = armed-routed.
    @State private var sessionShapeOverride: String =
        LocalChatBackend.SessionShape(
            rawValue: UserDefaults.standard.string(forKey: "debug.sessionShape") ?? "armed-routed"
        )?.rawValue ?? "armed-routed"
    // #196: guards the one-tap rate battery against double-fires.
    @State private var batteryRunning = false

    // #196 second battery: one launcher, two powers — n=10 resolves the
    // reminder-grab question (8/10 -> ~0 is unmissable); n=20 is required
    // for a significant composition verdict (4/10 vs 8/10 at n=10 is
    // p~0.17 — the exact underpowering behind the afternoon's overturned
    // n=4 conviction).
    @ViewBuilder
    private func batteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            // Headless battery sessions can never answer a confirmation
            // card (non-cancellable continuation), so action-tool grabs
            // auto-decline for the run — which also measures post-denial
            // recovery behavior. The auto-modes are mutually exclusive:
            // clearing accept here (and both at run end) keeps the #200
            // launcher and this one from ever overlapping flags.
            container.toolConfirmationCenter.autoAcceptForBattery = false
            container.toolConfirmationCenter.autoDeclineForBattery = true
            // A ~20-minute n=20 must survive auto-lock — work-desk runs
            // (#196 results-page lane) have no cable keeping the screen
            // awake, and a locked screen suspends the run mid-battery.
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runShapeBattery(trials: trials)
                container.toolConfirmationCenter.autoDeclineForBattery = false
                container.toolConfirmationCenter.autoAcceptForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200 action battery: the action-SUCCESS path. Auto-ACCEPT armed —
    // every staged confirmation approves, so appropriate creates EXECUTE:
    // real EventKit/AlarmKit writes, every artifact marker-tagged by the
    // gate, all reaped before the DONE line. Run with Reminders/Calendar
    // permissions GRANTED (the observed #200 failure post-dates the grant).
    // Shares the batteryRunning guard with the other instruments.
    @ViewBuilder
    private func actionBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            // Mutually exclusive with the decline mode — decline would
            // measure the #196 contract, not action success.
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            // Same auto-lock guard as the shape battery.
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runActionBattery(trials: trials)
                // Both flags cleared at run end, whatever this run armed.
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200B destall battery: the reminder list-stall treatment as measured
    // cells (control / guidefix / toolfix / bothfix) × four prompts — the
    // haiku grab canary included, since the de-stall texts push toward
    // immediate creation. Auto-ACCEPT, real writes, reaped. Promotion only
    // on the classified verdict.
    @ViewBuilder
    private func destallBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runDestallBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200C instrfix battery: control vs the INSTRUCTIONS-level de-stall
    // clause (#200B falsified the tool-text seam — the stall fires before
    // tool engagement). Auto-ACCEPT, grab canary watching whether "create
    // it right away" pushes haiku grabs above the 8/10 control baseline.
    @ViewBuilder
    private func instrfixBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runInstrfixBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200E toolmode battery: promoted-production control vs the structural
    // `.required` treatment (DynamicProfile with the mandatory demote-after-
    // first-call exit — a static .required loops). Auto-ACCEPT; the canary
    // measures which tool a FORCED call grabs on the haiku misroute.
    @ViewBuilder
    private func toolmodeBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runToolmodeBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200F community battery: promoted-production control vs the three
    // survey-derived treatments (per-intent scoped belt, create-only belt,
    // find-first carve-out instructions). Auto-ACCEPT; per-trial reap.
    @ViewBuilder
    private func communityBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runCommunityBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200G findfix re-verify: promoted control vs explicit-true findfix
    // (identity — both halves measure production and pool).
    @ViewBuilder
    private func findfixBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runFindfixBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200H spiral battery: promoted control vs the lookup-spiral
    // carve-out (instructions) and the third-strike demote (structural).
    @ViewBuilder
    private func spiralBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runSpiralBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #209 read-tool battery: production vs the pinned read-tool rollback on
    // prompts where OMITTING the field is correct. READ tools only — nothing
    // is written, so no auto-accept is needed and the reap is a no-op.
    @ViewBuilder
    private func readToolBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runReadToolBattery(trials: trials)
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #211 motion-scope: control vs the scoped readMotion description. READ
    // tools only — nothing written, no auto-accept needed.
    @ViewBuilder
    private func motionRedirectBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runMotionRedirectBattery(trials: trials)
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #211 motion-scope: control vs the scoped readMotion description.
    @ViewBuilder
    private func motionScopeBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runMotionScopeBattery(trials: trials)
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200I spiralfix re-measure: promoted control vs the event-scoped
    // reword of the lookup-spiral carve-out. Strikefix is parked (its
    // tally instrument is unproven), so this is 2 cells, not 3.
    @ViewBuilder
    private func spiralfixBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runSpiralfixBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200J: promoted control vs the card-narration clause — the
    // treatment for #200I's largest failure bucket (zero-tool trials that
    // type the confirmation card out in prose and call nothing).
    @ViewBuilder
    private func cardfixBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runCardfixBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200K: the promoted control + the (now identity) cardfix cell —
    // pooled as the production re-verify — plus the datefix treatment.
    @ViewBuilder
    private func datefixBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runDatefixBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200L: promoted production vs the pinned card-clause rollback vs
    // the #200I spiral carve-out — the calendar lane.
    @ViewBuilder
    private func calendarBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runCalendarBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200M: production vs the v3 dead-end carve-out vs v2, same run.
    @ViewBuilder
    private func deadendBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runDeadendBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200N: the v3 confirmation A/B — production vs the dead-end
    // carve-out only, second independent run before any promotion.
    @ViewBuilder
    private func deadendVerifyBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runDeadendVerifyBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200O: the promoted control + the (now identity) deadendfix cell
    // pooled as the production re-verify, plus the grabfix treatment.
    @ViewBuilder
    private func grabfixBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runGrabfixBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200P: production vs the card-correction clause — the conserved
    // zero-tool stall, treated as a class rather than field by field.
    @ViewBuilder
    private func stallfixBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runStallfixBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200Q: production vs the reminder tool whose optional fields are
    // optional in the SCHEMA — the stall's structural seam.
    @ViewBuilder
    private func schemafixBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runSchemafixBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #201B: the same two arms REVERSED — production first, in the cool slot,
    // so the run doubles as the thermal control.
    @ViewBuilder
    private func deadendReversedBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runDeadendReversedBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #201: #200U's contact fix re-measured at n=20, production last — the
    // primary is a dead-end COUNT, which n=10 could not carry.
    @ViewBuilder
    private func deadendReconsiderBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runDeadendReconsiderBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200X: the promoted calendar tool against its OWN pinned rollback,
    // warm, production last — the confidence run the promotion is owed.
    @ViewBuilder
    private func calRollbackVerifyBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runCalRollbackVerifyBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200W: #200T's calendar arms re-run WARM with production last. The
    // primaries are the location-spiral and invented-location counts, not the
    // rate — warm production calendar is already ~9/10.
    @ViewBuilder
    private func calfixWarmBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runCalfixWarmBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200V: #200U's three arms REVERSED (production last) after a discarded
    // warm-up pass — the confirmation run that tests the cell-order confound.
    @ViewBuilder
    private func deadendConfirmBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runDeadendConfirmBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200U: control vs the contact not-found RESULT carrying continuation,
    // plus the ceiling probe with the tool absent.
    @ViewBuilder
    private func deadend2BatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runDeadend2Battery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200T: production control vs the calendar tool with its two
    // undefaultable fields optional in the schema.
    @ViewBuilder
    private func calfixBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runCalfixBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200S: pooled production re-verify (control + the now-identity
    // schemafix cell) vs the pinned pre-promotion rollback.
    @ViewBuilder
    private func schemaReverifyBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runSchemaReverifyBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #200 orphan cleanup: the four crashed action batteries stranded
    // their battery alarms (up to ~50 armed for 6:30 AM, ringing through
    // Silent). AlarmKit enumeration carries no label, so this cancels ALL
    // Talaria alarms — real /alarm ones included. User-invoked only.
    @State private var alarmSweepResult: String?

    @ViewBuilder
    private var alarmSweepButton: some View {
        Button {
            let result = AlarmService.sweepAllTalariaAlarms()
            alarmSweepResult = "cancelled=\(result.cancelled) failed=\(result.failed)"
        } label: {
            MonoLabel(alarmSweepResult.map { "Swept — \($0)" } ?? "Sweep ALL Talaria alarms (incl. real)",
                      size: 10, tracking: Design.Tracking.mono,
                      color: alarmSweepResult == nil ? Design.Colors.danger : Design.Colors.mutedForeground)
        }
        .disabled(batteryRunning)
    }

    // #196 battery 4: router-accuracy probe — no tools execute (pure
    // classification), so no confirmation auto-decline is needed; the
    // shared batteryRunning guard keeps the two instruments from
    // overlapping on the model.
    @ViewBuilder
    private func routerProbeButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            // Same auto-lock guard as the battery button — 200 router
            // generations take minutes, not seconds.
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runRouterProbe(trials: trials)
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #202A: same shape as the #196 router probe — pure classification, so
    // no confirmation auto-decline and nothing to sweep afterwards. The
    // idle-timer lock matters here too: ~585 generations is ~10 minutes.
    @ViewBuilder
    private func routerContextProbeButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runRouterContextProbe(trials: trials)
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #202B two-turn battery: an offer, then a bare affirmative. Auto-ACCEPT
    // so an appropriate create EXECUTES and is countable as an artifact —
    // real writes, marker-tagged, reaped per trial.
    @ViewBuilder
    private func twoTurnBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runTwoTurnBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #202C: the honesty lane. Every trial runs with an EMPTY belt, so no
    // confirmation can fire and nothing can be written — no grants needed
    // and nothing to reap, same as the probes.
    @ViewBuilder
    private func honestyBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runHonestyBattery(trials: trials)
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #207: same shape as the other probes — classification only.
    @ViewBuilder
    private func imageRoutingProbeButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runImageRoutingProbe(trials: trials)
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #199: the DECLINE lane. auto-DECLINE is mutually exclusive with
    // auto-accept — declining is the whole measurement, so no artifact can
    // be created and there is nothing to reap.
    @ViewBuilder
    private func declineBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoAcceptForBattery = false
            container.toolConfirmationCenter.autoDeclineForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runDeclineBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #204: full action battery — auto-ACCEPT, real writes, reaped per
    // trial. Run with Reminders/Calendar GRANTED.
    @ViewBuilder
    private func clauseReverifyBatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            container.toolConfirmationCenter.autoDeclineForBattery = false
            container.toolConfirmationCenter.autoAcceptForBattery = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runClauseReverifyBattery(trials: trials)
                container.toolConfirmationCenter.autoAcceptForBattery = false
                container.toolConfirmationCenter.autoDeclineForBattery = false
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    // #202D: same empty-belt shape as #202C — nothing to grant, nothing to reap.
    @ViewBuilder
    private func honestyV2BatteryButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runHonestyBattery(
                    trials: trials, cells: LocalChatBackend.honestyV2BatteryCells)
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    @ViewBuilder
    private func longContextProbeButton(trials: Int, label: String) -> some View {
        Button {
            guard !batteryRunning, let backend = container.localChatBackend else { return }
            batteryRunning = true
            UIApplication.shared.isIdleTimerDisabled = true
            Task {
                await backend.runLongContextProbe(trials: trials)
                UIApplication.shared.isIdleTimerDisabled = false
                batteryRunning = false
            }
        } label: {
            MonoLabel(batteryRunning ? "Battery running… watch Console" : label,
                      size: 10, tracking: Design.Tracking.mono,
                      color: batteryRunning ? Design.Colors.mutedForeground : Design.Colors.foregroundBright)
        }
        .disabled(batteryRunning)
    }

    private var localBrainPanel: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Local brain — #102", size: 10, tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)

            // #196 desk A/B: pick the session shape for the NEXT launch.
            // Mirrors the TALARIA_SESSION_SHAPE launch env (which wins when
            // set); read once per process, so a change here needs a
            // force-quit + relaunch to take effect — which is the A/B
            // protocol between cells anyway.
            VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                MonoLabel("Session shape A/B (#196) — active: \(LocalChatBackend.activeSessionShape.rawValue). Changes apply after force-quit + relaunch; start a NEW chat per cell.",
                          size: 9, tracking: Design.Tracking.mono,
                          color: Design.Colors.secondaryForeground)
                Picker("Session shape", selection: $sessionShapeOverride) {
                    // Post-promotion (2026-07-28): armed-routed IS
                    // production; armed is the legacy control.
                    Text("armed-routed (production)").tag("armed-routed")
                    Text("armed (legacy control)").tag("armed")
                    Text("toolless-lic (payload A)").tag("toolless-lic")
                    Text("toolless-lic2 (payload B)").tag("toolless-lic2")
                    // Battery-3 decomposition cells + battery-2 treatments:
                    // reachable for spot checks, out of the battery list.
                    Text("armed-noinstr").tag("armed-noinstr")
                    Text("toolless-noinstr").tag("toolless-noinstr")
                    Text("armed-readonly").tag("armed-readonly")
                    Text("armed-nocall").tag("armed-nocall")
                    Text("armed-noschema").tag("armed-noschema")
                    Text("armed-remfix (held)").tag("armed-remfix")
                    Text("armed-complic (held)").tag("armed-complic")
                    Text("armed-fix (held)").tag("armed-fix")
                    Text("toolless (held)").tag("toolless")
                }
                // Menu, not segmented: eleven cells don't fit a phone-width
                // segmented control (#196).
                .pickerStyle(.menu)
                .onChange(of: sessionShapeOverride) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: "debug.sessionShape")
                }

                // #196 fourth battery (cure lane): 4 cells × 3 prompts × n
                // trials, in-process, results to Console (category
                // LocalChatBackend, lines prefixed "battery:"); armed-routed
                // trials log their per-trial "route=" line, and the router
                // probe measures classification accuracy alone (lines
                // prefixed "router:"). No force-quit cycling needed.
                HStack(spacing: Design.Spacing.sm) {
                    batteryButton(trials: 10, label: "Battery n=10 (~120 trials)")
                    batteryButton(trials: 20, label: "Battery n=20 (~240)")
                }
                HStack(spacing: Design.Spacing.sm) {
                    routerProbeButton(trials: 20, label: "Router probe n=20 (200)")
                }
                // #200 action battery: 1 armed cell × 3 create prompts × n,
                // auto-ACCEPT — real writes, [T27-battery]-tagged, reaped
                // before DONE. Run with Reminders/Calendar GRANTED. n=5 is
                // the crash-repro power (both 2026-07-28 n=20 attempts died
                // mid-run); n=20 is the measurement power.
                HStack(spacing: Design.Spacing.sm) {
                    actionBatteryButton(trials: 5, label: "Action battery n=5 (15)")
                    actionBatteryButton(trials: 20, label: "Action battery n=20 (60)")
                }
                // #209: production vs the pinned read-tool rollback, on prompts
                // where omitting the field is CORRECT. 2 cells × 4 prompts × n.
                HStack(spacing: Design.Spacing.sm) {
                    readToolBatteryButton(trials: 10, label: "Read-tool battery n=10 (80)")
                }
                // #211: control vs the scoped readMotion description, on the
                // step question the app currently answers wrong 20/20.
                HStack(spacing: Design.Spacing.sm) {
                    motionScopeBatteryButton(trials: 10, label: "Motion-scope battery n=10 (40)")
                }
                // #211 follow-on: promoted vs promoted-plus-boundary, against
                // the extra-tool chaining the promotion cost.
                HStack(spacing: Design.Spacing.sm) {
                    motionRedirectBatteryButton(trials: 10, label: "Motion-redirect battery n=10 (40)")
                }
                // #200B: 4 treatment cells × 4 prompts (haiku grab canary).
                HStack(spacing: Design.Spacing.sm) {
                    destallBatteryButton(trials: 10, label: "Destall battery n=10 (160)")
                }
                // #200C: control vs instructions-level de-stall clause.
                HStack(spacing: Design.Spacing.sm) {
                    instrfixBatteryButton(trials: 10, label: "Instrfix battery n=10 (80)")
                }
                // #200E: control vs structural .required (demote exit).
                HStack(spacing: Design.Spacing.sm) {
                    toolmodeBatteryButton(trials: 10, label: "Toolmode battery n=10 (80)")
                }
                // #200F: control vs scoped / create-only / find-first cells.
                HStack(spacing: Design.Spacing.sm) {
                    communityBatteryButton(trials: 10, label: "Community battery n=10 (160)")
                }
                // #200G: promoted-production re-verify (both halves pool).
                HStack(spacing: Design.Spacing.sm) {
                    findfixBatteryButton(trials: 10, label: "Findfix battery n=10 (80)")
                }
                // #200H: control vs spiral carve-out / third-strike demote.
                HStack(spacing: Design.Spacing.sm) {
                    spiralBatteryButton(trials: 10, label: "Spiral battery n=10 (120)")
                }
                // #200I: the same control vs the event-scoped reword only.
                HStack(spacing: Design.Spacing.sm) {
                    spiralfixBatteryButton(trials: 10, label: "Spiralfix battery n=10 (80)")
                }
                // #200J: control vs the card-narration clause.
                HStack(spacing: Design.Spacing.sm) {
                    cardfixBatteryButton(trials: 10, label: "Cardfix battery n=10 (80)")
                }
                // #200K: pooled production re-verify + the datefix cell.
                HStack(spacing: Design.Spacing.sm) {
                    datefixBatteryButton(trials: 10, label: "Datefix battery n=10 (120)")
                }
                // #200L: production vs card-clause rollback vs spiralfix.
                HStack(spacing: Design.Spacing.sm) {
                    calendarBatteryButton(trials: 10, label: "Calendar battery n=10 (120)")
                }
                // #200M: production vs carve-out v3 vs carve-out v2.
                HStack(spacing: Design.Spacing.sm) {
                    deadendBatteryButton(trials: 10, label: "Deadend battery n=10 (120)")
                }
                // #200N: the v3 confirmation A/B.
                HStack(spacing: Design.Spacing.sm) {
                    deadendVerifyBatteryButton(trials: 10, label: "Deadend verify n=10 (80)")
                }
                // #200O: pooled production re-verify + the grabfix cell.
                HStack(spacing: Design.Spacing.sm) {
                    grabfixBatteryButton(trials: 10, label: "Grabfix battery n=10 (120)")
                }
                // #200P: production vs the card-correction clause.
                HStack(spacing: Design.Spacing.sm) {
                    stallfixBatteryButton(trials: 10, label: "Stallfix battery n=10 (80)")
                }
                // #200Q: production vs the schema swap.
                HStack(spacing: Design.Spacing.sm) {
                    schemafixBatteryButton(trials: 10, label: "Schemafix battery n=10 (80)")
                }
                // #200S: promotion re-verify vs its own rollback.
                HStack(spacing: Design.Spacing.sm) {
                    schemaReverifyBatteryButton(trials: 10, label: "Schema re-verify n=10 (120)")
                }
                // #200T: production vs the calendar schema swap.
                HStack(spacing: Design.Spacing.sm) {
                    calfixBatteryButton(trials: 10, label: "Calendar schema n=10 (80)")
                }
                // #200U: contact dead-end fix + its ceiling probe.
                HStack(spacing: Design.Spacing.sm) {
                    deadend2BatteryButton(trials: 10, label: "Contact dead-end n=10 (120)")
                }
                // #200V: the same three arms reversed, warm-up first.
                HStack(spacing: Design.Spacing.sm) {
                    deadendConfirmBatteryButton(trials: 10, label: "Dead-end confirm n=10 (120+4)")
                }
                // #200W: calendar arms warm, production last.
                HStack(spacing: Design.Spacing.sm) {
                    calfixWarmBatteryButton(trials: 10, label: "Calendar warm n=10 (80+4)")
                }
                // #200X: promoted calendar tool vs its pinned rollback.
                HStack(spacing: Design.Spacing.sm) {
                    calRollbackVerifyBatteryButton(trials: 10, label: "Calendar rollback n=10 (80+4)")
                }
                // #201: contact dead-end fix re-measured at n=20.
                HStack(spacing: Design.Spacing.sm) {
                    deadendReconsiderBatteryButton(trials: 20, label: "Dead-end reconsider n=20 (160+4)")
                }
                // #201B: the SAME two arms at n=40 — powered from the 16.7%
                // base rate so a 0-vs-k comparison can actually conclude.
                HStack(spacing: Design.Spacing.sm) {
                    deadendReconsiderBatteryButton(trials: 40, label: "Dead-end POWER n=40 (320+4)")
                }
                // #201B confirmation: reversed, production in the cool slot.
                HStack(spacing: Design.Spacing.sm) {
                    deadendReversedBatteryButton(trials: 40, label: "Dead-end REVERSED n=40 (320+4)")
                }
                // #202A: the context-blind router probe. 3 generating
                // variants × 23 rows × n, plus the free deterministic
                // lenrule column. Pure classification — no tool runs and
                // nothing is written, so this one needs no grants and has
                // nothing to reap.
                HStack(spacing: Design.Spacing.sm) {
                    routerContextProbeButton(trials: 15, label: "Router context n=15 (~585)")
                }
                // #202B: the two-turn offer→accept shape. Auto-ACCEPT, real
                // writes, reaped per trial — run with Reminders GRANTED.
                HStack(spacing: Design.Spacing.sm) {
                    twoTurnBatteryButton(trials: 12, label: "Two-turn n=12 (24+5+1)")
                }
                // #202C: the toolless honesty clause + the #196 tic guard.
                // NO belt in any trial, so nothing can be created and there
                // is nothing to grant or reap.
                HStack(spacing: Design.Spacing.sm) {
                    honestyBatteryButton(trials: 10, label: "Honesty n=10 (20+24+1)")
                }
                // #202C companion: ctx-a on realistic LONG contexts, timed.
                HStack(spacing: Design.Spacing.sm) {
                    longContextProbeButton(trials: 5, label: "Long-context probe n=5 (50)")
                }
                // #207: can the router be told an image is attached, and is
                // that enough? Pure classification — no grants, no reap.
                HStack(spacing: Design.Spacing.sm) {
                    imageRoutingProbeButton(trials: 10, label: "Image routing n=10 (420)")
                }
                // #199: auto-DECLINE. Measures what production SAYS after the
                // user says no. Nothing is created, so nothing is reaped.
                HStack(spacing: Design.Spacing.sm) {
                    declineBatteryButton(trials: 10, label: "Decline n=10 (40)")
                }
                // #204: the two promoted instruction clauses vs their own
                // rollbacks, warm and within-run. Auto-ACCEPT, real writes.
                HStack(spacing: Design.Spacing.sm) {
                    clauseReverifyBatteryButton(trials: 10, label: "Clause re-verify n=10 (120+4)")
                }
                // #202D: clause v1 vs the reworded v2 — production absent,
                // its number is settled across two runs.
                HStack(spacing: Design.Spacing.sm) {
                    honestyV2BatteryButton(trials: 10, label: "Honesty v2 n=10 (20+24+1)")
                }
                HStack(spacing: Design.Spacing.sm) {
                    alarmSweepButton
                }

                // #196 results-page lane: every run above also persists to
                // the structured store — view, drill into raw replies, and
                // export from anywhere, no Console required.
                NavigationLink {
                    BatteryResultsScreen()
                } label: {
                    MonoLabel("Battery results →", size: 10, weight: .medium,
                              tracking: Design.Tracking.mono, color: Design.Brand.accent)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: Design.Spacing.sm) {
                MonoLabel("Streams a synthetic loop through the real on-device chat path. Turn on read-aloud first to verify #110.",
                          size: 9, tracking: Design.Tracking.mono,
                          color: Design.Colors.secondaryForeground)
                GhostButton(
                    title: forcedTripState == .running ? "Tripping…" : "Force repetition trip",
                    systemImage: "repeat",
                    height: 40
                ) {
                    runForcedTrip(holdLiveSDKStream: false)
                }
                .disabled(forcedTripState == .running)
                GhostButton(
                    title: "Force trip (live SDK)",
                    systemImage: "bolt",
                    height: 40
                ) {
                    runForcedTrip(holdLiveSDKStream: true)
                }
                .disabled(forcedTripState == .running)
                if forcedTripState == .done {
                    MonoLabel("Tripped — check the chat reply, the #102 Console notice, and that the next send still works.",
                              size: 9, tracking: Design.Tracking.mono,
                              color: Design.Brand.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Design.Spacing.md)
            .hudPanel(
                cornerRadius: Design.CornerRadius.lg,
                borderColor: Design.Colors.accentTint(0.12),
                fill: Design.Colors.background.opacity(0.5),
                innerGlow: false
            )
        }
    }

    private func runForcedTrip(holdLiveSDKStream: Bool) {
        guard forcedTripState != .running else { return }
        forcedTripState = .running
        Task {
            await container.chatStore.debugRunForcedTrip(holdLiveSDKStream: holdLiveSDKStream)
            forcedTripState = .done
        }
    }
    #endif

    // MARK: Sensor pipeline (#15)

    @ViewBuilder
    private var sensorPanel: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Sensor Pipeline", size: 10, tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)

            if let s = container.sensorUploadService?.sensorDiagnostics {
                VStack(spacing: 0) {
                    sensorRow("Pipeline", s.isActive ? "ACTIVE" : "IDLE",
                              s.isActive ? Design.Brand.accent : Design.Colors.mutedForeground,
                              blinks: s.isActive)
                    rowDivider
                    sensorRow("Paired", s.isPaired ? "YES" : "NO",
                              s.isPaired ? Design.Brand.accent : Design.Colors.danger)
                    rowDivider
                    sensorRow("Access Token", tokenLabel, tokenColor)
                    rowDivider
                    sensorRow("Pending Location", pendingLocationText(s),
                              s.pendingLocation == nil ? Design.Colors.mutedForeground : Design.Brand.forge)
                    rowDivider
                    sensorRow("Pending Health", pendingHealthText(s),
                              s.pendingHealthCount == 0 ? Design.Colors.mutedForeground : Design.Brand.forge)
                    rowDivider
                    sensorRow("Last Drain", lastDrainText(s),
                              s.lastDrainSummary == nil ? Design.Colors.mutedForeground : Design.Colors.secondaryForeground)
                    rowDivider
                    sensorRow("Location", "\(s.locationAuthorization.displayLabel) · \(s.locationAccuracyLabel)",
                              locationColor(s.locationAuthorization))
                    rowDivider
                    sensorRow("Health", s.healthAuthorization.displayLabel, permissionColor(s.healthAuthorization))
                    rowDivider
                    sensorRow("Motion", s.motionAuthorization.displayLabel, permissionColor(s.motionAuthorization))
                }
                .hudPanel(
                    cornerRadius: Design.CornerRadius.lg,
                    borderColor: Design.Colors.accentTint(0.12),
                    fill: Design.Colors.background.opacity(0.5),
                    innerGlow: false
                )
            } else {
                MonoLabel("Sensor pipeline unavailable in this build.", size: 10,
                          tracking: Design.Tracking.mono, color: Design.Colors.secondaryForeground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Design.Spacing.md)
                    .hudPanel(
                        cornerRadius: Design.CornerRadius.lg,
                        borderColor: Design.Colors.accentTint(0.12),
                        fill: Design.Colors.background.opacity(0.5),
                        innerGlow: false
                    )
            }
        }
    }

    private func sensorRow(_ label: String, _ value: String, _ color: Color, blinks: Bool = false) -> some View {
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

    private var tokenLabel: String {
        switch sensorAccessToken {
        case .some(true): "PRESENT"
        case .some(false): "ABSENT"
        case .none: "—"
        }
    }

    private var tokenColor: Color {
        switch sensorAccessToken {
        case .some(true): Design.Brand.accent
        case .some(false): Design.Colors.danger
        case .none: Design.Colors.mutedForeground
        }
    }

    private func pendingLocationText(_ s: SensorUploadService.SensorDiagnostics) -> String {
        guard let loc = s.pendingLocation else { return "none" }
        let coord = String(format: "%.3f, %.3f", loc.latitude, loc.longitude)
        return "\(coord) · \(relativeAge(loc.recordedAt))"
    }

    private func pendingHealthText(_ s: SensorUploadService.SensorDiagnostics) -> String {
        s.pendingHealthCount == 0 ? "none" : "\(s.pendingHealthCount) sample\(s.pendingHealthCount == 1 ? "" : "s")"
    }

    private func lastDrainText(_ s: SensorUploadService.SensorDiagnostics) -> String {
        guard let summary = s.lastDrainSummary else { return "—" }
        guard let at = s.lastDrainAt else { return summary }
        return "\(summary) · \(relativeAge(at))"
    }

    private func relativeAge(_ date: Date) -> String {
        let seconds = Int(max(0, Date().timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86_400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86_400)d ago"
    }

    private func locationColor(_ level: LocationAuthorizationLevel) -> Color {
        switch level {
        case .always, .whenInUse: Design.Brand.accent
        case .denied, .restricted: Design.Colors.danger
        case .notDetermined: Design.Colors.mutedForeground
        }
    }

    private func permissionColor(_ status: PermissionStatus) -> Color {
        switch status {
        case .authorized, .authorizedWhenInUse, .authorizedAlways: Design.Brand.accent
        case .limited: Design.Brand.forge
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
