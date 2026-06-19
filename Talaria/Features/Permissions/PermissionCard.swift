import SwiftUI

struct PermissionCard: View {
    let capability: DeviceCapability
    let onRequest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            headerRow
            explanationText
            statusAndAction
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Design.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.lg))
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: Design.Spacing.sm) {
            Image(systemName: capability.permissionType.displayIcon)
                .font(.system(size: Design.Size.iconMedium))
                .foregroundStyle(.white)
                .frame(width: Design.Size.avatarSmall, height: Design.Size.avatarSmall)
                .background(capability.permissionType.displayColor, in: .rect(cornerRadius: Design.CornerRadius.sm))

            Text(capability.permissionType.displayLabel)
                .font(Design.Typography.headline)
                .foregroundStyle(Design.Colors.foreground)

            Spacer()
        }
    }

    // MARK: - Explanation

    private var explanationText: some View {
        Text(capability.permissionType.explanation)
            .font(Design.Typography.callout)
            .foregroundStyle(Design.Colors.secondaryForeground)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Status & Action

    private var statusAndAction: some View {
        HStack {
            Label(statusLabelText, systemImage: statusIcon)
                .font(Design.Typography.footnote)
                .foregroundStyle(capability.status.displayColor)

            Spacer()

            if let actionLabel = actionLabelText {
                Button {
                    onRequest()
                } label: {
                    Text(actionLabel)
                        .font(Design.Typography.footnote.weight(.semibold))
                        .foregroundStyle(Design.Colors.foreground)
                        .padding(.horizontal, Design.Spacing.md)
                        .padding(.vertical, Design.Spacing.xs)
                }
                .background(Design.Brand.accent)
                .clipShape(Capsule())
            }
        }
    }

    private var statusLabelText: String {
        capability.statusDetail ?? capability.status.displayLabel
    }

    private var actionLabelText: String? {
        if capability.permissionType == .health,
           capability.status == .denied || capability.status == .restricted {
            return nil
        }
        return capability.status.actionLabel
    }

    private var statusIcon: String {
        switch capability.status {
        case .authorized, .authorizedWhenInUse, .authorizedAlways: "checkmark.circle.fill"
        case .limited: "exclamationmark.circle.fill"
        case .denied: "xmark.circle.fill"
        case .notDetermined: "questionmark.circle"
        case .restricted: "lock.fill"
        case .unsupported: "nosign"
        }
    }
}
