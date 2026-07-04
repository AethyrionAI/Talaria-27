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
        case id, clientMessageID, sender, content, timestamp, jobID, status, attachments, toolActivities
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
        // Persisted with the message (#10) so the tool timeline survives the
        // conversation cache; absent in pre-#10 caches.
        toolActivities = try container.decodeIfPresent([ToolActivity].self, forKey: .toolActivities) ?? []
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
        if !toolActivities.isEmpty {
            try container.encode(toolActivities, forKey: .toolActivities)
        }
    }
}


// MARK: - Agent-generated files (#21 Tier 1)

extension MessageAttachment {
    /// Reconstructs a shareable file attachment from an agent `write_file` tool
    /// call. The agent writes files to its own host working dir and the Sessions
    /// API never delivers them to the phone — but the SSE `tool.started` event
    /// carries the bytes inline (`args.content`), so the client rebuilds the file
    /// locally and stages it for the share sheet. Text content only (Tier 1).
    /// Returns nil if the content can't be staged to disk.
    static func agentFile(remotePath: String, content: String) -> MessageAttachment? {
        let lastComponent = (remotePath as NSString).lastPathComponent
        let fileName = lastComponent.isEmpty ? "agent_output.txt" : lastComponent
        guard let data = content.data(using: .utf8),
              let storedPath = stageAgentFile(data: data, preferredFileName: fileName)
        else { return nil }
        return MessageAttachment(
            kind: "file",
            fileName: fileName,
            mimeType: inferredMimeType(forFileName: fileName),
            thumbnailBase64: nil,
            localStoragePath: storedPath
        )
    }

    /// Stages bytes into the same `App Support/Talaria/Attachments` directory the
    /// composer uses for outgoing attachments. Self-contained (mirrors the
    /// `PendingAttachment` staging) so the existing upload path stays untouched.
    private static func stageAgentFile(data: Data, preferredFileName: String) -> String? {
        let fileManager = FileManager.default
        guard let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let attachmentDirectory = baseDirectory
            .appendingPathComponent("Talaria", isDirectory: true)
            .appendingPathComponent("Attachments", isDirectory: true)
        do {
            try fileManager.createDirectory(at: attachmentDirectory, withIntermediateDirectories: true, attributes: nil)
            let sanitized = sanitizeAgentFileName(preferredFileName)
            let destination = attachmentDirectory.appendingPathComponent("\(UUID().uuidString)-\(sanitized)")
            try data.write(to: destination, options: .atomic)
            return destination.path
        } catch {
            return nil
        }
    }

    private static func sanitizeAgentFileName(_ fileName: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = fileName.components(separatedBy: invalidCharacters).joined(separator: "_")
        return cleaned.isEmpty ? "agent_output.txt" : cleaned
    }

    /// Best-effort MIME inference from the file extension. Defaults to
    /// `text/plain` because Tier 1 only reconstructs text the agent streamed as
    /// a string in `args.content`.
    static func inferredMimeType(forFileName fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        let map: [String: String] = [
            "txt": "text/plain", "log": "text/plain", "text": "text/plain",
            "md": "text/markdown", "markdown": "text/markdown",
            "json": "application/json", "csv": "text/csv", "tsv": "text/tab-separated-values",
            "yml": "application/yaml", "yaml": "application/yaml", "toml": "text/plain",
            "xml": "text/xml", "html": "text/html", "htm": "text/html", "css": "text/css",
            "swift": "text/x-swift", "py": "text/x-python", "js": "text/javascript",
            "ts": "text/typescript", "sh": "text/x-shellscript", "rtf": "text/rtf",
            "ini": "text/plain", "conf": "text/plain", "env": "text/plain",
        ]
        return map[ext] ?? "text/plain"
    }
}
