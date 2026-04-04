import Foundation
import UIKit

/// An attachment staged in the composer before sending.
struct PendingAttachment: Identifiable, Sendable {
    let id = UUID()
    let kind: Kind
    let fileName: String
    let mimeType: String
    let data: Data
    let localStoragePath: String?
    /// Thumbnail for display — stored separately since UIImage isn't Sendable.
    let thumbnailData: Data?

    enum Kind: String, Sendable {
        case image
        case file
    }

    /// Maximum file size: 5 MB (before base64 encoding).
    static let maxFileSize = 5 * 1024 * 1024
    static let maxAttachmentsPerMessage = 4

    private static let supportedTextMimeTypes: Set<String> = [
        "text/plain",
        "text/csv",
        "text/markdown",
        "text/html",
        "text/xml",
        "text/x-python",
        "text/x-swift",
        "text/javascript",
        "application/json",
        "application/xml",
        "application/yaml",
        "application/x-yaml",
    ]

    static func supportsMimeType(_ mimeType: String) -> Bool {
        mimeType.hasPrefix("image/") || supportedTextMimeTypes.contains(mimeType)
    }

    /// Create an image attachment from a UIImage.
    /// Large images are automatically downscaled to stay within the size limit.
    static func image(_ image: UIImage, fileName: String? = nil) -> PendingAttachment? {
        var quality: CGFloat = 0.8
        var targetImage = image

        // Downscale very large images (> 4096px on any side)
        let maxDimension: CGFloat = 4096
        if max(image.size.width, image.size.height) > maxDimension {
            let scale = maxDimension / max(image.size.width, image.size.height)
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            targetImage = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        }

        guard var jpegData = targetImage.jpegData(compressionQuality: quality) else { return nil }

        // Progressively lower quality if still too large
        while jpegData.count > maxFileSize && quality > 0.1 {
            quality -= 0.2
            if let reduced = targetImage.jpegData(compressionQuality: max(quality, 0.1)) {
                jpegData = reduced
            } else {
                break
            }
        }
        guard jpegData.count <= maxFileSize else { return nil }

        // Create thumbnail
        let thumbSize = CGSize(width: 120, height: 120)
        let renderer = UIGraphicsImageRenderer(size: thumbSize)
        let thumbImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: thumbSize))
        }
        let thumbData = thumbImage.jpegData(compressionQuality: 0.6)

        return PendingAttachment(
            kind: .image,
            fileName: fileName ?? "photo_\(UUID().uuidString.prefix(8)).jpg",
            mimeType: "image/jpeg",
            data: jpegData,
            localStoragePath: stageLocally(data: jpegData, preferredFileName: fileName ?? "photo.jpg"),
            thumbnailData: thumbData
        )
    }

    /// Create a file attachment from a URL.
    static func file(at url: URL) -> PendingAttachment? {
        let mimeType = Self.mimeType(for: url)
        guard supportsMimeType(mimeType) else { return nil }

        guard let data = try? Data(contentsOf: url) else { return nil }
        let isImage = mimeType.hasPrefix("image/")

        if isImage, let image = UIImage(data: data) {
            return Self.image(image, fileName: url.lastPathComponent)
        }

        guard data.count <= maxFileSize else { return nil }

        var thumbData: Data?
        if let image = UIImage(data: data) {
            let thumbSize = CGSize(width: 120, height: 120)
            let renderer = UIGraphicsImageRenderer(size: thumbSize)
            let thumbImage = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: thumbSize))
            }
            thumbData = thumbImage.jpegData(compressionQuality: 0.6)
        }

        return PendingAttachment(
            kind: isImage ? .image : .file,
            fileName: url.lastPathComponent,
            mimeType: mimeType,
            data: data,
            localStoragePath: stageLocally(data: data, preferredFileName: url.lastPathComponent),
            thumbnailData: thumbData
        )
    }

    static func restore(from attachment: MessageAttachment) -> PendingAttachment? {
        guard let localStoragePath = attachment.localStoragePath else { return nil }
        let url = URL(fileURLWithPath: localStoragePath)
        guard let data = try? Data(contentsOf: url), data.count <= maxFileSize else { return nil }

        let thumbnailData = attachment.thumbnailBase64.flatMap { Data(base64Encoded: $0) }
        let kind = attachment.kind == "image" ? Kind.image : Kind.file
        return PendingAttachment(
            kind: kind,
            fileName: attachment.fileName,
            mimeType: attachment.mimeType,
            data: data,
            localStoragePath: localStoragePath,
            thumbnailData: thumbnailData
        )
    }

    /// Base64 encoded data string.
    var base64Data: String {
        data.base64EncodedString()
    }

    var thumbnailBase64: String? {
        thumbnailData?.base64EncodedString()
    }

    private static func mimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        let map: [String: String] = [
            "jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png",
            "gif": "image/gif", "webp": "image/webp", "heic": "image/heic",
            "txt": "text/plain",
            "json": "application/json", "csv": "text/csv",
            "md": "text/markdown", "swift": "text/x-swift",
            "py": "text/x-python", "js": "text/javascript",
            "html": "text/html", "css": "text/css",
            "xml": "text/xml", "yml": "application/yaml",
            "yaml": "application/yaml",
        ]
        return map[ext] ?? "application/octet-stream"
    }

    private static func stageLocally(data: Data, preferredFileName: String) -> String? {
        let fileManager = FileManager.default
        guard let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        let attachmentDirectory = baseDirectory
            .appendingPathComponent("HermesMobile", isDirectory: true)
            .appendingPathComponent("Attachments", isDirectory: true)

        do {
            try fileManager.createDirectory(at: attachmentDirectory, withIntermediateDirectories: true, attributes: nil)
            let sanitizedName = sanitizeFileName(preferredFileName)
            let destination = attachmentDirectory.appendingPathComponent("\(UUID().uuidString)-\(sanitizedName)")
            try data.write(to: destination, options: .atomic)
            return destination.path
        } catch {
            return nil
        }
    }

    private static func sanitizeFileName(_ fileName: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = fileName.components(separatedBy: invalidCharacters).joined(separator: "_")
        return cleaned.isEmpty ? "attachment" : cleaned
    }
}
