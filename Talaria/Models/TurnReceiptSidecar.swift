import CryptoKit
import Foundation

/// #330 — the durable, per-thread record of TURN RECEIPTS: the four fields the
/// status card's SESSION block is computed from (`usage`, `turnDuration`,
/// `servingModel`, `isContextPriming`).
///
/// **Why this exists.** `ChatStore.openSession` REPLACES the message array
/// with the server transcript, and that transcript is produced by
/// `SessionsHermesClient.mapStoredMessage`, which can supply none of those
/// four fields — the stored transcript carries no usage of any kind (probe
/// 2026-07-16: per-row `token_count` is always null) and no wall-clock
/// duration by any path. So both of `ChatStore.sessionUsageTotals`' inputs go
/// to zero in ONE event and the whole SESSION block — `Metered turns`,
/// session `Input`/`Output`, `Model time`, `Priming (N hops)` and
/// **`Est. cost`** — silently vanishes off a thread that was displaying it a
/// second earlier. Measured and reproduced in units by #330's measurement
/// lane (`SessionTotalsAfterReopenTests`), then confirmed on device
/// 2026-08-25.
///
/// **The non-merge at `openSession` STAYS.** It is deliberate and pinned
/// (`AgentFileChipPersistenceTests`, and the comment at the call site):
/// merging would re-append every departing row as "unconfirmed" (#248), hand
/// the arriving thread the departing conversation's UUID (P1/#90) and keep the
/// departing title (#4.8). This is a second, thread-keyed copy of the receipt
/// FIELDS — never a second copy of the transcript.
///
/// **The design is `AgentAttachmentSidecar`'s, deliberately.** Same key (the
/// SERVER SESSION ID, the handle `openSession(_:)` is called with — the only
/// identity that survives both the single-slot conversation cache and a
/// conversation-UUID churn), same two-tier match (exact message id, then a
/// content fingerprint claimed with dequeue counting), same LRU trim, same
/// replace-not-merge record policy. Two lanes that solve the same problem the
/// same way should not invent two shapes of it.
///
/// **The one thing it adds: a THIRD match tier, for the priming row.** The
/// context-transplant notice is the app's only carrier of `isContextPriming`,
/// and its content is the label `[Context transplanted into a fresh session —
/// N tokens]` — which the server transcript cannot reproduce verbatim, because
/// the host never stored the notice at all. What the host DOES store is the
/// primer PAYLOAD, as a `user` row, which `mapStoredMessage` now recognises by
/// `ContextTransplanter.transplantMarker` and re-maps into a token-less
/// notice. So the arriving notice's content differs from the recorded one by
/// exactly the token count, both tiers above miss it, and the priming tier
/// claims it by flag — restoring both the usage AND the label that names it.
struct TurnReceiptSidecar: Codable, Hashable, Sendable {

    /// One row's receipt, addressable across a server refetch.
    struct Row: Codable, Hashable, Sendable {
        /// The message id AS LAST SEEN. Upgraded to the server-derived id
        /// (#237) the first time a restore runs, which is what makes tier 1
        /// the steady state.
        var messageID: UUID
        /// `fingerprint(sender:content:)` of that row — the tier-2 key.
        var contentKey: String
        var usage: TokenUsage?
        var turnDuration: TimeInterval?
        var servingModel: String?
        var isContextPriming: Bool = false
        /// The row's own text, recorded ONLY for priming rows. The notice
        /// label carries the hop's token count in its prose, and the
        /// re-mapped primer arrives without it; everything else is restored
        /// from the transcript verbatim and must never be second-guessed by
        /// a cached copy.
        var primingLabel: String?
    }

    /// One thread's rows, keyed by the SERVER SESSION ID.
    struct ThreadRecord: Codable, Hashable, Sendable {
        var sessionID: String
        var rows: [Row]
    }

    /// Most-recently-touched FIRST. Order is the trim policy, not decoration.
    var threads: [ThreadRecord] = []

    /// Bounds — deliberately NOT the chip sidecar's 40 × 60. A chip exists
    /// only where the agent wrote a file; a receipt exists on EVERY metered
    /// turn, so the row dimension has to be generous and the thread dimension
    /// pays for it. 20 × 200 is comfortably above real use (a 200-turn thread,
    /// 20 distinct threads) and bounded against the UserDefaults slot this
    /// rides in beside the conversation cache.
    static let maxThreads = 20
    static let maxRowsPerThread = 200

    func rows(forSessionID sessionID: String) -> [Row] {
        threads.first(where: { $0.sessionID == sessionID })?.rows ?? []
    }

    /// Files `rows` under `sessionID` and moves that thread to the front.
    /// Replaces rather than merges, for `AgentAttachmentSidecar.record`'s
    /// reason: `rows(from:)` is computed over the whole transcript, so it is
    /// already the complete answer for that thread, and merging would
    /// resurrect receipts a truncation (#78) removed.
    mutating func record(sessionID: String, rows: [Row]) {
        threads.removeAll { $0.sessionID == sessionID }
        threads.insert(ThreadRecord(sessionID: sessionID, rows: Array(rows.suffix(Self.maxRowsPerThread))), at: 0)
        if threads.count > Self.maxThreads {
            threads.removeSubrange(Self.maxThreads...)
        }
    }

    /// The rows worth persisting: every row carrying at least one of the four
    /// fields the SESSION block is computed from.
    ///
    /// Deliberately NOT filtered by sender. The priming notice is `.system`,
    /// and a sender filter here is the exact shape of blindness #330 spent a
    /// measurement lane on (`/history`'s `.user`/`.hermes` guard cannot see
    /// the one row that carries `isContextPriming`).
    static func rows(from messages: [Message]) -> [Row] {
        messages.compactMap { message in
            guard message.usage != nil
                    || message.turnDuration != nil
                    || message.servingModel != nil
                    || message.isContextPriming
            else { return nil }
            return Row(
                messageID: message.id,
                contentKey: fingerprint(sender: message.sender, content: message.content),
                usage: message.usage,
                turnDuration: message.turnDuration,
                servingModel: message.servingModel,
                isContextPriming: message.isContextPriming,
                primingLabel: message.isContextPriming ? message.content : nil
            )
        }
    }

    /// Puts recorded receipts back onto a freshly fetched transcript.
    ///
    /// Three passes — id, then content, then the priming flag — so a
    /// duplicate-content row can never steal a record that a later row owns
    /// by identity, and the priming tier only ever sees what the first two
    /// could not place. Each record is claimed at most once (dequeue
    /// counting, #185/#248).
    ///
    /// **Restoration is fill-only.** A field the arriving row already carries
    /// is left alone: the transcript is server truth and a cached receipt is a
    /// second-hand copy of it. Today the arriving rows carry none of these
    /// four, so every claim fills; if a future host ever starts returning
    /// per-row usage, this sidecar quietly stops being the authority on it
    /// rather than overwriting it.
    static func replaying(_ rows: [Row], onto messages: [Message]) -> [Message] {
        guard !rows.isEmpty else { return messages }
        var result = messages
        var unclaimed = rows
        var claimedBy: [Int: Row] = [:]

        for index in result.indices {
            guard let match = unclaimed.firstIndex(where: { $0.messageID == result[index].id }) else { continue }
            claimedBy[index] = unclaimed.remove(at: match)
        }
        for index in result.indices where claimedBy[index] == nil {
            let key = fingerprint(sender: result[index].sender, content: result[index].content)
            guard let match = unclaimed.firstIndex(where: { $0.contentKey == key }) else { continue }
            claimedBy[index] = unclaimed.remove(at: match)
        }
        // The priming tier. Both sides are already ordered by the transcript,
        // so the Nth unplaced priming record belongs to the Nth unclaimed
        // priming row — the same in-order pairing the content tier's dequeue
        // counting relies on, applied to a key that is a flag rather than a
        // digest.
        for index in result.indices
        where claimedBy[index] == nil && result[index].isContextPriming {
            guard let match = unclaimed.firstIndex(where: { $0.isContextPriming }) else { break }
            claimedBy[index] = unclaimed.remove(at: match)
        }

        for (index, row) in claimedBy {
            if result[index].usage == nil { result[index].usage = row.usage }
            if result[index].turnDuration == nil { result[index].turnDuration = row.turnDuration }
            if result[index].servingModel == nil { result[index].servingModel = row.servingModel }
            if row.isContextPriming {
                result[index].isContextPriming = true
                // The label carries the hop's token count in prose. Restored
                // only onto a row the mapper already knows is a priming
                // notice, so a stale label can never be printed over a real
                // message.
                if let label = row.primingLabel, !label.isEmpty, result[index].sender == .system {
                    result[index].content = label
                }
            }
        }
        return result
    }

    /// The tier-2 key. Sender is in the digest so a user row echoing the
    /// reply's text can never claim an assistant row's receipt; content is
    /// trimmed because `SessionsHermesClient.mapStoredMessage` trims what it
    /// maps. Its own domain string, so a digest can never be compared across
    /// sidecars.
    static func fingerprint(sender: MessageSender, content: String) -> String {
        let normalized = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let digest = SHA256.hash(data: Data("talaria-receipt:\(sender.rawValue):\(normalized)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
