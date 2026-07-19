import Foundation
import Testing
import UIKit
@testable import Talaria

/// #123 — app-side drain: SharedInbox envelopes become composer-ready
/// content. Text-ish payloads (note, URL, shared text) join in share order;
/// file blobs convert through the EXISTING `PendingAttachment.file(at:)`
/// staging path (caps, MIME detection, image downscale, thumbnails) so the
/// share pipeline can never accept what the picker pipeline would refuse.
/// Tolerant: an unconvertible item is skipped + logged, never a crash, and a
/// processed envelope never resurfaces.
@MainActor
struct ShareInboxDrainTests {

    private static let t0 = Date(timeIntervalSince1970: 1_752_000_000)

    private func makeStore() -> SharedInboxStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareInboxDrainTests-\(UUID().uuidString)", isDirectory: true)
        return SharedInboxStore(rootURL: root)
    }

    private func envelope(
        createdAt: Date = t0,
        note: String = "",
        items: [ShareEnvelope.Item]
    ) -> ShareEnvelope {
        ShareEnvelope(id: UUID(), createdAt: createdAt, note: note, items: items)
    }

    @Test func drainCombinesEnvelopesInShareOrder() throws {
        let store = makeStore()
        let drainer = ShareInboxDrainer(store: store)
        let second = envelope(createdAt: Self.t0.addingTimeInterval(1), items: [.text("and this text")])
        let first = envelope(createdAt: Self.t0, note: "check this", items: [.webURL("https://example.com/x")])
        try store.write(second, blobs: [:])
        try store.write(first, blobs: [:])

        let result = try #require(drainer.drain())
        #expect(result.text == "check this\nhttps://example.com/x\nand this text")
        #expect(result.attachments.isEmpty)
        #expect(result.envelopeCount == 2)
        // Consumed — a second drain finds nothing.
        #expect(store.pendingEnvelopes().isEmpty)
        #expect(drainer.drain() == nil)
    }

    @Test func drainConvertsTextBlobThroughPendingAttachment() throws {
        let store = makeStore()
        let drainer = ShareInboxDrainer(store: store)
        let body = "# shared notes"
        let env = envelope(items: [.file(blobFileName: "0-notes.md", fileName: "notes.md")])
        try store.write(env, blobs: ["0-notes.md": Data(body.utf8)])

        let result = try #require(drainer.drain())
        let attachment = try #require(result.attachments.first)
        #expect(result.attachments.count == 1)
        #expect(attachment.kind == .file)
        #expect(attachment.fileName == "notes.md")
        #expect(attachment.mimeType == "text/markdown")
        #expect(attachment.data == Data(body.utf8))
    }

    @Test func drainConvertsImageBlobToImageAttachment() throws {
        let store = makeStore()
        let drainer = ShareInboxDrainer(store: store)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 12, height: 12))
        }
        let jpeg = try #require(image.jpegData(compressionQuality: 0.9))
        let env = envelope(items: [.file(blobFileName: "0-photo.jpg", fileName: "photo.jpg")])
        try store.write(env, blobs: ["0-photo.jpg": jpeg])

        let result = try #require(drainer.drain())
        #expect(result.attachments.count == 1)
        #expect(result.attachments.first?.kind == .image)
    }

    @Test func drainSkipsUnsupportedBlobAndKeepsTheRest() throws {
        let store = makeStore()
        let drainer = ShareInboxDrainer(store: store)
        let env = envelope(items: [
            .file(blobFileName: "0-clip.mov", fileName: "clip.mov"),
            .text("kept"),
        ])
        try store.write(env, blobs: ["0-clip.mov": Data(count: 64)])

        let result = try #require(drainer.drain())
        #expect(result.text == "kept")
        #expect(result.attachments.isEmpty)
        // The envelope is consumed even though one item was refused —
        // a bad item must not wedge the inbox.
        #expect(store.pendingEnvelopes().isEmpty)
    }

    @Test func drainReturnsNilWhenInboxEmpty() {
        let drainer = ShareInboxDrainer(store: makeStore())
        #expect(drainer.drain() == nil)
    }

    @Test func drainWithNothingConvertibleReturnsNilButConsumes() throws {
        let store = makeStore()
        let drainer = ShareInboxDrainer(store: store)
        let env = envelope(items: [.file(blobFileName: "0-blob.bin", fileName: "blob.bin")])
        try store.write(env, blobs: ["0-blob.bin": Data(count: 64)])

        #expect(drainer.drain() == nil)
        #expect(store.pendingEnvelopes().isEmpty)
    }
}
