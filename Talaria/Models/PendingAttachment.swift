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

    /// Staging cap: 350 KB raw (~470 KB base64). A BACKSTOP, not the working
    /// size — since #174 a staged image is bounded by `imageMaxPixelDimension`
    /// and lands far below this; the cap's live job is the text-file path,
    /// which ships its bytes verbatim. The Hermes API server accepts a 1 MB
    /// request body for the whole message payload, so a stack of attachments
    /// is still bounded separately by `AttachmentInlining`.
    static let maxFileSize = 350 * 1024

    /// PDFs get their own, larger staging cap (#8): a raw PDF is NEVER
    /// transmitted — only its OCR-extracted text ships (as a delimited text
    /// part) — so the wire-oriented 350 KB cap doesn't apply. 10 MB keeps
    /// per-page rasterization + OCR memory sane.
    static let maxPDFFileSize = 10 * 1024 * 1024

    static let maxAttachmentsPerMessage = 4

    // #123: the MIME/type tables moved to `StageableTypeCatalog`
    // (ShareInboxCore.swift) so the share sheet can honestly refuse up front
    // what this staging path would reject. These forwarders keep every
    // existing call site untouched.
    static let pdfMimeType = StageableTypeCatalog.pdfMimeType

    private static var supportedTextMimeTypes: Set<String> {
        StageableTypeCatalog.textMimeTypes
    }

    static func supportsMimeType(_ mimeType: String) -> Bool {
        StageableTypeCatalog.isStageable(mimeType: mimeType)
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

    /// #174: longest-edge cap for a staged image, in PIXELS.
    ///
    /// This used to be a bare `768` compared against `UIImage.size` — which is
    /// POINTS — and rendered through a default-scale `UIGraphicsImageRenderer`,
    /// so on a 3× device the "768 px" downscale produced a 2304 px raster and
    /// inlined 233–472 KB of base64 per image (measured on the wire 2026-07-23).
    ///
    /// 1536 px is chosen against the two consumers of these exact bytes:
    /// vision models resize a long edge to roughly 1100–1570 px internally, so
    /// nothing is lost at the model; and the #8 "Extract text" OCR path runs
    /// Vision over this same buffer, where a photographed page at 1536 px
    /// across still puts body text near 22 px cap height. Honoring the old
    /// 768 comment literally would have halved that and cost extraction
    /// accuracy on documents.
    static let imageMaxPixelDimension = 1536

    /// JPEG quality for staged images — deliberately UNCHANGED at the
    /// long-standing 0.5. #174 is a payload-size fix, and moving quality at
    /// the same time as the pixel cap would have muddied the measurement:
    /// 0.6 was tried and gave back roughly a third of the reduction the pixel
    /// fix won. One knob at a time.
    static let imageJPEGQuality: CGFloat = 0.5

    /// Create an image attachment from a UIImage.
    /// Large images are automatically downscaled to stay within the size limit.
    static func image(_ image: UIImage, fileName: String? = nil) -> PendingAttachment? {
        var quality = imageJPEGQuality
        var targetImage = image

        // Measure and render in PIXELS: `size` is points, and the renderer
        // defaults to the screen's scale, so both halves have to be pinned or
        // the cap silently multiplies by the device scale (#174).
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let longestEdge = max(pixelWidth, pixelHeight)
        let maxDimension = CGFloat(imageMaxPixelDimension)
        if longestEdge > maxDimension {
            let ratio = maxDimension / longestEdge
            let newSize = CGSize(width: pixelWidth * ratio, height: pixelHeight * ratio)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
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
        StageableTypeCatalog.mimeType(forFileExtension: url.pathExtension)
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
