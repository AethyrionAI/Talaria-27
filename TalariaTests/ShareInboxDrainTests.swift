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

    /// #431-C — REWRITTEN. This test used to end at "the envelope is consumed
    /// even though one item was refused", which pinned the silent skip as
    /// correct: nothing asserted that the user ever learned. The unsupported
    /// item now comes back as a NAMED failure alongside the text that landed.
    @Test func drainReportsUnsupportedBlobAndKeepsTheRest() throws {
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
        #expect(result.failures.count == 1, "the refused item vanished instead of being reported")
        let failure = try #require(result.failures.first)
        #expect(failure.fileName == "clip.mov")
        #expect(failure.message == ShareRefusal.unsupportedType(fileName: "clip.mov"),
                "\(failure.message)")
        // The envelope is consumed even though one item was refused —
        // a bad item must not wedge the inbox.
        #expect(store.pendingEnvelopes().isEmpty)
    }

    @Test func drainReturnsNilWhenInboxEmpty() {
        let drainer = ShareInboxDrainer(store: makeStore())
        #expect(drainer.drain() == nil)
    }

    /// #431-C — REWRITTEN, and this is the assertion that PINNED the defect:
    /// `#expect(drainer.drain() == nil)` said a share whose every item failed
    /// must produce nothing at all, which is precisely how a file the share
    /// sheet accepted could be consumed and forgotten with the app showing no
    /// sign of it. A failures-only drain now returns a result.
    @Test func drainWithNothingConvertibleReportsFailuresAndConsumes() throws {
        let store = makeStore()
        let drainer = ShareInboxDrainer(store: store)
        let env = envelope(items: [.file(blobFileName: "0-blob.bin", fileName: "blob.bin")])
        try store.write(env, blobs: ["0-blob.bin": Data(count: 64)])

        let result = try #require(drainer.drain(),
                                  "a share whose every item failed still returned nothing to show")
        #expect(result.text.isEmpty)
        #expect(result.attachments.isEmpty)
        #expect(result.failures.map(\.fileName) == ["blob.bin"])
        #expect(store.pendingEnvelopes().isEmpty)
    }

    /// #431-C, the bar's own worked case: one corrupt PDF and one good image
    /// yields the image AND one named failure.
    ///
    /// The corrupt PDF is only a failure because #431 taught
    /// `PendingAttachment.file(at:)` to check for `%PDF-`. Before that it
    /// staged happily into a chip that could never be sent (a raw PDF has no
    /// wire representation and "Extract text" had nothing to rasterize) — a
    /// different way for the same file to go quietly nowhere.
    @Test func drainReportsACorruptPDFAndKeepsTheGoodImage() throws {
        let store = makeStore()
        let drainer = ShareInboxDrainer(store: store)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 12, height: 12))
        }
        let jpeg = try #require(image.jpegData(compressionQuality: 0.9))
        let env = envelope(items: [
            .file(blobFileName: "0-report.pdf", fileName: "report.pdf"),
            .file(blobFileName: "1-photo.jpg", fileName: "photo.jpg"),
        ])
        try store.write(env, blobs: [
            "0-report.pdf": Data("this is not a pdf at all".utf8),
            "1-photo.jpg": jpeg,
        ])

        let result = try #require(drainer.drain())
        #expect(result.attachments.count == 1)
        #expect(result.attachments.first?.kind == .image)
        #expect(result.failures.count == 1)
        let failure = try #require(result.failures.first)
        #expect(failure.fileName == "report.pdf")
        #expect(failure.message == ShareRefusal.couldNotStage(fileName: "report.pdf"),
                "\(failure.message)")
        #expect(store.pendingEnvelopes().isEmpty)
    }

    /// #431-C, the over-cap arm — and it is not hypothetical after 431-B: an
    /// envelope written by a PRE-431 extension can be sitting in the inbox
    /// when the fixed build first launches, carrying exactly the payload the
    /// old sheet accepted and the app refuses. The failure names the cap.
    @Test func drainReportsAnOverCapTextFileWithItsCap() throws {
        let store = makeStore()
        let drainer = ShareInboxDrainer(store: store)
        let oversized = Data(count: PendingAttachment.maxFileSize + 1)
        let env = envelope(items: [.file(blobFileName: "0-notes.md", fileName: "notes.md")])
        try store.write(env, blobs: ["0-notes.md": oversized])

        let result = try #require(drainer.drain())
        #expect(result.attachments.isEmpty)
        let failure = try #require(result.failures.first)
        #expect(failure.fileName == "notes.md")
        #expect(failure.message.contains(StageableTypeCatalog.maxVerbatimLabel), "\(failure.message)")
        #expect(failure.message.contains("notes.md"), "\(failure.message)")
    }

    // MARK: - #431-C: the failures reach the user

    @MainActor
    private final class InertClient: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .disconnected
        var currentConversation: Conversation?

        func connect() async {}
        func disconnect() async {}

        func send(message: String, attachments: [PendingAttachment], clientMessageID: UUID) async -> Message {
            Message(sender: .hermes, content: "unused", status: .delivered)
        }

        func sendStreaming(message: String, attachments: [PendingAttachment], clientMessageID: UUID) -> AsyncStream<StreamingUpdate> {
            AsyncStream { $0.finish() }
        }

        func loadConversation() async -> Conversation {
            currentConversation ?? Conversation(title: "Talaria")
        }

        func clearConversation() async throws -> Conversation {
            Conversation(title: "Talaria")
        }
    }

    private func makeChatStore() -> ChatStore {
        let suiteName = "share-drain-failures-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return ChatStore(
            hermesClient: InertClient(),
            persistence: UserDefaultsAppPersistenceStore(defaults: defaults))
    }

    /// #431-C — a share with NOTHING to seed still says what happened. The
    /// store's seed guard used to return before any failure could be recorded,
    /// so this is the ordering that matters, not just the field.
    @Test func aFailuresOnlyShareStillSurfacesOnTheStore() {
        let store = makeChatStore()
        let failure = ShareItemFailure(
            fileName: "notes.md",
            message: ShareRefusal.overTypeCap(
                fileName: "notes.md", byteCount: 400_000, capLabel: "350 KB"))

        store.seedComposerFromShare(text: "", attachments: [], failures: [failure])

        #expect(store.pendingShareSeed == nil, "there was nothing to seed")
        #expect(store.shareStagingFailureMessage == failure.message)
    }

    /// One line per failed item, and a dismiss clears them — the #190B shape.
    @Test func failureMessagesJoinPerItemAndDismissClearsThem() {
        let store = makeChatStore()
        let failures = [
            ShareItemFailure(fileName: "a.md", message: ShareRefusal.couldNotStage(fileName: "a.md")),
            ShareItemFailure(fileName: "b.pdf", message: ShareRefusal.couldNotStage(fileName: "b.pdf")),
        ]

        store.seedComposerFromShare(text: "note", attachments: [], failures: failures)
        let message = store.shareStagingFailureMessage
        let lineCount = message?.split(separator: "\n").count ?? 0
        #expect(lineCount == 2, "one line per failed item; got \(lineCount)")
        #expect(message?.contains("a.md") == true)
        #expect(message?.contains("b.pdf") == true)

        store.dismissShareStagingFailures()
        #expect(store.shareStagingFailureMessage == nil)
    }

    /// A later clean share must not leave the previous share's banner up.
    @Test func aCleanShareClearsAStaleFailureBanner() {
        let store = makeChatStore()
        store.seedComposerFromShare(
            text: "", attachments: [],
            failures: [ShareItemFailure(fileName: "a.md",
                                        message: ShareRefusal.couldNotStage(fileName: "a.md"))])
        #expect(store.shareStagingFailureMessage != nil)

        store.seedComposerFromShare(text: "all good", attachments: [])
        #expect(store.shareStagingFailureMessage == nil)
    }
}
