import SwiftUI

struct CaptureScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Design.Colors.background
                .ignoresSafeArea()

            ContentUnavailableView {
                Label("Capture", systemImage: "camera.viewfinder")
                    .foregroundStyle(Design.Colors.foreground)
            } description: {
                Text("Camera and canvas features are coming soon. This screen is a placeholder for future Hermes visual capabilities.")
                    .foregroundStyle(Design.Colors.secondaryForeground)
            } actions: {
                Button("Go Back") {
                    dismiss()
                }
                .font(Design.Typography.headline)
                .foregroundStyle(Design.Colors.foreground)
                .padding(.horizontal, Design.Spacing.lg)
                .padding(.vertical, Design.Spacing.sm)
                .background(Design.Brand.accent)
                .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.lg))
            }
        }
        .navigationTitle("Capture")
    }
}
