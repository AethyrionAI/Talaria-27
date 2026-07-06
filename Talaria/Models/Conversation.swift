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
}
