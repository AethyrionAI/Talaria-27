import Foundation

struct Conversation: Codable, Identifiable, Hashable, Sendable {
    /// Placeholder title for a not-yet-labeled conversation. On-device title
    /// generation (#4.8) only ever fires while the title still equals this,
    /// so a manual `/title` is never overwritten.
    static let defaultTitle = "Hermes"

    let id: UUID
    var title: String
    var messages: [Message]
    var lastActivity: Date
    var latestUsage: TokenUsage?

    /// #349: the CTX gauge's numerator. `promptTokens` IS context occupancy
    /// only for a turn that made no tool calls — on agentic turns the wire's
    /// `input_tokens` is the SUM of billed input across every internal model
    /// call (wire-measured 2026-08-18: 46,953 on a thread whose true depth
    /// was ~23.5K; 287K-on-a-128K-window in the production filing), so the
    /// gauge renders ABSENT rather than a wrong number (#25). Computed from
    /// the last usage-carrying hermes message so the reading and the
    /// tool-activity gate come from the SAME turn — no stale carry-forward
    /// (an older toolless reading would UNDERSTATE current depth, which is
    /// the direction that removes the ceiling warning when it matters).
    var contextOccupancyTokens: Int? {
        guard let last = messages.last(where: { $0.sender == .hermes && $0.usage != nil }) else {
            return nil
        }
        return last.toolActivities.isEmpty ? last.usage?.promptTokens : nil
    }
    /// One-line on-device preview generated alongside the title (#4.8).
    /// nil until the first completed exchange has been summarized (and in
    /// pre-#4.8 caches).
    var generatedPreview: String?

    init(
        id: UUID = UUID(),
        title: String,
        messages: [Message] = [],
        lastActivity: Date = .now,
        latestUsage: TokenUsage? = nil,
        generatedPreview: String? = nil
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.lastActivity = lastActivity
        self.latestUsage = latestUsage
        self.generatedPreview = generatedPreview
    }

    var lastMessage: Message? {
        messages.last
    }

    var previewText: String {
        lastMessage?.content ?? "No messages yet"
    }

    /// #237: heal adopted-echo corruption. Pre-fix reconciles unioned whole
    /// transcripts with fresh identities (32 → 128 on the observed thread),
    /// so identity alone cannot find the copies — first occurrence wins for
    /// rows sharing (sender, trimmed content, timestamp), with empty-content
    /// tool-shell rows additionally keyed on their activity labels so two
    /// DIFFERENT shells at one timestamp both survive. A genuinely repeated
    /// user message differs in timestamp and is untouched. Idempotent.
    static func dedupingAdoptedEchoes(_ messages: [Message]) -> [Message] {
        var seen = Set<String>()
        return messages.filter { message in
            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            var key = "\(message.sender)|\(content)|\(message.timestamp.timeIntervalSince1970)"
            if content.isEmpty {
                key += "|\(message.toolActivities.map(\.label).joined(separator: ","))"
            }
            return seen.insert(key).inserted
        }
    }
}
