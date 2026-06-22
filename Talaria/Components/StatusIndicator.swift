import SwiftUI

struct StatusIndicator: View {
    let status: ConnectionStatus

    var body: some View {
        HStack(spacing: Design.Spacing.xs) {
            StatusPip(
                color: status.displayColor,
                diameter: 7,
                blinks: status == .connecting
            )

            MonoLabel(
                status.displayLabel,
                size: 10,
                weight: .medium,
                tracking: Design.Tracking.mono,
                color: Design.Colors.coolForeground
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Connection status: \(status.displayLabel)")
    }
}
