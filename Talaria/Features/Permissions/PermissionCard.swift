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
        .hudPanel(
            cornerRadius: Design.CornerRadius.lg,
            borderColor: Design.Colors.cyanHairline,
            fill: Design.Colors.surface
        )
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: Design.Spacing.sm) {
            Image(systemName: capability.permissionType.displayIcon)
                .font(.system(size: Design.Size.iconSmall, weight: .medium))
                .foregroundStyle(Design.Brand.accentBright)
                .frame(width: Design.Size.avatarSmall, height: Design.Size.avatarSmall)
                .background(Design.Colors.accentTint(0.10), in: RoundedRectangle(cornerRadius: Design.CornerRadius.sm))
                .overlay {
                    RoundedRectangle(cornerRadius: Design.CornerRadius.sm)
                        .strokeBorder(Design.Colors.cyanBorder, lineWidth: 1)
                }

            Text(capability.permissionType.displayLabel)
                .font(Design.Typography.headline)
                .foregroundStyle(Design.Colors.foregroundBright)

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
            HStack(spacing: Design.Spacing.xs) {
                Image(systemName: statusIcon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(capability.status.displayColor)
                MonoLabel(
                    statusLabelText,
                    size: 10,
                    weight: .medium,
                    tracking: Design.Tracking.mono,
                    color: capability.status.displayColor
                )
            }

            Spacer()

            if let actionLabel = actionLabelText {
                Button {
                    onRequest()
                } label: {
                    Text(actionLabel.uppercased())
                        .font(Design.Typography.mono(11, weight: .medium))
                        .tracking(Design.Tracking.mono)
                        .foregroundStyle(Design.Colors.foregroundBright)
                        .padding(.horizontal, Design.Spacing.md)
                        .frame(minHeight: Design.Size.minTapTarget)
                        .background(
                            LinearGradient(
                                colors: [Design.Colors.accentTint(0.24), Design.Colors.accentTint(0.08)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            in: Capsule()
                        )
                        .overlay {
                            Capsule().strokeBorder(Design.Colors.accentTint(0.6), lineWidth: 1)
                        }
                        .hudGlow(Design.Brand.accent, radius: 14, strength: 0.3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(actionLabel) \(capability.permissionType.displayLabel)")
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
