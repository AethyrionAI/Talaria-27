import Foundation
import Testing
import UIKit
@testable import Talaria

/// #123 — app-side drain: SharedInbox envelopes become composer-ready
/// content. Text-ish payloads (note, URL, shared text) join in share order;
/// file blobs convert through the EXISTING `PendingAttachment.stageFile(at:)`
/// staging path (caps, MIME detection, image downscale, thumbnails) so the
/// share pipeline can never accept what the picker pipeline would refuse.
/// Tolerant: an unconvertible item produces a visible refusal, and a
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

    // #440: a rejected envelope must produce a visible result even when no
    // valid item survives. Removing the scan-failure handoff breaks these rows.
    @Test func corruptEnvelopeProducesFailureOnlyDrainOnce() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.rootURL) }
        let dir = store.rootURL.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not JSON".utf8).write(to: dir.appendingPathComponent("envelope.json"))
        let drainer = ShareInboxDrainer(store: store)

        let result = try #require(drainer.drain())
        #expect(result.attachments.isEmpty)
        #expect(result.text.isEmpty)
        #expect(result.failures.count == 1)
        #expect(result.failures.first?.message.contains("couldn’t be read") == true)
        #expect(drainer.drain() == nil)
    }

    @Test func rejectedEnvelopeDoesNotHideAValidShare() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.rootURL) }
        let good = envelope(note: "keep this note", items: [.text("keep this text")])
        try store.write(good, blobs: [:])
        let bad = store.rootURL.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: bad, withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: bad.appendingPathComponent("envelope.json"))

        let result = try #require(ShareInboxDrainer(store: store).drain())
        #expect(result.text == "keep this note\nkeep this text")
        #expect(result.failures.count == 1)
        #expect(result.envelopeCount == 2)
    }

    // #439: assert the same staging decision used by the actual picker,
    // including rejection before I/O when the composer is full.
    @Test func pickerReportsRefusedFilesAndPreservesAcceptedBytes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cases: [(String, Data, String)] = [
            ("large.md", Data(count: 350 * 1024 + 1), "350 KB"),
            ("large.pdf", Data(count: 10 * 1024 * 1024 + 1), "10 MB"),
            ("fake.pdf", Data("not a PDF".utf8), "isn’t a PDF"),
            ("bad.jpg", Data("not an image".utf8), "couldn’t"),
            ("clip.mov", Data([1]), "isn’t a file type"),
        ]
        for (name, bytes, reason) in cases {
            let url = root.appendingPathComponent(name)
            try bytes.write(to: url)
            switch ChatScreen.stagePickedAttachment(.file(url), existingCount: 0) {
            case .staged:
                Issue.record("Refused file staged: \(name)")
            case .refused(let failure):
                #expect(failure.fileName == name)
                #expect(failure.message.contains(reason))
            }
        }
        let url = root.appendingPathComponent("good.md")
        try Data("kept".utf8).write(to: url)
        switch ChatScreen.stagePickedAttachment(.file(url), existingCount: 0) {
        case .staged(let attachment):
            #expect(attachment.data == Data("kept".utf8))
            if let path = attachment.localStoragePath { try? FileManager.default.removeItem(atPath: path) }
        case .refused: Issue.record("Valid text was refused")
        }
    }

    @Test func pickerReportsMissingFileAndFullComposer() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("missing.md")
        for count in [0, PendingAttachment.maxAttachmentsPerMessage] {
            switch ChatScreen.stagePickedAttachment(.file(missing), existingCount: count) {
            case .staged: Issue.record("Missing file staged")
            case .refused(let failure):
                #expect(failure.message.contains(count == 0 ? "couldn’t be read" : "Remove an attachment"))
            }
        }
    }

    @Test func pickerAcceptsAnImageBelowTheCountLimitAndRefusesItAtTheLimit() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 12, height: 12))
        }
        switch ChatScreen.stagePickedAttachment(.image(image), existingCount: PendingAttachment.maxAttachmentsPerMessage - 1) {
        case .staged(let attachment):
            #expect(attachment.kind == .image)
            #expect(!attachment.data.isEmpty)
            if let path = attachment.localStoragePath { try? FileManager.default.removeItem(atPath: path) }
        case .refused: Issue.record("Valid image was refused below the count limit")
        }
        switch ChatScreen.stagePickedAttachment(.image(image), existingCount: PendingAttachment.maxAttachmentsPerMessage) {
        case .staged: Issue.record("Image exceeded the count limit")
        case .refused(let failure): #expect(failure.message.contains("Remove an attachment"))
        }
    }

    @Test func incompleteAndOversizeEnvelopesReachTheFailureBanner() throws {
        for oversize in [false, true] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let inbox = SharedInboxStore(rootURL: root, maxEnvelopeBytes: 1000, staleIncompleteGrace: 0)
            let dir = root.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if oversize {
                let env = envelope(items: [.text("too large")])
                try inbox.write(env, blobs: [:])
                try FileManager.default.removeItem(at: dir)
                try Data(count: 1001).write(to: root.appendingPathComponent(env.id.uuidString).appendingPathComponent("extra.bin"))
            }
            let result = try #require(ShareInboxDrainer(store: inbox).drain())
            let chat = makeChatStore()
            chat.seedComposerFromShare(text: result.text, attachments: result.attachments, failures: result.failures)
            #expect(chat.shareStagingFailures.count == 1)
            #expect(chat.shareStagingFailureMessage?.contains(oversize ? "size limit" : "didn’t finish") == true)
            #expect(chat.consumeShareSeed() == nil)
        }
    }

    @Test func pickerFailureReachesBannerWithoutChangingComposerSeed() {
        let store = makeChatStore()
        store.seedComposerFromShare(text: "keep my draft", attachments: [])
        store.reportAttachmentStagingFailure(ShareItemFailure(fileName: "bad.pdf", message: "bad.pdf refused"))
        #expect(store.shareStagingFailureMessage == "bad.pdf refused")
        #expect(store.consumeShareSeed()?.text == "keep my draft")
        store.dismissShareStagingFailures()
        #expect(store.shareStagingFailureMessage == nil)
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
        #expect(store.pendingEnvelopes().envelopes.isEmpty)
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
        #expect(store.pendingEnvelopes().envelopes.isEmpty)
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
        #expect(store.pendingEnvelopes().envelopes.isEmpty)
    }

    /// #431-C, the bar's own worked case: one corrupt PDF and one good image
    /// yields the image AND one named failure.
    ///
    /// The corrupt PDF is only a failure because #431 taught
    /// `PendingAttachment.stageFile(at:)` to check for `%PDF-`. Before that it
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
        // #431 fix round 1: this said `couldNotStage` — "Talaria couldn't read
        // the file" — which is not what happened. The file read fine and is
        // not a PDF, and the sentence now says that.
        #expect(failure.message == ShareRefusal.notAPDF(fileName: "report.pdf"),
                "\(failure.message)")
        #expect(store.pendingEnvelopes().envelopes.isEmpty)
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

    // MARK: - #431-C: the banner is not outranked by the state it serves

    /// **The finding this row exists for.** The share-failure banner used to be
    /// the third arm of ONE `if / else if` ladder in `ChatScreen`, behind the
    /// standalone-unavailable explanation. `drainShareInbox` runs ahead of the
    /// pairing-gated work precisely because sharing is a free-tier surface, and
    /// "no host, brain unavailable" is what makes that explanation non-nil — so
    /// the configuration 431-C exists to protect was the one configuration that
    /// suppressed its own banner, after which the next clean share cleared the
    /// failures the user never saw.
    @Test func theShareFailureSurvivesTheHostlessState() {
        let banners = ChatScreen.BannerStack.resolve(
            standalone: "Apple Intelligence is off",
            sessionOpenFailure: nil,
            shareFailure: "“notes.md” is 400 KB; Talaria accepts up to 350 KB for this type")

        #expect(banners.contains(.standaloneUnavailable("Apple Intelligence is off")),
                "the hostless explanation must still show: \(banners)")
        #expect(banners.contains(where: {
            if case .shareStagingFailure = $0 { return true } else { return false }
        }), "the share failure was suppressed by the very state it serves: \(banners)")
    }

    /// The same stacking against #190B's failed session open — the other
    /// persistent state that outranked it.
    @Test func theShareFailureStacksWithAFailedSessionOpen() {
        let failure = ChatStore.SessionOpenFailure(sessionID: "s-1", message: "Couldn’t open that conversation")
        let banners = ChatScreen.BannerStack.resolve(
            standalone: nil,
            sessionOpenFailure: failure,
            shareFailure: "“clip.mov” isn’t a file type Talaria can accept")

        #expect(banners.contains(.sessionOpenFailure(failure)), "\(banners)")
        #expect(banners.contains(.shareStagingFailure("“clip.mov” isn’t a file type Talaria can accept")),
                "\(banners)")
        #expect(banners.count == 2, "\(banners)")
    }

    /// …and the two PERSISTENT state banners stay mutually exclusive: only one
    /// app state is true at a time, and stacking them would be a different
    /// (wrong) change. Nothing showing resolves to nothing — the routing and
    /// connection notices below the stack depend on that.
    @Test func theTwoPersistentStateBannersStayMutuallyExclusive() {
        let banners = ChatScreen.BannerStack.resolve(
            standalone: "Apple Intelligence is off",
            sessionOpenFailure: ChatStore.SessionOpenFailure(sessionID: "s-1", message: "nope"),
            shareFailure: nil)
        #expect(banners == [.standaloneUnavailable("Apple Intelligence is off")], "\(banners)")

        #expect(ChatScreen.BannerStack.resolve(
            standalone: nil, sessionOpenFailure: nil, shareFailure: nil).isEmpty)
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
