import SwiftUI

struct CaptureScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            ContentUnavailableView {
                Label("Capture", systemImage: "camera.viewfinder")
            } description: {
                Text("Camera and canvas features are coming soon. This screen is a placeholder for future Hermes visual capabilities.")
            } actions: {
                Button("Go Back") {
                    dismiss()
                }
                .buttonStyle(.glassProminent)
            }
        }
        .navigationTitle("Capture")
    }
}
