import SwiftUI

struct InboxItemRow: View {
    let item: InboxItem
    let onPrimaryAction: () -> Void
    let onSecondaryAction: () -> Void
    let onOpenDetails: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Left vertical priority accent bar.
            RoundedRectangle(cornerRadius: 1.5)
                .fill(priorityColor)
                .frame(width: 3)
                .hudGlow(priorityColor, radius: 8, strength: 0.7)
                .padding(.vertical, Design.Spacing.xs)

            VStack(alignment: .leading, spacing: Design.Spacing.sm) {
                badgeRow
                titleBlock

                if item.isActionable && !item.isRead {
                    actionButtons
                }
            }
            .padding(.vertical, Design.Spacing.md)
            .padding(.leading, Design.Spacing.md)
            .padding(.trailing, Design.Spacing.md)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPanel(
            cornerRadius: Design.CornerRadius.lg,
            borderColor: priorityColor.opacity(0.35),
            fill: Design.Colors.surface
        )
        .opacity(item.isRead ? 0.7 : 1.0)
        .contentShape(RoundedRectangle(cornerRadius: Design.CornerRadius.lg))
        .onTapGesture(perform: onOpenDetails)
    }

    // MARK: - Badge row (priority/category pill + timestamp + unread pip)

    private var badgeRow: some View {
        HStack(spacing: Design.Spacing.xs) {
            badgePill

            Spacer(minLength: Design.Spacing.xs)

            Text(item.timestamp, style: .relative)
                .font(Design.Typography.mono(10, weight: .regular))
                .tracking(Design.Tracking.mono)
                .foregroundStyle(Design.Colors.mutedForeground)

            if !item.isRead {
                StatusPip(color: priorityColor, diameter: 6, blinks: priority == .urgent)
                    .accessibilityLabel("Unread")
            }
        }
    }

    private var badgePill: some View {
        Text(badgeText)
            .font(Design.Typography.mono(9, weight: .medium))
            .tracking(Design.Tracking.mono)
            .foregroundStyle(priorityColor)
            .padding(.horizontal, Design.Spacing.xs)
            .padding(.vertical, 3)
            .background(priorityColor.opacity(0.12), in: RoundedRectangle(cornerRadius: Design.CornerRadius.xs))
            .overlay {
                RoundedRectangle(cornerRadius: Design.CornerRadius.xs)
                    .strokeBorder(priorityColor.opacity(0.4), lineWidth: 1)
            }
    }

    private var badgeText: String {
        "\(item.type.displayLabel.uppercased()) · \(priorityLabel)"
    }

    // MARK: - Title / preview

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
            Text(item.title)
                .font(Design.Typography.headline)
                .foregroundStyle(Design.Colors.foregroundBright)
                .lineLimit(2)

            Text(item.body)
                .font(Design.Typography.callout)
                .foregroundStyle(Design.Colors.secondaryForeground)
                .lineLimit(3)
        }
    }

    // MARK: - Actions

    private var actionButtons: some View {
        HStack(spacing: Design.Spacing.sm) {
            Button {
                onPrimaryAction()
            } label: {
                HStack(spacing: Design.Spacing.xs) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                    Text(primaryTitle)
                        .font(Design.Typography.body(13, weight: .medium))
                }
                .foregroundStyle(Design.Colors.foregroundBright)
                .frame(maxWidth: .infinity)
                .frame(height: Design.Size.minTapTarget)
                .background(
                    LinearGradient(
                        colors: [Design.Colors.accentTint(0.26), Design.Colors.accentTint(0.10)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    in: RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                        .strokeBorder(Design.Colors.accentTint(0.6), lineWidth: 1)
                }
                .hudGlow(Design.Brand.accent, radius: 16, strength: 0.3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(primaryTitle) \(item.title)")

            Button {
                onSecondaryAction()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Design.Colors.secondaryForeground)
                    .frame(width: 46, height: Design.Size.minTapTarget)
                    .background(Design.Colors.chipSurface, in: RoundedRectangle(cornerRadius: Design.CornerRadius.md))
                    .overlay {
                        RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                            .strokeBorder(Design.Colors.chipBorder, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(secondaryTitle) \(item.title)")
        }
    }

    // MARK: - Derived values

    private var primaryTitle: String {
        item.primaryAction?.title ?? (item.type == .approval ? "Approve" : "Open")
    }

    private var secondaryTitle: String {
        item.secondaryAction?.title ?? "Dismiss"
    }

    private var priority: InboxItemPriority { item.priority }

    /// Map the item's priority to a HUD accent colour.
    /// high/urgent → danger (red), normal → forge (amber), low → accent (cyan).
    private var priorityColor: Color {
        switch priority {
        case .high, .urgent: Design.Colors.danger
        case .normal: Design.Brand.forge
        case .low: Design.Brand.accent
        }
    }

    private var priorityLabel: String {
        switch priority {
        case .high: "HIGH"
        case .urgent: "URGENT"
        case .normal: "MED"
        case .low: "LOW"
        }
    }
}
