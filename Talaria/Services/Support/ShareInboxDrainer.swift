import Foundation
import os

/// #123: a share-extension payload staged for the composer, held on ChatStore
/// until ChatScreen pulls it in. Separate slot from the #48 ask-seed — shares
/// carry attachments and MERGE when queued (two rapid shares both land);
/// the ask-seed stays a replace-only String. Seed-only: never auto-sends.
struct ShareComposerSeed: Equatable {
    var text: String
    var attachments: [PendingAttachment]

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.text == rhs.text && lhs.attachments.map(\.id) == rhs.attachments.map(\.id)
    }
}

/// #123 — drains the app-group `SharedInbox/` on foreground and converts
/// envelopes into composer-ready content. Text-ish payloads (note, URL,
/// shared text) join in share order; file blobs convert through the EXISTING
/// `PendingAttachment.file(at:)` staging path (MIME detection, size caps,
/// image downscale + thumbnail, local staging copy) so the share pipeline
/// can never accept what the picker pipeline would refuse. Tolerant: an
/// unconvertible item is skipped + logged, never a crash, and a processed
/// envelope is removed so it can't resurface.
@MainActor
final class ShareInboxDrainer {
    struct DrainResult {
        var text: String
        var attachments: [PendingAttachment]
        var envelopeCount: Int
    }

    private static let log = Logger(subsystem: "org.aethyrion.talaria", category: "ShareInboxDrainer")

    private let store: SharedInboxStore?
    private var isDraining = false

    init(store: SharedInboxStore? = SharedInboxStore.appGroup()) {
        self.store = store
    }

    /// Nil when there was nothing to stage — either an empty inbox or
    /// envelopes whose every item was refused (those are still consumed).
    func drain() -> DrainResult? {
        guard !isDraining, let store else { return nil }
        isDraining = true
        defer { isDraining = false }

        var textParts: [String] = []
        var attachments: [PendingAttachment] = []
        var envelopeCount = 0

        for envelope in store.pendingEnvelopes() {
            envelopeCount += 1
            let note = envelope.note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty { textParts.append(note) }
            for item in envelope.items {
                switch item.kind {
                case .webURL, .text:
                    let text = item.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !text.isEmpty { textParts.append(text) }
                case .file:
                    if let attachment = convertFileItem(item, envelopeID: envelope.id, store: store) {
                        attachments.append(attachment)
                    } else {
                        Self.log.notice("Share drain: skipped unconvertible item \(item.fileName ?? item.blobFileName ?? "?", privacy: .public)")
                    }
                }
            }
            store.remove(envelopeID: envelope.id)
        }

        guard !textParts.isEmpty || !attachments.isEmpty else { return nil }
        return DrainResult(
            text: textParts.joined(separator: "\n"),
            attachments: attachments,
            envelopeCount: envelopeCount
        )
    }

    private func convertFileItem(
        _ item: ShareEnvelope.Item,
        envelopeID: UUID,
        store: SharedInboxStore
    ) -> PendingAttachment? {
        guard let blobName = item.blobFileName,
              let data = store.blobData(named: blobName, envelopeID: envelopeID) else { return nil }
        // The original file name drives MIME detection — re-materialize the
        // blob under it (sanitized) and hand it to the staging path.
        let fileName = SharedInboxStore.sanitizedBlobName(item.fileName ?? blobName)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareInboxDrain-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let tempFile = tempDir.appendingPathComponent(fileName)
            try data.write(to: tempFile)
            return PendingAttachment.file(at: tempFile)
        } catch {
            return nil
        }
    }
}
