import Foundation
import Testing
@testable import Talaria

/// The two persisted memory keys, without a settings blob — and the seam that
/// makes a MID-RUN toggle testable.
///
/// File-scope and un-isolated on purpose: it is read and written from the
/// runner's own plain synchronous callbacks.
private final class Knobs {
    var enabled = true
    var cursor = 0
    /// Every value `writeCursor` was handed, in order. A test needs what the
    /// runner PERSISTED, not merely where it ended up: a run that walked four
    /// sessions and stamped four cursors has burned the user's history even if
    /// the final number looks unremarkable.
    private(set) var written: [Int] = []
    func write(_ value: Int) {
        cursor = value
        written.append(value)
    }

    /// The INDEXER's read of the same switch, counted.
    ///
    /// Counting it is how a test flips the toggle strictly BETWEEN
    /// conversations: the indexer reads the switch twice per conversation
    /// (`backfill`, then `index`), so disabling after the second read lands the
    /// flip in the gap where a user's tap actually lands — after one
    /// conversation is fully indexed and before the next is looked at. The
    /// current call returns the value it had BEFORE the flip, so the
    /// conversation in flight is not half-processed.
    var disableAfterIndexerReads: Int?
    private(set) var indexerReads = 0

    func indexerEnabled() -> Bool {
        let current = enabled
        indexerReads += 1
        if let n = disableAfterIndexerReads, indexerReads >= n { enabled = false }
        return current
    }
}

/// #422 (bar 422-B): the launch backfill's cursor arithmetic.
///
/// This logic lived inside an `AppContainer` closure until a review found ways it
/// was quietly wrong — it advanced the cursor past history the toggle had refused
/// to index, and it walked an order that could shift under the cursor. Neither was
/// visible from outside, and neither had a test. That is the whole reason this is a
/// unit: every one of those is an assertion below.
@Suite("422-B backfill runner")
@MainActor
struct MemoryBackfillRunnerTests {

    // MARK: - Fixtures

    /// Dict-backed `LocalSessionStoring`, the `LocalSessionHistoryTests` shape.
    ///
    /// `createdAt` is settable per session because the ORDER is under test — the
    /// real store derives it from a message timestamp, which a fixture cannot
    /// vary finely enough to pin a tie-break. `sessionSummaries()` hands back
    /// most-recent-first, exactly as the real store does, so a runner that
    /// trusted that order fails here rather than in production.
    @MainActor
    private final class FakeSessionStore: LocalSessionStoring {
        private var sessions: [UUID: Conversation] = [:]
        private var createdAt: [UUID: Date] = [:]
        /// Ids whose row exists but whose transcript reads back nil — the real
        /// store's decode-failure path.
        var unreadableIDs: Set<UUID> = []
        /// Fires with the running transcript-read count, so a test can flip the
        /// toggle in the middle of a single conversation's turn.
        var onRead: ((Int) -> Void)?
        private(set) var readCount = 0
        private(set) var summaryOrder: [UUID] = []

        func add(_ conversation: Conversation, createdAt when: Date) {
            sessions[conversation.id] = conversation
            createdAt[conversation.id] = when
        }

        func upsertSession(_ conversation: Conversation) { sessions[conversation.id] = conversation }

        func sessionSummaries() -> [LocalSessionSummary] {
            let summaries = sessions.values
                .sorted { (createdAt[$0.id] ?? .distantPast) > (createdAt[$1.id] ?? .distantPast) }
                .map { convo in
                    LocalSessionSummary(
                        id: convo.id, title: convo.title, preview: nil,
                        messageCount: convo.messages.count,
                        createdAt: createdAt[convo.id] ?? .distantPast,
                        lastActivity: convo.lastActivity)
                }
            summaryOrder = summaries.map(\.id)
            return summaries
        }

        func conversation(withID id: UUID) -> Conversation? {
            readCount += 1
            onRead?(readCount)
            guard !unreadableIDs.contains(id) else { return nil }
            return sessions[id]
        }

        func hasSession(withID id: UUID) -> Bool { sessions[id] != nil }
        func recordRemoteSessionStubs(_ infos: [HermesSessionInfo]) {}
        func remoteSessionStubs() -> [HermesSessionInfo] { [] }
    }

    private func memoryStore() throws -> MemoryStore {
        try #require(MemoryStore.make(inMemoryOnly: true))
    }

    /// `count` single-turn sessions, created one minute apart, returned
    /// oldest-first.
    @discardableResult
    private func seed(_ sessions: FakeSessionStore, count: Int) -> [UUID] {
        (0 ..< count).map { i in
            let conversation = Conversation(
                id: UUID(), title: "s\(i)",
                messages: [Message(sender: .user, content: "Session \(i): my dentist is Dr. Patel.")])
            sessions.add(conversation, createdAt: Date(timeIntervalSince1970: 1_000 + Double(i) * 60))
            return conversation.id
        }
    }

    private func makeRunner(_ sessions: FakeSessionStore,
                            _ indexer: MemoryIndexer,
                            _ knobs: Knobs) -> MemoryBackfillRunner {
        MemoryBackfillRunner(
            sessions: sessions, indexer: indexer,
            isEnabled: { knobs.enabled },
            readCursor: { knobs.cursor },
            writeCursor: { knobs.write($0) })
    }

    /// A runner whose indexer honours the SAME switch the runner does — the
    /// production wiring, where both closures read one settings key.
    private func makeRunner(_ sessions: FakeSessionStore,
                            store: MemoryStore,
                            _ knobs: Knobs) -> MemoryBackfillRunner {
        makeRunner(sessions,
                   MemoryIndexer(store: store, isEnabled: { knobs.indexerEnabled() }),
                   knobs)
    }

    // MARK: - (a) the toggle stops the walk WITHOUT burning the cursor

    /// **The bug this unit was extracted to fix.** The container's loop advanced
    /// and PERSISTED the cursor for every session in its window whether or not
    /// the indexer had accepted it. A user who switched memory off part-way
    /// through the first backfill therefore had the REST of their history marked
    /// done forever: switching back on resumed past it, indexed nothing, and
    /// left no way to tell from the outside.
    ///
    /// The switch flips after the first cursor write — the walk is between
    /// conversations, which is where a real toggle lands.
    @Test func aToggleFlippedOffMidRunStopsWithoutAdvancingPastUnreadHistory() async throws {
        let memory = try memoryStore()
        let sessions = FakeSessionStore()
        seed(sessions, count: 4)
        let knobs = Knobs()
        // Two indexer reads per conversation, so this flips the switch after the
        // FIRST conversation is fully indexed and before the second is looked at.
        knobs.disableAfterIndexerReads = 2

        await makeRunner(sessions, store: memory, knobs).run()

        let afterFlip = memory.indexCount()
        #expect(afterFlip > 0, "the first conversation must genuinely have been indexed")
        #expect(knobs.cursor == 1,
                "the cursor read \(knobs.cursor), marking \(4 - knobs.cursor) unindexed session(s) as done forever")
        #expect(knobs.written == [1],
                "only conversations that were actually indexed may be persisted, got \(knobs.written)")
        #expect(sessions.readCount == 1,
                "the toggle must be re-read BEFORE the next transcript is loaded — \(sessions.readCount) were read")

        // …and the user turns memory back on. The skipped history must still be
        // reachable: the run resumes from 1 and finishes the corpus.
        let resumeKnobs = Knobs()
        resumeKnobs.cursor = knobs.cursor
        await makeRunner(sessions, store: memory, resumeKnobs).run()
        #expect(resumeKnobs.cursor == 4, "the resumed run must finish the corpus")

        let oneShot = try memoryStore()
        await makeRunner(sessions, store: oneShot, Knobs()).run()
        #expect(memory.indexCount() == oneShot.indexCount(),
                "a stopped-then-resumed backfill must land on exactly the index one clean pass builds")
        #expect(memory.indexCount() > afterFlip, "the resume must have indexed what the flip skipped")
    }

    /// The other half of the same protection: the switch flips WHILE the first
    /// conversation is being fetched, so the indexer refuses a conversation the
    /// runner had already committed to. The cursor must not move for work that
    /// did not happen.
    @Test func aConversationTheIndexerRefusesDoesNotAdvanceTheCursor() async throws {
        let memory = try memoryStore()
        let sessions = FakeSessionStore()
        seed(sessions, count: 3)
        let knobs = Knobs()
        sessions.onRead = { _ in knobs.enabled = false }

        await makeRunner(sessions, store: memory, knobs).run()

        #expect(memory.indexCount() == 0, "the refusal must actually have stopped the indexing")
        #expect(knobs.cursor == 0, "a refused conversation must leave the resume point alone")
        #expect(knobs.written.isEmpty, "nothing was indexed, so nothing may be persisted")
    }

    /// Memory off before the run starts: nothing walks and nothing is persisted.
    @Test func aRunThatStartsDisabledDoesNothingAtAll() async throws {
        let memory = try memoryStore()
        let sessions = FakeSessionStore()
        seed(sessions, count: 3)
        let knobs = Knobs()
        knobs.enabled = false

        let runner = makeRunner(sessions, store: memory, knobs)
        await runner.run()

        #expect(memory.indexCount() == 0)
        #expect(knobs.written.isEmpty, "a refused run must not touch the user's resume point")
    }

    // MARK: - (b) the order the cursor indexes into

    /// `sessionSummaries()` is most-recent-first, which is right for a drawer and
    /// wrong for a cursor: a session created since the last pass would land at
    /// index 0 and shift every unread session behind the cursor. Oldest-first
    /// makes a new session APPEND.
    ///
    /// The `id` tie-break is what makes the sort TOTAL. Two sessions can share a
    /// `createdAt` and Swift's `sort(by:)` is not stable, so without it a tied
    /// group can come back in either order and the cursor would point at
    /// different sessions on different launches — history skipped, silently.
    @Test func theWalkIsOldestFirstWithATotalOrder() async throws {
        let memory = try memoryStore()
        let sessions = FakeSessionStore()
        let tied = Date(timeIntervalSince1970: 5_000)
        var distinct: [UUID] = []
        var tiedIDs: [UUID] = []
        for i in 0 ..< 6 {
            let conversation = Conversation(
                id: UUID(), title: "t\(i)",
                messages: [Message(sender: .user, content: "turn \(i)")])
            if i < 3 {
                sessions.add(conversation, createdAt: Date(timeIntervalSince1970: 1_000 + Double(i)))
                distinct.append(conversation.id)
            } else {
                sessions.add(conversation, createdAt: tied)
                tiedIDs.append(conversation.id)
            }
        }

        let knobs = Knobs()
        let runner = makeRunner(sessions, store: memory, knobs)
        let order = runner.orderedSessionIDsForTesting()

        #expect(order != sessions.summaryOrder,
                "the fixture must hand back a different order, or this pins nothing")
        #expect(Array(order.prefix(3)) == distinct, "distinct createdAt values must walk oldest-first")
        #expect(order == runner.orderedSessionIDsForTesting(),
                "the order must be reproducible across launches")
        #expect(Array(order.suffix(3)) == tiedIDs.sorted { $0.uuidString < $1.uuidString },
                "sessions sharing a createdAt must order by id, or the walk is not reproducible")
        #expect(Set(order) == Set(distinct + tiedIDs), "every session must be walked exactly once")

        await runner.run()
        #expect(knobs.cursor == 6)
    }

    /// A summary whose transcript no longer reads back must be STEPPED OVER, not
    /// parked on: the walk advances, so the pass cannot loop forever on one bad
    /// row, and the sessions behind it still get indexed.
    @Test func aSessionWhoseTranscriptIsUnreadableIsSteppedOver() async throws {
        let memory = try memoryStore()
        let sessions = FakeSessionStore()
        let ids = seed(sessions, count: 3)
        sessions.unreadableIDs = [ids[1]]
        let knobs = Knobs()

        await makeRunner(sessions, store: memory, knobs).run()

        #expect(knobs.cursor == 3, "the walk must clear a missing transcript, not park on it")
        #expect(memory.indexCount() > 0, "the readable sessions must still have been indexed")
    }

    // MARK: - what the walk COSTS

    /// Every `writeCursor` re-encodes the whole `UserSettings` blob and
    /// invalidates its observers, so writing once per conversation put that cost
    /// on a loop. The cursor is now persisted every 10 conversations plus a flush
    /// at the end — and the exact sequence is the pin, because "fewer writes" is
    /// satisfied by a runner that writes once and loses 24 conversations of
    /// progress on a kill.
    @Test func theCursorIsPersistedInBatchesNotPerConversation() async throws {
        let memory = try memoryStore()
        let sessions = FakeSessionStore()
        seed(sessions, count: 25)
        let knobs = Knobs()

        await makeRunner(sessions, store: memory, knobs).run()

        #expect(knobs.written == [10, 20, 25],
                "expected two full batches then a closing flush, got \(knobs.written)")
        #expect(knobs.cursor == 25)
    }

    /// The flush is what makes batching safe. A walk cut short must still
    /// persist the conversations it DID index, or the next launch re-walks work
    /// the user already paid for — costly, though never duplicating (bar 422-A).
    @Test func aWalkCutShortStillPersistsTheProgressItMade() async throws {
        let memory = try memoryStore()
        let sessions = FakeSessionStore()
        seed(sessions, count: 25)
        let knobs = Knobs()
        // Two indexer reads per conversation: stop after the third.
        knobs.disableAfterIndexerReads = 6

        await makeRunner(sessions, store: memory, knobs).run()

        #expect(knobs.cursor == 3, "three conversations were indexed")
        #expect(knobs.written == [3],
                "an exit below the batch size must still flush, got \(knobs.written)")
    }

    /// A sim-side cost reading for the launch backfill, printed rather than
    /// asserted: a threshold here would be a flake on a shared box, and the
    /// number belongs in the report where its runtime can be stated with it
    /// (#398-A — a rate without the build it was measured on is ambiguous).
    /// The corpus is the real 422-R turn set, so the text lengths are the ones
    /// the chunker will actually meet.
    @Test func backfillTimingProbe() async throws {
        let corpus = try Self.corpusTurns()
        let memory = try memoryStore()
        let sessions = FakeSessionStore()

        let conversationCount = 50
        for i in 0 ..< conversationCount {
            let a = corpus[(i * 2) % corpus.count]
            let b = corpus[(i * 2 + 1) % corpus.count]
            let conversation = Conversation(id: UUID(), title: "probe \(i)", messages: [
                Message(sender: .user, content: a),
                Message(sender: .hermes, content: "Noted."),
                Message(sender: .user, content: b),
            ])
            sessions.add(conversation, createdAt: Date(timeIntervalSince1970: 1_000 + Double(i)))
        }

        let knobs = Knobs()
        let runner = makeRunner(sessions, MemoryIndexer(store: memory), knobs)

        let clock = ContinuousClock()
        let start = clock.now
        await runner.run()
        let ms = Double((clock.now - start) / .milliseconds(1))

        print("422-B backfill: \(conversationCount) conversations / \(memory.indexCount()) rows "
              + "in \(String(format: "%.0f", ms)) ms on "
              + ProcessInfo.processInfo.operatingSystemVersionString)

        #expect(knobs.cursor == conversationCount, "the probe must have walked the whole corpus")
        #expect(memory.indexCount() >= conversationCount, "…and indexed it")
    }

    /// The 422-R corpus's turn texts, read from the repo.
    private static func corpusTurns() throws -> [String] {
        struct Corpus: Decodable { struct Turn: Decodable { let text: String }; let turns: [Turn] }
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TalariaTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("planning/reports/2026-09-02-422-retrieval-corpus.json")
        let data = try #require(try? Data(contentsOf: url),
                                "cannot read the 422-R corpus — this probe did not run")
        let texts = try JSONDecoder().decode(Corpus.self, from: data).turns.map(\.text)
        #expect(texts.count >= 100, "the probe needs 100 turns, the corpus has \(texts.count)")
        return texts
    }

    // MARK: - (c) the repair pass runs ONCE per run

    // MARK: - (d) a cursor that outran its corpus

    /// A stored cursor can exceed the session count — a blob outliving the store
    /// it counted. Clamping is the whole fix, and its safety is worth stating:
    /// re-walking history costs WORK, never duplicate rows, because upsert keys
    /// on `messageID × chunkIndex` (bar 422-A). The dangerous direction is the
    /// other one — a cursor left too HIGH skips history silently — which is why
    /// the clamp is to `count` and why a refused conversation does not advance.
    @Test func aStoredCursorLargerThanTheCorpusIsClamped() async throws {
        let memory = try memoryStore()
        let sessions = FakeSessionStore()
        seed(sessions, count: 2)
        let knobs = Knobs()
        knobs.cursor = 99

        let runner = makeRunner(sessions, store: memory, knobs)
        await runner.run()

        #expect(knobs.cursor == 2, "a cursor past the end must land ON the end, not stay past it")
        #expect(knobs.written.contains(2),
                "the clamp must be PERSISTED — an unpersisted one is re-read on every future launch")
        #expect(memory.indexCount() == 0,
                "a clamped cursor sits at the end, so there is no history left to walk")
    }

    /// The mirror case: a negative cursor must not index below zero, and must
    /// simply start from the beginning.
    @Test func aNegativeStoredCursorStartsFromTheBeginning() async throws {
        let memory = try memoryStore()
        let sessions = FakeSessionStore()
        seed(sessions, count: 2)
        let knobs = Knobs()
        knobs.cursor = -5

        await makeRunner(sessions, store: memory, knobs).run()

        #expect(knobs.cursor == 2)
        #expect(memory.indexCount() > 0, "a negative cursor must not skip the corpus")
    }

    // MARK: - Forget everything's other half (fix round 1, Important item 2)
    //
    // Owen's ruling: Forget everything is the ONLY eraser, and retention is
    // never. Both halves of that are about THIS unit, because erasing the rows
    // does not erase the promise the cursor makes. A forget performed while the
    // backfill is unfinished leaves a cursor pointing into the middle of the
    // user's history; the next `run()` walks the rest of it back in, days
    // later, with nothing on screen to explain where the memories came from.

    /// A forget with a STALE cursor: the next run must index nothing.
    @Test func forgetParksTheCursorAtTheCorpusEndSoTheNextRunIndexesNothing() async throws {
        let memory = try memoryStore()
        let sessions = FakeSessionStore()
        seed(sessions, count: 6)
        let knobs = Knobs()
        // The shape a real forget lands in: a first launch got two sessions in
        // before the user erased everything.
        knobs.cursor = 2

        makeRunner(sessions, store: memory, knobs).cancelAndParkCursorAtCorpusEnd()
        #expect(knobs.cursor == 6, "parked at the corpus END, never reset to 0")
        #expect(knobs.written == [6], "and PERSISTED — an unparked cursor is re-read next launch")

        // The next launch builds a FRESH runner (a new process would), which is
        // the only thing standing between the user and their erased history.
        await makeRunner(sessions, store: memory, knobs).run()

        #expect(memory.indexCount() == 0, """
            the next backfill walked \(sessions.readCount) forgotten session(s) back into the \
            store — Forget everything is the only eraser, so nothing may re-index itself
            """)
        #expect(sessions.readCount == 0, "no transcript should even have been read")
    }

    /// A forget MID-RUN: the walk stops at the next conversation seam, and no
    /// rows appear after it.
    ///
    /// The forget is fired from `onRead` — the runner is on the MainActor and
    /// yields between conversations, so this is exactly where a user's tap
    /// lands: after one transcript has been read, before the next.
    @Test func forgetMidRunStopsTheWalkAndNoRowsAppearAfterIt() async throws {
        let memory = try memoryStore()
        let sessions = FakeSessionStore()
        seed(sessions, count: 6)
        let knobs = Knobs()
        let runner = makeRunner(sessions, store: memory, knobs)

        var forgotten = false
        var countBeforeForget = 0
        sessions.onRead = { reads in
            // On the SECOND transcript read: the first conversation is fully
            // indexed by now, so the erase has real rows to destroy and the
            // "nothing comes back" assertion is about something.
            guard reads == 2, !forgotten else { return }
            forgotten = true
            countBeforeForget = memory.indexCount()
            // Production's order, from `AppContainer.forgetLocalMemory`:
            // park + refuse first, erase second.
            runner.cancelAndParkCursorAtCorpusEnd()
            memory.forgetEverything()
        }

        await runner.run()

        #expect(forgotten, "precondition: the forget really did fire mid-walk")
        #expect(countBeforeForget > 0,
                "precondition: a conversation was genuinely indexed before the erase")
        #expect(memory.indexCount() == 0, """
            \(memory.indexCount()) row(s) appeared AFTER the forget — the in-flight walk kept \
            indexing into the store the user had just emptied
            """)
        #expect(sessions.readCount == 2,
                "the walk stopped at the conversation the forget landed on, and read no further")
        #expect(knobs.written == [6], """
            the cancelled walk flushed its own smaller cursor over the park (\(knobs.written)) — \
            which hands the next launch a licence to re-index the erased history
            """)
        #expect(knobs.cursor == 6)
    }

    /// A cancelled runner refuses to start at all — the launch task may not
    /// have reached `run()` when the forget landed.
    @Test func aCancelledRunnerNeverStarts() async throws {
        let memory = try memoryStore()
        let sessions = FakeSessionStore()
        seed(sessions, count: 3)
        let knobs = Knobs()
        let runner = makeRunner(sessions, store: memory, knobs)

        runner.cancelAndParkCursorAtCorpusEnd()
        await runner.run()

        #expect(memory.indexCount() == 0)
        #expect(sessions.readCount == 0)
        #expect(runner.isCancelled)
    }
}
