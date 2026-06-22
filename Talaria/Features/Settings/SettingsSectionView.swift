import SwiftUI

struct SettingsSectionView<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel(
                title,
                size: 10,
                weight: .medium,
                tracking: Design.Tracking.monoWide,
                color: Design.Colors.mutedForeground
            )
            .padding(.leading, Design.Spacing.xxs)

            VStack(spacing: 0) {
                content
            }
            .padding(Design.Spacing.md)
            .frame(maxWidth: .infinity)
            .hudPanel(
                cornerRadius: Design.CornerRadius.lg,
                borderColor: Design.Colors.cyanHairline,
                fill: Design.Colors.surface
            )
        }
    }
}
