import Foundation

/// Builds the wire-agnostic content parts for a chat turn from the composer's
/// message + staged attachments (#8; fixes #43 — text-MIME files used to be
/// silently dropped by `ChatTurnBody.make`).
///
/// Extracted from `SessionsHermesClient` so the assembly rules (ordering,
/// budget, delimiting, truncation) are unit-testable via `@testable import`,
/// and so the voice-memo feature (issue H) can reuse the exact same
/// delimited-text-part surface for its transcript path.
///
/// ## Delimiter format (shared surface — issue H depends on this; change with care)
///
/// Each inlined file becomes ONE `{type:"text"}` content part shaped as:
///
/// ```
/// ===== BEGIN FILE: {fileName} ({mimeType}, {totalBytes} bytes) =====
/// {content — UTF-8, capped at maxInlinedTextBytes}
/// [Talaria: truncated — first {sentBytes} of {totalBytes} bytes]   ← only when truncated
/// ===== END FILE: {fileName} =====
/// ```
///
/// `totalBytes` in the header is always the ORIGINAL size, so the agent can
/// see when the body is a prefix. An attachment that can't fit the aggregate
/// budget still ships an omission stub (same BEGIN/END frame, body
/// "[Talaria: file omitted — message size budget exceeded]") so the agent —
/// and therefore the user — is never silently shorted an attachment, which
/// was #43's core pathology.
enum AttachmentInlining {

    /// Aggregate byte budget for all attachment-derived parts in one turn.
    /// The Hermes API server accepts a ~1 MB request body; each image is
    /// already ≤350 KB raw (~470 KB base64) via `PendingAttachment`, so this
    /// conservative cap keeps a stack of attachments from tripping a hard
    /// server rejection. The user's own message text is NOT counted against
    /// it — the message always ships (plain-string turns carry no cap either).
    static let aggregateAttachmentBudget = 900 * 1024

    /// Per-file cap on inlined text content. Staged text files are ≤350 KB,
    /// but extracted OCR text from a multi-page PDF (#8) can run larger;
    /// truncation is noted INSIDE the delimited block so the agent knows it
    /// received a prefix rather than the whole file.
    static let maxInlinedTextBytes = 200 * 1024

    /// Wire-agnostic content part. `SessionsHermesClient.ChatTurnBody` maps
    /// these onto its Encodable `{type:"text"}` / `{type:"image_url"}` parts.
    enum Part: Equatable, Sendable {
        case text(String)
        case imageDataURL(String)
    }

    /// Assembly result. Empty `parts` ⇒ the caller keeps the plain-string
    /// body (byte-identical to the pre-attachment text-only turn).
    struct Assembly: Sendable {
        let parts: [Part]
        /// File names replaced with an in-band omission stub because the
        /// aggregate budget ran out. Already surfaced to the agent inside the
        /// stub; callers should also log these.
        let omittedForBudget: [String]
        /// File names with no wire representation at all (e.g. a raw,
        /// un-extracted PDF). Nothing is sent for these — the composer blocks
        /// send while any are staged (#8), so seeing one here means a non-UI
        /// path leaked it; callers must log it loudly rather than fail the turn.
        let notTransmittable: [String]
    }

    /// Assemble the content parts for one chat turn. Staged order is
    /// preserved; a non-empty message becomes the leading text part. Returns
    /// empty `parts` when nothing transmittable is attached, so text-only
    /// turns stay a plain string on the wire.
    static func assemble(message: String, attachments: [PendingAttachment]) -> Assembly {
        let notTransmittable = attachments.filter { !$0.isTransmittable }.map(\.fileName)
        let transmittable = attachments.filter(\.isTransmittable)
        guard !transmittable.isEmpty else {
            return Assembly(parts: [], omittedForBudget: [], notTransmittable: notTransmittable)
        }

        var parts: [Part] = []
        if !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(.text(message))
        }

        var remainingBudget = aggregateAttachmentBudget
        var omitted: [String] = []
        for attachment in transmittable {
            switch attachment.kind {
            case .image:
                let dataURL = "data:\(attachment.mimeType);base64,\(attachment.base64Data)"
                let cost = dataURL.utf8.count
                if cost <= remainingBudget {
                    remainingBudget -= cost
                    parts.append(.imageDataURL(dataURL))
                } else {
                    omitted.append(attachment.fileName)
                    let stub = omissionPart(
                        fileName: attachment.fileName,
                        mimeType: attachment.mimeType,
                        totalBytes: attachment.data.count
                    )
                    remainingBudget -= stub.utf8.count
                    parts.append(.text(stub))
                }
            case .file:
                // Decode with replacement characters for stray non-UTF-8
                // bytes — delivering a slightly lossy transcript beats
                // dropping the file (the mime gate already limits this path
                // to text-shaped content).
                let content = String(decoding: attachment.data, as: UTF8.self)
                let block = delimitedTextPart(
                    fileName: attachment.fileName,
                    mimeType: attachment.mimeType,
                    content: content
                )
                let cost = block.utf8.count
                if cost <= remainingBudget {
                    remainingBudget -= cost
                    parts.append(.text(block))
                } else {
                    omitted.append(attachment.fileName)
                    let stub = omissionPart(
                        fileName: attachment.fileName,
                        mimeType: attachment.mimeType,
                        totalBytes: attachment.data.count
                    )
                    remainingBudget -= stub.utf8.count
                    parts.append(.text(stub))
                }
            }
        }

        return Assembly(parts: parts, omittedForBudget: omitted, notTransmittable: notTransmittable)
    }

    /// THE shared delimiter surface (see format doc above; issue H reuses this
    /// for voice-memo transcripts). Content over `maxInlinedTextBytes` is cut
    /// on a character boundary with an explicit truncation notice in-block.
    static func delimitedTextPart(fileName: String, mimeType: String, content: String) -> String {
        let name = markerName(fileName)
        let totalBytes = content.utf8.count
        var body = content
        if totalBytes > maxInlinedTextBytes {
            let prefix = utf8SafePrefix(content, maxBytes: maxInlinedTextBytes)
            body = prefix + "\n[Talaria: truncated — first \(prefix.utf8.count) of \(totalBytes) bytes]"
        }
        return """
        ===== BEGIN FILE: \(name) (\(mimeType), \(totalBytes) bytes) =====
        \(body)
        ===== END FILE: \(name) =====
        """
    }

    /// In-band stand-in for an attachment that couldn't fit the aggregate
    /// budget: same frame, explicit omission notice — never a silent drop.
    private static func omissionPart(fileName: String, mimeType: String, totalBytes: Int) -> String {
        let name = markerName(fileName)
        return """
        ===== BEGIN FILE: \(name) (\(mimeType), \(totalBytes) bytes) =====
        [Talaria: file omitted — message size budget exceeded]
        ===== END FILE: \(name) =====
        """
    }

    /// Newlines in a file name would break the one-line BEGIN/END markers.
    private static func markerName(_ fileName: String) -> String {
        fileName
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }

    /// Longest prefix of `string` whose UTF-8 encoding is ≤ `maxBytes`, cut on
    /// a character boundary so the truncated text stays well-formed (no split
    /// multi-byte characters or emoji).
    static func utf8SafePrefix(_ string: String, maxBytes: Int) -> String {
        guard maxBytes > 0 else { return "" }
        let utf8 = string.utf8
        guard utf8.count > maxBytes else { return string }
        var cut = utf8.index(utf8.startIndex, offsetBy: maxBytes)
        while cut > utf8.startIndex, String.Index(cut, within: string) == nil {
            cut = utf8.index(before: cut)
        }
        guard let end = String.Index(cut, within: string) else { return "" }
        return String(string[..<end])
    }
}
