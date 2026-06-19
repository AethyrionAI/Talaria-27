import SwiftUI

struct StatusCardView: View {
    let connectionLabel: String
    let messageCount: Int
    let conversationID: UUID?
    let tokenUsage: TokenUsage?
    let dismissAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(Design.Brand.accent)
                Text("Session Status")
                    .font(Design.Typography.headline)
                    .foregroundStyle(Design.Colors.foreground)
                Spacer()
                Button(action: dismissAction) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Design.Colors.secondaryForeground)
                }
            }

            Divider()
                .overlay(Design.Colors.divider)

            statusRow("Connection", value: connectionLabel)
            statusRow("Messages", value: "\(messageCount)")
            if let id = conversationID {
                statusRow("Session", value: String(id.uuidString.prefix(8)))
            }

            if let usage = tokenUsage {
                Divider()
                    .overlay(Design.Colors.divider)
                statusRow("Current Context", value: "\(usage.promptTokens) tokens")
                statusRow("Completion", value: "\(usage.completionTokens)")
                statusRow("Total", value: "\(usage.totalTokens)")
            }
        }
        .padding(Design.Spacing.md)
        .background(Design.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.lg))
        .padding(.horizontal, Design.Spacing.md)
    }

    private func statusRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(Design.Typography.callout)
                .foregroundStyle(Design.Colors.secondaryForeground)
            Spacer()
            Text(value)
                .font(Design.Typography.callout)
                .foregroundStyle(Design.Colors.foreground)
        }
    }
}
