import Foundation
import os

/// #123 — the share-extension → app handoff surface. The TalariaShare
/// extension serializes one `ShareEnvelope` (plus its binary blobs) into the
/// app-group `SharedInbox/` directory and completes; the app drains the
/// directory on foreground and stages the content into the composer. This
/// file is compiled into BOTH targets (single-file inclusion in the app
/// target, whole-dir in TalariaShare) — Foundation only, no UIKit/network.
struct ShareEnvelope: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let createdAt: Date
    /// Optional user note typed in the share sheet — becomes composer text.
    var note: String
    var items: [Item]

    struct Item: Codable, Equatable, Sendable {
        enum Kind: String, Codable, Sendable {
            case webURL
            case text
            case file
        }

        var kind: Kind
        /// Inline payload for `.webURL` / `.text` items.
        var text: String?
        /// Blob file name inside the envelope's `blobs/` dir for `.file` items.
        var blobFileName: String?
        /// Original file name (drives MIME detection at conversion time).
        var fileName: String?

        static func webURL(_ url: String) -> Item {
            Item(kind: .webURL, text: url, blobFileName: nil, fileName: nil)
        }

        static func text(_ body: String) -> Item {
            Item(kind: .text, text: body, blobFileName: nil, fileName: nil)
        }

        static func file(blobFileName: String, fileName: String) -> Item {
            Item(kind: .file, text: nil, blobFileName: blobFileName, fileName: fileName)
        }
    }

    /// ISO-8601 dates (whole-second) on both sides — the encoder settings are
    /// part of the cross-process contract, so they live here, not at call
    /// sites.
    static func encode(_ envelope: ShareEnvelope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(envelope)
    }

    static func decode(from data: Data) throws -> ShareEnvelope {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ShareEnvelope.self, from: data)
    }
}

enum SharedInboxError: Error, Equatable {
    case payloadTooLarge(totalBytes: Int)
}

/// #431 — what the APP's staging path does with a file of a given type, as a
/// SIZE policy. The share extension cannot import `PendingAttachment` (UIKit,
/// app target only), so before this existed the sheet knew only whether a type
/// was stageable at all and let a 20 MB `.md` through against a 350 KB cap —
/// a 58× window whose whole content vanished at drain.
///
/// **The three arms are not three caps; they are three different behaviours**,
/// and that distinction is the reason a single `Int` would have been wrong:
/// `PendingAttachment.file(at:)` RE-ENCODES an image (downscale to
/// `imageMaxPixelDimension`, then step JPEG quality down) rather than refusing
/// it, so an oversized image is not an over-cap refusal and must not be
/// refused up front.
enum StagingSizePolicy: Equatable, Sendable {
    /// The bytes ship verbatim and the app REFUSES above `bytes`. `label` is
    /// what a refusal states, and it is carried beside the number rather than
    /// formatted from it: `ByteCountFormatter` ROUNDS, and 10,485,760 renders
    /// as "10.5 MB" — a stated limit 14,240 bytes LARGER than the one
    /// enforced, which is exactly the defect #180-E fixed at the envelope cap.
    /// These labels understate by construction.
    case refusedAbove(bytes: Int, label: String)
    /// The app re-encodes the file to fit its own cap, so the SOURCE size is
    /// never a refusal — only the aggregate envelope budget bounds it. An
    /// image whose bytes turn out to be undecodable still fails, but only the
    /// app can discover that, and #431-C makes that failure visible at drain.
    case reEncodedToFit
    /// Not stageable at all — refused on TYPE, before size is considered.
    case unsupportedType
}

/// The acceptance decision the share sheet makes for one file, and the app's
/// staging cap, derived from ONE table (#431-A). Lives in the shared core
/// because there is no `TalariaShareTests` target: the extension's own sources
/// are unreachable from the suite, so a decision that lives in
/// `ShareViewController` cannot be tested at all.
enum ShareItemAcceptance: Equatable, Sendable {
    case accepted
    /// `message` names the file, its size, and the limit — it is the whole
    /// user-facing sentence, so a surface with no separate name line (the
    /// drain's failure banner) can render it as-is.
    case refused(message: String)
}

/// The sentences the extension and the drain both speak (#431). One builder
/// per reason so the two processes cannot drift into two vocabularies for the
/// same refusal.
enum ShareRefusal {
    static func unsupportedType(fileName: String) -> String {
        "“\(fileName)” isn’t a file type Talaria can accept"
    }

    static func audioOrVideo(fileName: String) -> String {
        "“\(fileName)” — audio and video can’t be sent to Talaria"
    }

    static func unreadable(fileName: String) -> String {
        "“\(fileName)” couldn’t be read"
    }

    static func overTypeCap(fileName: String, byteCount: Int, capLabel: String) -> String {
        "“\(fileName)” is \(SharedInboxStore.byteLabel(byteCount)); "
            + "Talaria accepts up to \(capLabel) for this type"
    }

    /// The AGGREGATE refusal keeps its own reason (#431-B) — a share can be
    /// under every per-type cap and still overflow one envelope.
    ///
    /// **Unchanged residual, stated rather than hidden (#180-E's own
    /// found-but-not-fixed note):** `blobItem` guards on the REMAINING budget
    /// across a multi-item share while this names the FULL cap, so a second
    /// file refused because the first consumed the budget is told the limit
    /// that would have applied on its own. #431 does not fix that.
    static func overShareBudget(fileName: String, byteCount: Int) -> String {
        "“\(fileName)” is \(SharedInboxStore.byteLabel(byteCount)); "
            + "one share can carry up to \(SharedInboxStore.sizeLimitLabel)"
    }

    /// The drain-time fallback: the app refused the file for a reason the size
    /// table cannot name (undecodable image bytes, a `.pdf` that is not a
    /// PDF). Honest about which half knows what — the extension could not have
    /// seen this, so it is reported rather than pre-refused.
    static func couldNotStage(fileName: String) -> String {
        "“\(fileName)” couldn’t be added — Talaria couldn’t read the file"
    }
}

/// Canonical "what can the composer stage" tables — single source of truth
/// for the app's staging path (`PendingAttachment` forwards here) AND the
/// share sheet's honesty check (#123): the sheet must refuse up front what
/// the app would silently drop at drain time ("real data only" house rule).
enum StageableTypeCatalog {
    static let pdfMimeType = "application/pdf"

    /// #431-A — the app's verbatim staging caps, owned HERE and forwarded by
    /// `PendingAttachment` (which used to own them as literals the extension
    /// could not see). Today's values, deliberately unchanged by this lane.
    static let maxVerbatimBytes = 350 * 1024
    static let maxVerbatimLabel = "350 KB"
    static let maxPDFBytes = 10 * 1024 * 1024
    static let maxPDFLabel = "10 MB"

    static let textMimeTypes: Set<String> = [
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

    private static let extensionToMime: [String: String] = [
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

    static func mimeType(forFileExtension ext: String) -> String {
        extensionToMime[ext.lowercased()] ?? "application/octet-stream"
    }

    static func isStageable(mimeType: String) -> Bool {
        mimeType.hasPrefix("image/")
            || textMimeTypes.contains(mimeType)
            || mimeType == pdfMimeType
    }

    static func isStageable(fileName: String) -> Bool {
        isStageable(mimeType: mimeType(forFileExtension: (fileName as NSString).pathExtension))
    }

    /// #431-A — the ONE size table. `PendingAttachment.stagingCap(forMimeType:)`
    /// reads it, and so does the extension's acceptance decision below, so the
    /// two cannot diverge without an edit here.
    ///
    /// The arms mirror `isStageable(mimeType:)` exactly: a type is stageable
    /// if and only if its policy is not `.unsupportedType` (pinned).
    static func sizePolicy(forMimeType mimeType: String) -> StagingSizePolicy {
        if mimeType.hasPrefix("image/") { return .reEncodedToFit }
        if mimeType == pdfMimeType {
            return .refusedAbove(bytes: maxPDFBytes, label: maxPDFLabel)
        }
        if textMimeTypes.contains(mimeType) {
            return .refusedAbove(bytes: maxVerbatimBytes, label: maxVerbatimLabel)
        }
        return .unsupportedType
    }

    static func sizePolicy(fileName: String) -> StagingSizePolicy {
        sizePolicy(forMimeType: mimeType(forFileExtension: (fileName as NSString).pathExtension))
    }

    /// #431-B — the extension's acceptance decision for one file, made BEFORE
    /// Send. Type first, then the type's own cap, then the aggregate envelope
    /// budget: the most specific reason wins, because "one share can carry up
    /// to 20 MB" cannot explain a 400 KB `.md` being refused.
    ///
    /// `remainingBytes` is the budget LEFT in this share, not the cap — a
    /// multi-item share spends it in order.
    static func acceptance(
        fileName: String,
        byteCount: Int,
        remainingBytes: Int
    ) -> ShareItemAcceptance {
        switch sizePolicy(fileName: fileName) {
        case .unsupportedType:
            return .refused(message: ShareRefusal.unsupportedType(fileName: fileName))
        case .refusedAbove(let bytes, let label):
            if byteCount > bytes {
                return .refused(message: ShareRefusal.overTypeCap(
                    fileName: fileName, byteCount: byteCount, capLabel: label))
            }
        case .reEncodedToFit:
            break
        }
        guard byteCount <= remainingBytes else {
            return .refused(message: ShareRefusal.overShareBudget(
                fileName: fileName, byteCount: byteCount))
        }
        return .accepted
    }
}

/// File-store over the app-group `SharedInbox/` directory. Extension side
/// writes (blobs first, `envelope.json` LAST — its presence is the
/// completeness marker); app side drains. Tolerant by design: a corrupt or
/// oversize envelope is skipped + logged + cleaned, never a crash.
struct SharedInboxStore: Sendable {
    let rootURL: URL
    let maxEnvelopeBytes: Int
    /// How long an incomplete dir (no envelope.json yet) may sit before it
    /// counts as an abandoned extension write and is cleaned up.
    let staleIncompleteGrace: TimeInterval

    /// #180 lane 180-L (bar 180-E) — **base-10, deliberately, so the number
    /// the refusal states is the number the guard enforces.**
    ///
    /// ~~`20 * 1024 * 1024`~~ (20 MiB = 20,971,520) was base-2 while every
    /// label the extension renders is `ByteCountFormatter(.file)`, which is
    /// base-10 — the same arithmetic Files and Photos show the user. The
    /// refusal therefore announced *"limit 21 MB"*, a limit **28,480 bytes
    /// larger than the one actually enforced**, and a 20,999,999-byte file the
    /// guard refuses ALSO rendered "21 MB": *"21 MB is too large — limit
    /// 21 MB."*
    ///
    /// **This is Owen's decision (dispatch §8.4) and it is one constant wide.**
    /// The alternative was keeping the base-2 cap and rendering the limit with
    /// a base-2 formatter ("20 MiB") — more precise, uglier, and not what the
    /// user's file browser shows. Bar 180-E is identical either way, so
    /// reversing this is a one-line change plus a re-run.
    ///
    /// **Residual, stated rather than hidden:** any rounded label keeps a
    /// boundary band (cap+1 … ~cap+499,999) that still renders as "20 MB".
    /// This removes the systematic overstatement, not rounding itself.
    static let defaultMaxEnvelopeBytes = 20_000_000
    static let envelopeFileName = "envelope.json"
    private static let blobsDirName = "blobs"

    /// #180 lane 180-L (bar 180-E) — **the refusal's arithmetic lives next to
    /// the guard it explains.** This was `ShareSheetModel.LoadedItem.byteLabel`
    /// in `ShareViewController.swift`, which is compiled ONLY into the
    /// TalariaShare target and is therefore unreachable from the suite; this
    /// file is compiled into both, so the number the user is shown and the
    /// number the guard enforces can be asserted against each other.
    /// Pure code motion at this commit.
    static func byteLabel(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }

    /// The limit as the refusal states it. Same formatter as any file size the
    /// extension shows, so the two are comparable by construction.
    static var sizeLimitLabel: String { byteLabel(defaultMaxEnvelopeBytes) }

    private static let log = Logger(subsystem: "org.aethyrion.talaria", category: "SharedInbox")

    init(
        rootURL: URL,
        maxEnvelopeBytes: Int = Self.defaultMaxEnvelopeBytes,
        staleIncompleteGrace: TimeInterval = 3600
    ) {
        self.rootURL = rootURL
        self.maxEnvelopeBytes = maxEnvelopeBytes
        self.staleIncompleteGrace = staleIncompleteGrace
    }

    /// The production store in the shared app-group container, or nil when
    /// the group entitlement is missing (never expected in real builds).
    /// Same APP_GROUP_ID override + fallback as `SharedWidgetDataStore`.
    static func appGroup() -> SharedInboxStore? {
        let groupID = (Bundle.main.object(forInfoDictionaryKey: "APP_GROUP_ID") as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? "group.org.aethyrion.talaria"
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupID) else { return nil }
        return SharedInboxStore(rootURL: container.appendingPathComponent("SharedInbox", isDirectory: true))
    }

    // MARK: - Extension side (write)

    /// Writes blobs first, `envelope.json` last — a dir without the envelope
    /// file is by definition an in-flight or abandoned write. A failed or
    /// refused write leaves nothing behind.
    func write(_ envelope: ShareEnvelope, blobs: [String: Data]) throws {
        let totalBytes = blobs.values.reduce(0) { $0 + $1.count }
        guard totalBytes <= maxEnvelopeBytes else {
            throw SharedInboxError.payloadTooLarge(totalBytes: totalBytes)
        }

        let fileManager = FileManager.default
        let envelopeDir = directoryURL(for: envelope.id)
        let blobsDir = envelopeDir.appendingPathComponent(Self.blobsDirName, isDirectory: true)
        do {
            try fileManager.createDirectory(at: blobsDir, withIntermediateDirectories: true)
            for (name, data) in blobs {
                try data.write(to: blobsDir.appendingPathComponent(Self.sanitizedBlobName(name)), options: .atomic)
            }
            try ShareEnvelope.encode(envelope)
                .write(to: envelopeDir.appendingPathComponent(Self.envelopeFileName), options: .atomic)
        } catch {
            try? fileManager.removeItem(at: envelopeDir)
            throw error
        }
    }

    // MARK: - App side (drain)

    /// Complete envelopes in share order (createdAt ascending), deduped by
    /// envelope id. Anything unreadable is cleaned up as it's encountered:
    /// corrupt or oversize envelopes and stale incomplete dirs are removed;
    /// fresh incomplete dirs (the extension may still be writing) survive.
    func pendingEnvelopes() -> [ShareEnvelope] {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var byID: [UUID: ShareEnvelope] = [:]
        // Stable scan order so dedupe keeps a deterministic winner.
        for dir in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }

            let envelopeURL = dir.appendingPathComponent(Self.envelopeFileName)
            guard fileManager.fileExists(atPath: envelopeURL.path) else {
                if isStale(dir) {
                    Self.log.notice("SharedInbox drain: removing stale incomplete dir \(dir.lastPathComponent, privacy: .public)")
                    try? fileManager.removeItem(at: dir)
                }
                continue
            }

            let size = directorySize(dir)
            guard size <= maxEnvelopeBytes else {
                Self.log.notice("SharedInbox drain: skipping oversize envelope dir \(dir.lastPathComponent, privacy: .public) (\(size) bytes)")
                try? fileManager.removeItem(at: dir)
                continue
            }

            guard let data = try? Data(contentsOf: envelopeURL),
                  let envelope = try? ShareEnvelope.decode(from: data) else {
                Self.log.notice("SharedInbox drain: skipping corrupt envelope in \(dir.lastPathComponent, privacy: .public)")
                try? fileManager.removeItem(at: dir)
                continue
            }

            // Dedupe: the canonical dir is the one NAMED by the envelope id —
            // blob lookup resolves through it. Any duplicate is removed so it
            // can't resurface on the next drain.
            if dir.lastPathComponent != envelope.id.uuidString {
                if byID[envelope.id] != nil || fileManager.fileExists(atPath: directoryURL(for: envelope.id).path) {
                    Self.log.notice("SharedInbox drain: removing duplicate envelope dir \(dir.lastPathComponent, privacy: .public)")
                    try? fileManager.removeItem(at: dir)
                    continue
                }
            }
            if byID[envelope.id] == nil {
                byID[envelope.id] = envelope
            }
        }

        return byID.values.sorted {
            ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString)
        }
    }

    func blobData(named name: String, envelopeID: UUID) -> Data? {
        let url = directoryURL(for: envelopeID)
            .appendingPathComponent(Self.blobsDirName, isDirectory: true)
            .appendingPathComponent(Self.sanitizedBlobName(name))
        return try? Data(contentsOf: url)
    }

    func remove(envelopeID: UUID) {
        try? FileManager.default.removeItem(at: directoryURL(for: envelopeID))
    }

    // MARK: - Helpers

    private func directoryURL(for envelopeID: UUID) -> URL {
        rootURL.appendingPathComponent(envelopeID.uuidString, isDirectory: true)
    }

    /// Same invalid-character policy as `PendingAttachment.sanitizeFileName` —
    /// no path separators can survive, so a blob name can never escape its
    /// envelope's `blobs/` dir.
    static func sanitizedBlobName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = name.components(separatedBy: invalidCharacters).joined(separator: "_")
        return cleaned.isEmpty ? "blob" : cleaned
    }

    private func isStale(_ dir: URL) -> Bool {
        let modified = (try? dir.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
        return Date().timeIntervalSince(modified) >= staleIncompleteGrace
    }

    private func directorySize(_ dir: URL) -> Int {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: dir, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]
        ) else { return 0 }
        var total = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            total += values?.totalFileAllocatedSize ?? values?.fileSize ?? 0
        }
        return total
    }
}
