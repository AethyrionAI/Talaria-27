import SwiftUI

/// Banner displayed in chat when a voice session's transcript is injected.
struct VoiceSessionBanner: View {
    var duration: TimeInterval?

    var body: some View {
        HStack(spacing: Design.Spacing.sm) {
            dashedLine
            bannerContent
            dashedLine
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
    }

    private var bannerContent: some View {
        HStack(spacing: Design.Spacing.xs) {
            StatusPip(color: Design.Brand.accent, diameter: 6)

            MonoLabel(
                "Voice Link Ended",
                size: 10,
                tracking: Design.Tracking.monoWide,
                color: Design.Colors.mutedForeground
            )

            if let duration {
                Text(formattedDuration(duration))
                    .font(Design.Typography.mono(10, relativeTo: .caption2).monospacedDigit())
                    .tracking(Design.Tracking.mono)
                    .foregroundStyle(Design.Brand.accent)
            }
        }
        .padding(.horizontal, Design.Spacing.sm)
        .padding(.vertical, Design.Spacing.xs)
        .hudPanel(
            cornerRadius: Design.CornerRadius.full,
            borderColor: Design.Colors.cyanHairline,
            fill: Design.Colors.surface
        )
    }

    private var dashedLine: some View {
        Rectangle()
            .fill(Design.Colors.cyanHairline)
            .frame(height: 1)
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
