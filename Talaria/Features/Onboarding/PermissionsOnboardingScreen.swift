import SwiftUI

struct PermissionsOnboardingScreen: View {
    @Environment(PairingStore.self) private var pairingStore
    @Environment(PermissionsStore.self) private var permissionsStore

    var body: some View {
        ZStack {
            Design.Colors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Design.Spacing.lg) {
                        headerSection
                        permissionsList
                    }
                    .padding(.horizontal, Design.Spacing.md)
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
            Text("Permissions")
                .font(Design.Typography.heroTitle)
                .foregroundStyle(Design.Colors.foreground)

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
                .foregroundStyle(.white)
                .frame(width: Design.Size.avatarSmall, height: Design.Size.avatarSmall)
                .background(capability.permissionType.displayColor, in: .rect(cornerRadius: Design.CornerRadius.md))

            VStack(alignment: .leading, spacing: Design.Spacing.xxxs) {
                Text(capability.permissionType.displayLabel)
                    .font(Design.Typography.headline)
                    .foregroundStyle(Design.Colors.foreground)

                Text(capability.permissionType.explanation)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground)
                    .lineLimit(2)

                if capability.status.isGranted {
                    Text("Granted")
                        .font(Design.Typography.caption)
                        .foregroundStyle(.green)
                }
            }

            Spacer()

            permissionAction(for: capability)
        }
        .padding(Design.Spacing.md)
        .background(Design.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.lg))
    }

    @ViewBuilder
    private func permissionAction(for capability: DeviceCapability) -> some View {
        switch capability.status {
        case .notDetermined:
            Button {
                Task { await permissionsStore.requestPermission(for: capability.permissionType) }
            } label: {
                Text("Enable")
                    .font(Design.Typography.footnote.weight(.semibold))
                    .foregroundStyle(Design.Colors.foreground)
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.vertical, Design.Spacing.xs)
            }
            .background(Design.Brand.accent)
            .clipShape(Capsule())

        case .authorized, .authorizedWhenInUse, .authorizedAlways:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.green)

        case .denied:
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Settings")
                    .font(Design.Typography.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }

        case .limited, .restricted, .unsupported:
            Image(systemName: "minus.circle")
                .font(.system(size: 22))
                .foregroundStyle(Design.Colors.secondaryForeground)
        }
    }

    // MARK: - Continue Button

    private var continueButton: some View {
        Button {
            pairingStore.completePermissionsOnboarding()
        } label: {
            Text("Continue")
                .font(Design.Typography.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Design.Spacing.sm)
        }
        .background(Design.Brand.accent)
        .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.lg))
        .padding(.horizontal, Design.Spacing.md)
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
