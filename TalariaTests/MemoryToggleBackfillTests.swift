import Foundation
import Testing
@testable import Talaria

/// #422 (bar 422-B): the memory master switch and the resumable launch backfill.
///
/// Owen's 09-02 ruling is two claims, not one: OFF stops **retrieval AND
/// indexing**, and the index is **KEPT** until Forget everything. This suite
/// owns the indexing half — the retrieval half is pinned in lane M3, where the
/// retrieval call exists to be stopped. Nothing here deletes a row, and that is
/// the point: a toggle that erased the index would make "off" unrecoverable.
@Suite("422-B toggle + backfill")
@MainActor
struct MemoryToggleBackfillTests {

    // MARK: - Fixtures

    private func conversation(_ messages: [Message], id: UUID = UUID()) -> Conversation {
        Conversation(id: id, title: "t", messages: messages)
    }

    private func userTurn(_ text: String = "My dentist is Dr. Patel.") -> Message {
        Message(sender: .user, content: text)
    }

    // MARK: - The persisted key

    /// A blob written by any build before this lane carries no `memoryEnabled`
    /// key. Decoding it to `false` would silently switch memory off for every
    /// existing install — the migration hazard `autoConnectOnLaunch`'s
    /// `decodeIfPresent ?? true` exists to avoid, mirrored here on purpose.
    @Test func memoryEnabledDefaultsToTrueForBlobsThatPredateIt() throws {
        let legacy = try JSONDecoder().decode(UserSettings.self, from: Data("{}".utf8))
        #expect(legacy.memoryEnabled, "an absent key must decode to the documented default `true`")

        var settings = UserSettings()
        settings.memoryEnabled = false
        let round = try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(settings))
        #expect(round.memoryEnabled == false, "the user's OFF must survive a relaunch")
    }

    /// The cursor is a resume point, so a legacy blob must read as "nothing
    /// backfilled yet" — never as a position that skips the user's history.
    @Test func memoryBackfillCursorDefaultsToZeroForBlobsThatPredateIt() throws {
        let legacy = try JSONDecoder().decode(UserSettings.self, from: Data("{}".utf8))
        #expect(legacy.memoryBackfillCursor == 0)

        var settings = UserSettings()
        settings.memoryBackfillCursor = 7
        let round = try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(settings))
        #expect(round.memoryBackfillCursor == 7, "a resume point that does not persist cannot resume")
    }

    // MARK: - The toggle stops indexing

    @Test func indexingWritesNothingWhileTheToggleIsOff() throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        MemoryIndexer(store: store, isEnabled: { false })
            .index(conversation([userTurn()]))
        #expect(store.indexCount() == 0, "a turn taken while memory is off must not be remembered")
    }

    @Test func backfillWritesNothingWhileTheToggleIsOff() throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let indexer = MemoryIndexer(store: store, isEnabled: { false })
        var cursor = 0
        indexer.backfill([conversation([userTurn()]), conversation([userTurn("My dog is Biscuit.")])],
                         cursor: &cursor)
        #expect(store.indexCount() == 0, "the backfill is indexing too — the same switch stops it")
        #expect(cursor == 0, "a refused backfill must not advance the resume point past unread history")
    }

    /// The toggle is a RUNTIME switch, not a construction-time one. The indexer
    /// is built once on the launch path and lives for the process, so a closure
    /// read at `init` would leave a mid-session flip inert until the next cold
    /// start — the user turns memory off, keeps typing, and every turn is still
    /// remembered.
    @Test func theToggleIsReadOnEveryCallNotAtConstruction() throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        var enabled = false
        let indexer = MemoryIndexer(store: store, isEnabled: { enabled })

        indexer.index(conversation([userTurn()]))
        #expect(store.indexCount() == 0, "off at the time of the turn means nothing is written")

        enabled = true
        indexer.index(conversation([userTurn()]))
        #expect(store.indexCount() > 0, "the very same indexer must honour a flip back ON")
    }

    /// The KEPT half of Owen's ruling. Switching memory off is not an erasure —
    /// Forget everything is the only eraser — so rows written while it was on
    /// must still be there afterwards, and must come back into use on a flip
    /// back ON without the user having to re-say anything.
    @Test func switchingTheToggleOffKeepsWhatWasAlreadyIndexed() throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        var enabled = true
        let indexer = MemoryIndexer(store: store, isEnabled: { enabled })

        indexer.index(conversation([userTurn()]))
        let banked = store.indexCount()
        #expect(banked > 0)

        enabled = false
        indexer.index(conversation([userTurn("My dog is Biscuit.")]))
        #expect(store.indexCount() == banked, "off must neither add rows nor remove them")
    }

    // MARK: - The resumable backfill

    private func backfillCorpus(_ count: Int) -> [Conversation] {
        (0 ..< count).map { i in
            conversation([userTurn("Session \(i): my dentist is Dr. Patel. My dog is Biscuit.")])
        }
    }

    /// The launch backfill walks stored sessions one at a time and can be cut
    /// off at any point — the user leaves the app, or the OS suspends it. The
    /// cursor is what makes that survivable: a resumed pass must land on the
    /// same index a single uninterrupted pass would have, with no row counted
    /// twice (upsert idempotence, bar 422-A, does that half).
    @Test func aBackfillKilledPartWayResumesToTheSameIndex() throws {
        let corpus = backfillCorpus(5)

        let oneShot = try #require(MemoryStore.make(inMemoryOnly: true))
        var oneShotCursor = 0
        MemoryIndexer(store: oneShot)
            .backfill(corpus, cursor: &oneShotCursor)
        #expect(oneShotCursor == corpus.count, "an unbudgeted pass must consume the whole corpus")
        #expect(oneShot.indexCount() > 0)

        // …and now the same corpus, killed after 2 conversations and resumed.
        let resumed = try #require(MemoryStore.make(inMemoryOnly: true))
        let indexer = MemoryIndexer(store: resumed)
        var cursor = 0
        indexer.backfill(corpus, cursor: &cursor, budget: 2)
        #expect(cursor == 2, "the budget must stop the pass exactly where it says")
        let afterKill = resumed.indexCount()
        #expect(afterKill > 0, "a partial pass must have done real work")
        #expect(afterKill < oneShot.indexCount(), "…and must not have finished the corpus")

        indexer.backfill(corpus, cursor: &cursor)
        #expect(cursor == corpus.count)
        #expect(resumed.indexCount() == oneShot.indexCount(),
                "a resumed backfill must land on exactly the index a single pass would have built")
    }

    /// Re-running a completed backfill over the same corpus is what a second
    /// launch does when the cursor is already at the end — and what a stale
    /// cursor makes it do over history it has seen. Neither may duplicate.
    @Test func replayingAFinishedBackfillFromZeroAddsNothing() throws {
        let corpus = backfillCorpus(3)
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let indexer = MemoryIndexer(store: store)

        var cursor = 0
        indexer.backfill(corpus, cursor: &cursor)
        let first = store.indexCount()

        var replay = 0
        indexer.backfill(corpus, cursor: &replay)
        #expect(store.indexCount() == first, "a replayed backfill must be a no-op, not a duplicate")
    }

    // MARK: - The empty-vector repair

    // MARK: - What a vectorless row claims about itself

}
