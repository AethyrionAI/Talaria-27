import Foundation

/// P1 offline compose outbox (OPEN_ITEMS #90): turns composed while the
/// Sessions API is unreachable persist here — the SensorUploadService outbox
/// pattern applied to chat — and drain in order once the API is reachable
/// again. The transcript row keeps `.queued` status while its turn waits.
///
/// Text-only by design (v1): attachments have no durable wire-ready form to
/// park here, so attachment sends still fail honestly when offline.
struct ComposeOutboxState: Codable, Hashable, Sendable {
    struct PendingTurn: Codable, Hashable, Sendable, Identifiable {
        /// The transcript row's `clientMessageID`, so the drain can replace
        /// the queued bubble with the live re-send.
        let id: UUID
        let text: String
        let composedAt: Date
    }

    var pendingTurns: [PendingTurn] = []

    var isEmpty: Bool { pendingTurns.isEmpty }

    mutating func enqueue(id: UUID, text: String, composedAt: Date = .now) {
        guard !pendingTurns.contains(where: { $0.id == id }) else { return }
        pendingTurns.append(PendingTurn(id: id, text: text, composedAt: composedAt))
    }

    mutating func remove(id: UUID) {
        pendingTurns.removeAll { $0.id == id }
    }
}
