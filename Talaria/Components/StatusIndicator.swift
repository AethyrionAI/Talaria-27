import SwiftUI

struct StatusIndicator: View {
    let status: ConnectionStatus

    var body: some View {
        HStack(spacing: Design.Spacing.xxs) {
            Circle()
                .fill(status.displayColor)
                .frame(width: Design.Spacing.xs, height: Design.Spacing.xs)

            Text(status.displayLabel)
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.secondaryForeground)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Connection status: \(status.displayLabel)")
    }
}
