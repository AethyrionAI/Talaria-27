import Foundation

/// #422 (bar 422-B): indexes the local sessions the settle seam never saw —
/// everything the user said before memory existed.
///
/// **A unit, not a closure in `AppContainer`.** The cursor arithmetic here has
/// two ways to be quietly wrong — advancing past history the user never had
/// indexed, and walking an order that shifts under the cursor — and neither is
/// visible from outside. Living behind `init` seams (`isEnabled`, `readCursor`,
/// `writeCursor`) makes each of them a test rather than a claim; the container's
/// task just constructs one and calls `run()`.
///
/// **Not a BGTask.** #63's discretionary scheduling is exactly wrong for this:
/// the work is cheap, wants to happen soon, and has no deadline the system can
/// help with. One `.utility` task yielding after every conversation is the whole
/// mechanism, and it simply stops when the process does.
///
/// **It does NOT compete with nothing.** Every step of it — the store reads and
/// the chunking — runs on the MainActor, so it is on the same thread
/// as the UI and the `.utility` priority buys ordering, not parallelism. That is
/// why the unit of work is ONE conversation with a yield after it rather than a
/// window, and why the cursor is written every `cursorWriteStride` conversations
/// instead of every one: each write JSON-encodes the whole `UserSettings` blob
/// and invalidates every observer of it.
@MainActor
final class MemoryBackfillRunner {
    private let sessions: any LocalSessionStoring
    private let indexer: MemoryIndexer
    private let isEnabled: () -> Bool
    private let readCursor: () -> Int
    private let writeCursor: (Int) -> Void

    /// Conversations per persisted cursor. Every write re-encodes the entire
    /// settings blob and invalidates its observers, so writing per conversation
    /// put that cost on a loop. Batching is safe in exactly one direction: a
    /// cursor that lags reality costs a re-walk of at most this many
    /// conversations on the next launch, and a re-walk costs WORK, never
    /// duplicate rows (upsert keys on `messageID × chunkIndex`, bar 422-A). A
    /// cursor that RAN AHEAD would skip history silently, which is why nothing
    /// here ever writes a cursor for work that did not happen.
    private let cursorWriteStride = 10

    init(sessions: any LocalSessionStoring,
         indexer: MemoryIndexer,
         isEnabled: @escaping () -> Bool,
         readCursor: @escaping () -> Int,
         writeCursor: @escaping (Int) -> Void) {
        self.sessions = sessions
        self.indexer = indexer
        self.isEnabled = isEnabled
        self.readCursor = readCursor
        self.writeCursor = writeCursor
    }

    /// Walks the stored sessions from the persisted cursor.
    ///
    /// **The cursor advances only for work that actually happened**, and is
    /// PERSISTED in batches of `cursorWriteStride` plus a flush at every exit.
    /// That is the whole safety property: a cursor is a promise that everything behind it is
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
        // sessions it counted. Clamp, and PERSIST the clamp immediately: an
        // unpersisted repair leaves the bad value to be re-read on every future
        // launch.
        var cursor = min(max(0, readCursor()), ordered.count)
        if cursor != readCursor() { writeCursor(cursor) }

        var unwritten = 0
        func flushCursor() {
            guard unwritten > 0 else { return }
            writeCursor(cursor)
            unwritten = 0
        }

        while cursor < ordered.count {
            guard isEnabled() else { return flushCursor() }
            if let conversation = sessions.conversation(withID: ordered[cursor]) {
                var walked = 0
                indexer.backfill([conversation], cursor: &walked, budget: 1)
                guard walked == 1 else { return flushCursor() }
            }
            // A summary whose transcript no longer reads back is STEPPED OVER:
            // there is nothing to index, and parking on it would spin forever.
            cursor += 1
            unwritten += 1
            if unwritten >= cursorWriteStride { flushCursor() }
            // One conversation per hop. The whole point of `budget: 1` is that
            // the main thread is never held for a window of transcripts.
            await Task.yield()
        }
        // Every early exit above flushes too: progress the user actually paid
        // for must survive, or a paused backfill re-walks it on the next launch.
        flushCursor()
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
