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
    /// Local path of the recorded audio when this attachment is a voice memo
    /// (#9). The attachment's `data` is the TRANSCRIPT (what actually ships,
    /// via the #8 text-inlining branch); the audio itself never transmits and
    /// stays on-device for playback. Defaulted so every existing construction
    /// site is untouched.
    var voiceMemoAudioPath: String? = nil

    enum Kind: String, Sendable {
        case image
        case file
    }

    /// A voice memo is a text attachment (the transcript) carrying its source
    /// audio alongside for local playback (#9).
    var isVoiceMemo: Bool { voiceMemoAudioPath != nil }

    /// Maximum file size: 350 KB (before base64 encoding -> ~470KB base64).
    /// The Hermes API server accepts a 1 MB request body for the whole message payload,
    /// so individual attachments still need additional aggregate request-size validation.
    static let maxFileSize = 350 * 1024

    /// PDFs get their own, larger staging cap (#8): a raw PDF is NEVER
    /// transmitted — only its OCR-extracted text ships (as a delimited text
    /// part) — so the wire-oriented 350 KB cap doesn't apply. 10 MB keeps
    /// per-page rasterization + OCR memory sane.
    static let maxPDFFileSize = 10 * 1024 * 1024

    static let maxAttachmentsPerMessage = 4

    static let pdfMimeType = "application/pdf"

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
        mimeType.hasPrefix("image/")
            || supportedTextMimeTypes.contains(mimeType)
            || mimeType == pdfMimeType
    }

    /// Staging size cap by MIME type — see `maxPDFFileSize` for why PDFs differ.
    static func stagingCap(forMimeType mimeType: String) -> Int {
        mimeType == pdfMimeType ? maxPDFFileSize : maxFileSize
    }

    /// True when the file's bytes can be inlined as a `{type:"text"}` content
    /// part on the chat turn (#43): any `text/*` plus the structured-text
    /// application types above.
    static func isInlinableTextMime(_ mimeType: String) -> Bool {
        mimeType.hasPrefix("text/") || supportedTextMimeTypes.contains(mimeType)
    }

    /// Whether this attachment has a wire representation on the Sessions API:
    /// images ship as `image_url` data-URL parts, text-MIME files inline as
    /// delimited `{type:"text"}` parts (#43). A raw PDF (or other binary) has
    /// NO representation — it must be OCR-extracted first (#8); the composer
    /// blocks send while one is staged so it can never *look* sent.
    var isTransmittable: Bool {
        kind == .image || Self.isInlinableTextMime(mimeType)
    }

    /// Whether the explicit "Extract text" action (#8) can run on this
    /// attachment — images and PDFs go through `DocumentTextExtractor`.
    var isExtractable: Bool {
        kind == .image || mimeType == Self.pdfMimeType
    }

    /// Create an image attachment from a UIImage.
    /// Large images are automatically downscaled to stay within the size limit.
    static func image(_ image: UIImage, fileName: String? = nil) -> PendingAttachment? {
        var quality: CGFloat = 0.5
        var targetImage = image

        // Downscale images to 768px max — keeps base64 well under API body limit
        let maxDimension: CGFloat = 768
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

        // Per-mime cap: 350 KB for text (it ships inline), 10 MB for PDFs
        // (never transmitted raw — only their extracted text ships, #8).
        guard data.count <= stagingCap(forMimeType: mimeType) else { return nil }

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

    /// Convert an OCR extraction result into a staged TEXT attachment (#8).
    /// Self-describing and honest: the file name keeps the source's name plus
    /// an `.extracted.md` suffix, kind flips to `.file`, and NO thumbnail is
    /// carried over — the chip must read as "text will be sent", never as the
    /// original image ("real data only"). No size guard here: over-cap text is
    /// truncated at inline time with an explicit in-block notice
    /// (`AttachmentInlining.maxInlinedTextBytes`).
    static func extractedText(from source: PendingAttachment, text: String) -> PendingAttachment {
        let fileName = "\(source.fileName).extracted.md"
        let data = Data(text.utf8)
        return PendingAttachment(
            kind: .file,
            fileName: fileName,
            mimeType: "text/markdown",
            data: data,
            localStoragePath: stageLocally(data: data, preferredFileName: fileName),
            thumbnailData: nil
        )
    }

    /// Stage a completed voice-memo recording (#9): the TRANSCRIPT becomes the
    /// attachment's `data` — a plain-text file the #8 inlining branch ships as
    /// a delimited `{type:"text"}` part with zero send-path changes — while the
    /// audio stays referenced for local playback only. The transcript body
    /// leads with a one-line bracketed provenance header (recorded time +
    /// duration), mirroring the voice-session context-turn convention (#1).
    static func voiceMemo(
        transcript: String,
        audioFileURL: URL,
        duration: TimeInterval,
        recordedAt: Date = .now
    ) -> PendingAttachment {
        let fileName = voiceMemoFileName(recordedAt: recordedAt)
        let body = """
        [Voice memo transcript — recorded \(voiceMemoTimestamp(recordedAt)), \(voiceMemoDuration(duration))]
        \(transcript)
        """
        let data = Data(body.utf8)
        return PendingAttachment(
            kind: .file,
            fileName: fileName,
            mimeType: "text/plain",
            data: data,
            localStoragePath: stageLocally(data: data, preferredFileName: fileName),
            thumbnailData: nil,
            voiceMemoAudioPath: audioFileURL.path
        )
    }

    /// `Voice Memo 2026-07-06 14.30.05.txt` — the `.txt`/text-plain pairing is
    /// what routes it through the #8 text-inlining branch.
    static func voiceMemoFileName(recordedAt: Date) -> String {
        "Voice Memo \(voiceMemoTimestamp(recordedAt).replacingOccurrences(of: ":", with: ".")).txt"
    }

    static func voiceMemoTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    /// "4m 05s" / "32s" — human duration for the transcript provenance header.
    static func voiceMemoDuration(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration.rounded()))
        let minutes = total / 60
        let seconds = total % 60
        return minutes > 0 ? String(format: "%dm %02ds", minutes, seconds) : "\(seconds)s"
    }

    static func restore(from attachment: MessageAttachment) -> PendingAttachment? {
        guard let localStoragePath = attachment.localStoragePath else { return nil }
        let url = URL(fileURLWithPath: localStoragePath)
        guard let data = try? Data(contentsOf: url),
              data.count <= stagingCap(forMimeType: attachment.mimeType) else { return nil }

        let thumbnailData = attachment.thumbnailBase64.flatMap { Data(base64Encoded: $0) }
        let kind = attachment.kind == "image" ? Kind.image : Kind.file
        return PendingAttachment(
            kind: kind,
            fileName: attachment.fileName,
            mimeType: attachment.mimeType,
            data: data,
            localStoragePath: localStoragePath,
            thumbnailData: thumbnailData,
            voiceMemoAudioPath: attachment.voiceMemoAudioPath
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
            "pdf": "application/pdf",
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
            .appendingPathComponent("Talaria", isDirectory: true)
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
