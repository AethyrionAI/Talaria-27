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

/// Canonical "what can the composer stage" tables — single source of truth
/// for the app's staging path (`PendingAttachment` forwards here) AND the
/// share sheet's honesty check (#123): the sheet must refuse up front what
/// the app would silently drop at drain time ("real data only" house rule).
enum StageableTypeCatalog {
    static let pdfMimeType = "application/pdf"

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

    static let defaultMaxEnvelopeBytes = 20 * 1024 * 1024
    static let envelopeFileName = "envelope.json"
    private static let blobsDirName = "blobs"

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
