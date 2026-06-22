import SwiftUI

struct StatusCardView: View {
    let connectionLabel: String
    let messageCount: Int
    let conversationID: UUID?
    let tokenUsage: TokenUsage?
    let dismissAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            HStack(spacing: Design.Spacing.sm) {
                // Cyan checkmark box
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Design.Brand.accent)
                    .frame(width: Design.Size.avatarSmall, height: Design.Size.avatarSmall)
                    .background(Design.Colors.accentTint(0.14), in: RoundedRectangle(cornerRadius: Design.CornerRadius.sm + 1))
                    .overlay {
                        RoundedRectangle(cornerRadius: Design.CornerRadius.sm + 1)
                            .strokeBorder(Design.Colors.accentTint(0.4), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: Design.Spacing.xxxs) {
                    Text("Session Status")
                        .font(Design.Typography.body(13, weight: .medium))
                        .foregroundStyle(Design.Colors.foregroundBright)
                    MonoLabel(
                        connectionLabel,
                        size: 10,
                        tracking: Design.Tracking.mono,
                        color: Design.Colors.mutedForeground
                    )
                }

                Spacer(minLength: 0)

                Button(action: dismissAction) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Design.Colors.mutedForeground)
                        .frame(width: Design.Size.minTapTarget, height: Design.Size.minTapTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Dismiss session status")
            }

            Rectangle()
                .fill(Design.Colors.accentTint(0.12))
                .frame(height: 1)

            statusRow("Connection", value: connectionLabel)
            statusRow("Messages", value: "\(messageCount)")
            if let id = conversationID {
                statusRow("Session", value: String(id.uuidString.prefix(8)))
            }

            if let usage = tokenUsage {
                Rectangle()
                    .fill(Design.Colors.accentTint(0.12))
                    .frame(height: 1)
                statusRow("Current Context", value: "\(usage.promptTokens) tokens")
                statusRow("Completion", value: "\(usage.completionTokens)")
                statusRow("Total", value: "\(usage.totalTokens)")
            }
        }
        .padding(Design.Spacing.md)
        .background(
            LinearGradient(
                colors: [Design.Colors.accentTint(0.1), Design.Colors.accentTint(0.03)],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: Design.CornerRadius.sm + 4)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Design.CornerRadius.sm + 4)
                .strokeBorder(Design.Colors.accentTint(0.25), lineWidth: 1)
        }
        .padding(.horizontal, Design.Spacing.md)
    }

    private func statusRow(_ label: String, value: String) -> some View {
        HStack {
            MonoLabel(
                label,
                size: 10,
                tracking: Design.Tracking.mono,
                color: Design.Colors.mutedForeground
            )
            Spacer()
            Text(value)
                .font(Design.Typography.mono(11, weight: .medium))
                .foregroundStyle(Design.Colors.coolForeground)
        }
    }
}
