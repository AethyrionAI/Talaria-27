import SwiftUI
import UIKit

// MARK: - Privacy settings screen (Settings → PRIVACY, sub-screen 11)
//
// Permission readout + location sync preference. Mirrors
// design/Settings-Additional.dc.html page 11, real-data-only:
//   • Permission rows reflect the live PermissionsStore capability statuses.
//     A not-yet-determined permission prompts in-app; otherwise MANAGE deep-links
//     to iOS Settings.
//   • In-app revoke (#6): the app can't rescind an iOS grant, but it CAN
//     durably stop using it. The Revoke section halts HealthKit collection
//     (observers + background delivery), location monitoring, or the relay
//     push registration — persisted so a relaunch doesn't resurrect them.
//     Camera/Photos stay deep-link-only ("Manage in System Settings").
struct PrivacySettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AppContainer.self) private var container
    @Environment(PermissionsStore.self) private var permissionsStore
    @Environment(SettingsStore.self) private var settingsStore

    /// Permission whose revoke confirmation dialog is showing.
    @State private var pendingRevoke: RevocablePermission?

    private let shownPermissions: [PermissionType] = [.location, .health, .motion, .notifications, .microphone]

    /// The three grants Talaria can genuinely stop using in-app (#6).
    /// Camera/Photos are intentionally absent — deep-link-only.
    private enum RevocablePermission: String, Identifiable, CaseIterable {
        case health
        case location
        case notifications

        var id: String { rawValue }

        var displayLabel: String {
            switch self {
            case .health: "Health Collection"
            case .location: "Location Sync"
            case .notifications: "Push Notifications"
            }
        }

        var revokeEffect: String {
            switch self {
            case .health: "Stops health observers and background delivery, and drops queued samples."
            case .location: "Stops location monitoring and drops the queued fix. Sync resets to foreground-only."
            case .notifications: "Deactivates this device's push registration on the relay."
            }
        }
    }

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Design.Spacing.lg) {
                    SettingsScreenHeader(title: "Privacy", subtitle: "Permissions") { dismiss() }
                    permissionsSection
                    locationSection
                    revokeSection
                    manageSection
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)
            }
        }
        .navigationTitle("Privacy")
        .toolbarVisibility(.hidden, for: .navigationBar)
        .task { await permissionsStore.reloadCapabilities() }
    }

    // MARK: Permissions

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Permissions", size: 10, tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)

            VStack(spacing: 0) {
                let rows = permissionRows
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, cap in
                    permissionRow(cap)
                    if index < rows.count - 1 {
                        Rectangle()
                            .fill(Design.Colors.hairline)
                            .frame(height: 1)
                            .padding(.horizontal, Design.Spacing.md)
                    }
                }
            }
            .hudPanel(
                cornerRadius: Design.CornerRadius.lg,
                borderColor: Design.Colors.accentTint(0.12),
                fill: Design.Colors.background.opacity(0.5),
                innerGlow: false
            )
        }
    }

    private var permissionRows: [DeviceCapability] {
        shownPermissions.compactMap { type in
            permissionsStore.capabilities.first { $0.permissionType == type }
        }
    }

    private func permissionRow(_ cap: DeviceCapability) -> some View {
        Button {
            manage(cap)
        } label: {
            HStack(spacing: Design.Spacing.sm) {
                StatusPip(color: statusColor(cap.status), diameter: 7)
                Text(cap.permissionType.displayLabel)
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.foreground)
                Spacer(minLength: Design.Spacing.xs)
                MonoLabel(cap.status.displayLabel, size: 9, weight: .medium,
                          tracking: Design.Tracking.mono, color: statusColor(cap.status))
                    .lineLimit(1)
                MonoLabel(cap.status == .notDetermined ? "ENABLE ›" : "MANAGE ›",
                          size: 9, weight: .medium, tracking: Design.Tracking.mono,
                          color: Design.Colors.accentTint(0.7))
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func manage(_ cap: DeviceCapability) {
        if cap.status == .notDetermined {
            Task { await permissionsStore.requestPermission(for: cap.permissionType) }
        } else {
            openAppSettings()
        }
    }

    private func statusColor(_ status: PermissionStatus) -> Color {
        switch status {
        case .authorized, .authorizedWhenInUse, .authorizedAlways: Design.Brand.accent
        case .limited: Design.Brand.forge
        case .denied, .restricted: Design.Colors.danger
        case .notDetermined, .unsupported: Design.Colors.mutedForeground
        }
    }

    // MARK: Location

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Location", size: 10, tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)

            VStack(alignment: .leading, spacing: Design.Spacing.md) {
                HStack {
                    Text("Accuracy")
                        .font(Design.Typography.body(14, weight: .regular))
                        .foregroundStyle(Design.Colors.foreground)
                    Spacer()
                    MonoLabel(permissionsStore.locationAccuracyLevel.displayLabel, size: 10, weight: .medium,
                              tracking: Design.Tracking.mono, color: accuracyColor)
                }

                HStack(spacing: Design.Spacing.xxs) {
                    syncSegment("Foreground Only", pref: .foregroundOnly)
                    syncSegment("Background", pref: .backgroundAllowed)
                }
                .padding(Design.Spacing.xxs)
                .background(Design.Colors.background.opacity(0.5),
                            in: RoundedRectangle(cornerRadius: Design.CornerRadius.md))
                .overlay {
                    RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                        .strokeBorder(Design.Colors.hairline, lineWidth: 1)
                }
            }
            .padding(Design.Spacing.md)
            .hudPanel(
                cornerRadius: Design.CornerRadius.lg,
                borderColor: Design.Colors.accentTint(0.12),
                fill: Design.Colors.background.opacity(0.5),
                innerGlow: false
            )
        }
    }

    private var accuracyColor: Color {
        switch permissionsStore.locationAccuracyLevel {
        case .full: Design.Brand.accent
        case .reduced: Design.Brand.forge
        case .unknown: Design.Colors.mutedForeground
        }
    }

    private func syncSegment(_ label: String, pref: LocationSyncPreference) -> some View {
        let active = settingsStore.settings.locationSyncPreference == pref
        return Button {
            selectSync(pref)
        } label: {
            Text(label.uppercased())
                .font(Design.Typography.display(10, weight: .semibold, relativeTo: .caption2))
                .tracking(Design.Tracking.button)
                .foregroundStyle(active ? Design.Colors.background : Design.Colors.secondaryForeground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Design.Spacing.sm)
                .background(active ? Design.Brand.accent : Color.clear,
                            in: RoundedRectangle(cornerRadius: Design.CornerRadius.sm))
        }
        .buttonStyle(.plain)
    }

    private func selectSync(_ pref: LocationSyncPreference) {
        settingsStore.settings.locationSyncPreference = pref
        permissionsStore.updateLocationSyncPreference(pref)
        guard pref == .backgroundAllowed else { return }
        Task {
            switch permissionsStore.locationAuthorizationLevel {
            case .denied, .restricted:
                permissionsStore.openLocationSystemSettings()
            case .always, .whenInUse, .notDetermined:
                await permissionsStore.requestBackgroundLocationAccess()
            }
        }
    }

    // MARK: Revoke (#6)

    private var revokeSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Revoke / Reset", size: 10, tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)

            VStack(spacing: 0) {
                let all = RevocablePermission.allCases
                ForEach(Array(all.enumerated()), id: \.element.id) { index, permission in
                    revokeRow(permission)
                    if index < all.count - 1 {
                        Rectangle()
                            .fill(Design.Colors.hairline)
                            .frame(height: 1)
                            .padding(.horizontal, Design.Spacing.md)
                    }
                }
            }
            .hudPanel(
                cornerRadius: Design.CornerRadius.lg,
                borderColor: Design.Colors.accentTint(0.12),
                fill: Design.Colors.background.opacity(0.5),
                innerGlow: false
            )

            Text("Revoking stops Talaria's use of the grant — it does not change the iOS grant itself. Camera and Photos can only be managed in System Settings.")
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.secondaryForeground)
                .padding(.horizontal, Design.Spacing.xxs)
        }
        .confirmationDialog(
            "Revoke \(pendingRevoke?.displayLabel ?? "")?",
            isPresented: Binding(
                get: { pendingRevoke != nil },
                set: { if !$0 { pendingRevoke = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingRevoke
        ) { permission in
            Button("Revoke", role: .destructive) {
                revoke(permission)
            }
            Button("Cancel", role: .cancel) {}
        } message: { permission in
            Text(permission.revokeEffect)
        }
    }

    private func revokeRow(_ permission: RevocablePermission) -> some View {
        let active = isCollectionActive(permission)
        return HStack(spacing: Design.Spacing.sm) {
            StatusPip(color: active ? Design.Brand.accent : Design.Colors.mutedForeground, diameter: 7)
            Text(permission.displayLabel)
                .font(Design.Typography.callout)
                .foregroundStyle(Design.Colors.foreground)
            Spacer(minLength: Design.Spacing.xs)
            MonoLabel(active ? "ACTIVE" : "OFF", size: 9, weight: .medium,
                      tracking: Design.Tracking.mono,
                      color: active ? Design.Brand.accent : Design.Colors.mutedForeground)
            Button {
                if active {
                    pendingRevoke = permission
                } else {
                    reenable(permission)
                }
            } label: {
                MonoLabel(active ? "REVOKE ✕" : "ENABLE ›", size: 9, weight: .medium,
                          tracking: Design.Tracking.mono,
                          color: active ? Design.Colors.danger : Design.Colors.accentTint(0.7))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
    }

    private func isCollectionActive(_ permission: RevocablePermission) -> Bool {
        switch permission {
        case .health: settingsStore.settings.healthCollectionEnabled
        case .location: settingsStore.settings.locationCollectionEnabled
        case .notifications: settingsStore.settings.notificationsEnabled
        }
    }

    private func revoke(_ permission: RevocablePermission) {
        pendingRevoke = nil
        Task {
            switch permission {
            case .health: await container.setHealthCollectionEnabled(false)
            case .location: await container.setLocationCollectionEnabled(false)
            case .notifications: await container.setNotificationsEnabled(false)
            }
        }
    }

    private func reenable(_ permission: RevocablePermission) {
        Task {
            switch permission {
            case .health: await container.setHealthCollectionEnabled(true)
            case .location: await container.setLocationCollectionEnabled(true)
            case .notifications: await container.setNotificationsEnabled(true)
            }
        }
    }

    // MARK: Manage

    private var manageSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            Button {
                openAppSettings()
            } label: {
                HStack(spacing: Design.Spacing.sm) {
                    Text("Manage in System Settings")
                        .font(Design.Typography.callout)
                        .foregroundStyle(Design.Colors.foreground)
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Design.Colors.accentTint(0.8))
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .hudPanel(
                    cornerRadius: Design.CornerRadius.md,
                    borderColor: Design.Colors.accentTint(0.2),
                    fill: Design.Colors.accentTint(0.06),
                    innerGlow: false
                )
            }
            .buttonStyle(.plain)

            Text("Opens iOS Settings, where you can review or change Talaria's permissions. The app can't change OS grants directly.")
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.secondaryForeground)
                .padding(.horizontal, Design.Spacing.xxs)
        }
    }

    // MARK: Helpers

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}
