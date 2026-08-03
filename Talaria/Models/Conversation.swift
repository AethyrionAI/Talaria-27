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
