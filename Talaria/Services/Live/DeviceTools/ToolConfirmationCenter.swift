import Foundation
import os

/// The shared confirm gate for side-effecting device tools (#29). Authority
/// rule (shipped for AlarmKit in #16, now generalized): the model can NEVER
/// silently mutate the phone — every write is staged, rendered as a card in
/// the chat transcript, and executed only after the user's explicit approve.
///
/// FM tool calls are async, so the gate is plain structured concurrency: the
/// tool suspends on an awaited continuation until the user decides. Deny
/// resolves the tool with a "user declined" result the model reacts to
/// conversationally. The gate defaults CLOSED: if the app dies with a
/// confirmation pending, the continuation dies with the process and nothing
/// was ever created.
@MainActor
@Observable
final class ToolConfirmationCenter {

    /// One editable line on the confirmation card. `key` is what the tool
    /// reads back after approval, so edited values are what get created.
    struct Field: Identifiable {
        let id = UUID()
        let key: String
        let label: String
        var value: String
    }

    struct PendingConfirmation: Identifiable {
        let id = UUID()
        /// e.g. "Create this reminder?"
        let title: String
        /// One-line consequence statement, e.g. "It will ring through Silent mode."
        let detail: String?
        var fields: [Field]
    }

    enum Decision: Sendable {
        case approved([String: String])
        case declined
    }

    private static let logger = Logger(subsystem: "org.aethyrion.talaria", category: "ToolConfirmationCenter")

    /// The card the chat transcript renders. Nil when the gate is idle.
    private(set) var pending: PendingConfirmation?
    private var continuation: CheckedContinuation<Decision, Never>?

    /// Stages a confirmation and suspends the calling tool until the user
    /// decides. Tools run serially per session; if a second request somehow
    /// arrives while one is pending, it auto-declines (defensive — the gate
    /// never queues silently).
    func requestConfirmation(title: String, detail: String? = nil, fields: [Field]) async -> Decision {
        guard continuation == nil else {
            Self.logger.warning("confirmation requested while another is pending — auto-declining the new one")
            return .declined
        }
        return await withCheckedContinuation { newContinuation in
            continuation = newContinuation
            pending = PendingConfirmation(title: title, detail: detail, fields: fields)
            Self.logger.notice("confirmation staged: \(title, privacy: .public)")
        }
    }

    /// Approve with the card's CURRENT field values (edits included).
    func approve() {
        guard let pending else { return }
        let values = Dictionary(uniqueKeysWithValues: pending.fields.map { ($0.key, $0.value) })
        resolve(.approved(values))
    }

    func decline() {
        resolve(.declined)
    }

    /// The card's editable-field write path (bound from the UI).
    func updateField(id: Field.ID, value: String) {
        guard var pending, let index = pending.fields.firstIndex(where: { $0.id == id }) else { return }
        pending.fields[index].value = value
        self.pending = pending
    }

    private func resolve(_ decision: Decision) {
        pending = nil
        let waiting = continuation
        continuation = nil
        waiting?.resume(returning: decision)
        if case .declined = decision {
            Self.logger.notice("confirmation declined")
        } else {
            Self.logger.notice("confirmation approved")
        }
    }
}
