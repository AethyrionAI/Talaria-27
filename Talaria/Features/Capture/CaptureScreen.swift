import SwiftUI

struct CaptureScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()
            CornerBrackets(color: Design.Colors.accentTint(0.4))
                .padding(Design.Spacing.md)

            VStack(spacing: Design.Spacing.lg) {
                ReactorOrb(size: Design.Size.orbOnboarding, style: .standard)
                VStack(spacing: Design.Spacing.xs) {
                    Text("VISUAL LINK")
                        .font(Design.Typography.display(22, weight: .semibold, relativeTo: .title2))
                        .tracking(Design.Tracking.display)
                        .foregroundStyle(Design.Colors.foregroundBright)
                    MonoLabel("CAMERA · CANVAS · STANDBY", size: 10, tracking: Design.Tracking.monoWide)
                }
                Text("Camera and canvas features are coming soon — a placeholder for future Hermes visual capabilities.")
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.secondaryForeground)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Design.Spacing.xl)

                GlowButton(title: "Go Back", systemImage: "chevron.left", height: 50) {
                    dismiss()
                }
                .padding(.horizontal, Design.Spacing.xxl)
            }
        }
        .navigationTitle("Capture")
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}
