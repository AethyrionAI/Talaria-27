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
        ZStack {
            HUDScreenBackground(gridIntensity: 0.3)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Drag indicator
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(Design.Colors.accentTint(0.4))
                    .frame(width: 36, height: 5)
                    .padding(.top, Design.Spacing.sm)

                MonoLabel("ADD VISUAL INPUT", tracking: Design.Tracking.monoWide)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Design.Spacing.lg)
                    .padding(.top, Design.Spacing.md)

                VStack(spacing: Design.Spacing.sm) {
                    // Camera button
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            onCameraRequested()
                            dismiss()
                        } label: {
                            AttachmentRow(title: "Live Camera", systemImage: "video.fill")
                        }
                        .buttonStyle(.plain)
                    }

                    // Photo library picker
                    PhotosPicker(
                        selection: $selectedPhoto,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        AttachmentRow(title: "Photo Library", systemImage: "photo.on.rectangle")
                    }
                }
                .padding(.horizontal, Design.Spacing.lg)
                .padding(.vertical, Design.Spacing.md)
            }
        }
        .presentationBackground(Design.Colors.background)
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

    /// HUD attachment row: cyan glyph + label on a panelled chip.
    private struct AttachmentRow: View {
        let title: String
        let systemImage: String

        var body: some View {
        HStack(spacing: Design.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: Design.Size.iconSmall, weight: .medium))
                .foregroundStyle(Design.Brand.accent)
                .frame(width: Design.Size.iconLarge)
            Text(title)
                .font(Design.Typography.body)
                .foregroundStyle(Design.Colors.coolForeground)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Design.Colors.accentTint(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: Design.Size.minTapTarget)
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
        .hudPanel(cornerRadius: Design.CornerRadius.md)
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
