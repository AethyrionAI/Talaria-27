import SwiftUI

// MARK: - Notifications settings screen (Settings → NOTIFICATIONS, sub-screen 10)
//
// Alerts + haptics. Mirrors design/Settings-Additional.dc.html page 10,
// real-data-only:
//   • The Push toggle drives the real notificationsEnabled flag and re-runs
//     registerPushTokenIfNeeded so the relay registration follows the switch.
//   • The hero + status reflect live truth: OS authorization (PermissionsStore)
//     and the push-token pipeline state (AppContainer.pushTokenPipelineState —
//     the same source Diagnostics renders, so the two screens agree). When the
//     OS has denied notifications we say so rather than implying alerts are
//     active.
struct NotificationsSettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppContainer.self) private var container
    @Environment(PermissionsStore.self) private var permissionsStore
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Design.Spacing.lg) {
                    SettingsScreenHeader(title: "Notifications", subtitle: "Alerts") { dismiss() }
                    heroPanel
                    pushSection
                    feedbackSection
                    footer
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)
            }
        }
        .navigationTitle("Notifications")
        .toolbarVisibility(.hidden, for: .navigationBar)
        .task { await permissionsStore.reloadCapabilities() }
    }

    // MARK: Hero

    private var heroPanel: some View {
        VStack(spacing: Design.Spacing.md) {
            Image(systemName: hero.icon)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(hero.color)
                .frame(width: 58, height: 58)
                .background(
                    Circle().strokeBorder(hero.color.opacity(0.3), lineWidth: 1.5)
                )
                .hudGlow(hero.color, radius: 12, strength: 0.5)

            Text(hero.title)
                .font(Design.Typography.display(18, weight: .bold, relativeTo: .title3))
                .tracking(Design.Tracking.display)
                .foregroundStyle(Design.Colors.foregroundBright)

            MonoLabel(hero.subtitle, size: 10, weight: .medium,
                      tracking: Design.Tracking.mono, color: hero.color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Design.Spacing.xl)
        .padding(.horizontal, Design.Spacing.md)
        .hudPanel(
            cornerRadius: Design.CornerRadius.xl,
            borderColor: hero.color.opacity(0.28),
            fill: Design.Colors.accentTint(0.07),
            innerGlow: true
        )
    }

    // #189: the single resolution rule for what the hero asserts. OS
    // authorization is a fact the old hero never read — an APNs token and a
    // relay registration are both obtainable while authorization is
    // NotDetermined, so "ALERTS ACTIVE" could render while every alert was
    // silently dropped. Pure (the #146 precedent) so the no-false-green rule
    // is assertable without standing up a container.
    enum AlertsDisplayState: Equatable {
        /// OS authorization denied/restricted — nothing can be delivered.
        case blocked
        /// Authorization has never been requested (`NotDetermined`).
        case notRequested
        /// The in-app Push toggle is off.
        case paused
        /// Authorized but iOS has not issued an APNs token.
        case awaitingToken
        /// Authorized, token held, relay registration unconfirmed.
        case awaitingRelay
        /// Provisional/ephemeral authorization (quiet delivery) + registered —
        /// alerts flow, but not as full banners; labeled as its own fact.
        case provisional
        /// Authorized + registered — the only full green.
        case active
    }

    static func alertsDisplayState(
        authorization: PermissionStatus,
        notificationsEnabled: Bool,
        pipeline: AppContainer.PushTokenPipelineState
    ) -> AlertsDisplayState {
        // The OS gate precedes the app gate: when iOS cannot deliver at all,
        // that is the headline regardless of the in-app toggle.
        switch authorization {
        case .denied, .restricted: return .blocked
        case .notDetermined: return .notRequested
        default: break
        }
        guard notificationsEnabled else { return .paused }
        switch pipeline {
        case .notIssued: return .awaitingToken
        case .awaitingRelay: return .awaitingRelay
        case .registered: return authorization == .limited ? .provisional : .active
        }
    }

    private var displayState: AlertsDisplayState {
        Self.alertsDisplayState(
            authorization: notifAuthStatus,
            notificationsEnabled: notificationsEnabled,
            pipeline: pipelineState
        )
    }

    private var hero: (icon: String, title: String, subtitle: String, color: Color) {
        switch displayState {
        case .blocked:
            ("bell.slash", "ALERTS BLOCKED", "ENABLE IN SYSTEM SETTINGS", Design.Colors.danger)
        case .notRequested:
            ("bell", "ALERTS NOT SET UP", "PERMISSION NOT REQUESTED", Design.Brand.forge)
        case .paused:
            ("bell.slash", "ALERTS PAUSED", "PUSH DISABLED", Design.Colors.mutedForeground)
        case .awaitingToken:
            ("bell", "ALERTS PENDING", "AWAITING APNS TOKEN", Design.Brand.forge)
        case .awaitingRelay:
            ("bell", "ALERTS PENDING", "AWAITING RELAY REGISTRATION", Design.Brand.forge)
        case .provisional:
            ("bell.badge", "ALERTS QUIET", "PROVISIONAL · DELIVERED QUIETLY", Design.Brand.forge)
        case .active:
            ("bell.badge", "ALERTS ACTIVE", activeSubtitle, Design.Brand.accent)
        }
    }

    private var activeSubtitle: String {
        hapticsEnabled ? "PUSH + HAPTICS ENABLED" : "PUSH ENABLED"
    }

    // MARK: Push

    private var pushSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Push", size: 10, tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)

            VStack(spacing: 0) {
                HStack {
                    Text("Push Notifications")
                        .font(Design.Typography.callout)
                        .foregroundStyle(Design.Colors.foreground)
                    Spacer()
                    Toggle("", isOn: notificationsBinding)
                        .labelsHidden()
                        .tint(Design.Brand.accent)
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)

                Rectangle()
                    .fill(Design.Colors.hairline)
                    .frame(height: 1)
                    .padding(.horizontal, Design.Spacing.md)

                // #189: two rows, two facts. OS authorization and relay
                // registration are independent — both can be true or false in
                // any combination, so neither may stand in for the other.
                HStack(spacing: Design.Spacing.sm) {
                    StatusPip(color: permissionState.color, diameter: 6)
                    MonoLabel("PERMISSION · \(permissionState.text)", size: 10, weight: .medium,
                              tracking: Design.Tracking.mono, color: permissionState.color)
                    Spacer()
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)

                Rectangle()
                    .fill(Design.Colors.hairline)
                    .frame(height: 1)
                    .padding(.horizontal, Design.Spacing.md)

                HStack(spacing: Design.Spacing.sm) {
                    StatusPip(color: tokenState.color, diameter: 6)
                    MonoLabel(tokenState.text, size: 10, weight: .medium,
                              tracking: Design.Tracking.mono, color: tokenState.color)
                    Spacer()
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)
            }
            .hudPanel(
                cornerRadius: Design.CornerRadius.lg,
                borderColor: Design.Colors.accentTint(0.12),
                fill: Design.Colors.background.opacity(0.5),
                innerGlow: false
            )

            if displayState == .notRequested {
                // #189: the in-place way out of NotDetermined — the primary
                // priming path rides the first chat send, but this screen must
                // not be a dead end for a user who lands here first.
                GhostButton(title: "Enable Notifications", systemImage: "bell.badge", height: 40) {
                    Task { await permissionsStore.requestPermission(for: .notifications) }
                }
            }

            if osDenied {
                Text("Notifications are turned off for Talaria in iOS Settings. Push won't be delivered until re-enabled there.")
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground)
            }
        }
    }

    /// #189: the OS-authorization fact, from UNAuthorizationStatus via
    /// PermissionsStore — never inferred from token or registration state.
    /// `.limited` is how LiveNotificationService maps provisional/ephemeral.
    private var permissionState: (text: String, color: Color) {
        switch notifAuthStatus {
        case .authorized, .authorizedAlways, .authorizedWhenInUse:
            ("GRANTED", Design.Brand.accent)
        case .limited:
            ("PROVISIONAL", Design.Brand.forge)
        case .denied:
            ("DENIED", Design.Colors.danger)
        case .restricted:
            ("RESTRICTED", Design.Colors.danger)
        case .notDetermined:
            ("NOT REQUESTED", Design.Brand.forge)
        case .unsupported:
            ("—", Design.Colors.mutedForeground)
        }
    }

    // Same three-state source of truth Diagnostics renders (AppContainer.
    // pushTokenPipelineState) so the two screens can never contradict:
    // APNs token issuance and relay registration are separate stages. Pure
    // pipeline truth — the OS-authorization fact lives in the PERMISSION row
    // above (#189), not folded in here.
    private var tokenState: (text: String, color: Color) {
        switch pipelineState {
        case .registered:    return ("RELAY REGISTERED", Design.Brand.accent)
        case .awaitingRelay: return ("TOKEN HELD · AWAITING RELAY", Design.Brand.forge)
        case .notIssued:     return ("NO APNS TOKEN", Design.Colors.mutedForeground)
        }
    }

    // MARK: Feedback

    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Feedback", size: 10, tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)

            HStack {
                Text("Haptic Feedback")
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.foreground)
                Spacer()
                Toggle("", isOn: hapticBinding)
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
    }

    // MARK: Footer

    private var footer: some View {
        MonoLabel("ALERTS DELIVERED VIA APNs · DEVICE-BOUND", size: 9, weight: .regular,
                  tracking: Design.Tracking.monoWide, color: Design.Colors.dimForeground)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, Design.Spacing.xs)
            .padding(.bottom, Design.Spacing.md)
    }

    // MARK: Derived state

    private var notificationsEnabled: Bool { settingsStore.settings.notificationsEnabled }
    private var hapticsEnabled: Bool { settingsStore.settings.hapticFeedbackEnabled }
    private var pipelineState: AppContainer.PushTokenPipelineState { container.pushTokenPipelineState }

    private var notifAuthStatus: PermissionStatus {
        permissionsStore.capabilities.first { $0.permissionType == .notifications }?.status ?? .notDetermined
    }

    private var osDenied: Bool {
        notifAuthStatus == .denied || notifAuthStatus == .restricted
    }

    // MARK: Bindings

    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.notificationsEnabled },
            set: { newValue in
                settingsStore.settings.notificationsEnabled = newValue
                // Mirror the relay registration to the switch, like the live app.
                Task {
                    if let token = container.cachedAPNsDeviceToken {
                        await container.registerPushTokenIfNeeded(token)
                    }
                }
            }
        )
    }

    private var hapticBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.hapticFeedbackEnabled },
            set: { settingsStore.settings.hapticFeedbackEnabled = $0 }
        )
    }
}
