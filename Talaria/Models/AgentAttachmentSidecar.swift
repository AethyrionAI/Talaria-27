import CryptoKit
import Foundation

/// #277 — the durable, per-thread record of AGENT-WRITTEN file chips (#21).
///
/// **Why this exists.** A Tier-1 agent file is a client-side reconstruction:
/// the SSE stream carries `write_file`'s `args.content`, the app stages the
/// bytes and mints a `MessageAttachment`. Nothing about that round-trips —
/// `GET /api/sessions/{id}/messages` stores a tool call as name + preview
/// only, so a resumed thread rebuilds the write_file CARD and can never
/// rebuild the CHIP. `ChatStore.openSession` assigns that server transcript
/// over the local one, and the conversation cache is a single slot that the
/// next thread evicts — so leaving a thread and coming back lost every chip
/// in it, while the bytes sat untouched under Application Support.
///
/// This is the second, thread-keyed copy of just the attachment RECORDS —
/// never the file bytes, which are already on disk and are not duplicated
/// here.
///
/// **The key choice, which is the whole design.** A message's identity is not
/// stable across the boundary this has to cross: while the turn is live the
/// reply carries the CLIENT-minted streaming placeholder id, and after a
/// refetch it carries `SessionsHermesClient.stableMessageID` (#237), derived
/// from the server row. So matching is two-tier, mirroring the precedence
/// `mergeConversationMetadata` and `unconfirmedLocalMessages` (#248) already
/// use:
///
/// 1. **exact message id** — right whenever the identity survived (a reopen
///    inside one lifetime, a local-brain thread, and every reopen AFTER the
///    first, because a restore re-files the record under the server-derived
///    id);
/// 2. **content fingerprint** — a SHA-256 over sender + trimmed content,
///    claimed with dequeue counting so two identical replies map to two
///    distinct records instead of both aliasing the first.
///
/// So the content tier carries exactly one crossing: the first return to a
/// thread after the chip was made. It is a HASH, not the text, so the sidecar
/// never becomes a second copy of the transcript at rest.
///
/// **Deliberately NOT here:** re-deriving a lost chip from a surviving staged
/// file by name. #277 declines that on real-data-only grounds — name-matching
/// would attach the wrong bytes to the wrong turn. Threads whose records
/// predate this sidecar stay without chips, honestly.
struct AgentAttachmentSidecar: Codable, Hashable, Sendable {

    /// One assistant row's chips, addressable across a server refetch.
    struct Row: Codable, Hashable, Sendable {
        /// The message id AS LAST SEEN. Upgraded to the server-derived id the
        /// first time a restore runs, which is what makes tier 1 the steady
        /// state.
        var messageID: UUID
        /// `fingerprint(sender:content:)` of that row — the tier-2 key.
        var contentKey: String
        var attachments: [MessageAttachment]
    }

    /// One thread's rows, keyed by the SERVER SESSION ID — the handle
    /// `ChatStore.openSession(_:)` is called with, and the only identity that
    /// survives both the single-slot cache and a conversation-UUID churn.
    struct ThreadRecord: Codable, Hashable, Sendable {
        var sessionID: String
        var rows: [Row]
    }

    /// Most-recently-touched FIRST. Order is the trim policy, not decoration.
    var threads: [ThreadRecord] = []

    /// Bounds. This rides in UserDefaults beside the conversation cache, so
    /// it is capped rather than left to grow with every thread the user ever
    /// opened. Both limits are generous against real use (a thread with 60
    /// file-writing turns, 40 distinct threads) and cheap to hold.
    static let maxThreads = 40
    static let maxRowsPerThread = 60

    func rows(forSessionID sessionID: String) -> [Row] {
        threads.first(where: { $0.sessionID == sessionID })?.rows ?? []
    }

    /// Files `rows` under `sessionID` and moves that thread to the front.
    /// Replaces rather than merges: `rows(from:)` is computed over the whole
    /// transcript, so it is already the complete answer for that thread, and
    /// merging would resurrect chips a truncation (#78) removed.
    mutating func record(sessionID: String, rows: [Row]) {
        threads.removeAll { $0.sessionID == sessionID }
        threads.insert(ThreadRecord(sessionID: sessionID, rows: Array(rows.suffix(Self.maxRowsPerThread))), at: 0)
        if threads.count > Self.maxThreads {
            threads.removeSubrange(Self.maxThreads...)
        }
    }

    /// The rows worth persisting: assistant rows that carry attachments.
    /// User attachments are deliberately excluded — they are not agent files,
    /// and the compose path owns their durability.
    static func rows(from messages: [Message]) -> [Row] {
        messages.compactMap { message in
            guard isAgentAuthored(message.sender), !message.attachments.isEmpty else { return nil }
            return Row(
                messageID: message.id,
                contentKey: fingerprint(sender: message.sender, content: message.content),
                attachments: message.attachments
            )
        }
    }

    /// Puts recorded chips back onto a freshly fetched transcript.
    ///
    /// Two passes, id before content, so a duplicate-content row can never
    /// steal a record that a later row owns by identity. Each record is
    /// claimed at most once (dequeue counting, #185/#248), and the merge into
    /// a row is idempotent by attachment id — the same rule `.artifactProduced`
    /// and the finish merge use (#258) — so replaying twice cannot double a
    /// chip.
    ///
    /// `anchorOffset` (#262) rides along untouched: the stored anchor stays
    /// raw and honest, and `MessageBubble.transcriptLayout` already clamps at
    /// render time (#265).
    static func replaying(_ rows: [Row], onto messages: [Message]) -> [Message] {
        guard !rows.isEmpty else { return messages }
        var result = messages
        var unclaimed = rows
        var claimedBy: [Int: Row] = [:]

        for index in result.indices where isAgentAuthored(result[index].sender) {
            guard let match = unclaimed.firstIndex(where: { $0.messageID == result[index].id }) else { continue }
            claimedBy[index] = unclaimed.remove(at: match)
        }
        for index in result.indices
        where isAgentAuthored(result[index].sender) && claimedBy[index] == nil {
            let key = fingerprint(sender: result[index].sender, content: result[index].content)
            guard let match = unclaimed.firstIndex(where: { $0.contentKey == key }) else { continue }
            claimedBy[index] = unclaimed.remove(at: match)
        }

        for (index, row) in claimedBy {
            var seen = Set(result[index].attachments.map(\.id))
            for attachment in row.attachments where seen.insert(attachment.id).inserted {
                result[index].attachments.append(attachment)
            }
        }
        return result
    }

    /// The tier-2 key. Sender is in the digest so a user row echoing the
    /// reply's text can never claim an assistant row's chips; content is
    /// trimmed because `SessionsHermesClient.mapStoredMessage` trims what it
    /// maps.
    static func fingerprint(sender: MessageSender, content: String) -> String {
        let normalized = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let digest = SHA256.hash(data: Data("talaria-attach:\(sender.rawValue):\(normalized)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// The rows an agent writes files onto. Local to this type on purpose:
    /// #275's `isUserAuthored` exists because FOUR sites needed one answer;
    /// this question has exactly one asker.
    private static func isAgentAuthored(_ sender: MessageSender) -> Bool {
        sender == .hermes || sender == .voiceHermes
    }
}
