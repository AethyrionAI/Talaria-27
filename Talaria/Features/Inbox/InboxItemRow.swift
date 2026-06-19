import SwiftUI

struct InboxItemRow: View {
    let item: InboxItem
    let onPrimaryAction: () -> Void
    let onSecondaryAction: () -> Void
    let onOpenDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            headerRow

            Text(item.body)
                .font(Design.Typography.callout)
                .foregroundStyle(Design.Colors.secondaryForeground)
                .lineLimit(3)

            if item.isActionable && !item.isRead {
                actionButtons
            }
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Design.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.lg))
        .opacity(item.isRead ? 0.7 : 1.0)
        .onTapGesture(perform: onOpenDetails)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: Design.Spacing.sm) {
            Image(systemName: item.type.displayIcon)
                .font(.system(size: Design.Size.iconMedium))
                .foregroundStyle(item.type.displayColor)
                .frame(width: Design.Size.avatarSmall, height: Design.Size.avatarSmall)
                .background(Design.Colors.surface)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: Design.Spacing.xxxs) {
                Text(item.title)
                    .font(Design.Typography.headline)
                    .foregroundStyle(Design.Colors.foreground)

                Text(item.timestamp, style: .relative)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground.opacity(0.6))
            }

            Spacer()

            Text(item.priority.rawValue.capitalized)
                .font(Design.Typography.caption2.weight(.semibold))
                .foregroundStyle(Design.Colors.secondaryForeground)

            if !item.isRead {
                Circle()
                    .fill(item.type.displayColor)
                    .frame(width: Design.Spacing.xs, height: Design.Spacing.xs)
                    .accessibilityLabel("Unread")
            }
        }
    }

    // MARK: - Actions

    private var actionButtons: some View {
        HStack(spacing: Design.Spacing.sm) {
            Button {
                onPrimaryAction()
            } label: {
                Text(item.primaryAction?.title ?? defaultPrimaryActionTitle)
                    .font(Design.Typography.footnote.weight(.semibold))
                    .foregroundStyle(Design.Colors.foreground)
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.vertical, Design.Spacing.xs)
            }
            .background(Design.Brand.accent)
            .clipShape(Capsule())
            .accessibilityLabel("\(item.primaryAction?.title ?? defaultPrimaryActionTitle) \(item.title)")

            Button {
                onSecondaryAction()
            } label: {
                Text(item.secondaryAction?.title ?? "Dismiss")
                    .font(Design.Typography.footnote.weight(.medium))
                    .foregroundStyle(Design.Colors.secondaryForeground)
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.vertical, Design.Spacing.xs)
            }
            .background(Design.Colors.surface)
            .clipShape(Capsule())
            .accessibilityLabel("Dismiss \(item.title)")
        }
    }

    private var defaultPrimaryActionTitle: String {
        item.type == .approval ? "Approve" : "Open"
    }
}
