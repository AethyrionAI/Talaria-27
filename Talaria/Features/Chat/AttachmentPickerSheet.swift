import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Bottom sheet for adding attachments to the chat — camera, photo library, or files.
struct AttachmentPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PermissionsStore.self) private var permissionsStore

    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var showFilePicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []

    /// Called with the user-friendly description of what was picked (for chat input).
    var onAttachmentPicked: ((AttachmentResult) -> Void)?

    var body: some View {
        VStack(spacing: Design.Spacing.md) {
            // Drag indicator area
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Design.Colors.secondaryForeground.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, Design.Spacing.sm)

            // Header
            Text("Add to Chat")
                .font(Design.Typography.headline)
                .foregroundStyle(Design.Colors.foreground)

            // Attachment options
            HStack(spacing: Design.Spacing.sm) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    attachmentButton(
                        icon: "camera",
                        label: "Camera",
                        action: { showCamera = true }
                    )
                }

                attachmentButton(
                    icon: "photo.on.rectangle",
                    label: "Photos",
                    action: { showPhotoPicker = true }
                )

                attachmentButton(
                    icon: "doc",
                    label: "Files",
                    action: { showFilePicker = true }
                )
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.bottom, Design.Spacing.md)
        }
        .background(Design.Colors.background)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPickerView { image in
                if let image {
                    onAttachmentPicked?(.image(image))
                }
                dismiss()
            }
            .ignoresSafeArea()
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhotoItems,
            maxSelectionCount: 1,
            matching: .images
        )
        .onChange(of: selectedPhotoItems) { _, items in
            guard let item = items.first else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    onAttachmentPicked?(.image(image))
                }
                selectedPhotoItems = []
                dismiss()
            }
        }
        .sheet(isPresented: $showFilePicker) {
            DocumentPickerView { urls in
                if let url = urls.first {
                    onAttachmentPicked?(.file(url))
                }
                dismiss()
            }
        }
    }

    private func attachmentButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Design.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: Design.Size.iconLarge))
                    .foregroundStyle(Design.Colors.foreground)
                Text(label)
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.foreground)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(Design.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.md))
        }
    }
}

// MARK: - Attachment Result

enum AttachmentResult {
    case image(UIImage)
    case file(URL)
}

// MARK: - Camera Picker (UIImagePickerController wrapper)

struct CameraPickerView: UIViewControllerRepresentable {
    let onComplete: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onComplete: (UIImage?) -> Void

        init(onComplete: @escaping (UIImage?) -> Void) {
            self.onComplete = onComplete
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            onComplete(image)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onComplete(nil)
        }
    }
}

// MARK: - Document Picker (UIDocumentPickerViewController wrapper)

struct DocumentPickerView: UIViewControllerRepresentable {
    let onComplete: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [
            .image, .plainText, .sourceCode, .json, .html, .xml, .yaml,
        ], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onComplete: ([URL]) -> Void

        init(onComplete: @escaping ([URL]) -> Void) {
            self.onComplete = onComplete
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onComplete(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onComplete([])
        }
    }
}
