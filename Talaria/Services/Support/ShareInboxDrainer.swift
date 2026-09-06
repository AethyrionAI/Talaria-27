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

/// #431-C — a shared file the drain could not stage, carried to the UI
/// instead of being logged and dropped.
///
/// The old drain logged `skipped unconvertible item` and removed the envelope,
/// so a file the share sheet had ACCEPTED disappeared with no user-facing
/// result — #190B's shape exactly ("the old catch logged and returned, which
/// is how a deterministic dead tap stayed invisible on device"), and it is
/// surfaced the same way: as store state the chat screen renders.
///
/// `message` is the whole sentence and already names the file, because it is
/// built by the same `ShareRefusal` builders the extension speaks.
struct ShareItemFailure: Equatable, Sendable {
    let fileName: String
    let message: String
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
        /// #431-C: per-item results the user must see. A drain that produced
        /// ONLY failures still returns a result — that is the whole point.
        var failures: [ShareItemFailure] = []
    }

    /// The two ways one `.file` item can end (#431-C). It used to be
    /// `PendingAttachment?`, and the nil arm was where the item vanished.
    private enum FileItemOutcome {
        case staged(PendingAttachment)
        case failed(ShareItemFailure)
    }

    private static let log = Logger(subsystem: "org.aethyrion.talaria", category: "ShareInboxDrainer")

    private let store: SharedInboxStore?
    private var isDraining = false

    init(store: SharedInboxStore? = SharedInboxStore.appGroup()) {
        self.store = store
    }

    /// Nil when there was nothing to stage AND nothing to report — an empty
    /// inbox. **#431-C: an envelope whose every item failed no longer returns
    /// nil.** It used to, which is how a share could be consumed, logged and
    /// forgotten with the app showing nothing at all; the failures ride the
    /// result and reach the user.
    func drain() -> DrainResult? {
        guard !isDraining, let store else { return nil }
        isDraining = true
        defer { isDraining = false }

        var textParts: [String] = []
        var attachments: [PendingAttachment] = []
        var failures: [ShareItemFailure] = []
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
                    switch convertFileItem(item, envelopeID: envelope.id, store: store) {
                    case .staged(let attachment):
                        attachments.append(attachment)
                    case .failed(let failure):
                        failures.append(failure)
                        Self.log.notice("Share drain: could not stage \(failure.fileName, privacy: .public)")
                    }
                }
            }
            store.remove(envelopeID: envelope.id)
        }

        guard !textParts.isEmpty || !attachments.isEmpty || !failures.isEmpty else { return nil }
        return DrainResult(
            text: textParts.joined(separator: "\n"),
            attachments: attachments,
            envelopeCount: envelopeCount,
            failures: failures
        )
    }

    private func convertFileItem(
        _ item: ShareEnvelope.Item,
        envelopeID: UUID,
        store: SharedInboxStore
    ) -> FileItemOutcome {
        let displayName = item.fileName ?? item.blobFileName ?? "Shared file"
        guard let blobName = item.blobFileName,
              let data = store.blobData(named: blobName, envelopeID: envelopeID) else {
            return .failed(ShareItemFailure(
                fileName: displayName,
                message: ShareRefusal.unreadable(fileName: displayName)))
        }
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
            if let attachment = PendingAttachment.file(at: tempFile) {
                return .staged(attachment)
            }
            return .failed(ShareItemFailure(
                fileName: fileName,
                message: Self.stagingRefusalMessage(fileName: fileName, byteCount: data.count)))
        } catch {
            return .failed(ShareItemFailure(
                fileName: fileName,
                message: ShareRefusal.unreadable(fileName: fileName)))
        }
    }

    /// #431-C — why the staging path said no, named from the SAME table the
    /// share sheet reads (`StageableTypeCatalog`), so the two halves of the
    /// pipeline cannot explain one refusal two ways.
    ///
    /// `remainingBytes` is deliberately the file's own size: the aggregate
    /// envelope budget was already spent at write time and cannot be the
    /// reason here, so passing it inert keeps that arm from firing. When the
    /// table says the file was acceptable and the app still refused it, the
    /// cause is something only the app can see — undecodable image bytes, or
    /// a `.pdf` that is not a PDF (#431's `looksLikePDF`) — and the fallback
    /// says exactly that rather than inventing a size.
    // harness-visible
    static func stagingRefusalMessage(fileName: String, byteCount: Int) -> String {
        switch StageableTypeCatalog.acceptance(
            fileName: fileName, byteCount: byteCount, remainingBytes: byteCount
        ) {
        case .refused(let message): message
        case .accepted: ShareRefusal.couldNotStage(fileName: fileName)
        }
    }
}
