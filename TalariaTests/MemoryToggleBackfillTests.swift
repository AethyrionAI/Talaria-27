import Foundation
import NaturalLanguage
import Testing
@testable import Talaria

/// Counts how many times the indexer asked for an embedder. The toggle's second
/// claim is a COST claim — "no embedder is constructed" — and a row count cannot
/// see it: with acquisition stubbed to nil, an indexer that built an embedder and
/// then wrote nothing looks identical to one that never built anything.
///
/// File-scope and deliberately un-isolated: it is driven from the indexer's own
/// `makeEmbedder` closure, which is a plain synchronous callback.
private final class EmbedderFactory {
    private(set) var constructions = 0
    private let make: () -> EmbeddingService
    init(_ make: @escaping () -> EmbeddingService) { self.make = make }
    func callAsFunction() -> EmbeddingService {
        constructions += 1
        return make()
    }
}

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

    /// Acquisition that never yields an embedder — rows land with an EMPTY
    /// vector, which is exactly the state the backfill's re-embed pass exists
    /// to repair.
    private func nullEmbedder() -> EmbeddingService { EmbeddingService(acquire: { nil }) }

    /// The runtime's real sentence embedder, acquired over a bounded window
    /// (422-C: the variable is elapsed time, not attempt count — the first call
    /// in a process reliably returns nil and a cold run can stay nil for
    /// several back-to-back calls). Wrapping it in the `acquire:` seam keeps
    /// the re-embed test off that timing entirely once it is held.
    private func realEmbedder(budget: Duration = .seconds(3)) async throws -> NLEmbedding {
        let clock = ContinuousClock()
        let start = clock.now
        repeat {
            if let e = NLEmbedding.sentenceEmbedding(for: .english), e.vector(for: "warm") != nil {
                return e
            }
            try await Task.sleep(for: .milliseconds(50))
        } while clock.now - start < budget
        return try #require(NLEmbedding.sentenceEmbedding(for: .english),
                            "no sentence embedder available to drive the re-embed pass")
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
        MemoryIndexer(store: store, makeEmbedder: nullEmbedder, isEnabled: { false })
            .index(conversation([userTurn()]))
        #expect(store.indexCount() == 0, "a turn taken while memory is off must not be remembered")
    }

    @Test func backfillWritesNothingWhileTheToggleIsOff() throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let indexer = MemoryIndexer(store: store, makeEmbedder: nullEmbedder, isEnabled: { false })
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
        let indexer = MemoryIndexer(store: store, makeEmbedder: nullEmbedder, isEnabled: { enabled })

        indexer.index(conversation([userTurn()]))
        #expect(store.indexCount() == 0, "off at the time of the turn means nothing is written")

        enabled = true
        indexer.index(conversation([userTurn()]))
        #expect(store.indexCount() > 0, "the very same indexer must honour a flip back ON")
    }

    /// The cost half of the ruling. `EmbeddingService.init` makes real
    /// `NLEmbedding` asset lookups; a user who has switched memory off should
    /// not pay for one, and the row count cannot tell whether they did.
    @Test func noEmbedderIsConstructedWhileTheToggleIsOff() throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let factory = EmbedderFactory { EmbeddingService(acquire: { nil }) }
        let indexer = MemoryIndexer(store: store, makeEmbedder: { factory() }, isEnabled: { false })

        indexer.index(conversation([userTurn()]))
        var cursor = 0
        indexer.backfill([conversation([userTurn()])], cursor: &cursor)

        #expect(factory.constructions == 0,
                "memory off must cost nothing — no embedder was needed, \(factory.constructions) were built")
    }

    /// The negative control for the test above: the same factory, the same
    /// calls, the toggle ON. Without it a `makeEmbedder` that is simply never
    /// called — a broken indexer — would satisfy the zero-construction pin.
    @Test func anEmbedderIsConstructedWhenTheToggleIsOn() throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let factory = EmbedderFactory { EmbeddingService(acquire: { nil }) }
        let indexer = MemoryIndexer(store: store, makeEmbedder: { factory() }, isEnabled: { true })

        indexer.index(conversation([userTurn()]))

        #expect(factory.constructions == 1, "indexing a turn must actually reach the embedder")
        #expect(store.indexCount() > 0)
    }

    /// The KEPT half of Owen's ruling. Switching memory off is not an erasure —
    /// Forget everything is the only eraser — so rows written while it was on
    /// must still be there afterwards, and must come back into use on a flip
    /// back ON without the user having to re-say anything.
    @Test func switchingTheToggleOffKeepsWhatWasAlreadyIndexed() throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        var enabled = true
        let indexer = MemoryIndexer(store: store, makeEmbedder: nullEmbedder, isEnabled: { enabled })

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
        MemoryIndexer(store: oneShot, makeEmbedder: nullEmbedder)
            .backfill(corpus, cursor: &oneShotCursor)
        #expect(oneShotCursor == corpus.count, "an unbudgeted pass must consume the whole corpus")
        #expect(oneShot.indexCount() > 0)

        // …and now the same corpus, killed after 2 conversations and resumed.
        let resumed = try #require(MemoryStore.make(inMemoryOnly: true))
        let indexer = MemoryIndexer(store: resumed, makeEmbedder: nullEmbedder)
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
        let indexer = MemoryIndexer(store: store, makeEmbedder: nullEmbedder)

        var cursor = 0
        indexer.backfill(corpus, cursor: &cursor)
        let first = store.indexCount()

        var replay = 0
        indexer.backfill(corpus, cursor: &replay)
        #expect(store.indexCount() == first, "a replayed backfill must be a no-op, not a duplicate")
    }

    // MARK: - The empty-vector repair

    /// The gap the incremental index leaves behind (Task 4): a turn indexed
    /// while the embedder was unavailable keeps its row — the verbatim text IS
    /// the memory — but with an EMPTY vector, and "already indexed" means the
    /// settle seam never looks at it again. Without this pass that row is
    /// lexical-only for the life of the install, which on a phone whose asset
    /// simply had not downloaded yet is a permanent penalty for a transient
    /// condition.
    @Test func backfillReEmbedsRowsStoredWhileTheEmbedderWasUnavailable() async throws {
        let real = try await realEmbedder()
        let store = try #require(MemoryStore.make(inMemoryOnly: true))

        MemoryIndexer(store: store, makeEmbedder: nullEmbedder)
            .index(conversation([userTurn()]))
        let stranded = store.entriesWithEmptyVector(limit: 10)
        #expect(stranded.count == store.indexCount(),
                "every row of this fixture must have landed vectorless, or the repair proves nothing")
        let subject = try #require(stranded.first)
        #expect(store.vectorByteCount(entryID: subject.entryID) == 0)

        var cursor = 0
        MemoryIndexer(store: store, makeEmbedder: { EmbeddingService(acquire: { real }) })
            .backfill([], cursor: &cursor)

        #expect(store.vectorByteCount(entryID: subject.entryID) ?? 0 > 0,
                "a row stranded without a vector must be repaired once an embedder exists")
        #expect(store.entriesWithEmptyVector(limit: 10).isEmpty,
                "the pass must repair every stranded row it was given budget for, not just the first")
    }

    /// The repair must not run away with the launch: it takes a bounded slice
    /// and leaves the rest for the next pass.
    @Test func theReEmbedPassHonoursItsLimit() throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        MemoryIndexer(store: store, makeEmbedder: nullEmbedder)
            .index(conversation([userTurn("My dentist is Dr. Patel."),
                                 userTurn("My dog is called Biscuit."),
                                 userTurn("I park on Oak Street.")]))
        #expect(store.indexCount() >= 3, "the fixture needs more rows than the limit under test")
        #expect(store.entriesWithEmptyVector(limit: 2).count == 2)
    }

    /// A repair pass with no embedder must leave the rows exactly as they are —
    /// never blank an embedderID or drop a row it could not score.
    @Test func theReEmbedPassLeavesRowsAloneWhenNoEmbedderArrives() throws {
        let store = try #require(MemoryStore.make(inMemoryOnly: true))
        let indexer = MemoryIndexer(store: store, makeEmbedder: nullEmbedder)
        indexer.index(conversation([userTurn()]))
        let before = store.indexCount()

        var cursor = 0
        indexer.backfill([], cursor: &cursor)

        #expect(store.indexCount() == before, "a failed repair must not cost the user a memory")
        #expect(store.entriesWithEmptyVector(limit: 10).count == before)
    }
}
