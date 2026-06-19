import PhotosUI
import SwiftUI

/// Bottom sheet for adding visual input during a voice session.
/// Offers photo library and live camera options.
struct VoiceAttachmentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onPhotoPicked: (Data) -> Void
    let onCameraRequested: () -> Void

    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Design.Colors.secondaryForeground.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, Design.Spacing.sm)

            VStack(spacing: Design.Spacing.xs) {
                // Camera button
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        onCameraRequested()
                        dismiss()
                    } label: {
                        Label("Live Camera", systemImage: "video.fill")
                            .font(Design.Typography.body)
                            .foregroundStyle(Design.Colors.foreground)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Design.Spacing.md)
                            .background(Design.Colors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.md))
                    }
                }

                // Photo library picker
                PhotosPicker(
                    selection: $selectedPhoto,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label("Photo Library", systemImage: "photo.on.rectangle")
                        .font(Design.Typography.body)
                        .foregroundStyle(Design.Colors.foreground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Design.Spacing.md)
                        .background(Design.Colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.md))
                }
            }
            .padding(.horizontal, Design.Spacing.lg)
            .padding(.vertical, Design.Spacing.md)
        }
        .background(Design.Colors.background)
        .onChange(of: selectedPhoto) {
            guard let selectedPhoto else { return }
            Task {
                if let data = try? await selectedPhoto.loadTransferable(type: Data.self) {
                    let compressed = Self.compressForVoice(data)
                    onPhotoPicked(compressed)
                }
                self.selectedPhoto = nil
                dismiss()
            }
        }
    }

    /// Downscale to 512px longest side and compress for WebRTC data channel.
    private static func compressForVoice(_ data: Data) -> Data {
        guard let image = UIImage(data: data) else { return data }

        let maxDimension: CGFloat = 512
        let scale = min(maxDimension / max(image.size.width, image.size.height), 1.0)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        return resized.jpegData(compressionQuality: 0.6) ?? data
    }
}
