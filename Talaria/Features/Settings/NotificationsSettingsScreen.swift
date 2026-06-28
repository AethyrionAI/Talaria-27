import SwiftUI

// MARK: - Notifications settings screen (Settings → NOTIFICATIONS, sub-screen 10)
//
// Alerts + haptics. Mirrors design/Settings-Additional.dc.html page 10,
// real-data-only:
//   • The Push toggle drives the real notificationsEnabled flag and re-runs
//     registerPushTokenIfNeeded so the relay registration follows the switch.
//   • The hero + status reflect live truth: OS authorization (PermissionsStore)
//     and the actual relay token-registration state (sessionStore). When the OS
//     has denied notifications we say so rather than implying alerts are active.
struct NotificationsSettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppContainer.self) private var container
    @Environment(AppSessionStore.self) private var sessionStore
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

    private var hero: (icon: String, title: String, subtitle: String, color: Color) {
        if osDenied {
            return ("bell.slash", "ALERTS BLOCKED", "ENABLE IN SYSTEM SETTINGS", Design.Colors.danger)
        }
        guard notificationsEnabled else {
            return ("bell.slash", "ALERTS PAUSED", "PUSH DISABLED", Design.Colors.mutedForeground)
        }
        if tokenRegistered {
            return ("bell.badge", "ALERTS ACTIVE", activeSubtitle, Design.Brand.accent)
        }
        return ("bell", "ALERTS PENDING", "AWAITING TOKEN REGISTRATION", Design.Brand.forge)
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
                    .fill(Design.Colors.cyanHairline)
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

            if osDenied {
                Text("Notifications are turned off for Talaria in iOS Settings. Push won't be delivered until re-enabled there.")
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground)
            }
        }
    }

    private var tokenState: (text: String, color: Color) {
        if osDenied { return ("OS DENIED", Design.Colors.danger) }
        if tokenRegistered { return ("TOKEN REGISTERED", Design.Brand.accent) }
        return ("TOKEN NOT REGISTERED", Design.Colors.mutedForeground)
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
    private var tokenRegistered: Bool { sessionStore.state.pushTokenRegistered }

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
                    if let token = UserDefaults.standard.string(forKey: "hermes.apns.deviceToken") {
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
