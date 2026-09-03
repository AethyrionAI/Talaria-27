import Foundation

/// #422 (bar 422-B): indexes the local sessions the settle seam never saw —
/// everything the user said before memory existed.
///
/// **A unit, not a closure in `AppContainer`.** The cursor arithmetic here has
/// three ways to be quietly wrong — advancing past history the user never had
/// indexed, walking an order that shifts under the cursor, and re-scanning the
/// repair queue once per conversation — and none of them is visible from
/// outside. Living behind `init` seams (`isEnabled`, `readCursor`,
/// `writeCursor`) makes each of them a test rather than a claim; the container's
/// task just constructs one and calls `run()`.
///
/// **Not a BGTask.** #63's discretionary scheduling is exactly wrong for this:
/// the work is cheap, wants to happen soon, and has no deadline the system can
/// help with. One `.utility` task yielding after every conversation is the whole
/// mechanism — it competes with nothing on the launch path and simply stops when
/// the process does.
@MainActor
final class MemoryBackfillRunner {
    private let sessions: any LocalSessionStoring
    private let indexer: MemoryIndexer
    private let isEnabled: () -> Bool
    private let readCursor: () -> Int
    private let writeCursor: (Int) -> Void
    private let repairLimit: Int

    /// How many repair passes this runner has made, and how many rows they
    /// wrote. Observable because "the repair runs once per run" is a claim about
    /// a call that leaves no other trace once the queue is empty.
    private(set) var repairPasses = 0
    private(set) var repairedRows = 0

    init(sessions: any LocalSessionStoring,
         indexer: MemoryIndexer,
         isEnabled: @escaping () -> Bool,
         readCursor: @escaping () -> Int,
         writeCursor: @escaping (Int) -> Void,
         repairLimit: Int = 200) {
        self.sessions = sessions
        self.indexer = indexer
        self.isEnabled = isEnabled
        self.readCursor = readCursor
        self.writeCursor = writeCursor
        self.repairLimit = repairLimit
    }

    /// Walks the stored sessions from the persisted cursor, then repairs
    /// stranded vectors ONCE.
    ///
    /// **The cursor advances only for work that actually happened.** That is the
    /// whole safety property: a cursor is a promise that everything behind it is
    /// indexed, so stamping it for a conversation the indexer refused converts a
    /// paused backfill into permanently skipped history — silently, and with no
    /// way to notice from outside. The toggle is therefore re-read at the top of
    /// every iteration (the user reaching for the switch mid-walk), AND the
    /// indexer's own refusal is honoured through `walked`, because the switch can
    /// flip between the two checks.
    func run() async {
        guard isEnabled() else { return }
        let ordered = orderedSessionIDs()

        // A stored cursor can outrun its corpus — a settings blob outliving the
        // sessions it counted. Clamp, and PERSIST the clamp: an unpersisted
        // repair leaves the bad value to be re-read on every future launch.
        // Clamping is safe in a way worth stating: re-walking history costs
        // WORK, never duplicate rows, because upsert keys on
        // `messageID × chunkIndex` (bar 422-A). The dangerous direction is a
        // cursor left too HIGH, which skips history and says nothing.
        var cursor = min(max(0, readCursor()), ordered.count)
        if cursor != readCursor() { writeCursor(cursor) }

        while cursor < ordered.count {
            guard isEnabled() else { return }
            if let conversation = sessions.conversation(withID: ordered[cursor]) {
                var walked = 0
                indexer.backfill([conversation], cursor: &walked, budget: 1)
                guard walked == 1 else { return }
            }
            // A summary whose transcript no longer reads back is STEPPED OVER:
            // there is nothing to index, and parking on it would spin forever.
            cursor += 1
            writeCursor(cursor)
            // One conversation per hop. The whole point of `budget: 1` is that
            // the main thread is never held for a window of transcripts — this
            // runs at `.utility` behind everything the user can see.
            await Task.yield()
        }

        guard isEnabled() else { return }
        repairPasses += 1
        repairedRows += await indexer.reEmbedStrandedRows(limit: repairLimit)
    }

    /// The walk order, and the cursor's whole meaning.
    ///
    /// `sessionSummaries()` is most-recent-first — right for a drawer, wrong for
    /// a cursor: a session created since the last pass would land at index 0 and
    /// shift every unread session behind the cursor. Oldest-first makes a new
    /// session APPEND instead.
    ///
    /// The `id` tie-break is what makes the sort TOTAL. Two sessions can share a
    /// `createdAt` (the store derives it from a message timestamp) and Swift's
    /// `sort(by:)` is not stable, so without it a tied pair can come back in
    /// either order and the cursor would point at different sessions on
    /// different launches.
    // harness-visible
    func orderedSessionIDsForTesting() -> [UUID] { orderedSessionIDs() }

    private func orderedSessionIDs() -> [UUID] {
        sessions.sessionSummaries()
            .sorted {
                $0.createdAt == $1.createdAt
                    ? $0.id.uuidString < $1.id.uuidString
                    : $0.createdAt < $1.createdAt
            }
            .map(\.id)
    }
}
