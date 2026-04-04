import Foundation

/// A lightweight attachment reference stored on a message for display.
struct MessageAttachment: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let kind: String       // "image" or "file"
    let fileName: String
    let mimeType: String
    /// Base64-encoded thumbnail (for images) — small enough to cache/persist.
    let thumbnailBase64: String?
    let localStoragePath: String?

    init(
        id: UUID = UUID(),
        kind: String,
        fileName: String,
        mimeType: String,
        thumbnailBase64: String? = nil,
        localStoragePath: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.fileName = fileName
        self.mimeType = mimeType
        self.thumbnailBase64 = thumbnailBase64
        self.localStoragePath = localStoragePath
    }

    init(from pending: PendingAttachment) {
        self.id = pending.id
        self.kind = pending.kind.rawValue
        self.fileName = pending.fileName
        self.mimeType = pending.mimeType
        self.thumbnailBase64 = pending.thumbnailBase64
        self.localStoragePath = pending.localStoragePath
    }
}

struct Message: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let clientMessageID: UUID?
    let sender: MessageSender
    var content: String
    let timestamp: Date
    let jobID: UUID?
    var status: MessageStatus
    var toolActivity: String?
    var toolActivities: [ToolActivity]
    var codeDiff: CodeDiff?
    var isStreaming: Bool
    var voiceSessionDuration: TimeInterval?
    var attachments: [MessageAttachment]

    /// Whether this message was transcribed from a voice session.
    var isVoiceTranscript: Bool {
        sender == .voiceUser || sender == .voiceHermes
    }

    init(
        id: UUID = UUID(),
        clientMessageID: UUID? = nil,
        sender: MessageSender,
        content: String,
        timestamp: Date = .now,
        jobID: UUID? = nil,
        status: MessageStatus = .sent,
        toolActivity: String? = nil,
        toolActivities: [ToolActivity] = [],
        codeDiff: CodeDiff? = nil,
        isStreaming: Bool = false,
        voiceSessionDuration: TimeInterval? = nil,
        attachments: [MessageAttachment] = []
    ) {
        self.id = id
        self.clientMessageID = clientMessageID
        self.sender = sender
        self.content = content
        self.timestamp = timestamp
        self.jobID = jobID
        self.status = status
        self.toolActivity = toolActivity
        self.toolActivities = toolActivities
        self.codeDiff = codeDiff
        self.isStreaming = isStreaming
        self.voiceSessionDuration = voiceSessionDuration
        self.attachments = attachments
    }

    enum CodingKeys: String, CodingKey {
        case id, clientMessageID, sender, content, timestamp, jobID, status, attachments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        clientMessageID = try container.decodeIfPresent(UUID.self, forKey: .clientMessageID)
        sender = try container.decode(MessageSender.self, forKey: .sender)
        content = try container.decode(String.self, forKey: .content)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        jobID = try container.decodeIfPresent(UUID.self, forKey: .jobID)
        status = try container.decode(MessageStatus.self, forKey: .status)
        attachments = try container.decodeIfPresent([MessageAttachment].self, forKey: .attachments) ?? []
        toolActivity = nil
        toolActivities = []
        codeDiff = nil
        isStreaming = false
        voiceSessionDuration = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(clientMessageID, forKey: .clientMessageID)
        try container.encode(sender, forKey: .sender)
        try container.encode(content, forKey: .content)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(jobID, forKey: .jobID)
        try container.encode(status, forKey: .status)
        if !attachments.isEmpty {
            try container.encode(attachments, forKey: .attachments)
        }
    }
}
