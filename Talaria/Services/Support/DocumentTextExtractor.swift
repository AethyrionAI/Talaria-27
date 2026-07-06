import Foundation
import PDFKit
import UIKit
import Vision

/// On-device OCR / document extraction (#8).
///
/// ALL of the Vision + PDFKit API surface for the feature lives in this one
/// file so a Mac session can verify/fix the genuinely-new iOS 26 shapes in a
/// single place. Everything else in the feature (inlining, chips, wire format)
/// is stable API.
///
/// Two engines, in order:
/// 1. `RecognizeDocumentsRequest` (iOS 26 GA — no entitlement, not
///    Apple-Intelligence-gated): structured output — running text, tables,
///    lists, barcodes/QR, detected data (emails/phones/URLs). Formatted here
///    into readable markdown-ish text for the agent.
/// 2. `RecognizeTextRequest` (iOS 18 GA) as the fallback when the document
///    request throws: plain line-by-line transcript.
///
/// PDFs: `RecognizeDocumentsRequest` takes images, not PDFs, and produces one
/// `DocumentObservation` per image — so pages are rasterized via PDFKit at
/// ~2x scale and OCR'd one page at a time, emitting page-numbered sections.
///
/// Stateless — static async funcs only. All funcs are nonisolated, so OCR runs
/// off the main actor; inputs/outputs are `Sendable` (`Data`/`String`).
enum DocumentTextExtractor {

    enum ExtractionError: LocalizedError {
        case unsupportedType(String)
        case unreadablePDF
        case noTextFound

        var errorDescription: String? {
            switch self {
            case .unsupportedType(let mimeType):
                "Text extraction isn't supported for \(mimeType)."
            case .unreadablePDF:
                "The PDF couldn't be opened."
            case .noTextFound:
                "No readable text was found."
            }
        }
    }

    // MARK: - Entry points

    /// Extract text from a staged attachment — images and PDFs only (the
    /// composer's "Extract text" action gates on `isExtractable`).
    static func extractText(from attachment: PendingAttachment) async throws -> String {
        if attachment.mimeType == PendingAttachment.pdfMimeType {
            return try await extractText(fromPDFData: attachment.data)
        }
        if attachment.mimeType.hasPrefix("image/") {
            return try await extractText(fromImageData: attachment.data)
        }
        throw ExtractionError.unsupportedType(attachment.mimeType)
    }

    static func extractText(fromImageData data: Data) async throws -> String {
        let text = try await recognize(imageData: data)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExtractionError.noTextFound
        }
        return text
    }

    /// Rasterize each PDF page and OCR it, emitting `## Page N` sections.
    /// Pages that render but carry no recognizable text are noted honestly
    /// rather than skipped; if NO page yields text the whole extraction fails
    /// so the UI never stages an empty "extracted" file.
    static func extractText(fromPDFData data: Data) async throws -> String {
        guard let document = PDFDocument(data: data), document.pageCount > 0 else {
            throw ExtractionError.unreadablePDF
        }

        var sections: [String] = []
        var recognizedAny = false
        for pageIndex in 0 ..< document.pageCount {
            let pageNumber = pageIndex + 1
            guard let page = document.page(at: pageIndex),
                  let imageData = rasterize(page: page) else {
                sections.append("## Page \(pageNumber)\n\n[page could not be rendered]")
                continue
            }
            let pageText = ((try? await recognize(imageData: imageData)) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if pageText.isEmpty {
                sections.append("## Page \(pageNumber)\n\n[no text detected]")
            } else {
                recognizedAny = true
                sections.append("## Page \(pageNumber)\n\n\(pageText)")
            }
        }

        guard recognizedAny else { throw ExtractionError.noTextFound }
        return sections.joined(separator: "\n\n")
    }

    // MARK: - PDF rasterization (PDFKit)

    /// Render one page to JPEG bytes at ~2x (≈144 dpi) — enough resolution for
    /// OCR without ballooning memory. `PDFPage.thumbnail(of:for:)` handles the
    /// coordinate flip/rotation that manual CGContext drawing gets wrong.
    private static func rasterize(page: PDFPage) -> Data? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let scale: CGFloat = 2.0
        // Clamp the longest side so a giant page can't allocate hundreds of MB.
        let maxSide: CGFloat = 4096
        let rawSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let clamp = min(1, maxSide / max(rawSize.width, rawSize.height))
        let size = CGSize(width: rawSize.width * clamp, height: rawSize.height * clamp)

        let image = page.thumbnail(of: size, for: .mediaBox)
        return image.jpegData(compressionQuality: 0.9)
    }

    // MARK: - Vision

    /// Structured document OCR with a plain-text fallback: if the iOS 26
    /// document request throws (or its shape shifted under a beta), fall back
    /// to the battle-tested `RecognizeTextRequest` rather than surfacing an
    /// error for content the older engine can still read.
    private static func recognize(imageData data: Data) async throws -> String {
        do {
            return try await recognizeDocument(in: data)
        } catch {
            return try await recognizeLinesFallback(in: data)
        }
    }

    /// iOS 26 Vision API — verify against SDK on Mac: `RecognizeDocumentsRequest`,
    /// `perform(on: Data)`, and `[DocumentObservation]` with `.document`.
    private static func recognizeDocument(in data: Data) async throws -> String {
        let request = RecognizeDocumentsRequest()
        let observations = try await request.perform(on: data)
        guard let document = observations.first?.document else {
            throw ExtractionError.noTextFound
        }
        let formatted = format(document)
        guard !formatted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExtractionError.noTextFound
        }
        return formatted
    }

    /// iOS 18 GA Vision Swift API — stable, well-documented shape.
    private static func recognizeLinesFallback(in data: Data) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let observations = try await request.perform(on: data)
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        guard !lines.isEmpty else { throw ExtractionError.noTextFound }
        return lines.joined(separator: "\n")
    }

    // MARK: - Structured formatting (iOS 26 shapes — verify on Mac)

    /// Render a `DocumentObservation.Container.Document` as readable
    /// markdown-ish text: the running transcript first (paragraphs in reading
    /// order), then structured tables/lists, then barcode payloads and a
    /// detected-data trailer — each section only when present. Table/list text
    /// may repeat content from the transcript; the duplication is deliberate
    /// (a repeat is cheaper for the agent than an omission).
    private static func format(_ document: DocumentObservation.Container.Document) -> String {
        var sections: [String] = []

        // iOS 26 Vision API — verify on Mac: `document.text.transcript`.
        let transcript = document.text.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !transcript.isEmpty {
            sections.append(transcript)
        }

        let tables = document.tables.compactMap(markdownTable)
        if !tables.isEmpty {
            sections.append("Tables (structured):\n\n" + tables.joined(separator: "\n\n"))
        }

        let lists = document.lists.compactMap(markdownList)
        if !lists.isEmpty {
            sections.append("Lists (structured):\n\n" + lists.joined(separator: "\n\n"))
        }

        // iOS 26 Vision API — verify on Mac: `document.barcodes` →
        // `[BarcodeObservation]` with `.payloadString`.
        let barcodePayloads = document.barcodes.compactMap { $0.payloadString }
        if !barcodePayloads.isEmpty {
            sections.append("Barcodes / QR:\n" + barcodePayloads.map { "- \($0)" }.joined(separator: "\n"))
        }

        let detected = detectedDataLines(in: document)
        if !detected.isEmpty {
            sections.append("Detected data:\n" + detected.map { "- \($0)" }.joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n")
    }

    /// iOS 26 Vision API — verify on Mac: `table.rows` is an array of rows,
    /// each an array of cells, and `cell.content.text.transcript` is the
    /// cell's text.
    private static func markdownTable(_ table: DocumentObservation.Container.Table) -> String? {
        let rows: [[String]] = table.rows.map { row in
            row.map { cell in
                cell.content.text.transcript
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "|", with: "\\|")
            }
        }
        guard let header = rows.first else { return nil }
        var lines: [String] = []
        lines.append("| " + header.joined(separator: " | ") + " |")
        lines.append("| " + header.map { _ in "---" }.joined(separator: " | ") + " |")
        for row in rows.dropFirst() {
            lines.append("| " + row.joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n")
    }

    /// iOS 26 Vision API — verify on Mac: `list.items` elements expose
    /// `.text.transcript` like the other containers.
    private static func markdownList(_ list: DocumentObservation.Container.List) -> String? {
        let items = list.items
            .map { $0.text.transcript.replacingOccurrences(of: "\n", with: " ") }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !items.isEmpty else { return nil }
        return items.map { "- \($0)" }.joined(separator: "\n")
    }

    /// iOS 26 Vision API — verify on Mac: `document.text.detectedData` items
    /// carry `match.details` with associated payloads per kind. Emails,
    /// phones, and links have clean payload accessors; dates / postal
    /// addresses / other kinds need their payload shapes checked against the
    /// SDK before formatting (their raw text is in the transcript regardless),
    /// so they fall through `default` for now.
    private static func detectedDataLines(in document: DocumentObservation.Container.Document) -> [String] {
        var lines: [String] = []
        for item in document.text.detectedData {
            switch item.match.details {
            case .emailAddress(let email):
                lines.append("Email: \(email.emailAddress)")
            case .phoneNumber(let phone):
                lines.append("Phone: \(phone.phoneNumber)")
            case .link(let url):
                lines.append("URL: \(url.absoluteString)")
            default:
                break
            }
        }
        return lines
    }
}
