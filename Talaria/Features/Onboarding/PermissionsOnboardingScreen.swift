import SwiftUI

struct PermissionsOnboardingScreen: View {
    @Environment(PairingStore.self) private var pairingStore
    @Environment(PermissionsStore.self) private var permissionsStore

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            CornerBrackets(arm: Design.Size.bracket, lineWidth: 1.5, inset: Design.Spacing.md)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Design.Spacing.lg) {
                        headerSection
                        permissionsList
                    }
                    .padding(.horizontal, Design.Spacing.lg)
                    .padding(.vertical, Design.Spacing.lg)
                }

                continueButton
            }
        }
        .task {
            await permissionsStore.reloadCapabilities()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("DEVICE ACCESS", tracking: Design.Tracking.monoXWide,
                      color: Design.Brand.accent)

            Text("PERMISSIONS")
                .font(Design.Typography.display(26, weight: .bold, relativeTo: .title))
                .tracking(Design.Tracking.display)
                .foregroundStyle(Design.Colors.foregroundBright)

            Text("Enable only what you need. You can change these anytime in Settings.")
                .font(Design.Typography.body)
                .foregroundStyle(Design.Colors.secondaryForeground)
        }
    }

    // MARK: - Permissions List

    private var permissionsList: some View {
        VStack(spacing: Design.Spacing.sm) {
            ForEach(onboardingCapabilities) { capability in
                permissionRow(capability)
            }
        }
    }

    private var onboardingCapabilities: [DeviceCapability] {
        permissionsStore.capabilities.filter { capability in
            PermissionType.onboardingPermissions.contains(capability.permissionType)
        }
    }

    private func permissionRow(_ capability: DeviceCapability) -> some View {
        HStack(spacing: Design.Spacing.md) {
            Image(systemName: capability.permissionType.displayIcon)
                .font(.system(size: Design.Size.iconMedium))
                .foregroundStyle(Design.Brand.accentBright)
                .frame(width: Design.Size.avatarSmall, height: Design.Size.avatarSmall)
                .background(
                    Design.Colors.accentTint(0.10),
                    in: RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                        .strokeBorder(Design.Colors.strongBorder, lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: Design.Spacing.xxxs) {
                Text(capability.permissionType.displayLabel)
                    .font(Design.Typography.headline)
                    .foregroundStyle(Design.Colors.foreground)

                Text(capability.permissionType.explanation)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground)
                    .lineLimit(2)

                if capability.status.isGranted {
                    HStack(spacing: Design.Spacing.xs) {
                        StatusPip(color: Design.Brand.accent, diameter: 6)
                        MonoLabel("GRANTED", tracking: Design.Tracking.mono,
                                  color: Design.Brand.accent)
                    }
                }
            }

            Spacer()

            permissionAction(for: capability)
        }
        .padding(Design.Spacing.md)
        .hudPanel(cornerRadius: Design.CornerRadius.lg)
    }

    @ViewBuilder
    private func permissionAction(for capability: DeviceCapability) -> some View {
        switch capability.status {
        case .notDetermined:
            Button {
                Task { await permissionsStore.requestPermission(for: capability.permissionType) }
            } label: {
                Text("ENABLE")
                    .font(Design.Typography.mono(11, weight: .medium))
                    .tracking(Design.Tracking.monoWide)
                    .foregroundStyle(Design.Colors.foregroundBright)
                    .padding(.horizontal, Design.Spacing.md)
                    .frame(minHeight: Design.Size.minTapTarget)
            }
            .background(
                Design.Colors.accentTint(0.12),
                in: Capsule()
            )
            .overlay {
                Capsule().strokeBorder(Design.Colors.accentTint(0.6), lineWidth: 1)
            }
            .accessibilityLabel("Enable \(capability.permissionType.displayLabel)")

        case .authorized, .authorizedWhenInUse, .authorizedAlways:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Design.Brand.accent)
                .frame(width: Design.Size.minTapTarget, height: Design.Size.minTapTarget)
                .accessibilityLabel("Granted")

        case .denied:
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("SETTINGS")
                    .font(Design.Typography.mono(10, weight: .medium))
                    .tracking(Design.Tracking.monoWide)
                    .foregroundStyle(Design.Brand.forge)
                    .frame(minHeight: Design.Size.minTapTarget)
            }
            .accessibilityLabel("Open Settings for \(capability.permissionType.displayLabel)")

        case .limited, .restricted, .unsupported:
            Image(systemName: "minus.circle")
                .font(.system(size: 22))
                .foregroundStyle(Design.Colors.mutedForeground)
                .frame(width: Design.Size.minTapTarget, height: Design.Size.minTapTarget)
                .accessibilityLabel("Unavailable")
        }
    }

    // MARK: - Continue Button

    private var continueButton: some View {
        GlowButton(title: "Continue") {
            pairingStore.completePermissionsOnboarding()
        }
        .padding(.horizontal, Design.Spacing.lg)
        .padding(.bottom, Design.Spacing.xl)
    }
}

// MARK: - PermissionStatus Helper

private extension PermissionStatus {
    var isGranted: Bool {
        switch self {
        case .authorized, .authorizedWhenInUse, .authorizedAlways: true
        default: false
        }
    }
}
