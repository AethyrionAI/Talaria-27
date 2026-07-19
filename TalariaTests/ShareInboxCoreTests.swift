import Foundation
import Testing
@testable import Talaria

/// #123 — share-extension inbox core: the envelope the TalariaShare extension
/// serializes into the app-group container and the store the app drains on
/// foreground. The store is the only writer/reader of `SharedInbox/` layout —
/// these tests pin the contract both processes depend on: completeness
/// (envelope.json written last), drain order, dedupe by envelope id,
/// corrupt-skip (tolerant, never crash the drain), and the size cap.
struct ShareInboxCoreTests {

    // MARK: Fixtures

    /// Whole-second reference date — the envelope encodes dates as ISO-8601,
    /// which drops sub-second precision, so fixtures stay round-trip-exact.
    private static let t0 = Date(timeIntervalSince1970: 1_752_000_000)

    private func makeStore(
        maxEnvelopeBytes: Int = SharedInboxStore.defaultMaxEnvelopeBytes,
        staleIncompleteGrace: TimeInterval = 3600
    ) -> SharedInboxStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareInboxCoreTests-\(UUID().uuidString)", isDirectory: true)
        return SharedInboxStore(
            rootURL: root,
            maxEnvelopeBytes: maxEnvelopeBytes,
            staleIncompleteGrace: staleIncompleteGrace
        )
    }

    private func envelope(
        id: UUID = UUID(),
        createdAt: Date = t0,
        note: String = "",
        items: [ShareEnvelope.Item]
    ) -> ShareEnvelope {
        ShareEnvelope(id: id, createdAt: createdAt, note: note, items: items)
    }

    // MARK: Envelope round-trip

    @Test func envelopeRoundTripsThroughJSON() throws {
        let original = envelope(
            note: "look at this",
            items: [
                .webURL("https://example.com/a?b=1"),
                .text("plain shared text"),
                .file(blobFileName: "0-report.pdf", fileName: "report.pdf"),
            ]
        )
        let decoded = try ShareEnvelope.decode(from: ShareEnvelope.encode(original))
        #expect(decoded == original)
    }

    // MARK: Write → drain round-trip

    @Test func writeThenPendingReturnsEnvelopeAndBlobs() throws {
        let store = makeStore()
        let blob = Data("pdf-bytes".utf8)
        let env = envelope(
            note: "note",
            items: [.file(blobFileName: "0-doc.pdf", fileName: "doc.pdf")]
        )
        try store.write(env, blobs: ["0-doc.pdf": blob])

        let pending = store.pendingEnvelopes()
        #expect(pending == [env])
        #expect(store.blobData(named: "0-doc.pdf", envelopeID: env.id) == blob)
    }

    @Test func missingBlobReturnsNil() throws {
        let store = makeStore()
        let env = envelope(items: [.text("hi")])
        try store.write(env, blobs: [:])
        #expect(store.blobData(named: "nope.bin", envelopeID: env.id) == nil)
    }

    // MARK: Drain order

    @Test func pendingSortsByCreatedAtAscending() throws {
        let store = makeStore()
        let first = envelope(createdAt: Self.t0, items: [.text("first")])
        let second = envelope(createdAt: Self.t0.addingTimeInterval(1), items: [.text("second")])
        let third = envelope(createdAt: Self.t0.addingTimeInterval(2), items: [.text("third")])

        // Written out of order — drain order must follow createdAt, not
        // filesystem enumeration order.
        try store.write(third, blobs: [:])
        try store.write(first, blobs: [:])
        try store.write(second, blobs: [:])

        #expect(store.pendingEnvelopes().map(\.id) == [first.id, second.id, third.id])
    }

    // MARK: Dedupe

    @Test func duplicateEnvelopeIDReturnsOnce() throws {
        let store = makeStore()
        let env = envelope(items: [.text("only once")])
        try store.write(env, blobs: [:])

        // Simulate a retried extension write that left the same envelope in a
        // second directory.
        let original = store.rootURL.appendingPathComponent(env.id.uuidString, isDirectory: true)
        let duplicate = store.rootURL.appendingPathComponent("dup-\(env.id.uuidString)", isDirectory: true)
        try FileManager.default.copyItem(at: original, to: duplicate)

        let pending = store.pendingEnvelopes()
        #expect(pending.map(\.id) == [env.id])
        // The duplicate must not resurface on the next drain either.
        #expect(store.pendingEnvelopes().map(\.id) == [env.id])
    }

    // MARK: Corrupt-skip (tolerant drain — house rule)

    @Test func corruptEnvelopeJSONIsSkippedAndCleaned() throws {
        let store = makeStore()
        let good = envelope(items: [.text("survivor")])
        try store.write(good, blobs: [:])

        let corruptDir = store.rootURL.appendingPathComponent("corrupt", isDirectory: true)
        try FileManager.default.createDirectory(at: corruptDir, withIntermediateDirectories: true)
        try Data("not json {".utf8).write(
            to: corruptDir.appendingPathComponent(SharedInboxStore.envelopeFileName))

        #expect(store.pendingEnvelopes().map(\.id) == [good.id])
        // A corrupt envelope can never become valid — it must be cleaned up,
        // not re-hit on every drain.
        #expect(!FileManager.default.fileExists(atPath: corruptDir.path))
    }

    @Test func incompleteFreshDirIsLeftAlone() throws {
        // No envelope.json yet = the extension may be mid-write (blobs land
        // first, envelope.json last). A fresh incomplete dir must survive.
        let store = makeStore()
        let inflight = store.rootURL.appendingPathComponent("inflight", isDirectory: true)
        try FileManager.default.createDirectory(at: inflight, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: inflight.appendingPathComponent("blob.bin"))

        #expect(store.pendingEnvelopes().isEmpty)
        #expect(FileManager.default.fileExists(atPath: inflight.path))
    }

    @Test func incompleteStaleDirIsRemoved() throws {
        // Grace of zero: any incomplete dir counts as an abandoned write.
        let store = makeStore(staleIncompleteGrace: 0)
        let stale = store.rootURL.appendingPathComponent("stale", isDirectory: true)
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: stale.appendingPathComponent("blob.bin"))

        #expect(store.pendingEnvelopes().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: stale.path))
    }

    // MARK: Size cap

    @Test func writeRejectsOverCapPayload() {
        let store = makeStore(maxEnvelopeBytes: 1024)
        let env = envelope(items: [.file(blobFileName: "big.bin", fileName: "big.bin")])
        #expect(throws: SharedInboxError.self) {
            try store.write(env, blobs: ["big.bin": Data(count: 2048)])
        }
        // A refused write must leave nothing behind for the drain to trip on.
        #expect(store.pendingEnvelopes().isEmpty)
        #expect(!FileManager.default.fileExists(
            atPath: store.rootURL.appendingPathComponent(env.id.uuidString).path))
    }

    @Test func oversizeEnvelopeDirIsSkippedOnDrain() throws {
        let store = makeStore(maxEnvelopeBytes: 1024)
        let env = envelope(items: [.text("small when written")])
        try store.write(env, blobs: [:])

        // Something ballooned the directory past the cap after the write —
        // the drain must skip AND clean it, never hand a 20MB+ payload on.
        let envDir = store.rootURL.appendingPathComponent(env.id.uuidString, isDirectory: true)
        try Data(count: 2048).write(to: envDir.appendingPathComponent("planted.bin"))

        #expect(store.pendingEnvelopes().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: envDir.path))
    }

    // MARK: Removal

    @Test func removeDeletesEnvelopeDir() throws {
        let store = makeStore()
        let env = envelope(items: [.text("bye")])
        try store.write(env, blobs: [:])

        store.remove(envelopeID: env.id)

        #expect(store.pendingEnvelopes().isEmpty)
        #expect(!FileManager.default.fileExists(
            atPath: store.rootURL.appendingPathComponent(env.id.uuidString).path))
    }

    // MARK: Blob-name safety

    @Test func blobNamesAreSanitizedAgainstTraversal() throws {
        let store = makeStore()
        let env = envelope(items: [.file(blobFileName: "../evil.txt", fileName: "evil.txt")])
        try store.write(env, blobs: ["../evil.txt": Data("payload".utf8)])

        // The blob must land INSIDE the envelope dir (sanitized), and the
        // sanitized lookup must still find it.
        let escaped = store.rootURL.deletingLastPathComponent()
            .appendingPathComponent("evil.txt")
        #expect(!FileManager.default.fileExists(atPath: escaped.path))
        #expect(store.blobData(named: "../evil.txt", envelopeID: env.id) == Data("payload".utf8))
    }
}
